import Foundation

/// One meal in the next-24h home meal plan carousel.
struct MealPlanMeal: Equatable, Codable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var timeLabel: String
    var ingredients: [String]
    var keyMacro: String
    var keyMicro: String
    var approxKcal: Int

    init(
        id: UUID = UUID(),
        title: String,
        timeLabel: String,
        ingredients: [String],
        keyMacro: String,
        keyMicro: String,
        approxKcal: Int
    ) {
        self.id = id
        self.title = title
        self.timeLabel = timeLabel
        self.ingredients = ingredients
        self.keyMacro = keyMacro
        self.keyMicro = keyMicro
        self.approxKcal = approxKcal
    }
}

/// Cached next-24h meal plan. Regenerates only when cache key inputs change or user refreshes.
struct MealPlanPayload: Equatable, Codable, Sendable {
    var cacheKey: String
    /// Local calendar day `yyyy-MM-dd`.
    var dayKey: String
    var maxKcal: Int
    var proteinGrams: Int
    var dietRaw: String
    var meals: [MealPlanMeal]
    var generatedAt: Date
    var usedNetwork: Bool
    var sourceNote: String

    var isComplete: Bool { meals.count >= 3 }
}

enum MealPlanStore {
    private static let key = "thescale.mealPlan.v1"

    static func load() -> MealPlanPayload? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let payload = try? JSONDecoder().decode(MealPlanPayload.self, from: data)
        else { return nil }
        return payload
    }

    static func save(_ payload: MealPlanPayload) {
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Cache key + offline meals + compact Grok JSON parse for the home meal plan.
enum MealPlanEngine {
    /// Day + deficit budget + diet + protein. Changing any forces a new plan.
    static func cacheKey(
        dayKey: String,
        maxKcal: Int,
        proteinGrams: Int,
        diet: DietPreference,
        weeklyDeltaKg: Double
    ) -> String {
        let deltaBucket = Int((weeklyDeltaKg * 10).rounded())
        return "\(dayKey)|\(maxKcal)|\(proteinGrams)|\(diet.rawValue)|\(deltaBucket)"
    }

    static func dayKey(now: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func offlinePlan(
        name: String,
        diet: DietPreference,
        maxKcal: Int,
        proteinGrams: Int,
        dayKey: String,
        weeklyDeltaKg: Double,
        now: Date = Date()
    ) -> MealPlanPayload {
        let meals = offlineMeals(diet: diet, maxKcal: maxKcal, proteinGrams: proteinGrams)
        let key = cacheKey(
            dayKey: dayKey,
            maxKcal: maxKcal,
            proteinGrams: proteinGrams,
            diet: diet,
            weeklyDeltaKg: weeklyDeltaKg
        )
        let who = name.isEmpty ? "you" : name
        return MealPlanPayload(
            cacheKey: key,
            dayKey: dayKey,
            maxKcal: maxKcal,
            proteinGrams: proteinGrams,
            dietRaw: diet.rawValue,
            meals: meals,
            generatedAt: now,
            usedNetwork: false,
            sourceNote: "Offline pattern for \(who). Refresh for live Grok."
        )
    }

    static func offlineMeals(
        diet: DietPreference,
        maxKcal: Int,
        proteinGrams: Int
    ) -> [MealPlanMeal] {
        let per = max(280, maxKcal / 4)
        let pMeal = max(20, proteinGrams / 4)
        switch diet {
        case .vegan:
            return [
                MealPlanMeal(
                    title: "Breakfast",
                    timeLabel: "~8:00",
                    ingredients: ["Tofu scramble", "Spinach", "Berries"],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Iron ~4 mg",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Lunch",
                    timeLabel: "~12:30",
                    ingredients: ["Lentil bowl", "Kale", "Lemon"],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Fiber ≥ 10 g",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Snack",
                    timeLabel: "~16:00",
                    ingredients: ["Apple", "Almond butter"],
                    keyMacro: "Protein \(max(8, pMeal / 2)) g",
                    keyMicro: "Potassium",
                    approxKcal: max(150, per / 2)
                ),
                MealPlanMeal(
                    title: "Dinner",
                    timeLabel: "~19:00",
                    ingredients: ["Tempeh", "Broccoli", "Brown rice (small)"],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Iron + vitamin C",
                    approxKcal: per
                )
            ]
        case .vegetarian:
            return [
                MealPlanMeal(
                    title: "Breakfast",
                    timeLabel: "~8:00",
                    ingredients: ["Eggs", "Spinach", "Fruit"],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Iron",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Lunch",
                    timeLabel: "~12:30",
                    ingredients: ["Greek yogurt", "Berries", "Seeds"],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Calcium",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Snack",
                    timeLabel: "~16:00",
                    ingredients: ["Cottage cheese", "Cucumber"],
                    keyMacro: "Protein \(max(12, pMeal / 2)) g",
                    keyMicro: "Potassium",
                    approxKcal: max(160, per / 2)
                ),
                MealPlanMeal(
                    title: "Dinner",
                    timeLabel: "~19:00",
                    ingredients: ["Bean chili", "Side salad"],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Fiber ≥ 12 g",
                    approxKcal: per
                )
            ]
        case .pescatarian:
            return [
                MealPlanMeal(
                    title: "Breakfast",
                    timeLabel: "~8:00",
                    ingredients: ["Egg whites", "Fruit", "Toast (thin)"],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Vitamin C",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Lunch",
                    timeLabel: "~12:30",
                    ingredients: ["Tuna salad", "Greens", "Olive oil (tsp)"],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Omega-3",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Snack",
                    timeLabel: "~16:00",
                    ingredients: ["Greek yogurt", "Berries"],
                    keyMacro: "Protein \(max(12, pMeal / 2)) g",
                    keyMicro: "Calcium",
                    approxKcal: max(160, per / 2)
                ),
                MealPlanMeal(
                    title: "Dinner",
                    timeLabel: "~19:00",
                    ingredients: ["Salmon", "Broccoli", "Potato (small)"],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Vitamin D / selenium",
                    approxKcal: per
                )
            ]
        case .omnivore, .other:
            return [
                MealPlanMeal(
                    title: "Breakfast",
                    timeLabel: "~8:00",
                    ingredients: ["Eggs", "Fruit", "Black coffee"],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Choline",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Lunch",
                    timeLabel: "~12:30",
                    ingredients: ["Chicken salad", "Greens", "Vinegar"],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Fiber ≥ 8 g",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Snack",
                    timeLabel: "~16:00",
                    ingredients: ["Greek yogurt", "Berries"],
                    keyMacro: "Protein \(max(12, pMeal / 2)) g",
                    keyMicro: "Calcium",
                    approxKcal: max(160, per / 2)
                ),
                MealPlanMeal(
                    title: "Dinner",
                    timeLabel: "~19:00",
                    ingredients: ["Lean fish or turkey", "Veg pile", "Rice (small)"],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Potassium",
                    approxKcal: per
                )
            ]
        }
    }

    /// Parse compact Grok JSON: `{ "meals": [ { "title", "time", "ingredients", "macro", "micro", "kcal" } ] }`
    static func parseGrokJSON(_ raw: String) -> [MealPlanMeal]? {
        let cleaned = CoachCopySanitize.clean(raw)
        guard let data = extractJSONObjectData(from: cleaned),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["meals"] as? [[String: Any]]
        else { return nil }

        var meals: [MealPlanMeal] = []
        for item in arr.prefix(5) {
            let title = stringValue(item["title"]) ?? "Meal"
            let time = stringValue(item["time"]) ?? ""
            let ingredients: [String] = {
                if let list = item["ingredients"] as? [String] {
                    return list.map { CoachCopySanitize.clean($0) }.filter { !$0.isEmpty }
                }
                if let one = stringValue(item["ingredients"]) {
                    return one.split(separator: ",").map { CoachCopySanitize.clean(String($0)) }.filter { !$0.isEmpty }
                }
                return []
            }()
            let macro = stringValue(item["macro"]) ?? "Protein"
            let micro = stringValue(item["micro"]) ?? "Fiber"
            let kcal = intValue(item["kcal"]) ?? 400
            guard !ingredients.isEmpty else { continue }
            meals.append(
                MealPlanMeal(
                    title: title,
                    timeLabel: time,
                    ingredients: Array(ingredients.prefix(5)),
                    keyMacro: macro,
                    keyMicro: micro,
                    approxKcal: max(80, min(1200, kcal))
                )
            )
        }
        return meals.count >= 3 ? meals : nil
    }

    private static func extractJSONObjectData(from text: String) -> Data? {
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end
        else { return nil }
        let slice = String(text[start...end])
        return slice.data(using: .utf8)
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String {
            let c = CoachCopySanitize.clean(s)
            return c.isEmpty ? nil : c
        }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d.rounded()) }
        if let s = any as? String, let i = Int(s.filter(\.isNumber)) { return i }
        return nil
    }
}
