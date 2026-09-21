import SwiftUI

/// Three-step first launch: identity → body → confirm (Grok-filled persona) + legal.
/// Designed for low friction: freeform instead of persona form fields; permissions last.
struct OnboardingView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel

    @State private var step = 0
    @State private var name = ""
    @State private var freeform = ""
    @State private var heightCm: Double = 170
    @State private var ageYears: Double = 30
    @State private var sex: UserBodyProfile.Sex = .male
    @State private var idealKg: Double = UserBodyProfile.suggestedIdealWeightKg(heightCm: 170)
    @State private var idealBodyFat: Double? = nil
    @State private var diet: DietPreference = .omnivore
    @State private var location = ""
    @State private var ethnicity = ""
    @State private var preferredLanguage = "English"
    @State private var culturalVibe = ""
    @State private var allowGrokAssist = true
    @State private var acceptedLegal = false
    @State private var enableNotifications = true
    @State private var isInferring = false
    @State private var inferenceNote: String?

    private let lastStep = 2
    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let steel = Color(red: 0.42, green: 0.45, blue: 0.50)
    private let moss = Color(red: 0.12, green: 0.35, blue: 0.28)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.96, blue: 0.98),
                    Color(red: 0.86, green: 0.89, blue: 0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("The Scale")
                    .font(.system(size: 36, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)

                stepDots

                Text(stepTitle)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                Text(stepSubtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(steel)

                Group {
                    switch step {
                    case 0: identityStep
                    case 1: bodyStep
                    default: confirmStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if isInferring {
                Label("Coach is shaping your profile…", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(moss)
            }

            HStack(spacing: 12) {
                    if step > 0 {
                        Button("Back") {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                                step -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    Button(action: advance) {
                        HStack {
                            if isInferring && step == 1 {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(primaryCTA)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ink)
                    .disabled(!canAdvance)
                }
            }
            .padding(28)
        }
        .preferredColorScheme(.light)
        .onAppear {
            seedFromSession()
            if !GrokSharedConfig.isLiveConfigured {
                allowGrokAssist = false
            }
        }
    }

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(0...lastStep, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? moss : steel.opacity(0.25))
                    .frame(width: index == step ? 22 : 8, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)
            }
            Spacer()
            Text("\(step + 1) / 3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(steel)
        }
    }

    private var stepTitle: String {
        switch step {
        case 0: return "Who’s on the scale?"
        case 1: return "Body basics"
        default: return "Looks right?"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case 0:
            return "Name plus a freeform note. Coach fills the rest — no long form."
        case 1:
            return "Only what on-device fat math needs. Ideal weight starts from height."
        default:
            return "Edit anything. Legal once. Then you’re in."
        }
    }

    private var primaryCTA: String {
        switch step {
        case 0: return "Continue"
        case 1: return isInferring ? "Filling profile…" : "Review profile"
        default: return "Start weighing"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 0:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1:
            return heightCm >= 100 && ageYears >= 10 && !isInferring
        default:
            return acceptedLegal && !isInferring
        }
    }

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Your name", text: $name)
                .textContentType(.givenName)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .padding(.vertical, 8)

            Text("About you (optional)")
                .font(.subheadline.weight(.semibold))
            TextField(
                "City, diet, language, vibe, goals… e.g. Filipina in Manila, IF, aiming 62 kg",
                text: $freeform,
                axis: .vertical
            )
            .lineLimit(3...6)
            .padding(12)
            .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if GrokSharedConfig.isLiveConfigured {
                Toggle("Let Coach pre-fill from my note", isOn: $allowGrokAssist)
                    .font(.footnote)
                Text("One setup call. Profile stays on-device. You can change Coach consent later in Settings.")
                    .font(.caption2)
                    .foregroundStyle(steel)
            } else {
                Text("Offline build: we’ll infer what we can on-device from your note.")
                    .font(.caption)
                    .foregroundStyle(steel)
            }
        }
    }

    private var bodyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldRow("Height", unit: "cm", value: $heightCm, fraction: 0)
            fieldRow("Age", unit: "yr", value: $ageYears, fraction: 0)
            Picker("Sex", selection: $sex) {
                ForEach(UserBodyProfile.Sex.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            fieldRow("Ideal weight", unit: "kg", value: $idealKg, fraction: 1)
            Text("Used only for local BIA math and pacing. Never sold.")
                .font(.caption)
                .foregroundStyle(steel)
        }
        .onChange(of: heightCm) { _, newValue in
            if inferenceNote == nil {
                idealKg = UserBodyProfile.suggestedIdealWeightKg(heightCm: newValue)
            }
        }
    }

    private var confirmStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let inferenceNote {
                    Text(inferenceNote)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(moss)
                }

                confirmField("Location", text: $location)
                confirmField("Ethnicity / culture", text: $ethnicity)
                confirmField("Language", text: $preferredLanguage)
                confirmField("Vibe", text: $culturalVibe, axis: true)

                Text("Diet")
                    .font(.subheadline.weight(.semibold))
                Picker("Diet", selection: $diet) {
                    ForEach(DietPreference.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Target body fat % (optional)")
                    Spacer()
                    TextField(
                        "%",
                        value: Binding(
                            get: { idealBodyFat ?? 0 },
                            set: { idealBodyFat = $0 > 0.5 ? $0 : nil }
                        ),
                        format: .number.precision(.fractionLength(1))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                }
                .font(.body)

                Toggle("Bad-trend + weekly goal notifications", isOn: $enableNotifications)
                    .font(.footnote)

                Toggle(
                    "Allow live Grok Coach later",
                    isOn: Binding(
                        get: { allowGrokAssist },
                        set: { allowGrokAssist = $0 }
                    )
                )
                .font(.footnote)
                .disabled(!GrokSharedConfig.isLiveConfigured)

                Toggle("I understand the fitness disclaimer", isOn: $acceptedLegal)
                    .font(.footnote.weight(.semibold))
                Text(CoachCopySanitize.medicalDisclaimer)
                    .font(.caption2)
                    .foregroundStyle(steel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func confirmField(_ title: String, text: Binding<String>, axis: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(steel)
            if axis {
                TextField(title, text: text, axis: .vertical)
                    .lineLimit(2...4)
            } else {
                TextField(title, text: text)
            }
        }
    }

    private func fieldRow(_ title: String, unit: String, value: Binding<Double>, fraction: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                unit,
                value: value,
                format: .number.precision(.fractionLength(fraction))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            Text(unit).foregroundStyle(steel)
        }
        .font(.body)
    }

    private func seedFromSession() {
        name = session.profile.displayName
        heightCm = session.profile.heightCm
        ageYears = session.profile.ageYears
        sex = session.profile.sex
        idealKg = session.profile.idealWeightKg
        idealBodyFat = session.profile.idealBodyFatPercent
        diet = session.profile.dietPreference
        location = session.profile.location
        ethnicity = session.profile.ethnicity
        preferredLanguage = session.profile.preferredLanguage
        culturalVibe = session.profile.culturalVibe
        enableNotifications = session.notificationPreferences.notifyOnBadTrend
    }

    private func advance() {
        switch step {
        case 0:
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                step = 1
            }
        case 1:
            Task { await runInferenceThenConfirm() }
        default:
            finish()
        }
    }

    private func runInferenceThenConfirm() async {
        guard !isInferring else { return }
        isInferring = true
        inferenceNote = nil
        let draft = await GrokClient.shared.inferOnboardingProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            freeform: freeform.trimmingCharacters(in: .whitespacesAndNewlines),
            heightCm: heightCm,
            ageYears: ageYears,
            sex: sex,
            idealKg: idealKg,
            allowNetwork: allowGrokAssist && GrokSharedConfig.isLiveConfigured
        )
        applyInference(draft)
        isInferring = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            step = 2
        }
    }

    private func applyInference(_ draft: OnboardingInferenceDraft) {
        if let d = draft.diet { diet = d }
        if let loc = draft.location, !loc.isEmpty { location = loc }
        if let eth = draft.ethnicity, !eth.isEmpty { ethnicity = eth }
        if let lang = draft.preferredLanguage, !lang.isEmpty { preferredLanguage = lang }
        if let vibe = draft.culturalVibe, !vibe.isEmpty { culturalVibe = vibe }
        if let w = draft.idealWeightKg { idealKg = w }
        if let bf = draft.idealBodyFatPercent { idealBodyFat = bf }

        if draft.sourceLabel == "empty"
            || (freeform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.usedNetwork) {
            inferenceNote = "No note to parse — defaults ready. Edit anything below."
        } else if draft.usedNetwork {
            inferenceNote = "Coach filled these from your note. Edit freely."
        } else {
            inferenceNote = "Filled on-device from your note. Edit freely."
        }
    }

    private func finish() {
        session.profile = UserBodyProfile(
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
            culturalVibe: culturalVibe.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if GrokSharedConfig.isLiveConfigured {
            GrokPrivacyConsent.isAccepted = allowGrokAssist
        }

        var prefs = session.notificationPreferences
        prefs.notifyOnBadTrend = enableNotifications
        prefs.weeklyGoalReminders = enableNotifications
        session.notificationPreferences = prefs

        OnboardingStore.hasCompleted = true
        session.hasCompletedOnboarding = true

        if enableNotifications {
            Task {
                _ = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
                await session.refreshTrendNotifications()
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(ScaleSessionViewModel())
}
