import SwiftUI

/// Full-screen live weigh-in: fixed zones so streaming kg / ohms do not jump or clip on iPhone 15.
struct LiveWeighInSheet: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var pulse = false
    @State private var confirmWeightOnly = false

    private var atmosphere: TrendAtmosphere {
        TrendAtmosphere.forTrend(session.trendForDisplay)
    }

    var body: some View {
        ZStack {
            TrendAtmosphereBackground(atmosphere: atmosphere)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.85), value: session.trendForDisplay)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        brandRow
                        weightBlock
                        resistancePanel
                        statusLine
                        if showsConfirmChrome {
                            editAndConfirm
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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

    private var topBar: some View {
        HStack(alignment: .center) {
            Button {
                session.dismissWeighIn()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(atmosphere.accent.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.35), in: Circle())
            }
            .accessibilityLabel("Close weigh-in")

            Spacer(minLength: 8)

            trendChip
                .layoutPriority(1)
        }
        .frame(minHeight: 44)
    }

    private var trendChip: some View {
        let trend = session.trendForDisplay
        return HStack(spacing: 6) {
            Image(systemName: trendSymbol(trend))
            Text(trend.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(atmosphere.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.white.opacity(0.4), in: Capsule())
    }

    private var brandRow: some View {
        HStack(spacing: 10) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("The Scale")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundStyle(atmosphere.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .opacity(0.95)
        .frame(minHeight: 36)
    }

    private var weightBlock: some View {
        VStack(spacing: 6) {
            Text(weightText)
                .font(.system(size: 72, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(atmosphere.accent)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 78, alignment: .center)
                .scaleEffect(isLiveMeasuring ? (pulse ? 1.012 : 0.994) : 1.0)
                .animation(
                    isLiveMeasuring
                        ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                        : .spring(response: 0.45, dampingFraction: 0.82),
                    value: pulse
                )
                // Avoid animating layout on every kg tick (that caused jump/clip).
                .contentTransition(.identity)

            HStack(spacing: 8) {
                Text("kg")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.7))
                if session.calibration.hasCorrection {
                    Text("calibrated")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(atmosphere.accent.opacity(0.65))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.35), in: Capsule())
                }
            }
            .frame(height: 28)

            Text(session.trendForDisplay.subtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(minHeight: 36, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }

    /// Always-visible BIA / resistance zone (never collapses when weight is streaming).
    private var resistancePanel: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Resistance")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.75))
                Spacer()
                Text(resistanceValueText)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.accent)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            Text(resistanceStatusText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .top)
        .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resistance \(resistanceValueText). \(resistanceStatusText)")
    }

    private var statusLine: some View {
        VStack(spacing: 8) {
            Text(session.liveHint)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.9)
                .frame(minHeight: 40, alignment: .top)

            if case .healthKitSuccess = session.phase {
                Label("Saved to Apple Health", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.42, blue: 0.32))
            }
            if case .healthKitFailed(let message) = session.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.48, green: 0.12, blue: 0.12))
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var editAndConfirm: some View {
        VStack(spacing: 14) {
            if session.isEditingDraft, let draft = session.draft {
                draftEditor(draft)
            } else {
                compositionSummary
            }

            HStack(spacing: 12) {
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
        .padding(16)
        .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                        .font(.caption)
                        .foregroundStyle(atmosphere.accent.opacity(0.75))
                }
            }
        }
    }

    private func draftEditor(_ draft: EditableMeasurementDraft) -> some View {
        VStack(spacing: 10) {
            editRow(title: "Weight (kg)", value: draft.weightKg) { session.updateDraftWeight($0) }
            editIntRow(title: "Resistance (Ω)", value: draft.impedanceOhms) { session.updateDraftImpedance($0) }
            if draft.bodyFatPercent != nil || draft.impedanceOhms != nil {
                editOptionalRow(title: "Body fat %", value: draft.bodyFatPercent) {
                    session.updateDraftBodyFat($0)
                }
                editOptionalRow(title: "BMI", value: draft.bmi) { session.updateDraftBMI($0) }
                editOptionalRow(title: "Lean mass kg", value: draft.leanBodyMassKg) {
                    session.updateDraftLeanMass($0)
                }
                Toggle("Write fat % + lean to Health", isOn: Binding(
                    get: { draft.includeCompositionInHealth },
                    set: { session.setIncludeCompositionInHealth($0) }
                ))
                .font(.footnote.weight(.medium))
                .foregroundStyle(atmosphere.accent)
            }
            Text("Only Confirm writes to Apple Health. Mistakes stay local until then.")
                .font(.caption2)
                .foregroundStyle(atmosphere.accent.opacity(0.7))
        }
    }

    private func editRow(title: String, value: Double, onChange: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(atmosphere.accent)
            Spacer()
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
            .frame(width: 96)
            .foregroundStyle(atmosphere.accent)
        }
        .font(.system(size: 15, weight: .medium, design: .rounded))
    }

    private func editOptionalRow(
        title: String,
        value: Double?,
        onChange: @escaping (Double?) -> Void
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(atmosphere.accent)
            Spacer()
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
            .frame(width: 96)
            .foregroundStyle(atmosphere.accent)
        }
        .font(.system(size: 15, weight: .medium, design: .rounded))
    }

    private func editIntRow(
        title: String,
        value: Int?,
        onChange: @escaping (Int?) -> Void
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(atmosphere.accent)
            Spacer()
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
            .frame(width: 96)
            .foregroundStyle(atmosphere.accent)
        }
        .font(.system(size: 15, weight: .medium, design: .rounded))
    }

    private func metricLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 15, weight: .medium, design: .rounded))
        .foregroundStyle(atmosphere.accent)
    }

    private var weightText: String {
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
    }
}

struct ScalePrimaryButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .background(accent.opacity(configuration.isPressed ? 0.75 : 1.0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ScaleSecondaryButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)
            .padding(.vertical, 14)
            .background(.white.opacity(configuration.isPressed ? 0.35 : 0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    LiveWeighInSheet()
        .environmentObject(ScaleSessionViewModel())
}
