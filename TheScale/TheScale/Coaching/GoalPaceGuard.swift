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
                keelNote: AppLanguageStore.text(
                    "onboarding.pace.too_soon",
                    default: "Pick a date at least a week out. Instant transformation is a fairy tale, not a plan."
                )
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
                keelNote: AppLanguageStore.text(
                    "onboarding.pace.hold",
                    default: "Already near that number. Fine as a hold target."
                )
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
                    format: AppLanguageStore.text(
                        "onboarding.pace.human",
                        default: "Pace looks human: about %.2f kg/week (safe cap ~%.2f kg/week)."
                    ),
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
        let earliestLabel = earliest?.formatted(
            .dateTime.month(.abbreviated).day().year().locale(AppLanguageStore.effectiveLocale)
        ) ?? AppLanguageStore.text("onboarding.pace.later", default: "later")

        let direction: String
        if towardLower {
            direction = AppLanguageStore.text("onboarding.pace.lose", default: "lose")
        } else if towardHigher {
            direction = AppLanguageStore.text("onboarding.pace.gain", default: "gain")
        } else {
            direction = AppLanguageStore.text("onboarding.pace.move", default: "move")
        }
        return GoalPaceVerdict(
            status: .rejected,
            requiredKgPerWeek: requiredPerWeek,
            safeCapKgPerWeek: safeCap,
            earliestFeasibleDate: earliest,
            keelNote: String(
                format: AppLanguageStore.text(
                    "onboarding.pace.refuse",
                    default: "Keel says no. %.1f kg in %d days is about %.2f kg/week. Safe max to %@ is ~%.2f kg/week. Earliest honest date: %@."
                ),
                abs(delta),
                days,
                magnitudeNeeded,
                direction,
                safeCap,
                earliestLabel
            )
        )
    }

    /// Display mass bounds for the analog dream / target scale (kg, always).
    /// Hard BMI band from height + sex + age; absolute human mass caps from `ProfileNumericBounds`.
    /// Does **not** expand past the BMI floor/ceiling — ticks cannot scroll into nonsense.
    static func dreamWeightBoundsKg(
        currentKg: Double,
        heightCm: Double,
        sex: UserBodyProfile.Sex,
        ageYears: Double
    ) -> ClosedRange<Double> {
        let floorBMI = TargetFeasibility.targetBMIHardFloor(sex: sex, ageYears: ageYears)
        let ceilingBMI = TargetFeasibility.targetBMIHardCeiling(sex: sex, ageYears: ageYears)
        let hardFloor = TargetFeasibility.weightKg(forBMI: floorBMI, heightCm: heightCm)
        let hardCeiling = TargetFeasibility.weightKg(forBMI: ceilingBMI, heightCm: heightCm)
        let absolute = ProfileNumericBounds.weightKg
        let low = max(absolute.lowerBound, hardFloor)
        let high = min(absolute.upperBound, hardCeiling)
        // `currentKg` kept in signature for call-site clarity / future centering; band is BMI-hard only.
        _ = currentKg
        return low...max(low + 1, high)
    }
}
