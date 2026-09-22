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
    @Published var ageYears: Double = 30
    @Published var sex: UserBodyProfile.Sex = .male
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

    var canAdvance: Bool {
        switch step {
        case .identity:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .body:
            return heightCm >= 100 && ageYears >= 10 && !isInferring
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
        ageYears = profile.ageYears
        sex = profile.sex
        idealKg = profile.idealWeightKg
        idealBodyFat = profile.idealBodyFatPercent
        diet = profile.dietPreference
        location = profile.location
        ethnicity = profile.ethnicity
        preferredLanguage = profile.preferredLanguage
        culturalVibe = profile.culturalVibe
        intermittentFasting = profile.intermittentFasting
        enableNotifications = notifications.notifyOnBadTrend
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
                sex: sex,
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
            inferenceNote = "No note to parse — defaults ready. Edit anything below."
        } else if draft.sourceLabel == "foundation-model" {
            inferenceNote = "On-device Coach filled these from your note. Edit freely."
        } else {
            inferenceNote = "Filled on-device from your note. Edit freely."
        }
    }

    func buildProfile() -> UserBodyProfile {
        UserBodyProfile(
            displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            heightCm: heightCm,
            ageYears: ageYears,
            sex: sex,
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
