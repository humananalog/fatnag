import XCTest
@testable import TheScale

final class MealPlanEngineTests: XCTestCase {
    func testCacheKeyChangesWithDeficitAndDiet() {
        let day = "2026-09-21"
        let a = MealPlanEngine.cacheKey(
            dayKey: day,
            maxKcal: 1800,
            proteinGrams: 140,
            diet: .omnivore,
            weeklyDeltaKg: -0.3
        )
        let b = MealPlanEngine.cacheKey(
            dayKey: day,
            maxKcal: 1800,
            proteinGrams: 140,
            diet: .vegan,
            weeklyDeltaKg: -0.3
        )
        let c = MealPlanEngine.cacheKey(
            dayKey: day,
            maxKcal: 1600,
            proteinGrams: 140,
            diet: .omnivore,
            weeklyDeltaKg: -0.3
        )
        let d = MealPlanEngine.cacheKey(
            dayKey: "2026-09-22",
            maxKcal: 1800,
            proteinGrams: 140,
            diet: .omnivore,
            weeklyDeltaKg: -0.3
        )
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
        XCTAssertTrue(a.contains("omnivore"))
        XCTAssertTrue(a.hasPrefix(day))
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
    }
}
