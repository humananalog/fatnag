import Foundation

/// Physics-aware weigh-in gate + short-term recovery plan after a confirmed spike.
enum WeightSpikeKind: String, Equatable, Sendable {
    /// Jump beyond human physiology in the lookback window → glitch or another person.
    case impossible
    /// Large but possible (water / binge / travel). Needs confirmation + recovery.
    case notableGain
    /// Large drop — same other-person / glitch risk.
    case notableLoss
}

struct WeightSpikeVerdict: Equatable, Sendable {
    var kind: WeightSpikeKind
    var deltaKg: Double
    var priorKg: Double
    var weighedKg: Double
    var hoursSincePrior: Double
    /// One-line reason for UI / local AI.
    var reason: String
}

struct WeightRecoveryPlan: Equatable, Sendable {
    /// Keep weekStartKg; do not treat spike as the new baseline for Sunday math.
    var ignoreSpikeForWeekStart: Bool
    /// Aggressive weekly delta (kg), clamped to safe metabolism.
    var weeklyDeltaKg: Double
    var sundayTargetKg: Double
    var dailyTargetKg: Double
    var kickHeadline: String
    var kickBody: String
    var actionLines: [String]
    var pacingLine: String
}

enum WeightSpikeEvaluator {
    /// Absolute ceiling for 24h mass change a human body can show on a scale.
    /// Above this → refuse as baseline / treat as other person or malfunction.
    static let impossibleAbsKgPerDay: Double = 8.0
    /// Soft spike that still needs a reality-check confirmation.
    static let notableAbsKgPerDay: Double = 2.4
    /// Relative body-mass ceiling (~12% in 24h is never real fat change).
    static let impossibleFractionPerDay: Double = 0.12

    /// Evaluate `weighedKg` vs the most recent prior Health sample.
    static func evaluate(
        weighedKg: Double,
        priorKg: Double?,
        priorDate: Date?,
        now: Date = Date()
    ) -> WeightSpikeVerdict? {
        guard let priorKg, ProfileNumericBounds.isPlausibleWeighKg(weighedKg),
              ProfileNumericBounds.isPlausibleWeighKg(priorKg) else { return nil }
        let delta = weighedKg - priorKg
        let hours: Double = {
            guard let priorDate else { return 24 }
            let h = now.timeIntervalSince(priorDate) / 3_600
            return max(h.isFinite ? h : 24, 1)
        }()
        let dayScale = max(hours / 24.0, 0.25)
        let absDelta = abs(delta)
        let absPerDay = absDelta / dayScale
        let fraction = absDelta / max(priorKg, 1)

        if absPerDay >= impossibleAbsKgPerDay
            || fraction >= impossibleFractionPerDay * dayScale {
            let kind: WeightSpikeKind = delta >= 0 ? .impossible : .impossible
            return WeightSpikeVerdict(
                kind: kind,
                deltaKg: delta,
                priorKg: priorKg,
                weighedKg: weighedKg,
                hoursSincePrior: hours,
                reason: String(
                    format: "A %.1f kg swing in %.0fh is not physically plausible for one person. Scale glitch or someone else?",
                    absDelta,
                    hours
                )
            )
        }

        if absPerDay >= notableAbsKgPerDay {
            if delta > 0 {
                return WeightSpikeVerdict(
                    kind: .notableGain,
                    deltaKg: delta,
                    priorKg: priorKg,
                    weighedKg: weighedKg,
                    hoursSincePrior: hours,
                    reason: String(
                        format: "Up %.1f kg in %.0fh. Confirm it is you, then we lock a recovery plan.",
                        absDelta,
                        hours
                    )
                )
            }
            return WeightSpikeVerdict(
                kind: .notableLoss,
                deltaKg: delta,
                priorKg: priorKg,
                weighedKg: weighedKg,
                hoursSincePrior: hours,
                reason: String(
                    format: "Down %.1f kg in %.0fh. Confirm it is you before we trust this sample.",
                    absDelta,
                    hours
                )
            )
        }
        return nil
    }

    /// After the user confirms a notable gain is real: aggressive return-to-track plan.
    /// Uses `weekStartKg` (not the spike) so Sunday target is not rewritten upward.
    static func recoveryPlan(
        name: String,
        spike: WeightSpikeVerdict,
        weekStartKg: Double?,
        idealKg: Double,
        system: PreferredUnitSystem,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeightRecoveryPlan {
        let baseline = weekStartKg ?? spike.priorKg
        let safeLoss = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: max(spike.weighedKg, baseline))
        // Aggressive: full safe weekly loss from the pre-spike track, not from the spike.
        let weekly = -safeLoss
        let sunday = MondayCardEngine.targetSunday(from: now, calendar: calendar)
        let daysLeft = max(
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: now),
                to: calendar.startOfDay(for: sunday)
            ).day ?? 1,
            1
        )
        // Aim Sunday at week-start + weekly plan (ignore spike as new truth).
        let sundayTarget = (baseline + weekly).rounded(toPlaces: 2)
        let daily = (weekly / 7.0).rounded(toPlaces: 3)
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Hey" : name
        let up = UnitFormat.massDeltaString(spike.deltaKg, system: system)
        let sunLabel = UnitFormat.massString(sundayTarget, system: system, fractionDigits: 1)
        let dailyLabel = UnitFormat.massDeltaString(daily, system: system)

        return WeightRecoveryPlan(
            ignoreSpikeForWeekStart: true,
            weeklyDeltaKg: weekly.rounded(toPlaces: 2),
            sundayTargetKg: sundayTarget,
            dailyTargetKg: daily,
            kickHeadline: AppLanguageStore.text("spike.red.headline", default: "Red card. Put it together."),
            kickBody: "\(who). \(up) just blew the week. We are not rewriting Sunday upward. Target \(sunLabel) and move \(dailyLabel)/day. Reality check, then execute.",
            actionLines: [
                AppLanguageStore.text("spike.red.action1", default: "Weigh every morning, empty bladder, same scale."),
                AppLanguageStore.text("spike.red.action2", default: "Hit the calorie and protein caps on the home board. No make-up-later."),
                String(
                    format: AppLanguageStore.text("spike.red.action3", default: "Next %d days: sleep on time, walk the step target, no celebration eats."),
                    daysLeft
                ),
                AppLanguageStore.text("spike.red.action4", default: "If this was not you on the scale, discard the sample and re-weigh."),
            ],
            pacingLine: String(
                format: AppLanguageStore.text("spike.red.pacing", default: "Recovery: %@ / week toward %@ by Sunday (safe metabolism cap)."),
                UnitFormat.massDeltaString(weekly, system: system),
                sunLabel
            )
        )
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let f = pow(10.0, Double(places))
        return (self * f).rounded() / f
    }
}
