import Foundation

/// Dual presentation for mirrored iPhone + Apple Watch alerts.
/// Watch reads `title` / `subtitle` only; iPhone gets body + attachment chrome.
enum ScaleNotificationCopy {
    /// Canonical moment → factory draft with Watch-safe glance fields.
    struct Moment: Sendable {
        var kind: ScaleNotificationKind
        /// Wrist / Lock Screen primary line. Verb or metric first. No emoji. ≤20.
        var glanceTitle: String
        /// One fact under the title. ≤36.
        var glanceLine: String
        /// Expanded iPhone Notification Center / long-look body. Name + personality OK.
        var phoneBody: String
        var visualHeadline: String?
        var visualDetail: String?
        var relevanceScore: Double?

        func asDraft() -> ScaleNotificationContentFactory.Draft {
            ScaleNotificationContentFactory.Draft(
                kind: kind,
                title: glanceTitle,
                subtitle: glanceLine,
                body: phoneBody,
                visualHeadline: visualHeadline ?? glanceTitle,
                visualDetail: visualDetail ?? glanceLine,
                relevanceScore: relevanceScore
            )
        }
    }

    // MARK: - Moments

    static func morningWeigh(profileName: String) -> Moment {
        let who = greet(profileName, anonymous: "Soldier")
        return Moment(
            kind: .morningWeigh,
            glanceTitle: "Weigh now",
            glanceLine: "Empty bladder · scale",
            phoneBody: "\(who). Drop a load, step on the scale, then open fatnag. Morning mass locks the week.",
            visualHeadline: "Weigh now",
            visualDetail: "Morning drill",
            relevanceScore: 1.0
        )
    }

    static func coachWake(profileName: String, beforeDeadline: Date?) -> Moment {
        let who = greet(profileName, anonymous: "Hey")
        let line: String = {
            guard let beforeDeadline else { return "Time to get up" }
            let t = DateFormatter.localizedString(
                from: beforeDeadline,
                dateStyle: .none,
                timeStyle: .short
            )
            return "Before \(t)"
        }()
        return Moment(
            kind: .coachWake,
            glanceTitle: "Wake up",
            glanceLine: line,
            phoneBody: "\(who). \(line). Open fatnag when you're ready.",
            visualHeadline: "Wake",
            visualDetail: line,
            relevanceScore: 1.0
        )
    }

    static func coachReminder(profileName: String, fireAt: Date) -> Moment {
        let who = greet(profileName, anonymous: "Hey")
        let when = fireAt.formatted(date: .omitted, time: .shortened)
        return Moment(
            kind: .coachReminder,
            glanceTitle: "Coach ping",
            glanceLine: when,
            phoneBody: "\(who). You asked Coach to ping you. Open fatnag when you're ready.",
            visualHeadline: "Reminder",
            visualDetail: when,
            relevanceScore: 0.8
        )
    }

    static func weightSpikeKick(
        profileName: String,
        headline: String,
        body: String
    ) -> Moment {
        let who = greet(profileName, anonymous: "Hey")
        return Moment(
            kind: .weightSpike,
            glanceTitle: "Red card",
            glanceLine: clamp(headline, max: 36),
            phoneBody: clamp("\(who). \(body)", max: 140),
            visualHeadline: "Red card",
            visualDetail: clamp(headline, max: 40),
            relevanceScore: 1.0
        )
    }

    static func badTrend(
        profileName: String,
        currentKg: Double?,
        idealKg: Double,
        reason: String,
        system: PreferredUnitSystem = PreferredUnitSystemStore.load()
    ) -> Moment {
        let who = greet(profileName, anonymous: "Hey")
        let kgBit = currentKg.map {
            UnitFormat.massString($0, system: system, fractionDigits: 1)
        } ?? "Scale"
        let deltaBit: String = {
            guard let currentKg else { return "Above pace" }
            let gap = currentKg - idealKg
            if gap > 0.05 {
                return UnitFormat.massDeltaString(gap, system: system) + " vs goal"
            }
            return "Above pace"
        }()
        return Moment(
            kind: .badTrend,
            glanceTitle: kgBit,
            glanceLine: deltaBit,
            phoneBody: "\(who). \(clamp(reason, max: 120)) Open Charts when you can.",
            visualHeadline: kgBit,
            visualDetail: "Ideal \(UnitFormat.massString(idealKg, system: system, fractionDigits: 1))",
            relevanceScore: 0.9
        )
    }

    static func weeklyGoal(
        profileName: String,
        weeklyGoal: WeeklyMiniGoal,
        system: PreferredUnitSystem = PreferredUnitSystemStore.load()
    ) -> Moment {
        let who = greet(profileName, anonymous: "Hey")
        let delta = UnitFormat.massDeltaString(weeklyGoal.targetDeltaKg, system: system)
        return Moment(
            kind: .weeklyGoal,
            glanceTitle: "Goal \(delta)",
            glanceLine: "Monday plan",
            phoneBody: "\(who). This week's plan is \(delta). Open Progress and lock the week.",
            visualHeadline: delta,
            visualDetail: "Monday mini-goal",
            relevanceScore: 0.55
        )
    }

    static func fitnessInterval(profileName: String, intervalTitle: String) -> Moment {
        let who = greet(profileName, anonymous: "Hey")
        return Moment(
            kind: .fitnessInterval,
            glanceTitle: "Coach check",
            glanceLine: intervalTitle,
            phoneBody: "\(who). Background Health check is ready. Open Coach for the full read.",
            visualHeadline: "Check-in",
            visualDetail: intervalTitle,
            relevanceScore: 0.3
        )
    }

    static func watchWear(profileName: String, algorithmicMessage: String) -> Moment {
        let who = greet(profileName, anonymous: "Hey")
        return Moment(
            kind: .watchWear,
            glanceTitle: "Watch off",
            glanceLine: "No HR today",
            phoneBody: "\(who). \(clamp(algorithmicMessage, max: 120))",
            visualHeadline: "Watch",
            visualDetail: "Wear signal",
            relevanceScore: 0.85
        )
    }

    static func preSleepHR(
        profileName: String,
        elevated: Bool,
        algorithmicMessage: String
    ) -> Moment {
        let who = greet(profileName, anonymous: "Hey")
        return Moment(
            kind: .preSleepHR,
            glanceTitle: elevated ? "HR high" : "HR missing",
            glanceLine: "Pre-sleep",
            phoneBody: "\(who). \(clamp(algorithmicMessage, max: 120))",
            visualHeadline: elevated ? "HR high" : "HR missing",
            visualDetail: "Pre-sleep",
            relevanceScore: 0.88
        )
    }

    /// After heavy background analysis: short wrist line + iPhone story.
    static func keyCoachMoment(profileName: String, summary: String) -> Moment {
        let who = greet(profileName, anonymous: "Hey")
        let glance = firstGlancePhrase(from: summary) ?? "Coach read"
        let body = clamp("\(who). \(summary)", max: 140)
        return Moment(
            kind: .coachReminder,
            glanceTitle: glance,
            glanceLine: "Key moment",
            phoneBody: body,
            visualHeadline: glance,
            visualDetail: "Background read",
            relevanceScore: 0.82
        )
    }

    static func sample(profileName: String, currentKg: Double?, system: PreferredUnitSystem) -> Moment {
        let who = greet(profileName, anonymous: "Hey")
        let kgLine = currentKg.map {
            UnitFormat.massString($0, system: system, fractionDigits: 1)
        } ?? "No mass"
        return Moment(
            kind: .sample,
            glanceTitle: "Sample ping",
            glanceLine: kgLine,
            phoneBody: "\(who). SOTA banner with Coach chrome and actions. Tap Open Coach.",
            visualHeadline: kgLine,
            visualDetail: "Sample · fatnag",
            relevanceScore: 0.95
        )
    }

    // MARK: - Sanitize / helpers

    /// Force Watch-safe title: strip emoji, "Name:" prefixes, length.
    static func glanceSanitize(_ raw: String, max: Int = 20) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.unicodeScalars.filter { scalar in
            let v = scalar.value
            // Drop emoji / pictographs; keep basic punctuation & letters.
            if (0x1F300...0x1FAFF).contains(v) { return false }
            if (0x2600...0x27BF).contains(v) { return false }
            if v == 0xFE0F || v == 0x200D { return false }
            return true
        }.map(String.init).joined()
        text = text.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop "Alex: " / "Hey: " style prefixes that waste wrist space.
        if let colon = text.firstIndex(of: ":") {
            let head = text[..<colon]
            if head.count <= 14, !head.contains(where: \.isNumber) {
                let rest = text[text.index(after: colon)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !rest.isEmpty { text = String(rest) }
            }
        }
        return clamp(text, max: max)
    }

    static func greet(_ profileName: String, anonymous: String) -> String {
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? anonymous : name
    }

    static func clamp(_ text: String, max: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: max - 1)
        return String(trimmed[..<idx]) + "…"
    }

    /// Pull a short metric/verb phrase from analysis for the wrist.
    static func firstGlancePhrase(from summary: String) -> String? {
        let cleaned = summary
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        // Prefer leading signed mass like "+0.6 kg" / "−650g".
        if let regex = try? NSRegularExpression(
            pattern: #"([+\-−]?\d+(?:\.\d+)?\s?(?:kg|lb|g))"#,
            options: [.caseInsensitive]
        ),
           let match = regex.firstMatch(
            in: cleaned,
            range: NSRange(cleaned.startIndex..., in: cleaned)
           ),
           let range = Range(match.range(at: 1), in: cleaned) {
            return glanceSanitize(String(cleaned[range]), max: 16)
        }
        let first = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? cleaned
        return glanceSanitize(first, max: 18)
    }
}
