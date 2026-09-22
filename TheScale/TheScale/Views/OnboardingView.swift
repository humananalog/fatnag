import SwiftUI

/// First launch: identity → body (18+ gender) → anatomy → dream weight → confirm.
struct OnboardingView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @StateObject private var flow = OnboardingFlowModel()

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let steel = Color(red: 0.42, green: 0.45, blue: 0.50)
    private let moss = Color(red: 0.12, green: 0.35, blue: 0.28)
    private let warn = Color(red: 0.65, green: 0.12, blue: 0.12)

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
                    .accessibilityIdentifier("onboarding.brand")

                stepDots

                Text(stepTitle)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .accessibilityIdentifier("onboarding.stepTitle")
                Text(stepSubtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(steel)

                Group {
                    switch flow.step {
                    case .identity: identityStep
                    case .body: bodyStep
                    case .anatomy: anatomyStep
                    case .dream: dreamStep
                    case .confirm: confirmStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if flow.isInferring {
                    Label("On-device Coach is shaping your profile…", systemImage: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(moss)
                        .accessibilityIdentifier("onboarding.inferring")
                }

                HStack(spacing: 12) {
                    if flow.step != .identity {
                        Button("Back") {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                                flow.goBack()
                            }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("onboarding.back")
                    }
                    Button {
                        Task { await advance() }
                    } label: {
                        HStack {
                            if flow.isInferring && flow.step == .anatomy {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(flow.primaryCTA)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ink)
                    .disabled(!flow.canAdvance)
                    .accessibilityIdentifier("onboarding.continue")
                }
            }
            .padding(28)
        }
        .preferredColorScheme(.light)
        .onAppear {
            flow.seed(
                from: session.profile,
                notifications: session.notificationPreferences,
                units: session.preferredUnits
            )
        }
    }

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingFlowModel.Step.allCases, id: \.rawValue) { index in
                Capsule()
                    .fill(index.rawValue <= flow.step.rawValue ? moss : steel.opacity(0.25))
                    .frame(width: index == flow.step ? 22 : 8, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: flow.step)
            }
            Spacer()
            Text(flow.stepCountLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(steel)
                .accessibilityIdentifier("onboarding.stepCounter")
        }
    }

    private var stepTitle: String {
        switch flow.step {
        case .identity: return "What this is"
        case .body: return "Body basics"
        case .anatomy: return "Your frame"
        case .dream: return "Dream weight"
        case .confirm: return "Looks right?"
        }
    }

    private var stepSubtitle: String {
        switch flow.step {
        case .identity:
            return "Hard facts up front. Diet is not the main thing. You fail on consistency, small habits, and mind. We help with that. Keel kicks your ass when you get lazy."
        case .body:
            return "Age (18+) and gender. Required for BIA and Coach."
        case .anatomy:
            return "Height, current weight, optional body fat, and anything Keel should know. Units convert live."
        case .dream:
            return "Spin the dial. Pick a date. Impossible rates get a hard Keel no."
        case .confirm:
            return "Edit anything. Legal once. Then you’re in."
        }
    }

    // MARK: - Identity

    private var identityStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                thesisBlock
                weighInPathsBlock

                TextField("Your name", text: $flow.name)
                    .textContentType(.givenName)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("onboarding.name")

                Text("About you (optional)")
                    .font(.subheadline.weight(.semibold))
                TextField(
                    "City, diet, IF 16-8, language, vibe, goals… e.g. Filipina in Manila, IF 16-8, aiming 62 kg",
                    text: $flow.freeform,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .padding(12)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("onboarding.freeform")

                if FoundationModelAvailability.isAvailable {
                    Toggle("Use on-device Coach to pre-fill", isOn: $flow.allowOnDevicePrefill)
                        .font(.footnote)
                        .accessibilityIdentifier("onboarding.fmToggle")
                    Text("Apple Intelligence stays on this iPhone. Heuristics fill in if the model is busy.")
                        .font(.caption2)
                        .foregroundStyle(steel)
                } else {
                    Text(FoundationModelAvailability.statusSummary)
                        .font(.caption)
                        .foregroundStyle(steel)
                    Text("We’ll still parse what we can from your note on-device.")
                        .font(.caption2)
                        .foregroundStyle(steel)
                }
            }
        }
    }

    private var thesisBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The Scale")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(moss)
                .accessibilityIdentifier("onboarding.thesis.eyebrow")
            Text("Consistency coach. Not another diet app.")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.thesis.headline")
            Text("Weigh-ins and charts are the scoreboard. The real game is small habits and not quitting when you’re bored. We call that out.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(steel)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.thesis.body")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var weighInPathsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How you weigh. Your choice.")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .accessibilityIdentifier("onboarding.weighPaths.title")
            weighPathRow(
                number: "1",
                title: "Apple Health scale",
                body: "Already got a smart scale dumping into Health? We read it. No new gadgets required."
            )
            weighPathRow(
                number: "2",
                title: "Bluetooth scale",
                body: "Pair something like a Xiaomi Mi Body Composition Scale. Each weigh-in syncs here."
            )
            weighPathRow(
                number: "3",
                title: "Full manual",
                body: "No scale drama. Type the number yourself. Still counts."
            )
            Text("Weigh every day. That’s how the habit starts, and how you kill the fear of the number going up.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
                .accessibilityIdentifier("onboarding.weighPaths.daily")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("onboarding.weighPaths")
    }

    private func weighPathRow(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(ink, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                Text(body)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(steel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Body (gender + age)

    private var bodyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                fieldRow("Age", unit: "yr", value: $flow.ageYears, fraction: 0, id: "onboarding.age")
                Text("18 or older. Required.")
                    .font(.caption)
                    .foregroundStyle(steel)
                if let ageMsg = flow.ageValidationMessage {
                    Text(ageMsg)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(warn)
                        .accessibilityIdentifier("onboarding.age.error")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Gender")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ink)
                HStack(spacing: 10) {
                    genderChip(.male)
                    genderChip(.female)
                }
                .accessibilityIdentifier("onboarding.sex")
                if !flow.hasChosenGender {
                    Text("Required.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(steel)
                        .accessibilityIdentifier("onboarding.sex.required")
                }
            }
        }
    }

    private func genderChip(_ value: UserBodyProfile.Sex) -> some View {
        let selected = flow.sex == value
        return Button {
            flow.sex = value
            flow.refreshPaceAndDifficulty()
        } label: {
            Text(value.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(selected ? Color.white : ink)
                .background(
                    selected ? ink : Color.white.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ink.opacity(selected ? 0 : 0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.sex.\(value.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Anatomy

    private var anatomyStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                unitToggle(id: "onboarding.anatomy.units")

                unitAwareField(
                    title: "Height",
                    display: Binding(
                        get: { UnitFormat.height(fromCm: flow.heightCm, system: flow.unitSystem) },
                        set: { flow.heightCm = UnitFormat.cm(fromHeight: $0, system: flow.unitSystem) }
                    ),
                    unit: flow.unitSystem.heightLabel,
                    fraction: flow.unitSystem == .metric ? 0 : 1,
                    id: "onboarding.height"
                )

                unitAwareField(
                    title: "Current weight",
                    display: Binding(
                        get: { UnitFormat.mass(fromKg: flow.currentWeightKg, system: flow.unitSystem) },
                        set: { flow.currentWeightKg = UnitFormat.kg(fromMass: $0, system: flow.unitSystem) }
                    ),
                    unit: flow.unitSystem.massLabel,
                    fraction: 1,
                    id: "onboarding.currentWeight"
                )

                HStack {
                    Text("Body fat % (optional)")
                    Spacer()
                    TextField(
                        "%",
                        value: Binding(
                            get: { flow.startingBodyFatPercent ?? 0 },
                            set: { flow.startingBodyFatPercent = $0 > 0.5 ? $0 : nil }
                        ),
                        format: .number.precision(.fractionLength(1))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .accessibilityIdentifier("onboarding.startingBodyFat")
                    Text("%").foregroundStyle(steel)
                }
                .font(.body)

                Text("Medical / habits (optional)")
                    .font(.subheadline.weight(.semibold))
                TextField(
                    "Injuries, meds, alcohol, sleep chaos… Keel reads this. Not a diagnosis.",
                    text: $flow.healthContextNotes,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .padding(12)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("onboarding.healthContext")
            }
            .onChange(of: flow.heightCm) { _, _ in
                flow.updateIdealFromHeightIfNeeded()
            }
            .onChange(of: flow.currentWeightKg) { _, _ in
                flow.clampIdealToBounds()
                flow.refreshPaceAndDifficulty()
            }
        }
    }

    // MARK: - Dream weight

    private var dreamStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                unitToggle(id: "onboarding.dream.units")

                AnalogDreamScaleView(
                    weightKg: Binding(
                        get: { flow.idealKg },
                        set: { next in
                            flow.idealKg = next
                            flow.refreshPaceAndDifficulty()
                        }
                    ),
                    boundsKg: flow.dreamBoundsKg,
                    unitSystem: flow.unitSystem,
                    ink: ink,
                    steel: steel,
                    accent: moss
                )
                .frame(maxWidth: .infinity)

                DatePicker(
                    "Target date",
                    selection: Binding(
                        get: { flow.goalDate },
                        set: { next in
                            flow.goalDate = next
                            flow.refreshPaceAndDifficulty()
                        }
                    ),
                    in: Date()...,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("onboarding.goalDate")

                if let refusal = flow.paceRefusalNote {
                    Text(refusal)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(warn)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(warn.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("onboarding.paceRefusal")
                } else if let band = flow.difficultyBand {
                    Text(band.revealLine)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(moss)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(moss.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("onboarding.difficultyReveal")
                }

                Text("Weekly + meal engines use this dream weight and date. Biology caps beat bravado.")
                    .font(.caption)
                    .foregroundStyle(steel)
            }
        }
    }

    // MARK: - Confirm

    private var confirmStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let band = flow.difficultyBand {
                    Text(band.revealLine)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(moss)
                        .accessibilityIdentifier("onboarding.confirm.difficulty")
                }

                if let note = flow.inferenceNote {
                    Text(note)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(moss)
                        .accessibilityIdentifier("onboarding.inferenceNote")
                }

                confirmField("Location", text: $flow.location, id: "onboarding.location")
                confirmField("Ethnicity / culture", text: $flow.ethnicity, id: "onboarding.ethnicity")
                confirmField("Language", text: $flow.preferredLanguage, id: "onboarding.language")
                confirmField("Vibe", text: $flow.culturalVibe, axis: true, id: "onboarding.vibe")

                Text("Diet")
                    .font(.subheadline.weight(.semibold))
                Picker("Diet", selection: $flow.diet) {
                    ForEach(DietPreference.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("onboarding.diet")

                if let fasting = flow.intermittentFasting, fasting.isActive {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Intermittent fasting")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            "\(fasting.protocolLabel) · eating \(MealPlanEngine.formatHour(fasting.eatingStartHour))-\(MealPlanEngine.formatHour(fasting.eatingEndHour)) · \(fasting.fastingHours)h fast"
                        )
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(steel)
                        .accessibilityIdentifier("onboarding.ifWindow")
                    }
                }

                HStack {
                    Text("Target body fat % (optional)")
                    Spacer()
                    TextField(
                        "%",
                        value: Binding(
                            get: { flow.idealBodyFat ?? 0 },
                            set: { flow.idealBodyFat = $0 > 0.5 ? $0 : nil }
                        ),
                        format: .number.precision(.fractionLength(1))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .accessibilityIdentifier("onboarding.bodyFat")
                }
                .font(.body)

                Text(
                    "Dream \(UnitFormat.massString(flow.idealKg, system: flow.unitSystem)) by \(flow.goalDate.formatted(date: .abbreviated, time: .omitted))"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ink)
                .accessibilityIdentifier("onboarding.confirm.dreamSummary")

                Toggle("Bad-trend + weekly goal notifications", isOn: $flow.enableNotifications)
                    .font(.footnote)
                    .accessibilityIdentifier("onboarding.notifications")

                Toggle(CoachPersona.onboardingLiveToggleTitle, isOn: $flow.allowGrokCoachLater)
                    .font(.footnote)
                    .disabled(!GrokSharedConfig.isLiveConfigured)
                    .accessibilityIdentifier("onboarding.grokLater")

                Toggle("I understand the fitness disclaimer", isOn: $flow.acceptedLegal)
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("onboarding.legal")
                Text(CoachCopySanitize.medicalDisclaimer)
                    .font(.caption2)
                    .foregroundStyle(steel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Shared controls

    private func unitToggle(id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Units", selection: Binding(
                get: { flow.unitSystem },
                set: { flow.applyUnitSystem($0) }
            )) {
                ForEach(PreferredUnitSystem.allCases) { system in
                    Text(system.shortTitle).tag(system)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(id)
            Text("Numbers convert live. Health stays metric under the hood.")
                .font(.caption2)
                .foregroundStyle(steel)
        }
    }

    private func confirmField(_ title: String, text: Binding<String>, axis: Bool = false, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(steel)
            if axis {
                TextField(title, text: text, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityIdentifier(id)
            } else {
                TextField(title, text: text)
                    .accessibilityIdentifier(id)
            }
        }
    }

    private func fieldRow(
        _ title: String,
        unit: String,
        value: Binding<Double>,
        fraction: Int,
        id: String
    ) -> some View {
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
            .accessibilityIdentifier(id)
            Text(unit).foregroundStyle(steel)
        }
        .font(.body)
    }

    private func unitAwareField(
        title: String,
        display: Binding<Double>,
        unit: String,
        fraction: Int,
        id: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                unit,
                value: display,
                format: .number.precision(.fractionLength(fraction))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            .accessibilityIdentifier(id)
            Text(unit).foregroundStyle(steel)
        }
        .font(.body)
    }

    private func advance() async {
        switch flow.step {
        case .identity:
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                flow.step = .body
            }
        case .body:
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                flow.step = .anatomy
            }
        case .anatomy:
            await flow.runInference()
            flow.clampIdealToBounds()
            flow.refreshPaceAndDifficulty()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                flow.step = .dream
            }
        case .dream:
            flow.refreshPaceAndDifficulty()
            guard flow.paceVerdict.status == .accepted else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                flow.step = .confirm
            }
        case .confirm:
            finish()
        }
    }

    private func finish() {
        let profile = flow.buildProfile()
        session.profile = profile
        session.preferredUnits = flow.unitSystem
        session.weeklyGoal = flow.buildWeeklyMiniGoal()
        session.rebuildWeeklyGoalSurface()

        if let fasting = profile.intermittentFasting, fasting.isActive {
            let open = MealPlanEngine.formatHour(fasting.eatingStartHour)
            let close = MealPlanEngine.formatHour(fasting.eatingEndHour)
            CoachMemoryStore.remember(
                CoachMemoryFact(
                    text: "Intermittent fasting \(fasting.protocolLabel). Eating window \(open)-\(close) local (eatingWindowStart=\(fasting.eatingWindowStart), eatingWindowEnd=\(fasting.eatingWindowEnd)).",
                    tags: ["fasting", "diet", fasting.protocolLabel]
                )
            )
            session.clearMealPlanCache()
        }

        let health = profile.healthContextNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !health.isEmpty {
            CoachMemoryStore.remember(
                CoachMemoryFact(
                    text: "Health context from onboarding: \(health)",
                    tags: ["health", "onboarding", "context"]
                )
            )
        }
        if let band = flow.difficultyBand {
            CoachMemoryStore.remember(
                CoachMemoryFact(
                    text: band.coachTag + ". " + band.revealLine,
                    tags: ["goal", "difficulty", band.title]
                )
            )
        }
        CoachMemoryStore.remember(
            CoachMemoryFact(
                text: String(
                    format: "Dream weight %.1f kg by %@. Starting %.1f kg.",
                    profile.idealWeightKg,
                    (profile.goalDate ?? flow.goalDate).formatted(date: .abbreviated, time: .omitted),
                    profile.startingWeightKg ?? flow.currentWeightKg
                ),
                tags: ["goal", "weight", "onboarding"]
            )
        )

        if GrokSharedConfig.isLiveConfigured {
            GrokPrivacyConsent.isAccepted = flow.allowGrokCoachLater
        }
        var prefs = session.notificationPreferences
        prefs.notifyOnBadTrend = flow.enableNotifications
        prefs.weeklyGoalReminders = flow.enableNotifications
        session.notificationPreferences = prefs
        OnboardingStore.hasCompleted = true
        session.hasCompletedOnboarding = true
        if flow.enableNotifications {
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
