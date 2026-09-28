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

    func testLocaleRulesRequireTargetLanguageAndBanRacistJokes() {
        var profile = UserBodyProfile.default
        profile.preferredLanguage = "Tagalog"
        profile.location = "Manila"
        profile.ethnicity = "Filipina"
        profile.culturalVibe = "straight talk"
        profile.useLocalContext = true
        let locale = CoachLocaleContext.resolve(profile: profile, appLanguage: .system)
        XCTAssertEqual(locale.replyLanguageName, "Tagalog")
        let rules = CoachVoice.llmRules(sex: .male, locale: locale)
        XCTAssertTrue(rules.contains("Tagalog"))
        XCTAssertTrue(rules.contains("Manila"))
        XCTAssertTrue(rules.lowercased().contains("local humour") || rules.lowercased().contains("vulgar"))
        XCTAssertTrue(rules.lowercased().contains("racist") || rules.lowercased().contains("hard ban"))
        XCTAssertTrue(rules.lowercased().contains("never"))
        let banner = CoachVoice.bannerRules(sex: .female, locale: locale)
        XCTAssertTrue(banner.contains("Tagalog"))
        XCTAssertTrue(banner.lowercased().contains("hard ban"))
    }

    func testAppLanguageOverridesPreferredLanguageForReply() {
        var profile = UserBodyProfile.default
        profile.preferredLanguage = "English"
        profile.location = "Paris"
        let locale = CoachLocaleContext.resolve(profile: profile, appLanguage: .french)
        XCTAssertEqual(locale.replyLanguageName, AppLanguage.french.profileLanguageName)
        XCTAssertTrue(CoachVoice.llmRules(sex: .male, locale: locale).contains(locale.replyLanguageName))
    }
}
