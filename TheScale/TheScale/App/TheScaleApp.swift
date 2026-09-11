import SwiftUI

@main
struct TheScaleApp: App {
    @StateObject private var session = ScaleSessionViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
        }
    }
}
