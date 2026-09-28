import Foundation

/// How this week's mini-goal was shaped relative to last week / the finish line.
enum WeeklyTargetMode: String, Equatable, Sendable {
    /// Needed pace to the user's goal date, inside the safe biology cap.
    case aggressive
    /// Goal date needs more than a safe weekly cut. Intake drops to the cap.
    case commando
    /// Missed last Sunday target: catch-up shortfall within safe max.
    case hardcoreCatchUp
    /// Ahead of last week / calendar: do not coast; keep near safe-max toward finish.
    case accelerate
    /// Near ideal: hold / tiny nudge.
    case hold

    /// Short Monday-hero badge (Keel voice, no medical framing).
    var mondayHeroBadge: String {
        switch self {
        case .hardcoreCatchUp: return String(localized: "week.mode.hardcore", defaultValue: "HARDCORE")
        case .accelerate: return String(localized: "week.mode.ahead", defaultValue: "AHEAD")
        case .aggressive: return String(localized: "week.mode.aggressive", defaultValue: "AGGRESSIVE")
        case .commando: return String(localized: "week.mode.commando", defaultValue: "COMMANDO")
        case .hold: return String(localized: "week.mode.hold", defaultValue: "HOLD")
        }
    }

    /// One-line CTA under the Sunday target.
    var mondayHeroCTA: String {
        switch self {
        case .hardcoreCatchUp: return String(localized: "week.mode.hardcore.cta", defaultValue: "No coast. Close the gap.")
        case .accelerate: return String(localized: "week.mode.ahead.cta", defaultValue: "Celebrate, then push.")
        case .aggressive: return String(localized: "week.mode.aggressive.cta", defaultValue: "Hit Sunday. Full send.")
        case .commando: return String(localized: "week.mode.commando.cta", defaultValue: "Cut intake. The date has to move.")
        case .hold: return String(localized: "week.mode.hold.cta", defaultValue: "Hold the line.")
        }
    }
}

struct AggressiveWeeklyTarget: Equatable, Sendable {
    var weeklyDeltaKg: Double
    var sundayTargetKg: Double
    var sundayDate: Date
    var mode: WeeklyTargetMode
    var safeCapKgPerWeek: Double
    var pacingLine: String
}

/// Weekly mini-goal from the macro goal: as hard as biology safely allows.
/// Missed last week → hardcore catch-up. Ahead → accelerate, never coast.
enum AggressiveWeeklyTargetEngine {
    /// Tolerance around prior Sunday before counting miss / ahead (kg).
    static let adherenceSlackKg: Double = 0.15

    static func compute(
        currentKg: Double,
        idealKg: Double,
        goalDate: Date?,
        priorSundayTargetKg: Double?,
        fallbackWeeklyDeltaKg: Double = -0.3,
        system: PreferredUnitSystem = .metric,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AggressiveWeeklyTarget {
        let sunday = MondayCardEngine.targetSunday(from: now, calendar: calendar)
        let remaining = idealKg - currentKg
        let towardLower = remaining < -0.05
        let towardHigher = remaining > 0.05

        if abs(remaining) < 0.15 {
            let delta = 0.0
            return AggressiveWeeklyTarget(
                weeklyDeltaKg: delta,
                sundayTargetKg: round2(currentKg + delta),
                sundayDate: sunday,
                mode: .hold,
                safeCapKgPerWeek: 0,
                pacingLine: String(
                    format: "Near ideal (%@). Hold Sunday near %@.",
                    UnitFormat.massString(idealKg, system: system, fractionDigits: 1),
                    UnitFormat.massString(currentKg, system: system, fractionDigits: 2)
                )
            )
        }

        let safeLoss = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: currentKg)
        let safeGain = TargetFeasibility.maxSafeGainKgPerWeek(currentKg: currentKg)
        let safeCap = towardLower ? safeLoss : safeGain

        // Calendar pace to goal date, else fallback nudge in the right direction.
        let calendarPace: Double = {
            if let goalDate {
                let days = max(
                    calendar.dateComponents(
                        [.day],
                        from: calendar.startOfDay(for: now),
                        to: calendar.startOfDay(for: goalDate)
                    ).day ?? 0,
                    0
                )
                let weeks = max(Double(days) / 7.0, 1.0 / 7.0)
                return remaining / weeks
            }
            let signedFallback = towardLower
                ? -abs(fallbackWeeklyDeltaKg)
                : abs(fallbackWeeklyDeltaKg)
            return signedFallback
        }()

        // Follow the goal date when that pace is safe. A softer calendar must not
        // be replaced by the biology cap — that pulled ETA months ahead of the date.
        // Only an impossible date drops intake to the safe max (commando).
        var weekly: Double
        var mode: WeeklyTargetMode
        if towardLower {
            if calendarPace < -safeLoss - 0.001 {
                weekly = -safeLoss
                mode = .commando
            } else {
                weekly = calendarPace
                mode = .aggressive
            }
        } else if towardHigher {
            if calendarPace > safeGain + 0.001 {
                weekly = safeGain
                mode = .commando
            } else {
                weekly = calendarPace
                mode = .aggressive
            }
        } else {
            weekly = 0
            mode = .hold
        }

        // Last-week adherence vs prior Sunday target. Commando already sits on the cap.
        if mode != .commando, let prior = priorSundayTargetKg {
            let miss = currentKg - prior
            if towardLower {
                if miss > adherenceSlackKg {
                    let catchUp = weekly - miss
                    weekly = max(catchUp, -safeLoss)
                    mode = .hardcoreCatchUp
                } else if miss < -adherenceSlackKg {
                    // Ahead of last Sunday: keep the goal-date pace. Do not race the macro ETA.
                    mode = .accelerate
                }
            } else if towardHigher {
                if miss < -adherenceSlackKg {
                    let catchUp = weekly + abs(miss)
                    weekly = min(catchUp, safeGain)
                    mode = .hardcoreCatchUp
                } else if miss > adherenceSlackKg {
                    mode = .accelerate
                }
            }
        }

        // Never overshoot past ideal in one week.
        if towardLower {
            weekly = max(weekly, remaining) // remaining is negative; don't go past ideal
            weekly = max(weekly, -safeLoss)
        } else {
            weekly = min(weekly, remaining)
            weekly = min(weekly, safeGain)
        }

        weekly = round2(weekly)
        let target = round2(currentKg + weekly)

        let towardBit: String = {
            if let goalDate {
                let label = goalDate.formatted(.dateTime.month(.abbreviated).day().year())
                return " toward \(UnitFormat.massString(idealKg, system: system, fractionDigits: 1)) by \(label)"
            }
            return " toward \(UnitFormat.massString(idealKg, system: system, fractionDigits: 1))"
        }()

        let modeBit: String = {
            switch mode {
            case .hardcoreCatchUp:
                return " Hardcore catch-up after last week."
            case .accelerate:
                return " Ahead: accelerate, no coast."
            case .aggressive:
                return " Paced to your goal date."
            case .commando:
                return " Commando: intake at the safe max. The date needs a rewrite."
            case .hold:
                return ""
            }
        }()

        let pacingLine = "\(UnitFormat.massDeltaString(weekly, system: system, fractionDigits: 2))/wk\(towardBit) → \(UnitFormat.sundayTitle(kg: target, system: system)).\(modeBit)"

        return AggressiveWeeklyTarget(
            weeklyDeltaKg: weekly,
            sundayTargetKg: target,
            sundayDate: sunday,
            mode: mode,
            safeCapKgPerWeek: round2(safeCap),
            pacingLine: pacingLine
        )
    }

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
