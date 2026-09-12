import Combine
import Foundation

/// A nearby Xiaomi scale discovered via BLE advertisements.
struct DiscoveredScale: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let rssi: Int
    let lastSeen: Date
}

enum ScaleSessionPhase: Equatable, Sendable {
    case idle
    case scanning
    case listening(scaleName: String)
    case measuring
    /// Stabilized weight received; still listening for the impedance / BIA frame.
    case awaitingImpedance
    case ready
    case healthKitWriting
    case healthKitSuccess
    case healthKitFailed(String)
    case bluetoothUnavailable(String)
    case error(String)
}

@MainActor
final class ScaleSessionViewModel: ObservableObject {
    /// How long to keep waiting for a valid impedance frame after weight stabilizes.
    static let impedanceWaitSeconds: TimeInterval = 18

    @Published private(set) var phase: ScaleSessionPhase = .idle
    @Published private(set) var discoveredScales: [DiscoveredScale] = []
    @Published private(set) var selectedScaleID: UUID?
    @Published private(set) var latestMeasurement: ScaleMeasurement?
    @Published private(set) var composition: BodyCompositionResult?
    @Published private(set) var liveHint: String = "Step on the scale when listening."
    @Published private(set) var impedanceMissingReason: String?
    @Published var profile: UserBodyProfile {
        didSet { UserProfileStore.save(profile) }
    }

    private let scanner: ScaleScanning
    private let healthStore: HealthWriting
    private var lastAcceptedSignature: String?
    private var impedanceWaitTask: Task<Void, Never>?

    init(
        scanner: ScaleScanning,
        healthStore: HealthWriting,
        profile: UserBodyProfile = UserProfileStore.load()
    ) {
        self.scanner = scanner
        self.healthStore = healthStore
        self.profile = profile
        self.scanner.delegate = self
    }

    convenience init() {
        self.init(
            scanner: CoreBluetoothScaleScanner(),
            healthStore: HealthKitWriter()
        )
    }

    var healthKitAvailable: Bool { healthStore.isHealthDataAvailable }

    /// True when the latest reading has weight but no usable ohms (socks/shoes or timed out).
    var isWeightOnlyReading: Bool {
        guard let measurement = latestMeasurement else { return false }
        return !measurement.hasImpedance
    }

    func startScanning() {
        cancelImpedanceWait()
        discoveredScales = []
        selectedScaleID = nil
        latestMeasurement = nil
        composition = nil
        impedanceMissingReason = nil
        lastAcceptedSignature = nil
        phase = .scanning
        liveHint = "Looking for MIBFS / Mi Body Composition Scale 2…"
        scanner.startScanning()
    }

    func stop() {
        cancelImpedanceWait()
        scanner.stop()
        switch phase {
        case .listening, .scanning, .measuring, .awaitingImpedance:
            phase = .idle
        default:
            break
        }
    }

    func selectScale(_ scale: DiscoveredScale) {
        cancelImpedanceWait()
        selectedScaleID = scale.id
        scanner.focus(on: scale.id)
        phase = .listening(scaleName: scale.name)
        impedanceMissingReason = nil
        liveHint = "Listening for broadcasts from \(scale.name). Step on barefoot for body composition."
    }

    func saveToHealth() async {
        guard let measurement = latestMeasurement else { return }
        phase = .healthKitWriting
        do {
            try await healthStore.requestAuthorizationIfNeeded()
            try await healthStore.write(
                measurement: measurement,
                composition: composition,
                profile: profile
            )
            phase = .healthKitSuccess
            if measurement.hasImpedance {
                liveHint = "Saved weight, BMI, body fat %, and lean mass to Apple Health."
            } else {
                liveHint = "Saved weight and BMI only. Body fat was not written (no impedance)."
            }
        } catch {
            phase = .healthKitFailed(error.localizedDescription)
        }
    }

    private func accept(_ measurement: ScaleMeasurement) {
        // Never replace a good impedance reading with a later weight-only frame
        // for essentially the same weigh-in (ESPHome clear_impedance defaults false).
        if let existing = latestMeasurement,
           existing.hasImpedance,
           !measurement.hasImpedance,
           abs(existing.weightKg - measurement.weightKg) < 0.2 {
            return
        }

        let signature = String(
            format: "%.2f-%d-%d-%@",
            measurement.weightKg,
            measurement.impedanceOhms ?? -1,
            measurement.biaPending ? 1 : 0,
            measurement.scaleDate?.description ?? "nil"
        )
        if signature == lastAcceptedSignature { return }
        lastAcceptedSignature = signature

        latestMeasurement = measurement

        if let ohms = measurement.impedanceOhms {
            cancelImpedanceWait()
            composition = BodyCompositionCalculator.calculate(
                weightKg: measurement.weightKg,
                impedanceOhms: ohms,
                profile: profile
            )
            impedanceMissingReason = nil
            liveHint = "Stabilized reading with impedance (\(ohms) Ω). Ready to save body fat to Apple Health."
            phase = .ready
            return
        }

        composition = nil
        phase = .awaitingImpedance
        if measurement.biaPending {
            liveHint = "Weight locked. Impedance sweep in progress: stay barefoot on the electrodes."
        } else {
            liveHint = "Weight only so far. Stay barefoot until the scale finishes a second measurement with impedance."
        }
        impedanceMissingReason = nil
        scheduleImpedanceWait()
    }

    private func scheduleImpedanceWait() {
        cancelImpedanceWait()
        let seconds = Self.impedanceWaitSeconds
        impedanceWaitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard case .awaitingImpedance = self.phase else { return }
            guard let measurement = self.latestMeasurement, !measurement.hasImpedance else { return }
            self.phase = .ready
            self.impedanceMissingReason =
                "Impedance missing. Socks, shoes, or stepping off early block body fat. Stand barefoot on the metal electrodes and wait a few seconds after weight stabilizes for the second (BIA) broadcast."
            self.liveHint = self.impedanceMissingReason ?? self.liveHint
        }
    }

    private func cancelImpedanceWait() {
        impedanceWaitTask?.cancel()
        impedanceWaitTask = nil
    }

    private var shouldSurfaceTransientHints: Bool {
        switch phase {
        case .listening, .measuring, .awaitingImpedance:
            return true
        default:
            return false
        }
    }
}

extension ScaleSessionViewModel: ScaleScannerDelegate {
    nonisolated func scaleScanner(_ scanner: ScaleScanning, didUpdateBluetoothState message: String?) {
        Task { @MainActor in
            self.handleBluetoothState(message)
        }
    }

    nonisolated func scaleScanner(_ scanner: ScaleScanning, didDiscover scale: DiscoveredScale) {
        Task { @MainActor in
            self.handleDiscover(scale)
        }
    }

    nonisolated func scaleScanner(_ scanner: ScaleScanning, didDecode measurement: ScaleMeasurement) {
        Task { @MainActor in
            self.handleDecode(measurement)
        }
    }

    nonisolated func scaleScanner(_ scanner: ScaleScanning, transientStatus: String) {
        Task { @MainActor in
            self.handleTransientStatus(transientStatus)
        }
    }

    private func handleBluetoothState(_ message: String?) {
        if let message {
            cancelImpedanceWait()
            phase = .bluetoothUnavailable(message)
        } else if case .bluetoothUnavailable = phase {
            phase = .idle
        }
    }

    private func handleDiscover(_ scale: DiscoveredScale) {
        if let index = discoveredScales.firstIndex(where: { $0.id == scale.id }) {
            discoveredScales[index] = scale
        } else {
            discoveredScales.append(scale)
        }
        discoveredScales.sort { $0.rssi > $1.rssi }
    }

    private func handleDecode(_ measurement: ScaleMeasurement) {
        if case .listening = phase {
            phase = .measuring
        }
        accept(measurement)
    }

    private func handleTransientStatus(_ status: String) {
        if shouldSurfaceTransientHints {
            liveHint = status
        }
    }
}

enum UserProfileStore {
    private static let key = "thescale.userBodyProfile"

    static func load() -> UserBodyProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profile = try? JSONDecoder().decode(UserBodyProfile.self, from: data)
        else {
            return .default
        }
        return profile
    }

    static func save(_ profile: UserBodyProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
