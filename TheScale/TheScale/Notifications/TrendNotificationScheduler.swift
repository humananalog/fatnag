import Foundation
import UserNotifications

/// Local notifications only when trends look bad (or weekly goal nudge if enabled).
/// Algorithmic triggers stay authoritative; Foundation Models may polish copy after schedule.
@MainActor
enum TrendNotificationScheduler {
    static let badTrendId = "thescale.bad-trend"
    static let weeklyGoalId = "thescale.weekly-goal"
    static let goalRevisionId = "thescale.goal-revision"

    /// Fires once when the goal date is biologically unrealistic and commando meals start.
    static func scheduleGoalRevision(proposed: Date) async {
        let allowed = await requestAuthorizationIfNeeded()
        guard allowed else { return }
        let when = proposed.formatted(.dateTime.month(.abbreviated).day().year())
        let content = UNMutableNotificationContent()
        content.title = "Date too fast"
        content.body = "Commando meals are on. Keel pre-selected \(when). Open to keep it or pick another day."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: goalRevisionId, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func requestAuthorizationIfNeeded() async -> Bool {
        #if DEBUG
        if PromoCaptureMode.isActive { return true }
        #endif
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                // Time Sensitive delivery uses the entitlement
                // (com.apple.developer.usernotifications.time-sensitive) plus
                // UNNotificationInterruptionLevel.timeSensitive on content.
                // UNAuthorizationOptions.timeSensitive is deprecated since iOS 15.
                return try await center.requestAuthorization(
                    options: [
                        .alert,
                        .sound,
                        .badge,
                        .providesAppNotificationSettings
                    ]
                )
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Human-readable auth status for Settings / Alerts sheet (includes denied call-to-action).
    static func authorizationStatusDetail() async -> (line: String, isDenied: Bool, isNotDetermined: Bool) {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized:
            let ts: String = {
                switch settings.timeSensitiveSetting {
                case .enabled: return "time-sensitive on"
                case .disabled: return "time-sensitive off"
                case .notSupported: return "time-sensitive n/a"
                @unknown default: return "time-sensitive?"
                }
            }()
            return ("Notifications allowed · \(ts)", false, false)
        case .provisional:
            return ("Provisional (quiet). Enable Alerts in System Settings for full pings.", false, false)
        case .ephemeral:
            return ("Ephemeral authorization active.", false, false)
        case .denied:
            return (
                "Notifications DENIED. Coach drills cannot fire. Open System Settings and allow alerts.",
                true,
                false
            )
        case .notDetermined:
            return ("Not asked yet. Tap Allow to arm Coach drills.", false, true)
        @unknown default:
            return ("Notification status unknown.", false, false)
        }
    }

    /// Evaluate after a Health save / history load / background wake.
    /// Cancels stale bad-trend pings when things improve.
    /// Schedules algorithmic copy first; FM polish is optional and never blocks delivery.
    static func refresh(
        prefs: NotificationPreferences,
        profileName: String,
        currentKg: Double?,
        idealKg: Double,
        recentWeights: [HealthMetricSample],
        weeklyGoal: WeeklyMiniGoal,
        sex: UserBodyProfile.Sex = .male,
        ageYears: Double = 30,
        cultureContext: String = ""
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
                    ),
                    sex: sex,
                    ageYears: ageYears,
                    cultureContext: cultureContext
                )
                if judgment.shouldNotify {
                    let units = PreferredUnitSystemStore.load()
                    let moment = ScaleNotificationCopy.badTrend(
                        profileName: name,
                        currentKg: currentKg,
                        idealKg: idealKg,
                        reason: reason,
                        system: units
                    )
                    let content = ScaleNotificationContentFactory.make(moment)
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 18 * 3600, repeats: false)
                    let request = UNNotificationRequest(identifier: badTrendId, content: content, trigger: trigger)
                    try? await center.add(request)

                    Task {
                        let polished = await FoundationModelCoach.refineNotificationCopy(
                            profileName: name,
                            kind: "bad-trend",
                            fallbackTitle: moment.glanceTitle,
                            fallbackBody: moment.phoneBody,
                            context: reason,
                            sex: sex,
                            ageYears: ageYears,
                            cultureContext: cultureContext
                        )
                        guard polished.usedFoundationModel else { return }
                        guard polished.title != moment.glanceTitle || polished.body != moment.phoneBody else { return }
                        var updatedMoment = moment
                        updatedMoment.glanceTitle = ScaleNotificationCopy.glanceSanitize(polished.title)
                        updatedMoment.phoneBody = polished.body
                        let updated = ScaleNotificationContentFactory.make(updatedMoment)
                        let replacement = UNNotificationRequest(
                            identifier: badTrendId,
                            content: updated,
                            trigger: trigger
                        )
                        try? await center.add(replacement)
                    }
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
            let units = PreferredUnitSystemStore.load()
            let moment = ScaleNotificationCopy.weeklyGoal(
                profileName: name,
                weeklyGoal: weeklyGoal,
                system: units
            )
            let content = ScaleNotificationContentFactory.make(moment)
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(identifier: weeklyGoalId, content: content, trigger: trigger)
            try? await center.add(request)

            Task {
                let polished = await FoundationModelCoach.refineNotificationCopy(
                    profileName: name,
                    kind: "weekly-goal",
                    fallbackTitle: moment.glanceTitle,
                    fallbackBody: moment.phoneBody,
                    context: "Weekly mini-goal: \(weeklyGoal.title)",
                    sex: sex,
                    ageYears: ageYears,
                    cultureContext: cultureContext
                )
                guard polished.usedFoundationModel else { return }
                guard polished.title != moment.glanceTitle || polished.body != moment.phoneBody else { return }
                var updatedMoment = moment
                updatedMoment.glanceTitle = ScaleNotificationCopy.glanceSanitize(polished.title)
                updatedMoment.phoneBody = polished.body
                let updated = ScaleNotificationContentFactory.make(updatedMoment)
                let replacement = UNNotificationRequest(
                    identifier: weeklyGoalId,
                    content: updated,
                    trigger: trigger
                )
                try? await center.add(replacement)
            }
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [weeklyGoalId])
        }
    }

    /// Bad trend: above ideal and rising over ~7 days by ≥0.4 kg, or clear gain streak.
    nonisolated static func badTrendReason(
        currentKg: Double?,
        idealKg: Double,
        recent: [HealthMetricSample],
        unitSystem: PreferredUnitSystem = PreferredUnitSystemStore.load()
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
            return "Up \(UnitFormat.massDeltaString(weekDelta, system: unitSystem)) this week and still above ideal (\(UnitFormat.massString(idealKg, system: unitSystem, fractionDigits: 1))). Not a crisis. Worth a look."
        }
        if weekDelta >= 0.8 {
            return "Sharp \(UnitFormat.massDeltaString(weekDelta, system: unitSystem)) week. Could be water, could be the fridge. Check History."
        }
        return nil
    }
}
