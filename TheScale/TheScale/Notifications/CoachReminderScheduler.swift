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
}

/// Parse Coach chat for wake / notification asks and schedule via `UNUserNotificationCenter`.
@MainActor
enum CoachReminderScheduler {
    static let notificationIdPrefix = "thescale.coach-reminder."
    /// Stable id for the latest Coach-scheduled wake ping (replaces prior wake reminder).
    static let wakeReminderId = "thescale.coach-reminder.wake"

    /// Request auth (shared with trend / fitness) then schedule a calendar trigger.
    static func schedule(
        _ request: CoachReminderRequest,
        profileName: String
    ) async -> CoachReminderResult {
        let allowed = await TrendNotificationScheduler.requestAuthorizationIfNeeded()
        guard allowed else {
            return CoachReminderResult(
                status: .denied,
                request: request,
                coachNote: "Notifications are off for The Scale. Flip them on in iOS Settings → Notifications → The Scale, then ask me again."
            )
        }

        let center = UNUserNotificationCenter.current()
        let name = profileName.isEmpty ? "Hey" : profileName
        let fallbackTitle = request.title.isEmpty ? "\(name): reminder" : request.title
        let polished = await FoundationModelCoach.refineNotificationCopy(
            profileName: name,
            kind: request.kind == .wakeUp ? "wake-reminder" : "coach-reminder",
            fallbackTitle: fallbackTitle,
            fallbackBody: request.body,
            context: "Coach-scheduled local reminder at \(request.fireAt.formatted(date: .abbreviated, time: .shortened))"
        )
        let content = UNMutableNotificationContent()
        content.title = polished.title
        content.body = polished.body
        content.sound = .default

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: request.fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = request.kind == .wakeUp ? wakeReminderId : notificationIdPrefix + UUID().uuidString
        let unRequest = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        let polishedRequest = CoachReminderRequest(
            kind: request.kind,
            fireAt: request.fireAt,
            beforeDeadline: request.beforeDeadline,
            title: polished.title,
            body: polished.body
        )

        do {
            if request.kind == .wakeUp {
                center.removePendingNotificationRequests(withIdentifiers: [wakeReminderId])
            }
            try await center.add(unRequest)
            let note = confirmationNote(for: polishedRequest, profileName: name)
            return CoachReminderResult(status: .scheduled, request: polishedRequest, coachNote: note)
        } catch {
            return CoachReminderResult(
                status: .failed,
                request: request,
                coachNote: "Tried to set the local notification and iOS bounced it. Ask me again in a minute."
            )
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
                let deadlineText = DateFormatter.localizedString(from: deadline, dateStyle: .none, timeStyle: .short)
                return "Local wake ping locked for \(when) (before \(deadlineText)). Phone needs to be on and notifications allowed."
            }
            return "Local wake ping locked for \(when). Phone needs to be on and notifications allowed."
        case .generic:
            return "Local notification locked for \(when)."
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
            || lower.contains("nudge me")
        guard wantsNotify else { return nil }

        let isWake =
            lower.contains("wake") || lower.contains("get up") || lower.contains("get out of bed")
            || lower.contains("alarm")

        let dayOffset = resolveDayOffset(lower: lower, now: now, calendar: calendar)
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

        let kind: CoachReminderRequest.Kind = isWake ? .wakeUp : .generic
        let title = isWake ? "Wake up" : "Reminder"
        let body: String = {
            if isWake {
                if let beforeDeadline {
                    let t = DateFormatter.localizedString(from: beforeDeadline, dateStyle: .none, timeStyle: .short)
                    return "Up before \(t). Open The Scale when you're ready."
                }
                return "Time to get up. Open The Scale when you're ready."
            }
            return "You asked Coach to ping you. Open The Scale when you're ready."
        }()

        return CoachReminderRequest(
            kind: kind,
            fireAt: fireAt,
            beforeDeadline: beforeDeadline,
            title: title,
            body: body
        )
    }

    private static func resolveDayOffset(lower: String, now: Date, calendar: Calendar) -> Int {
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

    private static func resolveFireTime(lower: String, text: String) -> ResolvedTime {
        let clock = parseClock(in: lower) ?? parseClock(in: text.lowercased())

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
        // Fallback: one hour from "now" is handled by caller via day bump; use 8:00 as soft default.
        return ResolvedTime(hour: 8, minute: 0, deadlineHourMinute: nil)
    }

    /// Parses `7:30`, `7.30`, `7am`, `07:30 am`.
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

    private static func applyMeridiem(hour: Int, meridiem: String?) -> Int {
        guard let meridiem else { return hour }
        var h = hour
        if meridiem.contains("p"), h < 12 { h += 12 }
        if meridiem.contains("a"), h == 12 { h = 0 }
        return h
    }
}

