import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                homeAtmosphere
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        brandHeader
                        privacyCard
                        profileSummary
                        discoverySection
                        homeActions
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                            .environmentObject(session)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.isWeighInPresented },
                set: { if !$0 { session.dismissWeighIn() } }
            )) {
                LiveWeighInSheet()
                    .environmentObject(session)
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.isResultsPresented },
                set: { if !$0 { session.dismissResults() } }
            )) {
                WeighInResultsView()
                    .environmentObject(session)
            }
            .task {
                await session.refreshHealthBaseline()
            }
        }
        .preferredColorScheme(.light)
    }

    private var homeAtmosphere: some View {
        LinearGradient(
            colors: [
                Color(red: 0.94, green: 0.96, blue: 0.98),
                Color(red: 0.88, green: 0.91, blue: 0.94),
                Color(red: 0.96, green: 0.95, blue: 0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("The Scale")
                        .font(.system(size: 36, weight: .semibold, design: .serif))
                    Text("Mi Body Composition Scale 2")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Text("On-device BLE → Apple Health. Live weigh-in, trend colors, body fat % and lean %, edit before you confirm. After save, weight and fat history charts open.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            if let baseline = session.healthBaselineKg {
                Text(String(format: "Last Health weight: %.2f kg", baseline))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if session.calibration.hasCorrection {
                Text(session.calibration.summaryLine)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Privacy", systemImage: "lock.shield")
                .font(.headline)
            Text("Measurements stay on this iPhone. The Scale reads recent Health weight only for on-device trend, and writes weight / BMI / body fat % / lean mass only after you confirm. Calibration stays on-device. No accounts, no cloud, no analytics.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var profileSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Profile & calibration")
                    .font(.headline)
                Spacer()
                NavigationLink("Settings") {
                    SettingsView()
                        .environmentObject(session)
                }
                .font(.subheadline.weight(.semibold))
            }
            Text(
                String(
                    format: "%.0f cm · %.0f yr · %@ · ref %.2f kg",
                    session.profile.heightCm,
                    session.profile.ageYears,
                    session.profile.sex.title,
                    session.calibration.referenceMassKg
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Text("Open Settings for height/age/sex. Calibrate by entering a known mass, then weighing it on the live sheet (same screen as a normal weigh-in).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nearby scales")
                .font(.headline)

            switch session.phase {
            case .scanning where session.discoveredScales.isEmpty:
                ProgressView("Scanning for MIBFS…")
            case .idle where session.discoveredScales.isEmpty:
                Text("Tap Find Scale, then step near the Mi Scale 2. Selecting a scale opens the live weigh-in sheet.")
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

            if case .bluetoothUnavailable(let message) = session.phase {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if case .healthKitSuccess = session.phase, !session.isWeighInPresented {
                Label("Last confirm saved to Apple Health", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Button {
                    session.reopenResults()
                } label: {
                    Label("Open history charts", systemImage: "chart.xyaxis.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var homeActions: some View {
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

            if session.selectedScaleID != nil {
                Button {
                    session.reopenWeighIn()
                } label: {
                    Label("Open live weigh-in", systemImage: "scalemass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                session.beginCalibrationWeighIn()
            } label: {
                Label("Calibrate with live sheet", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if !session.healthKitAvailable {
                Text("HealthKit unavailable in this environment (expected on Simulator without Health).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ScaleSessionViewModel())
}
