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
    @Published private(set) var healthBaselineKg: Double? {
        didSet { rebuildWeeklyGoalSurface() }
    }
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
        didSet {
            let fastingChanged = oldValue.intermittentFasting?.cacheToken
                != profile.intermittentFasting?.cacheToken
            UserProfileStore.save(profile)
            rebuildWeeklyGoalSurface()
            if fastingChanged {
                MealPlanStore.clear()
                mealPlan = nil
            }
        }
    }
    @Published var calibration: ScaleCalibration {
        didSet { ScaleCalibrationStore.save(calibration) }
    }
    @Published var notificationPreferences: NotificationPreferences {
        didSet { NotificationPreferencesStore.save(notificationPreferences) }
    }
    @Published var fitnessMonitorPreferences: FitnessMonitorPreferences {
        didSet {
            FitnessMonitorPreferencesStore.save(fitnessMonitorPreferences)
            Task {
                await GrokFitnessMonitor.scheduleIntervalNotification(
                    prefs: fitnessMonitorPreferences,
                    profileName: profile.greetingName
                )
                GrokFitnessMonitor.scheduleBackgroundRefresh(prefs: fitnessMonitorPreferences)
                GrokFitnessMonitor.scheduleBackgroundProcessing(prefs: fitnessMonitorPreferences)
                if fitnessMonitorPreferences.enabled {
                    await armHealthKitBackgroundDelivery()
                }
            }
        }
    }
    @Published var weeklyGoal: WeeklyMiniGoal {
        didSet {
            WeeklyMiniGoalStore.save(weeklyGoal)
            rebuildWeeklyGoalSurface()
        }
    }
    /// Display / Coach prompt units. Canonical Health + profile fields stay metric.
    @Published var preferredUnits: PreferredUnitSystem {
        didSet { PreferredUnitSystemStore.save(preferredUnits) }
    }
    /// Home weekly-goal hero snapshot (progress %, track band, tomorrow advice, daily targets).
    @Published private(set) var weeklyGoalSurface: WeeklyGoalSurface = WeeklyGoalSurfaceEngine.build(
        weeklyGoal: .default,
        currentKg: nil,
        profile: .default,
        digest: nil
    )
    /// Last computed weekly target mode (catch-up / accelerate / aggressive).
    @Published private(set) var weeklyTargetMode: WeeklyTargetMode = .aggressive
    @Published var hasCompletedOnboarding: Bool {
        didSet { OnboardingStore.hasCompleted = hasCompletedOnboarding }
    }
    /// Soft star-rating sheet (non-invasive; only after real weigh-in success).
    @Published var isAppReviewPromptPresented = false
    /// Selected system TabView destination (native Liquid Glass tab bar).
    @Published var homeTab: HomeGlassDestination = .weigh
    @Published var isProgressPresented = false
    @Published var isCoachPresented = false
    @Published var isSettingsPresented = false
    @Published var isMealPlanPresented = false
    @Published private(set) var mealPlan: MealPlanPayload?
    @Published private(set) var isMealPlanLoading = false
    /// Hero coach card after a successful weigh-in (sergeant / encourage / skeptical).
    @Published private(set) var lastWeighInAnalysis: WeighInAnalysisCard?
    /// Full-screen hero moment shown right after a weigh-in before History.
    @Published private(set) var isWeighInHeroPresented = false
    /// Soft one-question sheet for blank lifestyle fields (diet / location / avoid).
    @Published private(set) var pendingProfileGap: ProfileGapKind?
    /// Offer Monday card after the hero moment dismisses.
    private var pendingMondayAfterHero = false
    private var pendingMondayWeighKg: Double?
    /// True while 10s auto-confirm countdown is armed on the live sheet.
    @Published var autoConfirmArmed = false
    @Published var autoConfirmSecondsRemaining = 10
    /// Shown when live / auto-confirm / save rejects 0 or out-of-bounds kg.
    @Published private(set) var weighRejectionMessage: String?
    /// Published gate for Weigh Now CTA (Health samples and/or local same-day save stamp).
    @Published private(set) var alreadyWeighedToday = false
    /// False until stamp-first sync and/or async Health today reconcile finishes.
    /// Prevents Weigh Now flash when Health already has today's mass.
    @Published private(set) var weighNowGateResolved = false
    /// Monday morning post-weigh weekly goal card.
    @Published private(set) var isMondayCardPresented = false
    @Published private(set) var mondayCard: MondayCardPayload?
    @Published private(set) var isMondayCardLoading = false
    @Published private(set) var mondayCardStreamEncouragement = ""
    @Published private(set) var mondayCardStreamMeals = ""
    @Published private(set) var mondayCardStreamDiagnostic = ""
    @Published private(set) var lastFitnessDigest: FitnessDigest? {
        didSet { rebuildWeeklyGoalSurface() }
    }
    @Published private(set) var lastFitnessCoachReply: String?
    @Published private(set) var lastFitnessTriggers: [FitnessTrigger] = []
    /// Settings + Coach honesty line for Apple Health read status.
    @Published private(set) var healthAccessStatusLine: String = "Health status not checked yet."
    /// Last raw kg seen from BLE (kept after the live sheet closes so Settings can capture).
    @Published private(set) var lastRawWeightKg: Double?
    /// Optional manual raw kg typed in Settings when BLE reading is unavailable.
    @Published var manualCalibrationRawKg: Double?

    private let scanner: ScaleScanning
    private let healthStore: HealthWriting
    private var lastAcceptedSignature: String?
    private var impedanceWaitTask: Task<Void, Never>?
    private var lastHomeGaugeRefreshAt: Date?
    /// Coalesce auto sheet open: ignore BLE reopen until this instant.
    private var autoSheetCooldownUntil: Date?
    /// Prevents concurrent discover + decode races from double-presenting.
    private var isAutoPresentingSheet = false
    /// Serializes Health today reconciles (home appear + digest + scene active).
    private var weighGateReconcileTask: Task<Void, Never>?
    /// Seconds after dismiss before BLE may auto-open again.
    static let autoSheetCooldownSeconds: TimeInterval = 2.0

    init(
        scanner: ScaleScanning,
        healthStore: HealthWriting,
        profile: UserBodyProfile = UserProfileStore.load(),
        calibration: ScaleCalibration = ScaleCalibrationStore.load(),
        notificationPreferences: NotificationPreferences = NotificationPreferencesStore.load(),
        fitnessMonitorPreferences: FitnessMonitorPreferences = FitnessMonitorPreferencesStore.load(),
        weeklyGoal: WeeklyMiniGoal = WeeklyMiniGoalStore.load(),
        preferredUnits: PreferredUnitSystem = PreferredUnitSystemStore.load(),
        hasCompletedOnboarding: Bool = OnboardingStore.hasCompleted
    ) {
        self.scanner = scanner
        self.healthStore = healthStore
        self.profile = profile
        self.calibration = calibration
        self.notificationPreferences = notificationPreferences
        self.fitnessMonitorPreferences = fitnessMonitorPreferences
        self.weeklyGoal = weeklyGoal
        self.preferredUnits = preferredUnits
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.scanner.delegate = self
        self.lastFitnessCoachReply = GrokFitnessMonitor.loadLastReply()
        self.mealPlan = MealPlanStore.load()
        rebuildWeeklyGoalSurface()
        // Stamp-first: hide Weigh Now immediately when local day is already stamped.
        // If not stamped, leave weighNowGateResolved false until Health today reconcile finishes
        // so Health-only same-day mass does not flash the CTA.
        refreshAlreadyWeighedToday()
        weighNowGateResolved = alreadyWeighedToday
        GrokFitnessMonitor.install { [weak self] force in
            guard let self else { return false }
            return await self.runBackgroundHealthWake(
                reason: force ? .processingTask : .appRefresh,
                forceFullCoach: force
            )
        }
        HealthKitBackgroundDelivery.shared.onHealthUpdate = { [weak self] reason in
            guard let self else { return }
            _ = await self.runBackgroundHealthWake(reason: reason, forceFullCoach: false)
        }
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

    /// Passive BLE listen on home: no "Find Scale" primary. Auto-opens live card on signal.
    func startPassiveListening() {
        guard !isWeighInPresented else { return }
        switch phase {
        case .scanning, .listening, .measuring, .awaitingImpedance, .ready, .reviewing, .healthKitWriting:
            return
        default:
            break
        }
        weighInPurpose = .normal
        if phase == .idle || phase == .healthKitSuccess {
            phase = .scanning
            liveHint = "Scale nearby? Step on barefoot. Live card opens on BLE."
        }
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

    /// Focus a discovered scale. Pass `presentSheet: true` for explicit user taps only.
    /// Passive BLE discovery must not present (avoids sheet thrash on noisy ads).
    func selectScale(_ scale: DiscoveredScale, presentSheet: Bool = true) {
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
        if presentSheet {
            presentLiveSheetCoalesced(userInitiated: true)
        }
        Task { await refreshHealthBaseline() }
    }

    func reopenWeighIn() {
        guard selectedScaleID != nil else { return }
        weighInPurpose = .normal
        presentLiveSheetCoalesced(userInitiated: true)
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
        syncWeighInLiveActivity(starting: true)
    }

    func dismissWeighIn() {
        isWeighInPresented = false
        isAutoPresentingSheet = false
        isEditingDraft = false
        autoConfirmArmed = false
        weighRejectionMessage = nil
        weighInPurpose = .normal
        // Cooldown stops dismiss → immediate BLE re-open thrash.
        autoSheetCooldownUntil = Date().addingTimeInterval(Self.autoSheetCooldownSeconds)
        WeighInLiveActivityController.end()
        if case .healthKitSuccess = phase {
            // Keep success state on home / results.
        } else if case .reviewing = phase {
            phase = .ready
        }
        // Resume passive listen so the next confirmed step-on still auto-opens.
        startPassiveListening()
    }

    func cancelAutoConfirm() {
        autoConfirmArmed = false
        autoConfirmSecondsRemaining = 10
    }

    func armAutoConfirm(seconds: Int = 10) {
        guard weighInPurpose == .normal, !isEditingDraft else { return }
        guard let kg = displayWeightKg, ProfileNumericBounds.isPlausibleWeighKg(kg) else {
            cancelAutoConfirm()
            if let kg = displayWeightKg, let message = ProfileNumericBounds.rejectWeighKgMessage(kg) {
                weighRejectionMessage = message
                liveHint = message
            }
            return
        }
        weighRejectionMessage = nil
        autoConfirmSecondsRemaining = seconds
        autoConfirmArmed = true
    }

    /// Clear a rejected impossible reading from the live sheet (UI reset).
    func clearRejectedWeighReading() {
        weighRejectionMessage = nil
        cancelAutoConfirm()
        latestMeasurement = nil
        liveWeightKg = nil
        composition = nil
        draft = nil
        isEditingDraft = false
        impedanceMissingReason = nil
        lastAcceptedSignature = nil
        cancelImpedanceWait()
        if case .ready = phase { phase = selectedScaleID == nil ? .scanning : .listening(scaleName: discoveredScales.first(where: { $0.id == selectedScaleID })?.name ?? "scale") }
        if case .awaitingImpedance = phase { phase = .listening(scaleName: discoveredScales.first(where: { $0.id == selectedScaleID })?.name ?? "scale") }
        if case .reviewing = phase { phase = .listening(scaleName: discoveredScales.first(where: { $0.id == selectedScaleID })?.name ?? "scale") }
        liveHint = "Waiting for a valid weigh. Step on barefoot."
        syncWeighInLiveActivity(starting: false)
    }

    func dismissWeighInAnalysis() {
        lastWeighInAnalysis = nil
    }

    /// Close the post-weigh hero moment, then open History (and Monday card if queued).
    func dismissWeighInHero() {
        isWeighInHeroPresented = false
        refreshAlreadyWeighedToday()
        isResultsPresented = true
        let offerMonday = pendingMondayAfterHero
        let kg = pendingMondayWeighKg
        pendingMondayAfterHero = false
        pendingMondayWeighKg = nil
        guard offerMonday, let kg else { return }
        Task {
            await presentMondayCardIfNeeded(weighInKg: kg, force: false, regenerate: false)
        }
    }

    /// Soft lifestyle gap sheet at calm moments (after meals dismiss, after results).
    func considerProfileGapPrompt() {
        guard pendingProfileGap == nil else { return }
        guard !isCoachPresented,
              !isMondayCardPresented,
              !isSettingsPresented,
              !isWeighInPresented,
              !isWeighInHeroPresented,
              !isResultsPresented,
              !isProgressPresented,
              !isMealPlanPresented,
              !isAppReviewPromptPresented,
              !isManualEntryPresented
        else { return }
        guard let gap = ProfileGapPromptEngine.nextGap(profile: profile) else { return }
        pendingProfileGap = gap
    }

    func skipProfileGap() {
        guard let kind = pendingProfileGap else { return }
        ProfileGapPromptEngine.recordSkipped(kind)
        pendingProfileGap = nil
    }

    func dismissProfileGapSheet() {
        if pendingProfileGap != nil {
            skipProfileGap()
        }
    }

    func saveProfileGap(
        location: String,
        useLocalContext: Bool,
        foodAvoidances: String,
        diet: DietPreference
    ) {
        guard let kind = pendingProfileGap else { return }
        var next = profile
        switch kind {
        case .location:
            next.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
            next.useLocalContext = useLocalContext
        case .foodAvoidances:
            next.foodAvoidances = foodAvoidances.trimmingCharacters(in: .whitespacesAndNewlines)
            next.foodAvoidancesConfirmed = true
        case .diet:
            next.dietPreference = diet
            next.dietPreferenceConfirmed = true
        }
        profile = next
        ProfileGapPromptEngine.recordSaved(kind)
        pendingProfileGap = nil
        if kind == .diet || kind == .foodAvoidances || kind == .location {
            clearMealPlanCache()
        }
    }

    #if DEBUG
    /// Preview / debug injection for hero moment UI.
    func previewInjectWeighInHero(_ card: WeighInAnalysisCard) {
        lastWeighInAnalysis = card
        isWeighInHeroPresented = true
    }
    #endif

    func dismissResults() {
        isResultsPresented = false
        refreshAlreadyWeighedToday()
        // Settle home first so the soft sheet never fights the results dismiss.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            considerAppReviewPrompt()
            if !isAppReviewPromptPresented {
                considerProfileGapPrompt()
            }
        }
    }

    func dismissAppReviewPrompt() {
        isAppReviewPromptPresented = false
    }

    /// Soft star prompt after enough successful Health saves — never mid-weigh-in.
    func considerAppReviewPrompt() {
        guard ScaleAppReviewPrompt.shouldOfferSoftPrompt() else { return }
        // Avoid stacking over Coach / Monday / settings.
        guard !isCoachPresented,
              !isMondayCardPresented,
              !isSettingsPresented,
              !isWeighInPresented,
              !isWeighInHeroPresented,
              !isResultsPresented,
              !isProgressPresented
        else { return }
        isAppReviewPromptPresented = true
    }

    private func noteSuccessfulWeighInForReview() {
        ScaleAppReviewPrompt.recordSuccessfulWeighIn()
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

    /// Switch the system tab bar (and keep legacy presented flags in sync for gates).
    func selectHomeTab(_ tab: HomeGlassDestination) {
        let leavingMeals = homeTab == .meals && tab != .meals
        homeTab = tab
        isProgressPresented = tab == .progress
        isCoachPresented = tab == .keel
        isMealPlanPresented = tab == .meals
        isSettingsPresented = tab == .settings
        if tab == .progress {
            ensureWeeklyGoalBaseline()
        }
        if leavingMeals {
            isMealPlanLoading = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                considerProfileGapPrompt()
            }
        }
    }

    func presentProgress() {
        selectHomeTab(.progress)
    }

    func dismissProgress() {
        selectHomeTab(.weigh)
    }

    func presentCoach() {
        selectHomeTab(.keel)
    }

    func dismissCoach() {
        selectHomeTab(.weigh)
    }

    func presentMealPlan() {
        selectHomeTab(.meals)
    }

    /// Drop cached meals so the next ensure rebuilds (e.g. IF window changed).
    func clearMealPlanCache() {
        MealPlanStore.clear()
        mealPlan = nil
    }

    func dismissMealPlan() {
        selectHomeTab(.weigh)
    }

    /// Load cached meal plan if key matches; otherwise generate (offline or Grok).
    @discardableResult
    func ensureMealPlan() async -> MealPlanPayload {
        await refreshMealPlan(force: false)
    }

    /// `force` regenerates even when a complete plan already exists for today.
    /// Default path: reuse any complete same-day plan (no Grok). Refresh button passes `force: true`.
    @discardableResult
    func refreshMealPlan(force: Bool) async -> MealPlanPayload {
        rebuildWeeklyGoalSurface()
        let surface = weeklyGoalSurface
        let day = MealPlanEngine.dayKey()
        let fasting = FastingWindowResolver.current(
            profile: profile,
            memoryBlock: CoachMemoryStore.promptBlock()
        )
        let now = Date()
        let key = MealPlanEngine.cacheKey(
            dayKey: day,
            maxKcal: surface.targets.maxCalories,
            proteinGrams: surface.targets.proteinGrams,
            diet: profile.dietPreference,
            weeklyDeltaKg: weeklyGoal.targetDeltaKg,
            fasting: fasting,
            now: now
        )

        // Day cache wins: do not burn tokens when today's plan already exists.
        if !force,
           let cached = mealPlan ?? MealPlanStore.load(),
           cached.dayKey == day,
           cached.isComplete {
            mealPlan = cached
            return cached
        }

        // Exact key match still short-circuits incomplete drafts that share the day.
        if !force,
           let cached = mealPlan ?? MealPlanStore.load(),
           cached.cacheKey == key,
           cached.isComplete {
            mealPlan = cached
            return cached
        }

        isMealPlanLoading = true
        defer { isMealPlanLoading = false }

        let brief = makeCoachBrief()
        let micro = "\(surface.targets.microName) \(surface.targets.microTargetLine)"
        let plan = await GrokClient.shared.mealPlan(
            brief: brief,
            maxKcal: surface.targets.maxCalories,
            proteinGrams: surface.targets.proteinGrams,
            microHint: micro,
            dayKey: day,
            weeklyDeltaKg: weeklyGoal.targetDeltaKg,
            fasting: fasting,
            now: now
        )
        mealPlan = plan
        MealPlanStore.save(plan)
        return plan
    }

    func dismissMondayCard() {
        isMondayCardPresented = false
        isMondayCardLoading = false
    }

    /// Dev / preview: force-show the Monday card (optionally regenerate past cache).
    func forcePresentMondayCard(regenerate: Bool = true) {
        Task {
            await presentMondayCardIfNeeded(
                weighInKg: healthBaselineKg ?? displayWeightKg ?? profile.idealWeightKg,
                force: true,
                regenerate: regenerate
            )
        }
    }

    /// After Confirm-to-Health (or Manual) on Monday morning, or Dev force.
    /// Caches one card per ISO week unless weigh-in signature changes or regenerate.
    func presentMondayCardIfNeeded(
        weighInKg: Double,
        force: Bool,
        regenerate: Bool,
        now: Date = Date()
    ) async {
        guard force || MondayCardEngine.shouldOfferAfterWeighIn(now: now) else { return }

        let week = MondayWeekKey.current(now: now)
        let signature = MondayCardEngine.weighInSignature(kg: weighInKg, at: now)

        if !regenerate, let cached = MondayCardStore.load(), cached.weekKey == week.storageKey, cached.isComplete {
            // Production: reuse week cache unless a new Monday weigh-in signature.
            // Dev force without regenerate: show whatever is cached for the week.
            let sameWeighIn = cached.weighInSignature == signature
            if force || sameWeighIn {
                applyMondayCardCache(cached)
                return
            }
        }

        isMondayCardLoading = true
        isMondayCardPresented = true
        mondayCardStreamEncouragement = ""
        mondayCardStreamMeals = ""
        mondayCardStreamDiagnostic = ""

        let digest = await refreshFitnessDigestForCoach()
        if historyWeights.isEmpty {
            do { try await loadHistory(for: .lastTwoWeeks) } catch { /* soft */ }
        }

        let progress = MondayCardEngine.progress(
            weights: historyWeights.isEmpty ? historyTrendWindowWeights : historyWeights,
            fats: historyBodyFatPercents,
            currentKg: weighInKg,
            priorSundayTargetKg: MondayCardStore.priorSundayTargetKg,
            digest: digest,
            now: now
        )
        let sunday = MondayCardEngine.sundayGoal(
            currentKg: weighInKg,
            idealKg: profile.idealWeightKg,
            goalDate: profile.goalDate,
            fallbackWeeklyDeltaKg: weeklyGoal.targetDeltaKg,
            priorSundayTargetKg: MondayCardStore.priorSundayTargetKg,
            now: now
        )

        // Keep Progress mini-goal aligned with this week's Sunday pace.
        var nextGoal = weeklyGoal
        nextGoal.targetDeltaKg = sunday.weeklyDeltaKg
        nextGoal.title = String(format: "Sunday %.2f kg", sunday.targetKg)
        nextGoal.weekStartKg = weighInKg
        nextGoal.weekStartDate = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        weeklyTargetMode = sunday.mode
        weeklyGoal = nextGoal

        let goalDateLine: String = {
            if let date = profile.goalDate {
                return String(
                    format: "Target %.1f kg by %@",
                    profile.idealWeightKg,
                    date.formatted(.dateTime.month(.abbreviated).day().year())
                )
            }
            return String(format: "Target weight %.1f kg (no goal date set; using weekly nudge).", profile.idealWeightKg)
        }()

        var draft = MondayCardPayload(
            weekKey: week.storageKey,
            weighInSignature: signature,
            currentKg: weighInKg,
            progress: progress,
            sundayGoal: sunday,
            encouragement: "",
            meals: "",
            diagnostic: "",
            usedNetwork: false,
            generatedAt: now
        )
        mondayCard = draft

        let brief = makeCoachBrief(digest: digest)
        let result = await GrokClient.shared.mondayCardStreaming(
            brief: brief,
            progress: progress,
            sundayGoal: sunday,
            goalDateLine: goalDateLine
        ) { [weak self] encouragement, meals, diagnostic, _ in
            guard let self else { return }
            self.mondayCardStreamEncouragement = encouragement
            self.mondayCardStreamMeals = meals
            self.mondayCardStreamDiagnostic = diagnostic
            if var live = self.mondayCard {
                live.encouragement = encouragement
                live.meals = meals
                live.diagnostic = diagnostic
                self.mondayCard = live
            }
        }

        draft.encouragement = result.encouragement
        draft.meals = result.meals
        draft.diagnostic = result.diagnostic
        draft.usedNetwork = result.usedNetwork
        draft.generatedAt = Date()
        mondayCard = draft
        mondayCardStreamEncouragement = result.encouragement
        mondayCardStreamMeals = result.meals
        mondayCardStreamDiagnostic = result.diagnostic
        MondayCardStore.save(draft)
        isMondayCardLoading = false
    }

    private func applyMondayCardCache(_ cached: MondayCardPayload) {
        mondayCard = cached
        mondayCardStreamEncouragement = cached.encouragement
        mondayCardStreamMeals = cached.meals
        mondayCardStreamDiagnostic = cached.diagnostic
        isMondayCardPresented = true
        isMondayCardLoading = false
    }

    func updateWeeklyGoalDelta(_ deltaKg: Double) {
        var next = weeklyGoal
        next.targetDeltaKg = deltaKg
        next.title = String(format: "Nudge %+.1f kg this week", deltaKg)
        weeklyGoal = next
    }

    /// Lock ISO-week baseline from the latest Health weight when missing or stale.
    /// Also refreshes weekly delta from the macro goal (aggressive / catch-up / accelerate).
    func ensureWeeklyGoalBaseline() {
        guard let baseline = healthBaselineKg else {
            rebuildWeeklyGoalSurface()
            return
        }
        var next = weeklyGoal
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start
        var weekRolled = false
        if next.weekStartKg == nil || next.weekStartDate == nil {
            next.weekStartKg = baseline
            next.weekStartDate = weekStart ?? Date()
            weekRolled = true
        } else if let stored = next.weekStartDate, let weekStart,
                  !cal.isDate(stored, equalTo: weekStart, toGranularity: .weekOfYear) {
            next.weekStartKg = baseline
            next.weekStartDate = weekStart
            weekRolled = true
        }

        let hit = AggressiveWeeklyTargetEngine.compute(
            currentKg: baseline,
            idealKg: profile.idealWeightKg,
            goalDate: profile.goalDate,
            priorSundayTargetKg: MondayCardStore.priorSundayTargetKg,
            fallbackWeeklyDeltaKg: next.targetDeltaKg
        )
        weeklyTargetMode = hit.mode

        // Always re-sync delta + Sunday title from the biology-capped engine.
        // Stale titles (or pacing-line titles with other "X kg" tokens) must not stick.
        let titleNeedsRefresh: Bool = {
            guard let shown = WeeklyGoalSurfaceEngine.parseSundayKg(from: next.title) else { return true }
            return abs(shown - hit.sundayTargetKg) > 0.04
        }()
        if weekRolled
            || abs(next.targetDeltaKg - hit.weeklyDeltaKg) > 0.04
            || titleNeedsRefresh
            || hit.mode == .hardcoreCatchUp
            || hit.mode == .accelerate
        {
            next.targetDeltaKg = hit.weeklyDeltaKg
            next.title = String(format: "Sunday %.2f kg", hit.sundayTargetKg)
        }
        // If week-start was locked far from today's baseline (manual edit / bad Health sample),
        // keep the Sunday number anchored to the engine's live currentKg math.
        if let start = next.weekStartKg, abs(start - baseline) > 2.5 {
            next.weekStartKg = baseline
            next.weekStartDate = weekStart ?? Date()
            next.targetDeltaKg = hit.weeklyDeltaKg
            next.title = String(format: "Sunday %.2f kg", hit.sundayTargetKg)
        }
        weeklyGoal = next
    }

    /// Refresh home gauges from a lean HealthKit query (steps / move / nutrition only).
    /// Prefer this for UI speed; full Coach digest stays on `refreshFitnessDigestForCoach`.
    @discardableResult
    func refreshHomeGauges(force: Bool = false) async -> WeeklyGoalSurface {
        if !force,
           let last = lastHomeGaugeRefreshAt,
           Date().timeIntervalSince(last) < 8,
           lastFitnessDigest?.stepsToday != nil {
            rebuildWeeklyGoalSurface()
            return weeklyGoalSurface
        }

        guard healthKitAvailable else {
            var digest = lastFitnessDigest ?? FitnessDigest.unavailable()
            digest.applyHomeDailyMetrics(.zero)
            lastFitnessDigest = digest
            return weeklyGoalSurface
        }

        do {
            try await healthStore.requestAuthorizationIfNeeded()
            let metrics = try await healthStore.fetchHomeDailyMetrics(now: Date())
            var digest = lastFitnessDigest ?? FitnessDigest.empty
            if digest.access == .notRequested {
                digest.access = healthStore.authorizationWasRequested ? .readable : .notRequested
                digest.accessDetail = digest.access == .readable
                    ? "Home gauges refreshed from Health."
                    : "Health access not requested yet."
            }
            digest.applyHomeDailyMetrics(metrics)
            lastHomeGaugeRefreshAt = Date()
            lastFitnessDigest = digest
            // Success path stays silent — never print Home gauges steps/move/diet on every wake.
        } catch {
            ScaleDebugLog.throttled("homeGauges.fail", "Home gauges refresh FAILED: \(error.localizedDescription)")
            // Soft-fail: keep prior digest; still rebuild so UI settles.
            rebuildWeeklyGoalSurface()
        }
        return weeklyGoalSurface
    }

    /// Refresh Health digest + rebuild the home weekly-goal hero.
    @discardableResult
    func refreshWeeklyGoalSurface() async -> WeeklyGoalSurface {
        // Fast path first so Horizon Arc Bank fills without waiting on sleep/HRV/workouts.
        await refreshHomeGauges(force: true)
        _ = await refreshFitnessDigestForCoach()
        rebuildWeeklyGoalSurface()
        await polishTomorrowAdviceIfAvailable()
        return weeklyGoalSurface
    }

    func rebuildWeeklyGoalSurface() {
        weeklyGoalSurface = WeeklyGoalSurfaceEngine.build(
            weeklyGoal: weeklyGoal,
            currentKg: healthBaselineKg ?? displayWeightKg,
            profile: profile,
            digest: lastFitnessDigest,
            recentWeights: recentHealthWeights,
            targetMode: weeklyTargetMode
        )
    }

    /// Optional on-device FM polish for the today-ahead line (never required).
    private func polishTomorrowAdviceIfAvailable() async {
        guard FoundationModelAvailability.isAvailable else { return }
        let digest = lastFitnessDigest
        let block = digest?.promptBlock(
            preSleepWindowMinutes: fitnessMonitorPreferences.thresholds.preSleepHRWindowMinutes
        ) ?? ""
        let energyLine = weeklyGoalSurface.energySnapshot?.summaryLine ?? ""
        let meals = weeklyGoalSurface.mealSuggestion ?? ""
        let fallback = weeklyGoalSurface.todayAdvice
        let overeating: Bool = {
            if case .overeatingWhileActive = weeklyGoalSurface.energySnapshot?.diagnosis { return true }
            return false
        }()
        let prompt: String
        if overeating {
            prompt = """
                Rewrite as ONE blunt Coach line for TODAY (max 36 words).
                Name the user if present. No em dashes. No medical diagnosis. No disclaimer.
                Lead with intake / get your act together, NOT a step target.
                Keep the calorie cap number. Optionally weave one short meal idea from: \(meals)
                Energy read: \(energyLine)
                Current line: \(fallback)
                """
        } else {
            prompt = """
                Rewrite this as ONE short punchy line for TODAY (max 28 words).
                Coach voice, call the user by name if present, no em dashes, no medical diagnosis, no disclaimer.
                Prefer calorie / protein / sleep fixes over inventing a new step goal when intake is the issue.
                Current line: \(fallback)
                Energy read: \(energyLine)
                """
        }
        let digestBlock = block.isEmpty ? energyLine : (block + "\n" + energyLine)
        guard !digestBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !fallback.isEmpty else { return }
        if let polished = await FoundationModelCoach.summarizeFitnessDigest(
            profileName: profile.greetingName,
            digestBlock: prompt + "\n\n" + digestBlock
        ) {
            let cleaned = CoachCopySanitize.clean(polished)
            guard !cleaned.isEmpty, cleaned.count < 280 else { return }
            var next = weeklyGoalSurface
            next.todayAdvice = cleaned
            weeklyGoalSurface = next
        }
    }

    func makeCoachBrief(digest: FitnessDigest? = nil) -> CoachBrief {
        let weekDelta: Double? = {
            guard let current = healthBaselineKg, let start = weeklyGoal.weekStartKg else { return nil }
            return current - start
        }()
        let activeDigest = digest ?? lastFitnessDigest ?? FitnessDigest.empty
        let window = fitnessMonitorPreferences.thresholds.preSleepHRWindowMinutes
        return CoachBrief(
            userName: profile.greetingName,
            diet: profile.dietPreference,
            heightCm: profile.heightCm,
            ageYears: profile.ageYears,
            sex: profile.sex,
            currentKg: healthBaselineKg ?? displayWeightKg,
            idealKg: profile.idealWeightKg,
            bodyFatPercent: historyBodyFatPercents.last?.value ?? displayBodyFatPercent,
            idealBodyFatPercent: profile.idealBodyFatPercent,
            trend: trendForDisplay,
            weekDeltaKg: weekDelta,
            weeklyGoal: weeklyGoal,
            personaBlock: profile.coachPersonaBlock,
            memoryBlock: {
                let mem = CoachMemoryStore.promptBlock()
                let comments = ChartCommentStore.analysisPayload()
                if mem.isEmpty { return comments }
                if comments.isEmpty { return mem }
                return mem + "\n" + comments
            }(),
            fitnessDigestBlock: activeDigest.promptBlock(preSleepWindowMinutes: window),
            localNow: Date(),
            unitSystem: preferredUnits
        )
    }

    /// Fresh HealthKit snapshot for every Coach turn (not only background fitness jobs).
    @discardableResult
    func refreshFitnessDigestForCoach(reRequestAuth: Bool = false) async -> FitnessDigest {
        guard healthKitAvailable else {
            let digest = FitnessDigest.unavailable()
            lastFitnessDigest = digest
            healthAccessStatusLine = digest.settingsStatusLine
            return digest
        }
        do {
            if reRequestAuth {
                try await healthStore.reRequestAuthorization()
            }
            try await healthStore.requestAuthorizationIfNeeded()
            let digest = try await healthStore.fetchFitnessDigest(
                preSleepWindowMinutes: fitnessMonitorPreferences.thresholds.preSleepHRWindowMinutes,
                now: Date()
            )
            lastFitnessDigest = digest
            healthAccessStatusLine = digest.settingsStatusLine
            ScaleDebugLog.throttled("coachDigest.ok", "Coach digest refresh: \(digest.debugSummaryLine)")
            await considerMorningWeighDrill(digest: digest)
            return digest
        } catch {
            let digest = FitnessDigest.readFailed(message: error.localizedDescription)
            lastFitnessDigest = digest
            healthAccessStatusLine = digest.settingsStatusLine
            ScaleDebugLog.throttled("coachDigest.fail", "Coach digest refresh FAILED: \(error.localizedDescription)")
            return digest
        }
    }

    /// After digest refresh / scene active: reconcile Weigh Now gate, then morning drill.
    func considerMorningWeighDrill(digest: FitnessDigest? = nil) async {
        await reconcileAlreadyWeighedTodayFromHealth()
        let weighedToday = alreadyWeighedToday
        let snap = digest ?? lastFitnessDigest
        await MorningWeighDrillScheduler.consider(
            prefs: notificationPreferences,
            profileName: profile.greetingName,
            sleepWake: snap?.sleepWake,
            alreadyWeighedToday: weighedToday
        )
    }

    /// True when Apple Health bodyMass and/or an in-app save already logged mass today.
    /// Prefer reading `alreadyWeighedToday` in SwiftUI (published). This method stays for callers.
    func hasValidWeighInToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        Self.detectWeighInToday(
            historyWeights: historyWeights,
            trendWeights: historyTrendWindowWeights,
            recentWeights: recentHealthWeights,
            localDayStamp: Self.loadLocalWeighDayStamp(),
            now: now,
            calendar: calendar
        )
    }

    /// Homepage should show Weigh Now only after the gate is resolved and today is still empty.
    var shouldShowWeighNowCTA: Bool {
        weighNowGateResolved && !alreadyWeighedToday
    }

    /// Recompute published CTA gate from Health arrays + local same-day save stamp.
    /// When Health already has a plausible today sample, backfill the local stamp so the
    /// Weigh Now CTA stays hidden even if a later Health read fails.
    @discardableResult
    func refreshAlreadyWeighedToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let next = hasValidWeighInToday(now: now, calendar: calendar)
        if next {
            let stamp = Self.localDayStamp(now, calendar: calendar)
            if Self.loadLocalWeighDayStamp() != stamp {
                UserDefaults.standard.set(stamp, forKey: Self.localWeighDayKey)
            }
        }
        alreadyWeighedToday = next
        return next
    }

    /// Stamp-first, then always pull local-today bodyMass from Health when available.
    /// Health-only same-day entries (no prior in-app stamp) hide Weigh Now once found.
    /// Coalesced: overlapping home/digest/scene calls share one in-flight pass.
    func reconcileAlreadyWeighedTodayFromHealth() async {
        // Stamp-first sync path (no await): hide CTA immediately when stamped.
        refreshAlreadyWeighedToday()
        if alreadyWeighedToday {
            weighNowGateResolved = true
        }

        if let existing = weighGateReconcileTask {
            await existing.value
            return
        }

        let task = Task { @MainActor in
            await self.runWeighGateHealthReconcile()
        }
        weighGateReconcileTask = task
        await task.value
        weighGateReconcileTask = nil
    }

    private func runWeighGateHealthReconcile() async {
        refreshAlreadyWeighedToday()
        if healthKitAvailable {
            // Always query local-today bodyMass (covers Health-only entries).
            await refreshTodayHealthWeightsForGate()
            refreshAlreadyWeighedToday()
            if !alreadyWeighedToday {
                await refreshHealthBaseline()
                refreshAlreadyWeighedToday()
            }
        }
        weighNowGateResolved = true
    }

    /// Immediate post-save: stamp **device local today** (not scale clock), inject sample, flip gate.
    /// Scale `scaleDate` can be wrong TZ/day and left Weigh Now visible after a real save.
    func markValidWeighInToday(kg: Double, at date: Date = Date(), calendar: Calendar = .current) {
        guard ProfileNumericBounds.isPlausibleWeighKg(kg) else { return }
        let now = Date()
        let stamp = Self.localDayStamp(now, calendar: calendar)
        UserDefaults.standard.set(stamp, forKey: Self.localWeighDayKey)
        // Prefer the Health sample date when it is still local-today; else stamp with now.
        let injectAt = calendar.isDate(date, inSameDayAs: now) ? date : now
        injectOptimisticWeighSample(kg: kg, at: injectAt, calendar: calendar)
        alreadyWeighedToday = true
        weighNowGateResolved = true
    }

    /// Pull body-mass samples for local calendar today into in-memory series for the gate.
    private func refreshTodayHealthWeightsForGate(now: Date = Date(), calendar: Calendar = .current) async {
        guard healthKitAvailable else { return }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
        do {
            try await healthStore.requestAuthorizationIfNeeded()
            let today = try await healthStore.fetchWeights(from: start, to: end)
            let plausible = today.filter { ProfileNumericBounds.isPlausibleWeighKg($0.value) }
            guard let newest = plausible.last else { return }

            let sample = HealthWeightSample(weightKg: newest.value, date: newest.date)
            if !recentHealthWeights.contains(where: {
                calendar.isDate($0.date, inSameDayAs: now)
                    && ProfileNumericBounds.isPlausibleWeighKg($0.weightKg)
            }) {
                recentHealthWeights = [sample] + recentHealthWeights
            } else {
                // Refresh newest today mass to the front so baseline stays coherent.
                recentHealthWeights = [sample] + recentHealthWeights.filter {
                    !(calendar.isDate($0.date, inSameDayAs: now) && abs($0.weightKg - newest.value) < 0.05)
                }
            }
            healthBaselineKg = newest.value

            if !historyWeights.contains(where: {
                calendar.isDate($0.date, inSameDayAs: now)
                    && ProfileNumericBounds.isPlausibleWeighKg($0.value)
            }) {
                historyWeights = historyWeights + [newest]
            }
            if !historyTrendWindowWeights.contains(where: {
                calendar.isDate($0.date, inSameDayAs: now)
                    && ProfileNumericBounds.isPlausibleWeighKg($0.value)
            }) {
                historyTrendWindowWeights = historyTrendWindowWeights + [newest]
            }
        } catch {
            ScaleDebugLog.throttled("weighGate.fail", "Today weigh gate Health fetch failed: \(error.localizedDescription)")
        }
    }

    nonisolated static let localWeighDayKey = "thescale.weighIn.lastValidLocalDay"

    nonisolated static func localDayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    nonisolated static func loadLocalWeighDayStamp() -> String? {
        UserDefaults.standard.string(forKey: localWeighDayKey)
    }

    nonisolated static func detectWeighInToday(
        historyWeights: [HealthMetricSample],
        trendWeights: [HealthMetricSample],
        recentWeights: [HealthWeightSample],
        localDayStamp: String? = nil,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        if let localDayStamp, localDayStamp == Self.localDayStamp(now, calendar: calendar) {
            return true
        }
        if historyWeights.contains(where: {
            calendar.isDate($0.date, inSameDayAs: now)
                && ProfileNumericBounds.isPlausibleWeighKg($0.value)
        }) {
            return true
        }
        if trendWeights.contains(where: {
            calendar.isDate($0.date, inSameDayAs: now)
                && ProfileNumericBounds.isPlausibleWeighKg($0.value)
        }) {
            return true
        }
        if recentWeights.contains(where: {
            calendar.isDate($0.date, inSameDayAs: now)
                && ProfileNumericBounds.isPlausibleWeighKg($0.weightKg)
        }) {
            return true
        }
        return false
    }

    private func injectOptimisticWeighSample(kg: Double, at date: Date, calendar: Calendar) {
        let recent = HealthWeightSample(weightKg: kg, date: date)
        if !recentHealthWeights.contains(where: {
            calendar.isDate($0.date, inSameDayAs: date) && abs($0.weightKg - kg) < 0.05
        }) {
            recentHealthWeights = [recent] + recentHealthWeights
        }
        healthBaselineKg = kg
        let metric = HealthMetricSample(value: kg, date: date)
        if !historyWeights.contains(where: {
            calendar.isDate($0.date, inSameDayAs: date) && abs($0.value - kg) < 0.05
        }) {
            historyWeights = historyWeights + [metric]
        }
        if !historyTrendWindowWeights.contains(where: {
            calendar.isDate($0.date, inSameDayAs: date) && abs($0.value - kg) < 0.05
        }) {
            historyTrendWindowWeights = historyTrendWindowWeights + [metric]
        }
    }

    /// Pure auto-open gate (unit-tested). Hero is never gated here; that waits on Health save.
    nonisolated static func shouldAutoPresentLiveSheet(
        isAlreadyPresented: Bool,
        isAutoPresenting: Bool,
        alreadyWeighedToday: Bool,
        purpose: WeighInPurpose,
        isEditingDraft: Bool,
        cooldownActive: Bool,
        measurementStabilized: Bool,
        weightKg: Double,
        phaseAllowsAutoOpen: Bool
    ) -> Bool {
        guard !isAlreadyPresented, !isAutoPresenting else { return false }
        guard purpose == .normal, !isEditingDraft else { return false }
        guard !alreadyWeighedToday else { return false }
        guard !cooldownActive else { return false }
        guard phaseAllowsAutoOpen else { return false }
        guard measurementStabilized else { return false }
        guard ProfileNumericBounds.isPlausibleWeighKg(weightKg) else { return false }
        return true
    }

    func presentSettings() {
        selectHomeTab(.settings)
    }

    func dismissSettings() {
        selectHomeTab(.weigh)
    }

    func handleNotificationDestination(_ destination: ScaleNotificationDestination) {
        switch destination {
        case .coach:
            presentCoach()
        case .progress:
            presentProgress()
        case .history:
            selectHomeTab(.weigh)
            reopenResults()
        case .settings:
            presentSettings()
        case .weigh:
            selectHomeTab(.weigh)
            if selectedScaleID != nil {
                reopenWeighIn()
            } else {
                presentManualEntry()
            }
        }
    }

    /// Settings: re-prompt Health permissions, refresh digest, arm background delivery.
    func requestHealthAccessFromSettings() async {
        _ = await refreshFitnessDigestForCoach(reRequestAuth: true)
        await armHealthKitBackgroundDelivery()
    }

    /// Parse Coach chat for stated weight / body-fat targets, gate medically, update profile when safe.
    @discardableResult
    func processCoachStatedTargets(from userText: String) -> [TargetFeasibilityResult] {
        let stated = CoachTargetExtractor.extract(from: userText)
        guard !stated.isEmpty else { return [] }
        let currentKg = healthBaselineKg ?? displayWeightKg
        let currentFat = historyBodyFatPercents.last?.value ?? displayBodyFatPercent
        var results: [TargetFeasibilityResult] = []
        var next = profile
        for target in stated {
            let result = TargetFeasibility.evaluate(
                stated: target,
                profile: next,
                currentKg: currentKg,
                currentBodyFatPercent: currentFat
            )
            results.append(result)
            switch result.verdict {
            case .accepted, .acceptedWithCaution:
                if let kg = result.appliedWeightKg {
                    next.idealWeightKg = kg
                }
                if let fat = result.appliedBodyFatPercent {
                    next.idealBodyFatPercent = fat
                }
                CoachMemoryStore.remember(
                    CoachMemoryFact(
                        text: result.coachNote,
                        tags: ["target"]
                    )
                )
            case .rejected:
                CoachMemoryStore.remember(
                    CoachMemoryFact(
                        text: "Rejected unsafe target: \(result.coachNote)",
                        tags: ["target", "safety"]
                    )
                )
            }
        }
        if next != profile {
            profile = next
        }
        return results
    }

    /// Scientific tempered projection for History charts (always-on Target path).
    func scientificWeightProjection(now: Date = Date()) -> ScientificWeightProjection? {
        let samples = historyWeights.isEmpty ? historyTrendWindowWeights : historyWeights
        return HealthChartMath.scientificProjectWeight(
            samples: samples,
            idealKg: profile.idealWeightKg,
            currentKg: healthBaselineKg ?? displayWeightKg ?? historyWeights.last?.value,
            heightCm: profile.heightCm,
            sex: profile.sex,
            digest: lastFitnessDigest,
            now: now
        )
    }

    func requestOrchestratorCoach() async -> CoachReply {
        await GrokClient.shared.orchestrate(brief: makeCoachBrief())
    }

    /// Pull Health fitness signals, evaluate triggers, optionally call Grok.
    @discardableResult
    func runFitnessMonitorCheck(force: Bool) async -> Bool {
        await runBackgroundHealthWake(
            reason: force ? .manual : .appRefresh,
            forceFullCoach: force
        )
    }

    /// Background-capable Health sweep: works from HKObserverQuery / BG tasks without UI.
    /// Always evaluates Watch-wear / pre-sleep triggers when monitoring is on (cooldowns still apply).
    /// Full Coach/Grok digests run when forced or when the interval is due.
    @discardableResult
    func runBackgroundHealthWake(
        reason: HealthKitBackgroundDelivery.HealthKitBackgroundWakeReason,
        forceFullCoach: Bool
    ) async -> Bool {
        var prefs = fitnessMonitorPreferences
        let monitoringOn = prefs.enabled || forceFullCoach
        let wantTrend =
            notificationPreferences.notifyOnBadTrend || notificationPreferences.weeklyGoalReminders
        let wantMorning = notificationPreferences.morningWeighDrill
        // Morning drill alone must still wake: sleep digest + calendar fallback.
        guard monitoringOn || wantTrend || wantMorning else { return false }

        do {
            try await healthStore.requestAuthorizationIfNeeded()
            await armHealthKitBackgroundDelivery()

            if monitoringOn || wantMorning {
                let digest = try await healthStore.fetchFitnessDigest(
                    preSleepWindowMinutes: prefs.thresholds.preSleepHRWindowMinutes,
                    now: Date()
                )
                lastFitnessDigest = digest
                healthAccessStatusLine = digest.settingsStatusLine

                if monitoringOn {
                    let triggers = FitnessTriggerMonitor.evaluate(
                        digest: digest,
                        thresholds: prefs.thresholds
                    )
                    lastFitnessTriggers = triggers

                    await GrokFitnessMonitor.notifyTriggers(
                        triggers,
                        prefs: &prefs,
                        profileName: profile.greetingName
                    )

                    let intervalDue = FitnessTriggerMonitor.isAutomatedCheckDue(prefs: prefs)
                    let doFullCoach = forceFullCoach || intervalDue
                    if doFullCoach {
                        let triggerSummary: String = {
                            if triggers.isEmpty {
                                return "Scheduled progress check (no critical local triggers). Wake=\(reason.rawValue)."
                            }
                            return triggers.map(\.message).joined(separator: " | ")
                        }()

                        if GrokPrivacyConsent.isAccepted, GrokSharedConfig.isLiveConfigured {
                            let reply = await GrokClient.shared.fitnessCheck(
                                brief: makeCoachBrief(digest: digest),
                                triggerSummary: triggerSummary
                            )
                            if reply.isQuotaLock {
                                if let fmSummary = await FoundationModelCoach.summarizeFitnessDigest(
                                    profileName: profile.greetingName,
                                    digestBlock: digest.promptBlock(
                                        preSleepWindowMinutes: prefs.thresholds.preSleepHRWindowMinutes
                                    ) + "\nTriggers: \(triggerSummary)\nNote: \(reply.text)"
                                ) {
                                    lastFitnessCoachReply = fmSummary
                                    GrokFitnessMonitor.storeLastReply(fmSummary)
                                } else if let top = triggers.first {
                                    lastFitnessCoachReply = top.message
                                    GrokFitnessMonitor.storeLastReply(top.message)
                                }
                            } else {
                                lastFitnessCoachReply = reply.text
                                GrokFitnessMonitor.storeLastReply(reply.text)
                            }
                        } else if let fmSummary = await FoundationModelCoach.summarizeFitnessDigest(
                            profileName: profile.greetingName,
                            digestBlock: digest.promptBlock(
                                preSleepWindowMinutes: prefs.thresholds.preSleepHRWindowMinutes
                            ) + "\nTriggers: \(triggerSummary)"
                        ) {
                            lastFitnessCoachReply = fmSummary
                            GrokFitnessMonitor.storeLastReply(fmSummary)
                        } else if let top = triggers.first {
                            lastFitnessCoachReply = top.message
                            GrokFitnessMonitor.storeLastReply(top.message)
                        }
                        prefs.lastAutomatedCheckAt = Date()
                    }

                    fitnessMonitorPreferences = prefs
                    await GrokFitnessMonitor.scheduleIntervalNotification(
                        prefs: prefs,
                        profileName: profile.greetingName
                    )
                    GrokFitnessMonitor.scheduleBackgroundRefresh(prefs: prefs)
                    GrokFitnessMonitor.scheduleBackgroundProcessing(prefs: prefs)
                }

                if wantMorning {
                    await considerMorningWeighDrill(digest: digest)
                }
            }

            if wantTrend {
                let end = Date()
                let start = end.addingTimeInterval(-14 * 86_400)
                let weights = try await healthStore.fetchWeights(from: start, to: end)
                if let newest = weights.last?.value {
                    healthBaselineKg = newest
                }
                historyTrendWindowWeights = weights
                await refreshTrendNotifications()
            } else if wantMorning {
                // refreshTrendNotifications also re-arms morning; when trends are off, still ensure fallback.
                await considerMorningWeighDrill()
            }

            return true
        } catch {
            return false
        }
    }

    /// Start HKObserverQuery + enableBackgroundDelivery after Health auth.
    func armHealthKitBackgroundDelivery() async {
        guard healthKitAvailable else { return }
        await HealthKitBackgroundDelivery.shared.start()
    }

    func refreshTrendNotifications() async {
        await TrendNotificationScheduler.refresh(
            prefs: notificationPreferences,
            profileName: profile.greetingName,
            currentKg: healthBaselineKg,
            idealKg: profile.idealWeightKg,
            recentWeights: historyTrendWindowWeights.isEmpty
                ? historyWeights
                : historyTrendWindowWeights,
            weeklyGoal: weeklyGoal
        )
        await considerMorningWeighDrill()
    }

    /// Load Apple Health weight + body fat samples for the results charts.
    /// Always also loads the last 2 weeks for Trend projection (independent of picker range).
    func loadHistory(for range: HealthHistoryRange = .default) async throws {
        historyRange = range
        guard healthKitAvailable else {
            historyWeights = []
            historyBodyFatPercents = []
            historyTrendWindowWeights = []
            refreshAlreadyWeighedToday()
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
        refreshAlreadyWeighedToday()
    }

    /// Mass-only Manual entry → Apple Health (weight + BMI). No fat/lean invented.
    func saveManualWeight(kg: Double, at date: Date) async throws {
        if let message = ProfileNumericBounds.rejectWeighKgMessage(kg) {
            weighRejectionMessage = message
            throw ScaleWeighValidationError.impossibleWeight(message)
        }
        weighRejectionMessage = nil
        let draft = EditableMeasurementDraft.manual(weightKg: kg, at: date, profile: profile)
        try await healthStore.requestAuthorizationIfNeeded()
        try await healthStore.write(draft: draft, profile: profile)
        phase = .healthKitSuccess
        noteSuccessfulWeighInForReview()
        // Flip Weigh Now off immediately (do not wait on HealthKit read-back).
        markValidWeighInToday(kg: kg)
        await refreshHealthBaseline()
        ensureWeeklyGoalBaseline()
        do {
            try await loadHistory(for: historyRange)
        } catch {
            // Keep optimistic samples; do not wipe today's gate.
        }
        refreshAlreadyWeighedToday()
        MorningWeighDrillScheduler.markSatisfied()
        await refreshTrendNotifications()
        isManualEntryPresented = false
        isWeighInPresented = false
        WeighInLiveActivityController.end()
        isResultsPresented = true
        if MondayCardEngine.shouldOfferAfterWeighIn() {
            await presentMondayCardIfNeeded(weighInKg: kg, force: false, regenerate: false)
        }
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
        if let message = ProfileNumericBounds.rejectWeighKgMessage(kg) {
            weighRejectionMessage = message
            // Keep prior draft mass; do not lock impossible edit into Health path.
            return
        }
        weighRejectionMessage = nil
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
            refreshAlreadyWeighedToday()
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
        refreshAlreadyWeighedToday()
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
        if weighInPurpose == .normal,
           let message = ProfileNumericBounds.rejectWeighKgMessage(draft.weightKg) {
            weighRejectionMessage = message
            liveHint = message
            cancelAutoConfirm()
            phase = .ready
            return
        }
        weighRejectionMessage = nil
        phase = .healthKitWriting
        do {
            try await healthStore.requestAuthorizationIfNeeded()
            try await healthStore.write(draft: draft, profile: profile)
            phase = .healthKitSuccess
            noteSuccessfulWeighInForReview()
            isEditingDraft = false
            if draft.includeCompositionInHealth {
                liveHint = "Saved confirmed weight, BMI, body fat %, and lean mass to Apple Health."
            } else {
                liveHint = "Saved confirmed weight and BMI only. Body fat was not written."
            }
            let weighKg = draft.weightKg
            // Flip Weigh Now off immediately (device-local today; ignore scale clock).
            if ProfileNumericBounds.isPlausibleWeighKg(weighKg) {
                markValidWeighInToday(kg: weighKg)
            }
            await refreshHealthBaseline()
            ensureWeeklyGoalBaseline()
            // Present the dual-chart history screen after a successful Health write.
            do {
                try await loadHistory(for: .default)
            } catch {
                // Soft-fail charts only. Never wipe optimistic today's sample / gate.
            }
            refreshAlreadyWeighedToday()
            MorningWeighDrillScheduler.markSatisfied()
            await refreshTrendNotifications()
            isWeighInPresented = false
            WeighInLiveActivityController.end()
            autoConfirmArmed = false
            // Hero only after confirmed Health save of a plausible kg.
            guard ProfileNumericBounds.isPlausibleWeighKg(weighKg) else {
                weighRejectionMessage = ProfileNumericBounds.rejectWeighKgMessage(weighKg)
                return
            }
            let previous = recentHealthWeights.dropFirst().first?.weightKg ?? healthBaselineKg
            // Prefer prior sample before this write when available.
            let priorKg: Double? = {
                if let first = recentHealthWeights.first, abs(first.weightKg - weighKg) < 0.05 {
                    return recentHealthWeights.dropFirst().first?.weightKg
                }
                return previous
            }()
            lastWeighInAnalysis = WeighInAnalysisEngine.build(
                name: profile.greetingName,
                weighedKg: weighKg,
                previousKg: priorKg,
                weeklyGoal: weeklyGoal,
                idealKg: profile.idealWeightKg,
                profile: profile,
                chartCommentsBlock: ChartCommentStore.analysisPayload(),
                unitSystem: preferredUnits
            )
            rebuildWeeklyGoalSurface()
            let offerMonday = MondayCardEngine.shouldOfferAfterWeighIn()
            pendingMondayAfterHero = offerMonday
            pendingMondayWeighKg = offerMonday ? weighKg : nil
            isWeighInHeroPresented = true
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
            // Live stream only while sheet already open; never hero / auto-confirm off blips.
            liveWeightKg = measurement.weightKg
            if case .listening = phase {
                phase = .measuring
            }
            liveHint = "Live weight updating…"
            syncWeighInLiveActivity(starting: false)
            return
        }

        let calibratedPreview = calibration.apply(toRawKg: measurement.weightKg)
        if weighInPurpose == .normal,
           let message = ProfileNumericBounds.rejectWeighKgMessage(calibratedPreview) {
            weighRejectionMessage = message
            liveHint = message
            cancelAutoConfirm()
            liveWeightKg = measurement.weightKg
            // Do not lock draft / ready / auto-confirm on impossible mass.
            if isWeighInPresented {
                // Keep sheet open with clear rejection; wait for a real reading.
                phase = .measuring
            }
            syncWeighInLiveActivity(starting: false)
            return
        }
        weighRejectionMessage = nil

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

    /// Dynamic Island / Lock Screen Live Activity for the in-progress weigh-in.
    private func syncWeighInLiveActivity(starting: Bool) {
        guard isWeighInPresented else {
            WeighInLiveActivityController.end()
            return
        }
        let name = discoveredScales.first(where: { $0.id == selectedScaleID })?.name
            ?? (weighInPurpose == .calibration ? "Calibration" : "Scale")
        if starting {
            WeighInLiveActivityController.start(scaleName: name, statusLine: liveHint)
        }
        WeighInLiveActivityController.update(
            weightKg: displayWeightKg,
            statusLine: liveHint,
            isSettled: latestMeasurement?.isStabilized == true
        )
    }

    /// One coalesced present. User taps bypass cooldown and already-weighed auto gate.
    private func presentLiveSheetCoalesced(userInitiated: Bool) {
        if isWeighInPresented {
            syncWeighInLiveActivity(starting: false)
            return
        }
        if !userInitiated {
            if isAutoPresentingSheet { return }
            if let until = autoSheetCooldownUntil, Date() < until { return }
            if hasValidWeighInToday() { return }
        }
        isAutoPresentingSheet = true
        isWeighInPresented = true
        isAutoPresentingSheet = false
        syncWeighInLiveActivity(starting: true)
    }

    private var phaseAllowsBLEAutoOpen: Bool {
        switch phase {
        case .scanning, .idle, .healthKitSuccess, .listening, .measuring:
            return true
        default:
            return false
        }
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

enum ScaleWeighValidationError: LocalizedError {
    case impossibleWeight(String)

    var errorDescription: String? {
        switch self {
        case .impossibleWeight(let message):
            return message
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
            isAutoPresentingSheet = false
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

        // Auto-focus strongest scale while passively listening. Do NOT present the sheet
        // on advertisement alone (that caused flicker / races with decode).
        if selectedScaleID == nil,
           !isWeighInPresented,
           weighInPurpose == .normal,
           (phase == .scanning || phase == .idle || phase == .healthKitSuccess),
           let best = discoveredScales.first {
            selectScale(best, presentSheet: false)
        }
    }

    private func handleDecode(_ measurement: ScaleMeasurement) {
        let calibratedKg = calibration.apply(toRawKg: measurement.weightKg)
        let cooldownActive = autoSheetCooldownUntil.map { Date() < $0 } ?? false
        let shouldOpen = Self.shouldAutoPresentLiveSheet(
            isAlreadyPresented: isWeighInPresented,
            isAutoPresenting: isAutoPresentingSheet,
            alreadyWeighedToday: hasValidWeighInToday(),
            purpose: weighInPurpose,
            isEditingDraft: isEditingDraft,
            cooldownActive: cooldownActive,
            measurementStabilized: measurement.isStabilized,
            weightKg: calibratedKg,
            phaseAllowsAutoOpen: phaseAllowsBLEAutoOpen
        )
        if shouldOpen {
            if selectedScaleID == nil, let best = discoveredScales.first {
                selectedScaleID = best.id
                scanner.focus(on: best.id)
            }
            if selectedScaleID != nil || !discoveredScales.isEmpty {
                if selectedScaleID == nil, let best = discoveredScales.first {
                    selectedScaleID = best.id
                    scanner.focus(on: best.id)
                }
                presentLiveSheetCoalesced(userInitiated: false)
            }
        }

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
