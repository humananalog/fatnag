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

    /// Parsed local hour from `~12:30` / `12:30` / `12`.
    var approxHour: Double? {
        MealPlanEngine.parseHour(from: timeLabel)
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
    private static let key = "thescale.mealPlan.v2"

    static func load() -> MealPlanPayload? {
        if let data = UserDefaults.standard.data(forKey: key),
           let payload = try? JSONDecoder().decode(MealPlanPayload.self, from: data) {
            return payload
        }
        // Migrate once from v1 (no fasting token) → treat as miss so IF regenerates.
        UserDefaults.standard.removeObject(forKey: "thescale.mealPlan.v1")
        return nil
    }

    static func save(_ payload: MealPlanPayload) {
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: "thescale.mealPlan.v1")
    }
}

/// Cache key + offline meals + compact Grok JSON parse for the home meal plan.
enum MealPlanEngine {
    /// Day + deficit + diet + protein + fasting window. Changing any forces a new plan.
    /// Hour bucket (4h) keeps morning vs afternoon plans distinct without hourly token burn.
    static func cacheKey(
        dayKey: String,
        maxKcal: Int,
        proteinGrams: Int,
        diet: DietPreference,
        weeklyDeltaKg: Double,
        fasting: FastingWindow,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let deltaBucket = Int((weeklyDeltaKg * 10).rounded())
        let hour = calendar.component(.hour, from: now)
        let hourBucket = (hour / 4) * 4
        return "\(dayKey)|\(maxKcal)|\(proteinGrams)|\(diet.rawValue)|\(deltaBucket)|\(fasting.cacheToken)|h\(hourBucket)"
    }

    static func dayKey(now: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func parseHour(from label: String) -> Double? {
        let digits = label.filter { $0.isNumber || $0 == ":" }
        guard !digits.isEmpty else { return nil }
        let parts = digits.split(separator: ":")
        guard let h = Int(parts[0]), h >= 0, h <= 23 else { return nil }
        let m: Int = {
            guard parts.count > 1, let mm = Int(parts[1]) else { return 0 }
            return min(59, max(0, mm))
        }()
        return Double(h) + Double(m) / 60.0
    }

    static func formatHour(_ hour: Double) -> String {
        let h = Int(hour)
        let m = Int(((hour - Double(h)) * 60).rounded())
        if m == 0 {
            return String(format: "~%d:00", h)
        }
        return String(format: "~%d:%02d", h, m)
    }

    static func offlinePlan(
        name: String,
        diet: DietPreference,
        maxKcal: Int,
        proteinGrams: Int,
        dayKey: String,
        weeklyDeltaKg: Double,
        fasting: FastingWindow = .none,
        units: PreferredUnitSystem = .metric,
        now: Date = Date(),
        calendar: Calendar = .current,
        sourceNoteOverride: String? = nil
    ) -> MealPlanPayload {
        let rawMeals = offlineMeals(
            diet: diet,
            maxKcal: maxKcal,
            proteinGrams: proteinGrams,
            fasting: fasting,
            now: now,
            calendar: calendar
        )
        let meals = localizePortions(rawMeals, units: units)
        let key = cacheKey(
            dayKey: dayKey,
            maxKcal: maxKcal,
            proteinGrams: proteinGrams,
            diet: diet,
            weeklyDeltaKg: weeklyDeltaKg,
            fasting: fasting,
            now: now,
            calendar: calendar
        )
        let who = name.isEmpty ? "you" : name
        let fastingNote = fasting.isActive
            ? " IF \(fasting.cacheToken) respected."
            : ""
        let note = sourceNoteOverride ?? "On-device menu for \(who) with metric-sized portions.\(fastingNote) Refresh when Keel credits remain."
        return MealPlanPayload(
            cacheKey: key,
            dayKey: dayKey,
            maxKcal: maxKcal,
            proteinGrams: proteinGrams,
            dietRaw: diet.rawValue,
            meals: meals,
            generatedAt: now,
            usedNetwork: false,
            sourceNote: note
        )
    }

    static func offlineMeals(
        diet: DietPreference,
        maxKcal: Int,
        proteinGrams: Int,
        fasting: FastingWindow = .none,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MealPlanMeal] {
        let templates = baseTemplates(diet: diet, maxKcal: maxKcal, proteinGrams: proteinGrams)
        return scheduleMeals(templates, fasting: fasting, now: now, calendar: calendar)
    }

    /// Drop meals still inside the fasting window or already past; retitle first remaining as break-fast when IF.
    static func scheduleMeals(
        _ templates: [MealPlanMeal],
        fasting: FastingWindow,
        now: Date,
        calendar: Calendar = .current
    ) -> [MealPlanMeal] {
        let nowHour = Double(calendar.component(.hour, from: now))
            + Double(calendar.component(.minute, from: now)) / 60.0

        if !fasting.isActive {
            // Still skip meals already past by >45 min so a 7pm open doesn't push breakfast.
            let upcoming = templates.filter { meal in
                guard let h = meal.approxHour else { return true }
                return h >= nowHour - 0.75
            }
            return upcoming.count >= 3 ? upcoming : Array(templates.suffix(max(3, upcoming.count)))
        }

        let open = fasting.eatingStartHour
        let close = fasting.eatingEndHour
        let firstHour = max(open, nowHour < open ? open : nowHour)

        // Build IF-aware slots inside the window from "now".
        var slots: [Double] = []
        if firstHour < close - 0.5 {
            slots.append(max(firstHour, open))
        }
        let mid = (open + close) / 2.0
        if mid > firstHour + 1.0, mid < close - 0.5 {
            slots.append(mid)
        }
        let lateSnack = close - 0.75
        if lateSnack > firstHour + 1.5 {
            slots.append(lateSnack)
        }
        let dinner = min(close - 0.25, max(open + 5.0, 18.5))
        if dinner > firstHour + 0.5, !slots.contains(where: { abs($0 - dinner) < 0.4 }) {
            slots.append(dinner)
        }
        slots = Array(Set(slots.map { ($0 * 4).rounded() / 4 })).sorted()
        if slots.count < 3 {
            // Force three plateaus inside window.
            let span = max(1.5, close - open - 0.5)
            slots = [
                open,
                open + span * 0.4,
                open + span * 0.85
            ].map { min(max($0, open), close - 0.25) }
            if nowHour > open {
                slots = slots.map { max($0, nowHour) }.filter { $0 < close }
            }
            while slots.count < 3 {
                slots.append(min(close - 0.2, (slots.last ?? open) + 1.5))
            }
        }

        let titles: [String] = {
            if fasting.isFasting(at: now, calendar: calendar) || nowHour < open {
                return ["Break-fast", "Lunch plate", "Dinner"]
            }
            return ["Next plate", "Later plate", "Close window"]
        }()

        var meals: [MealPlanMeal] = []
        for (index, hour) in slots.prefix(4).enumerated() {
            let template = templates[min(index, templates.count - 1)]
            let title = index < titles.count ? titles[index] : template.title
            meals.append(
                MealPlanMeal(
                    title: title,
                    timeLabel: formatHour(hour),
                    ingredients: template.ingredients,
                    keyMacro: template.keyMacro,
                    keyMicro: template.keyMicro,
                    approxKcal: template.approxKcal
                )
            )
        }
        return meals
    }

    /// Reject Grok meals that land inside the fasting window; reschedule survivors.
    static func enforceFasting(
        _ meals: [MealPlanMeal],
        fasting: FastingWindow,
        now: Date,
        calendar: Calendar = .current
    ) -> [MealPlanMeal] {
        guard fasting.isActive else {
            return scheduleMeals(meals, fasting: .none, now: now, calendar: calendar)
        }
        let allowed = meals.filter { meal in
            guard let h = meal.approxHour else { return true }
            return fasting.allowsMeal(atHour: h)
        }
        if allowed.count >= 3 {
            return scheduleMeals(allowed, fasting: fasting, now: now, calendar: calendar)
        }
        return scheduleMeals(meals, fasting: fasting, now: now, calendar: calendar)
    }

    private static func baseTemplates(
        diet: DietPreference,
        maxKcal: Int,
        proteinGrams: Int
    ) -> [MealPlanMeal] {
        let per = max(280, maxKcal / 4)
        let pMeal = max(20, proteinGrams / 4)
        // Portions are metric (g / ml) so offline / quota-exhausted plans stay cookable.
        switch diet {
        case .vegan:
            return [
                MealPlanMeal(
                    title: "Breakfast",
                    timeLabel: "~8:00",
                    ingredients: [
                        "Firm tofu scramble 150 g",
                        "Spinach 80 g",
                        "Berries 120 g",
                        "Olive oil 5 ml"
                    ],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Iron ~4 mg",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Lunch",
                    timeLabel: "~12:30",
                    ingredients: [
                        "Cooked lentils 200 g",
                        "Kale 100 g",
                        "Cherry tomatoes 80 g",
                        "Lemon juice 15 ml"
                    ],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Fiber ≥ 10 g",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Snack",
                    timeLabel: "~16:00",
                    ingredients: [
                        "Apple 180 g",
                        "Almond butter 20 g"
                    ],
                    keyMacro: "Protein \(max(8, pMeal / 2)) g",
                    keyMicro: "Potassium",
                    approxKcal: max(150, per / 2)
                ),
                MealPlanMeal(
                    title: "Dinner",
                    timeLabel: "~19:00",
                    ingredients: [
                        "Tempeh 120 g",
                        "Broccoli 200 g",
                        "Cooked brown rice 100 g"
                    ],
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
                    ingredients: [
                        "Eggs 2 (≈100 g)",
                        "Spinach 60 g",
                        "Fruit 150 g"
                    ],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Iron",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Lunch",
                    timeLabel: "~12:30",
                    ingredients: [
                        "Greek yogurt 200 g",
                        "Berries 100 g",
                        "Pumpkin seeds 15 g"
                    ],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Calcium",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Snack",
                    timeLabel: "~16:00",
                    ingredients: [
                        "Cottage cheese 150 g",
                        "Cucumber 120 g"
                    ],
                    keyMacro: "Protein \(max(12, pMeal / 2)) g",
                    keyMicro: "Potassium",
                    approxKcal: max(160, per / 2)
                ),
                MealPlanMeal(
                    title: "Dinner",
                    timeLabel: "~19:00",
                    ingredients: [
                        "Bean chili 250 g",
                        "Side salad 150 g",
                        "Olive oil 5 ml"
                    ],
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
                    ingredients: [
                        "Egg whites 180 g",
                        "Fruit 150 g",
                        "Wholegrain toast 30 g"
                    ],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Vitamin C",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Lunch",
                    timeLabel: "~12:30",
                    ingredients: [
                        "Tuna in water 120 g",
                        "Mixed greens 120 g",
                        "Olive oil 5 ml"
                    ],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Omega-3",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Snack",
                    timeLabel: "~16:00",
                    ingredients: [
                        "Greek yogurt 170 g",
                        "Berries 100 g"
                    ],
                    keyMacro: "Protein \(max(12, pMeal / 2)) g",
                    keyMicro: "Calcium",
                    approxKcal: max(160, per / 2)
                ),
                MealPlanMeal(
                    title: "Dinner",
                    timeLabel: "~19:00",
                    ingredients: [
                        "Salmon 150 g",
                        "Broccoli 200 g",
                        "Potato 150 g"
                    ],
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
                    ingredients: [
                        "Eggs 2 (≈100 g)",
                        "Fruit 150 g",
                        "Black coffee 240 ml"
                    ],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Choline",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Lunch",
                    timeLabel: "~12:30",
                    ingredients: [
                        "Chicken breast 140 g",
                        "Mixed greens 150 g",
                        "Vinegar 10 ml"
                    ],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Fiber ≥ 8 g",
                    approxKcal: per
                ),
                MealPlanMeal(
                    title: "Snack",
                    timeLabel: "~16:00",
                    ingredients: [
                        "Greek yogurt 170 g",
                        "Berries 100 g"
                    ],
                    keyMacro: "Protein \(max(12, pMeal / 2)) g",
                    keyMicro: "Calcium",
                    approxKcal: max(160, per / 2)
                ),
                MealPlanMeal(
                    title: "Dinner",
                    timeLabel: "~19:00",
                    ingredients: [
                        "Lean turkey or white fish 150 g",
                        "Mixed vegetables 250 g",
                        "Cooked rice 80 g"
                    ],
                    keyMacro: "Protein \(pMeal) g",
                    keyMicro: "Potassium",
                    approxKcal: per
                )
            ]
        }
    }

    /// Remap metric g/ml ingredient strings into the user's preferred unit system for display.
    static func localizePortions(_ meals: [MealPlanMeal], units: PreferredUnitSystem) -> [MealPlanMeal] {
        guard units == .imperial else { return meals }
        return meals.map { meal in
            var copy = meal
            copy.ingredients = meal.ingredients.map(localizeIngredientPortion)
            return copy
        }
    }

    private static func localizeIngredientPortion(_ raw: String) -> String {
        var text = raw
        // "150 g" / "≈100 g" → oz
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*g\b"#, options: .caseInsensitive) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                let numRange = match.range(at: 1)
                guard let swiftRange = Range(numRange, in: text),
                      let grams = Int(text[swiftRange])
                else { continue }
                let replacement = UnitFormat.portionGrams(grams, system: .imperial)
                if let full = Range(match.range, in: text) {
                    text.replaceSubrange(full, with: replacement)
                }
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*ml\b"#, options: .caseInsensitive) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                let numRange = match.range(at: 1)
                guard let swiftRange = Range(numRange, in: text),
                      let ml = Int(text[swiftRange])
                else { continue }
                let replacement = UnitFormat.portionMl(ml, system: .imperial)
                if let full = Range(match.range, in: text) {
                    text.replaceSubrange(full, with: replacement)
                }
            }
        }
        return text
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
