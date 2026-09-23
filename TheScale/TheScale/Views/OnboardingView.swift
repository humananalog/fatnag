import SwiftUI

/// First launch: identity → body → anatomy → dream → lifestyle → confirm.
/// Every step is one screenfit page on iPhone 15. Hard facts. Short lines.
struct OnboardingView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @StateObject private var flow = OnboardingFlowModel()

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let steel = Color(red: 0.42, green: 0.45, blue: 0.50)
    private let moss = Color(red: 0.12, green: 0.35, blue: 0.28)
    private let warn = Color(red: 0.65, green: 0.12, blue: 0.12)

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 780
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

                VStack(alignment: .leading, spacing: compact ? 10 : 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("The Scale")
                            .font(.system(size: compact ? 28 : 32, weight: .semibold, design: .serif))
                            .foregroundStyle(ink)
                            .accessibilityIdentifier("onboarding.brand")
                        Spacer(minLength: 8)
                        stepDots
                    }

                    Text(stepTitle)
                        .font(.system(size: compact ? 17 : 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                        .accessibilityIdentifier("onboarding.stepTitle")
                    Text(stepSubtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(steel)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Group {
                        switch flow.step {
                        case .identity: identityStep(compact: compact)
                        case .body: bodyStep(compact: compact)
                        case .anatomy: anatomyStep(compact: compact)
                        case .dream: dreamStep(compact: compact)
                        case .lifestyle: lifestyleStep(compact: compact)
                        case .confirm: confirmStep(compact: compact)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    if flow.isInferring {
                        Text("Shaping profile…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(moss)
                            .accessibilityIdentifier("onboarding.inferring")
                    }

                    HStack(spacing: 10) {
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
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
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
        HStack(spacing: 6) {
            ForEach(OnboardingFlowModel.Step.allCases, id: \.rawValue) { index in
                Capsule()
                    .fill(index.rawValue <= flow.step.rawValue ? moss : steel.opacity(0.25))
                    .frame(width: index == flow.step ? 16 : 6, height: 5)
            }
            Text(flow.stepCountLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(steel)
                .accessibilityIdentifier("onboarding.stepCounter")
        }
    }

    private var stepTitle: String {
        switch flow.step {
        case .identity: return "Mission"
        case .body: return "Body"
        case .anatomy: return "Frame"
        case .dream: return "Dream weight"
        case .lifestyle: return "Food & place"
        case .confirm: return "Lock in"
        }
    }

    private var stepSubtitle: String {
        switch flow.step {
        case .identity: return "Consistency coach. Not a diet app."
        case .body: return "18+. Required for BIA and Keel."
        case .anatomy: return "Height, weight, optional BF%. Units live-convert."
        case .dream: return "Drag the disc. Impossible pace gets a hard no."
        case .lifestyle: return "Optional. Leave blank; we may ask gently later."
        case .confirm: return "Legal once. Then weigh."
        }
    }

    private func vectorArt(_ name: String, height: CGFloat) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }

    // MARK: - Identity

    private func identityStep(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            vectorArt("OnboardingVectorIdentity", height: compact ? 72 : 96)

            HStack(spacing: 8) {
                factChip("Health")
                factChip("Bluetooth")
                factChip("Manual")
            }
            .accessibilityIdentifier("onboarding.weighPaths")

            Text("Weigh daily. Kill the fear of the number.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .accessibilityIdentifier("onboarding.weighPaths.daily")

            TextField("Your name", text: $flow.name)
                .textContentType(.givenName)
                .font(.system(size: compact ? 24 : 28, weight: .semibold, design: .rounded))
                .padding(.vertical, 4)
                .accessibilityIdentifier("onboarding.name")

            TextField(
                "City, IF 16-8, language…",
                text: $flow.freeform,
                axis: .vertical
            )
            .lineLimit(2...3)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .padding(10)
            .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityIdentifier("onboarding.freeform")

            if FoundationModelAvailability.isAvailable {
                Toggle("On-device pre-fill", isOn: $flow.allowOnDevicePrefill)
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("onboarding.fmToggle")
            }

            Spacer(minLength: 0)
        }
    }

    private func factChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.75), in: Capsule())
            .overlay(Capsule().strokeBorder(ink.opacity(0.14), lineWidth: 1))
    }

    // MARK: - Body

    private func bodyStep(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            vectorArt("OnboardingVectorBody", height: compact ? 64 : 80)

            AgeSwipeControl(
                ageYears: Binding(
                    get: { flow.ageYears },
                    set: { flow.ageYears = $0 }
                ),
                ink: ink,
                steel: steel,
                accent: moss
            )

            if let ageMsg = flow.ageValidationMessage {
                Text(ageMsg)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(warn)
                    .accessibilityIdentifier("onboarding.age.error")
            }

            Text("GENDER")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(steel)

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

            Spacer(minLength: 0)
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

    private func anatomyStep(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            vectorArt("OnboardingVectorAnatomy", height: compact ? 56 : 72)

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
                title: "Weight",
                display: Binding(
                    get: { UnitFormat.mass(fromKg: flow.currentWeightKg, system: flow.unitSystem) },
                    set: { flow.currentWeightKg = UnitFormat.kg(fromMass: $0, system: flow.unitSystem) }
                ),
                unit: flow.unitSystem.massLabel,
                fraction: 1,
                id: "onboarding.currentWeight"
            )

            HStack {
                Text("BF% (opt)")
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
                .frame(width: 56)
                .accessibilityIdentifier("onboarding.startingBodyFat")
                Text("%").foregroundStyle(steel)
            }
            .font(.body.weight(.medium))

            TextField(
                "Medical / habits (opt)",
                text: $flow.healthContextNotes,
                axis: .vertical
            )
            .lineLimit(2...3)
            .padding(10)
            .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityIdentifier("onboarding.healthContext")

            Spacer(minLength: 0)
        }
        .onChange(of: flow.heightCm) { _, _ in
            flow.updateIdealFromHeightIfNeeded()
        }
        .onChange(of: flow.currentWeightKg) { _, _ in
            flow.clampIdealToBounds()
            flow.refreshPaceAndDifficulty()
        }
    }

    // MARK: - Dream

    private func dreamStep(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if !compact {
                vectorArt("OnboardingVectorDream", height: 56)
            }

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
                "Target",
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(warn)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(warn.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("onboarding.paceRefusal")
            } else if let band = flow.difficultyBand {
                Text(band.revealLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(moss)
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(moss.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("onboarding.difficultyReveal")
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Lifestyle (optional diet / location / avoid)

    private func lifestyleStep(compact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 10 : 12) {
                Text("Diet preference")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(steel)
                    .accessibilityIdentifier("onboarding.lifestyle.dietLabel")

                Picker("Diet", selection: Binding(
                    get: { flow.diet },
                    set: { flow.diet = $0; flow.markDietConfirmed() }
                )) {
                    ForEach(DietPreference.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("onboarding.diet")

                Text("Location")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(steel)
                    .padding(.top, 4)

                TextField("City or area (e.g. Manila, Central HK)", text: $flow.location)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("onboarding.location")

                Toggle(isOn: $flow.useLocalContext) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use for local food and fitness")
                            .font(.footnote.weight(.semibold))
                        Text("Picks nearby markets, meal staples, and fitness options when on.")
                            .font(.caption2)
                            .foregroundStyle(steel)
                    }
                }
                .accessibilityIdentifier("onboarding.useLocalContext")

                Text("Avoid")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(steel)
                    .padding(.top, 4)

                TextField("Allergies and hard nos (peanuts, shellfish…)", text: $flow.foodAvoidances, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("onboarding.foodAvoidances")

                Text("Blank is fine. We may ask once in a while at key moments, never every day.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(steel)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.lifestyle.softHint")

                if let fasting = flow.intermittentFasting, fasting.isActive {
                    Text(
                        "\(fasting.protocolLabel) · \(MealPlanEngine.formatHour(fasting.eatingStartHour))-\(MealPlanEngine.formatHour(fasting.eatingEndHour))"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(moss)
                    .accessibilityIdentifier("onboarding.ifWindow")
                }
            }
        }
    }

    // MARK: - Confirm

    private func confirmStep(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            vectorArt("OnboardingVectorConfirm", height: compact ? 48 : 64)

            if let band = flow.difficultyBand {
                Text(band.revealLine)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(moss)
                    .lineLimit(2)
                    .accessibilityIdentifier("onboarding.confirm.difficulty")
            }

            if let note = flow.inferenceNote {
                Text(note)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(moss)
                    .lineLimit(2)
                    .accessibilityIdentifier("onboarding.inferenceNote")
            }

            lifestyleSummaryChip

            confirmMini("Lang", text: $flow.preferredLanguage, id: "onboarding.language")

            Text(
                "Dream \(UnitFormat.massString(flow.idealKg, system: flow.unitSystem)) by \(flow.goalDate.formatted(date: .abbreviated, time: .omitted))"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(ink)
            .accessibilityIdentifier("onboarding.confirm.dreamSummary")

            Toggle("Alerts", isOn: $flow.enableNotifications)
                .font(.footnote.weight(.semibold))
                .accessibilityIdentifier("onboarding.notifications")

            Toggle(CoachPersona.onboardingLiveToggleTitle, isOn: $flow.allowGrokCoachLater)
                .font(.footnote.weight(.semibold))
                .disabled(!GrokSharedConfig.isLiveConfigured)
                .accessibilityIdentifier("onboarding.grokLater")

            Toggle("I agree to Terms, Privacy Policy, and the fitness disclaimer", isOn: $flow.acceptedLegal)
                .font(.footnote.weight(.semibold))
                .accessibilityIdentifier("onboarding.legal")

            Text(CoachCopySanitize.medicalDisclaimer)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(steel)
                .lineLimit(3)
                .minimumScaleFactor(0.8)

            Text("Full Terms and Privacy are in Settings after launch. Age \(ScaleLegal.minimumAgeYears)+ required.")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(steel)

            Spacer(minLength: 0)
        }
    }

    private var lifestyleSummaryChip: some View {
        let loc = flow.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let avoid = flow.foodAvoidances.trimmingCharacters(in: .whitespacesAndNewlines)
        let dietBit = flow.dietConfirmed ? flow.diet.title : "Diet TBD"
        let locBit = loc.isEmpty ? "Location TBD" : loc
        let avoidBit = avoid.isEmpty ? "No avoids yet" : "Avoid: \(avoid)"
        return Text("\(dietBit) · \(locBit) · \(avoidBit)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(steel)
            .lineLimit(2)
            .accessibilityIdentifier("onboarding.confirm.lifestyleSummary")
    }

    // MARK: - Shared

    private func unitToggle(id: String) -> some View {
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
    }

    private func confirmMini(_ title: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(steel)
            TextField(title, text: text)
                .font(.footnote.weight(.medium))
                .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .frame(width: 72)
            .accessibilityIdentifier(id)
            Text(unit).foregroundStyle(steel)
        }
        .font(.body.weight(.medium))
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
                flow.step = .lifestyle
            }
        case .lifestyle:
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
        LegalAcceptanceStore.markAccepted()
        var prefs = session.notificationPreferences
        prefs.notifyOnBadTrend = flow.enableNotifications
        prefs.weeklyGoalReminders = flow.enableNotifications
        // Keep morning drill aligned with the Alerts toggle (defaults stay on when Alerts is on).
        prefs.morningWeighDrill = flow.enableNotifications
        session.notificationPreferences = prefs
        OnboardingStore.hasCompleted = true
        session.hasCompletedOnboarding = true
        if flow.enableNotifications {
            Task {
                _ = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
                await session.refreshTrendNotifications()
            }
        } else {
            MorningWeighDrillScheduler.cancelAllPending()
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(ScaleSessionViewModel())
}
