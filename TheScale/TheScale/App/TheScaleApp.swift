import SwiftUI
import UserNotifications

@main
struct TheScaleApp: App {
    @StateObject private var session = ScaleSessionViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitesting-skip-splash") { return false }
        #if DEBUG
        if DemoPersonaSeeder.Persona.fromLaunchArguments(args) != nil { return false }
        #endif
        return true
    }()
    /// First-launch karaoke after splash. UI tests that skip splash also skip this.
    @State private var showFirstLaunchLanding = false
    @State private var appLanguage = AppLanguageStore.current

    init() {
        UNUserNotificationCenter.current().delegate = ScaleNotificationDelegate.shared
        ScaleNotificationCategories.register()
        GrokFitnessMonitor.registerBackgroundTask()
        AppLanguageBundleInstaller.installIfNeeded()
        AppLanguageStore.syncBundleLanguages()
        Self.applyLaunchArguments()
    }

    /// UITest / DEBUG launch flags. Safe no-ops in Release (no flags passed).
    private static func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitesting-reset-onboarding") {
            OnboardingStore.hasCompleted = false
        }
        #if DEBUG
        PromoCaptureMode.activateIfNeeded(arguments: args)
        // Seed UserDefaults before ScaleSessionViewModel loads profile / onboarding flag.
        if let persona = DemoPersonaSeeder.Persona.fromLaunchArguments(args) {
            DemoPersonaSeeder.persist(persona)
        }
        #endif
    }

    #if DEBUG
    /// `-promoShot=home|weigh|charts|alerts|progress|keel` (also accepts bare `-promoShot` + next argv).
    private static func promoShotArgument(
        _ args: [String] = ProcessInfo.processInfo.arguments
    ) -> String? {
        if let eq = args.first(where: { $0.hasPrefix("-promoShot=") }) {
            return String(eq.dropFirst("-promoShot=".count))
        }
        if let idx = args.firstIndex(of: "-promoShot"), args.indices.contains(idx + 1) {
            let next = args[idx + 1]
            if !next.hasPrefix("-") { return next }
        }
        return nil
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Guaranteed base under splash/content so a failed first paint is never a
                // pure LaunchBackground void with no chrome.
                Color.black
                    .ignoresSafeArea()

                Group {
                    if session.hasCompletedOnboarding {
                        ContentView()
                            .environmentObject(session)
                    } else {
                        OnboardingView()
                            .environmentObject(session)
                    }
                }
                .environment(\.locale, appLanguage.locale)
                .environment(\.layoutDirection, appLanguage.layoutDirection)
                .id(appLanguage.rawValue)
                .opacity(showSplash || showFirstLaunchLanding ? 0 : 1)

                if showFirstLaunchLanding {
                    FirstLaunchLandingView {
                        showFirstLaunchLanding = false
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }

                if showSplash {
                    // Outside language `.id` remount so the tagline stays the persisted
                    // Settings language (or system on first launch) for the whole slam.
                    SplashView {
                        showSplash = false
                        if !session.hasCompletedOnboarding {
                            showFirstLaunchLanding = true
                        }
                    }
                    .transition(.opacity)
                    .zIndex(3)
                }
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-uitesting-reset-onboarding") {
                    OnboardingStore.hasCompleted = false
                    session.hasCompletedOnboarding = false
                }
                #if DEBUG
                if let persona = DemoPersonaSeeder.Persona.fromLaunchArguments() {
                    DemoPersonaSeeder.hydrate(persona, into: session)
                    showSplash = false
                    showFirstLaunchLanding = false
                    if let shot = Self.promoShotArgument() {
                        // Let ContentView mount before presenting sheets/tabs.
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 700_000_000)
                            session.applyPromoShot(shot)
                        }
                    }
                }
                #endif
                // Drop per-user paste keys from 2.0 / 2.1; coaching uses shared build config only.
                GrokLegacyKeychain.clearUserEnteredKey()
                // Failsafe: never leave the user on splash forever if its Task is cancelled.
                // Does not skip the first-launch landing.
                if showSplash {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        if showSplash {
                            showSplash = false
                            if !session.hasCompletedOnboarding {
                                showFirstLaunchLanding = true
                            }
                        }
                    }
                }
                // Do not prompt Health / BG tasks until onboarding finishes.
                guard session.hasCompletedOnboarding else { return }
                #if DEBUG
                if PromoCaptureMode.isActive { return }
                #endif
                schedulePostOnboardingWork()
            }
            .onChange(of: session.hasCompletedOnboarding) { _, completed in
                guard completed else { return }
                #if DEBUG
                if PromoCaptureMode.isActive { return }
                #endif
                schedulePostOnboardingWork()
            }
            .task(id: scenePhase) {
                guard scenePhase == .active, session.hasCompletedOnboarding else { return }
                #if DEBUG
                if PromoCaptureMode.isActive { return }
                #endif
                while !Task.isCancelled {
                    await session.runActivityPulse()
                    try? await Task.sleep(for: .seconds(10 * 60))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, session.hasCompletedOnboarding else { return }
                appLanguage = AppLanguageStore.current
                Task {
                    await session.refreshHomeGauges(force: false)
                    _ = await session.runFitnessMonitorCheck(force: false)
                    await session.armHealthKitBackgroundDelivery()
                    await session.refreshTrendNotifications()
                }
                GrokFitnessMonitor.scheduleBackgroundRefresh(prefs: session.fitnessMonitorPreferences)
                GrokFitnessMonitor.scheduleBackgroundProcessing(prefs: session.fitnessMonitorPreferences)
            }
            .onReceive(NotificationCenter.default.publisher(for: .appLanguageDidChange)) { _ in
                appLanguage = AppLanguageStore.current
            }
        }
    }

    private func schedulePostOnboardingWork() {
        GrokFitnessMonitor.scheduleBackgroundRefresh(prefs: session.fitnessMonitorPreferences)
        GrokFitnessMonitor.scheduleBackgroundProcessing(prefs: session.fitnessMonitorPreferences)
        Task {
            await ScaleSubscriptionStore.shared.refresh()
            // Compatible phones (no Apple Intelligence) auto-install 0.5B Metal polish.
            // AI-capable iPhones skip the download entirely.
            await OnDevicePolishBootstrap.configureAndInstallIfNeeded()
            await session.armHealthKitBackgroundDelivery()
            // Arm weekly + morning fallback even if the user never opens Settings.
            _ = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
            await session.refreshTrendNotifications()
        }
    }
}
