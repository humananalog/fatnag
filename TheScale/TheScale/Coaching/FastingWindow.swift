import Foundation

/// Intermittent fasting eating window (local clock). Default 16/8 is noon-8pm.
struct FastingWindow: Equatable, Sendable, Codable {
    /// Inclusive start of eating window (minutes from midnight).
    var eatingStartMinutes: Int
    /// Exclusive end of eating window (minutes from midnight).
    var eatingEndMinutes: Int
    /// Short fingerprint for meal-plan cache keys (e.g. `16-8@720-1200`).
    var cacheToken: String

    var eatingStartHour: Double { Double(eatingStartMinutes) / 60.0 }
    var eatingEndHour: Double { Double(eatingEndMinutes) / 60.0 }

    static let classic168 = FastingWindow(
        eatingStartMinutes: 12 * 60,
        eatingEndMinutes: 20 * 60,
        cacheToken: "16-8@720-1200"
    )

    static let none = FastingWindow(
        eatingStartMinutes: 0,
        eatingEndMinutes: 24 * 60,
        cacheToken: "none"
    )

    var isActive: Bool { cacheToken != "none" }

    func isFasting(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isActive else { return false }
        let mins = Self.minutesSinceMidnight(date, calendar: calendar)
        if eatingStartMinutes <= eatingEndMinutes {
            return mins < eatingStartMinutes || mins >= eatingEndMinutes
        }
        // Overnight window (rare): fasting is the gap.
        return mins >= eatingEndMinutes && mins < eatingStartMinutes
    }

    func allowsMeal(atHour hour: Double) -> Bool {
        guard isActive else { return true }
        let mins = Int((hour * 60).rounded())
        if eatingStartMinutes <= eatingEndMinutes {
            return mins >= eatingStartMinutes && mins < eatingEndMinutes
        }
        return mins >= eatingStartMinutes || mins < eatingEndMinutes
    }

    func firstMealHour(after now: Date, calendar: Calendar = .current) -> Double {
        guard isActive else {
            let h = calendar.component(.hour, from: now)
            let m = calendar.component(.minute, from: now)
            return Double(h) + Double(m) / 60.0
        }
        let mins = Self.minutesSinceMidnight(now, calendar: calendar)
        if mins < eatingStartMinutes {
            return eatingStartHour
        }
        if mins >= eatingEndMinutes {
            // Next day's open.
            return eatingStartHour
        }
        return Double(mins) / 60.0
    }

    static func minutesSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        return h * 60 + m
    }

    /// Detect IF from coach memory + free text. Defaults to classic 16/8 when IF is mentioned.
    static func detect(memoryBlock: String, extraHints: [String] = []) -> FastingWindow {
        let blob = ([memoryBlock] + extraHints).joined(separator: "\n").lowercased()
        guard blob.contains("intermittent fasting")
            || blob.contains("16/8")
            || blob.contains("16-8")
            || blob.contains("if 16")
            || (blob.contains("fasting") && (blob.contains("16") || blob.contains("eating window")))
        else {
            return .none
        }

        // Optional explicit window: "12-8", "12:00-20:00", "noon to 8"
        if let parsed = parseExplicitWindow(from: blob) {
            return parsed
        }
        return .classic168
    }

    private static func parseExplicitWindow(from lower: String) -> FastingWindow? {
        // Patterns like 12-8, 12:00-20:00, 11am-7pm
        let patterns = [
            #"(\d{1,2})(?::(\d{2}))?\s*(?:-|to)\s*(\d{1,2})(?::(\d{2}))?"#,
            #"(\d{1,2})\s*(am|pm)\s*(?:-|to)\s*(\d{1,2})\s*(am|pm)"#
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            guard let match = regex.firstMatch(in: lower, options: [], range: range) else { continue }
            if index == 0 {
                guard let sH = Int(substring(lower, match, 1)),
                      let eH = Int(substring(lower, match, 3))
                else { continue }
                let sM = Int(substring(lower, match, 2)) ?? 0
                let eM = Int(substring(lower, match, 4)) ?? 0
                var start = sH * 60 + sM
                var end = eH * 60 + eM
                // 12-8 without am/pm → treat as 12:00-20:00 when end < start in 12h sense
                if end <= start, eH <= 12 { end = (eH + 12) * 60 + eM }
                if end - start < 4 * 60 || end - start > 14 * 60 { continue }
                let token = "custom@\(start)-\(end)"
                return FastingWindow(eatingStartMinutes: start, eatingEndMinutes: end, cacheToken: token)
            } else {
                let sAP = substring(lower, match, 2).lowercased()
                let eAP = substring(lower, match, 4).lowercased()
                guard let sH = Int(substring(lower, match, 1)),
                      !sAP.isEmpty,
                      let eH = Int(substring(lower, match, 3)),
                      !eAP.isEmpty
                else { continue }
                let start = hour12(sH, sAP) * 60
                let end = hour12(eH, eAP) * 60
                guard end > start else { continue }
                return FastingWindow(
                    eatingStartMinutes: start,
                    eatingEndMinutes: end,
                    cacheToken: "custom@\(start)-\(end)"
                )
            }
        }
        return nil
    }

    private static func hour12(_ h: Int, _ ap: String) -> Int {
        var hour = h % 12
        if ap == "pm" { hour += 12 }
        return hour
    }

    private static func substring(_ text: String, _ match: NSTextCheckingResult, _ idx: Int) -> String {
        guard let range = Range(match.range(at: idx), in: text) else { return "" }
        return String(text[range])
    }
}

enum FastingWindowResolver {
    /// Prefer coach memory; always honour explicit 16/8 facts.
    static func current(memoryBlock: String? = nil) -> FastingWindow {
        let block = memoryBlock ?? CoachMemoryStore.promptBlock()
        return FastingWindow.detect(memoryBlock: block)
    }
}
