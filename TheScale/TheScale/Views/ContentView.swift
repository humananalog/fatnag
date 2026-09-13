import SwiftUI

/// Home: sparse brand + scan + History. Profile, calibration, and Health copy live in Settings.
struct ContentView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let steel = Color(red: 0.42, green: 0.45, blue: 0.50)

    var body: some View {
        NavigationStack {
            ZStack {
                homeAtmosphere
                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    brandBlock
                    Spacer(minLength: 28)
                    primaryActions
                    discoveryBlock
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                            .environmentObject(session)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.medium))
                            .foregroundStyle(ink.opacity(0.85))
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
            .fullScreenCover(isPresented: Binding(
                get: { session.isManualEntryPresented && !session.isResultsPresented },
                set: { if !$0 { session.dismissManualEntry() } }
            )) {
                ManualWeighInView()
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
                Color(red: 0.96, green: 0.97, blue: 0.98),
                Color(red: 0.90, green: 0.92, blue: 0.94),
                Color(red: 0.86, green: 0.88, blue: 0.90)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var brandBlock: some View {
        VStack(spacing: 18) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: ink.opacity(0.14), radius: 16, y: 6)

            Text("The Scale")
                .font(.system(size: 42, weight: .semibold, design: .serif))
                .foregroundStyle(ink)
                .tracking(-0.6)

            Text("Mi Scale 2 → Apple Health")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(steel)

            if let baseline = session.healthBaselineKg {
                Text(String(format: "%.1f kg", baseline))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(steel.opacity(0.9))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(brandAccessibilityLabel)
    }

    private var brandAccessibilityLabel: String {
        if let baseline = session.healthBaselineKg {
            return String(format: "The Scale. Last Health weight %.1f kilograms.", baseline)
        }
        return "The Scale"
    }

    private var primaryActions: some View {
        VStack(spacing: 12) {
            Button {
                session.startScanning()
            } label: {
                Text(session.phase == .scanning ? "Scanning…" : "Find Scale")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(ink)
            .disabled(session.phase == .scanning || session.phase == .healthKitWriting)

            Button {
                session.reopenResults()
            } label: {
                Label("History", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.bordered)
            .tint(ink)

            Button {
                session.presentManualEntry()
            } label: {
                Label("Manual", systemImage: "pencil.line")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.bordered)
            .tint(ink)
            .accessibilityHint("Log weight without the scale")

            if session.selectedScaleID != nil {
                Button {
                    session.reopenWeighIn()
                } label: {
                    Text("Weigh in")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(steel)
                .padding(.top, 4)
            }

            if case .healthKitSuccess = session.phase, !session.isWeighInPresented {
                Text("Saved to Health")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.34))
            }

            if !session.healthKitAvailable {
                Text("Health unavailable on this device.")
                    .font(.caption)
                    .foregroundStyle(steel)
            }
        }
    }

    @ViewBuilder
    private var discoveryBlock: some View {
        switch session.phase {
        case .scanning where session.discoveredScales.isEmpty:
            ProgressView()
                .padding(.top, 28)
                .tint(ink)
        case .bluetoothUnavailable(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color(red: 0.55, green: 0.12, blue: 0.12))
                .multilineTextAlignment(.center)
                .padding(.top, 24)
        default:
            if session.discoveredScales.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(session.discoveredScales) { scale in
                        Button {
                            session.selectScale(scale)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scale.name)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(ink)
                                    Text("RSSI \(scale.rssi) dBm")
                                        .font(.caption)
                                        .foregroundStyle(steel)
                                }
                                Spacer()
                                if session.selectedScaleID == scale.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(ink)
                                }
                            }
                            .padding(.vertical, 14)
                        }
                        if scale.id != session.discoveredScales.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .padding(.top, 28)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ScaleSessionViewModel())
}
