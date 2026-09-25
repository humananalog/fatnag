import SwiftUI
import UserNotifications

/// Diffused haze behind the weekly-goal hero. Ambient drift + Core Motion tilt spring.
struct WeeklyGoalHazeBackground: View {
    let atmosphere: WeeklyGoalAtmosphere

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var tilt = HazeTiltMotion.shared
    @State private var motionHeld = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Was /18; modestly faster ambient drift (still calm).
            let slow = reduceMotion ? 0 : t / 13.5
            let x1 = CGFloat(sin(slow) * 0.12)
            let y1 = CGFloat(cos(slow * 0.7) * 0.10)
            let x2 = CGFloat(cos(slow * 0.55) * 0.14)
            let y2 = CGFloat(sin(slow * 0.9) * 0.11)
            let x3 = CGFloat(sin(slow * 0.4 + 1.2) * 0.10)
            let y3 = CGFloat(cos(slow * 0.65 + 0.8) * 0.13)

            let tx = reduceMotion ? 0 : tilt.offset.width
            let ty = reduceMotion ? 0 : tilt.offset.height

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
                    .offset(x: -80 + x1 * 160 + tx * 0.85, y: -120 + y1 * 140 + ty * 0.85)

                Ellipse()
                    .fill(atmosphere.hazeB)
                    .frame(width: 380, height: 300)
                    .blur(radius: 60)
                    .offset(x: 90 + x2 * 150 + tx * 1.15, y: 40 + y2 * 160 + ty * 1.10)

                Ellipse()
                    .fill(atmosphere.hazeA.opacity(0.65))
                    .frame(width: 260, height: 220)
                    .blur(radius: 44)
                    .offset(x: 20 + x3 * 120 + tx * 0.55, y: 180 + y3 * 100 + ty * 0.60)
            }
            .ignoresSafeArea()
        }
        .onAppear { syncTiltMotion() }
        .onDisappear {
            if motionHeld {
                HazeTiltMotion.shared.release()
                motionHeld = false
            }
        }
        .onChange(of: reduceMotion) { _, _ in syncTiltMotion() }
        .onChange(of: scenePhase) { _, _ in syncTiltMotion() }
    }

    private func syncTiltMotion() {
        let want = !reduceMotion && scenePhase == .active
        if want, !motionHeld {
            HazeTiltMotion.shared.retain()
            motionHeld = true
        } else if !want, motionHeld {
            HazeTiltMotion.shared.release()
            motionHeld = false
        }
    }
}

/// Home: one weekly-goal composition. No card chrome. Haze atmosphere only.
struct ContentView: View {
    @EnvironmentObject private var session: ScaleSessionViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    #if DEBUG
    @State private var showDebugTools = false
    #endif
    @State private var showNotificationCenter = false
    @State private var pendingNotifCount = 0

    private var surface: WeeklyGoalSurface {
        session.weeklyGoalSurface
    }

    private var atmosphere: WeeklyGoalAtmosphere {
        WeeklyGoalAtmosphere.forBand(surface.band, colorScheme: colorScheme)
    }

    var body: some View {
        TabView(selection: Binding(
            get: { session.homeTab },
            set: { session.selectHomeTab($0) }
        )) {
            Tab(HomeGlassDestination.weigh.title, systemImage: HomeGlassDestination.weigh.systemImage, value: HomeGlassDestination.weigh) {
                weighTabRoot
            }
            Tab(HomeGlassDestination.progress.title, systemImage: HomeGlassDestination.progress.systemImage, value: HomeGlassDestination.progress) {
                ProgressSheet()
                    .environmentObject(session)
            }
            Tab(HomeGlassDestination.keel.title, systemImage: HomeGlassDestination.keel.systemImage, value: HomeGlassDestination.keel) {
                CoachChatView()
                    .environmentObject(session)
            }
            Tab(HomeGlassDestination.meals.title, systemImage: HomeGlassDestination.meals.systemImage, value: HomeGlassDestination.meals) {
                MealPlanCarouselView()
                    .environmentObject(session)
            }
            Tab(HomeGlassDestination.settings.title, systemImage: HomeGlassDestination.settings.systemImage, value: HomeGlassDestination.settings) {
                NavigationStack {
                    SettingsView()
                        .environmentObject(session)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Weigh-now lives inside the Weigh tab only. A conditional
        // `tabViewBottomAccessory` left a blank white chrome bar on Settings / Coach / etc.
        // Follow system appearance so Progress / home / meals stay readable in dark mode.
        #if DEBUG
        .sheet(isPresented: $showDebugTools) {
            DebugToolsView()
                .environmentObject(session)
        }
        #endif
        .sheet(isPresented: $showNotificationCenter) {
            NotificationCenterSheet()
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
                await session.reconcileAlreadyWeighedTodayFromHealth()
                await session.refreshHomeGauges(force: false)
                await session.considerMorningWeighDrill()
                await refreshPendingNotifBadge()
            }
        }
    }

    /// Home / Weigh tab: weekly-goal composition under the system liquid-glass tab bar.
    private var weighTabRoot: some View {
        NavigationStack {
            ZStack {
                WeeklyGoalHazeBackground(atmosphere: atmosphere)
                homeScroll
                #if DEBUG
                debugOverlay
                #endif
            }
            // Exact Weigh Now control: bottom safeAreaInset on Weigh tab only.
            // Show only after gate resolved AND not already weighed (stamp-first, then Health today).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if session.shouldShowWeighNowCTA {
                    Button {
                        if session.selectedScaleID != nil {
                            session.reopenWeighIn()
                        } else {
                            session.presentManualEntry()
                        }
                    } label: {
                        Label("Weigh now", systemImage: "scalemass.fill")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.12, green: 0.42, blue: 0.30))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("home.weighNow")
                    .accessibilityLabel("Weigh now")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: session.homeTab) {
                guard session.homeTab == .weigh else { return }
                await session.reconcileAlreadyWeighedTodayFromHealth()
            }
            .onChange(of: session.alreadyWeighedToday) { _, weighed in
                #if DEBUG
                print("[TheScale] home alreadyWeighedToday=\(weighed) gateResolved=\(session.weighNowGateResolved)")
                #endif
            }
        }
    }

    private var homeScroll: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 720
            ScrollView(.vertical, showsIndicators: false) {
                homeColumn(compact: compact)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
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
                steel: atmosphere.muted,
                accent: atmosphere.accent,
                compact: compact
            )
            .onTapGesture { session.presentProgress() }

            adviceBlock(compact: compact)

            homeStatusLine(compact: compact)
            Spacer(minLength: compact ? 12 : 24)
        }
    }

    /// User-facing status only (Health unavailable). No BLE "Listening…" / scan chrome.
    private func homeStatusLine(compact: Bool) -> some View {
        Group {
            if !session.healthKitAvailable {
                Text("Health unavailable.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(atmosphere.ink.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, compact ? 2 : 4)
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
                .shadow(
                    color: colorScheme == .dark ? .black.opacity(0.45) : .white.opacity(0.35),
                    radius: 0,
                    y: 1
                )
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
        session.refreshAlreadyWeighedToday()
        session.startPassiveListening()
        async let gauges = session.refreshHomeGauges(force: true)
        async let baseline: Void = session.refreshHealthBaseline()
        _ = await gauges
        await baseline
        await session.reconcileAlreadyWeighedTodayFromHealth()
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
            Button {
                session.reopenResults()
            } label: {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(atmosphere.ink.opacity(0.9))
                    .frame(width: 36, height: 36)
                    .scaleGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.charts")
            .accessibilityLabel("Charts")
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
}

#Preview {
    ContentView()
        .environmentObject(ScaleSessionViewModel())
}
