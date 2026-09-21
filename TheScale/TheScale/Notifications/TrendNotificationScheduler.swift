import Foundation
import UserNotifications

/// Local notifications only when trends look bad (or weekly goal nudge if enabled).
/// Algorithmic triggers stay authoritative; Foundation Models may polish copy and suppress noise.
@MainActor
enum TrendNotificationScheduler {
    static let badTrendId = "thescale.bad-trend"
    static let weeklyGoalId = "thescale.weekly-goal"

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(
                    options: [.alert, .sound, .badge, .providesAppNotificationSettings]
                )
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Evaluate after a Health save / history load / background wake.
    /// Cancels stale bad-trend pings when things improve.
    static func refresh(
        prefs: NotificationPreferences,
        profileName: String,
        currentKg: Double?,
        idealKg: Double,
        recentWeights: [HealthMetricSample],
        weeklyGoal: WeeklyMiniGoal
    ) async {
        let center = UNUserNotificationCenter.current()
        guard prefs.notifyOnBadTrend || prefs.weeklyGoalReminders else {
            center.removePendingNotificationRequests(withIdentifiers: [badTrendId, weeklyGoalId])
            return
        }
        let allowed = await requestAuthorizationIfNeeded()
        guard allowed else { return }

        let name = profileName.isEmpty ? "Hey" : profileName

        if prefs.notifyOnBadTrend {
            if let reason = badTrendReason(currentKg: currentKg, idealKg: idealKg, recent: recentWeights) {
                let judgment = await FoundationModelCoach.shouldSendPing(
                    profileName: name,
                    kind: "bad-trend",
                    algorithmicReason: reason,
                    extraContext: String(
                        format: "currentKg=%@ idealKg=%.1f",
                        currentKg.map { String(format: "%.1f", $0) } ?? "nil",
                        idealKg
                    )
                )
                if judgment.shouldNotify {
                    let kgBit = currentKg.map { String(format: "%.1f kg", $0) } ?? "weight"
                    let fallbackTitle = "\(name): scale check"
                    let fallbackSubtitle = kgBit + " · above pace"
                    let polished = await FoundationModelCoach.refineNotificationCopy(
                        profileName: name,
                        kind: "bad-trend",
                        fallbackTitle: fallbackTitle,
                        fallbackBody: reason,
                        context: reason
                    )
                    let content = ScaleNotificationContentFactory.make(
                        .init(
                            kind: .badTrend,
                            title: polished.title,
                            subtitle: fallbackSubtitle,
                            body: polished.body,
                            visualHeadline: kgBit,
                            visualDetail: String(format: "Ideal %.1f kg", idealKg)
                        )
                    )
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 18 * 3600, repeats: false)
                    let request = UNNotificationRequest(identifier: badTrendId, content: content, trigger: trigger)
                    try? await center.add(request)
                } else {
                    center.removePendingNotificationRequests(withIdentifiers: [badTrendId])
                }
            } else {
                center.removePendingNotificationRequests(withIdentifiers: [badTrendId])
            }
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [badTrendId])
        }

        if prefs.weeklyGoalReminders {
            var date = DateComponents()
            date.weekday = 2 // Monday
            date.hour = 8
            date.minute = 15
            let fallbackTitle = "\(name): weekly mini-goal"
            let fallbackSubtitle = weeklyGoal.title
            let fallbackBody = "\(weeklyGoal.title) Open Progress when you're ready."
            let polished = await FoundationModelCoach.refineNotificationCopy(
                profileName: name,
                kind: "weekly-goal",
                fallbackTitle: fallbackTitle,
                fallbackBody: fallbackBody,
                context: "Weekly mini-goal: \(weeklyGoal.title)"
            )
            let content = ScaleNotificationContentFactory.make(
                .init(
                    kind: .weeklyGoal,
                    title: polished.title,
                    subtitle: fallbackSubtitle,
                    body: polished.body,
                    visualHeadline: String(format: "%+.1f kg", weeklyGoal.targetDeltaKg),
                    visualDetail: "Monday mini-goal"
                )
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(identifier: weeklyGoalId, content: content, trigger: trigger)
            try? await center.add(request)
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [weeklyGoalId])
        }
    }

    /// Bad trend: above ideal and rising over ~7 days by ≥0.4 kg, or clear gain streak.
    nonisolated static func badTrendReason(
        currentKg: Double?,
        idealKg: Double,
        recent: [HealthMetricSample]
    ) -> String? {
        guard let currentKg else { return nil }
        let ordered = recent.sorted { $0.date < $1.date }
        guard ordered.count >= 2 else { return nil }

        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let weekSamples = ordered.filter { $0.date >= weekAgo }
        let baseline: Double = {
            if let first = weekSamples.first { return first.value }
            return ordered[max(ordered.count - 4, 0)].value
        }()
        let weekDelta = currentKg - baseline
        let aboveIdeal = currentKg > idealKg + 0.3

        if aboveIdeal, weekDelta >= 0.4 {
            return String(
                format: "Up %.1f kg this week and still above ideal (%.1f). Not a crisis. Worth a look.",
                weekDelta,
                idealKg
            )
        }
        if weekDelta >= 0.8 {
            return String(
                format: "Sharp +%.1f kg week. Could be water, could be the fridge. Check History.",
                weekDelta
            )
        }
        return nil
    }
}
