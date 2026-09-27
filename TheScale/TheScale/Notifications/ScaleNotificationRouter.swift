import Foundation
import UserNotifications

/// Routes notification taps / actions into FATNAG screens, and handles snooze.
@MainActor
enum ScaleNotificationRouter {
    /// Installed by ContentView / app shell so notification actions can open UI.
    static var openDestination: ((ScaleNotificationDestination) -> Void)?
    static var openAppNotificationSettings: (() -> Void)?

    static func handle(response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let userInfo = content.userInfo
        let action = response.actionIdentifier

        if action == ScaleNotificationActionID.snooze10 {
            await snooze(request: response.notification.request, minutes: 10)
            return
        }

        let destination: ScaleNotificationDestination? = {
            switch action {
            case ScaleNotificationActionID.openCoach:
                return .coach
            case ScaleNotificationActionID.openProgress:
                return .progress
            case ScaleNotificationActionID.openHistory:
                return .history
            case ScaleNotificationActionID.openWeigh:
                return .weigh
            case UNNotificationDefaultActionIdentifier:
                if let raw = userInfo[ScaleNotificationUserInfoKey.destination] as? String,
                   let dest = ScaleNotificationDestination(rawValue: raw) {
                    return dest
                }
                if let target = content.targetContentIdentifier,
                   let dest = ScaleNotificationDestination(rawValue: target) {
                    return dest
                }
                return .coach
            default:
                return nil
            }
        }()

        if let destination {
            openDestination?(destination)
        }
    }

    static func handleOpenSettings() {
        if let openAppNotificationSettings {
            openAppNotificationSettings()
        } else {
            openDestination?(.settings)
        }
    }

    /// Re-schedule the same content ~N minutes later under a snooze id.
    static func snooze(request: UNNotificationRequest, minutes: Int) async {
        let content = request.content.mutableCopy() as? UNMutableNotificationContent
            ?? UNMutableNotificationContent()
        if content.title.isEmpty {
            content.title = request.content.title
            content.subtitle = request.content.subtitle
            content.body = request.content.body
            content.sound = request.content.sound
            content.categoryIdentifier = request.content.categoryIdentifier
            content.threadIdentifier = request.content.threadIdentifier
            content.interruptionLevel = request.content.interruptionLevel
            content.relevanceScore = request.content.relevanceScore
            content.userInfo = request.content.userInfo
            content.attachments = request.content.attachments
            content.targetContentIdentifier = request.content.targetContentIdentifier
        }
        content.subtitle = content.subtitle.isEmpty ? "Snoozed 10 min" : content.subtitle
        let seconds = max(TimeInterval(minutes * 60), 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let id = "thescale.snooze." + UUID().uuidString
        let snoozed = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(snoozed)
    }
}
