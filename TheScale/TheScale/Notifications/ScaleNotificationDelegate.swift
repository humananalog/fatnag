import UserNotifications

/// Presents Coach / trend banners while The Scale is in the foreground.
final class ScaleNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ScaleNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
