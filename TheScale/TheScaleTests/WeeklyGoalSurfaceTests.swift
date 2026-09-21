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

    func testOvereatingWhileActiveBeatsStepAdvice() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 9))!
        var goal = WeeklyMiniGoal.default
        goal.targetDeltaKg = -0.5
        goal.weekStartKg = 84.0
        goal.weekStartDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 21))!
        goal.title = "Nudge -0.5 kg this week"

        var digest = FitnessDigest.empty
        digest.access = .readable
        digest.stepsToday = 9_200
        digest.activeEnergyKcalToday = 520
        digest.activeEnergyKcalLast7dAverage = 480

        // Flat weight over 4 days while cutting → overeating if active.
        let weights = [
            HealthWeightSample(weightKg: 84.0, date: cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 8))!),
            HealthWeightSample(weightKg: 84.05, date: cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 8))!),
            HealthWeightSample(weightKg: 84.1, date: now)
        ]

        let surface = WeeklyGoalSurfaceEngine.build(
            weeklyGoal: goal,
            currentKg: 84.1,
            profile: UserBodyProfile(displayName: "Alex", heightCm: 175, ageYears: 35, sex: .male),
            digest: digest,
            recentWeights: weights,
            now: now,
            calendar: cal
        )

        guard case .overeatingWhileActive = surface.energySnapshot?.diagnosis else {
            return XCTFail("expected overeatingWhileActive, got \(String(describing: surface.energySnapshot?.diagnosis))")
        }
        XCTAssertEqual(surface.band, .atRisk)
        XCTAssertTrue(surface.tomorrowAdvice.lowercased().contains("act together")
                      || surface.tomorrowAdvice.lowercased().contains("intake"))
        XCTAssertTrue(surface.tomorrowAdvice.lowercased().contains("meal plan"))
        XCTAssertFalse(surface.tomorrowAdvice.contains("8600"))
    }

    func testUnderMovingWhenSoftActivityAndStall() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 9))!
        var goal = WeeklyMiniGoal.default
        goal.targetDeltaKg = -0.4
        goal.weekStartKg = 90
        goal.weekStartDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 21))!

        var digest = FitnessDigest.empty
        digest.access = .readable
        digest.stepsToday = 1_800
        digest.activeEnergyKcalToday = 80
        digest.activeEnergyKcalLast7dAverage = 90

        let weights = [
            HealthWeightSample(weightKg: 90.0, date: cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 8))!),
            HealthWeightSample(weightKg: 90.1, date: now)
        ]

        let snap = WeeklyEnergyBalanceEvaluator.evaluate(
            profile: .default,
            weeklyGoal: goal,
            currentKg: 90.1,
            recentWeights: weights,
            digest: digest,
            targetMaxKcal: 2000,
            now: now,
            calendar: cal
        )
        guard case .underMoving = snap.diagnosis else {
            return XCTFail("expected underMoving, got \(snap.diagnosis)")
        }
        XCTAssertFalse(snap.isMeaningfullyActive)
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
