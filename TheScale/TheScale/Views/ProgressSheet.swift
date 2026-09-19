import SwiftUI

/// Progress: weekly mini-goal + optional Grok orchestrator roast.
struct ProgressSheet: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var coachReply: CoachReply?
    @State private var isCoaching = false
    @State private var showPrivacyGate = false
    @State private var goalDelta: Double = -0.3

    private var atmosphere: TrendAtmosphere {
        TrendAtmosphere.forTrend(session.trendForDisplay)
    }

    private var name: String {
        let n = session.profile.greetingName
        return n.isEmpty ? "You" : n
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    weeklyCard
                    coachCard
                    privacyNote
                }
                .padding(20)
            }
            .background {
                TrendAtmosphereBackground(atmosphere: atmosphere)
                    .ignoresSafeArea()
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                goalDelta = session.weeklyGoal.targetDeltaKg
                session.ensureWeeklyGoalBaseline()
            }
            .alert("Send trend summary to Grok?", isPresented: $showPrivacyGate) {
                Button("Cancel", role: .cancel) {}
                Button("Agree & coach") {
                    GrokPrivacyConsent.isAccepted = true
                    Task { await runCoach() }
                }
            } message: {
                Text("Only a short weight/fat trend summary (no raw impedance, no Health dump) goes to the shared Grok backend when you tap Coach. You can revoke consent in Settings.")
            }
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(name), here's the week.")
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .foregroundStyle(atmosphere.accent)
            if let kg = session.healthBaselineKg {
                Text(String(format: "Last Health weight %.1f kg · ideal %.1f kg", kg, session.profile.idealWeightKg))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.7))
            }
        }
    }

    private var weeklyCard: some View {
        let fraction = session.weeklyGoal.progressFraction(currentKg: session.healthBaselineKg) ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            Text("Weekly mini-goal")
                .font(.headline)
                .foregroundStyle(atmosphere.accent)
            Text(session.weeklyGoal.title)
                .font(.subheadline.weight(.semibold))
            ProgressView(value: min(fraction, 1))
                .tint(atmosphere.accent)
            Text(session.weeklyGoal.statusLine(currentKg: session.healthBaselineKg))
                .font(.footnote)
                .foregroundStyle(atmosphere.accent.opacity(0.75))

            HStack {
                Text("Target delta kg")
                Spacer()
                TextField(
                    "kg",
                    value: $goalDelta,
                    format: .number.precision(.fractionLength(2))
                )
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                .onChange(of: goalDelta) { _, newValue in
                    session.updateWeeklyGoalDelta(newValue)
                }
            }
            .font(.footnote)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleGlassPanel(cornerRadius: 18)
    }

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Coach", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(atmosphere.accent)

            if isCoaching {
                ProgressView("Consulting the peanut gallery…")
            } else if let coachReply {
                Text(coachReply.text)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.accent.opacity(0.9))
                HStack {
                    Text(coachReply.usedNetwork ? "Grok · live" : "Offline fallback")
                        .font(.caption2.weight(.semibold))
                    Spacer()
                    Text(coachReply.role.title)
                        .font(.caption2)
                }
                .foregroundStyle(atmosphere.accent.opacity(0.55))
                Text(coachReply.disclaimer)
                    .font(.caption2)
                    .foregroundStyle(atmosphere.accent.opacity(0.5))
            } else {
                Text("Want a short roast of your week? Offline mock always works; live Grok needs shared build config + consent.")
                    .font(.footnote)
                    .foregroundStyle(atmosphere.accent.opacity(0.7))
            }

            Button {
                if GrokPrivacyConsent.isAccepted || !GrokSharedConfig.isLiveConfigured {
                    Task { await runCoach() }
                } else {
                    showPrivacyGate = true
                }
            } label: {
                Text(GrokSharedConfig.isLiveConfigured ? "Quick roast" : "Quick roast (offline)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCoaching)

            Button {
                dismiss()
                session.presentCoach()
            } label: {
                Label("Open multi-agent chat", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleGlassPanel(cornerRadius: 18)
    }

    private var privacyNote: some View {
        Text("Privacy: weigh-ins stay on-device / Apple Health. Grok only runs when you tap Coach after consent. Shared key is operator-managed; revoke consent anytime in Settings.")
            .font(.caption2)
            .foregroundStyle(atmosphere.accent.opacity(0.55))
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
