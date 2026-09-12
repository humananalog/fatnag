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
    case ready
    case healthKitWriting
    case healthKitSuccess
    case healthKitFailed(String)
    case bluetoothUnavailable(String)
    case error(String)
}

@MainActor
final class ScaleSessionViewModel: ObservableObject {
    @Published private(set) var phase: ScaleSessionPhase = .idle
    @Published private(set) var discoveredScales: [DiscoveredScale] = []
    @Published private(set) var selectedScaleID: UUID?
    @Published private(set) var latestMeasurement: ScaleMeasurement?
    @Published private(set) var composition: BodyCompositionResult?
    @Published private(set) var liveHint: String = "Step on the scale when listening."
    @Published var profile: UserBodyProfile {
        didSet { UserProfileStore.save(profile) }
    }

    private let scanner: ScaleScanning
    private let healthStore: HealthWriting
    private var lastAcceptedSignature: String?

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

    func startScanning() {
        discoveredScales = []
        selectedScaleID = nil
        latestMeasurement = nil
        composition = nil
        lastAcceptedSignature = nil
        phase = .scanning
        liveHint = "Looking for MIBFS / Mi Body Composition Scale 2…"
        scanner.startScanning()
    }

    func stop() {
        scanner.stop()
        if case .listening = phase {
            phase = .idle
        } else if case .scanning = phase {
            phase = .idle
        }
    }

    func selectScale(_ scale: DiscoveredScale) {
        selectedScaleID = scale.id
        scanner.focus(on: scale.id)
        phase = .listening(scaleName: scale.name)
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
        } catch {
            phase = .healthKitFailed(error.localizedDescription)
        }
    }

    private func accept(_ measurement: ScaleMeasurement) {
        let signature = String(
            format: "%.2f-%d-%@",
            measurement.weightKg,
            measurement.impedanceOhms ?? -1,
            measurement.scaleDate?.description ?? "nil"
        )
        if signature == lastAcceptedSignature { return }
        lastAcceptedSignature = signature

        latestMeasurement = measurement
        if let ohms = measurement.impedanceOhms {
            composition = BodyCompositionCalculator.calculate(
                weightKg: measurement.weightKg,
                impedanceOhms: ohms,
                profile: profile
            )
            liveHint = "Stabilized reading with impedance."
        } else {
            composition = nil
            liveHint = "Weight only: stay on the scale barefoot until impedance finishes."
        }
        phase = .ready
    }
}

extension ScaleSessionViewModel: ScaleScannerDelegate {
    nonisolated func scaleScanner(_ scanner: ScaleScanning, didUpdateBluetoothState message: String?) {
        Task { @MainActor in
            if let message {
                self.phase = .bluetoothUnavailable(message)
            } else if case .bluetoothUnavailable = self.phase {
                self.phase = .idle
            }
        }
    }

    nonisolated func scaleScanner(_ scanner: ScaleScanning, didDiscover scale: DiscoveredScale) {
        Task { @MainActor in
            if let index = self.discoveredScales.firstIndex(where: { $0.id == scale.id }) {
                self.discoveredScales[index] = scale
            } else {
                self.discoveredScales.append(scale)
            }
            self.discoveredScales.sort { $0.rssi > $1.rssi }
        }
    }

    nonisolated func scaleScanner(_ scanner: ScaleScanning, didDecode measurement: ScaleMeasurement) {
        Task { @MainActor in
            if case .listening = self.phase {
                self.phase = .measuring
            }
            self.accept(measurement)
        }
    }

    nonisolated func scaleScanner(_ scanner: ScaleScanning, transientStatus: String) {
        Task { @MainActor in
            if case .listening = self.phase {
                self.liveHint = transientStatus
            }
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
