import Foundation
import UserNotifications

/// Routes notification taps / actions into FATNAG screens, and handles snooze.
@MainActor
enum ScaleNotificationRouter {
    /// Installed by ContentView / app shell so notification actions can open UI.
    private static var openDestinationHandler: ((ScaleNotificationDestination) -> Void)?
    /// Cold-start taps arrive before ContentView installs the handler.
    private static var pendingDestination: ScaleNotificationDestination?
    static var openAppNotificationSettings: (() -> Void)?

    /// Assign from the home shell. Flushes any tap that landed while the UI was still launching.
    static var openDestination: ((ScaleNotificationDestination) -> Void)? {
        get { openDestinationHandler }
        set {
            openDestinationHandler = newValue
            if let newValue, let pending = pendingDestination {
                pendingDestination = nil
                newValue(pending)
            }
        }
    }

    static func route(_ destination: ScaleNotificationDestination) {
        if let openDestinationHandler {
            openDestinationHandler(destination)
        } else {
            pendingDestination = destination
        }
    }

    static func handle(response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let userInfo = content.userInfo
        let action = response.actionIdentifier

        // Tap, dismiss, snooze, and action buttons all mean the user dealt with it.
        NotificationArchiveStore.acknowledge(response.notification)

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
                if let kindRaw = userInfo[ScaleNotificationUserInfoKey.kind] as? String,
                   let kind = ScaleNotificationKind(rawValue: kindRaw) {
                    return kind.destination
                }
                return .coach
            default:
                return nil
            }
        }()

        if let destination {
            route(destination)
        }
    }

    static func handleOpenSettings() {
        if let openAppNotificationSettings {
            openAppNotificationSettings()
        } else {
            route(.settings)
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

extension Notification.Name {
    static let fatnagAlertsDidChange = Notification.Name("fatnag.alerts.didChange")
}

/// Acknowledged alerts leave the active inbox and stay here.
struct ArchivedAlert: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var requestId: String
    var title: String
    var body: String
    var deliveredAt: Date
    var acknowledgedAt: Date
}

enum NotificationArchiveStore {
    static let storageKey = "thescale.notificationArchive.v1"
    private static let maxKept = 40
    /// Same delivery can be reported with a slightly different timestamp.
    private static let matchWindow: TimeInterval = 2

    static func load() -> [ArchivedAlert] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([ArchivedAlert].self, from: data)
        else { return [] }
        return items.sorted { $0.acknowledgedAt > $1.acknowledgedAt }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: .fatnagAlertsDidChange, object: nil)
    }

    static func removing(id: String, from archive: [ArchivedAlert]) -> [ArchivedAlert] {
        archive.filter { $0.id != id }
    }

    static func delete(id: String) {
        let items = removing(id: id, from: load())
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        NotificationCenter.default.post(name: .fatnagAlertsDidChange, object: nil)
    }

    static func isAcknowledged(
        requestId: String,
        deliveredAt: Date,
        in archive: [ArchivedAlert]
    ) -> Bool {
        archive.contains { item in
            item.requestId == requestId
                && abs(item.deliveredAt.timeIntervalSince(deliveredAt)) < matchWindow
        }
    }

    static func acknowledge(
        requestId: String,
        title: String,
        body: String,
        deliveredAt: Date,
        now: Date = Date()
    ) {
        var items = load()
        if isAcknowledged(requestId: requestId, deliveredAt: deliveredAt, in: items) { return }
        items.insert(
            ArchivedAlert(
                id: UUID().uuidString,
                requestId: requestId,
                title: title,
                body: body,
                deliveredAt: deliveredAt,
                acknowledgedAt: now
            ),
            at: 0
        )
        if items.count > maxKept {
            items = Array(items.prefix(maxKept))
        }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [requestId])
        NotificationCenter.default.post(name: .fatnagAlertsDidChange, object: nil)
    }

    static func acknowledge(_ notification: UNNotification) {
        let content = notification.request.content
        acknowledge(
            requestId: notification.request.identifier,
            title: content.title,
            body: content.body,
            deliveredAt: notification.date
        )
    }

    static func activeCount(in delivered: [UNNotification]) -> Int {
        let archive = load()
        return delivered.filter {
            !isAcknowledged(requestId: $0.request.identifier, deliveredAt: $0.date, in: archive)
        }.count
    }
}
