import SwiftUI

/// Progress: sparse weekly % + Sunday target. Green on pace, lime when ahead.
struct ProgressSheet: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var coachReply: CoachReply?
    @State private var isCoaching = false
    @State private var showPrivacyGate = false

    private var surface: WeeklyGoalSurface {
        session.weeklyGoalSurface
    }

    private var atmosphere: WeeklyGoalAtmosphere {
        WeeklyGoalAtmosphere.forBand(surface.band, colorScheme: colorScheme)
    }

    private var percent: Int {
        surface.completionPercent
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WeeklyGoalHazeBackground(atmosphere: atmosphere)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 28)

                    Text(surface.band.statusLabel.uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(2.0)
                        .foregroundStyle(atmosphere.accent)

                    Text("\(percent)%")
                        .font(.system(size: 84, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(atmosphere.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .padding(.top, 6)
                        .accessibilityIdentifier("progress.percent")

                    Text("weekly progress")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(atmosphere.muted)
                        .padding(.top, 2)

                    ProgressView(value: min(Double(percent) / 100.0, 1.2), total: 1.0)
                        .tint(atmosphere.accent)
                        .padding(.top, 18)

                    if let sunday = surface.sundayTargetKg {
                        Text(String(format: "Sunday %.2f kg", sunday))
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundStyle(atmosphere.ink)
                            .padding(.top, 28)
                            .accessibilityIdentifier("progress.sundayKg")
                    }

                    Text(String(format: "%+.2f kg this week", surface.weeklyDeltaKg))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(atmosphere.accent)
                        .padding(.top, 6)

                    Spacer(minLength: 24)

                    if isCoaching {
                        ProgressView()
                            .tint(atmosphere.accent)
                            .padding(.bottom, 12)
                    } else if let coachReply {
                        Text(coachReply.text)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(atmosphere.ink.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(5)
                            .minimumScaleFactor(0.85)
                            .padding(.bottom, 14)
                    }

                    Button {
                        if GrokPrivacyConsent.isAccepted || !GrokSharedConfig.isLiveConfigured {
                            Task { await runCoach() }
                        } else {
                            showPrivacyGate = true
                        }
                    } label: {
                        Text(GrokSharedConfig.isLiveConfigured ? "Keel roast" : "Keel roast (offline)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(colorScheme == .dark ? atmosphere.ink : Color(red: 0.04, green: 0.05, blue: 0.07))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(atmosphere.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isCoaching)
                    .padding(.bottom, 28)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if session.alreadyWeighedToday {
                        Button("Manual") { session.presentManualEntry() }
                    } else if session.weighNowGateResolved {
                        Button("Weigh") { session.selectHomeTab(.weigh) }
                    }
                }
            }
            .onAppear {
                session.ensureWeeklyGoalBaseline()
                session.refreshAlreadyWeighedToday()
                session.rebuildWeeklyGoalSurface()
            }
            .alert("Send trend summary to Keel?", isPresented: $showPrivacyGate) {
                Button("Cancel", role: .cancel) {}
                Button("Agree & coach") {
                    GrokPrivacyConsent.isAccepted = true
                    Task { await runCoach() }
                }
            } message: {
                Text("Only a short weight/fat trend summary goes to Keel when you tap roast. Revoke in Settings.")
            }
        }
    }

    private func runCoach() async {
        isCoaching = true
        defer { isCoaching = false }
        coachReply = await session.requestOrchestratorCoach()
    }
}

#Preview {
    ProgressSheet()
        .environmentObject(ScaleSessionViewModel())
}
