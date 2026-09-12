import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    privacyCard
                    profileSection
                    statusSection
                    discoverySection
                    readingSection
                    actions
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("The Scale")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mi Body Composition Scale 2")
                .font(.title2.weight(.semibold))
            Text("On-device BLE → Apple Health. No accounts, no cloud, no analytics.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Privacy", systemImage: "lock.shield")
                .font(.headline)
            Text("Measurements stay on this iPhone. The Scale writes only weight, BMI, body fat %, and lean body mass to Apple Health when you confirm. Muscle, bone, water, and impedance stay in the app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your profile")
                .font(.headline)
            Text("Needed to estimate body composition from impedance. Stored only in this app’s UserDefaults.")
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
                Text("cm")
                    .foregroundStyle(.secondary)
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
                Text("yr")
                    .foregroundStyle(.secondary)
            }

            Picker("Sex", selection: $session.profile.sex) {
                ForEach(UserBodyProfile.Sex.allCases) { sex in
                    Text(sex.title).tag(sex)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)
            Text(statusText)
                .font(.body)
            Text(session.liveHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nearby scales")
                .font(.headline)

            switch session.phase {
            case .scanning where session.discoveredScales.isEmpty:
                ProgressView("Scanning for MIBFS…")
            case .idle where session.discoveredScales.isEmpty:
                Text("Tap Find Scale, then step near the Mi Scale 2.")
                    .foregroundStyle(.secondary)
            default:
                if session.discoveredScales.isEmpty {
                    Text("No scales yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.discoveredScales) { scale in
                        Button {
                            session.selectScale(scale)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scale.name)
                                        .foregroundStyle(.primary)
                                    Text("RSSI \(scale.rssi) dBm")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if session.selectedScaleID == scale.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latest reading")
                .font(.headline)

            if let measurement = session.latestMeasurement {
                metricRow("Weight", String(format: "%.2f kg", measurement.weightKg))
                if let ohms = measurement.impedanceOhms {
                    metricRow("Impedance", "\(ohms) Ω")
                } else {
                    Text("No impedance yet: stand barefoot until the scale finishes BIA.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let composition = session.composition {
                    Divider()
                    metricRow("BMI", String(format: "%.1f", composition.bmi))
                    metricRow("Body fat", String(format: "%.1f%%", composition.bodyFatPercent))
                    metricRow("Water", String(format: "%.1f%%", composition.waterPercent))
                    metricRow("Muscle", String(format: "%.2f kg", composition.muscleMassKg))
                    metricRow("Bone", String(format: "%.2f kg", composition.boneMassKg))
                    metricRow("Lean mass", String(format: "%.2f kg", composition.leanBodyMassKg))
                    metricRow("Visceral fat", String(format: "%.1f", composition.visceralFat))
                }
            } else {
                Text("No measurement yet.")
                    .foregroundStyle(.secondary)
            }

            if case .healthKitSuccess = session.phase {
                Label("Saved to Apple Health", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            if case .healthKitFailed(let message) = session.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                session.startScanning()
            } label: {
                Label(
                    session.phase == .scanning ? "Scanning…" : "Find Scale",
                    systemImage: "dot.radiowaves.left.and.right"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.phase == .scanning || session.phase == .healthKitWriting)

            Button {
                Task { await session.saveToHealth() }
            } label: {
                Label(
                    session.phase == .healthKitWriting ? "Writing…" : "Save to Apple Health",
                    systemImage: "heart"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(session.latestMeasurement == nil || session.phase == .healthKitWriting)

            if !session.healthKitAvailable {
                Text("HealthKit unavailable in this environment (expected on Simulator without Health).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private var statusText: String {
        switch session.phase {
        case .idle:
            return "Ready"
        case .scanning:
            return "Scanning for scale"
        case .listening(let name):
            return "Listening to \(name)"
        case .measuring:
            return "Receiving measurement"
        case .ready:
            return "Measurement ready"
        case .healthKitWriting:
            return "Writing to Apple Health…"
        case .healthKitSuccess:
            return "Apple Health write succeeded"
        case .healthKitFailed:
            return "Apple Health write failed"
        case .bluetoothUnavailable(let message):
            return message
        case .error(let message):
            return message
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ScaleSessionViewModel())
}
