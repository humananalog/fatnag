import Foundation
import UserNotifications

/// Out-of-bed / left-bedtime sergeant ping: weigh yourself now.
/// Wake source: HealthKit sleep analysis wake time from FitnessDigest (Apple Watch sleep stages
/// or legacy asleep). Once per local calendar morning; coalesces pending id.
@MainActor
enum MorningWeighDrillScheduler {
    static let requestId = "thescale.morning-weigh-drill"
    private static let lastFiredDayKey = "thescale.morningWeighDrill.lastFiredDay"

    /// Call after digest refresh / scene active. No-op when prefs off, already weighed, or outside window.
    static func consider(
        prefs: NotificationPreferences,
        profileName: String,
        sleepWake: Date?,
        alreadyWeighedToday: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard prefs.morningWeighDrill else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestId])
            return
        }
        guard !alreadyWeighedToday else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestId])
            return
        }
        guard let wake = sleepWake else { return }

        let dayKey = dayStamp(now, calendar: calendar)
        if UserDefaults.standard.string(forKey: lastFiredDayKey) == dayKey {
            return
        }

        let sinceWake = now.timeIntervalSince(wake)
        // 3 min after wake … 2.5 h window. Avoid midnight false wakes.
        guard sinceWake >= 3 * 60, sinceWake <= 2.5 * 3600 else { return }

        let hour = calendar.component(.hour, from: now)
        guard (4..<12).contains(hour) else { return }

        let allowed = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
        guard allowed else { return }

        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let greet = name.isEmpty ? "Soldier" : name
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
        let pick = drafts[abs(dayKey.hashValue) % drafts.count]

        let content = ScaleNotificationContentFactory.make(
            .init(
                kind: .morningWeigh,
                title: pick.title,
                subtitle: pick.subtitle,
                body: pick.body,
                visualHeadline: "Weigh now",
                visualDetail: "Morning drill"
            )
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestId])
        center.removeDeliveredNotifications(withIdentifiers: [requestId])

        // Fire ASAP (1s) so BG / scene-active paths land while the window is hot.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)
        do {
            try await center.add(request)
            UserDefaults.standard.set(dayKey, forKey: lastFiredDayKey)
            #if DEBUG
            print("[TheScale] Morning weigh drill scheduled (wake \(wake))")
            #endif
        } catch {
            #if DEBUG
            print("[TheScale] Morning weigh drill failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Mark morning drill satisfied after a successful weigh-in today.
    static func markSatisfied(now: Date = Date(), calendar: Calendar = .current) {
        UserDefaults.standard.set(dayStamp(now, calendar: calendar), forKey: lastFiredDayKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestId])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [requestId])
    }

    private static func dayStamp(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
