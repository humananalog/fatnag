import XCTest
@testable import TheScale

final class HealthScienceMathTests: XCTestCase {
    func testSleepSnapshotStagesAndConsistency() {
        let cal = Calendar(identifier: .gregorian)
        let components = DateComponents(year: 2026, month: 9, day: 20, hour: 10)
        let now = cal.date(from: components)!

        // Night waking on Sep 20: onset 23:00 Sep 19, stages through morning.
        let onset = cal.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 23))!
        let coreEnd = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 1))!
        let deepEnd = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 2))!
        let remEnd = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 3))!
        let awakeEnd = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 3, minute: 20))!
        let finalEnd = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 7))!

        var samples: [(value: Int, start: Date, end: Date)] = [
            (HKCategoryValueSleepAnalysisProxy.asleepCore, onset, coreEnd),
            (HKCategoryValueSleepAnalysisProxy.asleepDeep, coreEnd, deepEnd),
            (HKCategoryValueSleepAnalysisProxy.asleepREM, deepEnd, remEnd),
            (HKCategoryValueSleepAnalysisProxy.awake, remEnd, awakeEnd),
            (HKCategoryValueSleepAnalysisProxy.asleepCore, awakeEnd, finalEnd)
        ]

        // Two prior nights with different bedtimes for consistency.
        for day in [17, 18] {
            let o = cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 22, minute: 30))!
            let w = cal.date(from: DateComponents(year: 2026, month: 9, day: day + 1, hour: 6, minute: 30))!
            samples.append((HKCategoryValueSleepAnalysisProxy.asleepUnspecified, o, w))
        }

        let snap = HealthScienceMath.buildSleepSnapshot(samples: samples, now: now, calendar: cal)
        XCTAssertEqual(snap.totalAsleepHours ?? 0, 7.666, accuracy: 0.05)
        XCTAssertNotNil(snap.stages)
        XCTAssertEqual(snap.stages?.deepHours ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(snap.stages?.remHours ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(snap.stages?.awakeHours ?? 0, 1.0 / 3.0, accuracy: 0.02)
        XCTAssertGreaterThanOrEqual(snap.nightsSampled, 3)
        XCTAssertNotNil(snap.bedtimeConsistencyStdDevHours)
        XCTAssertNotNil(snap.averageAsleepHours7d)
    }

    func testBedtimeConsistencyUnwrapsMidnight() throws {
        let cal = Calendar(identifier: .gregorian)
        let onsets = [
            cal.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 23, minute: 30))!,
            cal.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 0, minute: 15))!,
            cal.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 23, minute: 45))!
        ]
        let std = try XCTUnwrap(
            HealthScienceMath.bedtimeConsistencyStdDevHours(onsets: onsets, calendar: cal)
        )
        // ~45 min spread → std-dev well under 1 hour, not ~11h.
        XCTAssertLessThan(std, 1.0)
    }

    func testRecoveryHeuristicGreenVsRed() {
        let green = HealthScienceMath.recoveryHeuristic(
            sleepHours: 7.5,
            stages: SleepStageHours(coreHours: 4, deepHours: 1.2, remHours: 1.5, awakeHours: 0.3, unspecifiedAsleepHours: nil),
            hrvSDNNMs: 55,
            hrvMedian7dMs: 50,
            restingHRBpm: 58,
            workoutCountLast24h: 0,
            lastWorkoutDurationMinutes: nil,
            lastWorkoutKcal: nil
        )
        XCTAssertEqual(green.band, .green)
        XCTAssertNotNil(green.score0to100)

        let red = HealthScienceMath.recoveryHeuristic(
            sleepHours: 4.5,
            stages: SleepStageHours(coreHours: 3, deepHours: 0.3, remHours: 0.5, awakeHours: 1.0, unspecifiedAsleepHours: nil),
            hrvSDNNMs: 18,
            hrvMedian7dMs: 45,
            restingHRBpm: 96,
            workoutCountLast24h: 2,
            lastWorkoutDurationMinutes: 90,
            lastWorkoutKcal: 700
        )
        XCTAssertEqual(red.band, .red)

        let thin = HealthScienceMath.recoveryHeuristic(
            sleepHours: 5.0,
            stages: nil,
            hrvSDNNMs: nil,
            hrvMedian7dMs: nil,
            restingHRBpm: nil,
            workoutCountLast24h: 0,
            lastWorkoutDurationMinutes: nil,
            lastWorkoutKcal: nil
        )
        XCTAssertEqual(thin.band, .unknown)
    }

    /// Apple Sleep ~98 caliber night must never be labeled red / bad recovery.
    func testStrongSleepNightNeverRedDespiteSecondaryPenalties() {
        let stages = SleepStageHours(
            coreHours: 4.2,
            deepHours: 1.1,
            remHours: 1.8,
            awakeHours: 0.25,
            unspecifiedAsleepHours: nil
        )
        let proxy = HealthScienceMath.sleepQualityProxyScore(sleepHours: 8.0, stages: stages)
        XCTAssertGreaterThanOrEqual(proxy ?? 0, 85)

        let recovery = HealthScienceMath.recoveryHeuristic(
            sleepHours: 8.0,
            stages: stages,
            hrvSDNNMs: 28,
            hrvMedian7dMs: 50,
            restingHRBpm: 78,
            workoutCountLast24h: 2,
            lastWorkoutDurationMinutes: 90,
            lastWorkoutKcal: 700
        )
        XCTAssertEqual(recovery.band, .green)
        XCTAssertGreaterThanOrEqual(recovery.score0to100 ?? 0, 78)
        XCTAssertFalse(recovery.summaryLine.lowercased().contains("bad"))
    }

    func testSolidSleepAloneIsGreenNotUnknown() {
        let recovery = HealthScienceMath.recoveryHeuristic(
            sleepHours: 7.4,
            stages: SleepStageHours(
                coreHours: 4,
                deepHours: 1.0,
                remHours: 1.4,
                awakeHours: 0.2,
                unspecifiedAsleepHours: nil
            ),
            hrvSDNNMs: nil,
            hrvMedian7dMs: nil,
            restingHRBpm: nil,
            workoutCountLast24h: 0,
            lastWorkoutDurationMinutes: nil,
            lastWorkoutKcal: nil
        )
        XCTAssertEqual(recovery.band, .green)
        XCTAssertNotNil(recovery.score0to100)
    }

    func testPreSleepHRUsesHRVBorderline() {
        let elevated = HealthScienceMath.isPreSleepHRElevated(
            averageBpm: 88,
            restingBpm: 60,
            aboveRestingDelta: 15,
            absoluteFloorBpm: 90,
            hrvSDNNMs: 20,
            hrvMedian7dMs: 40
        )
        XCTAssertTrue(elevated)

        let calm = HealthScienceMath.isPreSleepHRElevated(
            averageBpm: 70,
            restingBpm: 60,
            aboveRestingDelta: 15,
            absoluteFloorBpm: 90,
            hrvSDNNMs: 50,
            hrvMedian7dMs: 48
        )
        XCTAssertFalse(calm)
    }

    func testWatchWearUsesDistance() {
        let notWorn = HealthScienceMath.isWatchLikelyNotWorn(
            stepsToday: 500,
            workoutCountLast24h: 0,
            activeEnergyKcalToday: 40,
            distanceKmLast24h: 5.0,
            heartRateSampleCountToday: 2,
            minSteps: 2_000,
            minHRSamples: 8
        )
        XCTAssertTrue(notWorn)

        let worn = HealthScienceMath.isWatchLikelyNotWorn(
            stepsToday: 8_000,
            workoutCountLast24h: 0,
            activeEnergyKcalToday: 300,
            distanceKmLast24h: 4.0,
            heartRateSampleCountToday: 40,
            minSteps: 2_000,
            minHRSamples: 8
        )
        XCTAssertFalse(worn)
    }

    func testSafeLossRatePercentBand() {
        // 80 kg → ~0.56 kg/wk at 0.7%, within 0.25–1.0 clamp.
        let rate = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: 80)
        XCTAssertEqual(rate, 80 * 0.007, accuracy: 0.001)
        XCTAssertLessThanOrEqual(rate, 1.0)
        XCTAssertGreaterThanOrEqual(rate, 0.25)
    }
}
