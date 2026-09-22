import XCTest
@testable import TheScale

final class MealPlanEngineTests: XCTestCase {
    func testCacheKeyChangesWithDeficitDietAndFasting() {
        let day = "2026-09-21"
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 7))!
        let a = MealPlanEngine.cacheKey(
            dayKey: day,
            maxKcal: 1800,
            proteinGrams: 140,
            diet: .omnivore,
            weeklyDeltaKg: -0.3,
            fasting: .none,
            now: morning,
            calendar: cal
        )
        let b = MealPlanEngine.cacheKey(
            dayKey: day,
            maxKcal: 1800,
            proteinGrams: 140,
            diet: .vegan,
            weeklyDeltaKg: -0.3,
            fasting: .none,
            now: morning,
            calendar: cal
        )
        let c = MealPlanEngine.cacheKey(
            dayKey: day,
            maxKcal: 1800,
            proteinGrams: 140,
            diet: .omnivore,
            weeklyDeltaKg: -0.3,
            fasting: .classic168,
            now: morning,
            calendar: cal
        )
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertTrue(c.contains("16-8"))
    }

    func testParseGrokJSONMeals() {
        let raw = """
        {"meals":[
          {"title":"Breakfast","time":"~8:00","ingredients":["Eggs","Spinach"],"macro":"Protein 32 g","micro":"Iron","kcal":380},
          {"title":"Lunch","time":"~12:30","ingredients":["Chicken","Greens"],"macro":"Protein 40 g","micro":"Fiber 8 g","kcal":450},
          {"title":"Dinner","time":"~19:00","ingredients":["Fish","Broccoli"],"macro":"Protein 38 g","micro":"Potassium","kcal":480}
        ]}
        """
        let meals = MealPlanEngine.parseGrokJSON(raw)
        XCTAssertEqual(meals?.count, 3)
        XCTAssertEqual(meals?.first?.title, "Breakfast")
        XCTAssertFalse(meals?.first?.ingredients.isEmpty ?? true)
    }

    func testParseRejectsEmDashBySanitize() {
        let raw = """
        {"meals":[
          {"title":"Breakfast","time":"~8:00","ingredients":["Eggs — spinach"],"macro":"Protein 30 g","micro":"Iron","kcal":350},
          {"title":"Lunch","time":"~12:30","ingredients":["Chicken"],"macro":"Protein 40 g","micro":"Fiber","kcal":400},
          {"title":"Dinner","time":"~19:00","ingredients":["Fish"],"macro":"Protein 35 g","micro":"Potassium","kcal":420}
        ]}
        """
        let meals = MealPlanEngine.parseGrokJSON(raw)
        XCTAssertEqual(meals?.count, 3)
        XCTAssertFalse(meals?.first?.ingredients.joined().contains("—") ?? true)
    }

    func testOfflinePlanCompleteness() {
        let plan = MealPlanEngine.offlinePlan(
            name: "Alex",
            diet: .pescatarian,
            maxKcal: 1900,
            proteinGrams: 150,
            dayKey: "2026-09-21",
            weeklyDeltaKg: -0.4
        )
        XCTAssertTrue(plan.isComplete)
        XCTAssertEqual(plan.dietRaw, "pescatarian")
        XCTAssertFalse(plan.usedNetwork)
        // Metric portions on every meal for cookable offline menus.
        for meal in plan.meals {
            XCTAssertTrue(
                meal.ingredients.contains(where: { $0.range(of: #"\d+\s*(g|ml)\b"#, options: .regularExpression) != nil }),
                "meal \(meal.title) missing metric portion: \(meal.ingredients)"
            )
        }
    }

    func testImperialLocalizesPortions() {
        let metric = MealPlanEngine.offlinePlan(
            name: "Alex",
            diet: .omnivore,
            maxKcal: 1800,
            proteinGrams: 140,
            dayKey: "2026-09-21",
            weeklyDeltaKg: -0.3,
            units: .metric
        )
        let imperial = MealPlanEngine.offlinePlan(
            name: "Alex",
            diet: .omnivore,
            maxKcal: 1800,
            proteinGrams: 140,
            dayKey: "2026-09-21",
            weeklyDeltaKg: -0.3,
            units: .imperial
        )
        XCTAssertTrue(imperial.meals.first?.ingredients.joined().contains("oz") == true)
        XCTAssertFalse(metric.meals.first?.ingredients.joined().contains("oz") == true)
    }

    func testIFAt7amDoesNotProposeBreakfastAt8() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let sevenAM = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 7, minute: 0))!
        let meals = MealPlanEngine.offlineMeals(
            diet: .omnivore,
            maxKcal: 1800,
            proteinGrams: 140,
            fasting: .classic168,
            now: sevenAM,
            calendar: cal
        )
        XCTAssertEqual(meals.count, 2)
        for meal in meals {
            guard let hour = meal.approxHour else { continue }
            XCTAssertGreaterThanOrEqual(hour, 12.0, "meal \(meal.title) at \(meal.timeLabel) is inside fasting window")
            XCTAssertLessThan(hour, 20.0)
        }
        XCTAssertFalse(meals.contains(where: { ($0.approxHour ?? 99) < 11.5 }))
    }

    func testDetectClassic168FromMemory() {
        let window = FastingWindow.detect(memoryBlock: "User mentioned: intermittent fasting 16/8")
        XCTAssertTrue(window.isActive)
        XCTAssertEqual(window.eatingStartMinutes, 12 * 60)
        XCTAssertEqual(window.eatingWindowEndMinutes, 20 * 60)
        XCTAssertEqual(window.protocolLabel, "16-8")
        XCTAssertEqual(window.eatingHours, 8, accuracy: 0.01)
        XCTAssertTrue(window.isFasting(
            at: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 7))!
        ))
    }

    func testSixteenDashEightIsProtocolNotClock() {
        let window = FastingWindow.detect(memoryBlock: "doing IF 16-8")
        XCTAssertEqual(window.protocolLabel, "16-8")
        XCTAssertEqual(window.eatingWindowStartMinutes, 12 * 60)
        XCTAssertEqual(window.eatingWindowEndMinutes, 20 * 60)
        XCTAssertFalse(window.cacheToken.contains("@960-"))
    }

    func testIFMealsSpacedAcrossEightHourWindow() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let sevenAM = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 7))!
        let meals = MealPlanEngine.offlineMeals(
            diet: .omnivore,
            maxKcal: 1800,
            proteinGrams: 140,
            fasting: .classic168,
            now: sevenAM,
            calendar: cal
        )
        XCTAssertEqual(meals.count, 2)
        XCTAssertEqual(MealPlanEngine.preferredMealCount(for: .classic168), 2)
        let hours = meals.compactMap(\.approxHour)
        XCTAssertEqual(hours.first ?? -1, 12.0, accuracy: 0.26)
        XCTAssertGreaterThanOrEqual(hours.last ?? 0, 18.5)
        XCTAssertLessThan(hours.last ?? 99, 20.0)
        // Two plates bookend the 8h window.
        XCTAssertGreaterThan((hours.last ?? 0) - (hours.first ?? 0), 5.0)
    }

    func testIFFirstPlateIsNeverBreakfast() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let sevenAM = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 7))!
        let noon = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12))!
        for now in [sevenAM, noon] {
            let meals = MealPlanEngine.offlineMeals(
                diet: .omnivore,
                maxKcal: 1800,
                proteinGrams: 140,
                fasting: .classic168,
                now: now,
                calendar: cal
            )
            XCTAssertEqual(meals.count, 2)
            XCTAssertEqual(meals.map(\.title), ["Lunch", "Dinner"])
            XCTAssertFalse(meals.contains(where: {
                $0.title.localizedCaseInsensitiveContains("breakfast")
                    || $0.title.localizedCaseInsensitiveContains("break-fast")
            }))
        }

        let grokLabeledBreakfast = [
            MealPlanMeal(title: "Breakfast", timeLabel: "~12:00", ingredients: ["Eggs"], keyMacro: "P", keyMicro: "M", approxKcal: 400),
            MealPlanMeal(title: "Dinner", timeLabel: "~19:00", ingredients: ["Fish"], keyMacro: "P", keyMicro: "M", approxKcal: 500)
        ]
        let fixed = MealPlanEngine.enforceFasting(grokLabeledBreakfast, fasting: .classic168, now: noon, calendar: cal)
        XCTAssertEqual(fixed.map(\.title), ["Lunch", "Dinner"])
    }

    func testEnforceFastingDropsEarlyBreakfast() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let sevenAM = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 7))!
        let raw = [
            MealPlanMeal(title: "Breakfast", timeLabel: "~8:00", ingredients: ["Eggs"], keyMacro: "P", keyMicro: "M", approxKcal: 300),
            MealPlanMeal(title: "Lunch", timeLabel: "~12:30", ingredients: ["Chicken"], keyMacro: "P", keyMicro: "M", approxKcal: 400),
            MealPlanMeal(title: "Dinner", timeLabel: "~19:00", ingredients: ["Fish"], keyMacro: "P", keyMicro: "M", approxKcal: 450)
        ]
        let fixed = MealPlanEngine.enforceFasting(raw, fasting: .classic168, now: sevenAM, calendar: cal)
        XCTAssertEqual(fixed.count, 2)
        XCTAssertFalse(fixed.contains(where: { ($0.approxHour ?? 99) < 11.5 }))
    }

    func testPreferredMealCountMatchesProtocol() {
        XCTAssertEqual(MealPlanEngine.preferredMealCount(for: .none), 3)
        XCTAssertEqual(MealPlanEngine.preferredMealCount(for: .classic168), 2)
        XCTAssertEqual(MealPlanEngine.preferredMealCount(for: .classic186), 2)
        XCTAssertEqual(MealPlanEngine.preferredMealCount(for: .classic204), 2)
        XCTAssertEqual(
            MealPlanEngine.preferredMealCount(for: FastingWindow.make(
                startMinutes: 17 * 60,
                endMinutes: 19 * 60,
                protocolLabel: "omad",
                fastingHours: 22
            )),
            1
        )
    }

    func testSpacedHoursEven() {
        let slots = MealPlanEngine.spacedHours(count: 3, from: 12, to: 19.75)
        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(slots[0], 12, accuracy: 0.01)
        XCTAssertEqual(slots[2], 19.75, accuracy: 0.01)
        XCTAssertEqual(slots[1], 16.0, accuracy: 0.35)
    }
}
