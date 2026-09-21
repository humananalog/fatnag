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
                // Drop per-user paste keys from 2.0 / 2.1; coaching uses shared build config only.
                GrokLegacyKeychain.clearUserEnteredKey()
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        _ = await session.runFitnessMonitorCheck(force: false)
                        await session.armHealthKitBackgroundDelivery()
                    }
                    GrokFitnessMonitor.scheduleBackgroundRefresh(prefs: session.fitnessMonitorPreferences)
                    GrokFitnessMonitor.scheduleBackgroundProcessing(prefs: session.fitnessMonitorPreferences)
                }
            }
        }
    }
}
