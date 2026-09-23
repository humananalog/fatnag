import Foundation
import UserNotifications

/// Out-of-bed sergeant ping: weigh yourself now.
///
/// Rules (2.35+):
/// - Max once per local day (`lastFiredDayKey`).
/// - Never schedule or fire after 09:00 local.
/// - If a valid weigh-in already exists today, cancel wake + fallback for today.
/// - Sleep-wake ASAP when Health has wake; calendar fallback before 09:00 otherwise.
@MainActor
enum MorningWeighDrillScheduler {
    static let requestId = "thescale.morning-weigh-drill"
    static let fallbackRequestId = "thescale.morning-weigh-fallback"
    static let testRequestId = "thescale.morning-weigh-test"
    private static let lastFiredDayKey = "thescale.morningWeighDrill.lastFiredDay"

    /// Call after digest refresh / scene active / trend refresh.
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

        // Already weighed or already fired today: kill today's drills; arm tomorrow only.
        if alreadyWeighedToday || alreadyFired {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [requestId, fallbackRequestId]
            )
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [requestId]
            )
            await scheduleFallback(
                prefs: prefs,
                profileName: profileName,
                forceTomorrow: true,
                now: now,
                calendar: calendar
            )
            return
        }

        // Past 09:00 local: do not schedule or deliver today.
        if !ProfileNumericBounds.isBeforeMorningDeadline(now, calendar: calendar) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [requestId, fallbackRequestId]
            )
            await scheduleFallback(
                prefs: prefs,
                profileName: profileName,
                forceTomorrow: true,
                now: now,
                calendar: calendar
            )
            return
        }

        await scheduleFallback(
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
    /// Always before 09:00. Rolls to tomorrow when weighed, fired, past slot, or past deadline.
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

    /// DEBUG / Settings QA: schedule a sergeant test ping in ~2s. Does not burn the day stamp.
    @discardableResult
    static func forceFireTest(profileName: String) async -> Bool {
        let allowed = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
        guard allowed else { return false }
        let content = makeContent(profileName: profileName, variant: .test)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [testRequestId])
        center.removeDeliveredNotifications(withIdentifiers: [testRequestId])
        let request = UNNotificationRequest(
            identifier: testRequestId,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    /// Mark morning drill satisfied after a successful weigh-in today.
    static func markSatisfied(now: Date = Date(), calendar: Calendar = .current) {
        UserDefaults.standard.set(dayStamp(now, calendar: calendar), forKey: lastFiredDayKey)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestId, testRequestId, fallbackRequestId])
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [requestId, testRequestId])
    }

    static func cancelAllPending() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [requestId, fallbackRequestId, testRequestId]
        )
    }

    // MARK: - Private

    private enum CopyVariant {
        case sleepWake
        case fallback
        case test
    }

    private static func scheduleFallback(
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

        // Never schedule a same-day slot at or after 09:00.
        if calendar.isDate(fireAt, inSameDayAs: now),
           !ProfileNumericBounds.isBeforeMorningDeadline(fireAt, calendar: calendar)
        {
            return
        }

        let content = makeContent(profileName: profileName, variant: .fallback)
        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: fallbackRequestId,
            content: content,
            trigger: trigger
        )
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [fallbackRequestId])
        do {
            try await center.add(request)
            #if DEBUG
            print("[TheScale] Morning weigh fallback scheduled \(fireAt)")
            #endif
        } catch {
            #if DEBUG
            print("[TheScale] Morning weigh fallback failed: \(error.localizedDescription)")
            #endif
        }
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
            await scheduleFallback(
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

    private static func makeContent(profileName: String, variant: CopyVariant) -> UNNotificationContent {
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let greet = name.isEmpty ? "Soldier" : name
        let pick: (title: String, subtitle: String, body: String)
        switch variant {
        case .sleepWake:
            let drafts = [
                (
                    title: "Keel · weigh drill",
                    subtitle: "Out of bed. On the scale.",
                    body: "\(greet). Boots off the mattress: barefoot, empty bladder, same scale. Hit the platform before coffee invents a narrative."
                ),
                (
                    title: "Keel · morning weigh",
                    subtitle: "Left bedtime. Move.",
                    body: "\(greet). Sleep scored. Now the number. No doomscroll. Step on. Sunday target does not update itself."
                ),
                (
                    title: "Keel · stand and weigh",
                    subtitle: "Wake confirmed.",
                    body: "\(greet). You left the nest. Scale first. Keel wants the morning kg before the day rewrites the plot."
                )
            ]
            pick = drafts[abs(dayStamp(Date()).hashValue) % drafts.count]
        case .fallback:
            pick = (
                title: "Keel · morning weigh",
                subtitle: "Sergeant drill. Scale now.",
                body: "\(greet). Wake data was soft. Drill still stands. Barefoot, empty bladder, same scale. Report the number."
            )
        case .test:
            pick = (
                title: "Keel · test drill",
                subtitle: "Force-fire QA.",
                body: "\(greet). Test ping only. If you see this banner, local notifications are armed."
            )
        }
        return ScaleNotificationContentFactory.make(
            .init(
                kind: .morningWeigh,
                title: pick.title,
                subtitle: pick.subtitle,
                body: pick.body,
                visualHeadline: "Weigh now",
                visualDetail: variant == .test ? "Test drill" : "Morning drill"
            )
        )
    }

    private static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
