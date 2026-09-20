import Foundation

/// Sleep stage hours from HealthKit `HKCategoryTypeIdentifier.sleepAnalysis`.
///
/// Apple Watch (watchOS 9+) writes Core / Deep / REM / Awake. Older sources may
/// only write legacy `asleep` / `asleepUnspecified`. Missing stages stay nil —
/// Coach must never invent them.
struct SleepStageHours: Equatable, Sendable {
    var coreHours: Double?
    var deepHours: Double?
    var remHours: Double?
    var awakeHours: Double?
    var unspecifiedAsleepHours: Double?

    var hasAnyStage: Bool {
        coreHours != nil || deepHours != nil || remHours != nil
            || awakeHours != nil || unspecifiedAsleepHours != nil
    }

    /// Sum of asleep stages only (excludes awake). Nil when nothing asleep was recorded.
    var totalAsleepHours: Double? {
        let parts = [coreHours, deepHours, remHours, unspecifiedAsleepHours].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0, +)
    }
}

/// One night's sleep window for Coach + algorithms.
struct HealthSleepSnapshot: Equatable, Sendable {
    var totalAsleepHours: Double?
    var onset: Date?
    var wake: Date?
    var stages: SleepStageHours?
    /// Std-dev of bedtime (sleep onset) across recent nights, in hours. Lower = more consistent.
    var bedtimeConsistencyStdDevHours: Double?
    /// Mean asleep hours over nights with data in the lookback.
    var averageAsleepHours7d: Double?
    /// How many distinct nights contributed to consistency / 7d average.
    var nightsSampled: Int

    static let empty = HealthSleepSnapshot(
        totalAsleepHours: nil,
        onset: nil,
        wake: nil,
        stages: nil,
        bedtimeConsistencyStdDevHours: nil,
        averageAsleepHours7d: nil,
        nightsSampled: 0
    )
}

/// Transparent training-load / recovery band for Coach (not a clinical diagnosis).
struct RecoveryLoadHeuristic: Equatable, Sendable {
    enum Band: String, Equatable, Sendable {
        case green
        case yellow
        case red
        case unknown
    }

    var band: Band
    /// 0...100 when enough signals exist; nil when unknown.
    var score0to100: Int?
    /// Short factor lines shown in the digest (what moved the score).
    var factors: [String]
    var summaryLine: String
}

/// Pure, unit-testable science helpers for Health digests and projections.
///
/// Formulas are coaching heuristics with cited ballparks in comments — not medical devices.
enum HealthScienceMath {
    // MARK: - Sleep aggregation

    /// Collapse HealthKit sleep category samples into last-night + 7-night stats.
    ///
    /// **Last night:** prefer the contiguous asleep bout whose wake is nearest `now`
    /// within the last ~36h (covers late sleepers). Stages accumulate by category value.
    ///
    /// **Consistency:** for each distinct wake-calendar-day with ≥20 min asleep, take
    /// earliest onset; compute sample std-dev of onset time-of-day (hours). Needs ≥3 nights.
    ///
    /// Rationale: bedtime regularity associates with better cardiometabolic markers in
    /// observational sleep research; we report std-dev hours, not a proprietary "score".
    static func buildSleepSnapshot(
        samples: [(value: Int, start: Date, end: Date)],
        now: Date,
        calendar: Calendar = .current
    ) -> HealthSleepSnapshot {
        let asleep = samples.filter { isAsleepValue($0.value) }
        guard !asleep.isEmpty else {
            return .empty
        }
        let awakeSamples = samples.filter { isAwakeInBedValue($0.value) }

        // Group asleep samples into nights by wake calendar day.
        struct Night {
            var onset: Date
            var wake: Date
            var asleepSeconds: Double
            var stages: SleepStageHours
        }

        var nightsByWakeDay: [Date: Night] = [:]
        for sample in asleep {
            let wakeDay = calendar.startOfDay(for: sample.end)
            let duration = sample.end.timeIntervalSince(sample.start)
            guard duration > 0 else { continue }
            var night = nightsByWakeDay[wakeDay] ?? Night(
                onset: sample.start,
                wake: sample.end,
                asleepSeconds: 0,
                stages: SleepStageHours()
            )
            night.onset = min(night.onset, sample.start)
            night.wake = max(night.wake, sample.end)
            night.asleepSeconds += duration
            accumulateStage(value: sample.value, hours: duration / 3600.0, into: &night.stages)
            nightsByWakeDay[wakeDay] = night
        }

        // Fold in-bed awake segments that overlap each night window.
        for wakeDay in nightsByWakeDay.keys {
            guard var night = nightsByWakeDay[wakeDay] else { continue }
            for sample in awakeSamples {
                let overlapStart = max(sample.start, night.onset)
                let overlapEnd = min(sample.end, night.wake)
                let duration = overlapEnd.timeIntervalSince(overlapStart)
                guard duration > 0 else { continue }
                accumulateStage(value: sample.value, hours: duration / 3600.0, into: &night.stages)
            }
            nightsByWakeDay[wakeDay] = night
        }

        let nights = nightsByWakeDay.values
            .filter { $0.asleepSeconds >= 20 * 60 }
            .sorted { $0.wake > $1.wake }

        let recentCutoff = now.addingTimeInterval(-36 * 3600)
        let lastNight = nights.first { $0.wake >= recentCutoff && $0.onset <= now }

        let lookback = now.addingTimeInterval(-8 * 86_400)
        let weekNights = nights.filter { $0.wake >= lookback }
        let avg7d: Double? = {
            guard !weekNights.isEmpty else { return nil }
            let hours = weekNights.map { $0.asleepSeconds / 3600.0 }
            return hours.reduce(0, +) / Double(hours.count)
        }()

        let consistency: Double? = bedtimeConsistencyStdDevHours(
            onsets: weekNights.map(\.onset),
            calendar: calendar
        )

        guard let last = lastNight else {
            return HealthSleepSnapshot(
                totalAsleepHours: nil,
                onset: nil,
                wake: nil,
                stages: nil,
                bedtimeConsistencyStdDevHours: consistency,
                averageAsleepHours7d: avg7d,
                nightsSampled: weekNights.count
            )
        }

        return HealthSleepSnapshot(
            totalAsleepHours: last.asleepSeconds / 3600.0,
            onset: last.onset,
            wake: last.wake,
            stages: last.stages.hasAnyStage ? last.stages : nil,
            bedtimeConsistencyStdDevHours: consistency,
            averageAsleepHours7d: avg7d,
            nightsSampled: weekNights.count
        )
    }

    /// Sample standard deviation of bedtime (onset) expressed as hours-from-midnight.
    /// Handles midnight wrap by centering angles on the circular mean (simple unwrap
    /// via shifting times within ±12h of the median).
    static func bedtimeConsistencyStdDevHours(
        onsets: [Date],
        calendar: Calendar = .current
    ) -> Double? {
        guard onsets.count >= 3 else { return nil }
        let minutes: [Double] = onsets.map { onset in
            let comps = calendar.dateComponents([.hour, .minute, .second], from: onset)
            let h = Double(comps.hour ?? 0)
            let m = Double(comps.minute ?? 0)
            let s = Double(comps.second ?? 0)
            return h * 60 + m + s / 60.0
        }
        // Unwrap around median so 23:30 and 00:15 are 45 min apart, not ~23h.
        let sorted = minutes.sorted()
        let median = sorted[sorted.count / 2]
        let unwrapped = minutes.map { value -> Double in
            var v = value
            while v - median > 12 * 60 { v -= 24 * 60 }
            while median - v > 12 * 60 { v += 24 * 60 }
            return v
        }
        let mean = unwrapped.reduce(0, +) / Double(unwrapped.count)
        let variance = unwrapped.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
            / Double(unwrapped.count - 1)
        return sqrt(variance) / 60.0
    }

    static func isAsleepValue(_ value: Int) -> Bool {
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysisProxy.asleepUnspecified,
            HKCategoryValueSleepAnalysisProxy.asleepCore,
            HKCategoryValueSleepAnalysisProxy.asleepDeep,
            HKCategoryValueSleepAnalysisProxy.asleepREM,
            HKCategoryValueSleepAnalysisProxy.legacyAsleep
        ]
        return asleepValues.contains(value)
    }

    static func isAwakeInBedValue(_ value: Int) -> Bool {
        value == HKCategoryValueSleepAnalysisProxy.awake
    }

    private static func accumulateStage(value: Int, hours: Double, into stages: inout SleepStageHours) {
        switch value {
        case HKCategoryValueSleepAnalysisProxy.asleepCore:
            stages.coreHours = (stages.coreHours ?? 0) + hours
        case HKCategoryValueSleepAnalysisProxy.asleepDeep:
            stages.deepHours = (stages.deepHours ?? 0) + hours
        case HKCategoryValueSleepAnalysisProxy.asleepREM:
            stages.remHours = (stages.remHours ?? 0) + hours
        case HKCategoryValueSleepAnalysisProxy.awake:
            stages.awakeHours = (stages.awakeHours ?? 0) + hours
        case HKCategoryValueSleepAnalysisProxy.asleepUnspecified,
             HKCategoryValueSleepAnalysisProxy.legacyAsleep:
            stages.unspecifiedAsleepHours = (stages.unspecifiedAsleepHours ?? 0) + hours
        default:
            break
        }
    }

    // MARK: - Recovery / training-load heuristic

    /// Simple recovery band from sleep + HRV (SDNN) + RHR + recent workout load.
    ///
    /// **Not a diagnosis.** Transparent additive score starting at 70:
    /// - Sleep duration vs ~7–9 h adult ballpark (consensus sleep-duration reviews)
    /// - Deep sleep < ~45 min when stages present → mild penalty
    /// - HRV SDNN: very rough adult coaching bands (<20 / 20–40 / >50 ms). Individual
    ///   baselines dominate clinical HRV; we only nudge when absolute extremes appear,
    ///   and prefer relative vs 7d median when both exist.
    /// - RHR ≥ 85 bpm or ≥ +8 vs typical resting when only one reading exists → penalty
    /// - Heavy recent workout (long duration or high kcal) → small load penalty
    ///
    /// Bands: ≥70 green, 45–69 yellow, <45 red; unknown when almost no signals.
    static func recoveryHeuristic(
        sleepHours: Double?,
        stages: SleepStageHours?,
        hrvSDNNMs: Double?,
        hrvMedian7dMs: Double?,
        restingHRBpm: Double?,
        workoutCountLast24h: Int,
        lastWorkoutDurationMinutes: Double?,
        lastWorkoutKcal: Double?
    ) -> RecoveryLoadHeuristic {
        var signals = 0
        var score = 70.0
        var factors: [String] = []

        if let sleep = sleepHours {
            signals += 1
            if sleep < 5.5 {
                score -= 22
                factors.append(String(format: "Short sleep (%.1f h) vs ~7-9 h ballpark.", sleep))
            } else if sleep < 6.5 {
                score -= 10
                factors.append(String(format: "Sleep %.1f h is a bit short.", sleep))
            } else if sleep <= 9.0 {
                score += 10
                factors.append(String(format: "Sleep %.1f h in a solid duration band.", sleep))
            } else {
                score -= 4
                factors.append(String(format: "Long sleep (%.1f h); check if recovering from load.", sleep))
            }
        }

        if let deep = stages?.deepHours {
            signals += 1
            if deep < 0.75 {
                score -= 8
                factors.append(String(format: "Deep sleep only %.1f h.", deep))
            } else {
                factors.append(String(format: "Deep sleep %.1f h present.", deep))
            }
        }

        if let hrv = hrvSDNNMs {
            signals += 1
            if let median = hrvMedian7dMs, median > 0 {
                let ratio = hrv / median
                if ratio < 0.7 {
                    score -= 14
                    factors.append(
                        String(format: "HRV SDNN %.0f ms is low vs ~7d median %.0f ms.", hrv, median)
                    )
                } else if ratio > 1.15 {
                    score += 8
                    factors.append(
                        String(format: "HRV SDNN %.0f ms above ~7d median %.0f ms.", hrv, median)
                    )
                } else {
                    factors.append(String(format: "HRV SDNN %.0f ms near recent median.", hrv))
                }
            } else if hrv < 20 {
                score -= 12
                factors.append(String(format: "HRV SDNN %.0f ms is low on absolute coaching bands.", hrv))
            } else if hrv >= 50 {
                score += 6
                factors.append(String(format: "HRV SDNN %.0f ms looks comfortable on absolute bands.", hrv))
            } else {
                factors.append(String(format: "HRV SDNN %.0f ms (no 7d median yet).", hrv))
            }
        }

        if let rhr = restingHRBpm {
            signals += 1
            if rhr >= 85 {
                score -= 14
                factors.append(String(format: "Resting HR %.0f bpm is elevated.", rhr))
            } else if rhr >= 75 {
                score -= 4
                factors.append(String(format: "Resting HR %.0f bpm a bit high for recovery.", rhr))
            } else {
                factors.append(String(format: "Resting HR %.0f bpm.", rhr))
            }
        }

        let heavyWorkout =
            (lastWorkoutDurationMinutes ?? 0) >= 75
            || (lastWorkoutKcal ?? 0) >= 600
            || workoutCountLast24h >= 2
        if heavyWorkout {
            signals += 1
            score -= 8
            factors.append("Recent workout load looks meaningful; bias toward recovery.")
        }

        guard signals >= 2 else {
            return RecoveryLoadHeuristic(
                band: .unknown,
                score0to100: nil,
                factors: factors.isEmpty
                    ? ["Not enough sleep / HRV / RHR / load signals for a recovery band."]
                    : factors,
                summaryLine: "Recovery heuristic: unknown (thin data). Not a diagnosis."
            )
        }

        let clamped = Int(min(100, max(0, score)).rounded())
        let band: RecoveryLoadHeuristic.Band
        if clamped >= 70 {
            band = .green
        } else if clamped >= 45 {
            band = .yellow
        } else {
            band = .red
        }
        return RecoveryLoadHeuristic(
            band: band,
            score0to100: clamped,
            factors: factors,
            summaryLine: String(
                format: "Recovery heuristic: %@ (score %d/100). Transparent coaching band only, not a diagnosis.",
                band.rawValue,
                clamped
            )
        )
    }

    // MARK: - Pre-sleep HR

    /// Elevated if avg pre-sleep HR ≥ RHR + delta, or ≥ absolute floor.
    /// When overnight HRV is clearly depressed vs 7d median, treat borderline HR as elevated.
    static func isPreSleepHRElevated(
        averageBpm: Double,
        restingBpm: Double?,
        aboveRestingDelta: Double,
        absoluteFloorBpm: Double,
        hrvSDNNMs: Double?,
        hrvMedian7dMs: Double?
    ) -> Bool {
        let vsResting: Bool = {
            guard let restingBpm else { return false }
            return averageBpm >= restingBpm + aboveRestingDelta
        }()
        let absolute = averageBpm >= absoluteFloorBpm
        let hrvDepressed: Bool = {
            guard let hrv = hrvSDNNMs, let median = hrvMedian7dMs, median > 0 else { return false }
            // Borderline HR (within 5 bpm of absolute floor) + HRV < 70% median → flag.
            return hrv / median < 0.7 && averageBpm >= absoluteFloorBpm - 5
        }()
        return vsResting || absolute || hrvDepressed
    }

    // MARK: - Watch wear

    /// Movement without HR → likely not wearing Watch.
    /// Movement = steps, workouts, active energy, or meaningful walking/running distance.
    static func isWatchLikelyNotWorn(
        stepsToday: Double?,
        workoutCountLast24h: Int,
        activeEnergyKcalToday: Double?,
        distanceKmLast24h: Double?,
        heartRateSampleCountToday: Int,
        minSteps: Double,
        minHRSamples: Int,
        minDistanceKm: Double = 2.0
    ) -> Bool {
        let moved =
            (stepsToday ?? 0) >= minSteps
            || workoutCountLast24h > 0
            || (activeEnergyKcalToday ?? 0) >= 150
            || (distanceKmLast24h ?? 0) >= minDistanceKm
        return moved && heartRateSampleCountToday < minHRSamples
    }
}

/// Raw ints mirroring `HKCategoryValueSleepAnalysis` so unit tests do not need HealthKit.
///
/// Apple: inBed=0, asleepUnspecified(=legacy asleep)=1, awake=2, core=3, deep=4, REM=5.
enum HKCategoryValueSleepAnalysisProxy {
    static let inBed = 0
    static let asleepUnspecified = 1
    static let legacyAsleep = 1
    static let awake = 2
    static let asleepCore = 3
    static let asleepDeep = 4
    static let asleepREM = 5
}
