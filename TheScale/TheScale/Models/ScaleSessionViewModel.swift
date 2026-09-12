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
    case reviewing
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
    @Published private(set) var liveWeightKg: Double?
    @Published private(set) var composition: BodyCompositionResult?
    @Published private(set) var liveHint: String = "Step on the scale when listening."
    @Published private(set) var impedanceMissingReason: String?
    @Published private(set) var isWeighInPresented = false
    @Published private(set) var recentHealthWeights: [HealthWeightSample] = []
    @Published private(set) var healthBaselineKg: Double?
    @Published var draft: EditableMeasurementDraft?
    @Published var isEditingDraft = false
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

    /// Live display weight: streaming kg while settling, else stabilized / draft.
    var displayWeightKg: Double? {
        if let draft, isEditingDraft || phase == .reviewing {
            return draft.weightKg
        }
        if let liveWeightKg { return liveWeightKg }
        return latestMeasurement?.weightKg
    }

    var currentTrend: WeightTrend {
        WeightTrend.from(currentKg: displayWeightKg ?? 0, baselineKg: healthBaselineKg)
    }

    var trendForDisplay: WeightTrend {
        guard displayWeightKg != nil else { return .unknown }
        return currentTrend
    }

    func startScanning() {
        cancelImpedanceWait()
        discoveredScales = []
        selectedScaleID = nil
        latestMeasurement = nil
        liveWeightKg = nil
        composition = nil
        draft = nil
        isEditingDraft = false
        impedanceMissingReason = nil
        lastAcceptedSignature = nil
        isWeighInPresented = false
        phase = .scanning
        liveHint = "Looking for MIBFS / Mi Body Composition Scale 2…"
        scanner.startScanning()
        Task { await refreshHealthBaseline() }
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
        isWeighInPresented = true
        Task { await refreshHealthBaseline() }
    }

    func reopenWeighIn() {
        guard selectedScaleID != nil else { return }
        isWeighInPresented = true
    }

    func dismissWeighIn() {
        isWeighInPresented = false
        isEditingDraft = false
        if case .healthKitSuccess = phase {
            // Keep success state on home.
        } else if case .reviewing = phase {
            phase = .ready
        }
    }

    func beginReview() {
        guard let measurement = latestMeasurement else { return }
        draft = EditableMeasurementDraft.from(
            measurement: measurement,
            composition: composition,
            profile: profile
        )
        isEditingDraft = true
        phase = .reviewing
    }

    func updateDraftWeight(_ kg: Double) {
        guard var draft else { return }
        draft.weightKg = kg
        draft.recalculate(using: profile)
        self.draft = draft
    }

    func updateDraftImpedance(_ ohms: Int?) {
        guard var draft else { return }
        draft.impedanceOhms = ohms
        draft.recalculate(using: profile)
        self.draft = draft
    }

    func updateDraftBodyFat(_ percent: Double?) {
        guard var draft else { return }
        draft.bodyFatPercent = percent
        if let percent, let weight = Optional(draft.weightKg) {
            draft.leanBodyMassKg = max(weight - (weight * percent / 100.0), 0)
        }
        self.draft = draft
    }

    func updateDraftBMI(_ value: Double?) {
        guard var draft else { return }
        draft.bmi = value
        self.draft = draft
    }

    func updateDraftLeanMass(_ kg: Double?) {
        guard var draft else { return }
        draft.leanBodyMassKg = kg
        self.draft = draft
    }

    func setIncludeCompositionInHealth(_ include: Bool) {
        guard var draft else { return }
        draft.includeCompositionInHealth = include
        self.draft = draft
    }

    func refreshHealthBaseline() async {
        guard healthKitAvailable else {
            recentHealthWeights = []
            healthBaselineKg = nil
            return
        }
        do {
            try await healthStore.requestAuthorizationIfNeeded()
            let samples = try await healthStore.fetchRecentWeights(limit: 14)
            recentHealthWeights = samples
            healthBaselineKg = samples.first?.weightKg
        } catch {
            // Soft-fail: trend stays unknown; weigh-in still works.
            liveHint = "Health history unavailable: \(error.localizedDescription)"
        }
    }

    func saveDraftToHealth() async {
        if draft == nil, let measurement = latestMeasurement {
            draft = EditableMeasurementDraft.from(
                measurement: measurement,
                composition: composition,
                profile: profile
            )
        }
        guard let draft else { return }
        phase = .healthKitWriting
        do {
            try await healthStore.requestAuthorizationIfNeeded()
            try await healthStore.write(draft: draft, profile: profile)
            phase = .healthKitSuccess
            isEditingDraft = false
            if draft.includeCompositionInHealth {
                liveHint = "Saved confirmed weight, BMI, body fat %, and lean mass to Apple Health."
            } else {
                liveHint = "Saved confirmed weight and BMI only. Body fat was not written."
            }
            await refreshHealthBaseline()
        } catch {
            phase = .healthKitFailed(error.localizedDescription)
        }
    }

    /// Legacy entry used by older UI paths; routes through draft confirm.
    func saveToHealth() async {
        await saveDraftToHealth()
    }

    private func accept(_ measurement: ScaleMeasurement) {
        if !measurement.isStabilized {
            liveWeightKg = measurement.weightKg
            if case .listening = phase {
                phase = .measuring
            }
            liveHint = "Live weight updating…"
            return
        }

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
        liveWeightKg = measurement.weightKg

        if let ohms = measurement.impedanceOhms {
            cancelImpedanceWait()
            composition = BodyCompositionCalculator.calculate(
                weightKg: measurement.weightKg,
                impedanceOhms: ohms,
                profile: profile
            )
            impedanceMissingReason = nil
            liveHint = "Stabilized reading with impedance (\(ohms) Ω). Review before saving to Health."
            draft = EditableMeasurementDraft.from(
                measurement: measurement,
                composition: composition,
                profile: profile
            )
            phase = .ready
            return
        }

        composition = nil
        draft = EditableMeasurementDraft.from(
            measurement: measurement,
            composition: nil,
            profile: profile
        )
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
            self.draft = EditableMeasurementDraft.from(
                measurement: measurement,
                composition: nil,
                profile: self.profile
            )
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
            isWeighInPresented = false
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
        // Do not clobber an in-progress manual edit with new BLE frames.
        if isEditingDraft, case .reviewing = phase {
            if measurement.isStabilized == false {
                return
            }
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
