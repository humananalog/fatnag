import BackgroundTasks
import Foundation
import UserNotifications

/// Schedules fitness digests + Grok checks. Honest about iOS background limits:
/// BGAppRefresh is best-effort; local notifications + foreground resume are the reliable path.
@MainActor
enum GrokFitnessMonitor {
    static let bgTaskId = "app.thescale.ios.fitness-check"
    static let intervalNotifyId = "thescale.fitness-interval"
    static let triggerNotifyPrefix = "thescale.fitness-trigger."
    static let lastCoachReplyKey = "thescale.lastFitnessCoachReply"

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskId, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                let ok = await Self.runAutomatedCheckIfDue(force: false)
                refresh.setTaskCompleted(success: ok)
            }
            refresh.expirationHandler = { work.cancel() }
        }
    }

    static func scheduleBackgroundRefresh(prefs: FitnessMonitorPreferences) {
        guard prefs.enabled, prefs.interval != .manualOnly else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: bgTaskId)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: bgTaskId)
        let delay = prefs.interval.nominalSeconds ?? (24 * 3600)
        request.earliestBeginDate = Date().addingTimeInterval(min(delay, 12 * 3600))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // iOS may refuse; interval notifications still cover the UX.
        }
    }

    /// Schedule a gentle local notification as a wake hint (iOS will not guarantee BG timing).
    static func scheduleIntervalNotification(
        prefs: FitnessMonitorPreferences,
        profileName: String
    ) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [intervalNotifyId])
        guard prefs.enabled, prefs.interval != .manualOnly else { return }
        let allowed = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
        guard allowed else { return }

        let name = profileName.isEmpty ? "Hey" : profileName
        let polished = await FoundationModelCoach.refineNotificationCopy(
            profileName: name,
            kind: "fitness-interval",
            fallbackTitle: "\(name): fitness check",
            fallbackBody: "Open The Scale so Coach can read the latest Health digest. iOS background is best-effort.",
            context: "Scheduled Health↔Coach interval: \(prefs.interval.title)"
        )
        let content = UNMutableNotificationContent()
        content.title = polished.title
        content.body = polished.body
        content.sound = .default

        switch prefs.interval {
        case .manualOnly:
            return
        case .every6Hours:
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 6 * 3600, repeats: true)
            try? await center.add(
                UNNotificationRequest(identifier: intervalNotifyId, content: content, trigger: trigger)
            )
        case .every12Hours, .morningAndEvening:
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 12 * 3600, repeats: true)
            try? await center.add(
                UNNotificationRequest(identifier: intervalNotifyId, content: content, trigger: trigger)
            )
        case .daily:
            var date = DateComponents()
            date.hour = 8
            date.minute = 20
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            try? await center.add(
                UNNotificationRequest(identifier: intervalNotifyId, content: content, trigger: trigger)
            )
        }
    }

    @discardableResult
    static func runAutomatedCheckIfDue(force: Bool) async -> Bool {
        // Requires a live session; ContentView / app hooks call the ViewModel path.
        // This entry is for BGTask when we stash a weak runner.
        await runner?(force) ?? false
    }

    private static var runner: ((Bool) async -> Bool)?

    static func install(runner: @escaping (Bool) async -> Bool) {
        self.runner = runner
    }

    static func storeLastReply(_ text: String) {
        UserDefaults.standard.set(text, forKey: lastCoachReplyKey)
    }

    static func loadLastReply() -> String? {
        UserDefaults.standard.string(forKey: lastCoachReplyKey)
    }

    static func notifyTriggers(
        _ triggers: [FitnessTrigger],
        prefs: inout FitnessMonitorPreferences,
        profileName: String,
        now: Date = Date()
    ) async {
        guard prefs.notifyOnTriggers, !triggers.isEmpty else { return }
        let allowed = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
        guard allowed else { return }
        let center = UNUserNotificationCenter.current()
        let name = profileName.isEmpty ? "Hey" : profileName

        for trigger in triggers {
            let judgment = await FoundationModelCoach.shouldSendPing(
                profileName: name,
                kind: trigger.kind.rawValue,
                algorithmicReason: trigger.message,
                extraContext: "severity=\(trigger.severity)"
            )
            guard judgment.shouldNotify else { continue }

            switch trigger.kind {
            case .watchLikelyNotWorn:
                if let last = prefs.lastWatchWearNotifyAt,
                   now.timeIntervalSince(last) < prefs.thresholds.watchWearNotifyCooldownHours * 3600 {
                    continue
                }
                prefs.lastWatchWearNotifyAt = now
            case .preSleepHRElevated, .preSleepHRMissing:
                if let last = prefs.lastPreSleepAlertAt,
                   now.timeIntervalSince(last) < 20 * 3600 {
                    continue
                }
                prefs.lastPreSleepAlertAt = now
            }

            let polished = await FoundationModelCoach.refineNotificationCopy(
                profileName: name,
                kind: trigger.kind.rawValue,
                fallbackTitle: "\(name): Coach signal",
                fallbackBody: trigger.message,
                context: trigger.message
            )
            let content = UNMutableNotificationContent()
            content.title = polished.title
            content.body = polished.body
            content.sound = .default
            let id = triggerNotifyPrefix + trigger.kind.rawValue
            let request = UNNotificationRequest(
                identifier: id,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
