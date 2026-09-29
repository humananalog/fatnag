import Foundation
import UserNotifications

/// Out-of-bed sergeant ping: weigh yourself now.
///
/// Rules (2.50+):
/// - Max once per local day (`lastFiredDayKey`).
/// - Never schedule or fire at/after **08:00** local for "today."
/// - If already weighed today (body mass before 8:00 local day): cancel today's ASAP; arm **tomorrow** morning only (idempotent).
/// - Fallback default **06:30** local; schedule is **idempotent**: do not remove/re-add when the pending fire date already matches.
/// - Sleep-wake ASAP when Health has wake (before 08:00); calendar fallback otherwise.
@MainActor
enum MorningWeighDrillScheduler {
    static let requestId = "thescale.morning-weigh-drill"
    static let fallbackRequestId = "thescale.morning-weigh-fallback"
    static let testRequestId = "thescale.morning-weigh-test"
    private static let lastFiredDayKey = "thescale.morningWeighDrill.lastFiredDay"
    /// Match window when comparing pending vs intended fire (calendar trigger rebuild noise).
    nonisolated static let fireDateMatchTolerance: TimeInterval = 60

    /// Watch glance + iPhone body. Time Sensitive via kind.
    nonisolated static let drillTitle = "💩 Weigh"
    nonisolated static let drillSubtitle = "Empty bladder · scale"
    nonisolated static let drillBodyCore = "Go drop a 💩, step on the scale, then open fatnag. Morning mass locks the week."

    /// Call after digest refresh / scene active / trend refresh.
    /// Safe to call often: fallback `add` only runs when the intended fire date changed.
    static func consider(
        prefs: NotificationPreferences,
        profileName: String,
        sleepWake: Date?,
        alreadyWeighedToday: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard prefs.morningWeighDrill else {
            cancelAllPending()
            return
        }

        let allowed = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
        guard allowed else {
            cancelAllPending()
            return
        }

        let dayKey = dayStamp(now, calendar: calendar)
        let alreadyFired = UserDefaults.standard.string(forKey: lastFiredDayKey) == dayKey

        // Already weighed or already fired today: drop today's ASAP; arm tomorrow (idempotent).
        if alreadyWeighedToday || alreadyFired {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [requestId]
            )
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [requestId]
            )
            await ensureFallbackScheduled(
                prefs: prefs,
                profileName: profileName,
                forceTomorrow: true,
                now: now,
                calendar: calendar
            )
            return
        }

        // Past 08:00 local: no today fire; arm tomorrow only.
        if !ProfileNumericBounds.isBeforeMorningDeadline(now, calendar: calendar) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [requestId]
            )
            await ensureFallbackScheduled(
                prefs: prefs,
                profileName: profileName,
                forceTomorrow: true,
                now: now,
                calendar: calendar
            )
            return
        }

        await ensureFallbackScheduled(
            prefs: prefs,
            profileName: profileName,
            forceTomorrow: false,
            now: now,
            calendar: calendar
        )

        guard let wake = sleepWake else { return }

        let sinceWake = now.timeIntervalSince(wake)
        // 3 min after wake ... 2.5 h window. Avoid midnight false wakes.
        guard sinceWake >= 3 * 60, sinceWake <= 2.5 * 3600 else { return }

        let hour = calendar.component(.hour, from: now)
        guard (4..<ProfileNumericBounds.morningWeighDeadlineHour).contains(hour) else { return }

        await fireASAP(
            prefs: prefs,
            profileName: profileName,
            dayKey: dayKey,
            wake: wake,
            now: now,
            calendar: calendar
        )
    }

    /// Next local morning clock for the fallback sergeant drill (pure; testable).
    /// Uses `calendar` date components (device local TZ). Always before 08:00 local.
    nonisolated static func nextFallbackFireDate(
        hour: Int,
        minute: Int,
        alreadyWeighedToday: Bool,
        alreadyFiredToday: Bool,
        now: Date,
        calendar: Calendar = .current,
        forceTomorrow: Bool = false
    ) -> Date {
        let clamped = ProfileNumericBounds.clampMorningFallback(hour: hour, minute: minute)
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = clamped.hour
        comps.minute = clamped.minute
        comps.second = 0
        let todaySlot = calendar.date(from: comps) ?? now.addingTimeInterval(3600)

        let pastDeadline = !ProfileNumericBounds.isBeforeMorningDeadline(now, calendar: calendar)
        if forceTomorrow || alreadyWeighedToday || alreadyFiredToday || todaySlot <= now || pastDeadline {
            return calendar.date(byAdding: .day, value: 1, to: todaySlot)
                ?? now.addingTimeInterval(86_400)
        }
        return todaySlot
    }

    /// True when an existing pending fire is close enough to the intended instant.
    nonisolated static func pendingFireMatchesIntended(
        pending: Date?,
        intended: Date,
        tolerance: TimeInterval = fireDateMatchTolerance
    ) -> Bool {
        guard let pending else { return false }
        return abs(pending.timeIntervalSince(intended)) <= tolerance
    }

    /// Watch glance title/subtitle + iPhone body. Pure; testable.
    nonisolated static func drillCopy(profileName: String, variant: DrillCopyVariant = .fallback) -> (
        title: String,
        subtitle: String,
        body: String
    ) {
        let moment = ScaleNotificationCopy.morningWeigh(profileName: profileName)
        switch variant {
        case .sleepWake, .fallback:
            return (moment.glanceTitle, moment.glanceLine, moment.phoneBody)
        }
    }

    enum DrillCopyVariant: Sendable {
        case sleepWake
        case fallback
    }


    /// Mark morning drill satisfied after a successful weigh-in today.
    static func markSatisfied(now: Date = Date(), calendar: Calendar = .current) {
        UserDefaults.standard.set(dayStamp(now, calendar: calendar), forKey: lastFiredDayKey)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestId, testRequestId])
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [requestId, testRequestId])
        // Fallback re-armed for tomorrow on next consider(); leave pending if already tomorrow.
    }

    static func cancelAllPending() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [requestId, fallbackRequestId, testRequestId]
        )
    }

    // MARK: - Private

    /// Schedule calendar fallback only when missing or fire date differs.
    private static func ensureFallbackScheduled(
        prefs: NotificationPreferences,
        profileName: String,
        forceTomorrow: Bool,
        now: Date,
        calendar: Calendar
    ) async {
        let dayKey = dayStamp(now, calendar: calendar)
        let alreadyFired = UserDefaults.standard.string(forKey: lastFiredDayKey) == dayKey
        let fireAt = nextFallbackFireDate(
            hour: prefs.morningWeighFallbackHour,
            minute: prefs.morningWeighFallbackMinute,
            alreadyWeighedToday: false,
            alreadyFiredToday: alreadyFired,
            now: now,
            calendar: calendar,
            forceTomorrow: forceTomorrow
        )

        // Never schedule a same-day slot at or after 08:00 local.
        if calendar.isDate(fireAt, inSameDayAs: now),
           !ProfileNumericBounds.isBeforeMorningDeadline(fireAt, calendar: calendar)
        {
            return
        }

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        if let existing = pending.first(where: { $0.identifier == fallbackRequestId }) {
            let existingFire = nextFireDate(from: existing.trigger)
            if pendingFireMatchesIntended(pending: existingFire, intended: fireAt) {
                // Already armed for this local morning. Do not remove/re-add (stops log spam).
                return
            }
        }

        let content = makeContent(profileName: profileName, variant: .fallback)
        // Explicit local calendar components (device TZ via `calendar`).
        var comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireAt
        )
        comps.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: fallbackRequestId,
            content: content,
            trigger: trigger
        )
        center.removePendingNotificationRequests(withIdentifiers: [fallbackRequestId])
        do {
            try await center.add(request)
            #if DEBUG
            let local = fireAt.formatted(date: .abbreviated, time: .shortened)
            print(
                "[TheScale] Morning weigh fallback scheduled local=\(local) tz=\(calendar.timeZone.identifier)"
            )
            #endif
        } catch {
            #if DEBUG
            print("[TheScale] Morning weigh fallback failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func nextFireDate(from trigger: UNNotificationTrigger?) -> Date? {
        if let cal = trigger as? UNCalendarNotificationTrigger {
            return cal.nextTriggerDate()
        }
        if let interval = trigger as? UNTimeIntervalNotificationTrigger {
            return interval.nextTriggerDate()
        }
        return nil
    }

    private static func fireASAP(
        prefs: NotificationPreferences,
        profileName: String,
        dayKey: String,
        wake: Date,
        now: Date,
        calendar: Calendar
    ) async {
        let content = makeContent(profileName: profileName, variant: .sleepWake)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestId])
        center.removeDeliveredNotifications(withIdentifiers: [requestId])

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)
        do {
            try await center.add(request)
            UserDefaults.standard.set(dayKey, forKey: lastFiredDayKey)
            await ensureFallbackScheduled(
                prefs: prefs,
                profileName: profileName,
                forceTomorrow: true,
                now: now,
                calendar: calendar
            )
            #if DEBUG
            print("[TheScale] Morning weigh drill scheduled (wake \(wake))")
            #endif
        } catch {
            #if DEBUG
            print("[TheScale] Morning weigh drill failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func makeContent(profileName: String, variant: DrillCopyVariant) -> UNNotificationContent {
        _ = variant
        return ScaleNotificationContentFactory.make(
            ScaleNotificationCopy.morningWeigh(profileName: profileName)
        )
    }

    private static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
