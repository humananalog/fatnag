import Foundation

/// How this week's mini-goal was shaped relative to last week / the finish line.
enum WeeklyTargetMode: String, Equatable, Sendable {
    /// Needed pace, pushed to the safe biology cap toward the macro goal.
    case aggressive
    /// Missed last Sunday target: catch-up shortfall within safe max.
    case hardcoreCatchUp
    /// Ahead of last week / calendar: do not coast; keep near safe-max toward finish.
    case accelerate
    /// Near ideal: hold / tiny nudge.
    case hold
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
                    format: "Near ideal (%.1f kg). Hold Sunday near %.2f kg.",
                    idealKg,
                    currentKg
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

        // Aggressive default: push as hard as biology allows toward the finish line.
        // If calendar needs more than safe, clamp. If calendar is softer, still use safe max.
        var weekly: Double
        var mode: WeeklyTargetMode = .aggressive
        if towardLower {
            weekly = -safeLoss
            // Never go softer than calendar pace when calendar is already aggressive.
            if calendarPace < weekly {
                weekly = max(calendarPace, -safeLoss)
            }
        } else {
            weekly = safeGain
            if calendarPace > weekly {
                weekly = min(calendarPace, safeGain)
            }
        }

        // Last-week adherence vs prior Sunday target.
        if let prior = priorSundayTargetKg {
            let miss = currentKg - prior
            if towardLower {
                if miss > adherenceSlackKg {
                    // Over prior Sunday: hardcore catch-up (extra loss), still within safe max.
                    let catchUp = weekly - miss
                    weekly = max(catchUp, -safeLoss)
                    mode = .hardcoreCatchUp
                } else if miss < -adherenceSlackKg {
                    // Under prior Sunday (ahead): do not coast; keep near safe max.
                    weekly = -safeLoss
                    mode = .accelerate
                }
            } else if towardHigher {
                if miss < -adherenceSlackKg {
                    let catchUp = weekly + abs(miss)
                    weekly = min(catchUp, safeGain)
                    mode = .hardcoreCatchUp
                } else if miss > adherenceSlackKg {
                    weekly = safeGain
                    mode = .accelerate
                }
            }
        } else if towardLower, let goalDate {
            // No prior Sunday: if calendar ETA already beats plan, still accelerate (no coast).
            let neededWeeks = abs(remaining / max(abs(calendarPace), 0.01))
            let daysLeft = max(
                calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: now),
                    to: calendar.startOfDay(for: goalDate)
                ).day ?? 0,
                0
            )
            let weeksLeft = Double(daysLeft) / 7.0
            if weeksLeft > neededWeeks + 0.5 {
                weekly = -safeLoss
                mode = .accelerate
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
                return String(format: " toward %.1f kg by %@", idealKg, label)
            }
            return String(format: " toward %.1f kg", idealKg)
        }()

        let modeBit: String = {
            switch mode {
            case .hardcoreCatchUp:
                return " Hardcore catch-up after last week."
            case .accelerate:
                return " Ahead: accelerate, no coast."
            case .aggressive:
                return " Aggressive to finish (safe cap)."
            case .hold:
                return ""
            }
        }()

        let pacingLine = String(
            format: "%+.2f kg/wk%@ → Sunday %.2f kg.%@",
            weekly,
            towardBit,
            target,
            modeBit
        )

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
