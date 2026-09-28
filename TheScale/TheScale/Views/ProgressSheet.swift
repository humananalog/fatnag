import SwiftUI

/// Progress: week-start → arrow → Sunday target, then pace chrome. Green on pace, lime when ahead.
/// Every tab visit replays a big hero entrance. A warmed data cache must not skip that motion.
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
    /// Chevron runway between week-start and Sunday. Cascades on each entrance.
    @State private var arrowIn = false
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

    /// Monday has no pace yet. Percent, gauge, and deltas would all read as noise.
    private var showsPaceChrome: Bool {
        surface.weekMoment != .mondayFresh
    }

    /// Big number punch. View-level so it still runs after an awaited stagger.
    private var punchSpring: Animation {
        .spring(response: 0.34, dampingFraction: 0.45)
    }

    private var heroSpring: Animation {
        .spring(response: 0.4, dampingFraction: 0.48)
    }

    private var arrowSpring: Animation {
        .spring(response: 0.42, dampingFraction: 0.62)
    }

    private var gaugeSpring: Animation {
        .spring(response: 0.9, dampingFraction: 0.8)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statusBlock
                        .padding(.top, 20)
                        .progressActionBlock(revealed: statusIn, reduceMotion: reduceMotion, slide: 48, fromScale: 0.55)

                    if showsPaceChrome || surface.weekStartKg == nil || surface.sundayTargetKg == nil {
                        momentCaption
                            .padding(.top, 6)
                            .progressActionBlock(revealed: statusIn, reduceMotion: reduceMotion, slide: 28, fromScale: 0.7)
                    }

                    weekJourney
                        .padding(.top, showsPaceChrome ? 18 : 28)

                    if showsPaceChrome {
                        heroPercentBlock
                            .padding(.top, 28)
                            .progressActionBlock(revealed: heroIn, reduceMotion: reduceMotion, slide: 72, fromScale: 0.28)
                            .scaleEffect(percentScale, anchor: .leading)
                            .animation(heroSpring, value: percentScale)

                        Text(progressCaption)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(atmosphere.muted)
                            .padding(.top, 4)
                            .progressActionBlock(revealed: heroIn, reduceMotion: reduceMotion, slide: 36, fromScale: 0.62)

                        chunkyGauge
                            .padding(.top, 16)
                            .progressActionBlock(revealed: gaugeIn, reduceMotion: reduceMotion, slide: 52, fromScale: 0.5)
                            .animation(gaugeSpring, value: gaugeFill)

                        deltaBlock
                            .padding(.top, 10)
                            .progressActionBlock(revealed: deltaIn, reduceMotion: reduceMotion, slide: 40, fromScale: 0.58)
                    }

                    if surface.isWinnerWeek {
                        Text(String(localized: "home.winner", defaultValue: "You're a winner."))
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
            .navigationTitle(String(localized: "progress.title", defaultValue: "Progress"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if session.alreadyWeighedToday {
                        Button(String(localized: "common.manual", defaultValue: "Manual")) { session.presentManualEntry() }
                    } else if session.weighNowGateResolved {
                        Button(String(localized: "common.weigh", defaultValue: "Weigh")) { session.selectHomeTab(.weigh) }
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
            .alert(
                String(localized: "progress.privacy.title", defaultValue: "Send trend summary to Keel?"),
                isPresented: $showPrivacyGate
            ) {
                Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
                Button(String(localized: "progress.privacy.agree", defaultValue: "Agree & coach")) {
                    GrokPrivacyConsent.isAccepted = true
                    Task { await runCoach() }
                }
            } message: {
                Text(String(localized: "progress.privacy.body", defaultValue: "Only a short weight/fat trend summary goes to Keel when you tap roast. Revoke in Settings."))
            }
        }
    }

    private var statusBlock: some View {
        Text(surface.statusHeadline.uppercased())
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .tracking(2.2)
            .foregroundStyle(atmosphere.accent)
            .accessibilityIdentifier("progress.status")
    }

    private var momentCaption: some View {
        Text(surface.detailLine)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(atmosphere.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("progress.detail")
    }

    private var progressCaption: String {
        switch surface.weekMoment {
        case .mondayFresh:
            return String(localized: "progress.caption.monday_fresh", defaultValue: "week just opened")
        case .earlyWeek:
            return String(localized: "progress.caption.early_week", defaultValue: "early-week pace")
        case .midWeek:
            return String(localized: "progress.caption.mid_week", defaultValue: "mid-week progress")
        case .lateWeek:
            return String(localized: "progress.caption.late_week", defaultValue: "finish to Sunday")
        }
    }

    private var deltaBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(
                format: String(localized: "progress.goal_delta", defaultValue: "Goal %@"),
                UnitFormat.massDeltaString(surface.weeklyDeltaKg, system: units)
            ))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(atmosphere.accent)
                .accessibilityIdentifier("progress.weekDelta")

            if let moved = surface.movedDeltaKg {
                Text(String(
                    format: String(localized: "progress.moved_so_far", defaultValue: "Moved %@ so far"),
                    UnitFormat.massDeltaString(moved, system: units)
                ))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(atmosphere.ink.opacity(0.78))
                    .accessibilityIdentifier("progress.movedDelta")
            } else {
                Text(String(localized: "progress.lock_move", defaultValue: "Weigh in to lock this week's move"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.muted)
                    .accessibilityIdentifier("progress.movedDelta")
            }
        }
    }

    /// Week start kg  ›››››  Sunday target. The only hero on Monday.
    private var weekJourney: some View {
        HStack(alignment: .center, spacing: 8) {
            journeyColumn(
                title: String(localized: "progress.week_start", defaultValue: "WEEK START"),
                kilograms: surface.weekStartKg,
                alignment: .leading,
                size: showsPaceChrome ? 30 : 36,
                design: .rounded,
                identifier: "progress.weekStartKg",
                accessibility: weekStartAccessibility
            )
            .scaleEffect(weekStartScale, anchor: .center)
            .animation(punchSpring, value: weekStartScale)
            .progressActionBlock(
                revealed: weekStartIn,
                reduceMotion: reduceMotion,
                slide: 36,
                fromScale: 0.32,
                anchor: .center
            )

            journeyArrow
                .frame(width: showsPaceChrome ? 64 : 78)

            journeyColumn(
                title: String(localized: "horizon.sunday_target", defaultValue: "SUNDAY TARGET"),
                kilograms: surface.sundayTargetKg,
                alignment: .trailing,
                size: showsPaceChrome ? 32 : 40,
                design: .serif,
                identifier: "progress.sundayKg",
                accessibility: sundayAccessibility
            )
            .scaleEffect(sundayScale, anchor: .center)
            .animation(punchSpring, value: sundayScale)
            .progressActionBlock(
                revealed: sundayIn,
                reduceMotion: reduceMotion,
                slide: 36,
                fromScale: 0.32,
                anchor: .center
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var journeyArrow: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(atmosphere.accent.opacity(colorScheme == .dark ? 0.45 : 0.35))
                .frame(height: 3)
                .scaleEffect(x: arrowIn ? 1 : 0.08, anchor: .leading)
                .animation(reduceMotion ? nil : arrowSpring, value: arrowIn)

            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: "chevron.right")
                        .font(.system(size: showsPaceChrome ? 11 : 13, weight: .black))
                        .foregroundStyle(atmosphere.accent)
                        .opacity(arrowIn ? 1 : 0)
                        .offset(x: arrowIn ? 0 : -14)
                        .animation(
                            reduceMotion ? nil : arrowSpring.delay(Double(index) * 0.055),
                            value: arrowIn
                        )
                }
            }
        }
        .frame(height: 28)
        .accessibilityHidden(true)
    }

    private func journeyColumn(
        title: String,
        kilograms: Double?,
        alignment: HorizontalAlignment,
        size: CGFloat,
        design: Font.Design,
        identifier: String,
        accessibility: String
    ) -> some View {
        let textAlignment: TextAlignment = alignment == .trailing ? .trailing : .leading
        return VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(atmosphere.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(kilograms.map { UnitFormat.massString($0, system: units, fractionDigits: 1) } ?? "—")
                .font(.system(size: size, weight: .bold, design: design))
                .monospacedDigit()
                .foregroundStyle(kilograms == nil ? atmosphere.muted : atmosphere.ink)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .multilineTextAlignment(textAlignment)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility)
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
            let trackWidth = ProgressBounds.safeLength(geo.size.width)
            let width = ProgressBounds.safeLength(trackWidth * CGFloat(fill / 1.2))
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
                Label {
                    Text(String(localized: "progress.charts", defaultValue: "Charts"))
                } icon: {
                    Image(systemName: "chart.xyaxis.line")
                }
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
            .accessibilityLabel(String(localized: "progress.charts.a11y", defaultValue: "Open weight and body fat charts"))

            Button {
                if GrokPrivacyConsent.isAccepted || !GrokSharedConfig.isLiveConfigured {
                    Task { await runCoach() }
                } else {
                    showPrivacyGate = true
                }
            } label: {
                Text(GrokSharedConfig.isLiveConfigured
                      ? String(localized: "progress.keel_roast", defaultValue: "Keel roast")
                      : String(localized: "progress.keel_roast.offline", defaultValue: "Keel roast (offline)"))
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
        session.refreshAlreadyWeighedToday()
        if session.progressSurfaceWarmed {
            session.ensureWeeklyGoalBaseline()
            session.rebuildWeeklyGoalSurface()
            Task { await session.warmProgressSurface(force: false) }
        } else {
            // First visit before launch warm finishes — sync paint, then full warm.
            session.ensureWeeklyGoalBaseline()
            session.rebuildWeeklyGoalSurface()
            Task { await session.warmProgressSurface(force: true) }
        }
    }

    /// Reset → stagger in. Always plays, including when the weekly surface was pre-warmed.
    /// Motion is attached with `.animation(_:value:)` because `withAnimation` after `await` was dropping the hero.
    private func playEntrance() {
        entranceToken &+= 1
        let token = entranceToken

        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            statusIn = false
            weekStartIn = false
            sundayIn = false
            arrowIn = false
            heroIn = false
            percentScale = 1
            weekStartScale = 1
            sundayScale = 1
            gaugeIn = false
            gaugeFill = reduceMotion ? targetGauge : 0
            deltaIn = false
            coachIn = false
            actionsIn = false
            displayedPercent = reduceMotion ? percent : 0
        }

        if reduceMotion {
            revealEntranceFinal()
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            guard token == entranceToken else { return }
            statusIn = true

            try? await Task.sleep(for: .milliseconds(120))
            guard token == entranceToken else { return }
            weekStartIn = true

            try? await Task.sleep(for: .milliseconds(160))
            guard token == entranceToken else { return }
            weekStartScale = 1.22
            arrowIn = true

            try? await Task.sleep(for: .milliseconds(180))
            guard token == entranceToken else { return }
            weekStartScale = 1
            sundayIn = true

            try? await Task.sleep(for: .milliseconds(170))
            guard token == entranceToken else { return }
            sundayScale = 1.26

            try? await Task.sleep(for: .milliseconds(200))
            guard token == entranceToken else { return }
            sundayScale = 1

            if surface.weekMoment != .mondayFresh {
                guard token == entranceToken else { return }
                heroIn = true
                percentScale = 1.38
                await countPercent(token: token)

                try? await Task.sleep(for: .milliseconds(40))
                guard token == entranceToken else { return }
                percentScale = 1
                gaugeIn = true
                gaugeFill = targetGauge

                try? await Task.sleep(for: .milliseconds(140))
                guard token == entranceToken else { return }
                deltaIn = true
            } else {
                heroIn = true
                gaugeIn = true
                deltaIn = true
                displayedPercent = percent
                gaugeFill = targetGauge
            }

            try? await Task.sleep(for: .milliseconds(110))
            guard token == entranceToken else { return }
            coachIn = true

            try? await Task.sleep(for: .milliseconds(120))
            guard token == entranceToken else { return }
            actionsIn = true
        }

        // If a later visit cancels this run, the new run owns the token.
        // If the task is dropped, never leave the sheet at the hidden floor.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2200))
            guard token == entranceToken else { return }
            guard !actionsIn else { return }
            revealEntranceFinal()
        }
    }

    private func countPercent(token: Int) async {
        let target = percent
        displayedPercent = 0
        guard target > 0 else { return }
        let steps = 7
        for step in 1...steps {
            guard token == entranceToken else { return }
            displayedPercent = Int((Double(target) * Double(step) / Double(steps)).rounded())
            try? await Task.sleep(for: .milliseconds(36))
        }
        guard token == entranceToken else { return }
        displayedPercent = target
    }

    private func revealEntranceFinal() {
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) {
            statusIn = true
            weekStartIn = true
            sundayIn = true
            arrowIn = true
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
        fromScale: CGFloat = 0.58,
        anchor: UnitPoint = .leading
    ) -> some View {
        if reduceMotion {
            self.opacity(revealed ? 1 : 0.04)
        } else {
            self
                .opacity(revealed ? 1 : 0.04)
                .offset(y: revealed ? 0 : slide)
                .scaleEffect(revealed ? 1 : fromScale, anchor: anchor)
                .animation(.spring(response: 0.48, dampingFraction: 0.55), value: revealed)
        }
    }
}

#Preview {
    ProgressSheet()
        .environmentObject(ScaleSessionViewModel())
}
