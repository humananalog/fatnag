import Foundation

/// Whether a dream-weight + target-date pair is biologically plausible.
struct GoalPaceVerdict: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case accepted
        case rejected
    }

    let status: Status
    /// Required kg/week to hit the date (signed: negative = lose).
    let requiredKgPerWeek: Double
    /// Safe biology cap for that direction (always positive magnitude).
    let safeCapKgPerWeek: Double
    /// Earliest date that stays within the safe cap (when rejected).
    let earliestFeasibleDate: Date?
    /// Keel-voice refusal or pacing note. No em dashes.
    let keelNote: String
}

/// Blocks impossible dream-weight calendars (e.g. 10 kg in 1 week).
/// Safe biology caps from `TargetFeasibility` win over flavor and desire.
enum GoalPaceGuard {
    /// Minimum days before a target date can be set (same calendar day is nonsense).
    static let minimumHorizonDays: Int = 7

    static func evaluate(
        currentKg: Double,
        targetKg: Double,
        goalDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> GoalPaceVerdict {
        let delta = targetKg - currentKg
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: goalDate)
        ).day ?? 0

        if days < minimumHorizonDays {
            let earliest = calendar.date(byAdding: .day, value: minimumHorizonDays, to: calendar.startOfDay(for: now))
            return GoalPaceVerdict(
                status: .rejected,
                requiredKgPerWeek: 0,
                safeCapKgPerWeek: 0,
                earliestFeasibleDate: earliest,
                keelNote: "Pick a date at least a week out. Instant transformation is a fairy tale, not a plan."
            )
        }

        let weeks = Double(days) / 7.0
        let requiredPerWeek = delta / weeks
        let towardLower = delta < -0.05
        let towardHigher = delta > 0.05

        if abs(delta) < 0.15 {
            return GoalPaceVerdict(
                status: .accepted,
                requiredKgPerWeek: 0,
                safeCapKgPerWeek: 0,
                earliestFeasibleDate: nil,
                keelNote: "Already near that number. Fine as a hold target."
            )
        }

        let safeCap = towardLower
            ? TargetFeasibility.maxSafeLossKgPerWeek(currentKg: currentKg)
            : TargetFeasibility.maxSafeGainKgPerWeek(currentKg: currentKg)

        let magnitudeNeeded = abs(requiredPerWeek)
        if magnitudeNeeded <= safeCap + 0.001 {
            return GoalPaceVerdict(
                status: .accepted,
                requiredKgPerWeek: requiredPerWeek,
                safeCapKgPerWeek: safeCap,
                earliestFeasibleDate: nil,
                keelNote: String(
                    format: "Pace looks human: about %.2f kg/week (safe cap ~%.2f kg/week).",
                    requiredPerWeek,
                    safeCap
                )
            )
        }

        let weeksNeeded = abs(delta) / max(safeCap, 0.01)
        let daysNeeded = Int(ceil(weeksNeeded * 7.0))
        let earliest = calendar.date(
            byAdding: .day,
            value: max(daysNeeded, minimumHorizonDays),
            to: calendar.startOfDay(for: now)
        )
        let earliestLabel = earliest?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "later"

        let direction = towardLower ? "lose" : (towardHigher ? "gain" : "move")
        return GoalPaceVerdict(
            status: .rejected,
            requiredKgPerWeek: requiredPerWeek,
            safeCapKgPerWeek: safeCap,
            earliestFeasibleDate: earliest,
            keelNote: String(
                format: "Keel says no. %.1f kg in %d days is about %.2f kg/week. Safe max to %@ is ~%.2f kg/week. Earliest honest date: %@.",
                abs(delta),
                days,
                magnitudeNeeded,
                direction,
                safeCap,
                earliestLabel
            )
        )
    }

    /// Display mass bounds for the analog dream scale (kg, always).
    static func dreamWeightBoundsKg(currentKg: Double, heightCm: Double) -> ClosedRange<Double> {
        let hardFloor = TargetFeasibility.weightKg(forBMI: TargetFeasibility.bmiHardFloor, heightCm: heightCm)
        let hardCeiling = TargetFeasibility.weightKg(forBMI: TargetFeasibility.bmiHardCeiling, heightCm: heightCm)
        let low = max(30, min(hardFloor, currentKg - 40))
        let high = min(300, max(hardCeiling, currentKg + 40))
        return low...max(low + 1, high)
    }
}
