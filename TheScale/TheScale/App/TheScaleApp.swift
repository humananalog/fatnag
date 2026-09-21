import SwiftUI
import UserNotifications

@main
struct TheScaleApp: App {
    @StateObject private var session = ScaleSessionViewModel()
    @Environment(\.scenePhase) private var scenePhase

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
            Group {
                if session.hasCompletedOnboarding {
                    ContentView()
                        .environmentObject(session)
                } else {
                    OnboardingView()
                        .environmentObject(session)
                }
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-uitesting-reset-onboarding") {
                    OnboardingStore.hasCompleted = false
                    session.hasCompletedOnboarding = false
                }
                // Drop per-user paste keys from 2.0 / 2.1; coaching uses shared build config only.
                GrokLegacyKeychain.clearUserEnteredKey()
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
                Task {
                    _ = await session.runFitnessMonitorCheck(force: false)
                    await session.armHealthKitBackgroundDelivery()
                }
                GrokFitnessMonitor.scheduleBackgroundRefresh(prefs: session.fitnessMonitorPreferences)
                GrokFitnessMonitor.scheduleBackgroundProcessing(prefs: session.fitnessMonitorPreferences)
            }
        }
    }

    private func schedulePostOnboardingWork() {
        GrokFitnessMonitor.scheduleBackgroundRefresh(prefs: session.fitnessMonitorPreferences)
        GrokFitnessMonitor.scheduleBackgroundProcessing(prefs: session.fitnessMonitorPreferences)
        Task {
            await ScaleSubscriptionStore.shared.refresh()
            await GrokFitnessMonitor.scheduleIntervalNotification(
                prefs: session.fitnessMonitorPreferences,
                profileName: session.profile.greetingName
            )
            await session.armHealthKitBackgroundDelivery()
        }
    }
}
