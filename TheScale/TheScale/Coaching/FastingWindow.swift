import Foundation

/// Intermittent fasting eating window (local clock).
///
/// Classic **16-8** means 16 hours fasting + an **8-hour eating window**
/// (default noon-8pm: `eatingWindowStart` 12:00, `eatingWindowEnd` 20:00).
/// Protocol labels like `16-8` / `16/8` are never parsed as clock times.
struct FastingWindow: Equatable, Sendable, Codable {
    /// Inclusive start of eating window (minutes from midnight). Alias: eatingWindowStart.
    var eatingWindowStartMinutes: Int
    /// Exclusive end of eating window (minutes from midnight). Alias: eatingWindowEnd.
    var eatingWindowEndMinutes: Int
    /// Short fingerprint for meal-plan cache keys (e.g. `16-8@720-1200`).
    var cacheToken: String
    /// Protocol label when known (`16-8`, `18-6`, `20-4`, `custom`).
    var protocolLabel: String
    /// Fasting hours implied by the protocol (e.g. 16 for 16-8).
    var fastingHours: Int

    /// Preferred name for callers / docs.
    var eatingWindowStart: Int { eatingWindowStartMinutes }
    var eatingWindowEnd: Int { eatingWindowEndMinutes }

    var eatingStartHour: Double { Double(eatingWindowStartMinutes) / 60.0 }
    var eatingEndHour: Double { Double(eatingWindowEndMinutes) / 60.0 }

    /// Codable aliases for older fields (`eatingStartMinutes` / `eatingEndMinutes`).
    var eatingStartMinutes: Int {
        get { eatingWindowStartMinutes }
        set { eatingWindowStartMinutes = newValue }
    }

    var eatingEndMinutes: Int {
        get { eatingWindowEndMinutes }
        set { eatingWindowEndMinutes = newValue }
    }

    static let classic168 = FastingWindow(
        eatingWindowStartMinutes: 12 * 60,
        eatingWindowEndMinutes: 20 * 60,
        cacheToken: "16-8@720-1200",
        protocolLabel: "16-8",
        fastingHours: 16
    )

    static let classic186 = FastingWindow(
        eatingWindowStartMinutes: 13 * 60,
        eatingWindowEndMinutes: 19 * 60,
        cacheToken: "18-6@780-1140",
        protocolLabel: "18-6",
        fastingHours: 18
    )

    static let classic204 = FastingWindow(
        eatingWindowStartMinutes: 14 * 60,
        eatingWindowEndMinutes: 18 * 60,
        cacheToken: "20-4@840-1080",
        protocolLabel: "20-4",
        fastingHours: 20
    )

    static let none = FastingWindow(
        eatingWindowStartMinutes: 0,
        eatingWindowEndMinutes: 24 * 60,
        cacheToken: "none",
        protocolLabel: "none",
        fastingHours: 0
    )

    var isActive: Bool { cacheToken != "none" && protocolLabel != "none" }

    /// Eating window length in hours (handles overnight windows).
    var eatingHours: Double {
        guard isActive else { return 24 }
        if eatingWindowEndMinutes >= eatingWindowStartMinutes {
            return Double(eatingWindowEndMinutes - eatingWindowStartMinutes) / 60.0
        }
        return Double(24 * 60 - eatingWindowStartMinutes + eatingWindowEndMinutes) / 60.0
    }

    init(
        eatingWindowStartMinutes: Int,
        eatingWindowEndMinutes: Int,
        cacheToken: String,
        protocolLabel: String = "custom",
        fastingHours: Int = 0
    ) {
        self.eatingWindowStartMinutes = eatingWindowStartMinutes
        self.eatingWindowEndMinutes = eatingWindowEndMinutes
        self.cacheToken = cacheToken
        self.protocolLabel = protocolLabel
        self.fastingHours = fastingHours > 0
            ? fastingHours
            : max(0, 24 - Int(((Double(eatingWindowEndMinutes - eatingWindowStartMinutes) / 60.0).rounded())))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let start = try c.decodeIfPresent(Int.self, forKey: .eatingWindowStartMinutes)
            ?? c.decodeIfPresent(Int.self, forKey: .eatingStartMinutes)
            ?? 0
        let end = try c.decodeIfPresent(Int.self, forKey: .eatingWindowEndMinutes)
            ?? c.decodeIfPresent(Int.self, forKey: .eatingEndMinutes)
            ?? 24 * 60
        eatingWindowStartMinutes = start
        eatingWindowEndMinutes = end
        cacheToken = try c.decodeIfPresent(String.self, forKey: .cacheToken) ?? "custom@\(start)-\(end)"
        protocolLabel = try c.decodeIfPresent(String.self, forKey: .protocolLabel) ?? "custom"
        fastingHours = try c.decodeIfPresent(Int.self, forKey: .fastingHours) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(eatingWindowStartMinutes, forKey: .eatingWindowStartMinutes)
        try c.encode(eatingWindowEndMinutes, forKey: .eatingWindowEndMinutes)
        // Keep legacy keys so older builds can still read a saved window.
        try c.encode(eatingWindowStartMinutes, forKey: .eatingStartMinutes)
        try c.encode(eatingWindowEndMinutes, forKey: .eatingEndMinutes)
        try c.encode(cacheToken, forKey: .cacheToken)
        try c.encode(protocolLabel, forKey: .protocolLabel)
        try c.encode(fastingHours, forKey: .fastingHours)
    }

    private enum CodingKeys: String, CodingKey {
        case eatingWindowStartMinutes, eatingWindowEndMinutes
        case eatingStartMinutes, eatingEndMinutes
        case cacheToken, protocolLabel, fastingHours
    }

    func isFasting(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isActive else { return false }
        let mins = Self.minutesSinceMidnight(date, calendar: calendar)
        if eatingWindowStartMinutes <= eatingWindowEndMinutes {
            return mins < eatingWindowStartMinutes || mins >= eatingWindowEndMinutes
        }
        // Overnight window: fasting is the gap.
        return mins >= eatingWindowEndMinutes && mins < eatingWindowStartMinutes
    }

    func allowsMeal(atHour hour: Double) -> Bool {
        guard isActive else { return true }
        let mins = Int((hour * 60).rounded())
        if eatingWindowStartMinutes <= eatingWindowEndMinutes {
            return mins >= eatingWindowStartMinutes && mins < eatingWindowEndMinutes
        }
        return mins >= eatingWindowStartMinutes || mins < eatingWindowEndMinutes
    }

    func firstMealHour(after now: Date, calendar: Calendar = .current) -> Double {
        guard isActive else {
            let h = calendar.component(.hour, from: now)
            let m = calendar.component(.minute, from: now)
            return Double(h) + Double(m) / 60.0
        }
        let mins = Self.minutesSinceMidnight(now, calendar: calendar)
        if mins < eatingWindowStartMinutes {
            return eatingStartHour
        }
        if mins >= eatingWindowEndMinutes {
            return eatingStartHour
        }
        return Double(mins) / 60.0
    }

    static func minutesSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        return h * 60 + m
    }

    /// Build a window from explicit start/end minutes + optional protocol label.
    static func make(
        startMinutes: Int,
        endMinutes: Int,
        protocolLabel: String = "custom",
        fastingHours: Int? = nil
    ) -> FastingWindow {
        let start = max(0, min(24 * 60 - 1, startMinutes))
        var end = max(0, min(24 * 60, endMinutes))
        if end <= start { end = min(24 * 60, start + 8 * 60) }
        let eatingH = max(1, Int(((Double(end - start) / 60.0).rounded())))
        let fasting = fastingHours ?? max(0, 24 - eatingH)
        let label = protocolLabel.isEmpty ? "custom" : protocolLabel
        let token = "\(label)@\(start)-\(end)"
        return FastingWindow(
            eatingWindowStartMinutes: start,
            eatingWindowEndMinutes: end,
            cacheToken: token,
            protocolLabel: label,
            fastingHours: fasting
        )
    }

    /// Detect IF from coach memory + free text. Defaults to classic 16/8 when IF is mentioned.
    static func detect(memoryBlock: String, extraHints: [String] = []) -> FastingWindow {
        let blob = ([memoryBlock] + extraHints).joined(separator: "\n").lowercased()
        guard mentionsIntermittentFasting(blob) else {
            return .none
        }

        // Protocol ratios first so "16-8" is never treated as 16:00-08:00.
        if let protocolWindow = parseProtocol(from: blob) {
            // Explicit clock window can override default open/close for that protocol.
            if let explicit = parseExplicitClockWindow(from: blob) {
                return make(
                    startMinutes: explicit.start,
                    endMinutes: explicit.end,
                    protocolLabel: protocolWindow.protocolLabel,
                    fastingHours: protocolWindow.fastingHours
                )
            }
            return protocolWindow
        }

        if let explicit = parseExplicitClockWindow(from: blob) {
            return make(startMinutes: explicit.start, endMinutes: explicit.end, protocolLabel: "custom")
        }

        return .classic168
    }

    static func mentionsIntermittentFasting(_ lower: String) -> Bool {
        lower.contains("intermittent fasting")
            || lower.contains("16/8")
            || lower.contains("16-8")
            || lower.contains("18/6")
            || lower.contains("18-6")
            || lower.contains("20/4")
            || lower.contains("20-4")
            || lower.contains("if 16")
            || lower.contains("omad")
            || (lower.contains("fasting") && (lower.contains("16") || lower.contains("eating window")))
            || (lower.range(of: #"\bif\b"#, options: .regularExpression) != nil
                && (lower.contains("fast") || lower.contains("16") || lower.contains("window")))
    }

    /// Parse protocol labels (`16-8`, `16/8`, `18:6`, OMAD) into a default window.
    static func parseProtocol(from lower: String) -> FastingWindow? {
        if lower.contains("omad") || lower.contains("one meal a day") {
            return make(
                startMinutes: 17 * 60,
                endMinutes: 19 * 60,
                protocolLabel: "omad",
                fastingHours: 22
            )
        }
        let pattern = #"\b(14|16|18|20)\s*[/\-:`]\s*(4|6|8|10)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              match.numberOfRanges > 2,
              let fRange = Range(match.range(at: 1), in: lower),
              let eRange = Range(match.range(at: 2), in: lower),
              let fasting = Int(lower[fRange]),
              let eating = Int(lower[eRange]),
              fasting + eating == 24
        else { return nil }

        let label = "\(fasting)-\(eating)"
        switch (fasting, eating) {
        case (16, 8): return .classic168
        case (18, 6): return .classic186
        case (20, 4): return .classic204
        case (14, 10):
            return make(
                startMinutes: 10 * 60,
                endMinutes: 20 * 60,
                protocolLabel: label,
                fastingHours: 14
            )
        default:
            // Centre an eating window of `eating` hours ending at 20:00 by default.
            let end = 20 * 60
            let start = end - eating * 60
            return make(
                startMinutes: max(0, start),
                endMinutes: end,
                protocolLabel: label,
                fastingHours: fasting
            )
        }
    }

    /// Clock windows only: `12-8`, `12:00-20:00`, `noon to 8`, `11am-7pm`.
    /// Never matches protocol ratios like `16-8`.
    private static func parseExplicitClockWindow(from lower: String) -> (start: Int, end: Int)? {
        // noon / midday → 12:00, midnight → 0
        let normalized = lower
            .replacingOccurrences(of: "noon", with: "12:00")
            .replacingOccurrences(of: "midday", with: "12:00")
            .replacingOccurrences(of: "midnight", with: "0:00")

        let ampmPattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s*(?:-|to|until)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)"#
        if let regex = try? NSRegularExpression(pattern: ampmPattern),
           let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
            let sH = Int(substring(normalized, match, 1)) ?? -1
            let sM = Int(substring(normalized, match, 2)) ?? 0
            let sAP = substring(normalized, match, 3).lowercased()
            let eH = Int(substring(normalized, match, 4)) ?? -1
            let eM = Int(substring(normalized, match, 5)) ?? 0
            let eAP = substring(normalized, match, 6).lowercased()
            guard sH >= 0, eH >= 0, !sAP.isEmpty, !eAP.isEmpty else { return nil }
            let start = hour12(sH, sAP) * 60 + sM
            let end = hour12(eH, eAP) * 60 + eM
            guard end > start, end - start >= 4 * 60, end - start <= 14 * 60 else { return nil }
            return (start, end)
        }

        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(?:-|to|until)\s*(\d{1,2})(?::(\d{2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = regex.matches(in: normalized, options: [], range: range)
        for match in matches {
            guard let sH = Int(substring(normalized, match, 1)),
                  let eH = Int(substring(normalized, match, 3))
            else { continue }
            let sMRaw = substring(normalized, match, 2)
            let eMRaw = substring(normalized, match, 4)
            let sM = Int(sMRaw) ?? 0
            let eM = Int(eMRaw) ?? 0
            let hadMinutes = !sMRaw.isEmpty || !eMRaw.isEmpty

            // Skip IF protocol ratios (16-8, 18-6, …) that are not clock times.
            if looksLikeProtocolRatio(startHour: sH, endHour: eH, hadMinutes: hadMinutes) {
                continue
            }

            let start = sH * 60 + sM
            var end = eH * 60 + eM
            // 12-8 without am/pm → treat as 12:00-20:00 when end looks like a 12h clock close.
            if end <= start, eH <= 12 {
                end = (eH + 12) * 60 + eM
            }
            // 12-20 already 24h form
            if end - start < 4 * 60 || end - start > 14 * 60 { continue }
            // Prefer eating windows that start in the late morning / afternoon (IF-like).
            if start < 6 * 60 { continue }
            return (start, end)
        }
        return nil
    }

    /// `16-8` style: large first number (fasting) + small second (eating), no minutes.
    private static func looksLikeProtocolRatio(startHour: Int, endHour: Int, hadMinutes: Bool) -> Bool {
        if hadMinutes { return false }
        let fastingish = (14...22).contains(startHour)
        let eatingish = (4...10).contains(endHour)
        return fastingish && eatingish && (startHour + endHour == 24 || startHour > endHour)
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
    /// Prefer structured profile prefs; fall back to coach memory + free-text hints.
    static func current(
        profile: UserBodyProfile? = nil,
        memoryBlock: String? = nil,
        extraHints: [String] = []
    ) -> FastingWindow {
        if let stored = profile?.intermittentFasting, stored.isActive {
            return stored
        }
        let block = memoryBlock ?? CoachMemoryStore.promptBlock()
        var hints = extraHints
        if let vibe = profile?.culturalVibe, !vibe.isEmpty {
            hints.append(vibe)
        }
        return FastingWindow.detect(memoryBlock: block, extraHints: hints)
    }
}
