import BackgroundTasks
import Foundation
import UserNotifications

/// Schedules fitness digests + Grok checks. Honest about iOS background limits:
/// `HKObserverQuery` + background delivery wake the app for Health writes;
/// `BGAppRefresh` / `BGProcessing` are best-effort backups. Local notifications
/// still deliver when the UI never opens.
@MainActor
enum GrokFitnessMonitor {
    static let bgRefreshTaskId = "app.thescale.ios.fitness-check"
    static let bgProcessingTaskId = "app.thescale.ios.fitness-processing"
    /// Legacy alias used by older call sites / docs.
    static let bgTaskId = bgRefreshTaskId
    static let intervalNotifyId = "thescale.fitness-interval"
    static let triggerNotifyPrefix = "thescale.fitness-trigger."
    static let lastCoachReplyKey = "thescale.lastFitnessCoachReply"

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgRefreshTaskId, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                await HealthKitBackgroundDelivery.shared.handleTaskWake(reason: .appRefresh)
                let ok = await Self.runAutomatedCheckIfDue(force: false)
                Self.scheduleBackgroundRefresh(prefs: FitnessMonitorPreferencesStore.load())
                Self.scheduleBackgroundProcessing(prefs: FitnessMonitorPreferencesStore.load())
                refresh.setTaskCompleted(success: ok)
            }
            refresh.expirationHandler = { work.cancel() }
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgProcessingTaskId, using: nil) { task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                await HealthKitBackgroundDelivery.shared.handleTaskWake(reason: .processingTask)
                let ok = await Self.runAutomatedCheckIfDue(force: true)
                Self.scheduleBackgroundProcessing(prefs: FitnessMonitorPreferencesStore.load())
                processing.setTaskCompleted(success: ok)
            }
            processing.expirationHandler = { work.cancel() }
        }
    }

    static func scheduleBackgroundRefresh(prefs: FitnessMonitorPreferences) {
        guard prefs.enabled, prefs.interval != .manualOnly else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: bgRefreshTaskId)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: bgRefreshTaskId)
        let delay = prefs.interval.nominalSeconds ?? (24 * 3600)
        request.earliestBeginDate = Date().addingTimeInterval(min(delay, 12 * 3600))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // iOS may refuse; HealthKit observers + interval notifications still cover the UX.
        }
    }

    static func scheduleBackgroundProcessing(prefs: FitnessMonitorPreferences) {
        guard prefs.enabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: bgProcessingTaskId)
            return
        }
        let request = BGProcessingTaskRequest(identifier: bgProcessingTaskId)
        request.requiresNetworkConnectivity = GrokPrivacyConsent.isAccepted && GrokSharedConfig.isLiveConfigured
        request.requiresExternalPower = false
        request.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Best-effort; observer wakes remain primary.
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
        let fallbackTitle = "\(name): fitness check"
        let fallbackSubtitle = prefs.interval.title
        let fallbackBody = "Health updated in the background. Open Coach if you want the full read. iOS throttles wakes."
        let polished = await FoundationModelCoach.refineNotificationCopy(
            profileName: name,
            kind: "fitness-interval",
            fallbackTitle: fallbackTitle,
            fallbackBody: fallbackBody,
            context: "Scheduled Health↔Coach interval: \(prefs.interval.title)"
        )
        let content = ScaleNotificationContentFactory.make(
            .init(
                kind: .fitnessInterval,
                title: polished.title,
                subtitle: fallbackSubtitle,
                body: polished.body,
                visualHeadline: "Check-in",
                visualDetail: prefs.interval.title
            )
        )

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

            let kind: ScaleNotificationKind = {
                switch trigger.kind {
                case .watchLikelyNotWorn: return .watchWear
                case .preSleepHRElevated, .preSleepHRMissing: return .preSleepHR
                }
            }()
            let subtitle: String = {
                switch trigger.kind {
                case .watchLikelyNotWorn: return "Watch wear"
                case .preSleepHRElevated: return "Pre-sleep HR high"
                case .preSleepHRMissing: return "Pre-sleep HR missing"
                }
            }()
            let polished = await FoundationModelCoach.refineNotificationCopy(
                profileName: name,
                kind: trigger.kind.rawValue,
                fallbackTitle: "\(name): Coach signal",
                fallbackBody: trigger.message,
                context: trigger.message
            )
            let content = ScaleNotificationContentFactory.make(
                .init(
                    kind: kind,
                    title: polished.title,
                    subtitle: subtitle,
                    body: polished.body,
                    visualHeadline: subtitle,
                    visualDetail: name
                )
            )
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
