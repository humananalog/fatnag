import UserNotifications

/// Presents Coach / trend banners while FATNAG is in the foreground,
/// and routes taps / actions into the right screen.
final class ScaleNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = ScaleNotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let kindRaw = notification.request.content.userInfo[ScaleNotificationUserInfoKey.kind] as? String
        let kind = kindRaw.flatMap(ScaleNotificationKind.init(rawValue:))
        switch kind {
        case .fitnessInterval, .weeklyGoal:
            // Quiet while already in-app: list only, no sound.
            return [.banner, .list]
        case .coachWake, .morningWeigh, .weightSpike:
            return [.banner, .sound, .list, .badge]
        case .sample, .badTrend, .watchWear, .preSleepHR, .coachReminder, .none:
            return [.banner, .sound, .list]
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let transferred = UncheckedTransfer(response)
        await ScaleNotificationRouter.handle(response: transferred.value)
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

/// Transfers a non-Sendable UNNotificationResponse into MainActor work.
private struct UncheckedTransfer<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
