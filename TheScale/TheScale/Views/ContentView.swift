import SwiftUI
import UserNotifications

/// Slow-motion diffused haze behind the weekly-goal hero. Subtle, not noisy.
struct WeeklyGoalHazeBackground: View {
    let atmosphere: WeeklyGoalAtmosphere

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let slow = t / 18.0
            let x1 = CGFloat(sin(slow) * 0.12)
            let y1 = CGFloat(cos(slow * 0.7) * 0.10)
            let x2 = CGFloat(cos(slow * 0.55) * 0.14)
            let y2 = CGFloat(sin(slow * 0.9) * 0.11)
            let x3 = CGFloat(sin(slow * 0.4 + 1.2) * 0.10)
            let y3 = CGFloat(cos(slow * 0.65 + 0.8) * 0.13)

            ZStack {
                LinearGradient(
                    colors: [atmosphere.top, atmosphere.mid, atmosphere.bottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Ellipse()
                    .fill(atmosphere.hazeA)
                    .frame(width: 340, height: 280)
                    .blur(radius: 52)
                    .offset(x: -80 + x1 * 160, y: -120 + y1 * 140)

                Ellipse()
                    .fill(atmosphere.hazeB)
                    .frame(width: 380, height: 300)
                    .blur(radius: 60)
                    .offset(x: 90 + x2 * 150, y: 40 + y2 * 160)

                Ellipse()
                    .fill(atmosphere.hazeA.opacity(0.65))
                    .frame(width: 260, height: 220)
                    .blur(radius: 44)
                    .offset(x: 20 + x3 * 120, y: 180 + y3 * 100)
            }
            .ignoresSafeArea()
        }
    }
}

/// Home: one weekly-goal composition. No card chrome. Haze atmosphere only.
struct ContentView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @State private var showDebugTools = false
    #endif
    @State private var showNotificationCenter = false
    @State private var pendingNotifCount = 0

    private var surface: WeeklyGoalSurface {
        session.weeklyGoalSurface
    }

    private var atmosphere: WeeklyGoalAtmosphere {
        WeeklyGoalAtmosphere.forBand(surface.band)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                WeeklyGoalHazeBackground(atmosphere: atmosphere)
                homeScroll
                HomeGlassBar { destination in
                    handleGlassDestination(destination)
                }
                #if DEBUG
                debugOverlay
                #endif
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            #if DEBUG
            .sheet(isPresented: $showDebugTools) {
                DebugToolsView()
                    .environmentObject(session)
            }
            #endif
            .sheet(isPresented: $showNotificationCenter) {
                NotificationCenterSheet()
            }
            .sheet(isPresented: Binding(
                get: { session.isSettingsPresented },
                set: { if !$0 { session.dismissSettings() } }
            )) {
                NavigationStack {
                    SettingsView()
                        .environmentObject(session)
                }
            }
            .sheet(isPresented: Binding(
                get: { session.isMealPlanPresented },
                set: { if !$0 { session.dismissMealPlan() } }
            )) {
                MealPlanCarouselView()
                    .environmentObject(session)
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.isWeighInPresented },
                set: { if !$0 { session.dismissWeighIn() } }
            )) {
                LiveWeighInSheet()
                    .environmentObject(session)
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.isWeighInHeroPresented },
                set: { if !$0 { session.dismissWeighInHero() } }
            )) {
                WeighInHeroMomentView()
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
            .sheet(isPresented: Binding(
                get: { session.isProgressPresented },
                set: { if !$0 { session.dismissProgress() } }
            )) {
                ProgressSheet()
                    .environmentObject(session)
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.isCoachPresented },
                set: { if !$0 { session.dismissCoach() } }
            )) {
                CoachChatView()
                    .environmentObject(session)
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.isMondayCardPresented },
                set: { if !$0 { session.dismissMondayCard() } }
            )) {
                MondayWeeklyCardView()
                    .environmentObject(session)
            }
            .sheet(isPresented: Binding(
                get: { session.isAppReviewPromptPresented },
                set: { if !$0 { session.dismissAppReviewPrompt() } }
            )) {
                AppReviewPromptView {
                    session.dismissAppReviewPrompt()
                }
            }
            .sheet(isPresented: Binding(
                get: { session.pendingProfileGap != nil },
                set: { if !$0 { session.dismissProfileGapSheet() } }
            )) {
                ProfileGapPromptView()
                    .environmentObject(session)
            }
            .task {
                await bootstrapHome()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await session.refreshHomeGauges(force: false)
                    await session.considerMorningWeighDrill()
                    await refreshPendingNotifBadge()
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var homeScroll: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 720
            ScrollView(.vertical, showsIndicators: false) {
                homeColumn(compact: compact)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 96)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
            }
            .refreshable {
                await session.refreshHomeGauges(force: true)
                await session.refreshHealthBaseline()
                await session.refreshWeeklyGoalSurface()
            }
        }
    }

    private func homeColumn(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 18 : 24) {
            brandRow

            if let analysis = session.lastWeighInAnalysis {
                weighInAnalysisBlock(analysis)
            }

            HorizonArcBankView(
                sundayTargetKg: surface.sundayTargetKg,
                weeklyDeltaKg: surface.weeklyDeltaKg,
                bandLabel: surface.band.statusLabel,
                weekTitle: surface.weekTitle,
                metrics: surface.todayProgress,
                targetChips: surface.dailyTargetChips,
                ink: atmosphere.ink,
                steel: atmosphere.ink.opacity(0.72),
                accent: Color(red: 0.12, green: 0.42, blue: 0.30),
                compact: compact
            )
            .onTapGesture { session.presentProgress() }

            adviceBlock(compact: compact)

            homeStatusLine(compact: compact)
            discoveryBlock
            Spacer(minLength: compact ? 12 : 24)
        }
    }

    private func handleGlassDestination(_ destination: HomeGlassDestination) {
        switch destination {
        case .weigh:
            if session.selectedScaleID != nil {
                session.reopenWeighIn()
            } else {
                session.presentManualEntry()
            }
        case .progress:
            session.presentProgress()
        case .keel:
            session.presentCoach()
        case .meals:
            session.presentMealPlan()
        case .settings:
            session.presentSettings()
        }
    }

    private func homeStatusLine(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 8) {
            Text(session.phase == .scanning || session.selectedScaleID != nil
                 ? "Listening…"
                 : "Step on. Live card opens.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(atmosphere.ink.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .leading)

            if case .healthKitSuccess = session.phase, !session.isWeighInPresented {
                Text("Saved to Health")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.06, green: 0.32, blue: 0.20))
            }

            if !session.healthKitAvailable {
                Text("Health unavailable.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(atmosphere.ink.opacity(0.7))
            }
        }
    }

    private func adviceBlock(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INSIGHT")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(atmosphere.ink.opacity(0.55))

            Text(surface.todayAdvice)
                .font(.system(size: compact ? 18 : 21, weight: .bold, design: .serif))
                .foregroundStyle(atmosphere.ink)
                .shadow(color: .white.opacity(0.4), radius: 0, y: 1)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.9)
                .accessibilityIdentifier("home.todayAdvice")

            Text(surface.macroGoalETA.line)
                .font(.system(size: compact ? 14 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(atmosphere.ink.opacity(0.72))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, compact ? 14 : 18)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    #if DEBUG
    private var debugOverlay: some View {
        VStack {
            HStack {
                Button {
                    showDebugTools = true
                } label: {
                    Text("DEBUG")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.92), in: Capsule())
                }
                .accessibilityIdentifier("home.debug")
                .accessibilityLabel("Debug tools")
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(true)
    }
    #endif

    private func bootstrapHome() async {
        session.ensureWeeklyGoalBaseline()
        session.rebuildWeeklyGoalSurface()
        session.startPassiveListening()
        async let gauges = session.refreshHomeGauges(force: true)
        async let baseline: Void = session.refreshHealthBaseline()
        _ = await gauges
        await baseline
        session.ensureWeeklyGoalBaseline()
        await session.refreshWeeklyGoalSurface()
        await session.refreshTrendNotifications()
        ScaleNotificationRouter.openDestination = { destination in
            session.handleNotificationDestination(destination)
        }
        ScaleNotificationRouter.openAppNotificationSettings = {
            session.presentSettings()
        }
        await refreshPendingNotifBadge()
    }

    private func refreshPendingNotifBadge() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        pendingNotifCount = pending.count
    }

    private var brandRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("The Scale")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(atmosphere.ink)
                    .shadow(color: .white.opacity(0.55), radius: 0, y: 1)
                Text(greetingLine)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(atmosphere.ink.opacity(0.78))
            }
            Spacer(minLength: 0)
            HomeNotificationBell(isPresented: $showNotificationCenter, badgeCount: pendingNotifCount)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(brandAccessibilityLabel)
    }

    private var greetingLine: String {
        let name = session.profile.greetingName
        if let kg = session.healthBaselineKg {
            if name.isEmpty {
                return String(format: "%.1f kg · this week", kg)
            }
            return String(format: "%@ · %.1f kg", name, kg)
        }
        if name.isEmpty { return "Weekly goal" }
        return "\(name) · weekly goal"
    }

    private var brandAccessibilityLabel: String {
        let name = session.profile.greetingName
        if let baseline = session.healthBaselineKg {
            if name.isEmpty {
                return String(format: "The Scale. Last Health weight %.1f kilograms.", baseline)
            }
            return String(format: "The Scale. Hello %@. Last Health weight %.1f kilograms.", name, baseline)
        }
        if name.isEmpty { return "The Scale" }
        return "The Scale. Hello \(name)."
    }

    private func weighInAnalysisBlock(_ card: WeighInAnalysisCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(card.tone.badge)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(atmosphere.ink.opacity(0.65))
                Spacer()
                Button("Dismiss") {
                    session.dismissWeighInAnalysis()
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(atmosphere.ink.opacity(0.7))
            }
            Text(card.headline)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(atmosphere.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(card.body)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(atmosphere.ink.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
            if !card.popLine.isEmpty {
                Text(card.popLine)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(atmosphere.ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var discoveryBlock: some View {
        switch session.phase {
        case .scanning where session.discoveredScales.isEmpty:
            ProgressView()
                .padding(.top, 16)
                .tint(atmosphere.ink)
        case .bluetoothUnavailable(let message):
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(red: 0.40, green: 0.06, blue: 0.06))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
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
                                        .foregroundStyle(atmosphere.ink)
                                    Text("RSSI \(scale.rssi) dBm")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(atmosphere.ink.opacity(0.7))
                                }
                                Spacer()
                                if session.selectedScaleID == scale.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(atmosphere.ink)
                                }
                            }
                            .padding(.vertical, 14)
                        }
                        if scale.id != session.discoveredScales.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ScaleSessionViewModel())
}
