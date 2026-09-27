import AppIntents
import Foundation

/// Deep-link App Intents so notification chrome / Shortcuts can open the right screen.
struct OpenCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Coach"
    static let description = IntentDescription("Opens FATNAG Coach chat.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ScaleNotificationRouter.openDestination?(.coach)
        return .result()
    }
}

struct OpenProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Progress"
    static let description = IntentDescription("Opens FATNAG weekly Progress sheet.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ScaleNotificationRouter.openDestination?(.progress)
        return .result()
    }
}

struct OpenHistoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open History"
    static let description = IntentDescription("Opens FATNAG weight History.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ScaleNotificationRouter.openDestination?(.history)
        return .result()
    }
}

struct TheScaleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCoachIntent(),
            phrases: [
                "Open Coach in \(.applicationName)",
                "Talk to Coach in \(.applicationName)"
            ],
            shortTitle: "Open Coach",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: OpenProgressIntent(),
            phrases: [
                "Open Progress in \(.applicationName)",
                "Show my Progress in \(.applicationName)"
            ],
            shortTitle: "Open Progress",
            systemImageName: "flag.checkered"
        )
    }
}
