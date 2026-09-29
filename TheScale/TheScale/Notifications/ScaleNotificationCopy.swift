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
        /// Overrides `kind.destination` when the same kind opens different pages.
        var destination: ScaleNotificationDestination?

        func asDraft() -> ScaleNotificationContentFactory.Draft {
            var extras: [String: String] = [:]
            if let destination {
                extras[ScaleNotificationUserInfoKey.destination] = destination.rawValue
            }
            return ScaleNotificationContentFactory.Draft(
                kind: kind,
                title: glanceTitle,
                subtitle: glanceLine,
                body: phoneBody,
                visualHeadline: visualHeadline ?? glanceTitle,
                visualDetail: visualDetail ?? glanceLine,
                userInfoExtras: extras,
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

    static func activityPulse(_ pulse: ActivityPulse, profileName: String) -> Moment {
        let who = greet(profileName, anonymous: "Hey")
        let beat = glanceSanitize(pulse.glanceTitle, max: 20)
        return Moment(
            kind: .nag,
            glanceTitle: "Nag",
            glanceLine: beat,
            phoneBody: clamp("\(who). \(pulse.phoneBody)", max: 150),
            visualHeadline: "Nag",
            visualDetail: beat,
            relevanceScore: pulse.isStrong ? 0.9 : 0.72,
            destination: destination(for: pulse)
        )
    }

    /// Nag tones land on the page that matches the beat.
    static func destination(for pulse: ActivityPulse) -> ScaleNotificationDestination {
        switch pulse.tone {
        case .greeting:
            return .weigh
        case .punishment:
            return .progress
        case .reward:
            return pulse.id.hasPrefix("workout") ? .meals : .progress
        case .joke, .humor:
            return .coach
        }
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

enum ActivityPulseTone: String, Equatable, Sendable {
    case greeting
    case reward
    case joke
    case humor
    case punishment
}

struct ActivityPulse: Equatable, Sendable {
    var id: String
    var tone: ActivityPulseTone
    /// Milestones and sleep/workout beats can land sooner than a joke.
    var isStrong: Bool
    var glanceTitle: String
    var glanceLine: String
    var phoneBody: String
}

/// Turns a HealthKit digest into one coaching line. Empty Health stays quiet.
enum ActivityPulseAnalyzer {
    static let jokeGap: TimeInterval = 40 * 60
    static let strongGap: TimeInterval = 8 * 60

    static func evaluate(
        digest: FitnessDigest,
        profileName: String,
        sex: UserBodyProfile.Sex = .male,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ActivityPulse? {
        guard digest.hasAnyFitnessSignal else { return nil }
        let day = dayKey(now, calendar: calendar)
        let hour = calendar.component(.hour, from: now)
        let who = ScaleNotificationCopy.greet(profileName, anonymous: sex == .female ? "Hey" : "Recruit")

        if (5...11).contains(hour), let sleep = digest.sleepHoursLastNight, sleep > 0 {
            return sleepPulse(hours: sleep, day: day, who: who, sex: sex)
        }

        if let workout = digest.lastWorkout,
           calendar.isDate(workout.endDate, inSameDayAs: now),
           now.timeIntervalSince(workout.endDate) < 8 * 3600 {
            let minutes = Int(workout.durationMinutes.rounded())
            return ActivityPulse(
                id: "workout-\(day)-\(Int(workout.startDate.timeIntervalSince1970 / 60))",
                tone: .reward,
                isStrong: true,
                glanceTitle: "Workout banked",
                glanceLine: "\(minutes) min \(workout.activityName)",
                phoneBody: "\(workout.activityName), \(minutes) min. That's a reward. Eat like you want to keep it, not like you earned a bakery."
            )
        }

        if let steps = digest.stepsToday, steps >= 0 {
            let count = Int(steps.rounded())
            if let bucket = stepBucket(count) {
                return ActivityPulse(
                    id: "steps-\(day)-\(bucket)",
                    tone: .reward,
                    isStrong: true,
                    glanceTitle: "\(formatted(count)) steps",
                    glanceLine: "Milestone",
                    phoneBody: stepRewardBody(count: count, bucket: bucket, who: who, sex: sex)
                )
            }
            if hour >= 18, count < 2_500 {
                return ActivityPulse(
                    id: "steps-low-\(day)",
                    tone: .punishment,
                    isStrong: true,
                    glanceTitle: "Steps are soft",
                    glanceLine: "\(formatted(count)) today",
                    phoneBody: punishmentSteps(count: count, sex: sex)
                )
            }
            if (11...20).contains(hour), count >= 1_200 {
                let slot = hour / 2
                return ActivityPulse(
                    id: "joke-\(day)-\(slot)",
                    tone: slot.isMultiple(of: 2) ? .joke : .humor,
                    isStrong: false,
                    glanceTitle: "Still moving",
                    glanceLine: "\(formatted(count)) steps",
                    phoneBody: jokeLine(slot: slot, steps: count, sex: sex)
                )
            }
        }

        if (6...10).contains(hour) {
            return ActivityPulse(
                id: "greet-\(day)",
                tone: .greeting,
                isStrong: false,
                glanceTitle: "Morning",
                glanceLine: "You're up",
                phoneBody: sex == .female
                    ? "Good morning. Water, a weigh-in, then the day. I'll bring the jokes once the steps show up."
                    : "Morning. Weigh in, then walk. Jokes unlock after the steps do."
            )
        }
        return nil
    }

    static func shouldDeliver(
        pulse: ActivityPulse,
        lastId: String?,
        lastAt: Date?,
        now: Date
    ) -> Bool {
        if lastId == pulse.id { return false }
        let gap = pulse.isStrong ? strongGap : jokeGap
        if let lastAt, now.timeIntervalSince(lastAt) < gap { return false }
        return true
    }

    private static func sleepPulse(hours: Double, day: String, who: String, sex: UserBodyProfile.Sex) -> ActivityPulse {
        let label = String(format: "%.1f", hours)
        if hours >= 7 {
            return ActivityPulse(
                id: "sleep-\(day)-banked",
                tone: .reward,
                isStrong: true,
                glanceTitle: "Sleep banked",
                glanceLine: "\(label)h last night",
                phoneBody: sex == .female
                    ? "\(label) hours down. That's a reward. Spend it on the plan, not a victory pastry."
                    : "\(label) hours in the bank. Reward accepted. Don't cash it out at the snack cupboard."
            )
        }
        if hours < 5.5 {
            return ActivityPulse(
                id: "sleep-\(day)-short",
                tone: .punishment,
                isStrong: true,
                glanceTitle: "Short sleep",
                glanceLine: "\(label)h last night",
                phoneBody: sex == .female
                    ? "\(label) hours. Punishment is a plain day: protein, a walk, no heroics. Be kind, not chaotic."
                    : "\(label) hours. Punishment: boring food, real steps, no victory snacks. The day is already taxed."
            )
        }
        return ActivityPulse(
            id: "sleep-\(day)-ok",
            tone: .greeting,
            isStrong: true,
            glanceTitle: "Night logged",
            glanceLine: "\(label)h sleep",
            phoneBody: "\(who) slept \(label) hours. Not a medal, not a crisis. Hit the plan and keep the wrist on tonight."
        )
    }

    private static func stepBucket(_ count: Int) -> Int? {
        if count >= 10_000 { return 10_000 }
        if count >= 7_000 { return 7_000 }
        if count >= 4_000 { return 4_000 }
        return nil
    }

    private static func stepRewardBody(count: Int, bucket: Int, who: String, sex: UserBodyProfile.Sex) -> String {
        switch bucket {
        case 10_000:
            return sex == .female
                ? "\(formatted(count)) steps. Reward: you may feel smug for four minutes. Then eat the plan."
                : "\(formatted(count)) steps. Reward unlocked. Smugness expires in four minutes. Dinner still counts."
        case 7_000:
            return "\(formatted(count)) steps. That's a real reward, \(who). Don't negotiate it away at 9pm."
        default:
            return "\(formatted(count)) steps. Humor me and keep going. 4k is a start, not a parade."
        }
    }

    private static func punishmentSteps(count: Int, sex: UserBodyProfile.Sex) -> String {
        sex == .female
            ? "\(formatted(count)) steps and the evening is here. Punishment is a lap around the block, not a speech."
            : "\(formatted(count)) steps. Punishment: shoes on, ten minutes outside. The couch is not a personality."
    }

    private static func jokeLine(slot: Int, steps: Int, sex: UserBodyProfile.Sex) -> String {
        let lines: [String] = sex == .female
            ? [
                "\(formatted(steps)) steps. Joke's on the sofa. You're winning by a sidewalk.",
                "Still moving. The only plot twist I want is protein at dinner.",
                "Steps are up. Humor status: proud, not impressed enough to allow a pastry.",
                "Look at you, walking like it was your idea. Keep the streak boring."
            ]
            : [
                "\(formatted(steps)) steps. The couch filed a missing-person report. Stay missing.",
                "Joke: rest is earned. You have not earned a bakery.",
                "Humor checkpoint. Legs work. Keep them employed.",
                "Steps are talking. They say don't sit down and call it recovery."
            ]
        return lines[abs(slot) % lines.count]
    }

    private static func formatted(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
