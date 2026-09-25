import SwiftUI

/// Progress: sparse weekly % + Sunday target + Charts entry. Green on pace, lime when ahead.
/// Every tab visit runs a big-block ACTION entrance (staggered scale/slide, gauge fill, number punch).
struct ProgressSheet: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var coachReply: CoachReply?
    @State private var isCoaching = false
    @State private var showPrivacyGate = false

    /// Bumped on every Progress access so entrance always replays.
    @State private var entranceToken = 0
    @State private var statusIn = false
    @State private var heroIn = false
    @State private var percentScale: CGFloat = 0.55
    @State private var gaugeIn = false
    @State private var gaugeFill: Double = 0
    @State private var sundayIn = false
    @State private var deltaIn = false
    @State private var coachIn = false
    @State private var actionsIn = false
    @State private var displayedPercent = 0

    private var surface: WeeklyGoalSurface {
        session.weeklyGoalSurface
    }

    private var atmosphere: WeeklyGoalAtmosphere {
        WeeklyGoalAtmosphere.forBand(
            surface.band,
            colorScheme: colorScheme,
            sex: session.profile.sex
        )
    }

    private var atmosphereBaseFill: Color {
        colorScheme == .dark ? atmosphere.mid : atmosphere.top
    }

    private var percent: Int {
        surface.completionPercent
    }

    /// Visual fill max is 1.2 (120%) so "ahead" can overshoot the track without feeding ProgressView `value > total`.
    private var targetGauge: Double {
        ProgressBounds.clampedValue(Double(percent) / 100.0, total: 1.2)
    }

    /// Spring entrance can briefly overshoot; never paint outside `0...1.2`.
    private var safeGaugeFill: Double {
        ProgressBounds.clampedValue(gaugeFill, total: 1.2)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 28)

                statusBlock
                    .progressActionBlock(revealed: statusIn, reduceMotion: reduceMotion, slide: 36)

                heroPercentBlock
                    .progressActionBlock(revealed: heroIn, reduceMotion: reduceMotion, slide: 48)
                    .scaleEffect(percentScale, anchor: .leading)
                    .padding(.top, 6)

                Text("weekly progress")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.muted)
                    .padding(.top, 2)
                    .progressActionBlock(revealed: heroIn, reduceMotion: reduceMotion, slide: 28)

                chunkyGauge
                    .padding(.top, 18)
                    .progressActionBlock(revealed: gaugeIn, reduceMotion: reduceMotion, slide: 40)

                if surface.sundayTargetKg != nil {
                    sundayBlock
                        .padding(.top, 28)
                        .progressActionBlock(revealed: sundayIn, reduceMotion: reduceMotion, slide: 44)
                }

                Text(String(format: "%+.2f kg this week", surface.weeklyDeltaKg))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.accent)
                    .padding(.top, 6)
                    .progressActionBlock(revealed: deltaIn, reduceMotion: reduceMotion, slide: 32)

                Spacer(minLength: 24)

                coachBlock
                    .progressActionBlock(revealed: coachIn, reduceMotion: reduceMotion, slide: 28)

                actionsBlock
                    .progressActionBlock(revealed: actionsIn, reduceMotion: reduceMotion, slide: 52)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    atmosphereBaseFill
                    WeeklyGoalHazeBackground(atmosphere: atmosphere)
                }
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.55), value: session.profile.sex)
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
                refreshProgressData()
                // Always arm entrance on appear. TabView may preload this root while
                // homeTab is still `.weigh`; waiting for onChange alone left opacity-0
                // chrome on a night void (reads as a black screen).
                playEntrance()
            }
            .onChange(of: session.homeTab) { _, tab in
                // Re-fire every time the user tabs back to Progress (TabView keeps the root alive).
                guard tab == .progress else { return }
                refreshProgressData()
                playEntrance()
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

    private var statusBlock: some View {
        Text(surface.band.statusLabel.uppercased())
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .tracking(2.0)
            .foregroundStyle(atmosphere.accent)
    }

    private var heroPercentBlock: some View {
        Text("\(displayedPercent)%")
            .font(.system(size: 84, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(atmosphere.ink)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .accessibilityIdentifier("progress.percent")
            .accessibilityValue("\(percent) percent")
    }

    /// Thick ACTION gauge — fills 0 → value on each entrance (custom bar; not `ProgressView(value:)`).
    private var chunkyGauge: some View {
        GeometryReader { geo in
            let fill = safeGaugeFill
            let width = geo.size.width * CGFloat(fill / 1.2)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(atmosphere.ink.opacity(colorScheme == .dark ? 0.22 : 0.12))
                Capsule(style: .continuous)
                    .fill(atmosphere.accent)
                    .frame(width: max(width, fill > 0.001 ? 10 : 0))
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var sundayBlock: some View {
        if let sunday = surface.sundayTargetKg {
            Text(String(format: "Sunday %.2f kg", sunday))
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(atmosphere.ink)
                .accessibilityIdentifier("progress.sundayKg")
        }
    }

    @ViewBuilder
    private var coachBlock: some View {
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
    }

    private var actionsBlock: some View {
        VStack(spacing: 12) {
            Button {
                session.reopenResults()
            } label: {
                Label("Charts", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(atmosphere.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                atmosphere.ink.opacity(colorScheme == .dark ? 0.65 : 0.40),
                                lineWidth: 1.5
                            )
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("progress.charts")
            .accessibilityLabel("Open weight and body fat charts")

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
        }
        .padding(.bottom, 28)
    }

    private func refreshProgressData() {
        session.ensureWeeklyGoalBaseline()
        session.refreshAlreadyWeighedToday()
        session.rebuildWeeklyGoalSurface()
    }

    /// Reset → stagger in. Fires on every Progress tab access.
    private func playEntrance() {
        entranceToken &+= 1
        let token = entranceToken

        // Instant reset (no animation) so the next beat always starts from zero.
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            statusIn = false
            heroIn = false
            percentScale = reduceMotion ? 1 : 0.52
            gaugeIn = false
            gaugeFill = 0
            sundayIn = false
            deltaIn = false
            coachIn = false
            actionsIn = false
            displayedPercent = reduceMotion ? percent : 0
        }

        if reduceMotion {
            statusIn = true
            heroIn = true
            percentScale = 1
            gaugeIn = true
            gaugeFill = targetGauge
            sundayIn = true
            deltaIn = true
            coachIn = true
            actionsIn = true
            displayedPercent = percent
            return
        }

        // Athletic springs — punchy, not gentle fades.
        let punch = Animation.spring(response: 0.42, dampingFraction: 0.58)
        let settle = Animation.spring(response: 0.48, dampingFraction: 0.78)
        let block = Animation.spring(response: 0.50, dampingFraction: 0.72)
        let fill = Animation.spring(response: 0.72, dampingFraction: 0.82)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            guard token == entranceToken else { return }

            withAnimation(block) { statusIn = true }

            try? await Task.sleep(for: .milliseconds(70))
            guard token == entranceToken else { return }
            withAnimation(punch) {
                heroIn = true
                percentScale = 1.22
                displayedPercent = percent
            }

            try? await Task.sleep(for: .milliseconds(160))
            guard token == entranceToken else { return }
            withAnimation(settle) { percentScale = 1.0 }

            try? await Task.sleep(for: .milliseconds(50))
            guard token == entranceToken else { return }
            withAnimation(block) { gaugeIn = true }
            withAnimation(fill) { gaugeFill = targetGauge }

            try? await Task.sleep(for: .milliseconds(110))
            guard token == entranceToken else { return }
            withAnimation(block) { sundayIn = true }

            try? await Task.sleep(for: .milliseconds(90))
            guard token == entranceToken else { return }
            withAnimation(block) { deltaIn = true }

            try? await Task.sleep(for: .milliseconds(80))
            guard token == entranceToken else { return }
            withAnimation(block) { coachIn = true }

            try? await Task.sleep(for: .milliseconds(90))
            guard token == entranceToken else { return }
            withAnimation(punch) { actionsIn = true }
        }
    }

    private func runCoach() async {
        isCoaching = true
        defer { isCoaching = false }
        coachReply = await session.requestOrchestratorCoach()
        if session.homeTab == .progress {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                coachIn = true
            }
        }
    }
}

// MARK: - Block entrance

private extension View {
    /// Chunky section entrance: scale + slide up + opacity. Reduce Motion → opacity only / instant.
    /// Floor opacity at 0.04 so a missed entrance can never leave pure invisible ink on a void.
    @ViewBuilder
    func progressActionBlock(
        revealed: Bool,
        reduceMotion: Bool,
        slide: CGFloat
    ) -> some View {
        if reduceMotion {
            self.opacity(revealed ? 1 : 0.04)
        } else {
            self
                .opacity(revealed ? 1 : 0.04)
                .offset(y: revealed ? 0 : slide)
                .scaleEffect(revealed ? 1 : 0.72, anchor: .leading)
        }
    }
}

#Preview {
    ProgressSheet()
        .environmentObject(ScaleSessionViewModel())
}
