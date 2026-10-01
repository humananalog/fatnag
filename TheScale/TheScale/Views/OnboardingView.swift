import SwiftUI
import UIKit

/// First launch: language → identity → body → anatomy → dream → lifestyle → confirm.
/// Every step is one screenfit page on iPhone 15. Hard facts. Short lines.
struct OnboardingView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var flow = OnboardingFlowModel()
    @State private var healthWeight: HealthMetricSample?
    @State private var healthWeightResolved = false
    @State private var adjustWeightOnScale = false

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

                Text(stepSubtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(steel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var continueBar: some View {
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
            }
            .buttonStyle(.borderedProminent)
            .tint(ink)
            .disabled(!flow.canAdvance)
            .accessibilityIdentifier("onboarding.continue")
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
                Text(AppLanguageStore.text("onboarding.language.hint", default: "Choose the language for fatnag. Every screen follows this choice."))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(steel)
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

    private var stepTitle: String {
        switch flow.step {
        case .language: return AppLanguageStore.text("onboarding.step.language", default: "Language")
        case .identity: return AppLanguageStore.text("onboarding.step.identity", default: "Mission")
        case .body: return AppLanguageStore.text("onboarding.step.body", default: "Body")
        case .anatomy: return AppLanguageStore.text("onboarding.step.anatomy", default: "Frame")
        case .dream: return AppLanguageStore.text("onboarding.step.dream", default: "Dream weight")
        case .lifestyle: return AppLanguageStore.text("onboarding.step.lifestyle", default: "Food & place")
        case .confirm: return AppLanguageStore.text("onboarding.step.confirm", default: "Lock in")
        }
    }

    private var stepSubtitle: String {
        switch flow.step {
        case .language: return AppLanguageStore.text("onboarding.sub.language", default: "This choice follows you through the whole app.")
        case .identity: return AppLanguageStore.text("onboarding.sub.identity", default: "A consistency coach. The number gets less scary.")
        case .body: return AppLanguageStore.text("onboarding.sub.body", default: "Adults only. This sets the math.")
        case .anatomy: return AppLanguageStore.text("onboarding.sub.anatomy", default: "Height, then weight. Units switch live.")
        case .dream: return AppLanguageStore.text("onboarding.sub.dream", default: "Drag the dial. A reckless pace gets a no.")
        case .lifestyle: return AppLanguageStore.text("onboarding.sub.lifestyle", default: "Optional. Blank is a fine answer.")
        case .confirm: return AppLanguageStore.text("onboarding.sub.confirm", default: "One legal yes. Then the scale.")
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

            Text("Gender")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
        ScrollView {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            vectorArt("OnboardingVectorAnatomy", height: compact ? 56 : 72)

            unitToggle(id: "onboarding.anatomy.units")

            unitAwareField(
                title: "Height",
                display: Binding(
                    get: { UnitFormat.height(fromCm: flow.heightCm, system: flow.unitSystem) },
                    set: {
                        let cm = UnitFormat.cm(fromHeight: $0, system: flow.unitSystem)
                        flow.heightCm = ProfileNumericBounds.clampHeightCm(cm).value
                    }
                ),
                unit: flow.unitSystem.heightLabel,
                fraction: flow.unitSystem == .metric ? 0 : 1,
                id: "onboarding.height"
            )

            currentWeightControl

            VStack(alignment: .leading, spacing: 6) {
                Text("Body fat % (optional)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Text("Only if you already know it (DEXA, calipers, prior scale). Leave blank if unknown. Typical range about 3-60%.")
                    .font(.caption2)
                    .foregroundStyle(steel)
                HStack {
                    TextField(
                        "e.g. 18.5",
                        text: Binding(
                            get: {
                                flow.startingBodyFatPercent.map { String(format: "%.1f", $0) } ?? ""
                            },
                            set: { raw in
                                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    flow.startingBodyFatPercent = nil
                                    return
                                }
                                guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else {
                                    return
                                }
                                flow.startingBodyFatPercent = ProfileNumericBounds.clampOptionalBodyFatPercent(value).value
                            }
                        )
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .accessibilityIdentifier("onboarding.startingBodyFat")
                    Text("%").foregroundStyle(steel)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Medical / habits (optional)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Text("Injuries, meds, alcohol, sleep quirks. On-device Coach context only.")
                    .font(.caption2)
                    .foregroundStyle(steel)
                TextField(
                    "e.g. knee tweak, weekend wine",
                    text: $flow.healthContextNotes,
                    axis: .vertical
                )
                .lineLimit(2...3)
                .padding(10)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("onboarding.healthContext")
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: flow.heightCm) { _, _ in
            flow.updateIdealFromHeightIfNeeded()
        }
        .onChange(of: flow.currentWeightKg) { _, _ in
            flow.clampIdealToBounds()
            flow.refreshPaceAndDifficulty()
        }
    }

    private var showsWeightScale: Bool {
        adjustWeightOnScale || OnboardingFlowModel.weightNeedsScale(lastSample: healthWeight?.date)
    }

    private var currentWeightControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !healthWeightResolved && !adjustWeightOnScale {
                Text("Checking Health for a recent weigh…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(steel)
                    .accessibilityIdentifier("onboarding.currentWeight")
            } else if showsWeightScale {
                Text("Current weight")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                if let date = healthWeight?.date, OnboardingFlowModel.weightNeedsScale(lastSample: date) {
                    Text("Last Health weigh was \(relativeWeigh(date)). Drag the dial.")
                        .font(.caption)
                        .foregroundStyle(steel)
                        .fixedSize(horizontal: false, vertical: true)
                } else if healthWeight == nil {
                    Text("No recent Health weigh. Drag the dial. Marks follow \(flow.unitSystem.massLabel) only.")
                        .font(.caption)
                        .foregroundStyle(steel)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                    caption: "Drag. The needle stays. \(flow.unitSystem.massLabel) marks only."
                )
            } else if let sample = healthWeight {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current weight")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(UnitFormat.massString(sample.value, system: flow.unitSystem, fractionDigits: 1))
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(ink)
                            .monospacedDigit()
                    }
                    Text("From Health · \(relativeWeigh(sample.date))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(moss)
                    Button("Not this weight") {
                        adjustWeightOnScale = true
                    }
                    .font(.caption.weight(.bold))
                    .accessibilityIdentifier("onboarding.currentWeight.adjust")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .padding(.bottom, 12)
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
        case .language:
            AppLanguageStore.current = flow.appLanguage
            flow.preferredLanguage = flow.appLanguage.profileLanguageName
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
