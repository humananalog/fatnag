import XCTest
@testable import TheScale

final class CoachVoiceTests: XCTestCase {
    func testFemaleEnergyBudgetLeadsWithPlatesNotBareKcal() {
        let picture = CoachVoice.energyBudgetPhrase(
            kcal: 1343,
            diet: .omnivore,
            sex: .female
        )
        XCTAssertFalse(picture.contains("1343"))
        XCTAssertFalse(picture.lowercased().contains("kcal"))
        XCTAssertTrue(picture.contains("palm"))
        XCTAssertTrue(picture.contains("handful") || picture.contains("greens") || picture.contains("salad"))
    }

    func testMaleEnergyBudgetKeepsKcal() {
        let line = CoachVoice.energyBudgetPhrase(
            kcal: 1343,
            diet: .omnivore,
            sex: .male
        )
        XCTAssertTrue(line.contains("1343"))
        XCTAssertTrue(line.contains("kcal"))
    }

    func testFemaleProteinUsesPalmPicture() {
        let line = CoachVoice.proteinPhrase(grams: 92, diet: .vegan, sex: .female)
        XCTAssertFalse(line.contains("92 g"))
        XCTAssertTrue(line.contains("palm"))
        XCTAssertTrue(line.contains("tofu") || line.contains("chickpeas"))
    }

    func testFemaleChipsAvoidBareKcal() {
        let chips = WeeklyGoalSurfaceEngine.dailyTargetChips(
            targets: DailyGoalTargets(
                steps: 9000,
                maxCalories: 1343,
                proteinGrams: 90,
                proteinLabel: "Protein",
                microName: "Iron",
                microTargetLine: "Prioritize ≥ 18 mg with meals",
                intakeTracked: false
            ),
            showNutritionTargets: true,
            sex: .female,
            diet: .omnivore
        )
        let energy = chips.first { $0.title == "Energy" }?.valueLine ?? ""
        XCTAssertFalse(energy.contains("1343"))
        XCTAssertTrue(energy.contains("plates"))
    }

    func testFemaleAdviceUsesVisualFoodNotKcalHeadline() {
        var goal = WeeklyMiniGoal.default
        goal.title = "Soft Launch week"
        let targets = DailyGoalTargets(
            steps: 9000,
            maxCalories: 1343,
            proteinGrams: 90,
            proteinLabel: "Protein",
            microName: "Iron",
            microTargetLine: "Prioritize ≥ 18 mg with meals",
            intakeTracked: false
        )
        let advice = WeeklyGoalSurfaceEngine.todayAdvice(
            name: "Alex",
            band: .onTrack,
            weeklyGoal: goal,
            targets: targets,
            digest: nil,
            diet: .omnivore,
            energy: WeeklyEnergyBalanceSnapshot(
                diagnosis: .insufficientData,
                estimatedDailySpendKcal: nil,
                impliedDailyIntakeKcal: nil,
                isMeaningfullyActive: false,
                summaryLine: ""
            ),
            mealLine: "",
            sex: .female,
            unitSystem: .metric
        )
        XCTAssertTrue(advice.contains("Alex"))
        XCTAssertFalse(advice.contains("1343 kcal"))
        XCTAssertTrue(
            advice.contains("palm")
                || advice.contains("plates")
                || advice.contains("handful")
        )
        XCTAssertFalse(advice.contains("Operator"))
        XCTAssertFalse(advice.contains("ETA"))
    }

    func testFemaleMacroPaceLineAvoidsETAJargon() {
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
            sex: .female,
            unitSystem: .metric,
            now: now,
            calendar: cal
        )
        XCTAssertFalse(eta.line.contains("ETA"))
        XCTAssertTrue(eta.line.lowercased().contains("pace") || eta.line.contains("land"))
    }

    func testFemaleLLMRulesDemandFoodPictures() {
        let rules = CoachVoice.llmRules(sex: .female)
        XCTAssertTrue(rules.lowercased().contains("palm"))
        XCTAssertTrue(rules.lowercased().contains("1343") || rules.lowercased().contains("visual"))
        XCTAssertTrue(rules.lowercased().contains("nurtur") || rules.lowercased().contains("prais"))
        XCTAssertFalse(rules.contains("—"))
    }

    func testAgeBandsMapCorrectly() {
        XCTAssertEqual(CoachAgeBand.from(ageYears: 22), .earlyAdult)
        XCTAssertEqual(CoachAgeBand.from(ageYears: 29), .risingAdult)
        XCTAssertEqual(CoachAgeBand.from(ageYears: 38), .midAdult)
        XCTAssertEqual(CoachAgeBand.from(ageYears: 48), .established)
        XCTAssertEqual(CoachAgeBand.from(ageYears: 60), .mature)
        XCTAssertEqual(CoachAgeBand.from(ageYears: 72), .senior)
    }

    func testLLMRulesAreAgeSensitive() {
        let young = CoachVoice.llmRules(sex: .male, ageYears: 22)
        let senior = CoachVoice.llmRules(sex: .male, ageYears: 70)
        XCTAssertTrue(young.contains("Gen Z") || young.contains("early adult"))
        XCTAssertTrue(senior.contains("senior") || senior.lowercased().contains("infantilizing"))
        XCTAssertNotEqual(young, senior)
    }

    func testCulturePayloadUsesLocationAndAge() {
        let payload = CoachVoice.cultureInsightPayload(
            ageYears: 42,
            location: "Hong Kong",
            ethnicity: "French",
            culturalVibe: "American sitcom humour"
        )
        XCTAssertTrue(payload.contains("Hong Kong"))
        XCTAssertTrue(payload.contains("French"))
        XCTAssertTrue(payload.contains("42"))
        XCTAssertTrue(payload.contains("millennial") || payload.contains("mid adult"))
        XCTAssertTrue(payload.contains("American sitcom"))
    }

    func testPersonaBlockIncludesAgeAndCulturePayload() {
        var profile = UserBodyProfile.default
        profile.ageYears = 42
        profile.location = "Hong Kong"
        profile.ethnicity = "French"
        profile.culturalVibe = "Cha chaan teng + dry humour"
        let block = profile.coachPersonaBlock
        XCTAssertTrue(block.contains("Age: 42"))
        XCTAssertTrue(block.contains("Hong Kong"))
        XCTAssertTrue(block.contains("CULTURE / ORIGIN PAYLOAD"))
        XCTAssertTrue(block.contains("Cha chaan teng"))
    }
}
