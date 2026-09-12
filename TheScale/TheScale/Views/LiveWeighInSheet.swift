import SwiftUI

/// Full-screen live weigh-in / calibration: one viewport, system safe area, no ScrollView.
///
/// Layout contract (iPhone 15):
/// - Background only ignores safe area (full-bleed trend atmosphere).
/// - Content uses system safe area + explicit horizontal inset (never edge-flush glass text).
/// - No GeometryReader width hacks. No whole-view `ignoresSafeArea` on the content stack.
/// - Calibration reuses this same sheet (`weighInPurpose == .calibration`).
struct LiveWeighInSheet: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var pulse = false
    @State private var confirmWeightOnly = false
    @State private var calibrationStoredMessage: String?
    @FocusState private var referenceFocused: Bool

    /// Outer inset so glass panels never sit flush against the screen edge.
    private let horizontalInset: CGFloat = 20
    private let panelInnerPad: CGFloat = 16

    private var atmosphere: TrendAtmosphere {
        TrendAtmosphere.forTrend(session.trendForDisplay)
    }

    private var isCalibration: Bool {
        session.weighInPurpose == .calibration
    }

    var body: some View {
        ZStack {
            TrendAtmosphereBackground(atmosphere: atmosphere)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.85), value: session.trendForDisplay)

            VStack(spacing: 0) {
                topBar
                mainColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, horizontalInset)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        // Extra belt: never let content paint into the horizontal safe-area / bezel.
        .safeAreaPadding(.horizontal, 0)
        .preferredColorScheme(.light)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
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
        VStack(spacing: 10) {
            if isCalibration {
                calibrationHeader
            }

            weightBlock
            resistancePanel

            if !session.isEditingDraft {
                statusLine
            }

            Spacer(minLength: 0)

            if isCalibration {
                calibrationChrome
                    .transition(.opacity)
            } else if showsConfirmChrome {
                editAndConfirm
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                session.dismissWeighIn()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(atmosphere.accent.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.35), in: Circle())
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
        .padding(.bottom, 4)
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
        .padding(.vertical, 6)
        .background(.white.opacity(0.4), in: Capsule())
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
        .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    // MARK: - Shared weigh-in blocks

    private var weightBlock: some View {
        VStack(spacing: 4) {
            Text(weightText)
                .font(.system(size: session.isEditingDraft ? 48 : (isCalibration ? 56 : 68), weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(atmosphere.accent)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: session.isEditingDraft || isCalibration ? 56 : 72, alignment: .center)
                .scaleEffect(isLiveMeasuring ? (pulse ? 1.01 : 0.995) : 1.0)
                .animation(
                    isLiveMeasuring
                        ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                        : .spring(response: 0.45, dampingFraction: 0.82),
                    value: pulse
                )
                .contentTransition(.identity)

            HStack(spacing: 8) {
                Text(isCalibration ? "kg raw" : "kg")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.7))
                if !isCalibration, session.calibration.hasCorrection {
                    Text("calibrated")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(atmosphere.accent.opacity(0.65))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.35), in: Capsule())
                }
            }

            if !isCalibration {
                Text(session.trendForDisplay.subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(session.isEditingDraft ? 1 : 2)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Always-visible BIA / resistance zone (never collapses when weight is streaming).
    private var resistancePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Resistance")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(resistanceValueText)
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.accent)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }

            Text(resistanceStatusText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(session.isEditingDraft || isCalibration ? 1 : 2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(panelInnerPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resistance \(resistanceValueText). \(resistanceStatusText)")
    }

    private var statusLine: some View {
        VStack(spacing: 6) {
            Text(session.liveHint)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(isCalibration ? 2 : 3)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)

            if case .healthKitSuccess = session.phase, !isCalibration {
                Label("Saved to Apple Health", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
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
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    private var editAndConfirm: some View {
        VStack(spacing: 10) {
            if session.isEditingDraft, let draft = session.draft {
                draftEditor(draft)
            } else {
                compositionSummary
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        if session.isEditingDraft {
                            session.isEditingDraft = false
                        } else {
                            session.beginReview()
                        }
                    }
                } label: {
                    Text(session.isEditingDraft ? "Done editing" : "Edit")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ScaleSecondaryButtonStyle(accent: atmosphere.accent))

                Button {
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
                    Text(session.phase == .healthKitWriting ? "Saving…" : "Confirm to Health")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ScalePrimaryButtonStyle(accent: atmosphere.accent))
                .disabled(session.phase == .healthKitWriting || session.displayWeightKg == nil)
            }
        }
        .padding(panelInnerPad)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            VStack(spacing: 6) {
                metricLine("Resistance", draft.impedanceOhms.map { "\($0) Ω" } ?? "- Ω")
                metricLine("BMI", draft.bmi.map { String(format: "%.1f", $0) } ?? "-")
                if let fat = draft.bodyFatPercent {
                    metricLine("Body fat", String(format: "%.1f%%", fat))
                }
                if let lean = draft.leanBodyMassKg {
                    metricLine("Lean mass", String(format: "%.2f kg", lean))
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

    private func draftEditor(_ draft: EditableMeasurementDraft) -> some View {
        VStack(spacing: 6) {
            editRow(title: "Weight (kg)", value: draft.weightKg) {
                session.updateDraftWeight($0)
            }
            editIntRow(title: "Resistance (Ω)", value: draft.impedanceOhms) {
                session.updateDraftImpedance($0)
            }
            if draft.bodyFatPercent != nil || draft.impedanceOhms != nil {
                editOptionalRow(title: "Body fat %", value: draft.bodyFatPercent) {
                    session.updateDraftBodyFat($0)
                }
                editOptionalRow(title: "BMI", value: draft.bmi) {
                    session.updateDraftBMI($0)
                }
                editOptionalRow(title: "Lean mass kg", value: draft.leanBodyMassKg) {
                    session.updateDraftLeanMass($0)
                }
                Toggle("Write fat % + lean to Health", isOn: Binding(
                    get: { draft.includeCompositionInHealth },
                    set: { session.setIncludeCompositionInHealth($0) }
                ))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(atmosphere.accent)
                .tint(atmosphere.accent)
            }
            Text("Only Confirm writes to Apple Health. Mistakes stay local until then.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(atmosphere.accent.opacity(0.7))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    private func editRow(
        title: String,
        value: Double,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(atmosphere.accent)
            Spacer(minLength: 8)
            TextField(
                title,
                value: Binding(
                    get: { value },
                    set: onChange
                ),
                format: .number.precision(.fractionLength(2))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 88)
            .foregroundStyle(atmosphere.accent)
        }
        .font(.system(size: 14, weight: .medium, design: .rounded))
    }

    private func editOptionalRow(
        title: String,
        value: Double?,
        onChange: @escaping (Double?) -> Void
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(atmosphere.accent)
            Spacer(minLength: 8)
            TextField(
                title,
                value: Binding(
                    get: { value ?? 0 },
                    set: { onChange($0) }
                ),
                format: .number.precision(.fractionLength(2))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 88)
            .foregroundStyle(atmosphere.accent)
        }
        .font(.system(size: 14, weight: .medium, design: .rounded))
    }

    private func editIntRow(
        title: String,
        value: Int?,
        onChange: @escaping (Int?) -> Void
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(atmosphere.accent)
            Spacer(minLength: 8)
            TextField(
                title,
                value: Binding(
                    get: { value ?? 0 },
                    set: { onChange($0 == 0 ? nil : $0) }
                ),
                format: .number
            )
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 88)
            .foregroundStyle(atmosphere.accent)
        }
        .font(.system(size: 14, weight: .medium, design: .rounded))
    }

    private func metricLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .foregroundStyle(atmosphere.accent)
    }

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
            return "\(ohms) Ω"
        }
        return "- Ω"
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
        ZStack {
            LinearGradient(
                colors: [atmosphere.top, atmosphere.mid, atmosphere.bottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

struct ScalePrimaryButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .background(
                accent.opacity(configuration.isPressed ? 0.75 : 1.0),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}

struct ScaleSecondaryButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)
            .padding(.vertical, 13)
            .background(
                .white.opacity(configuration.isPressed ? 0.35 : 0.55),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}

#Preview("Weigh-in") {
    LiveWeighInSheet()
        .environmentObject(ScaleSessionViewModel())
}
