import XCTest
@testable import TheScale

final class WeeklyGoalSurfaceTests: XCTestCase {
    func testProgressPercentAndCrushedBand() {
        var goal = WeeklyMiniGoal.default
        goal.targetDeltaKg = -0.4
        goal.weekStartKg = 84.0
        goal.weekStartDate = Date()
        // Moved -0.45 → past goal.
        let surface = WeeklyGoalSurfaceEngine.build(
            weeklyGoal: goal,
            currentKg: 83.55,
            profile: .default,
            digest: nil
        )
        XCTAssertGreaterThanOrEqual(surface.completionPercent, 100)
        XCTAssertEqual(surface.band, .crushed)
        XCTAssertFalse(surface.targets.intakeTracked)
        XCTAssertTrue(surface.targets.honestyLine.lowercased().contains("not logged"))
    }

    func testAtRiskWhenBehindPace() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        // Mid-week Thursday ~0.5 elapsed.
        let thursday = cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!
        var goal = WeeklyMiniGoal.default
        goal.targetDeltaKg = -0.5
        goal.weekStartKg = 90
        goal.weekStartDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 21))!
        // Only -0.05 moved (~10%) while ~half week gone → at risk.
        let surface = WeeklyGoalSurfaceEngine.build(
            weeklyGoal: goal,
            currentKg: 89.95,
            profile: .default,
            digest: nil,
            now: thursday,
            calendar: cal
        )
        XCTAssertEqual(surface.band, .atRisk)
        XCTAssertLessThan(surface.completionPercent, 40)
    }

    func testRecoveryRedTipsOnTrackToAtRisk() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let wednesday = cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 10))!
        var goal = WeeklyMiniGoal.default
        goal.targetDeltaKg = -0.4
        goal.weekStartKg = 80
        // ~40% progress mid-week → would be on track without recovery.
        let current = 80 - 0.16
        var digest = FitnessDigest.empty
        digest.access = .readable
        digest.recovery = RecoveryLoadHeuristic(
            band: .red,
            score0to100: 30,
            factors: ["test"],
            summaryLine: "red"
        )
        let surface = WeeklyGoalSurfaceEngine.build(
            weeklyGoal: goal,
            currentKg: current,
            profile: .default,
            digest: digest,
            now: wednesday,
            calendar: cal
        )
        XCTAssertEqual(surface.band, .atRisk)
    }

    func testDailyCaloriesFloorAndProteinScale() {
        let profile = UserBodyProfile(
            displayName: "Alex",
            heightCm: 175,
            ageYears: 35,
            sex: .male,
            idealWeightKg: 78,
            dietPreference: .omnivore
        )
        let targets = WeeklyGoalSurfaceEngine.dailyTargets(
            profile: profile,
            currentKg: 84,
            weeklyDeltaKg: -0.5,
            digest: nil,
            band: .onTrack
        )
        XCTAssertGreaterThan(targets.maxCalories, 1400)
        XCTAssertLessThan(targets.maxCalories, 3500)
        XCTAssertEqual(targets.proteinGrams, Int((84 * 1.8).rounded()))
        XCTAssertEqual(targets.microName, "Fiber")
        XCTAssertFalse(targets.intakeTracked)
    }

    func testVeganMicroIsIron() {
        let profile = UserBodyProfile(
            heightCm: 165,
            ageYears: 28,
            sex: .female,
            dietPreference: .vegan
        )
        let targets = WeeklyGoalSurfaceEngine.dailyTargets(
            profile: profile,
            currentKg: 62,
            weeklyDeltaKg: -0.2,
            digest: nil,
            band: .onTrack
        )
        XCTAssertEqual(targets.microName, "Iron")
    }

    func testTomorrowAdviceAvoidsEmDashAndNamesUser() {
        var goal = WeeklyMiniGoal.default
        goal.targetDeltaKg = -0.3
        goal.weekStartKg = 82
        let surface = WeeklyGoalSurfaceEngine.build(
            weeklyGoal: goal,
            currentKg: 81.9,
            profile: UserBodyProfile(
                displayName: "Alex",
                heightCm: 170,
                ageYears: 30,
                sex: .male
            ),
            digest: nil
        )
        XCTAssertTrue(surface.tomorrowAdvice.contains("Alex"))
        XCTAssertFalse(surface.tomorrowAdvice.contains("—"))
        XCTAssertFalse(surface.tomorrowAdvice.lowercased().contains("diagnos"))
    }

    func testUnknownBandWithoutBaseline() {
        let surface = WeeklyGoalSurfaceEngine.build(
            weeklyGoal: .default,
            currentKg: nil,
            profile: .default,
            digest: nil
        )
        XCTAssertEqual(surface.band, .unknown)
        XCTAssertEqual(surface.completionPercent, 0)
    }

    func testMifflinBMRMaleBallpark() {
        let profile = UserBodyProfile(heightCm: 178, ageYears: 30, sex: .male)
        let bmr = WeeklyGoalSurfaceEngine.mifflinBMR(profile: profile, weightKg: 80)
        // 10*80 + 6.25*178 - 5*30 + 5 = 800 + 1112.5 - 150 + 5 = 1767.5
        XCTAssertEqual(bmr, 1767.5, accuracy: 0.1)
    }
}
