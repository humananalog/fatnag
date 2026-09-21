import Foundation
import UserNotifications

/// A one-shot local reminder the user asked Coach to schedule.
struct CoachReminderRequest: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case wakeUp
        case generic
    }

    let kind: Kind
    /// Absolute fire instant (device calendar / timezone).
    let fireAt: Date
    /// Optional deadline the user named (e.g. "before 7:30" → deadline 7:30, fire earlier).
    let beforeDeadline: Date?
    let title: String
    let body: String
}

struct CoachReminderResult: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case scheduled
        case denied
        case failed
    }

    let status: Status
    let request: CoachReminderRequest
    /// Short Coach bubble confirming the schedule (or permission failure).
    let coachNote: String
    /// Pending notification identifier when scheduled.
    let notificationId: String?
}

/// Row for Settings: pending Coach-scheduled local reminders.
struct PendingCoachReminder: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let nextFire: Date?
}

/// DEBUG-only reminder trace (no PII beyond fire clock; silent in Release).
enum CoachReminderLog {
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[CoachReminder] \(message())")
        #endif
    }
}

/// Parse Coach chat for wake / notification asks and schedule via `UNUserNotificationCenter`.
@MainActor
enum CoachReminderScheduler {
    static let notificationIdPrefix = "thescale.coach-reminder."
    /// Stable id for the latest Coach-scheduled wake ping (replaces prior wake reminder).
    static let wakeReminderId = "thescale.coach-reminder.wake"

    /// Request auth (shared with trend / fitness) then schedule a calendar / interval trigger.
    /// Algorithmic copy is scheduled first; Foundation Models polish is optional and never blocks delivery.
    static func schedule(
        _ request: CoachReminderRequest,
        profileName: String,
        now: Date = Date()
    ) async -> CoachReminderResult {
        let allowed = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
        guard allowed else {
            CoachReminderLog.debug("auth denied; not scheduling")
            return CoachReminderResult(
                status: .denied,
                request: request,
                coachNote: "Notifications are off for The Scale. Flip them on in iOS Settings → Notifications → The Scale, then ask me again.",
                notificationId: nil
            )
        }

        // Auth / polish delays must not leave a past fire date (iOS then never delivers).
        let fireAt = ensureFutureFireDate(request.fireAt, now: now)
        var liveRequest = CoachReminderRequest(
            kind: request.kind,
            fireAt: fireAt,
            beforeDeadline: request.beforeDeadline,
            title: request.title,
            body: request.body
        )

        let center = UNUserNotificationCenter.current()
        let name = profileName.isEmpty ? "Hey" : profileName
        let fallbackTitle = liveRequest.title.isEmpty ? "\(name): reminder" : liveRequest.title
        let fallbackBody = liveRequest.body.isEmpty
            ? "You asked Coach to ping you. Open The Scale when you're ready."
            : liveRequest.body

        let id = liveRequest.kind == .wakeUp
            ? wakeReminderId
            : notificationIdPrefix + UUID().uuidString

        let kind: ScaleNotificationKind = liveRequest.kind == .wakeUp ? .coachWake : .coachReminder
        let subtitle: String = {
            if liveRequest.kind == .wakeUp, let deadline = liveRequest.beforeDeadline {
                let t = DateFormatter.localizedString(
                    from: deadline,
                    dateStyle: .none,
                    timeStyle: .short
                )
                return "Before \(t)"
            }
            return fireAt.formatted(date: .omitted, time: .shortened)
        }()
        let content = ScaleNotificationContentFactory.make(
            .init(
                kind: kind,
                title: fallbackTitle,
                subtitle: subtitle,
                body: fallbackBody,
                visualHeadline: liveRequest.kind == .wakeUp ? "Wake" : "Reminder",
                visualDetail: subtitle
            )
        )

        let trigger = makeTrigger(for: fireAt, now: now)
        let unRequest = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            if liveRequest.kind == .wakeUp {
                center.removePendingNotificationRequests(withIdentifiers: [wakeReminderId])
            }
            try await center.add(unRequest)
            CoachReminderLog.debug(
                "scheduled id=\(id) fireAt=\(fireAt) tz=\(TimeZone.current.identifier)"
            )
            assert(
                fireAt > now.addingTimeInterval(-1),
                "Coach reminder fire date must be in the future"
            )

            let note = confirmationNote(for: liveRequest, profileName: name)

            // Optional polish after schedule. Never block confirmation or undo delivery.
            let polishRequest = liveRequest
            let polishTrigger = trigger
            Task {
                await polishPendingIfPossible(
                    id: id,
                    request: polishRequest,
                    profileName: name,
                    fallbackTitle: fallbackTitle,
                    fallbackBody: fallbackBody,
                    trigger: polishTrigger
                )
            }

            return CoachReminderResult(
                status: .scheduled,
                request: liveRequest,
                coachNote: note,
                notificationId: id
            )
        } catch {
            CoachReminderLog.debug("add failed: \(error.localizedDescription)")
            return CoachReminderResult(
                status: .failed,
                request: liveRequest,
                coachNote: "Tried to set the local notification and iOS bounced it. Ask me again in a minute.",
                notificationId: nil
            )
        }
    }

    /// Pending Coach reminders only (wake + generic prefix).
    static func listPendingCoachReminders() async -> [PendingCoachReminder] {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        return pending.compactMap { req -> PendingCoachReminder? in
            guard req.identifier == wakeReminderId
                || req.identifier.hasPrefix(notificationIdPrefix)
            else { return nil }
            let next: Date? = {
                if let cal = req.trigger as? UNCalendarNotificationTrigger {
                    return cal.nextTriggerDate()
                }
                if let interval = req.trigger as? UNTimeIntervalNotificationTrigger {
                    return interval.nextTriggerDate()
                }
                return nil
            }()
            return PendingCoachReminder(
                id: req.identifier,
                title: req.content.title,
                body: req.content.body,
                nextFire: next
            )
        }
        .sorted { ($0.nextFire ?? .distantFuture) < ($1.nextFire ?? .distantFuture) }
    }

    static func cancelCoachReminder(id: String) {
        guard id == wakeReminderId || id.hasPrefix(notificationIdPrefix) else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id])
        CoachReminderLog.debug("cancelled id=\(id)")
    }

    static func cancelAllCoachReminders() async {
        let ids = await listPendingCoachReminders().map(\.id)
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        CoachReminderLog.debug("cancelled all coach reminders count=\(ids.count)")
    }

    static func authorizationStatusLine() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let auth: String = {
            switch settings.authorizationStatus {
            case .authorized: return "allowed"
            case .provisional: return "provisional (quiet)"
            case .ephemeral: return "ephemeral"
            case .denied: return "denied · open system Settings"
            case .notDetermined: return "not asked yet"
            @unknown default: return "unknown"
            }
        }()
        let style: String = {
            switch settings.alertStyle {
            case .banner: return "banner"
            case .alert: return "alert"
            case .none: return "no banners"
            @unknown default: return "style?"
            }
        }()
        let sound = settings.soundSetting == .enabled ? "sound on" : "sound off"
        let badge = settings.badgeSetting == .enabled ? "badge on" : "badge off"
        let timeSensitive: String = {
            switch settings.timeSensitiveSetting {
            case .enabled: return "time-sensitive on"
            case .disabled: return "time-sensitive off"
            case .notSupported: return "time-sensitive n/a"
            @unknown default: return "time-sensitive?"
            }
        }()
        return "Notifications: \(auth) · \(style) · \(sound) · \(badge) · \(timeSensitive)"
    }

    /// If `fireAt` is already past, push forward so UNUserNotificationCenter can deliver.
    nonisolated static func ensureFutureFireDate(_ fireAt: Date, now: Date, calendar: Calendar = .current) -> Date {
        guard fireAt <= now else { return fireAt }
        let lag = now.timeIntervalSince(fireAt)
        // Near-term relative reminders that slipped: fire ~65s from now.
        if lag < 2 * 60 * 60 {
            return now.addingTimeInterval(65)
        }
        // Calendar morning / clock asks: roll forward day by day.
        var candidate = fireAt
        while candidate <= now {
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else {
                return now.addingTimeInterval(65)
            }
            candidate = next
        }
        return candidate
    }

    private static func makeTrigger(for fireAt: Date, now: Date) -> UNNotificationTrigger {
        let seconds = fireAt.timeIntervalSince(now)
        // Near-term (under 3h): interval trigger is more reliable than calendar comps around DST edges.
        if seconds > 0, seconds <= 3 * 60 * 60 {
            return UNTimeIntervalNotificationTrigger(
                timeInterval: max(seconds, 5),
                repeats: false
            )
        }
        let cal = Calendar.current
        let comps = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireAt
        )
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    private static func polishPendingIfPossible(
        id: String,
        request: CoachReminderRequest,
        profileName: String,
        fallbackTitle: String,
        fallbackBody: String,
        trigger: UNNotificationTrigger
    ) async {
        let polished = await FoundationModelCoach.refineNotificationCopy(
            profileName: profileName,
            kind: request.kind == .wakeUp ? "wake-reminder" : "coach-reminder",
            fallbackTitle: fallbackTitle,
            fallbackBody: fallbackBody,
            context: "Coach-scheduled local reminder at \(request.fireAt.formatted(date: .abbreviated, time: .shortened))"
        )
        guard polished.usedFoundationModel else { return }
        guard polished.title != fallbackTitle || polished.body != fallbackBody else { return }

        let kind: ScaleNotificationKind = request.kind == .wakeUp ? .coachWake : .coachReminder
        let subtitle: String = {
            if request.kind == .wakeUp, let deadline = request.beforeDeadline {
                let t = DateFormatter.localizedString(
                    from: deadline,
                    dateStyle: .none,
                    timeStyle: .short
                )
                return "Before \(t)"
            }
            return request.fireAt.formatted(date: .omitted, time: .shortened)
        }()
        let content = ScaleNotificationContentFactory.make(
            .init(
                kind: kind,
                title: polished.title,
                subtitle: subtitle,
                body: polished.body,
                visualHeadline: request.kind == .wakeUp ? "Wake" : "Reminder",
                visualDetail: subtitle
            )
        )
        let replacement = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(replacement)
            CoachReminderLog.debug("polished pending id=\(id)")
        } catch {
            CoachReminderLog.debug("polish replace failed (algorithmic copy kept): \(error.localizedDescription)")
        }
    }

    private static func confirmationNote(for request: CoachReminderRequest, profileName _: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let when = formatter.string(from: request.fireAt)
        switch request.kind {
        case .wakeUp:
            if let deadline = request.beforeDeadline {
                let deadlineText = DateFormatter.localizedString(
                    from: deadline,
                    dateStyle: .none,
                    timeStyle: .short
                )
                return "Local wake ping locked for \(when) (before \(deadlineText)). Phone on, notifications allowed; Focus/DND can still silence banners."
            }
            return "Local wake ping locked for \(when). Phone on, notifications allowed; Focus/DND can still silence banners."
        case .generic:
            return "Local notification locked for \(when) (\(TimeZone.current.identifier)). Focus/DND can still silence banners."
        }
    }
}

/// On-device parse of reminder / wake asks from Coach chat.
enum CoachReminderExtractor {
    /// Minutes before an explicit "before H:MM" deadline.
    static let beforeLeadMinutes = 15
    /// Default morning fire when user says "morning" with no clock.
    static let defaultMorningHour = 7
    static let defaultMorningMinute = 0

    static func extract(from userText: String, now: Date = Date(), calendar: Calendar = .current) -> CoachReminderRequest? {
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 6 else { return nil }
        let lower = text.lowercased()

        let wantsNotify =
            lower.contains("notif") || lower.contains("remind") || lower.contains("wake me")
            || lower.contains("wake up") || lower.contains("alarm") || lower.contains("ping me")
            || lower.contains("nudge me") || lower.contains("remind me")
        guard wantsNotify else { return nil }

        let isWake =
            lower.contains("wake") || lower.contains("get up") || lower.contains("get out of bed")
            || lower.contains("alarm")

        let kind: CoachReminderRequest.Kind = isWake ? .wakeUp : .generic
        let title = isWake ? "Wake up" : "Reminder"

        // Near-term relative: "in 2 minutes", "in 1 min", "in 1 hour"
        if let relativeFire = resolveRelativeFire(lower: lower, now: now) {
            return CoachReminderRequest(
                kind: kind,
                fireAt: relativeFire,
                beforeDeadline: nil,
                title: title,
                body: bodyCopy(isWake: isWake, beforeDeadline: nil)
            )
        }

        let dayOffset = resolveDayOffset(lower: lower)
        let time = resolveFireTime(lower: lower, text: text)

        var fireComps = calendar.dateComponents([.year, .month, .day], from: now)
        if let base = calendar.date(from: fireComps) {
            if let shifted = calendar.date(byAdding: .day, value: dayOffset, to: base) {
                fireComps = calendar.dateComponents([.year, .month, .day], from: shifted)
            }
        }
        fireComps.hour = time.hour
        fireComps.minute = time.minute
        fireComps.second = 0

        guard var fireAt = calendar.date(from: fireComps) else { return nil }

        // If resolved instant is already past (e.g. "morning" said late without tomorrow), push +1 day.
        if fireAt <= now {
            guard let bumped = calendar.date(byAdding: .day, value: 1, to: fireAt) else { return nil }
            fireAt = bumped
        }

        var beforeDeadline: Date?
        if let deadline = time.deadlineHourMinute {
            var deadlineComps = calendar.dateComponents([.year, .month, .day], from: fireAt)
            deadlineComps.hour = deadline.hour
            deadlineComps.minute = deadline.minute
            deadlineComps.second = 0
            beforeDeadline = calendar.date(from: deadlineComps)
        }

        return CoachReminderRequest(
            kind: kind,
            fireAt: fireAt,
            beforeDeadline: beforeDeadline,
            title: title,
            body: bodyCopy(isWake: isWake, beforeDeadline: beforeDeadline)
        )
    }

    private static func bodyCopy(isWake: Bool, beforeDeadline: Date?) -> String {
        if isWake {
            if let beforeDeadline {
                let t = DateFormatter.localizedString(
                    from: beforeDeadline,
                    dateStyle: .none,
                    timeStyle: .short
                )
                return "Up before \(t). Open The Scale when you're ready."
            }
            return "Time to get up. Open The Scale when you're ready."
        }
        return "You asked Coach to ping you. Open The Scale when you're ready."
    }

    private static func resolveDayOffset(lower: String) -> Int {
        if lower.contains("tomorrow") || lower.contains("tmrw") || lower.contains("tommorrow") {
            return 1
        }
        if lower.contains("today") {
            return 0
        }
        // Bare "morning" / time-only: same calendar day if still before fire, else extractor bumps.
        return 0
    }

    private struct ResolvedTime {
        let hour: Int
        let minute: Int
        /// When user said "before H:MM", the deadline clock.
        let deadlineHourMinute: (hour: Int, minute: Int)?
    }

    /// "in 2 minutes", "in 1 min", "in 90 seconds", "in 1 hour", "in 2 hrs"
    private static func resolveRelativeFire(lower: String, now: Date) -> Date? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\bin\s+(\d{1,3})\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)\b"#,
            options: []
        ) else { return nil }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        guard let match = regex.firstMatch(in: lower, options: [], range: range),
              match.numberOfRanges >= 3,
              let nRange = Range(match.range(at: 1), in: lower),
              let uRange = Range(match.range(at: 2), in: lower),
              let amount = Int(lower[nRange]),
              amount > 0
        else { return nil }

        let unit = String(lower[uRange])
        let seconds: TimeInterval
        if unit.hasPrefix("sec") {
            seconds = TimeInterval(amount)
        } else if unit.hasPrefix("min") {
            seconds = TimeInterval(amount * 60)
        } else {
            seconds = TimeInterval(amount * 3600)
        }
        // Clamp to a sane local-notification window (iOS interval max is large; keep UX tight).
        let clamped = min(max(seconds, 5), 24 * 3600)
        return now.addingTimeInterval(clamped)
    }

    private static func resolveFireTime(lower: String, text: String) -> ResolvedTime {
        let clock = parseClock(in: lower) ?? parseClock(in: text.lowercased()) ?? parseBareAtHour(in: lower)

        let isBefore = lower.contains("before") || lower.contains("by ")
        if let clock {
            if isBefore {
                // Fire leadMinutes before the named deadline.
                let total = clock.hour * 60 + clock.minute - beforeLeadMinutes
                let clamped = max(total, 0)
                return ResolvedTime(
                    hour: clamped / 60,
                    minute: clamped % 60,
                    deadlineHourMinute: (clock.hour, clock.minute)
                )
            }
            return ResolvedTime(hour: clock.hour, minute: clock.minute, deadlineHourMinute: nil)
        }

        if lower.contains("morning") {
            return ResolvedTime(
                hour: defaultMorningHour,
                minute: defaultMorningMinute,
                deadlineHourMinute: nil
            )
        }
        if lower.contains("afternoon") {
            return ResolvedTime(hour: 14, minute: 0, deadlineHourMinute: nil)
        }
        if lower.contains("evening") || lower.contains("tonight") {
            return ResolvedTime(hour: 19, minute: 0, deadlineHourMinute: nil)
        }
        // Fallback: soft default 8:00 local.
        return ResolvedTime(hour: 8, minute: 0, deadlineHourMinute: nil)
    }

    /// Parses `7:30`, `7.30`, `7am`, `07:30 am`, `8am`.
    private static func parseClock(in lower: String) -> (hour: Int, minute: Int)? {
        // H:MM with optional am/pm
        if let regex = try? NSRegularExpression(
            pattern: #"\b(\d{1,2})\s*[:.]\s*(\d{2})\s*(a\.?m\.?|p\.?m\.?)?\b"#,
            options: []
        ) {
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            if let match = regex.firstMatch(in: lower, options: [], range: range),
               match.numberOfRanges >= 3,
               let hRange = Range(match.range(at: 1), in: lower),
               let mRange = Range(match.range(at: 2), in: lower),
               var hour = Int(lower[hRange]),
               let minute = Int(lower[mRange]),
               minute >= 0, minute <= 59
            {
                var meridiem: String?
                if match.numberOfRanges > 3, let r = Range(match.range(at: 3), in: lower) {
                    let s = String(lower[r])
                    if !s.isEmpty { meridiem = s }
                }
                hour = applyMeridiem(hour: hour, meridiem: meridiem)
                if hour >= 0, hour <= 23 {
                    return (hour, minute)
                }
            }
        }

        // H am/pm without minutes
        if let regex = try? NSRegularExpression(
            pattern: #"\b(\d{1,2})\s*(a\.?m\.?|p\.?m\.?)\b"#,
            options: []
        ) {
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            if let match = regex.firstMatch(in: lower, options: [], range: range),
               match.numberOfRanges >= 3,
               let hRange = Range(match.range(at: 1), in: lower),
               let merRange = Range(match.range(at: 2), in: lower),
               var hour = Int(lower[hRange])
            {
                hour = applyMeridiem(hour: hour, meridiem: String(lower[merRange]))
                if hour >= 0, hour <= 23 {
                    return (hour, 0)
                }
            }
        }
        return nil
    }

    /// "at 8", "at 8 o'clock" (no am/pm). Hours 1-23 kept as-is; 24 invalid.
    private static func parseBareAtHour(in lower: String) -> (hour: Int, minute: Int)? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\bat\s+(\d{1,2})(?:\s*o['’]?clock)?\b"#,
            options: []
        ) else { return nil }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        guard let match = regex.firstMatch(in: lower, options: [], range: range),
              let hRange = Range(match.range(at: 1), in: lower),
              let hour = Int(lower[hRange]),
              hour >= 0, hour <= 23
        else { return nil }
        return (hour, 0)
    }

    private static func applyMeridiem(hour: Int, meridiem: String?) -> Int {
        guard let meridiem else { return hour }
        var h = hour
        if meridiem.contains("p"), h < 12 { h += 12 }
        if meridiem.contains("a"), h == 12 { h = 0 }
        return h
    }
}
