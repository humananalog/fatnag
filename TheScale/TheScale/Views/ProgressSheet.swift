import SwiftUI

/// Progress: week-start → Sunday target → %/gauge → roast. Green on pace, lime when ahead.
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
    @State private var weekStartIn = false
    @State private var sundayIn = false
    @State private var heroIn = false
    @State private var percentScale: CGFloat = 0.55
    @State private var weekStartScale: CGFloat = 0.72
    @State private var sundayScale: CGFloat = 0.72
    @State private var gaugeIn = false
    @State private var gaugeFill: Double = 0
    @State private var deltaIn = false
    @State private var coachIn = false
    @State private var actionsIn = false
    @State private var displayedPercent = 0

    private var surface: WeeklyGoalSurface {
        session.weeklyGoalSurface
    }

    private var units: PreferredUnitSystem {
        session.preferredUnits
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

    /// Roast body: Glacier Forge / Bloom Copper ink at full strength for night contrast.
    private var roastInk: Color {
        colorScheme == .dark ? atmosphere.ink : atmosphere.ink.opacity(0.94)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statusBlock
                        .padding(.top, 20)
                        .progressActionBlock(revealed: statusIn, reduceMotion: reduceMotion, slide: 48, fromScale: 0.55)

                    weekHeroBlock
                        .padding(.top, 18)
                        .scaleEffect(weekStartScale, anchor: .leading)
                        .progressActionBlock(revealed: weekStartIn, reduceMotion: reduceMotion, slide: 56, fromScale: 0.48)

                    sundayHeroBlock
                        .padding(.top, 16)
                        .scaleEffect(sundayScale, anchor: .leading)
                        .progressActionBlock(revealed: sundayIn, reduceMotion: reduceMotion, slide: 56, fromScale: 0.48)

                    heroPercentBlock
                        .padding(.top, 28)
                        .progressActionBlock(revealed: heroIn, reduceMotion: reduceMotion, slide: 64, fromScale: 0.42)
                        .scaleEffect(percentScale, anchor: .leading)

                    Text("weekly progress")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(atmosphere.muted)
                        .padding(.top, 4)
                        .progressActionBlock(revealed: heroIn, reduceMotion: reduceMotion, slide: 36, fromScale: 0.62)

                    chunkyGauge
                        .padding(.top, 16)
                        .progressActionBlock(revealed: gaugeIn, reduceMotion: reduceMotion, slide: 52, fromScale: 0.5)

                    Text("\(UnitFormat.massDeltaString(surface.weeklyDeltaKg, system: units)) this week")
                        .font(.system(size: surface.weeklyDeltaKg < -0.001 ? 28 : 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(atmosphere.accent)
                        .padding(.top, 10)
                        .progressActionBlock(revealed: deltaIn, reduceMotion: reduceMotion, slide: 40, fromScale: 0.58)
                        .accessibilityIdentifier("progress.weekDelta")

                    if surface.weeklyDeltaKg < -0.001 {
                        Text("You're a winner.")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(atmosphere.ink)
                            .accessibilityIdentifier("progress.weekWinner")
                    }

                    coachBlock
                        .padding(.top, 28)
                        .progressActionBlock(revealed: coachIn, reduceMotion: reduceMotion, slide: 44, fromScale: 0.62)

                    actionsBlock
                        .padding(.top, 18)
                        .progressActionBlock(revealed: actionsIn, reduceMotion: reduceMotion, slide: 60, fromScale: 0.5)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
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
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .tracking(2.2)
            .foregroundStyle(atmosphere.accent)
    }

    @ViewBuilder
    private var weekHeroBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WEEK START")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(atmosphere.muted)
            if let start = surface.weekStartKg {
                Text(UnitFormat.massString(start, system: units, fractionDigits: 1))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityIdentifier("progress.weekStartKg")
            } else {
                Text("—")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(atmosphere.muted)
                    .accessibilityIdentifier("progress.weekStartKg")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(weekStartAccessibility)
    }

    @ViewBuilder
    private var sundayHeroBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SUNDAY TARGET")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(atmosphere.muted)
            if let sunday = surface.sundayTargetKg {
                Text(UnitFormat.massString(sunday, system: units, fractionDigits: 1))
                    .font(.system(size: 52, weight: .bold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityIdentifier("progress.sundayKg")
            } else {
                Text("—")
                    .font(.system(size: 52, weight: .bold, design: .serif))
                    .foregroundStyle(atmosphere.muted)
                    .accessibilityIdentifier("progress.sundayKg")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sundayAccessibility)
    }

    private var weekStartAccessibility: String {
        if let start = surface.weekStartKg {
            return "Week start \(UnitFormat.massString(start, system: units, fractionDigits: 1))"
        }
        return "Week start not locked"
    }

    private var sundayAccessibility: String {
        if let sunday = surface.sundayTargetKg {
            return "Sunday target \(UnitFormat.massString(sunday, system: units, fractionDigits: 1))"
        }
        return "Sunday target unavailable"
    }

    private var heroPercentBlock: some View {
        Text("\(displayedPercent)%")
            .font(.system(size: 96, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(atmosphere.ink)
            .minimumScaleFactor(0.65)
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
                    .frame(width: max(width, fill > 0.001 ? 14 : 0))
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var coachBlock: some View {
        if isCoaching {
            ProgressView()
                .tint(atmosphere.accent)
                .padding(.bottom, 8)
        } else if let coachReply {
            Text(coachReply.text)
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .foregroundStyle(roastInk)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .lineLimit(8)
                .minimumScaleFactor(0.9)
                .padding(.bottom, 8)
                .accessibilityIdentifier("progress.roast")
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
        .padding(.bottom, 12)
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
            weekStartIn = false
            sundayIn = false
            heroIn = false
            percentScale = reduceMotion ? 1 : 0.34
            weekStartScale = reduceMotion ? 1 : 0.42
            sundayScale = reduceMotion ? 1 : 0.42
            gaugeIn = false
            gaugeFill = 0
            deltaIn = false
            coachIn = false
            actionsIn = false
            displayedPercent = reduceMotion ? percent : 0
        }

        if reduceMotion {
            statusIn = true
            weekStartIn = true
            sundayIn = true
            heroIn = true
            percentScale = 1
            weekStartScale = 1
            sundayScale = 1
            gaugeIn = true
            gaugeFill = targetGauge
            deltaIn = true
            coachIn = true
            actionsIn = true
            displayedPercent = percent
            return
        }

        // Athletic springs — bigger punches, clearer staggers (not gentle fades).
        let punch = Animation.spring(response: 0.38, dampingFraction: 0.52)
        let overshoot = Animation.spring(response: 0.36, dampingFraction: 0.48)
        let settle = Animation.spring(response: 0.46, dampingFraction: 0.74)
        let block = Animation.spring(response: 0.46, dampingFraction: 0.68)
        let fill = Animation.spring(response: 0.88, dampingFraction: 0.78)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(24))
            guard token == entranceToken else { return }

            withAnimation(block) { statusIn = true }

            try? await Task.sleep(for: .milliseconds(90))
            guard token == entranceToken else { return }
            withAnimation(overshoot) {
                weekStartIn = true
                weekStartScale = 1.18
            }

            try? await Task.sleep(for: .milliseconds(140))
            guard token == entranceToken else { return }
            withAnimation(settle) { weekStartScale = 1.0 }
            withAnimation(overshoot) {
                sundayIn = true
                sundayScale = 1.2
            }

            try? await Task.sleep(for: .milliseconds(150))
            guard token == entranceToken else { return }
            withAnimation(settle) { sundayScale = 1.0 }
            withAnimation(punch) {
                heroIn = true
                percentScale = 1.34
                displayedPercent = percent
            }

            try? await Task.sleep(for: .milliseconds(180))
            guard token == entranceToken else { return }
            withAnimation(settle) { percentScale = 1.0 }

            try? await Task.sleep(for: .milliseconds(40))
            guard token == entranceToken else { return }
            withAnimation(block) { gaugeIn = true }
            withAnimation(fill) { gaugeFill = targetGauge }

            try? await Task.sleep(for: .milliseconds(130))
            guard token == entranceToken else { return }
            withAnimation(block) { deltaIn = true }

            try? await Task.sleep(for: .milliseconds(100))
            guard token == entranceToken else { return }
            withAnimation(block) { coachIn = true }

            try? await Task.sleep(for: .milliseconds(110))
            guard token == entranceToken else { return }
            withAnimation(punch) { actionsIn = true }
        }
    }

    private func runCoach() async {
        isCoaching = true
        defer { isCoaching = false }
        coachReply = await session.requestOrchestratorCoach()
        if session.homeTab == .progress {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
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
        slide: CGFloat,
        fromScale: CGFloat = 0.58
    ) -> some View {
        if reduceMotion {
            self.opacity(revealed ? 1 : 0.04)
        } else {
            self
                .opacity(revealed ? 1 : 0.04)
                .offset(y: revealed ? 0 : slide)
                .scaleEffect(revealed ? 1 : fromScale, anchor: .leading)
        }
    }
}

#Preview {
    ProgressSheet()
        .environmentObject(ScaleSessionViewModel())
}
