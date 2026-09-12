import SwiftUI

/// Full-screen live weigh-in surface: trend atmosphere + live kg + edit-before-save.
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
                Spacer(minLength: 12)
                brandAndWeight
                Spacer(minLength: 12)
                statusCluster
                if session.phase == .ready || session.phase == .reviewing || session.isEditingDraft {
                    editAndConfirm
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .padding(.top, 8)
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

    private var topBar: some View {
        HStack {
            Button {
                session.dismissWeighIn()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(atmosphere.accent.opacity(0.85))
                    .padding(10)
                    .background(.white.opacity(0.35), in: Circle())
            }
            Spacer()
            trendChip
        }
    }

    private var trendChip: some View {
        let trend = session.trendForDisplay
        return HStack(spacing: 6) {
            Image(systemName: trendSymbol(trend))
            Text(trend.title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(atmosphere.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.white.opacity(0.4), in: Capsule())
    }

    private var brandAndWeight: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("The Scale")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundStyle(atmosphere.accent)
            }
            .opacity(0.95)

            VStack(spacing: 4) {
                Text(weightText)
                    .font(.system(size: 92, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.accent)
                    .scaleEffect(isLiveMeasuring ? (pulse ? 1.018 : 0.992) : 1.0)
                    .animation(
                        isLiveMeasuring
                            ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                            : .spring(response: 0.45, dampingFraction: 0.82),
                        value: session.displayWeightKg
                    )
                    .contentTransition(.numericText())

                Text("kg")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.7))
            }

            Text(session.trendForDisplay.subtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var statusCluster: some View {
        VStack(spacing: 10) {
            Text(session.liveHint)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(atmosphere.accent.opacity(0.85))
                .multilineTextAlignment(.center)

            if let ohms = session.latestMeasurement?.impedanceOhms ?? session.draft?.impedanceOhms {
                Text("Impedance \(ohms) Ω")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.accent)
            } else if case .awaitingImpedance = session.phase {
                Label("Waiting for barefoot impedance", systemImage: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.9))
            }

            if case .healthKitSuccess = session.phase {
                Label("Saved to Apple Health", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.42, blue: 0.32))
            }
            if case .healthKitFailed(let message) = session.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.48, green: 0.12, blue: 0.12))
            }
        }
        .padding(.bottom, 16)
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
        .padding(18)
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
                metricLine("BMI", draft.bmi.map { String(format: "%.1f", $0) } ?? "-")
                if let fat = draft.bodyFatPercent {
                    metricLine("Body fat", String(format: "%.1f%%", fat))
                }
                if let lean = draft.leanBodyMassKg {
                    metricLine("Lean mass", String(format: "%.2f kg", lean))
                }
                if draft.impedanceOhms == nil {
                    Text("Composition estimates need impedance. Edit weight freely; fat% stays off until ohms arrive.")
                        .font(.caption)
                        .foregroundStyle(atmosphere.accent.opacity(0.75))
                }
            }
        }
    }

    private func draftEditor(_ draft: EditableMeasurementDraft) -> some View {
        VStack(spacing: 10) {
            editRow(title: "Weight (kg)", value: draft.weightKg) { session.updateDraftWeight($0) }
            editIntRow(title: "Impedance (Ω)", value: draft.impedanceOhms) { session.updateDraftImpedance($0) }
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
            // Soft vignette / grain substitute: layered translucent ellipses
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
