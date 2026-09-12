import SwiftUI

/// Full-screen live weigh-in / calibration: one viewport, system safe area, no ScrollView.
///
/// Layout contract (iPhone 15):
/// - Content owns the layout size. Atmosphere is `.background` only (never a ZStack sibling).
/// - Oversized decorative ellipses must not inflate the layout width (that caused L/R mid-word clip).
/// - System safe area + explicit horizontal inset. No GeometryReader. No content `ignoresSafeArea`.
/// - Calibration reuses this same sheet (`weighInPurpose == .calibration`).
struct LiveWeighInSheet: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var pulse = false
    @State private var confirmWeightOnly = false
    @State private var calibrationStoredMessage: String?
    @FocusState private var referenceFocused: Bool
    @FocusState private var weightFieldFocused: Bool
    @FocusState private var ohmsFieldFocused: Bool

    /// Outer inset so glass panels never sit flush against the screen edge.
    private let horizontalInset: CGFloat = 24
    private let panelInnerPad: CGFloat = 16

    private var atmosphere: TrendAtmosphere {
        TrendAtmosphere.forTrend(session.trendForDisplay)
    }

    private var isCalibration: Bool {
        session.weighInPurpose == .calibration
    }

    private var isEditing: Bool {
        session.isEditingDraft && !isCalibration
    }

    var body: some View {
        // Content-first: never put wide decorative views in a sibling ZStack (they inflate width
        // past the screen and clip "Resistance" → "stance", status → "nt streaming", chip → "No bas").
        VStack(spacing: 0) {
            topBar
            mainColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, horizontalInset)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background {
            TrendAtmosphereBackground(atmosphere: atmosphere)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.85), value: session.trendForDisplay)
        }
        .preferredColorScheme(.light)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: session.isEditingDraft) { _, editing in
            if editing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    weightFieldFocused = true
                }
            } else {
                weightFieldFocused = false
                ohmsFieldFocused = false
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    weightFieldFocused = false
                    ohmsFieldFocused = false
                    referenceFocused = false
                }
                .fontWeight(.semibold)
            }
        }
        .alert("Save weight only?", isPresented: $confirmWeightOnly) {
            Button("Cancel", role: .cancel) {}
            Button("Save weight + BMI only") {
                Task { await session.saveDraftToHealth() }
            }
        } message: {
            Text("No impedance was captured, so body fat % will not be written. You can still edit weight before confirming.")
        }
        .alert("Calibration saved", isPresented: Binding(
            get: { calibrationStoredMessage != nil },
            set: { if !$0 { calibrationStoredMessage = nil } }
        )) {
            Button("Done") {
                calibrationStoredMessage = nil
                session.dismissWeighIn()
            }
        } message: {
            Text(calibrationStoredMessage ?? "")
        }
    }

    private var mainColumn: some View {
        VStack(spacing: 12) {
            if isCalibration {
                calibrationHeader
            }

            weightHero
            resistancePanel

            if !isEditing {
                statusLine
            }

            Spacer(minLength: 4)

            if isCalibration {
                calibrationChrome
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if showsConfirmChrome {
                editAndConfirm
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isEditing)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showsConfirmChrome)
    }

    private var showsConfirmChrome: Bool {
        session.phase == .ready
            || session.phase == .reviewing
            || session.isEditingDraft
            || session.phase == .healthKitWriting
            || session.phase == .healthKitSuccess
            || {
                if case .healthKitFailed = session.phase { return true }
                return false
            }()
    }

    // MARK: - Top bar (close + chip only; brand does not fight the trend pill)

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                weightFieldFocused = false
                ohmsFieldFocused = false
                session.dismissWeighIn()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(atmosphere.accent.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close weigh-in")

            Text(isCalibration ? "Calibrate" : "The Scale")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(atmosphere.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(0)

            Spacer(minLength: 8)

            trendChip
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .padding(.bottom, 2)
    }

    private var trendChip: some View {
        let trend = session.trendForDisplay
        return HStack(spacing: 5) {
            Image(systemName: trendSymbol(trend))
            Text(trend.shortTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(atmosphere.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Calibration header / chrome

    private var calibrationHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reference mass on the scale")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.8))

            HStack(spacing: 10) {
                TextField(
                    "kg",
                    value: Binding(
                        get: { session.calibration.referenceMassKg },
                        set: { session.updateCalibrationReferenceMass($0) }
                    ),
                    format: .number.precision(.fractionLength(3))
                )
                .keyboardType(.decimalPad)
                .focused($referenceFocused)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(atmosphere.accent)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("kg")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.7))
            }

            Picker(
                "Mode",
                selection: Binding(
                    get: { session.calibration.captureMode },
                    set: { session.setCalibrationCaptureMode($0) }
                )
            ) {
                ForEach(ScaleCalibration.CaptureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("Place that mass barefoot-optional on the platform. Live kg below is raw from the scale. Store when it settles.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.75))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(panelInnerPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var calibrationChrome: some View {
        VStack(spacing: 10) {
            if let raw = session.rawDisplayWeightKg {
                Text(
                    String(
                        format: "Raw reading %.3f kg → target %.3f kg",
                        raw,
                        session.calibration.referenceMassKg
                    )
                )
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(atmosphere.accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Waiting for a scale reading…")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                referenceFocused = false
                let ok = session.confirmCalibrationFromLiveReading()
                if ok {
                    let raw = session.calibration.lastCalibrationRawKg ?? 0
                    let ref = session.calibration.referenceMassKg
                    calibrationStoredMessage = String(
                        format: "Stored %@ from raw %.3f kg → true %.3f kg. Live weighs will use this correction.",
                        session.calibration.captureMode.title.lowercased(),
                        raw,
                        ref
                    )
                }
            } label: {
                Text(canStoreCalibration ? "Store calibration" : "Wait for settled kg")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ScalePrimaryButtonStyle(accent: atmosphere.accent))
            .disabled(!canStoreCalibration)

            Text("Does not write to Apple Health. Resistance is informational only during calibration.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(atmosphere.accent.opacity(0.7))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(panelInnerPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var canStoreCalibration: Bool {
        guard let raw = session.rawDisplayWeightKg, raw > 0.05 else { return false }
        switch session.phase {
        case .ready, .reviewing, .awaitingImpedance, .measuring:
            return true
        default:
            // Allow store once any live kg exists (small calibration masses settle fast).
            return session.latestMeasurement != nil || session.liveWeightKg != nil
        }
    }

    // MARK: - Hero weight (primary glance target)

    private var weightHero: some View {
        VStack(spacing: 6) {
            if isEditing, let draft = session.draft {
                editableWeightHero(draft)
            } else {
                liveWeightHero
            }

            HStack(spacing: 8) {
                Text(isCalibration ? "kg raw" : "kg")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.72))
                if !isCalibration, session.calibration.hasCorrection {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("calibrated")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(atmosphere.accent.opacity(0.7))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.38), in: Capsule())
                }
                if canBeginEdit, !isEditing {
                    Button {
                        beginEdit()
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(atmosphere.accent.opacity(0.85))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Edit weight")
                }
            }

            if !isCalibration, !isEditing {
                Text(session.trendForDisplay.subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(weightAccessibilityLabel)
        .accessibilityAddTraits(canBeginEdit && !isEditing ? .isButton : [])
        .accessibilityHint(canBeginEdit && !isEditing ? "Double tap to edit before saving to Health" : "")
        .onTapGesture {
            guard canBeginEdit, !isEditing else { return }
            beginEdit()
        }
    }

    private var liveWeightHero: some View {
        Text(weightText)
            .font(.system(size: heroWeightSize, weight: .ultraLight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(atmosphere.accent)
            .minimumScaleFactor(0.35)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: heroWeightHeight, alignment: .center)
            .contentTransition(.numericText())
            .scaleEffect(isLiveMeasuring ? (pulse ? 1.012 : 0.992) : 1.0)
            .animation(
                isLiveMeasuring
                    ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                    : .spring(response: 0.45, dampingFraction: 0.82),
                value: pulse
            )
            .animation(.snappy(duration: 0.28), value: weightText)
    }

    private func editableWeightHero(_ draft: EditableMeasurementDraft) -> some View {
        HStack(spacing: 10) {
            nudgeButton(systemName: "minus", accessibility: "Decrease weight by 0.1 kg") {
                session.updateDraftWeight(max(draft.weightKg - 0.1, 0.1))
            }

            TextField(
                "Weight",
                value: Binding(
                    get: { draft.weightKg },
                    set: { session.updateDraftWeight($0) }
                ),
                format: .number.precision(.fractionLength(2))
            )
            .keyboardType(.decimalPad)
            .focused($weightFieldFocused)
            .font(.system(size: 64, weight: .ultraLight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(atmosphere.accent)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.4)
            .frame(maxWidth: .infinity)
            .frame(height: 72, alignment: .center)
            .contentTransition(.numericText())

            nudgeButton(systemName: "plus", accessibility: "Increase weight by 0.1 kg") {
                session.updateDraftWeight(draft.weightKg + 0.1)
            }
        }
    }

    private var heroWeightSize: CGFloat {
        if isCalibration { return 64 }
        return 92
    }

    private var heroWeightHeight: CGFloat {
        if isCalibration { return 68 }
        return 96
    }

    private var canBeginEdit: Bool {
        !isCalibration && (
            session.phase == .ready
                || session.phase == .reviewing
                || session.draft != nil
                || session.latestMeasurement != nil
        )
    }

    private func beginEdit() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            if session.latestMeasurement != nil {
                session.beginReview()
            } else if session.draft != nil {
                session.isEditingDraft = true
            }
        }
    }

    private var weightAccessibilityLabel: String {
        if isCalibration {
            return "Raw weight \(weightText) kilograms"
        }
        return "Weight \(weightText) kilograms"
    }

    // MARK: - Resistance (secondary reading)

    /// Always-visible BIA / resistance zone. Plain padded VStack (not List/Form).
    private var resistancePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing, let draft = session.draft {
                editableResistance(draft)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Resistance")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(atmosphere.accent.opacity(0.72))
                            .lineLimit(1)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(resistanceValueText)
                            .font(.system(size: 40, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(atmosphere.accent)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.28), value: resistanceValueText)
                        Text("Ω")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(atmosphere.accent.opacity(0.7))
                    }
                }
            }

            Text(resistanceStatusText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(isEditing || isCalibration ? 1 : 2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(panelInnerPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resistance \(resistanceValueText). \(resistanceStatusText)")
    }

    private func editableResistance(_ draft: EditableMeasurementDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resistance")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.72))

            HStack(spacing: 10) {
                nudgeButton(systemName: "minus", accessibility: "Decrease resistance by 1 ohm") {
                    let next = max((draft.impedanceOhms ?? 0) - 1, 0)
                    session.updateDraftImpedance(next == 0 ? nil : next)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField(
                        "Ω",
                        value: Binding(
                            get: { draft.impedanceOhms ?? 0 },
                            set: { session.updateDraftImpedance($0 == 0 ? nil : $0) }
                        ),
                        format: .number
                    )
                    .keyboardType(.numberPad)
                    .focused($ohmsFieldFocused)
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.accent)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity)

                    Text("Ω")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(atmosphere.accent.opacity(0.7))
                }

                nudgeButton(systemName: "plus", accessibility: "Increase resistance by 1 ohm") {
                    session.updateDraftImpedance((draft.impedanceOhms ?? 0) + 1)
                }
            }
        }
    }

    // MARK: - Status

    /// Status / hint under resistance: simple padded VStack, no List.
    private var statusLine: some View {
        VStack(spacing: 6) {
            Text(session.liveHint)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineLimit(isCalibration ? 2 : 3)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)

            if case .healthKitSuccess = session.phase, !isCalibration {
                Label("Saved to Apple Health", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.42, blue: 0.32))
            }
            if case .healthKitFailed(let message) = session.phase, !isCalibration {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.48, green: 0.12, blue: 0.12))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, panelInnerPad)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Edit + confirm

    private var editAndConfirm: some View {
        VStack(spacing: 12) {
            if isEditing, let draft = session.draft {
                draftEditor(draft)
            } else {
                compositionSummary
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        if session.isEditingDraft {
                            weightFieldFocused = false
                            ohmsFieldFocused = false
                            session.isEditingDraft = false
                        } else {
                            beginEdit()
                        }
                    }
                } label: {
                    Label(
                        session.isEditingDraft ? "Done" : "Edit",
                        systemImage: session.isEditingDraft ? "checkmark" : "pencil"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ScaleSecondaryButtonStyle(accent: atmosphere.accent))

                Button {
                    weightFieldFocused = false
                    ohmsFieldFocused = false
                    if session.draft == nil {
                        session.beginReview()
                        session.isEditingDraft = false
                    }
                    if session.isWeightOnlyReading || session.draft?.includeCompositionInHealth == false {
                        confirmWeightOnly = true
                    } else {
                        Task { await session.saveDraftToHealth() }
                    }
                } label: {
                    Label(
                        session.phase == .healthKitWriting ? "Saving…" : "Confirm to Health",
                        systemImage: session.phase == .healthKitWriting ? "ellipsis" : "heart.fill"
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ScalePrimaryButtonStyle(accent: atmosphere.accent))
                .disabled(session.phase == .healthKitWriting || session.displayWeightKg == nil)
            }
        }
        .padding(panelInnerPad)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var compositionSummary: some View {
        if let draft = session.draft ?? (session.latestMeasurement.map {
            EditableMeasurementDraft.from(
                measurement: $0,
                composition: session.composition,
                profile: session.profile
            )
        }) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    metricChip(title: "BMI", value: draft.bmi.map { String(format: "%.1f", $0) } ?? "-")
                    metricChip(
                        title: "Body fat",
                        value: draft.bodyFatPercent.map { String(format: "%.1f%%", $0) } ?? "-"
                    )
                    metricChip(
                        title: "Lean",
                        value: draft.leanBodyMassKg.map { String(format: "%.1f", $0) } ?? "-"
                    )
                }

                if draft.impedanceOhms == nil {
                    Text("Composition needs ohms. Edit weight freely; fat% stays off until resistance arrives.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(atmosphere.accent.opacity(0.75))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
        }
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.65))
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(atmosphere.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func draftEditor(_ draft: EditableMeasurementDraft) -> some View {
        VStack(spacing: 8) {
            if draft.bodyFatPercent != nil || draft.impedanceOhms != nil {
                HStack(spacing: 8) {
                    compactEditField(
                        title: "Body fat %",
                        value: draft.bodyFatPercent,
                        fractionLength: 1
                    ) { session.updateDraftBodyFat($0) }
                    compactEditField(
                        title: "BMI",
                        value: draft.bmi,
                        fractionLength: 1
                    ) { session.updateDraftBMI($0) }
                    compactEditField(
                        title: "Lean kg",
                        value: draft.leanBodyMassKg,
                        fractionLength: 2
                    ) { session.updateDraftLeanMass($0) }
                }

                Toggle(isOn: Binding(
                    get: { draft.includeCompositionInHealth },
                    set: { session.setIncludeCompositionInHealth($0) }
                )) {
                    Label("Write fat % + lean to Health", systemImage: "figure.arms.open")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundStyle(atmosphere.accent)
                .tint(atmosphere.accent)
            } else {
                Text("Weight-only. Adjust kg above; body fat stays off until ohms arrive.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Only Confirm writes to Apple Health. Mistakes stay on this iPhone until then.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(atmosphere.accent.opacity(0.7))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    private func compactEditField(
        title: String,
        value: Double?,
        fractionLength: Int,
        onChange: @escaping (Double?) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.65))
            TextField(
                title,
                value: Binding(
                    get: { value ?? 0 },
                    set: { onChange($0) }
                ),
                format: .number.precision(.fractionLength(fractionLength))
            )
            .keyboardType(.decimalPad)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(atmosphere.accent)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nudgeButton(
        systemName: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(atmosphere.accent)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.42), in: Circle())
        }
        .accessibilityLabel(accessibility)
        .buttonStyle(.plain)
    }

    // MARK: - Derived text

    private var weightText: String {
        if isCalibration {
            guard let kg = session.rawDisplayWeightKg else { return "-" }
            return String(format: "%.2f", kg)
        }
        guard let kg = session.displayWeightKg else { return "-" }
        return String(format: "%.2f", kg)
    }

    private var resistanceValueText: String {
        if let ohms = session.displayImpedanceOhms {
            return "\(ohms)"
        }
        return "-"
    }

    private var resistanceStatusText: String {
        if isCalibration {
            return "Ohms stay visible; calibration only corrects weight kg."
        }
        if session.displayImpedanceOhms != nil {
            return "BIA impedance locked. Body fat math uses this resistance."
        }
        if session.isWeightOnlyReading,
           session.phase == .ready || session.phase == .reviewing {
            return "No ohms this session (socks/shoes or stepped off early)."
        }
        switch session.phase {
        case .awaitingImpedance:
            return "Waiting for barefoot impedance sweep. Stay on the electrodes."
        case .measuring, .listening:
            return "Weight streaming. Resistance appears after the scale finishes BIA."
        default:
            return "Resistance stays visible here once the scale reports ohms."
        }
    }

    private var isLiveMeasuring: Bool {
        switch session.phase {
        case .listening, .measuring, .awaitingImpedance:
            return true
        default:
            return false
        }
    }

    private func trendSymbol(_ trend: WeightTrend) -> String {
        switch trend {
        case .loss: return "arrow.down.right"
        case .stable: return "arrow.left.and.right"
        case .gain: return "arrow.up.right"
        case .unknown: return "minus"
        }
    }
}

struct TrendAtmosphereBackground: View {
    let atmosphere: TrendAtmosphere

    var body: some View {
        // Gradient defines layout size. Ellipses live in overlay so they cannot widen the sheet.
        LinearGradient(
            colors: [atmosphere.top, atmosphere.mid, atmosphere.bottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            ZStack {
                Ellipse()
                    .fill(.white.opacity(0.22))
                    .frame(width: 420, height: 280)
                    .blur(radius: 40)
                    .offset(x: -80, y: -220)
                Ellipse()
                    .fill(atmosphere.accent.opacity(0.12))
                    .frame(width: 520, height: 360)
                    .blur(radius: 50)
                    .offset(x: 90, y: 260)
            }
            .allowsHitTesting(false)
        }
        .clipped()
    }
}

struct ScalePrimaryButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .background(
                accent.opacity(configuration.isPressed ? 0.75 : 1.0),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ScaleSecondaryButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)
            .padding(.vertical, 14)
            .background(
                .white.opacity(configuration.isPressed ? 0.35 : 0.55),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview("Weigh-in") {
    LiveWeighInSheet()
        .environmentObject(ScaleSessionViewModel())
}
