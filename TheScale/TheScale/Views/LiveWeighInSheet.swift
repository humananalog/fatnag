import SwiftUI

/// Full-screen live weigh-in: one viewport, no ScrollView, adaptive type/spacing for iPhone 15.
struct LiveWeighInSheet: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var pulse = false
    @State private var confirmWeightOnly = false

    private var atmosphere: TrendAtmosphere {
        TrendAtmosphere.forTrend(session.trendForDisplay)
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = LiveSheetMetrics(size: geo.size, safe: geo.safeAreaInsets)
            ZStack {
                TrendAtmosphereBackground(atmosphere: atmosphere)
                    .animation(.easeInOut(duration: 0.85), value: session.trendForDisplay)

                VStack(spacing: 0) {
                    topBar(metrics: metrics)
                    mainColumn(metrics: metrics)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, metrics.bottomPadding)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        }
        .ignoresSafeArea()
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

    private func topBar(metrics: LiveSheetMetrics) -> some View {
        HStack(alignment: .center, spacing: metrics.gapS) {
            Button {
                session.dismissWeighIn()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(atmosphere.accent.opacity(0.85))
                    .frame(width: metrics.closeSize, height: metrics.closeSize)
                    .background(.white.opacity(0.35), in: Circle())
            }
            .accessibilityLabel("Close weigh-in")

            brandMark(metrics: metrics)

            Spacer(minLength: metrics.gapS)

            trendChip(metrics: metrics)
                .layoutPriority(1)
        }
        .frame(height: metrics.topBarHeight)
    }

    private func brandMark(metrics: LiveSheetMetrics) -> some View {
        HStack(spacing: metrics.gapS) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: metrics.brandIcon, height: metrics.brandIcon)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text("The Scale")
                .font(.system(size: metrics.brandFont, weight: .semibold, design: .serif))
                .foregroundStyle(atmosphere.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .opacity(0.95)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The Scale")
    }

    private func trendChip(metrics: LiveSheetMetrics) -> some View {
        let trend = session.trendForDisplay
        return HStack(spacing: 5) {
            Image(systemName: trendSymbol(trend))
            Text(trend.title)
                .font(.system(size: metrics.chipFont, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(atmosphere.accent)
        .padding(.horizontal, metrics.chipPadH)
        .padding(.vertical, metrics.chipPadV)
        .background(.white.opacity(0.4), in: Capsule())
    }

    private func mainColumn(metrics: LiveSheetMetrics) -> some View {
        VStack(spacing: metrics.sectionGap) {
            weightBlock(metrics: metrics)
            resistancePanel(metrics: metrics)
            statusLine(metrics: metrics)
            Spacer(minLength: 0)
            if showsConfirmChrome {
                editAndConfirm(metrics: metrics)
                    .transition(.opacity)
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func weightBlock(metrics: LiveSheetMetrics) -> some View {
        VStack(spacing: metrics.gapS) {
            Text(weightText)
                .font(.system(size: metrics.weightFont, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(atmosphere.accent)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.weightHeight, alignment: .center)
                .scaleEffect(isLiveMeasuring ? (pulse ? 1.01 : 0.995) : 1.0)
                .animation(
                    isLiveMeasuring
                        ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                        : .spring(response: 0.45, dampingFraction: 0.82),
                    value: pulse
                )
                .contentTransition(.identity)

            HStack(spacing: 8) {
                Text("kg")
                    .font(.system(size: metrics.unitFont, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.7))
                if session.calibration.hasCorrection {
                    Text("calibrated")
                        .font(.system(size: metrics.captionFont, weight: .semibold))
                        .foregroundStyle(atmosphere.accent.opacity(0.65))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.35), in: Capsule())
                }
            }
            .frame(height: metrics.unitRowHeight)

            Text(session.trendForDisplay.subtitle)
                .font(.system(size: metrics.subtitleFont, weight: .medium, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(metrics.compact ? 1 : 2)
                .minimumScaleFactor(0.8)
                .frame(height: metrics.subtitleHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }

    /// Always-visible BIA / resistance zone (never collapses when weight is streaming).
    private func resistancePanel(metrics: LiveSheetMetrics) -> some View {
        VStack(spacing: metrics.gapS) {
            HStack(alignment: .firstTextBaseline) {
                Text("Resistance")
                    .font(.system(size: metrics.labelFont, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.75))
                Spacer(minLength: 8)
                Text(resistanceValueText)
                    .font(.system(size: metrics.resistanceFont, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.accent)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }

            Text(resistanceStatusText)
                .font(.system(size: metrics.captionFont, weight: .medium, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(metrics.compact ? 1 : 2)
                .minimumScaleFactor(0.85)
        }
        .padding(metrics.panelPad)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resistance \(resistanceValueText). \(resistanceStatusText)")
    }

    private func statusLine(metrics: LiveSheetMetrics) -> some View {
        VStack(spacing: metrics.gapS) {
            Text(session.liveHint)
                .font(.system(size: metrics.hintFont, weight: .regular, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(metrics.compact ? 2 : 3)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(minHeight: metrics.hintMinHeight, alignment: .top)

            if case .healthKitSuccess = session.phase {
                Label("Saved to Apple Health", systemImage: "checkmark.seal.fill")
                    .font(.system(size: metrics.hintFont, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.42, blue: 0.32))
            }
            if case .healthKitFailed(let message) = session.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: metrics.captionFont, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.48, green: 0.12, blue: 0.12))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func editAndConfirm(metrics: LiveSheetMetrics) -> some View {
        VStack(spacing: metrics.confirmGap) {
            if session.isEditingDraft, let draft = session.draft {
                draftEditor(draft, metrics: metrics)
            } else {
                compositionSummary(metrics: metrics)
            }

            HStack(spacing: metrics.gapM) {
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
                .buttonStyle(ScaleSecondaryButtonStyle(accent: atmosphere.accent, compact: metrics.compact))

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
                .buttonStyle(ScalePrimaryButtonStyle(accent: atmosphere.accent, compact: metrics.compact))
                .disabled(session.phase == .healthKitWriting || session.displayWeightKg == nil)
            }
        }
        .padding(metrics.panelPad)
        .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func compositionSummary(metrics: LiveSheetMetrics) -> some View {
        if let draft = session.draft ?? (session.latestMeasurement.map {
            EditableMeasurementDraft.from(
                measurement: $0,
                composition: session.composition,
                profile: session.profile
            )
        }) {
            VStack(spacing: metrics.metricGap) {
                metricLine("Resistance", draft.impedanceOhms.map { "\($0) Ω" } ?? "- Ω", metrics: metrics)
                metricLine("BMI", draft.bmi.map { String(format: "%.1f", $0) } ?? "-", metrics: metrics)
                if let fat = draft.bodyFatPercent {
                    metricLine("Body fat", String(format: "%.1f%%", fat), metrics: metrics)
                }
                if let lean = draft.leanBodyMassKg {
                    metricLine("Lean mass", String(format: "%.2f kg", lean), metrics: metrics)
                }
                if draft.impedanceOhms == nil {
                    Text("Composition needs ohms. Edit weight freely; fat% stays off until resistance arrives.")
                        .font(.system(size: metrics.captionFont, weight: .regular))
                        .foregroundStyle(atmosphere.accent.opacity(0.75))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
        }
    }

    private func draftEditor(_ draft: EditableMeasurementDraft, metrics: LiveSheetMetrics) -> some View {
        VStack(spacing: metrics.metricGap) {
            editRow(title: "Weight (kg)", value: draft.weightKg, metrics: metrics) {
                session.updateDraftWeight($0)
            }
            editIntRow(title: "Resistance (Ω)", value: draft.impedanceOhms, metrics: metrics) {
                session.updateDraftImpedance($0)
            }
            if draft.bodyFatPercent != nil || draft.impedanceOhms != nil {
                editOptionalRow(title: "Body fat %", value: draft.bodyFatPercent, metrics: metrics) {
                    session.updateDraftBodyFat($0)
                }
                editOptionalRow(title: "BMI", value: draft.bmi, metrics: metrics) {
                    session.updateDraftBMI($0)
                }
                editOptionalRow(title: "Lean mass kg", value: draft.leanBodyMassKg, metrics: metrics) {
                    session.updateDraftLeanMass($0)
                }
                Toggle("Write fat % + lean to Health", isOn: Binding(
                    get: { draft.includeCompositionInHealth },
                    set: { session.setIncludeCompositionInHealth($0) }
                ))
                .font(.system(size: metrics.captionFont, weight: .medium))
                .foregroundStyle(atmosphere.accent)
                .tint(atmosphere.accent)
            }
            Text("Only Confirm writes to Apple Health. Mistakes stay local until then.")
                .font(.system(size: metrics.microFont, weight: .regular))
                .foregroundStyle(atmosphere.accent.opacity(0.7))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    private func editRow(
        title: String,
        value: Double,
        metrics: LiveSheetMetrics,
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
        .font(.system(size: metrics.rowFont, weight: .medium, design: .rounded))
    }

    private func editOptionalRow(
        title: String,
        value: Double?,
        metrics: LiveSheetMetrics,
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
        .font(.system(size: metrics.rowFont, weight: .medium, design: .rounded))
    }

    private func editIntRow(
        title: String,
        value: Int?,
        metrics: LiveSheetMetrics,
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
        .font(.system(size: metrics.rowFont, weight: .medium, design: .rounded))
    }

    private func metricLine(_ title: String, _ value: String, metrics: LiveSheetMetrics) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(.system(size: metrics.rowFont, weight: .medium, design: .rounded))
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

/// Scales type and spacing so weight, resistance, trend, edit, and confirm fit one iPhone 15 viewport.
private struct LiveSheetMetrics {
    let size: CGSize
    let safe: EdgeInsets

    /// iPhone 15 logical height is 852; treat sub-900 as compact.
    var compact: Bool { size.height < 900 }

    var horizontalPadding: CGFloat { compact ? 14 : 18 }
    /// Real safe-area inset + small inner inset so chrome is never under Dynamic Island / home indicator.
    var topPadding: CGFloat { max(safe.top, 47) + (compact ? 4 : 6) }
    var bottomPadding: CGFloat { max(safe.bottom, 20) + (compact ? 6 : 8) }

    /// Height left for the VStack after safe-area padding.
    var contentHeight: CGFloat {
        max(320, size.height - topPadding - bottomPadding)
    }

    var topBarHeight: CGFloat { compact ? 36 : 40 }
    var closeSize: CGFloat { compact ? 34 : 38 }
    var brandIcon: CGFloat { compact ? 24 : 28 }
    var brandFont: CGFloat { compact ? 20 : 22 }

    var chipFont: CGFloat { compact ? 11 : 12 }
    var chipPadH: CGFloat { compact ? 9 : 11 }
    var chipPadV: CGFloat { compact ? 5 : 6 }

    var sectionGap: CGFloat { compact ? 8 : 12 }
    var gapS: CGFloat { compact ? 4 : 6 }
    var gapM: CGFloat { compact ? 8 : 10 }
    var confirmGap: CGFloat { compact ? 8 : 10 }
    var metricGap: CGFloat { compact ? 4 : 6 }
    var panelPad: CGFloat { compact ? 10 : 12 }

    var weightFont: CGFloat { compact ? 56 : 64 }
    var weightHeight: CGFloat { compact ? 58 : 68 }
    var unitFont: CGFloat { compact ? 16 : 18 }
    var unitRowHeight: CGFloat { compact ? 22 : 24 }
    var subtitleFont: CGFloat { compact ? 12 : 13 }
    var subtitleHeight: CGFloat { compact ? 18 : 28 }

    var labelFont: CGFloat { compact ? 12 : 13 }
    var resistanceFont: CGFloat { compact ? 22 : 26 }
    var captionFont: CGFloat { 12 }
    var microFont: CGFloat { 10 }
    var hintFont: CGFloat { compact ? 12 : 13 }
    var hintMinHeight: CGFloat { compact ? 28 : 34 }
    var rowFont: CGFloat { compact ? 13 : 14 }
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
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 14 : 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, compact ? 11 : 13)
            .background(
                accent.opacity(configuration.isPressed ? 0.75 : 1.0),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}

struct ScaleSecondaryButtonStyle: ButtonStyle {
    let accent: Color
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 14 : 15, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)
            .padding(.vertical, compact ? 11 : 13)
            .background(
                .white.opacity(configuration.isPressed ? 0.35 : 0.55),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}

#Preview {
    LiveWeighInSheet()
        .environmentObject(ScaleSessionViewModel())
}
