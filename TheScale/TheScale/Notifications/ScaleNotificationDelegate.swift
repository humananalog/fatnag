import UserNotifications

/// Presents Coach / trend banners while The Scale is in the foreground,
/// and routes taps / actions into the right screen.
final class ScaleNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ScaleNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let kindRaw = notification.request.content.userInfo[ScaleNotificationUserInfoKey.kind] as? String
        let kind = kindRaw.flatMap(ScaleNotificationKind.init(rawValue:))
        switch kind {
        case .fitnessInterval, .weeklyGoal:
            // Quiet while already in-app: list only, no sound.
            return [.banner, .list]
        case .coachWake:
            return [.banner, .sound, .list, .badge]
        case .sample, .badTrend, .watchWear, .preSleepHR, .coachReminder, .none:
            return [.banner, .sound, .list]
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await ScaleNotificationRouter.handle(response: response)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        Task { @MainActor in
            ScaleNotificationRouter.handleOpenSettings()
        }
    }
}
