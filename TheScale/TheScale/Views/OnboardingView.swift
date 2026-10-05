import SwiftUI
import UIKit

/// First launch: language → units → identity → body → anatomy → dream → lifestyle → confirm.
/// Every step is one screenfit page. One instruction, one primary input.
struct OnboardingView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var flow = OnboardingFlowModel()
    @State private var healthWeight: HealthMetricSample?
    @State private var healthWeightResolved = false
    @State private var adjustWeightOnScale = false
    @FocusState private var nameFieldFocused: Bool

    private var compact: Bool { verticalSizeClass == .compact }

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let steel = Color(red: 0.42, green: 0.45, blue: 0.50)
    private let moss = Color(red: 0.12, green: 0.35, blue: 0.28)
    private let warn = Color(red: 0.65, green: 0.12, blue: 0.12)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                journeyHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                Group {
                    switch flow.step {
                    case .language: languageStep(compact: compact)
                    case .units: unitsStep(compact: compact)
                    case .identity: identityStep(compact: compact)
                    case .body: bodyStep(compact: compact)
                    case .anatomy: anatomyStep(compact: compact)
                    case .dream: dreamStep(compact: compact)
                    case .lifestyle: lifestyleStep(compact: compact)
                    case .confirm: confirmStep(compact: compact)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 20)
                .id(flow.appLanguage.rawValue)

                if flow.isInferring {
                    Text(AppLanguageStore.text("onboarding.shaping", default: "Shaping profile…"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(moss)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                        .accessibilityIdentifier("onboarding.inferring")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                continueBar
            }
            .background {
                LinearGradient(
                    colors: [
                        Color(red: 0.94, green: 0.96, blue: 0.98),
                        Color(red: 0.86, green: 0.89, blue: 0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(AppLanguageStore.text("common.done", default: "Done")) {
                        dismissKeyboard()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("onboarding.keyboardDone")
                }
            }
        }
        .preferredColorScheme(.light)
        .environment(\.locale, flow.appLanguage.locale)
        .environment(\.layoutDirection, flow.appLanguage.layoutDirection)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            flow.seed(
                from: session.profile,
                notifications: session.notificationPreferences,
                units: session.preferredUnits
            )
        }
        .task(id: flow.step) {
            await resolveHealthWeightIfNeeded()
            if flow.step == .identity {
                // Let the page settle, then focus so the keyboard does not fight the first paint.
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, flow.step == .identity else { return }
                nameFieldFocused = true
            } else {
                nameFieldFocused = false
            }
        }
    }

    private var journeyHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                FatnagWordmark(size: compact ? 26 : 30, color: ink)
                    .accessibilityIdentifier("onboarding.brand")
                Spacer(minLength: 12)
                if session.isOnboardingReplay {
                    Button(AppLanguageStore.text("onboarding.cancel", default: "Cancel")) {
                        dismissKeyboard()
                        session.isOnboardingReplay = false
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.85), in: Capsule())
                    .accessibilityIdentifier("onboarding.cancelReplay")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(stepTitle)
                        .font(.system(size: compact ? 22 : 26, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("onboarding.stepTitle")
                    Spacer(minLength: 8)
                    Text("\(flow.step.rawValue + 1) of \(OnboardingFlowModel.Step.allCases.count)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(steel)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.8), in: Capsule())
                        .accessibilityIdentifier("onboarding.stepCounter")
                }

                HStack(spacing: 5) {
                    ForEach(OnboardingFlowModel.Step.allCases, id: \.rawValue) { index in
                        Capsule()
                            .fill(index.rawValue <= flow.step.rawValue ? moss : steel.opacity(0.22))
                            .frame(height: 5)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)

                if !stepSubtitle.isEmpty {
                    Text(stepSubtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(steel)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("onboarding.stepSubtitle")
                }
            }
        }
    }

    private var continueBar: some View {
        VStack(spacing: 8) {
            if flow.step == .units, !flow.canAdvance {
                Text(AppLanguageStore.text(
                    "onboarding.units.need_choice",
                    default: "Choose kg or lb, then tap Next."
                ))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(steel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("onboarding.units.needChoice")
            }
            if flow.step == .identity, !flow.canAdvance {
                Text(AppLanguageStore.text(
                    "onboarding.identity.need_name",
                    default: "Type your name, then tap Next."
                ))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(steel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("onboarding.identity.needName")
            }
            HStack(spacing: 10) {
                if flow.step != .language {
                    Button(AppLanguageStore.text("onboarding.back", default: "Back")) {
                        dismissKeyboard()
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                            flow.goBack()
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("onboarding.back")
                }
                Button {
                    dismissKeyboard()
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
                    .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .tint(flow.canAdvance ? moss : steel)
                .disabled(!flow.canAdvance)
                .accessibilityIdentifier("onboarding.continue")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func resolveHealthWeightIfNeeded() async {
        guard flow.step == .anatomy, !healthWeightResolved else { return }
        dismissKeyboard()
        let sample = await session.latestHealthBodyMass()
        guard !Task.isCancelled, flow.step == .anatomy else { return }
        healthWeightResolved = true
        guard let sample else { return }
        healthWeight = sample
        if !OnboardingFlowModel.weightNeedsScale(lastSample: sample.date) {
            flow.currentWeightKg = sample.value
        }
    }

    private func languageStep(compact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                LazyVStack(spacing: 0) {
                    ForEach(AppLanguage.allCases.filter { $0 != .system } + [.system]) { lang in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                guard let applied = AppLanguageStore.apply(lang) else { return }
                                flow.appLanguage = applied
                                flow.preferredLanguage = applied.resolved.profileLanguageName
                            }
                        } label: {
                            HStack {
                                Text(lang.nativeLabel)
                                    .font(.system(size: compact ? 16 : 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(ink)
                                Spacer()
                                if flow.appLanguage == lang {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(moss)
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("onboarding.language.\(lang.rawValue)")
                        Divider().opacity(0.35)
                    }
                }
            }
        }
        .accessibilityIdentifier("onboarding.language")
    }

    // MARK: - Units (mass and height independently)

    private func unitsStep(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 20) {
            Text(AppLanguageStore.text(
                "onboarding.units.prompt",
                default: "How do you measure yourself?"
            ))
            .font(.system(size: compact ? 20 : 22, weight: .semibold, design: .rounded))
            .foregroundStyle(ink)
            .accessibilityIdentifier("onboarding.units.prompt")

            PreferredUnitsControls(
                units: Binding(
                    get: { flow.unitSystem },
                    set: { flow.selectUnits($0) }
                ),
                ink: ink,
                steel: steel,
                accent: moss,
                showLocationHint: true
            )
            .accessibilityIdentifier("onboarding.units")

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var stepTitle: String {
        switch flow.step {
        case .language: return AppLanguageStore.text("onboarding.step.language", default: "Language")
        case .units: return AppLanguageStore.text("onboarding.step.units", default: "Units")
        case .identity: return AppLanguageStore.text("onboarding.step.identity", default: "Your name")
        case .body: return AppLanguageStore.text("onboarding.step.body", default: "About you")
        case .anatomy: return AppLanguageStore.text("onboarding.step.anatomy", default: "Height & weight")
        case .dream: return AppLanguageStore.text("onboarding.step.dream", default: "Dream weight")
        case .lifestyle: return AppLanguageStore.text("onboarding.step.lifestyle", default: "Food")
        case .confirm: return AppLanguageStore.text("onboarding.step.confirm", default: "Almost done")
        }
    }

    private var stepSubtitle: String {
        switch flow.step {
        case .language:
            return AppLanguageStore.text(
                "onboarding.sub.language",
                default: "Pick the language for the app."
            )
        case .units, .identity, .anatomy, .lifestyle:
            return ""
        case .body:
            return AppLanguageStore.text(
                "onboarding.sub.body",
                default: "Age and gender. Adults 18+ only."
            )
        case .dream:
            return AppLanguageStore.text(
                "onboarding.sub.dream",
                default: "Set a target weight and date."
            )
        case .confirm:
            return AppLanguageStore.text(
                "onboarding.sub.confirm",
                default: "Agree to continue, then start."
            )
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

    // MARK: - Identity (one instruction, one input)

    private func identityStep(compact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 16 : 20) {
                Text(AppLanguageStore.text(
                    "onboarding.identity.prompt",
                    default: "What should we call you?"
                ))
                .font(.system(size: compact ? 20 : 22, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .accessibilityIdentifier("onboarding.identity.prompt")

                TextField(
                    AppLanguageStore.text("onboarding.identity.placeholder", default: "First name"),
                    text: $flow.name
                )
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($nameFieldFocused)
                .font(.system(size: compact ? 28 : 34, weight: .bold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(ink.opacity(0.12), lineWidth: 1)
                )
                .accessibilityIdentifier("onboarding.name")
                .onSubmit {
                    guard flow.canAdvance else { return }
                    dismissKeyboard()
                    Task { await advance() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("onboarding.identity")
    }

    // MARK: - Body

    private func bodyStep(compact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 16 : 20) {
                Text(AppLanguageStore.text("onboarding.body.age_prompt", default: "How old are you?"))
                    .font(.system(size: compact ? 18 : 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .accessibilityIdentifier("onboarding.body.agePrompt")

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

                Text(AppLanguageStore.text("onboarding.body.sex_prompt", default: "I am…"))
                    .font(.system(size: compact ? 18 : 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    genderChip(.male)
                    genderChip(.female)
                }
                .accessibilityIdentifier("onboarding.sex")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)
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

    // MARK: - Anatomy (height + weight only)

    private func anatomyStep(compact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 16 : 20) {
                Text(AppLanguageStore.text("onboarding.anatomy.height_prompt", default: "How tall are you?"))
                    .font(.system(size: compact ? 18 : 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .accessibilityIdentifier("onboarding.anatomy.heightPrompt")

                heightField(compact: compact)

                Text(AppLanguageStore.text("onboarding.anatomy.weight_prompt", default: "What do you weigh today?"))
                    .font(.system(size: compact ? 18 : 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .padding(.top, 4)
                    .accessibilityIdentifier("onboarding.anatomy.weightPrompt")

                currentWeightControl
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("onboarding.anatomy")
        .onChange(of: flow.heightCm) { _, _ in
            flow.updateIdealFromHeightIfNeeded()
        }
        .onChange(of: flow.currentWeightKg) { _, _ in
            flow.clampIdealToBounds()
            flow.refreshPaceAndDifficulty()
        }
    }

    private func heightField(compact: Bool) -> some View {
        HStack(spacing: 12) {
            TextField(
                flow.unitSystem.heightLabel,
                value: Binding(
                    get: { UnitFormat.height(fromCm: flow.heightCm, system: flow.unitSystem) },
                    set: {
                        let cm = UnitFormat.cm(fromHeight: $0, system: flow.unitSystem)
                        flow.heightCm = ProfileNumericBounds.clampHeightCm(cm).value
                    }
                ),
                format: .number.precision(.fractionLength(flow.unitSystem.usesImperialHeight ? 1 : 0))
            )
            .keyboardType(.decimalPad)
            .font(.system(size: compact ? 28 : 34, weight: .bold, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(ink.opacity(0.12), lineWidth: 1)
            )
            .accessibilityIdentifier("onboarding.height")

            Text(flow.unitSystem.heightLabel)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(steel)
                .frame(minWidth: 36, alignment: .leading)
        }
    }

    private var showsWeightScale: Bool {
        adjustWeightOnScale || OnboardingFlowModel.weightNeedsScale(lastSample: healthWeight?.date)
    }

    private var currentWeightControl: some View {
        Group {
            if !healthWeightResolved && !adjustWeightOnScale {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(AppLanguageStore.text("onboarding.anatomy.checking_health", default: "Checking Apple Health…"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(steel)
                }
                .accessibilityIdentifier("onboarding.currentWeight")
            } else if showsWeightScale {
                AnalogDreamScaleView(
                    weightKg: Binding(
                        get: { flow.currentWeightKg },
                        set: { flow.currentWeightKg = ProfileNumericBounds.clampWeightKg($0).value }
                    ),
                    boundsKg: ProfileNumericBounds.weightKg,
                    unitSystem: flow.unitSystem,
                    ink: ink,
                    steel: steel,
                    accent: moss,
                    accessibilityId: "onboarding.currentWeight",
                    caption: AppLanguageStore.text("onboarding.anatomy.drag", default: "Drag to set.")
                )
            } else if let sample = healthWeight {
                VStack(alignment: .leading, spacing: 8) {
                    Text(UnitFormat.massString(sample.value, system: flow.unitSystem, fractionDigits: 1))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .monospacedDigit()
                    Text(
                        String(
                            format: AppLanguageStore.text(
                                "onboarding.anatomy.from_health",
                                default: "From Health · %@"
                            ),
                            relativeWeigh(sample.date)
                        )
                    )
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(moss)
                    Button(AppLanguageStore.text("onboarding.anatomy.change_weight", default: "Change")) {
                        adjustWeightOnScale = true
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .accessibilityIdentifier("onboarding.currentWeight.adjust")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("onboarding.currentWeight")
            }
        }
    }

    private func relativeWeigh(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Dream

    private func dreamStep(compact: Bool) -> some View {
        ScrollView {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
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
        .padding(.bottom, 12)
        }
    }

    // MARK: - Lifestyle (optional — diet first, then quiet extras)

    private func lifestyleStep(compact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 14 : 18) {
                Text(AppLanguageStore.text(
                    "onboarding.lifestyle.prompt",
                    default: "How do you eat?"
                ))
                .font(.system(size: compact ? 20 : 22, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .accessibilityIdentifier("onboarding.lifestyle.prompt")

                Text(AppLanguageStore.text(
                    "onboarding.lifestyle.hint",
                    default: "Optional. Skip if you want — we can ask later."
                ))
                .font(.caption.weight(.medium))
                .foregroundStyle(steel)
                .accessibilityIdentifier("onboarding.lifestyle.softHint")

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(DietPreference.allCases) { diet in
                        dietChip(diet)
                    }
                }
                .accessibilityIdentifier("onboarding.diet")

                Text(AppLanguageStore.text(
                    "onboarding.lifestyle.avoid_prompt",
                    default: "Anything to avoid?"
                ))
                .font(.system(size: compact ? 17 : 18, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .padding(.top, 4)
                .accessibilityIdentifier("onboarding.lifestyle.avoidLabel")

                TextField(
                    AppLanguageStore.text(
                        "onboarding.lifestyle.avoid_placeholder",
                        default: "Peanuts, shellfish… (optional)"
                    ),
                    text: $flow.foodAvoidances,
                    axis: .vertical
                )
                .lineLimit(2...3)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("onboarding.foodAvoidances")

                Text(AppLanguageStore.text(
                    "onboarding.lifestyle.city_prompt",
                    default: "Where do you live?"
                ))
                .font(.system(size: compact ? 17 : 18, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .padding(.top, 4)
                .accessibilityIdentifier("onboarding.lifestyle.cityLabel")

                TextField(
                    AppLanguageStore.text(
                        "onboarding.lifestyle.city_placeholder",
                        default: "City (optional)"
                    ),
                    text: Binding(
                        get: { flow.location },
                        set: { next in
                            flow.location = next
                            let trimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
                            flow.useLocalContext = !trimmed.isEmpty
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("onboarding.location")

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("onboarding.lifestyle")
    }

    private func dietChip(_ diet: DietPreference) -> some View {
        let selected = flow.dietConfirmed && flow.diet == diet
        return Button {
            flow.diet = diet
            flow.markDietConfirmed()
        } label: {
            Text(diet.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 8)
                .foregroundStyle(selected ? Color.white : ink)
                .background(
                    selected ? moss : Color.white.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ink.opacity(selected ? 0 : 0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.diet.\(diet.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
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

            HStack(spacing: 12) {
                NavigationLink {
                    LegalDocumentView(document: .privacyPolicy)
                } label: {
                    Text("Privacy")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .accessibilityIdentifier("onboarding.privacyLink")

                NavigationLink {
                    LegalDocumentView(document: .termsOfUse)
                } label: {
                    Text("Terms")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .accessibilityIdentifier("onboarding.termsLink")

                NavigationLink {
                    LegalDocumentView(document: .medicalDisclaimer)
                } label: {
                    Text("Disclaimer")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .accessibilityIdentifier("onboarding.medicalLink")
            }

            Text(CoachCopySanitize.medicalDisclaimer)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(steel)
                .lineLimit(3)
                .minimumScaleFactor(0.8)

            Text("Age \(ScaleLegal.minimumAgeYears)+ required. Full copies stay in Settings → Privacy & Legal.")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(steel)

            Spacer(minLength: 0)
        }
    }

    private var lifestyleSummaryChip: some View {
        let loc = flow.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let avoid = flow.foodAvoidances.trimmingCharacters(in: .whitespacesAndNewlines)
        let dietBit = flow.dietConfirmed ? flow.diet.title : "Diet not set"
        let locBit = loc.isEmpty ? "Location not set" : loc
        let avoidBit = avoid.isEmpty ? "No avoids yet" : "Avoid: \(avoid)"
        return Text("\(dietBit) · \(locBit) · \(avoidBit)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(steel)
            .lineLimit(2)
            .accessibilityIdentifier("onboarding.confirm.lifestyleSummary")
    }

    // MARK: - Shared

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

    private func advance() async {
        switch flow.step {
        case .language:
            AppLanguageStore.current = flow.appLanguage
            flow.preferredLanguage = flow.appLanguage.profileLanguageName
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                flow.step = .units
            }
        case .units:
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                flow.step = .identity
            }
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
        AppLanguageStore.current = flow.appLanguage
        flow.preferredLanguage = flow.appLanguage.profileLanguageName
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
                    format: "Dream weight %@ by %@. Starting %@.",
                    UnitFormat.massString(profile.idealWeightKg, system: flow.unitSystem, fractionDigits: 1),
                    (profile.goalDate ?? flow.goalDate).formatted(date: .abbreviated, time: .omitted),
                    UnitFormat.massString(
                        profile.startingWeightKg ?? flow.currentWeightKg,
                        system: flow.unitSystem,
                        fractionDigits: 1
                    )
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
        session.isOnboardingReplay = false
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
