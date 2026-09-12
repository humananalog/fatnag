import SwiftUI

/// Profile + single-point scale calibration. All values stay on-device.
struct SettingsView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @State private var captureMessage: String?
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                profileCard
                calibrationCard
                privacyCard
            }
            .padding(20)
        }
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
        .alert("Reset calibration?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                session.resetCalibration()
                captureMessage = "Correction cleared. Raw scale kg will be used."
            }
        } message: {
            Text("Removes the stored scale factor and offset. Your reference mass value is kept.")
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

            Text("Place a known mass on the scale, enter its true weight, then capture. The Scale stores a single-point correction on this iPhone and applies it to live and saved weights.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Set reference mass")
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
                        format: .number.precision(.fractionLength(2))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 88)
                    Text("kg").foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("2. Weigh that mass")
                    .font(.subheadline.weight(.semibold))
                Text(rawReadingLine)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .monospacedDigit()
                Button {
                    let ok = session.captureCalibrationFromCurrentReading()
                    captureMessage = ok
                        ? "Captured. Correction is active for live weigh-ins and Health saves."
                        : "Need a positive raw reading first. Open live weigh-in, place the known mass, wait for a stable kg, then try again."
                } label: {
                    Label("Capture reading & store correction", systemImage: "plus.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("3. Current correction")
                    .font(.subheadline.weight(.semibold))
                Text(session.calibration.summaryLine)
                    .font(.footnote.weight(.medium))
                if let raw = session.calibration.lastCalibrationRawKg,
                   let at = session.calibration.calibratedAt {
                    Text(
                        String(
                            format: "Last capture: raw %.2f kg → reference %.2f kg on %@",
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

            Text("Limits: this is single-point calibration (one known mass). It corrects well near that mass; error can grow at very different weights. Multi-point / linear-fit calibration is not supported. Impedance (ohms) is never altered.")
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

    private var rawReadingLine: String {
        if let raw = session.rawDisplayWeightKg {
            let corrected = session.calibration.apply(toRawKg: raw)
            if session.calibration.hasCorrection {
                return String(format: "Latest raw %.2f kg → corrected %.2f kg", raw, corrected)
            }
            return String(format: "Latest raw reading: %.2f kg", raw)
        }
        return "No reading yet. Find the scale and open live weigh-in with the known mass on the platform."
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(ScaleSessionViewModel())
    }
}
