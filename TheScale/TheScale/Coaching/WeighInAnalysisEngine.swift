import Foundation

/// Coach reaction after a weigh-in lands in Health. Congrats / reward / blunt punish. No diagnosis.
enum WeighInCoachTone: String, Equatable, Sendable {
    case congratulate
    case reward
    case punish
}

struct WeighInAnalysisCard: Equatable, Sendable {
    var tone: WeighInCoachTone
    var headline: String
    var body: String
    var deltaKg: Double?
    var weighedKg: Double
    var createdAt: Date
}

enum WeighInAnalysisEngine {
    /// Build a hero analysis card from this weigh-in vs last Health baseline.
    static func build(
        name: String,
        weighedKg: Double,
        previousKg: Double?,
        weeklyGoal: WeeklyMiniGoal,
        idealKg: Double,
        chartCommentsBlock: String = "",
        now: Date = Date()
    ) -> WeighInAnalysisCard {
        let who = name.isEmpty ? "Operator" : name
        let delta: Double? = previousKg.map { weighedKg - $0 }
        let towardIdeal = weighedKg - idealKg
        let cutting = weeklyGoal.targetDeltaKg < -0.05

        let tone: WeighInCoachTone
        let headline: String
        let body: String

        if let delta {
            if cutting {
                if delta <= -0.15 {
                    tone = .congratulate
                    headline = "That's the number, \(who)."
                    body = String(
                        format: "%.2f kg down since last. Keep the boring streak. Ideal still %.1f kg away.",
                        abs(delta),
                        max(0, towardIdeal)
                    )
                } else if delta <= 0.12 {
                    tone = .reward
                    headline = "Quiet win."
                    body = String(
                        format: "Flat-ish (%+.2f kg). Noise happens. Hit protein and close the kitchen on time.",
                        delta
                    )
                } else {
                    tone = .punish
                    headline = "Scale doesn't do vibes, \(who)."
                    body = String(
                        format: "%+.2f kg since last. Not doom. Fix dinner tonight, not your personality.",
                        delta
                    )
                }
            } else {
                // Maintain / gain goal
                if abs(delta) <= 0.15 {
                    tone = .reward
                    headline = "Steady."
                    body = String(format: "%+.2f kg. Boring is the brand.", delta)
                } else if delta > 0.15 {
                    tone = .congratulate
                    headline = "Up is the job."
                    body = String(format: "%+.2f kg. Keep fueling like you mean it.", delta)
                } else {
                    tone = .punish
                    headline = "Wrong direction for this week."
                    body = String(format: "%+.2f kg. Eat the plan, not the fridge mood.", delta)
                }
            }
        } else {
            tone = .reward
            headline = "Baseline locked."
            body = String(
                format: "%.1f kg on the board, \(who). Next weigh-in gets the roast or the parade.",
                weighedKg
            )
        }

        _ = chartCommentsBlock // reserved for Coach payload; keep card copy short
        return WeighInAnalysisCard(
            tone: tone,
            headline: CoachCopySanitize.clean(headline),
            body: CoachCopySanitize.clean(body),
            deltaKg: delta,
            weighedKg: weighedKg,
            createdAt: now
        )
    }
}

/// ETA to macro (ideal) weight at current weekly speed vs planned goal date.
struct MacroGoalETA: Equatable, Sendable {
    var paceKgPerWeek: Double?
    var etaDate: Date?
    var plannedDate: Date?
    var remainingKg: Double
    var line: String

    static let empty = MacroGoalETA(
        paceKgPerWeek: nil,
        etaDate: nil,
        plannedDate: nil,
        remainingKg: 0,
        line: "Weigh in a few times to project ETA to your goal weight."
    )

    static func compute(
        currentKg: Double?,
        idealKg: Double,
        plannedDate: Date?,
        recentWeights: [HealthWeightSample],
        weeklyDeltaKg: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MacroGoalETA {
        guard let current = currentKg else { return .empty }
        let remaining = current - idealKg
        if abs(remaining) < 0.15 {
            return MacroGoalETA(
                paceKgPerWeek: 0,
                etaDate: now,
                plannedDate: plannedDate,
                remainingKg: remaining,
                line: "You're at goal weight. Hold the line."
            )
        }

        // Prefer observed 7-14d pace; fall back to weekly mini-goal.
        var pace: Double?
        let sorted = recentWeights.sorted { $0.date < $1.date }
        if sorted.count >= 2,
           let first = sorted.first,
           let last = sorted.last {
            let days = max(1.0, last.date.timeIntervalSince(first.date) / 86_400)
            if days >= 3 {
                let delta = last.weightKg - first.weightKg
                pace = delta / days * 7.0
            }
        }
        if pace == nil {
            pace = weeklyDeltaKg
        }
        guard let paceKgPerWeek = pace, abs(paceKgPerWeek) > 0.02 else {
            let plannedBit = plannedDate.map {
                " Planned " + $0.formatted(.dateTime.month(.abbreviated).day()) + "."
            } ?? ""
            return MacroGoalETA(
                paceKgPerWeek: pace,
                etaDate: nil,
                plannedDate: plannedDate,
                remainingKg: remaining,
                line: String(format: "%.1f kg to goal. Pace too flat to date.", abs(remaining)) + plannedBit
            )
        }

        // Need pace in the right direction toward ideal.
        let towardIdeal = remaining > 0 // need to lose
        let movingRight = towardIdeal ? paceKgPerWeek < 0 : paceKgPerWeek > 0
        guard movingRight else {
            return MacroGoalETA(
                paceKgPerWeek: paceKgPerWeek,
                etaDate: nil,
                plannedDate: plannedDate,
                remainingKg: remaining,
                line: String(
                    format: "%.1f kg to goal, but current pace (%+.2f kg/wk) goes the wrong way.",
                    abs(remaining),
                    paceKgPerWeek
                )
            )
        }

        let weeks = abs(remaining / paceKgPerWeek)
        let eta = calendar.date(byAdding: .day, value: Int((weeks * 7).rounded()), to: now)
        let etaText = eta?.formatted(.dateTime.month(.abbreviated).day()) ?? "soon"
        let plannedBit: String = {
            guard let planned = plannedDate else { return "" }
            let planText = planned.formatted(.dateTime.month(.abbreviated).day())
            if let eta, eta <= planned {
                return " Ahead of plan (\(planText))."
            }
            return " Plan was \(planText)."
        }()

        return MacroGoalETA(
            paceKgPerWeek: paceKgPerWeek,
            etaDate: eta,
            plannedDate: plannedDate,
            remainingKg: remaining,
            line: String(
                format: "ETA %@ at %+.2f kg/wk · %.1f kg to go.%@",
                etaText,
                paceKgPerWeek,
                abs(remaining),
                plannedBit
            )
        )
    }
}
