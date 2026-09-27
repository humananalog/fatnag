import XCTest
import UIKit
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
        XCTAssertEqual(surface.weekStartKg ?? -1, 84.0, accuracy: 0.01)
        XCTAssertEqual(surface.sundayTargetKg ?? -1, 83.60, accuracy: 0.01)
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

    func testTodayAdviceAvoidsEmDashAndNamesUser() {
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
        XCTAssertTrue(surface.todayAdvice.contains("Alex"))
        XCTAssertFalse(surface.todayAdvice.contains("—"))
        XCTAssertFalse(surface.todayAdvice.lowercased().contains("diagnos"))
        XCTAssertFalse(surface.todayAdvice.lowercased().contains("tomorrow"))
        XCTAssertFalse(surface.macroGoalETA.line.isEmpty)
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
        XCTAssertTrue(surface.todayAdvice.lowercased().contains("act together")
                      || surface.todayAdvice.lowercased().contains("intake"))
        XCTAssertTrue(surface.todayAdvice.lowercased().contains("meal plan"))
        XCTAssertFalse(surface.todayAdvice.contains("8600"))
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

    func testMacroGoalETAUsesObservedPace() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 8))!
        let weights = [
            HealthWeightSample(weightKg: 84.0, date: cal.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 8))!),
            HealthWeightSample(weightKg: 83.0, date: now)
        ]
        let eta = MacroGoalETA.compute(
            currentKg: 83.0,
            idealKg: 78.0,
            plannedDate: cal.date(from: DateComponents(year: 2026, month: 12, day: 1))!,
            recentWeights: weights,
            weeklyDeltaKg: -0.3,
            now: now,
            calendar: cal
        )
        XCTAssertNotNil(eta.etaDate)
        XCTAssertTrue(eta.line.contains("ETA"))
        XCTAssertFalse(eta.line.contains("—"))
    }

    func testWeighInAnalysisSergeantOnGainWhileCutting() {
        var goal = WeeklyMiniGoal.default
        goal.targetDeltaKg = -0.4
        let card = WeighInAnalysisEngine.build(
            name: "Alex",
            weighedKg: 84.5,
            previousKg: 84.0,
            weeklyGoal: goal,
            idealKg: 78,
            profile: .default
        )
        XCTAssertEqual(card.tone, .sergeant)
        XCTAssertTrue(card.headline.contains("Alex") || card.body.lowercased().contains("kg"))
        XCTAssertFalse(card.body.contains("—"))
        XCTAssertFalse(card.body.lowercased().contains("diagnos"))
        XCTAssertFalse(card.popLine.isEmpty)
    }

    func testWeighInHeroEncourageOnSolidCut() {
        var goal = WeeklyMiniGoal.default
        goal.targetDeltaKg = -0.4
        var profile = UserBodyProfile.default
        profile.culturalVibe = "Filipina in Manila"
        let card = WeighInAnalysisEngine.build(
            name: "Alex",
            weighedKg: 83.5,
            previousKg: 84.0,
            weeklyGoal: goal,
            idealKg: 78,
            profile: profile
        )
        XCTAssertEqual(card.tone, .encourage)
        XCTAssertFalse(card.popLine.isEmpty)
        XCTAssertFalse(card.popLine.contains("—"))
    }

    func testWeighInHeroSkepticalWhenFlat() {
        var goal = WeeklyMiniGoal.default
        goal.targetDeltaKg = -0.3
        let card = WeighInAnalysisEngine.build(
            name: "Alex",
            weighedKg: 84.05,
            previousKg: 84.0,
            weeklyGoal: goal,
            idealKg: 78
        )
        XCTAssertEqual(card.tone, .skeptical)
        XCTAssertEqual(card.tone.badge(sex: .male), "SIDE-EYE")
        XCTAssertEqual(card.tone.badge(sex: .female), "CURIOUS")
    }
    func testAtmosphereGreenOnTrackLimeAhead() {
        let on = WeeklyGoalAtmosphere.forBand(.onTrack, colorScheme: .light)
        let ahead = WeeklyGoalAtmosphere.forBand(.ahead, colorScheme: .light)
        let crushed = WeeklyGoalAtmosphere.forBand(.crushed, colorScheme: .light)
        // Green family for on-track; lime (high green + elevated red) for ahead/crushed.
        let onUI = UIColor(on.mid)
        let aheadUI = UIColor(ahead.mid)
        var or = CGFloat(0), og = CGFloat(0), ob = CGFloat(0), oa = CGFloat(0)
        var ar = CGFloat(0), ag = CGFloat(0), ab = CGFloat(0), aa = CGFloat(0)
        XCTAssertTrue(onUI.getRed(&or, green: &og, blue: &ob, alpha: &oa))
        XCTAssertTrue(aheadUI.getRed(&ar, green: &ag, blue: &ab, alpha: &aa))
        XCTAssertGreaterThan(og, or)
        XCTAssertGreaterThan(og, ob)
        XCTAssertGreaterThan(ag, ab)
        XCTAssertGreaterThan(ar, or) // lime pulls more yellow/red than pure green
        XCTAssertEqual(ahead.accent, crushed.accent)
    }

    func testWeekElapsedUsesMondayAnchorEvenOnSundayFirstCalendar() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 1 // US-style Sunday week must not skew Mon→Sun pace.
        let mondayMorning = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 1))!
        let thursdayNoon = cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!
        let early = WeeklyGoalSurfaceEngine.weekElapsedFraction(now: mondayMorning, calendar: cal)
        let mid = WeeklyGoalSurfaceEngine.weekElapsedFraction(now: thursdayNoon, calendar: cal)
        XCTAssertLessThan(early, 0.05)
        XCTAssertGreaterThan(mid, 0.45)
        XCTAssertLessThan(mid, 0.55)
    }

    func testMondayFreshFocusesPlanNotLastWeekWin() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 8))!
        var goal = WeeklyMiniGoal.default
        goal.targetDeltaKg = -0.65
        goal.weekStartKg = 89.35
        goal.weekStartDate = monday
        let surface = WeeklyGoalSurfaceEngine.build(
            weeklyGoal: goal,
            currentKg: 89.35,
            profile: .default,
            digest: nil,
            now: monday,
            calendar: cal
        )
        XCTAssertEqual(surface.weekMoment, .mondayFresh)
        XCTAssertEqual(surface.statusHeadline, "This week's plan")
        XCTAssertEqual(surface.weeklyDeltaKg, -0.65, accuracy: 0.001)
        XCTAssertEqual(surface.movedDeltaKg ?? 99, 0, accuracy: 0.01)
        XCTAssertEqual(surface.completionPercent, 0)
        XCTAssertFalse(surface.isWinnerWeek)
        XCTAssertNotEqual(surface.band, .crushed)
    }

    func testWinnerRequiresMovedNotJustNegativePlan() {
        XCTAssertFalse(
            WeeklyGoalSurfaceEngine.isWinnerWeek(
                movedDeltaKg: 0,
                targetDeltaKg: -0.65,
                band: .onTrack,
                moment: .midWeek
            )
        )
        XCTAssertTrue(
            WeeklyGoalSurfaceEngine.isWinnerWeek(
                movedDeltaKg: -0.66,
                targetDeltaKg: -0.65,
                band: .crushed,
                moment: .lateWeek
            )
        )
        XCTAssertFalse(
            WeeklyGoalSurfaceEngine.isWinnerWeek(
                movedDeltaKg: -0.66,
                targetDeltaKg: -0.65,
                band: .crushed,
                moment: .mondayFresh
            )
        )
    }
}
