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
        }
    }
}
