import Foundation
import UserNotifications

/// Capped weigh-adherence ladder: evening same-day → day 2–3 soft drift.
/// Monday noon skip + Sunday wrap live here too (weeklyGoalReminders).
///
/// Caps: ≤1 miss-ladder fire / local day, ≤3 / rolling 7 days.
/// Shares morning drill pref for evening/streak; weekly pref for Mon/Sun.
@MainActor
enum WeighMissLadderScheduler {
    static let eveningId = "thescale.weigh-miss.evening"
    static let streakId = "thescale.weigh-miss.streak"
    static let mondaySkipId = "thescale.weigh-miss.monday-skip"
    static let sundayWrapId = "thescale.weigh-miss.sunday-wrap"

    static let maxMissPerDay = 1
    static let maxMissPerWeek = 3
    /// Soft evening slot (local).
    static let eveningHour = 18
    static let eveningMinute = 30
    /// Latest hour to still deliver evening same-day.
    static let eveningWindowEndHour = 21
    /// Mid-afternoon window for multi-day streak nudges.
    static let streakHour = 15
    static let streakMinute = 0
    static let streakWindowEndHour = 20
    /// Monday Progress soft ping if still no Mon weigh.
    static let mondaySkipHour = 12
    /// Sunday wrap (gentle, not a siren).
    static let sundayWrapHour = 18
    static let sundayWrapMinute = 0

    private static let lastMissDayKey = "thescale.weighMiss.lastDay"
    private static let missWeekDaysKey = "thescale.weighMiss.weekDays"
    private static let mondaySkipWeekKey = "thescale.weighMiss.mondaySkipWeek"
    private static let sundayWrapWeekKey = "thescale.weighMiss.sundayWrapWeek"

    nonisolated static var missLadderIds: [String] {
        [eveningId, streakId]
    }

    nonisolated static var allRequestIds: [String] {
        [eveningId, streakId, mondaySkipId, sundayWrapId]
    }

    enum Rung: Equatable, Sendable {
        /// Past morning window, still empty today.
        case eveningSameDay
        /// Missed yesterday (1 full day).
        case day2
        /// Missed 2+ full days.
        case day3Plus
    }

    /// Full local calendar days without a weigh before today.
    /// 0 = weighed yesterday or today (or never — treated as 0 until first day of emptiness accumulates).
    /// If last weigh was 2 calendar days ago → 2.
    nonisolated static func consecutiveMissDays(
        lastWeighDate: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Int {
        guard let lastWeighDate else {
            // No history: don't climb the multi-day ladder from day one of install.
            return 0
        }
        let lastDay = calendar.startOfDay(for: lastWeighDate)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        return max(0, days)
    }

    /// Which rung (if any) should arm for this moment. Pure / testable.
    nonisolated static func resolveRung(
        alreadyWeighedToday: Bool,
        consecutiveMissDays: Int,
        now: Date,
        calendar: Calendar = .current,
        morningDeadlinePassed: Bool
    ) -> Rung? {
        guard !alreadyWeighedToday else { return nil }

        let hour = calendar.component(.hour, from: now)

        // Multi-day streak takes priority over same-day evening once they skipped yesterday+.
        if consecutiveMissDays >= 3 {
            guard hour >= streakHour, hour < streakWindowEndHour else { return nil }
            return .day3Plus
        }
        if consecutiveMissDays >= 2 {
            guard hour >= streakHour, hour < streakWindowEndHour else { return nil }
            return .day2
        }
        // Same-day evening only when morning window is done and they didn't miss prior days.
        if consecutiveMissDays <= 1, morningDeadlinePassed {
            guard hour >= eveningHour, hour < eveningWindowEndHour else { return nil }
            // day1 miss (weighed yesterday, empty today) still gets evening.
            return .eveningSameDay
        }
        return nil
    }

    /// Next fire instant for a rung (calendar or ASAP). Pure.
    nonisolated static func fireDate(
        for rung: Rung,
        now: Date,
        calendar: Calendar = .current
    ) -> Date {
        switch rung {
        case .eveningSameDay:
            return slotOrASAP(
                hour: eveningHour,
                minute: eveningMinute,
                now: now,
                calendar: calendar
            )
        case .day2, .day3Plus:
            return slotOrASAP(
                hour: streakHour,
                minute: streakMinute,
                now: now,
                calendar: calendar
            )
        }
    }

    nonisolated static func isoWeekKey(_ date: Date, calendar: Calendar = .current) -> String {
        let y = calendar.component(.yearForWeekOfYear, from: date)
        let w = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", y, w)
    }

    // MARK: - Consider

    static func consider(
        prefs: NotificationPreferences,
        profileName: String,
        alreadyWeighedToday: Bool,
        recentWeights: [HealthMetricSample],
        weeklyGoal: WeeklyMiniGoal,
        weekBand: WeeklyTrackBand? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let wantMiss = prefs.morningWeighDrill
        let wantWeekly = prefs.weeklyGoalReminders

        if !wantMiss && !wantWeekly {
            cancelAll()
            return
        }

        if alreadyWeighedToday {
            clearMissLadderDeliveredAndPending()
        }

        let allowed = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
        guard allowed else {
            cancelAll()
            return
        }

        let lastWeigh = recentWeights.map(\.date).max()
        let missDays = consecutiveMissDays(lastWeighDate: lastWeigh, now: now, calendar: calendar)
        let morningPast = !ProfileNumericBounds.isBeforeMorningDeadline(now, calendar: calendar)

        if wantMiss, !alreadyWeighedToday {
            await considerMissRung(
                profileName: profileName,
                missDays: missDays,
                morningPast: morningPast,
                now: now,
                calendar: calendar
            )
        } else if !wantMiss {
            cancelMissLadderOnly()
        }

        if wantWeekly {
            await considerMondaySkip(
                profileName: profileName,
                alreadyWeighedToday: alreadyWeighedToday,
                now: now,
                calendar: calendar
            )
            await considerSundayWrap(
                profileName: profileName,
                recentWeights: recentWeights,
                weeklyGoal: weeklyGoal,
                weekBand: weekBand,
                now: now,
                calendar: calendar
            )
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [mondaySkipId, sundayWrapId]
            )
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [mondaySkipId, sundayWrapId]
            )
        }
    }

    /// After a successful same-day weigh: drop miss banners.
    static func markSatisfied() {
        clearMissLadderDeliveredAndPending()
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: allRequestIds)
        center.removeDeliveredNotifications(withIdentifiers: allRequestIds)
    }

    static func cancelMissLadderOnly() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: missLadderIds)
        center.removeDeliveredNotifications(withIdentifiers: missLadderIds)
    }

    static func clearMissLadderDeliveredAndPending() {
        cancelMissLadderOnly()
    }

    // MARK: - Private

    private static func considerMissRung(
        profileName: String,
        missDays: Int,
        morningPast: Bool,
        now: Date,
        calendar: Calendar
    ) async {
        guard canFireMissToday(now: now, calendar: calendar) else {
            // Already used today's miss slot — leave any pending alone if same day.
            return
        }
        guard weekMissCount(now: now, calendar: calendar) < maxMissPerWeek else {
            cancelMissLadderOnly()
            return
        }
        guard let rung = resolveRung(
            alreadyWeighedToday: false,
            consecutiveMissDays: missDays,
            now: now,
            calendar: calendar,
            morningDeadlinePassed: morningPast
        ) else {
            // Past evening window: drop leftover pending. Before windows: keep quiet.
            let hour = calendar.component(.hour, from: now)
            if hour >= eveningWindowEndHour {
                cancelMissLadderOnly()
            }
            return
        }

        guard NotificationDailyBudget.canSpend(.missLadder, now: now, calendar: calendar) else {
            return
        }

        let fireAt = fireDate(for: rung, now: now, calendar: calendar)
        guard fireAt > now.addingTimeInterval(-5) else { return }

        let id = (rung == .eveningSameDay) ? eveningId : streakId
        let otherId = (rung == .eveningSameDay) ? streakId : eveningId
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [otherId])

        let pending = await center.pendingNotificationRequests()
        if let existing = pending.first(where: { $0.identifier == id }) {
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

        let moment = ScaleNotificationCopy.weighMiss(profileName: profileName, rung: rung)
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

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            try await center.add(request)
            recordMissFire(now: now, calendar: calendar)
            NotificationDailyBudget.record(.missLadder, now: now, calendar: calendar)
            #if DEBUG
            print("[TheScale] Weigh miss ladder \(rung) scheduled")
            #endif
        } catch {
            #if DEBUG
            print("[TheScale] Weigh miss ladder failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func considerMondaySkip(
        profileName: String,
        alreadyWeighedToday: Bool,
        now: Date,
        calendar: Calendar
    ) async {
        let weekday = calendar.component(.weekday, from: now) // 1=Sun … 2=Mon
        let hour = calendar.component(.hour, from: now)
        let weekKey = isoWeekKey(now, calendar: calendar)
        let center = UNUserNotificationCenter.current()

        guard weekday == 2, hour >= mondaySkipHour, !alreadyWeighedToday else {
            if weekday != 2 || alreadyWeighedToday {
                center.removePendingNotificationRequests(withIdentifiers: [mondaySkipId])
                if alreadyWeighedToday {
                    center.removeDeliveredNotifications(withIdentifiers: [mondaySkipId])
                }
            }
            return
        }

        if UserDefaults.standard.string(forKey: mondaySkipWeekKey) == weekKey {
            return
        }
        guard NotificationDailyBudget.canSpend(.mondaySkip, now: now, calendar: calendar) else {
            return
        }

        let moment = ScaleNotificationCopy.mondaySkip(profileName: profileName)
        let content = ScaleNotificationContentFactory.make(moment)
        let request = UNNotificationRequest(
            identifier: mondaySkipId,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        do {
            try await center.add(request)
            UserDefaults.standard.set(weekKey, forKey: mondaySkipWeekKey)
            NotificationDailyBudget.record(.mondaySkip, now: now, calendar: calendar)
        } catch {
            #if DEBUG
            print("[TheScale] Monday skip failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func considerSundayWrap(
        profileName: String,
        recentWeights: [HealthMetricSample],
        weeklyGoal: WeeklyMiniGoal,
        weekBand: WeeklyTrackBand?,
        now: Date,
        calendar: Calendar
    ) async {
        let weekday = calendar.component(.weekday, from: now) // 1 = Sunday
        let hour = calendar.component(.hour, from: now)
        let weekKey = isoWeekKey(now, calendar: calendar)
        let center = UNUserNotificationCenter.current()

        guard weekday == 1, hour >= sundayWrapHour else {
            if weekday != 1 {
                center.removePendingNotificationRequests(withIdentifiers: [sundayWrapId])
            }
            return
        }

        if UserDefaults.standard.string(forKey: sundayWrapWeekKey) == weekKey {
            return
        }

        // Only wrap if they engaged at least once this ISO week — miss ladder covers ghosts.
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now.addingTimeInterval(-7 * 86_400)
        let weighsThisWeek = recentWeights.filter { $0.date >= weekStart }.count
        guard weighsThisWeek >= 1 else { return }

        guard NotificationDailyBudget.canSpend(.sundayWrap, now: now, calendar: calendar) else {
            return
        }

        let moment = ScaleNotificationCopy.sundayWrap(
            profileName: profileName,
            weeklyGoal: weeklyGoal,
            band: weekBand,
            weighCount: weighsThisWeek
        )
        let content = ScaleNotificationContentFactory.make(moment)
        let request = UNNotificationRequest(
            identifier: sundayWrapId,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        do {
            try await center.add(request)
            UserDefaults.standard.set(weekKey, forKey: sundayWrapWeekKey)
            NotificationDailyBudget.record(.sundayWrap, now: now, calendar: calendar)
        } catch {
            #if DEBUG
            print("[TheScale] Sunday wrap failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func canFireMissToday(now: Date, calendar: Calendar) -> Bool {
        let day = NotificationDailyBudget.dayStamp(now, calendar: calendar)
        return UserDefaults.standard.string(forKey: lastMissDayKey) != day
    }

    private static func recordMissFire(now: Date, calendar: Calendar) {
        let day = NotificationDailyBudget.dayStamp(now, calendar: calendar)
        UserDefaults.standard.set(day, forKey: lastMissDayKey)
        var days = (UserDefaults.standard.array(forKey: missWeekDaysKey) as? [String]) ?? []
        days.append(day)
        let cutoff = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        days = days.filter { stamp in
            guard let d = parseDayStamp(stamp, calendar: calendar) else { return false }
            return d >= cutoff
        }
        UserDefaults.standard.set(days, forKey: missWeekDaysKey)
    }

    private static func weekMissCount(now: Date, calendar: Calendar) -> Int {
        let days = (UserDefaults.standard.array(forKey: missWeekDaysKey) as? [String]) ?? []
        let cutoff = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        return days.filter { stamp in
            guard let d = parseDayStamp(stamp, calendar: calendar) else { return false }
            return d >= cutoff
        }.count
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

    nonisolated private static func slotOrASAP(
        hour: Int,
        minute: Int,
        now: Date,
        calendar: Calendar
    ) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        let slot = calendar.date(from: comps) ?? now
        if slot <= now {
            return now.addingTimeInterval(5)
        }
        return slot
    }

    /// Test helper.
    nonisolated static func resetForTests(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastMissDayKey)
        defaults.removeObject(forKey: missWeekDaysKey)
        defaults.removeObject(forKey: mondaySkipWeekKey)
        defaults.removeObject(forKey: sundayWrapWeekKey)
    }
}
