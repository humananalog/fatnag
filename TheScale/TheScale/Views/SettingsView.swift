import SwiftUI

/// Profile + single-point scale calibration. All values stay on-device.
struct SettingsView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @FocusState private var focusedField: Field?
    @State private var captureMessage: String?
    @State private var showCaptureAlert = false
    @State private var captureAlertTitle = ""
    @State private var captureAlertBody = ""
    @State private var confirmReset = false

    private enum Field: Hashable {
        case reference
        case raw
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
        .alert(captureAlertTitle, isPresented: $showCaptureAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(captureAlertBody)
        }
        .alert("Reset calibration?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                session.resetCalibration()
                captureMessage = "Correction cleared. Raw scale kg will be used."
            }
        } message: {
            Text("Removes the stored scale factor and offset. Your reference mass value is kept.")
        }
        .onAppear {
            // Prefill raw field from last BLE reading so Capture works after leaving the live sheet.
            if session.manualCalibrationRawKg == nil, let last = session.lastRawWeightKg {
                session.manualCalibrationRawKg = last
            }
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your profile")
                .font(.headline)
            Text("Used only for on-device body composition math from impedance.")
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

            Text("Enter the true mass and what the scale / app read, then capture. Default mode stores an offset (true − raw). You can also use a scale factor. Correction stays on this iPhone.")
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
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("2. Scale reading (raw)")
                    .font(.subheadline.weight(.semibold))
                Text(rawStatusLine)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .monospacedDigit()
                HStack {
                    Text("Raw reading")
                    Spacer()
                    TextField(
                        "kg",
                        value: Binding(
                            get: { session.manualCalibrationRawKg ?? session.lastRawWeightKg ?? 0 },
                            set: { session.manualCalibrationRawKg = $0 }
                        ),
                        format: .number.precision(.fractionLength(3))
                    )
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .raw)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 96)
                    Text("kg").foregroundStyle(.secondary)
                }
                Text("Type the kg the scale showed if Capture had nothing to work with (common when Settings was open without a live BLE reading).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("3. Capture mode")
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    runCapture()
                }
            } label: {
                Label("Capture reading & store correction", systemImage: "plus.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                focusedField = nil
                // Alex: true 7.926 kg, scale showed 7.90 kg → offset +0.026 kg
                let ok = session.recordCalibration(
                    referenceKg: 7.926,
                    rawKg: 7.90,
                    mode: .offset
                )
                presentCaptureResult(
                    ok: ok,
                    successBody: String(
                        format: "Stored offset %+.3f kg (raw 7.900 → true 7.926). Live and saved weights use this.",
                        7.926 - 7.90
                    ),
                    failureBody: "Could not store that pair. Check the numbers and try again."
                )
            } label: {
                Label("Store Alex’s 7.926 / 7.90 offset", systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 6) {
                Text("4. Current correction")
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

            if let captureMessage {
                Text(captureMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Limits: single-point only. Offset mode assumes a nearly constant bias; factor mode assumes proportional error. Neither is a multi-point fit. Impedance (ohms) is never altered.")
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

    private var rawStatusLine: String {
        if let raw = session.calibrationSourceRawKg {
            let corrected = session.calibration.apply(toRawKg: raw)
            if session.calibration.hasCorrection {
                return String(format: "Using raw %.3f kg → corrected %.3f kg", raw, corrected)
            }
            return String(format: "Using raw %.3f kg (no correction yet)", raw)
        }
        return "No raw kg yet. Type what the scale showed, or open live weigh-in first."
    }

    private var modeHelpText: String {
        switch session.calibration.captureMode {
        case .offset:
            return "Offset: corrected = raw + (true − raw). Good for a small constant bias (e.g. 7.90 vs 7.926)."
        case .factor:
            return "Factor: corrected = raw × (true / raw). Better when error grows with mass."
        }
    }

    private func runCapture() {
        let ok = session.captureCalibrationFromCurrentReading()
        let raw = session.calibrationSourceRawKg
        let ref = session.calibration.referenceMassKg
        presentCaptureResult(
            ok: ok,
            successBody: {
                if let raw {
                    let offset = session.calibration.offsetKg
                    let factor = session.calibration.scaleFactor
                    return String(
                        format: "Stored from raw %.3f kg → true %.3f kg. Factor ×%.5f, offset %+.3f kg. Apply is on.",
                        raw,
                        ref,
                        factor,
                        offset
                    )
                }
                return "Correction stored and active."
            }(),
            failureBody: "Need a positive raw reading. Type the kg the scale showed in “Raw reading”, or open live weigh-in with the mass on the platform, then try again."
        )
    }

    private func presentCaptureResult(ok: Bool, successBody: String, failureBody: String) {
        if ok {
            captureAlertTitle = "Calibration saved"
            captureAlertBody = successBody
            captureMessage = successBody
        } else {
            captureAlertTitle = "Nothing captured"
            captureAlertBody = failureBody
            captureMessage = failureBody
        }
        showCaptureAlert = true
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(ScaleSessionViewModel())
    }
}
