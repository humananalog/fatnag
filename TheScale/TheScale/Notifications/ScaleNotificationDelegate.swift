import UserNotifications

/// Presents Coach / trend banners while FATNAG is in the foreground,
/// and routes taps / actions into the right screen.
///
/// Critical: never hop `UNNotificationResponse` / `UNNotification` across
/// actors. Those objects are bound to the notification-center queue and
/// crash when touched from MainActor after an `await`. Pull Sendable
/// fields first, then route.
final class ScaleNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = ScaleNotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Read userInfo on this queue before any suspension.
        let kindRaw = notification.request.content.userInfo[ScaleNotificationUserInfoKey.kind] as? String
        let kind = kindRaw.flatMap(ScaleNotificationKind.init(rawValue:))
        switch kind {
        case .fitnessInterval, .weeklyGoal, .mondaySkip, .sundayWrap:
            // Quiet while already in-app: list only, no sound.
            return [.banner, .list]
        case .coachWake, .morningWeigh, .weightSpike:
            return [.banner, .sound, .list, .badge]
        case .sample, .badTrend, .watchWear, .preSleepHR, .coachReminder, .nag, .weighMiss, .none:
            return [.banner, .sound, .list]
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Snapshot everything we need on the notification-center queue.
        // Crossing into MainActor with the live response object is the crash.
        let payload = ScaleNotificationTapPayload(response: response)
        await ScaleNotificationRouter.handle(payload: payload)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        Task { @MainActor in
            ScaleNotificationRouter.handleOpenSettings()
        }
    }
}

/// Sendable snapshot of a notification tap / action. Built on the
/// notification-center queue; consumed on MainActor.
struct ScaleNotificationTapPayload: Sendable, Equatable {
    var actionIdentifier: String
    var requestId: String
    var title: String
    var subtitle: String
    var body: String
    var categoryIdentifier: String
    var threadIdentifier: String
    var targetContentIdentifier: String?
    var kindRaw: String?
    var destinationRaw: String?
    var deliveredAt: Date
    var interruptionLevel: UNNotificationInterruptionLevel
    var relevanceScore: Double
    var userInfo: [String: String]

    nonisolated init(response: UNNotificationResponse) {
        let content = response.notification.request.content
        let info = content.userInfo
        actionIdentifier = response.actionIdentifier
        requestId = response.notification.request.identifier
        title = content.title
        subtitle = content.subtitle
        body = content.body
        categoryIdentifier = content.categoryIdentifier
        threadIdentifier = content.threadIdentifier
        targetContentIdentifier = content.targetContentIdentifier
        kindRaw = info[ScaleNotificationUserInfoKey.kind] as? String
        destinationRaw = info[ScaleNotificationUserInfoKey.destination] as? String
        deliveredAt = response.notification.date
        interruptionLevel = content.interruptionLevel
        relevanceScore = content.relevanceScore
        var stringInfo: [String: String] = [:]
        for (key, value) in info {
            let keyString: String
            if let s = key as? String {
                keyString = s
            } else {
                keyString = String(describing: key)
            }
            if let s = value as? String {
                stringInfo[keyString] = s
            }
        }
        userInfo = stringInfo
    }

    /// Test / preview constructor.
    nonisolated init(
        actionIdentifier: String,
        requestId: String,
        title: String,
        subtitle: String = "",
        body: String,
        categoryIdentifier: String = "",
        threadIdentifier: String = "",
        targetContentIdentifier: String? = nil,
        kindRaw: String? = nil,
        destinationRaw: String? = nil,
        deliveredAt: Date = Date(),
        interruptionLevel: UNNotificationInterruptionLevel = .active,
        relevanceScore: Double = 0.5,
        userInfo: [String: String] = [:]
    ) {
        self.actionIdentifier = actionIdentifier
        self.requestId = requestId
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.categoryIdentifier = categoryIdentifier
        self.threadIdentifier = threadIdentifier
        self.targetContentIdentifier = targetContentIdentifier
        self.kindRaw = kindRaw
        self.destinationRaw = destinationRaw
        self.deliveredAt = deliveredAt
        self.interruptionLevel = interruptionLevel
        self.relevanceScore = relevanceScore
        self.userInfo = userInfo
    }
}
