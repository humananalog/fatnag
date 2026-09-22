import Foundation

/// Testable 3-step onboarding state. UI binds to this; inference is injectable.
@MainActor
final class OnboardingFlowModel: ObservableObject {
    enum Step: Int, CaseIterable, Equatable {
        case identity = 0
        case body = 1
        case confirm = 2
    }

    @Published var step: Step = .identity
    @Published var name = ""
    @Published var freeform = ""
    @Published var heightCm: Double = 170
    /// 0 until the user enters age. Must be ≥ `UserBodyProfile.minimumAgeYears`.
    @Published var ageYears: Double = 0
    /// Nil until the user picks male or female on the body step.
    @Published var sex: UserBodyProfile.Sex?
    @Published var idealKg: Double = UserBodyProfile.suggestedIdealWeightKg(heightCm: 170)
    @Published var idealBodyFat: Double?
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

    var isAdultAge: Bool {
        ageYears >= UserBodyProfile.minimumAgeYears && ageYears <= 120
    }

    var hasChosenGender: Bool { sex != nil }

    var ageValidationMessage: String? {
        guard step == .body, ageYears > 0, !isAdultAge else { return nil }
        if ageYears < UserBodyProfile.minimumAgeYears {
            return "You must be 18 or older."
        }
        return "Enter a valid age."
    }

    var canAdvance: Bool {
        switch step {
        case .identity:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .body:
            return heightCm >= 100 && isAdultAge && hasChosenGender && !isInferring
        case .confirm:
            return acceptedLegal && !isInferring
        }
    }

    var primaryCTA: String {
        switch step {
        case .identity: return "Continue"
        case .body: return isInferring ? "Filling profile…" : "Review profile"
        case .confirm: return "Start weighing"
        }
    }

    func seed(from profile: UserBodyProfile, notifications: NotificationPreferences) {
        name = profile.displayName
        heightCm = profile.heightCm
        idealKg = profile.idealWeightKg
        idealBodyFat = profile.idealBodyFatPercent
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
        } else {
            ageYears = 0
            sex = nil
        }
        if !FoundationModelAvailability.isAvailable {
            allowOnDevicePrefill = false
        }
        if !GrokSharedConfig.isLiveConfigured {
            allowGrokCoachLater = false
        }
    }

    func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    /// Advances one step. On body → confirm, runs inference first.
    func advance(infer: ((OnboardingFlowModel) async -> OnboardingInferenceDraft)? = nil) async {
        switch step {
        case .identity:
            step = .body
        case .body:
            await runInference(infer: infer)
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
                freeform: freeform.trimmingCharacters(in: .whitespacesAndNewlines),
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
        if let w = draft.idealWeightKg { idealKg = w }
        if let bf = draft.idealBodyFatPercent { idealBodyFat = bf }

        let emptyNote = freeform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if draft.sourceLabel == "empty" || (emptyNote && draft.sourceLabel != "foundation-model") {
            inferenceNote = "No note to parse. Defaults ready. Edit anything below."
        } else if draft.sourceLabel == "foundation-model" {
            inferenceNote = "On-device Coach filled these from your note. Edit freely."
        } else {
            inferenceNote = "Filled on-device from your note. Edit freely."
        }
    }

    func buildProfile() -> UserBodyProfile {
        let clampedAge = min(120, max(UserBodyProfile.minimumAgeYears, ageYears))
        return UserBodyProfile(
            displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            heightCm: heightCm,
            ageYears: clampedAge,
            sex: sex ?? .male,
            idealWeightKg: idealKg,
            idealBodyFatPercent: idealBodyFat,
            dietPreference: diet,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            ethnicity: ethnicity.trimmingCharacters(in: .whitespacesAndNewlines),
            preferredLanguage: preferredLanguage.trimmingCharacters(in: .whitespacesAndNewlines),
            culturalVibe: culturalVibe.trimmingCharacters(in: .whitespacesAndNewlines),
            intermittentFasting: intermittentFasting?.isActive == true ? intermittentFasting : nil
        )
    }

    func updateIdealFromHeightIfNeeded() {
        if inferenceNote == nil {
            idealKg = UserBodyProfile.suggestedIdealWeightKg(heightCm: heightCm)
        }
    }
}
