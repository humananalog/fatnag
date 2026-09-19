import SwiftUI

@main
struct TheScaleApp: App {
    @StateObject private var session = ScaleSessionViewModel()

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
            }
        }
    }
}
