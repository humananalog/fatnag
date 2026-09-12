import SwiftUI

/// Profile + calibration setup. Live capture uses the same weigh-in sheet.
struct SettingsView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @FocusState private var focusedField: Field?
    @State private var confirmReset = false
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable {
        case reference
        case offset
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                profileCard
                calibrationCard
                privacyCard
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.96, blue: 0.98),
                    Color(red: 0.88, green: 0.91, blue: 0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .alert("Reset calibration?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                session.resetCalibration()
            }
        } message: {
            Text("Removes the stored scale factor and offset. Your reference mass value is kept.")
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your profile")
                .font(.headline)
            Text("Used only for on-device body fat % and lean % math.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Text("Height")
                Spacer()
                TextField(
                    "cm",
                    value: $session.profile.heightCm,
                    format: .number.precision(.fractionLength(0))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                Text("cm").foregroundStyle(.secondary)
            }

            HStack {
                Text("Age")
                Spacer()
                TextField(
                    "years",
                    value: $session.profile.ageYears,
                    format: .number.precision(.fractionLength(0))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                Text("yr").foregroundStyle(.secondary)
            }

            HStack {
                Text("Ideal weight")
                Spacer()
                TextField(
                    "kg",
                    value: $session.profile.idealWeightKg,
                    format: .number.precision(.fractionLength(1))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                Text("kg").foregroundStyle(.secondary)
            }

            HStack {
                Text("Ideal body fat")
                Spacer()
                TextField(
                    "%",
                    value: Binding(
                        get: { session.profile.idealBodyFatPercent ?? 0 },
                        set: { session.profile.idealBodyFatPercent = $0 > 0.05 ? $0 : nil }
                    ),
                    format: .number.precision(.fractionLength(1))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                Text("%").foregroundStyle(.secondary)
            }
            Text("Ideal weight floors the history weight chart and draws the Ideal line. Ideal body fat is optional: when set, the fat chart uses it the same way.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("Sex", selection: $session.profile.sex) {
                ForEach(UserBodyProfile.Sex.allCases) { sex in
                    Text(sex.title).tag(sex)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Weight calibration", systemImage: "slider.horizontal.3")
                .font(.headline)

            Text("Enter the true mass first, then open the live sheet and weigh that mass. Store the correction there. Same screen as a normal weigh-in.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. True mass (reference)")
                    .font(.subheadline.weight(.semibold))
                HStack {
                    Text("Known mass")
                    Spacer()
                    TextField(
                        "kg",
                        value: Binding(
                            get: { session.calibration.referenceMassKg },
                            set: { session.updateCalibrationReferenceMass($0) }
                        ),
                        format: .number.precision(.fractionLength(3))
                    )
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .reference)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 96)
                    Text("kg").foregroundStyle(.secondary)
                }
                Text("Examples: 5.000 kg plate, or Alex’s 7.926 kg known mass.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("2. Capture mode")
                    .font(.subheadline.weight(.semibold))
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
                Text(modeHelpText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                focusedField = nil
                session.beginCalibrationWeighIn()
                dismiss()
            } label: {
                Label("Weigh reference on live sheet", systemImage: "scalemass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                focusedField = nil
                // Alex: true 7.926 kg, scale showed 7.90 kg → offset +0.026 kg
                _ = session.recordCalibration(
                    referenceKg: 7.926,
                    rawKg: 7.90,
                    mode: .offset
                )
            } label: {
                Label("Store Alex’s 7.926 / 7.90 offset", systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 6) {
                Text("3. Current correction")
                    .font(.subheadline.weight(.semibold))
                Text(session.calibration.summaryLine)
                    .font(.footnote.weight(.medium))
                if let raw = session.calibration.lastCalibrationRawKg,
                   let at = session.calibration.calibratedAt {
                    Text(
                        String(
                            format: "Last capture: raw %.3f kg → reference %.3f kg on %@",
                            raw,
                            session.calibration.referenceMassKg,
                            at.formatted(date: .abbreviated, time: .shortened)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Toggle(
                    "Apply correction",
                    isOn: Binding(
                        get: { session.calibration.isActive },
                        set: { session.setCalibrationActive($0) }
                    )
                )
                .disabled(!session.calibration.hasCorrection && !session.calibration.isActive)

                HStack {
                    Text("Manual offset (kg)")
                    Spacer()
                    TextField(
                        "offset",
                        value: Binding(
                            get: { session.calibration.offsetKg },
                            set: { session.updateCalibrationOffset($0) }
                        ),
                        format: .number.precision(.fractionLength(3))
                    )
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focusedField, equals: .offset)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 88)
                }
                .font(.footnote)
            }

            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label("Reset calibration", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text("Limits: single-point only. Offset mode assumes a nearly constant bias; factor mode assumes proportional error. Neither is a multi-point fit. Body composition inputs from the scale are never altered by calibration.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Privacy", systemImage: "lock.shield")
                .font(.headline)
            Text("Calibration, profile, and measurements stay on this iPhone. HealthKit is the only destination after you confirm a weigh-in. No accounts, no cloud, no analytics.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var modeHelpText: String {
        switch session.calibration.captureMode {
        case .offset:
            return "Offset: corrected = raw + (true - raw). Good for a small constant bias (e.g. 7.90 vs 7.926)."
        case .factor:
            return "Factor: corrected = raw × (true / raw). Better when error grows with mass."
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(ScaleSessionViewModel())
    }
}
