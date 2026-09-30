import Foundation
import UserNotifications

/// Local notifications only when trends look bad (or weekly goal nudge if enabled).
/// Algorithmic triggers stay authoritative; Foundation Models may polish copy after schedule.
@MainActor
enum TrendNotificationScheduler {
    static let badTrendId = "thescale.bad-trend"
    static let weeklyGoalId = "thescale.weekly-goal"
    static let goalRevisionId = "thescale.goal-revision"

    /// Min distinct local days with a weigh in the last 7d before bad-trend can fire.
    nonisolated static let badTrendMinDistinctDays = 3
    /// Min calendar days between bad-trend schedules.
    nonisolated static let badTrendMinDaysBetweenFires = 3

    private nonisolated static let lastBadTrendDayKey = "thescale.badTrend.lastFireDay"

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
        alreadyWeighedToday: Bool = false,
        sex: UserBodyProfile.Sex = .male,
        ageYears: Double = 30,
        cultureContext: String = "",
        now: Date = Date(),
        calendar: Calendar = .current
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
            await refreshBadTrend(
                center: center,
                name: name,
                currentKg: currentKg,
                idealKg: idealKg,
                recentWeights: recentWeights,
                sex: sex,
                ageYears: ageYears,
                cultureContext: cultureContext,
                now: now,
                calendar: calendar
            )
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [badTrendId])
        }

        if prefs.weeklyGoalReminders {
            await refreshMondayWeeklyGoal(
                center: center,
                name: name,
                weeklyGoal: weeklyGoal,
                alreadyWeighedToday: alreadyWeighedToday,
                sex: sex,
                ageYears: ageYears,
                cultureContext: cultureContext,
                now: now,
                calendar: calendar
            )
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [weeklyGoalId])
        }
    }

    // MARK: - Bad trend

    private static func refreshBadTrend(
        center: UNUserNotificationCenter,
        name: String,
        currentKg: Double?,
        idealKg: Double,
        recentWeights: [HealthMetricSample],
        sex: UserBodyProfile.Sex,
        ageYears: Double,
        cultureContext: String,
        now: Date,
        calendar: Calendar
    ) async {
        guard let reason = badTrendReason(currentKg: currentKg, idealKg: idealKg, recent: recentWeights) else {
            center.removePendingNotificationRequests(withIdentifiers: [badTrendId])
            return
        }

        let pending = await center.pendingNotificationRequests()
        // Keep an already-armed 18h delay; do not cancel on cooldown re-check.
        if pending.contains(where: { $0.identifier == badTrendId }) {
            return
        }

        guard badTrendEligible(
            recent: recentWeights,
            lastFireDay: UserDefaults.standard.string(forKey: lastBadTrendDayKey),
            now: now,
            calendar: calendar
        ) else {
            return
        }
        guard NotificationDailyBudget.canSpend(.badTrend, now: now, calendar: calendar) else {
            return
        }

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
        guard judgment.shouldNotify else { return }

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
        recordBadTrendFire(now: now, calendar: calendar)
        NotificationDailyBudget.record(.badTrend, now: now, calendar: calendar)

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
    }

    /// Sparse weighers and recent fires skip bad-trend. Pure / testable.
    nonisolated static func badTrendEligible(
        recent: [HealthMetricSample],
        lastFireDay: String?,
        now: Date = Date(),
        calendar: Calendar = .current,
        minDistinctDays: Int = badTrendMinDistinctDays,
        minDaysBetweenFires: Int = badTrendMinDaysBetweenFires
    ) -> Bool {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let distinctDays = Set(
            recent
                .filter { $0.date >= weekAgo }
                .map { NotificationDailyBudget.dayStamp($0.date, calendar: calendar) }
        )
        guard distinctDays.count >= minDistinctDays else { return false }

        if let lastFireDay,
           let lastDate = parseDayStamp(lastFireDay, calendar: calendar)
        {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: lastDate),
                to: calendar.startOfDay(for: now)
            ).day ?? 0
            guard days >= minDaysBetweenFires else { return false }
        }
        return true
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

    // MARK: - Monday weekly (miss-aware, non-repeating)

    /// One-shot Monday 08:15 only when Mon weigh is still missing. Cancels if weighed.
    /// Noon+ skip is handled by `WeighMissLadderScheduler`.
    private static func refreshMondayWeeklyGoal(
        center: UNUserNotificationCenter,
        name: String,
        weeklyGoal: WeeklyMiniGoal,
        alreadyWeighedToday: Bool,
        sex: UserBodyProfile.Sex,
        ageYears: Double,
        cultureContext: String,
        now: Date,
        calendar: Calendar
    ) async {
        let weekday = calendar.component(.weekday, from: now) // 2 = Monday
        let hour = calendar.component(.hour, from: now)

        // Not Monday: drop any leftover one-shot (legacy repeating cancelled here too).
        guard weekday == 2 else {
            center.removePendingNotificationRequests(withIdentifiers: [weeklyGoalId])
            return
        }

        // Weighed Mon morning → no weekly siren.
        if alreadyWeighedToday {
            center.removePendingNotificationRequests(withIdentifiers: [weeklyGoalId])
            center.removeDeliveredNotifications(withIdentifiers: [weeklyGoalId])
            return
        }

        // After noon: Monday skip ladder owns the soft Progress ping.
        if hour >= WeighMissLadderScheduler.mondaySkipHour {
            center.removePendingNotificationRequests(withIdentifiers: [weeklyGoalId])
            return
        }

        let fireAt = mondayWeeklyFireDate(now: now, calendar: calendar)
        let pending = await center.pendingNotificationRequests()
        if let existing = pending.first(where: { $0.identifier == weeklyGoalId }) {
            let existingFire: Date? = {
                if let cal = existing.trigger as? UNCalendarNotificationTrigger {
                    return cal.nextTriggerDate()
                }
                if let interval = existing.trigger as? UNTimeIntervalNotificationTrigger {
                    return interval.nextTriggerDate()
                }
                return nil
            }()
            if MorningWeighDrillScheduler.pendingFireMatchesIntended(
                pending: existingFire,
                intended: fireAt
            ) {
                return
            }
        }

        guard NotificationDailyBudget.canSpend(.weeklyGoal, now: now, calendar: calendar) else {
            return
        }

        let units = PreferredUnitSystemStore.load()
        let moment = ScaleNotificationCopy.weeklyGoal(
            profileName: name,
            weeklyGoal: weeklyGoal,
            system: units,
            alreadyWeighedToday: false
        )
        let content = ScaleNotificationContentFactory.make(moment)

        let trigger: UNNotificationTrigger = {
            let seconds = fireAt.timeIntervalSince(now)
            if seconds <= 90 {
                return UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 2), repeats: false)
            }
            var comps = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireAt
            )
            comps.timeZone = calendar.timeZone
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        }()

        let request = UNNotificationRequest(identifier: weeklyGoalId, content: content, trigger: trigger)
        do {
            center.removePendingNotificationRequests(withIdentifiers: [weeklyGoalId])
            try await center.add(request)
            NotificationDailyBudget.record(.weeklyGoal, now: now, calendar: calendar)

            Task {
                let polished = await FoundationModelCoach.refineNotificationCopy(
                    profileName: name,
                    kind: "weekly-goal",
                    fallbackTitle: moment.glanceTitle,
                    fallbackBody: moment.phoneBody,
                    context: "Weekly mini-goal: \(weeklyGoal.title) · Mon weigh still missing",
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
        } catch {
            #if DEBUG
            print("[TheScale] Monday weekly goal failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// 08:15 local Monday, or ASAP if already past 08:15 and before noon.
    nonisolated static func mondayWeeklyFireDate(
        now: Date,
        calendar: Calendar = .current
    ) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = 8
        comps.minute = 15
        comps.second = 0
        let slot = calendar.date(from: comps) ?? now
        if slot <= now {
            return now.addingTimeInterval(5)
        }
        return slot
    }

    private static func recordBadTrendFire(now: Date, calendar: Calendar) {
        UserDefaults.standard.set(
            NotificationDailyBudget.dayStamp(now, calendar: calendar),
            forKey: lastBadTrendDayKey
        )
    }

    nonisolated private static func parseDayStamp(_ stamp: String, calendar: Calendar) -> Date? {
        let parts = stamp.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        return calendar.date(from: comps)
    }

    /// Test helper.
    nonisolated static func resetBadTrendForTests(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastBadTrendDayKey)
    }
}
