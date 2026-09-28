import SwiftUI
import UserNotifications

@main
struct TheScaleApp: App {
    @StateObject private var session = ScaleSessionViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = !ProcessInfo.processInfo.arguments.contains("-uitesting-skip-splash")
    @State private var appLanguage = AppLanguageStore.current

    init() {
        UNUserNotificationCenter.current().delegate = ScaleNotificationDelegate.shared
        ScaleNotificationCategories.register()
        GrokFitnessMonitor.registerBackgroundTask()
        Self.applyLaunchArguments()
    }

    /// UITest / DEBUG launch flags. Safe no-ops in Release (no flags passed).
    private static func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitesting-reset-onboarding") {
            OnboardingStore.hasCompleted = false
        }
    }

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
                .opacity(showSplash ? 0 : 1)

                if showSplash {
                    SplashView {
                        showSplash = false
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-uitesting-reset-onboarding") {
                    OnboardingStore.hasCompleted = false
                    session.hasCompletedOnboarding = false
                }
                // Drop per-user paste keys from 2.0 / 2.1; coaching uses shared build config only.
                GrokLegacyKeychain.clearUserEnteredKey()
                // Failsafe: never leave the user on splash forever if its Task is cancelled.
                if showSplash {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        if showSplash {
                            showSplash = false
                        }
                    }
                }
                // Do not prompt Health / BG tasks until onboarding finishes.
                guard session.hasCompletedOnboarding else { return }
                schedulePostOnboardingWork()
            }
            .onChange(of: session.hasCompletedOnboarding) { _, completed in
                guard completed else { return }
                schedulePostOnboardingWork()
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
            await GrokFitnessMonitor.scheduleIntervalNotification(
                prefs: session.fitnessMonitorPreferences,
                profileName: session.profile.greetingName
            )
            await session.armHealthKitBackgroundDelivery()
            // Arm weekly + morning fallback even if the user never opens Settings.
            _ = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
            await session.refreshTrendNotifications()
        }
    }
}
