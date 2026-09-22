import Foundation

/// Testable multi-step onboarding state. UI binds to this; inference is injectable.
@MainActor
final class OnboardingFlowModel: ObservableObject {
    enum Step: Int, CaseIterable, Equatable {
        case identity = 0
        case body = 1
        case anatomy = 2
        case dream = 3
        case confirm = 4
    }

    @Published var step: Step = .identity
    @Published var name = ""
    @Published var freeform = ""
    @Published var heightCm: Double = 170
    /// 0 until the user enters age. Must be ≥ `UserBodyProfile.minimumAgeYears`.
    @Published var ageYears: Double = 0
    /// Nil until the user picks male or female on the body step.
    @Published var sex: UserBodyProfile.Sex?
    /// Current / starting weight (kg). Required on anatomy.
    @Published var currentWeightKg: Double = 75
    /// Optional self-reported body fat %.
    @Published var startingBodyFatPercent: Double?
    /// Medical situations, drugs, bad habits.
    @Published var healthContextNotes = ""
    @Published var idealKg: Double = UserBodyProfile.suggestedIdealWeightKg(heightCm: 170)
    @Published var idealBodyFat: Double?
    @Published var goalDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @Published var unitSystem: PreferredUnitSystem = .metric
    @Published var diet: DietPreference = .omnivore
    @Published var location = ""
    @Published var ethnicity = ""
    @Published var preferredLanguage = "English"
    @Published var culturalVibe = ""
    @Published var intermittentFasting: FastingWindow?
    @Published var allowOnDevicePrefill = true
    @Published var allowGrokCoachLater = true
    @Published var acceptedLegal = false
    @Published var enableNotifications = true
    @Published var isInferring = false
    @Published var inferenceNote: String?
    @Published var paceRefusalNote: String?
    @Published var difficultyBand: GoalDifficultyBand?

    /// Inclusive upper bound for onboarding age swipe (18-100).
    static let maximumAgeYears: Double = UserBodyProfile.maximumAgeYears

    var isAdultAge: Bool {
        ageYears >= UserBodyProfile.minimumAgeYears && ageYears <= UserBodyProfile.maximumAgeYears
    }

    var hasChosenGender: Bool { sex != nil }

    var ageValidationMessage: String? {
        guard step == .body, ageYears > 0, !isAdultAge else { return nil }
        if ageYears < UserBodyProfile.minimumAgeYears {
            return "You must be 18 or older."
        }
        if ageYears > UserBodyProfile.maximumAgeYears {
            return "Age max is 100."
        }
        return "Enter a valid age."
    }

    var dreamBoundsKg: ClosedRange<Double> {
        GoalPaceGuard.dreamWeightBoundsKg(currentKg: currentWeightKg, heightCm: heightCm)
    }

    var paceVerdict: GoalPaceVerdict {
        GoalPaceGuard.evaluate(
            currentKg: currentWeightKg,
            targetKg: idealKg,
            goalDate: goalDate
        )
    }

    var canAdvance: Bool {
        switch step {
        case .identity:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .body:
            return isAdultAge && hasChosenGender && !isInferring
        case .anatomy:
            return heightCm >= 100 && heightCm <= 250
                && currentWeightKg >= 30 && currentWeightKg <= 300
                && !isInferring
        case .dream:
            return paceVerdict.status == .accepted && !isInferring
        case .confirm:
            return acceptedLegal && !isInferring
        }
    }

    var primaryCTA: String {
        switch step {
        case .identity: return "Continue"
        case .body: return "Continue"
        case .anatomy: return isInferring ? "Filling profile…" : "Set dream weight"
        case .dream: return "Lock target"
        case .confirm: return "Start weighing"
        }
    }

    var stepCountLabel: String {
        "\(step.rawValue + 1) / \(Step.allCases.count)"
    }

    func seed(from profile: UserBodyProfile, notifications: NotificationPreferences, units: PreferredUnitSystem) {
        name = profile.displayName
        heightCm = profile.heightCm
        idealKg = profile.idealWeightKg
        idealBodyFat = profile.idealBodyFatPercent
        currentWeightKg = profile.startingWeightKg ?? max(profile.idealWeightKg + 8, 60)
        startingBodyFatPercent = profile.startingBodyFatPercent
        healthContextNotes = profile.healthContextNotes
        if let date = profile.goalDate {
            goalDate = date
        }
        unitSystem = units
        diet = profile.dietPreference
        location = profile.location
        ethnicity = profile.ethnicity
        preferredLanguage = profile.preferredLanguage
        culturalVibe = profile.culturalVibe
        intermittentFasting = profile.intermittentFasting
        enableNotifications = notifications.notifyOnBadTrend
        // First launch: force explicit gender + adult age. Re-entry keeps profile values.
        if OnboardingStore.hasCompleted {
            ageYears = profile.ageYears
            sex = profile.sex
            if let title = profile.goalDifficultyTitle {
                let level = GoalDifficultyFlavor.maleTitles.firstIndex(of: title)
                    ?? GoalDifficultyFlavor.femaleTitles.firstIndex(of: title)
                    ?? 0
                difficultyBand = GoalDifficultyFlavor.band(sex: profile.sex, level: level, ratio: nil)
            }
        } else {
            ageYears = 0
            sex = nil
            difficultyBand = nil
        }
        if !FoundationModelAvailability.isAvailable {
            allowOnDevicePrefill = false
        }
        if !GrokSharedConfig.isLiveConfigured {
            allowGrokCoachLater = false
        }
        refreshPaceAndDifficulty()
    }

    func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    /// Advances one step. On anatomy → dream, runs inference first.
    func advance(infer: ((OnboardingFlowModel) async -> OnboardingInferenceDraft)? = nil) async {
        switch step {
        case .identity:
            step = .body
        case .body:
            step = .anatomy
        case .anatomy:
            await runInference(infer: infer)
            clampIdealToBounds()
            refreshPaceAndDifficulty()
            step = .dream
        case .dream:
            guard paceVerdict.status == .accepted else {
                paceRefusalNote = paceVerdict.keelNote
                return
            }
            refreshPaceAndDifficulty()
            step = .confirm
        case .confirm:
            break
        }
    }

    func runInference(infer: ((OnboardingFlowModel) async -> OnboardingInferenceDraft)? = nil) async {
        guard !isInferring else { return }
        isInferring = true
        inferenceNote = nil
        defer { isInferring = false }

        let draft: OnboardingInferenceDraft
        if let infer {
            draft = await infer(self)
        } else {
            draft = await FoundationModelCoach.inferOnboardingProfile(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                freeform: combinedFreeformForInference(),
                heightCm: heightCm,
                ageYears: ageYears,
                sex: sex ?? .male,
                idealKg: idealKg,
                allowOnDeviceModel: allowOnDevicePrefill
            )
        }
        applyInference(draft)
    }

    func applyInference(_ draft: OnboardingInferenceDraft) {
        if let d = draft.diet { diet = d }
        if let loc = draft.location, !loc.isEmpty { location = loc }
        if let eth = draft.ethnicity, !eth.isEmpty { ethnicity = eth }
        if let lang = draft.preferredLanguage, !lang.isEmpty { preferredLanguage = lang }
        if let vibe = draft.culturalVibe, !vibe.isEmpty { culturalVibe = vibe }
        if let fasting = draft.intermittentFasting, fasting.isActive {
            intermittentFasting = fasting
        }
        if let w = draft.idealWeightKg {
            idealKg = w
            clampIdealToBounds()
        }
        if let bf = draft.idealBodyFatPercent { idealBodyFat = bf }

        let emptyNote = combinedFreeformForInference().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if draft.sourceLabel == "empty" || (emptyNote && draft.sourceLabel != "foundation-model") {
            inferenceNote = "No note to parse. Defaults ready. Edit anything below."
        } else if draft.sourceLabel == "foundation-model" {
            inferenceNote = "On-device Coach filled these from your note. Edit freely."
        } else {
            inferenceNote = "Filled on-device from your note. Edit freely."
        }
    }

    func buildProfile() -> UserBodyProfile {
        let clampedAge = min(UserBodyProfile.maximumAgeYears, max(UserBodyProfile.minimumAgeYears, ageYears))
        refreshPaceAndDifficulty()
        return UserBodyProfile(
            displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            heightCm: heightCm,
            ageYears: clampedAge,
            sex: sex ?? .male,
            idealWeightKg: idealKg,
            goalDate: goalDate,
            idealBodyFatPercent: idealBodyFat,
            startingWeightKg: currentWeightKg,
            startingBodyFatPercent: startingBodyFatPercent,
            healthContextNotes: healthContextNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            goalDifficultyTitle: difficultyBand?.title,
            dietPreference: diet,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            ethnicity: ethnicity.trimmingCharacters(in: .whitespacesAndNewlines),
            preferredLanguage: preferredLanguage.trimmingCharacters(in: .whitespacesAndNewlines),
            culturalVibe: culturalVibe.trimmingCharacters(in: .whitespacesAndNewlines),
            intermittentFasting: intermittentFasting?.isActive == true ? intermittentFasting : nil
        )
    }

    /// Live unit toggle: convert already-entered values on the fly. Canonical storage stays metric.
    func applyUnitSystem(_ next: PreferredUnitSystem) {
        guard next != unitSystem else { return }
        unitSystem = next
        // Values are stored in metric; display bindings convert. No numeric rewrite needed.
        // Re-clamp dream weight into bounds after toggle for UX.
        clampIdealToBounds()
        refreshPaceAndDifficulty()
    }

    func updateIdealFromHeightIfNeeded() {
        if inferenceNote == nil, step == .anatomy {
            idealKg = UserBodyProfile.suggestedIdealWeightKg(heightCm: heightCm)
            clampIdealToBounds()
        }
    }

    func refreshPaceAndDifficulty() {
        let verdict = paceVerdict
        if verdict.status == .rejected {
            paceRefusalNote = verdict.keelNote
        } else {
            paceRefusalNote = nil
        }
        guard let sex else {
            difficultyBand = nil
            return
        }
        difficultyBand = GoalDifficultyFlavor.rate(
            sex: sex,
            currentKg: currentWeightKg,
            targetKg: idealKg,
            goalDate: goalDate
        )
    }

    func clampIdealToBounds() {
        let bounds = dreamBoundsKg
        idealKg = min(max(idealKg, bounds.lowerBound), bounds.upperBound)
    }

    /// Seed weekly mini-goal from dream weight + date (AggressiveWeeklyTargetEngine).
    func buildWeeklyMiniGoal(now: Date = Date()) -> WeeklyMiniGoal {
        let aggressive = AggressiveWeeklyTargetEngine.compute(
            currentKg: currentWeightKg,
            idealKg: idealKg,
            goalDate: goalDate,
            priorSundayTargetKg: nil,
            now: now
        )
        return WeeklyMiniGoal(
            targetDeltaKg: aggressive.weeklyDeltaKg,
            weekStartKg: currentWeightKg,
            weekStartDate: now,
            title: String(format: "Sunday %.2f kg", aggressive.sundayTargetKg)
        )
    }

    private func combinedFreeformForInference() -> String {
        let parts = [
            freeform.trimmingCharacters(in: .whitespacesAndNewlines),
            healthContextNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        ].filter { !$0.isEmpty }
        return parts.joined(separator: ". ")
    }
}
