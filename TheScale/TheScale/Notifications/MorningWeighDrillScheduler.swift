import Foundation
import UserNotifications

/// Out-of-bed sergeant ping: weigh yourself now.
///
/// Two paths (both required when coaching alerts are on):
/// 1. Sleep-wake ASAP: when FitnessDigest reports a fresh wake, fire in ~1s (BG / scene).
/// 2. Calendar fallback: non-repeating local trigger at the configured morning clock so
///    something ALWAYS lands even when HealthKit sleep wake is missing or BG is throttled.
@MainActor
enum MorningWeighDrillScheduler {
    static let requestId = "thescale.morning-weigh-drill"
    static let fallbackRequestId = "thescale.morning-weigh-fallback"
    static let testRequestId = "thescale.morning-weigh-test"
    private static let lastFiredDayKey = "thescale.morningWeighDrill.lastFiredDay"

    /// Call after digest refresh / scene active / trend refresh.
    /// Always re-arms the calendar fallback when the toggle is on.
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

        // Fallback first: guaranteed pending request whenever coaching morning drill is on.
        await scheduleFallback(
            prefs: prefs,
            profileName: profileName,
            alreadyWeighedToday: alreadyWeighedToday,
            now: now,
            calendar: calendar
        )

        guard !alreadyWeighedToday else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [requestId])
            return
        }

        guard let wake = sleepWake else { return }

        let dayKey = dayStamp(now, calendar: calendar)
        if UserDefaults.standard.string(forKey: lastFiredDayKey) == dayKey {
            return
        }

        let sinceWake = now.timeIntervalSince(wake)
        // 3 min after wake ... 2.5 h window. Avoid midnight false wakes.
        guard sinceWake >= 3 * 60, sinceWake <= 2.5 * 3600 else { return }

        let hour = calendar.component(.hour, from: now)
        guard (4..<12).contains(hour) else { return }

        await fireASAP(
            prefs: prefs,
            profileName: profileName,
            dayKey: dayKey,
            wake: wake,
            alreadyWeighedToday: alreadyWeighedToday,
            now: now,
            calendar: calendar
        )
    }

    /// Next local morning clock for the fallback sergeant drill (pure; testable).
    nonisolated static func nextFallbackFireDate(
        hour: Int,
        minute: Int,
        alreadyWeighedToday: Bool,
        alreadyFiredToday: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> Date {
        let h = min(max(hour, 0), 23)
        let m = min(max(minute, 0), 59)
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = h
        comps.minute = m
        comps.second = 0
        let todaySlot = calendar.date(from: comps) ?? now.addingTimeInterval(3600)

        if alreadyWeighedToday || alreadyFiredToday || todaySlot <= now {
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
            .removePendingNotificationRequests(withIdentifiers: [requestId, testRequestId])
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [requestId, testRequestId])
        // Leave fallback so it can re-arm for tomorrow on next consider().
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [fallbackRequestId])
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
        alreadyWeighedToday: Bool,
        now: Date,
        calendar: Calendar
    ) async {
        let dayKey = dayStamp(now, calendar: calendar)
        let alreadyFired = UserDefaults.standard.string(forKey: lastFiredDayKey) == dayKey
        let fireAt = nextFallbackFireDate(
            hour: prefs.morningWeighFallbackHour,
            minute: prefs.morningWeighFallbackMinute,
            alreadyWeighedToday: alreadyWeighedToday,
            alreadyFiredToday: alreadyFired,
            now: now,
            calendar: calendar
        )

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
        alreadyWeighedToday: Bool,
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
            // Sleep-wake won today: re-arm fallback for tomorrow morning.
            await scheduleFallback(
                prefs: prefs,
                profileName: profileName,
                alreadyWeighedToday: alreadyWeighedToday,
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
