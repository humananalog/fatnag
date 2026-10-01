import XCTest
@testable import TheScale

final class DreamOnboardingTests: XCTestCase {
    func testUnitConversionRoundTripPreservesCanonicalKg() {
        let kg = 78.4
        let lb = UnitFormat.mass(fromKg: kg, system: .imperial)
        let back = UnitFormat.kg(fromMass: lb, system: .imperial)
        XCTAssertEqual(back, kg, accuracy: 0.05)

        let cm = 175.0
        let inches = UnitFormat.height(fromCm: cm, system: .imperial)
        XCTAssertEqual(UnitFormat.cm(fromHeight: inches, system: .imperial), cm, accuracy: 0.05)
    }

    @MainActor
    func testLiveUnitToggleDoesNotRewriteCanonicalStorage() {
        let flow = OnboardingFlowModel()
        flow.heightCm = 180
        flow.currentWeightKg = 90
        flow.idealKg = 80
        flow.applyUnitSystem(.imperial)
        XCTAssertEqual(flow.heightCm, 180, accuracy: 0.01)
        XCTAssertEqual(flow.currentWeightKg, 90, accuracy: 0.01)
        XCTAssertEqual(flow.idealKg, 80, accuracy: 0.01)
        XCTAssertEqual(flow.unitSystem, .imperial)
        flow.applyUnitSystem(.metric)
        XCTAssertEqual(flow.unitSystem, .metric)
    }

    func testImpossiblePace10kgInOneWeekIsRejected() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 22))!
        let date = cal.date(byAdding: .day, value: 7, to: now)!
        let verdict = GoalPaceGuard.evaluate(
            currentKg: 90,
            targetKg: 80,
            goalDate: date,
            now: now,
            calendar: cal
        )
        XCTAssertEqual(verdict.status, .rejected)
        XCTAssertNotNil(verdict.earliestFeasibleDate)
        XCTAssertTrue(verdict.keelNote.lowercased().contains("keel") || verdict.keelNote.lowercased().contains("safe"))
        XCTAssertFalse(verdict.keelNote.contains("\u{2014}"))
        XCTAssertFalse(verdict.keelNote.contains("\u{2013}"))
    }

    func testFeasiblePaceIsAccepted() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 22))!
        let date = cal.date(byAdding: .day, value: 120, to: now)!
        let verdict = GoalPaceGuard.evaluate(
            currentKg: 90,
            targetKg: 80,
            goalDate: date,
            now: now,
            calendar: cal
        )
        XCTAssertEqual(verdict.status, .accepted)
    }

    func testMaleDifficultyBandsClimbWithIntensity() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 22))!
        let softDate = cal.date(byAdding: .day, value: 200, to: now)!
        let hardDate = cal.date(byAdding: .day, value: 70, to: now)!
        let soft = GoalDifficultyFlavor.rate(
            sex: .male,
            currentKg: 92,
            targetKg: 82,
            goalDate: softDate,
            now: now,
            calendar: cal
        )
        let hard = GoalDifficultyFlavor.rate(
            sex: .male,
            currentKg: 92,
            targetKg: 82,
            goalDate: hardDate,
            now: now,
            calendar: cal
        )
        XCTAssertEqual(GoalDifficultyFlavor.maleTitles[soft.level], soft.title)
        XCTAssertTrue(GoalDifficultyFlavor.maleTitles.contains(soft.title))
        XCTAssertGreaterThanOrEqual(hard.level, soft.level)
        XCTAssertTrue(soft.revealLine.contains(soft.title))
    }

    func testFemaleDifficultyUsesPopLadder() {
        let band = GoalDifficultyFlavor.band(sex: .female, level: 3, ratio: 0.9)
        XCTAssertEqual(band.title, "Brat Mode")
        XCTAssertTrue(band.revealLine.contains("Brat Mode"))
        XCTAssertTrue(GoalDifficultyFlavor.femaleTitles.contains("Icon Status"))
    }

    @MainActor
    func testBuildProfilePersistsDreamAndAnatomyFields() {
        let flow = OnboardingFlowModel()
        flow.name = "Alex"
        flow.sex = .male
        flow.ageYears = 35
        flow.heightCm = 178
        flow.currentWeightKg = 92
        flow.startingBodyFatPercent = 24
        flow.healthContextNotes = "Knee tweak, weekend wine"
        flow.idealKg = 82
        let cal = Calendar.current
        flow.goalDate = cal.date(byAdding: .month, value: 4, to: Date())!
        flow.refreshPaceAndDifficulty()
        let profile = flow.buildProfile()
        XCTAssertEqual(profile.startingWeightKg, 92)
        XCTAssertEqual(profile.startingBodyFatPercent, 24)
        XCTAssertEqual(profile.healthContextNotes, "Knee tweak, weekend wine")
        XCTAssertEqual(profile.idealWeightKg, 82)
        XCTAssertNotNil(profile.goalDate)
        XCTAssertNotNil(profile.goalDifficultyTitle)
        let weekly = flow.buildWeeklyMiniGoal()
        XCTAssertEqual(weekly.weekStartKg, 92)
        XCTAssertNotEqual(weekly.targetDeltaKg, 0, accuracy: 0.0001)
    }

    @MainActor
    func testAgeBoundsAreEighteenToOneHundred() {
        let flow = OnboardingFlowModel()
        flow.ageYears = 17
        XCTAssertFalse(flow.isAdultAge)
        flow.ageYears = 18
        XCTAssertTrue(flow.isAdultAge)
        flow.ageYears = 100
        XCTAssertTrue(flow.isAdultAge)
        flow.ageYears = 101
        XCTAssertFalse(flow.isAdultAge)
        XCTAssertEqual(UserBodyProfile.maximumAgeYears, 100)
    }
}

final class DailyMetricProgressTests: XCTestCase {
    func testStepsProgressCompletesAtTarget() {
        var digest = FitnessDigest.empty
        digest.stepsToday = 9000
        digest.activeEnergyKcalToday = 400
        let targets = DailyGoalTargets(
            steps: 8500,
            maxCalories: 2200,
            proteinGrams: 140,
            proteinLabel: "Protein",
            microName: "Fiber",
            microTargetLine: "Hit ≥ 30 g · keeps the cut sane",
            intakeTracked: false
        )
        let rows = WeeklyGoalSurfaceEngine.todayMetricProgress(targets: targets, digest: digest)
        // No robust nutrition: activity gauges only (steps + move).
        XCTAssertEqual(rows.count, 2)
        let steps = rows.first { $0.kind == .steps }
        XCTAssertEqual(steps?.status, .complete)
        XCTAssertGreaterThanOrEqual(steps?.fraction ?? 0, 1)
        let move = rows.first { $0.kind == .energy }
        XCTAssertEqual(move?.title, "Move")
        XCTAssertEqual(move?.status, .inProgress)
        XCTAssertGreaterThan(move?.fraction ?? 0, 0.5)
        XCTAssertNil(rows.first { $0.kind == .protein })
    }

    func testNutritionProgressWhenLogged() {
        var digest = FitnessDigest.empty
        digest.stepsToday = 3000
        digest.activeEnergyKcalToday = 200
        digest.dietaryEnergyKcalToday = 1800
        digest.dietaryProteinGramsToday = 120
        digest.dietaryFiberGramsToday = 28
        let targets = DailyGoalTargets(
            steps: 8500,
            maxCalories: 2000,
            proteinGrams: 140,
            proteinLabel: "Protein",
            microName: "Fiber",
            microTargetLine: "Hit ≥ 30 g",
            intakeTracked: true
        )
        let rows = WeeklyGoalSurfaceEngine.todayMetricProgress(targets: targets, digest: digest)
        XCTAssertEqual(rows.first { $0.kind == .energy }?.title, "Energy")
        XCTAssertEqual(rows.first { $0.kind == .energy }?.status, .complete)
        XCTAssertEqual(rows.first { $0.kind == .protein }?.status, .inProgress)
        XCTAssertEqual(rows.first { $0.kind == .micro }?.status, .inProgress)
        XCTAssertGreaterThan(rows.first { $0.kind == .micro }?.fraction ?? 0, 0.8)
    }

    func testOverCalorieBudgetMarksOver() {
        var digest = FitnessDigest.empty
        digest.dietaryEnergyKcalToday = 2600
        digest.dietaryProteinGramsToday = 80
        let targets = DailyGoalTargets(
            steps: 8000,
            maxCalories: 2000,
            proteinGrams: 120,
            proteinLabel: "Protein",
            microName: "Iron",
            microTargetLine: "Prioritize ≥ 18 mg with meals",
            intakeTracked: true
        )
        let energy = WeeklyGoalSurfaceEngine.todayMetricProgress(targets: targets, digest: digest)
            .first { $0.kind == .energy }
        XCTAssertEqual(energy?.status, .over)
    }

    func testMicroNumericTargetParsesCommaThousands() {
        let value = WeeklyGoalSurfaceEngine.microNumericTarget(
            name: "Potassium",
            line: "Aim ≥ 3,500 mg from food"
        )
        XCTAssertEqual(value, 3500)
    }

    func testSurfaceUsesTargetsNotNutritionGaugesWithoutFoodLog() {
        var digest = FitnessDigest.empty
        digest.stepsToday = 1000
        digest.activeEnergyKcalToday = 120
        var goal = WeeklyMiniGoal.default
        goal.weekStartKg = 80
        goal.weekStartDate = Date()
        goal.title = "Sunday 79.70 kg"
        goal.targetDeltaKg = -0.3
        let surface = WeeklyGoalSurfaceEngine.build(
            weeklyGoal: goal,
            currentKg: 79.8,
            profile: .default,
            digest: digest
        )
        XCTAssertFalse(surface.targets.intakeTracked)
        XCTAssertEqual(surface.todayProgress.count, 2)
        XCTAssertEqual(surface.todayProgress.map(\.kind), [.steps, .energy])
        XCTAssertEqual(surface.dailyTargetChips.count, 3)
        XCTAssertTrue(surface.dailyTargetChips.map(\.title).contains("Energy"))
        XCTAssertTrue(surface.dailyTargetChips.map(\.title).contains("Protein"))
        // Live week-start + delta wins (80 - 0.3), not a conflicting display.
        XCTAssertEqual(surface.sundayTargetKg ?? -1, 79.70, accuracy: 0.01)
        XCTAssertEqual(surface.weeklyDeltaKg, -0.3, accuracy: 0.001)
    }

    func testSundayTargetParsesTitleAndFallsBackToWeekStart() {
        var titled = WeeklyMiniGoal.default
        titled.title = "Sunday 82.40 kg"
        titled.weekStartKg = nil
        titled.targetDeltaKg = 0
        XCTAssertEqual(
            WeeklyGoalSurfaceEngine.sundayTargetKg(from: titled, currentKg: 83.0) ?? -1,
            82.40,
            accuracy: 0.01
        )

        var untitled = WeeklyMiniGoal.default
        untitled.title = "Nudge -0.3 kg this week"
        untitled.weekStartKg = 84.0
        untitled.targetDeltaKg = -0.5
        XCTAssertEqual(
            WeeklyGoalSurfaceEngine.sundayTargetKg(from: untitled, currentKg: 84.0) ?? -1,
            83.50,
            accuracy: 0.01
        )
    }

    func testSundayTargetPrefersWeekMathOverStaleTitle() {
        var goal = WeeklyMiniGoal.default
        goal.weekStartKg = 93.7
        goal.targetDeltaKg = -0.66
        goal.title = "Sunday 87.38 kg" // stale / impossible; must not win
        XCTAssertEqual(
            WeeklyGoalSurfaceEngine.sundayTargetKg(from: goal, currentKg: 93.7) ?? -1,
            93.04,
            accuracy: 0.01
        )
    }

    func testParseSundayKgIgnoresOtherKgTokensInPacingLine() {
        let pacing = "-0.66 kg/wk toward 80.5 kg by Dec 22, 2026 → Sunday 93.04 kg. Aggressive."
        XCTAssertEqual(WeeklyGoalSurfaceEngine.parseSundayKg(from: pacing) ?? -1, 93.04, accuracy: 0.01)
        XCTAssertNil(WeeklyGoalSurfaceEngine.parseSundayKg(from: "Nudge -0.3 kg this week"))
    }

    func testAlexScenarioSundayIsSafeCapNotSixKg() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 10))!
        let goalDate = cal.date(from: DateComponents(year: 2026, month: 12, day: 22))!
        let hit = AggressiveWeeklyTargetEngine.compute(
            currentKg: 93.7,
            idealKg: 80.5,
            goalDate: goalDate,
            priorSundayTargetKg: nil,
            now: now,
            calendar: cal
        )
        let safe = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: 93.7)
        XCTAssertEqual(abs(hit.weeklyDeltaKg), safe, accuracy: 0.02)
        XCTAssertEqual(hit.sundayTargetKg, 93.7 - safe, accuracy: 0.05)
        XCTAssertGreaterThan(hit.sundayTargetKg, 92.5)
        XCTAssertLessThan(abs(hit.weeklyDeltaKg), 1.05)
    }

    func testRobustNutritionRequiresRealMealSignal() {
        var weak = FitnessDigest.empty
        weak.dietaryEnergyKcalToday = 80
        weak.dietaryProteinGramsToday = 5
        XCTAssertFalse(WeeklyGoalSurfaceEngine.hasRobustNutritionLog(digest: weak))

        var strong = FitnessDigest.empty
        strong.dietaryEnergyKcalToday = 900
        strong.dietaryProteinGramsToday = 40
        XCTAssertTrue(WeeklyGoalSurfaceEngine.hasRobustNutritionLog(digest: strong))
    }

    func testHomeMetricsApplyFillsGaugeRows() {
        var digest = FitnessDigest.empty
        digest.applyHomeDailyMetrics(
            HomeDailyMetrics(
                stepsToday: 4200,
                activeEnergyKcalToday: 380,
                dietaryEnergyKcalToday: 0,
                dietaryProteinGramsToday: 0,
                dietaryFiberGramsToday: 0,
                dietaryIronMgToday: 0,
                dietaryPotassiumMgToday: 0,
                generatedAt: Date()
            )
        )
        XCTAssertEqual(digest.stepsToday, 4200)
        XCTAssertEqual(digest.activeEnergyKcalToday, 380)
        XCTAssertNil(digest.dietaryEnergyKcalToday)

        let targets = DailyGoalTargets(
            steps: 8500,
            maxCalories: 2200,
            proteinGrams: 140,
            proteinLabel: "Protein",
            microName: "Fiber",
            microTargetLine: "Hit ≥ 30 g",
            intakeTracked: false
        )
        let rows = WeeklyGoalSurfaceEngine.todayMetricProgress(targets: targets, digest: digest)
        XCTAssertEqual(rows.first { $0.kind == .steps }?.status, .inProgress)
        XCTAssertGreaterThan(rows.first { $0.kind == .steps }?.fraction ?? 0, 0.4)
        XCTAssertEqual(rows.first { $0.kind == .energy }?.title, "Move")
        XCTAssertEqual(rows.first { $0.kind == .energy }?.status, .inProgress)
        XCTAssertEqual(
            WeeklyGoalSurfaceEngine.dailyTargetChips(targets: targets, showNutritionTargets: true).count,
            3
        )
    }

    func testZeroStepsAfterHomeRefreshIsNotUnknown() {
        var digest = FitnessDigest.empty
        digest.applyHomeDailyMetrics(.zero)
        let targets = DailyGoalTargets(
            steps: 8000,
            maxCalories: 2000,
            proteinGrams: 120,
            proteinLabel: "Protein",
            microName: "Fiber",
            microTargetLine: "Hit ≥ 30 g",
            intakeTracked: false
        )
        let steps = WeeklyGoalSurfaceEngine.todayMetricProgress(targets: targets, digest: digest)
            .first { $0.kind == .steps }
        XCTAssertEqual(steps?.status, .inProgress)
        XCTAssertEqual(steps?.fraction ?? -1, 0, accuracy: 0.001)
        XCTAssertTrue(steps?.currentLine.contains("0") == true)
    }

    @MainActor
    func testReplayOnboardingKeepsSavedAnswers() {
        let prior = OnboardingStore.hasCompleted
        defer { OnboardingStore.hasCompleted = prior }
        OnboardingStore.hasCompleted = true
        var profile = UserBodyProfile.default
        profile.displayName = "Alex"
        profile.heightCm = 175
        profile.ageYears = 35
        profile.sex = .male
        profile.idealWeightKg = 78
        let flow = OnboardingFlowModel()
        flow.seed(from: profile, notifications: .default, units: .metric)
        XCTAssertEqual(flow.name, "Alex")
        XCTAssertEqual(flow.heightCm, 175, accuracy: 0.01)
        XCTAssertEqual(flow.ageYears, 35, accuracy: 0.01)
        XCTAssertEqual(flow.sex, .male)
        XCTAssertEqual(flow.idealKg, 78, accuracy: 0.01)
        XCTAssertEqual(flow.step, .language)
    }

    func testSettingsSearchFindsHeight() {
        let hits = SettingsSearchCatalog.matches("height", in: SettingsSearchCatalog.hits)
        XCTAssertEqual(hits.map(\.id), ["settings.height"])
        XCTAssertTrue(SettingsSearchCatalog.matches("zzzz", in: SettingsSearchCatalog.hits).isEmpty)
        XCTAssertEqual(
            SettingsSearchCatalog.matches("redo onboarding", in: SettingsSearchCatalog.hits).map(\.id),
            ["settings.profile"]
        )
    }
}
