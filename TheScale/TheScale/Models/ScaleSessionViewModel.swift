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

/// Why the live sheet is open. Calibration reuses the same UI as weigh-in.
enum WeighInPurpose: Equatable, Sendable {
    case normal
    case calibration
}

@MainActor
final class ScaleSessionViewModel: ObservableObject {
    /// How long to keep waiting for a valid impedance frame after weight stabilizes.
    static let impedanceWaitSeconds: TimeInterval = 18

    @Published private(set) var phase: ScaleSessionPhase = .idle
    @Published private(set) var discoveredScales: [DiscoveredScale] = []
    @Published private(set) var selectedScaleID: UUID?
    @Published private(set) var latestMeasurement: ScaleMeasurement?
    /// Raw (uncalibrated) live streaming kg from BLE.
    @Published private(set) var liveWeightKg: Double?
    @Published private(set) var composition: BodyCompositionResult?
    @Published private(set) var liveHint: String = "Step on the scale when listening."
    @Published private(set) var impedanceMissingReason: String?
    @Published private(set) var isWeighInPresented = false
    /// Shown after a successful Confirm → Health save (weight + fat charts).
    @Published private(set) var isResultsPresented = false
    /// Normal weigh-in vs on-sheet calibration (same live sheet).
    @Published private(set) var weighInPurpose: WeighInPurpose = .normal
    @Published private(set) var recentHealthWeights: [HealthWeightSample] = []
    @Published private(set) var healthBaselineKg: Double?
    /// Chart series for the post-save history screen (oldest → newest).
    @Published private(set) var historyWeights: [HealthMetricSample] = []
    @Published private(set) var historyBodyFatPercents: [HealthMetricSample] = []
    /// Last 14 days of Health weight (always), used by Trend projection regardless of chart range.
    @Published private(set) var historyTrendWindowWeights: [HealthMetricSample] = []
    @Published private(set) var historyRange: HealthHistoryRange = .default
    @Published private(set) var isManualEntryPresented = false
    @Published var draft: EditableMeasurementDraft?
    @Published var isEditingDraft = false
    @Published var profile: UserBodyProfile {
        didSet { UserProfileStore.save(profile) }
    }
    @Published var calibration: ScaleCalibration {
        didSet { ScaleCalibrationStore.save(calibration) }
    }
    /// Last raw kg seen from BLE (kept after the live sheet closes so Settings can capture).
    @Published private(set) var lastRawWeightKg: Double?
    /// Optional manual raw kg typed in Settings when BLE reading is unavailable.
    @Published var manualCalibrationRawKg: Double?

    private let scanner: ScaleScanning
    private let healthStore: HealthWriting
    private var lastAcceptedSignature: String?
    private var impedanceWaitTask: Task<Void, Never>?

    init(
        scanner: ScaleScanning,
        healthStore: HealthWriting,
        profile: UserBodyProfile = UserProfileStore.load(),
        calibration: ScaleCalibration = ScaleCalibrationStore.load()
    ) {
        self.scanner = scanner
        self.healthStore = healthStore
        self.profile = profile
        self.calibration = calibration
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

    /// Latest raw kg (live stream, last stabilized, or last remembered), before calibration.
    var rawDisplayWeightKg: Double? {
        if let liveWeightKg { return liveWeightKg }
        if let latestMeasurement { return latestMeasurement.weightKg }
        return lastRawWeightKg
    }

    /// Raw kg used for calibration capture: manual entry wins, else live/last BLE.
    var calibrationSourceRawKg: Double? {
        if let manualCalibrationRawKg, manualCalibrationRawKg > 0.05 {
            return manualCalibrationRawKg
        }
        return rawDisplayWeightKg
    }

    /// Live display weight: calibrated streaming kg while settling, else draft / stabilized.
    var displayWeightKg: Double? {
        if let draft, isEditingDraft || phase == .reviewing {
            return draft.weightKg
        }
        guard let raw = rawDisplayWeightKg else { return nil }
        return calibration.apply(toRawKg: raw)
    }

    /// Impedance for BIA math only. Never shown in the live sheet chrome.
    var displayImpedanceOhms: Int? {
        if let draft, isEditingDraft || phase == .reviewing || phase == .ready {
            return draft.impedanceOhms
        }
        return latestMeasurement?.impedanceOhms ?? draft?.impedanceOhms
    }

    /// Body fat % for the live sheet (draft, composition, or nil while waiting).
    var displayBodyFatPercent: Double? {
        if let draft, isEditingDraft || phase == .reviewing || phase == .ready {
            return draft.bodyFatPercent
        }
        return composition?.bodyFatPercent ?? draft?.bodyFatPercent
    }

    /// Lean mass % of body weight for the live sheet.
    var displayLeanPercent: Double? {
        if let draft, isEditingDraft || phase == .reviewing || phase == .ready {
            return draft.leanPercent
        }
        if let composition, let kg = displayWeightKg, kg > 0.05 {
            return (composition.leanBodyMassKg / kg) * 100.0
        }
        return draft?.leanPercent
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
        if weighInPurpose != .calibration {
            isWeighInPresented = false
            weighInPurpose = .normal
        }
        phase = .scanning
        liveHint = weighInPurpose == .calibration
            ? "Find the scale, then place your reference mass on the platform."
            : "Looking for MIBFS / Mi Body Composition Scale 2…"
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
        if weighInPurpose == .calibration {
            liveHint = "Listening to \(scale.name). Place \(String(format: "%.3f", calibration.referenceMassKg)) kg on the scale."
        } else {
            liveHint = "Listening for broadcasts from \(scale.name). Step on barefoot for body composition."
        }
        isWeighInPresented = true
        Task { await refreshHealthBaseline() }
    }

    func reopenWeighIn() {
        guard selectedScaleID != nil else { return }
        weighInPurpose = .normal
        isWeighInPresented = true
    }

    /// Primary calibration path: same live sheet as weigh-in, after the user sets reference mass.
    func beginCalibrationWeighIn() {
        weighInPurpose = .calibration
        isEditingDraft = false
        draft = nil
        liveHint = String(
            format: "Calibration: place %.3f kg on the scale. Store when the raw kg settles.",
            calibration.referenceMassKg
        )
        isWeighInPresented = true
        if selectedScaleID == nil {
            // Keep calibration purpose while scanning for a scale.
            startScanning()
            weighInPurpose = .calibration
            isWeighInPresented = true
            liveHint = String(
                format: "Find the scale, then place %.3f kg on the platform.",
                calibration.referenceMassKg
            )
        } else {
            let name = discoveredScales.first(where: { $0.id == selectedScaleID })?.name ?? "scale"
            phase = .listening(scaleName: name)
            liveHint = String(
                format: "Listening to %@. Place %.3f kg on the scale.",
                name,
                calibration.referenceMassKg
            )
        }
        Task { await refreshHealthBaseline() }
    }

    func dismissWeighIn() {
        isWeighInPresented = false
        isEditingDraft = false
        weighInPurpose = .normal
        if case .healthKitSuccess = phase {
            // Keep success state on home / results.
        } else if case .reviewing = phase {
            phase = .ready
        }
    }

    func dismissResults() {
        isResultsPresented = false
    }

    func reopenResults() {
        isResultsPresented = true
        Task {
            do {
                try await loadHistory(for: historyRange)
            } catch {
                // Soft-fail: results screen shows the load error inline via reload.
            }
        }
    }

    func presentManualEntry() {
        isManualEntryPresented = true
    }

    func dismissManualEntry() {
        isManualEntryPresented = false
    }

    /// Load Apple Health weight + body fat samples for the results charts.
    /// Always also loads the last 2 weeks for Trend projection (independent of picker range).
    func loadHistory(for range: HealthHistoryRange = .default) async throws {
        historyRange = range
        guard healthKitAvailable else {
            historyWeights = []
            historyBodyFatPercents = []
            historyTrendWindowWeights = []
            return
        }
        let end = Date()
        let start = range.startDate(relativeTo: end)
        let trendStart = HealthHistoryRange.lastTwoWeeks.startDate(relativeTo: end)
        try await healthStore.requestAuthorizationIfNeeded()
        // Sequential HealthKit reads (same MainActor store; avoids async-let Sendable noise).
        historyWeights = try await healthStore.fetchWeights(from: start, to: end)
        historyBodyFatPercents = try await healthStore.fetchBodyFatPercents(from: start, to: end)
        if range == .lastTwoWeeks {
            historyTrendWindowWeights = historyWeights
        } else {
            historyTrendWindowWeights = try await healthStore.fetchWeights(from: trendStart, to: end)
        }
    }

    /// Mass-only Manual entry → Apple Health (weight + BMI). No fat/lean invented.
    func saveManualWeight(kg: Double, at date: Date) async throws {
        let draft = EditableMeasurementDraft.manual(weightKg: kg, at: date, profile: profile)
        try await healthStore.requestAuthorizationIfNeeded()
        try await healthStore.write(draft: draft, profile: profile)
        phase = .healthKitSuccess
        await refreshHealthBaseline()
        try await loadHistory(for: historyRange)
        isManualEntryPresented = false
        isWeighInPresented = false
        isResultsPresented = true
    }

    /// Store correction from the live sheet using the current raw BLE kg and Settings reference mass.
    @discardableResult
    func confirmCalibrationFromLiveReading() -> Bool {
        guard let raw = rawDisplayWeightKg, raw > 0.05 else {
            liveHint = "Need a positive raw kg from the scale before storing calibration."
            return false
        }
        return recordCalibration(
            referenceKg: calibration.referenceMassKg,
            rawKg: raw,
            mode: calibration.captureMode
        )
    }

    func beginReview() {
        guard let measurement = latestMeasurement else { return }
        let calibrated = calibratedMeasurement(from: measurement)
        draft = EditableMeasurementDraft.from(
            measurement: calibrated,
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
        if let percent {
            draft.leanBodyMassKg = max(draft.weightKg - (draft.weightKg * percent / 100.0), 0)
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
        if let kg, draft.weightKg > 0.05 {
            draft.bodyFatPercent = max(100.0 - ((kg / draft.weightKg) * 100.0), 0)
        }
        self.draft = draft
    }

    /// Edit lean as % of body weight; keeps lean kg and body fat % in a two-compartment model.
    func updateDraftLeanPercent(_ percent: Double?) {
        guard var draft else { return }
        if let percent {
            let clamped = min(max(percent, 0), 100)
            draft.leanBodyMassKg = draft.weightKg * clamped / 100.0
            draft.bodyFatPercent = max(100.0 - clamped, 0)
        } else {
            draft.leanBodyMassKg = nil
        }
        self.draft = draft
    }

    func setIncludeCompositionInHealth(_ include: Bool) {
        guard var draft else { return }
        draft.includeCompositionInHealth = include
        self.draft = draft
    }

    // MARK: - Calibration

    func updateCalibrationReferenceMass(_ kg: Double) {
        var next = calibration
        next.referenceMassKg = max(kg, 0.1)
        calibration = next
    }

    func updateCalibrationOffset(_ kg: Double) {
        var next = calibration
        next.offsetKg = kg
        if abs(kg) > 0.000_01 || abs(next.scaleFactor - 1.0) > 0.000_01 {
            next.isActive = true
        }
        calibration = next
        reapplyCalibrationToLatest()
    }

    func setCalibrationCaptureMode(_ mode: ScaleCalibration.CaptureMode) {
        var next = calibration
        next.captureMode = mode
        calibration = next
    }

    func setCalibrationActive(_ active: Bool) {
        var next = calibration
        next.isActive = active
        calibration = next
        reapplyCalibrationToLatest()
    }

    /// Prefer manual raw if set; else last/live BLE raw. Default mode is offset.
    @discardableResult
    func captureCalibrationFromCurrentReading() -> Bool {
        guard let raw = calibrationSourceRawKg else { return false }
        var next = calibration
        guard next.capture(rawKg: raw) else { return false }
        calibration = next
        lastRawWeightKg = raw
        reapplyCalibrationToLatest()
        liveHint = String(
            format: "Calibration stored: raw %.3f kg → reference %.3f kg (%@).",
            raw,
            calibration.referenceMassKg,
            calibration.captureMode.title
        )
        return true
    }

    /// Record a known pair even when BLE is unavailable (Alex: 7.926 kg true, 7.90 kg raw).
    @discardableResult
    func recordCalibration(referenceKg: Double, rawKg: Double, mode: ScaleCalibration.CaptureMode? = nil) -> Bool {
        var next = calibration
        next.referenceMassKg = max(referenceKg, 0.1)
        if let mode {
            next.captureMode = mode
        }
        guard next.capture(rawKg: rawKg) else { return false }
        calibration = next
        lastRawWeightKg = rawKg
        manualCalibrationRawKg = rawKg
        reapplyCalibrationToLatest()
        liveHint = String(
            format: "Calibration recorded: raw %.3f kg → reference %.3f kg (offset %+.3f kg).",
            rawKg,
            next.referenceMassKg,
            next.offsetKg
        )
        return true
    }

    func resetCalibration() {
        var next = calibration
        next.reset()
        calibration = next
        reapplyCalibrationToLatest()
    }

    private func rememberRawWeight(_ kg: Double) {
        lastRawWeightKg = kg
        // Keep Settings field in sync when the user has not typed a manual override.
        if manualCalibrationRawKg == nil {
            // no-op; UI can bind to lastRawWeightKg via calibrationSourceRawKg
        }
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
            let calibrated = calibratedMeasurement(from: measurement)
            draft = EditableMeasurementDraft.from(
                measurement: calibrated,
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
            // Present the dual-chart history screen after a successful Health write.
            do {
                try await loadHistory(for: .default)
            } catch {
                // Soft-fail: still show the empty results screen with the error inline.
                historyWeights = []
                historyBodyFatPercents = []
                historyTrendWindowWeights = []
            }
            isWeighInPresented = false
            isResultsPresented = true
        } catch {
            phase = .healthKitFailed(error.localizedDescription)
        }
    }

    /// Legacy entry used by older UI paths; routes through draft confirm.
    func saveToHealth() async {
        await saveDraftToHealth()
    }

    private func calibratedMeasurement(from measurement: ScaleMeasurement) -> ScaleMeasurement {
        ScaleMeasurement(
            id: measurement.id,
            weightKg: calibration.apply(toRawKg: measurement.weightKg),
            impedanceOhms: measurement.impedanceOhms,
            scaleDate: measurement.scaleDate,
            hasImpedance: measurement.hasImpedance,
            biaPending: measurement.biaPending,
            displayUnit: measurement.displayUnit,
            receivedAt: measurement.receivedAt,
            isStabilized: measurement.isStabilized
        )
    }

    private func reapplyCalibrationToLatest() {
        guard let measurement = latestMeasurement else { return }
        let calibrated = calibratedMeasurement(from: measurement)
        if let ohms = calibrated.impedanceOhms {
            composition = BodyCompositionCalculator.calculate(
                weightKg: calibrated.weightKg,
                impedanceOhms: ohms,
                profile: profile
            )
        } else {
            composition = nil
        }
        if !isEditingDraft {
            draft = EditableMeasurementDraft.from(
                measurement: calibrated,
                composition: composition,
                profile: profile
            )
        }
    }

    private func accept(_ measurement: ScaleMeasurement) {
        rememberRawWeight(measurement.weightKg)
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
        let calibrated = calibratedMeasurement(from: measurement)

        if let ohms = measurement.impedanceOhms {
            cancelImpedanceWait()
            composition = BodyCompositionCalculator.calculate(
                weightKg: calibrated.weightKg,
                impedanceOhms: ohms,
                profile: profile
            )
            impedanceMissingReason = nil
            liveHint = "Body composition ready. Review body fat % and lean % before saving to Health."
            draft = EditableMeasurementDraft.from(
                measurement: calibrated,
                composition: composition,
                profile: profile
            )
            phase = .ready
            return
        }

        composition = nil
        draft = EditableMeasurementDraft.from(
            measurement: calibrated,
            composition: nil,
            profile: profile
        )
        phase = .awaitingImpedance
        if measurement.biaPending {
            liveHint = "Weight locked. Body composition scan in progress: stay barefoot on the electrodes."
        } else {
            liveHint = "Weight only so far. Stay barefoot until body fat % finishes calculating."
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
                "Body fat unavailable. Socks, shoes, or stepping off early block composition. Stand barefoot on the metal electrodes and wait a few seconds after weight stabilizes."
            self.liveHint = self.impedanceMissingReason ?? self.liveHint
            let calibrated = self.calibratedMeasurement(from: measurement)
            self.draft = EditableMeasurementDraft.from(
                measurement: calibrated,
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
