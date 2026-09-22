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
    @FocusState private var bodyFatFieldFocused: Bool
    @FocusState private var leanFieldFocused: Bool

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
        // past the screen and clip mid-word labels / status / trend chip).
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
                bodyFatFieldFocused = false
                leanFieldFocused = false
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    weightFieldFocused = false
                    bodyFatFieldFocused = false
                    leanFieldFocused = false
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
            Text("No body composition was captured, so body fat % will not be written. You can still edit weight before confirming.")
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
            compositionPanel

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
                bodyFatFieldFocused = false
                leanFieldFocused = false
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

            Text("Does not write to Apple Health. Body fat % is informational only during calibration.")
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

    // MARK: - Body composition (secondary reading: fat % + lean %)

    /// Always-visible body fat / lean zone. Plain padded VStack (not List/Form).
    /// Impedance stays internal for BIA; ohms never appear in chrome.
    private var compositionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing, let draft = session.draft {
                editableComposition(draft)
            } else {
                HStack(spacing: 12) {
                    compositionMetric(
                        title: "Body fat",
                        valueText: bodyFatValueText,
                        unit: "%"
                    )
                    compositionMetric(
                        title: "Lean",
                        valueText: leanValueText,
                        unit: "%"
                    )
                }
            }

            Text(compositionStatusText)
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
        .accessibilityLabel("Body fat \(bodyFatValueText) percent. Lean \(leanValueText) percent. \(compositionStatusText)")
    }

    private func compositionMetric(title: String, valueText: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.72))
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(valueText)
                    .font(.system(size: 40, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.28), value: valueText)
                Text(unit)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editableComposition(_ draft: EditableMeasurementDraft) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Body fat %")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.72))
                HStack(spacing: 8) {
                    nudgeButton(systemName: "minus", accessibility: "Decrease body fat by 0.1 percent") {
                        let next = max((draft.bodyFatPercent ?? 0) - 0.1, 0)
                        session.updateDraftBodyFat(next)
                    }
                    TextField(
                        "Fat",
                        value: Binding(
                            get: { draft.bodyFatPercent ?? 0 },
                            set: { session.updateDraftBodyFat($0) }
                        ),
                        format: .number.precision(.fractionLength(1))
                    )
                    .keyboardType(.decimalPad)
                    .focused($bodyFatFieldFocused)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.accent)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    nudgeButton(systemName: "plus", accessibility: "Increase body fat by 0.1 percent") {
                        session.updateDraftBodyFat((draft.bodyFatPercent ?? 0) + 0.1)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("Lean %")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.72))
                HStack(spacing: 8) {
                    nudgeButton(systemName: "minus", accessibility: "Decrease lean by 0.1 percent") {
                        let next = max((draft.leanPercent ?? 0) - 0.1, 0)
                        session.updateDraftLeanPercent(next)
                    }
                    TextField(
                        "Lean",
                        value: Binding(
                            get: { draft.leanPercent ?? 0 },
                            set: { session.updateDraftLeanPercent($0) }
                        ),
                        format: .number.precision(.fractionLength(1))
                    )
                    .keyboardType(.decimalPad)
                    .focused($leanFieldFocused)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.accent)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    nudgeButton(systemName: "plus", accessibility: "Increase lean by 0.1 percent") {
                        session.updateDraftLeanPercent((draft.leanPercent ?? 0) + 0.1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Status

    /// Status / hint under composition: simple padded VStack, no List.
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

            if session.autoConfirmArmed, !isEditing, !isCalibration {
                Text("Auto-confirm in \(session.autoConfirmSecondsRemaining)s")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        if session.isEditingDraft {
                            weightFieldFocused = false
                            bodyFatFieldFocused = false
                            leanFieldFocused = false
                            session.isEditingDraft = false
                            session.armAutoConfirm()
                        } else {
                            session.cancelAutoConfirm()
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

                if session.autoConfirmArmed, !isEditing {
                    Button {
                        session.cancelAutoConfirm()
                    } label: {
                        Label("Cancel", systemImage: "hand.raised")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ScaleSecondaryButtonStyle(accent: atmosphere.accent))
                }

                Button {
                    weightFieldFocused = false
                    bodyFatFieldFocused = false
                    leanFieldFocused = false
                    session.cancelAutoConfirm()
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
        .onChange(of: session.phase) { _, newPhase in
            if newPhase == .ready, !isCalibration, !session.isEditingDraft {
                session.armAutoConfirm()
            }
        }
        .onChange(of: session.isEditingDraft) { _, editing in
            if editing {
                session.cancelAutoConfirm()
            } else if session.phase == .ready, !isCalibration {
                session.armAutoConfirm()
            }
        }
        .onAppear {
            if session.phase == .ready, !isCalibration, !session.isEditingDraft {
                session.armAutoConfirm()
            }
        }
        .task(id: session.autoConfirmArmed) {
            guard session.autoConfirmArmed else { return }
            while session.autoConfirmArmed, session.autoConfirmSecondsRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard session.autoConfirmArmed else { return }
                session.autoConfirmSecondsRemaining -= 1
            }
            guard session.autoConfirmArmed,
                  session.autoConfirmSecondsRemaining <= 0,
                  !session.isEditingDraft,
                  session.phase == .ready || session.phase == .reviewing
            else { return }
            session.cancelAutoConfirm()
            if session.isWeightOnlyReading || session.draft?.includeCompositionInHealth == false {
                confirmWeightOnly = true
            } else {
                await session.saveDraftToHealth()
            }
        }
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
                        value: draft.leanPercent.map { String(format: "%.1f%%", $0) } ?? "-"
                    )
                }

                if draft.bodyFatPercent == nil {
                    Text("Composition needs a barefoot scan. Edit weight freely; fat % stays off until it arrives.")
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
            if draft.bodyFatPercent != nil || draft.sourceHasImpedance {
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
                        title: "Lean %",
                        value: draft.leanPercent,
                        fractionLength: 1
                    ) { session.updateDraftLeanPercent($0) }
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
                Text("Weight-only. Adjust kg above; body fat stays off until the barefoot scan finishes.")
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

    private var bodyFatValueText: String {
        if let percent = session.displayBodyFatPercent {
            return String(format: "%.1f", percent)
        }
        return "-"
    }

    private var leanValueText: String {
        if let percent = session.displayLeanPercent {
            return String(format: "%.1f", percent)
        }
        return "-"
    }

    private var compositionStatusText: String {
        if isCalibration {
            return "Calibration corrects weight kg only. Body fat stays informational."
        }
        if session.displayBodyFatPercent != nil {
            return "Body composition locked from the barefoot scan."
        }
        if session.isWeightOnlyReading,
           session.phase == .ready || session.phase == .reviewing {
            return "No body fat this session (socks/shoes or stepped off early)."
        }
        switch session.phase {
        case .awaitingImpedance:
            return "Waiting for barefoot body composition. Stay on the electrodes."
        case .measuring, .listening:
            return "Weight streaming. Body fat % appears after the scale finishes scanning."
        default:
            return "Body fat % and lean % appear here once the scan finishes."
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
        // MeshGradient (iOS 18+) for SOTA soft fields; no Metal drawingGroup / blur fopen spam.
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                .init(0, 0), .init(0.5, 0), .init(1, 0),
                .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                .init(0, 1), .init(0.5, 1), .init(1, 1)
            ],
            colors: [
                atmosphere.top, atmosphere.mid, atmosphere.top,
                atmosphere.mid, atmosphere.bottom, atmosphere.mid,
                atmosphere.bottom, atmosphere.mid, atmosphere.top
            ]
        )
        .overlay {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 180
                        )
                    )
                    .frame(width: 360, height: 360)
                    .offset(x: -90, y: -200)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [atmosphere.accent.opacity(0.14), atmosphere.accent.opacity(0)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 220
                        )
                    )
                    .frame(width: 440, height: 440)
                    .offset(x: 100, y: 240)
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
