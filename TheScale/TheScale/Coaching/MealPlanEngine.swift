import Foundation

/// What the meal planner should put on screen for the current clock.
enum MealPlanFocus: Equatable, Sendable {
    case next(MealPlanMeal)
    case kitchenClosed
}

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
    /// Expected plate count for this fasting / diet profile (1-4).
    var targetMealCount: Int

    var isComplete: Bool { meals.count >= max(1, targetMealCount) }

    enum CodingKeys: String, CodingKey {
        case cacheKey, dayKey, maxKcal, proteinGrams, dietRaw, meals, generatedAt, usedNetwork, sourceNote, targetMealCount
    }

    init(
        cacheKey: String,
        dayKey: String,
        maxKcal: Int,
        proteinGrams: Int,
        dietRaw: String,
        meals: [MealPlanMeal],
        generatedAt: Date,
        usedNetwork: Bool,
        sourceNote: String,
        targetMealCount: Int
    ) {
        self.cacheKey = cacheKey
        self.dayKey = dayKey
        self.maxKcal = maxKcal
        self.proteinGrams = proteinGrams
        self.dietRaw = dietRaw
        self.meals = meals
        self.generatedAt = generatedAt
        self.usedNetwork = usedNetwork
        self.sourceNote = sourceNote
        self.targetMealCount = targetMealCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cacheKey = try c.decode(String.self, forKey: .cacheKey)
        dayKey = try c.decode(String.self, forKey: .dayKey)
        maxKcal = try c.decode(Int.self, forKey: .maxKcal)
        proteinGrams = try c.decode(Int.self, forKey: .proteinGrams)
        dietRaw = try c.decode(String.self, forKey: .dietRaw)
        meals = try c.decode([MealPlanMeal].self, forKey: .meals)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        usedNetwork = try c.decode(Bool.self, forKey: .usedNetwork)
        sourceNote = try c.decode(String.self, forKey: .sourceNote)
        targetMealCount = try c.decodeIfPresent(Int.self, forKey: .targetMealCount) ?? max(meals.count, 2)
    }
}

enum MealPlanStore {
    private static let key = "thescale.mealPlan.v4"

    static func load() -> MealPlanPayload? {
        if let data = UserDefaults.standard.data(forKey: key),
           let payload = try? JSONDecoder().decode(MealPlanPayload.self, from: data) {
            return payload
        }
        // Drop stale caches so IF slot naming (no Breakfast at noon) regenerates.
        for stale in ["thescale.mealPlan.v1", "thescale.mealPlan.v2", "thescale.mealPlan.v3"] {
            UserDefaults.standard.removeObject(forKey: stale)
        }
        return nil
    }

    static func save(_ payload: MealPlanPayload) {
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        for stale in ["thescale.mealPlan.v1", "thescale.mealPlan.v2", "thescale.mealPlan.v3"] {
            UserDefaults.standard.removeObject(forKey: stale)
        }
    }
}

/// Cache key + offline meals + compact Grok JSON parse for the home meal plan.
enum MealPlanEngine {
    /// How many plates fit the eating window. 16-8 / 18-6 → 2. OMAD → 1. Open day → 3.
    static func preferredMealCount(for fasting: FastingWindow) -> Int {
        guard fasting.isActive else { return 3 }
        switch fasting.protocolLabel.lowercased() {
        case "omad":
            return 1
        case "20-4", "18-6", "16-8":
            return 2
        case "14-10":
            return 3
        default:
            let hours = fasting.eatingHours
            if hours <= 3 { return 1 }
            if hours <= 8 { return 2 }
            if hours <= 11 { return 3 }
            return 4
        }
    }

    /// Day + deficit + diet + protein + fasting window + meal count. Changing any forces a new plan.
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
        let meals = preferredMealCount(for: fasting)
        // `slots2` invalidates caches that still labeled IF first plate as Breakfast / Break-fast.
        return "\(dayKey)|\(maxKcal)|\(proteinGrams)|\(diet.rawValue)|\(deltaBucket)|\(fasting.cacheToken)|m\(meals)|h\(hourBucket)|slots2"
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

    /// A plate stays "the meal" until this long after its slot.
    static let mealGraceHours: Double = 1.25
    /// Deep night before the first morning plate. After the last window, the kitchen stays shut.
    static let kitchenClosedBeforeHour: Double = 5

    /// The one plate that matches the clock, or a shut kitchen once the last window has passed.
    static func focus(
        meals: [MealPlanMeal],
        now: Date = Date(),
        calendar: Calendar = .current,
        fasting: FastingWindow = .none
    ) -> MealPlanFocus {
        let nowHour = clockHour(now, calendar: calendar)
        let timed = meals.compactMap { meal -> (MealPlanMeal, Double)? in
            guard let hour = meal.approxHour else { return nil }
            return (meal, hour)
        }.sorted { $0.1 < $1.1 }

        guard let first = timed.first, let last = timed.last else {
            if nowHour >= 21 { return .kitchenClosed }
            if let meal = meals.first { return .next(meal) }
            return .kitchenClosed
        }

        let close = kitchenCloseHour(lastMealHour: last.1, fasting: fasting)
        if nowHour >= close { return .kitchenClosed }
        if nowHour < kitchenClosedBeforeHour, first.1 >= 6, close >= 18 {
            return .kitchenClosed
        }
        if let open = timed.first(where: { nowHour < $0.1 + mealGraceHours }) {
            return .next(open.0)
        }
        return .kitchenClosed
    }

    static func clockHour(_ date: Date, calendar: Calendar = .current) -> Double {
        Double(calendar.component(.hour, from: date))
            + Double(calendar.component(.minute, from: date)) / 60.0
    }

    /// Last plate's grace, pulled in when a fasting window ends sooner.
    static func kitchenCloseHour(lastMealHour: Double, fasting: FastingWindow) -> Double {
        var close = lastMealHour + mealGraceHours
        if fasting.isActive {
            close = min(close, fasting.eatingEndHour + 0.35)
        }
        return close
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
        let targetCount = preferredMealCount(for: fasting)
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
            sourceNote: note,
            targetMealCount: targetCount
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
        let count = preferredMealCount(for: fasting)
        let templates = selectTemplates(
            diet: diet,
            maxKcal: maxKcal,
            proteinGrams: proteinGrams,
            count: count
        )
        return scheduleMeals(templates, fasting: fasting, now: now, calendar: calendar, mealCount: count)
    }

    /// Drop meals still inside the fasting window or already past; space survivors across the eating window.
    static func scheduleMeals(
        _ templates: [MealPlanMeal],
        fasting: FastingWindow,
        now: Date,
        calendar: Calendar = .current,
        mealCount: Int? = nil
    ) -> [MealPlanMeal] {
        let nowHour = Double(calendar.component(.hour, from: now))
            + Double(calendar.component(.minute, from: now)) / 60.0
        let targetCount = max(1, mealCount ?? preferredMealCount(for: fasting))

        if !fasting.isActive {
            // Still skip meals already past by >45 min so a 7pm open doesn't push breakfast.
            let upcoming = templates.filter { meal in
                guard let h = meal.approxHour else { return true }
                return h >= nowHour - 0.75
            }
            let picked: [MealPlanMeal]
            if upcoming.count >= targetCount {
                picked = Array(upcoming.prefix(targetCount))
            } else {
                picked = Array(templates.suffix(min(targetCount, templates.count)))
            }
            return applySlotTitles(picked, fasting: .none)
        }

        let open = fasting.eatingStartHour
        let close = fasting.eatingEndHour
        // Usable span inside the protocol window: from max(open, now) to just before close.
        let usableStart = nowHour < open ? open : max(open, nowHour)
        let usableEnd = close - 0.25
        guard usableEnd > usableStart + 0.5 else {
            // Window almost closed: one late plate only, still inside.
            let hour = max(open, min(usableEnd, nowHour))
            let template = templates.last ?? templates[0]
            return applySlotTitles(
                [
                    MealPlanMeal(
                        title: "One plate",
                        timeLabel: formatHour(hour),
                        ingredients: template.ingredients,
                        keyMacro: template.keyMacro,
                        keyMicro: template.keyMicro,
                        approxKcal: template.approxKcal
                    )
                ],
                fasting: fasting
            )
        }

        let count = min(targetCount, max(1, templates.count))
        let slots = spacedHours(count: count, from: usableStart, to: usableEnd)
        let titles = slotTitles(count: count, fasting: fasting)

        var meals: [MealPlanMeal] = []
        for (index, hour) in slots.enumerated() {
            let clamped = min(max(hour, open), close - 0.05)
            guard fasting.allowsMeal(atHour: clamped) else { continue }
            let template = templates[min(index, templates.count - 1)]
            let title = index < titles.count ? titles[index] : template.title
            meals.append(
                MealPlanMeal(
                    title: title,
                    timeLabel: formatHour(clamped),
                    ingredients: template.ingredients,
                    keyMacro: template.keyMacro,
                    keyMicro: template.keyMicro,
                    approxKcal: template.approxKcal
                )
            )
        }
        return applySlotTitles(meals, fasting: fasting)
    }

    /// Slot names inside an IF eating window. Never "Breakfast" (morning meal sense) when fasting.
    /// 16-8 / 2 plates → Lunch + Dinner. 3+ → First / Mid / Last plate.
    static func slotTitles(count: Int, fasting: FastingWindow) -> [String] {
        let n = max(1, count)
        if !fasting.isActive {
            switch n {
            case 1: return ["One plate"]
            case 2: return ["Lunch", "Dinner"]
            case 3: return ["Breakfast", "Lunch", "Dinner"]
            default: return ["Breakfast", "Lunch", "Snack", "Dinner"]
            }
        }
        switch n {
        case 1:
            return ["One plate"]
        case 2:
            // Classic midday-open windows (16-8 ~12-20): Lunch then Dinner.
            return ["Lunch", "Dinner"]
        case 3:
            return ["First plate", "Mid plate", "Last plate"]
        default:
            return ["First plate", "Mid plate", "Later plate", "Last plate"]
        }
    }

    /// Overwrite meal titles by slot order so Grok/FM cannot leave "Breakfast" on a noon first plate.
    static func applySlotTitles(_ meals: [MealPlanMeal], fasting: FastingWindow) -> [MealPlanMeal] {
        guard !meals.isEmpty else { return meals }
        let titles = slotTitles(count: meals.count, fasting: fasting)
        return meals.enumerated().map { index, meal in
            var copy = meal
            if index < titles.count {
                copy.title = titles[index]
            }
            return copy
        }
    }

    /// Evenly space `count` meal hours across [from, to] inclusive.
    static func spacedHours(count: Int, from start: Double, to end: Double) -> [Double] {
        guard count > 0, end > start else { return [] }
        if count == 1 { return [start] }
        let span = end - start
        return (0..<count).map { i in
            let raw = start + span * Double(i) / Double(count - 1)
            return (raw * 4).rounded() / 4
        }
    }

    /// Reject Grok meals that land inside the fasting window; reschedule survivors.
    static func enforceFasting(
        _ meals: [MealPlanMeal],
        fasting: FastingWindow,
        now: Date,
        calendar: Calendar = .current
    ) -> [MealPlanMeal] {
        let target = preferredMealCount(for: fasting)
        guard fasting.isActive else {
            return applySlotTitles(
                scheduleMeals(meals, fasting: .none, now: now, calendar: calendar, mealCount: target),
                fasting: .none
            )
        }
        let allowed = meals.filter { meal in
            guard let h = meal.approxHour else { return true }
            return fasting.allowsMeal(atHour: h)
        }
        let scheduled: [MealPlanMeal]
        if allowed.count >= target {
            scheduled = scheduleMeals(allowed, fasting: fasting, now: now, calendar: calendar, mealCount: target)
        } else {
            scheduled = scheduleMeals(meals, fasting: fasting, now: now, calendar: calendar, mealCount: target)
        }
        return applySlotTitles(scheduled, fasting: fasting)
    }

    /// Pick and resize templates so plate count matches IF (2 for 16-8, 1 for OMAD, …).
    static func selectTemplates(
        diet: DietPreference,
        maxKcal: Int,
        proteinGrams: Int,
        count: Int
    ) -> [MealPlanMeal] {
        let all = baseTemplates(diet: diet, maxKcal: maxKcal, proteinGrams: proteinGrams)
        let n = max(1, min(4, count))
        let picked: [MealPlanMeal] = {
            switch n {
            case 1:
                return [all[3]]
            case 2:
                return [all[1], all[3]]
            case 3:
                return [all[0], all[1], all[3]]
            default:
                return all
            }
        }()
        let per = max(280, maxKcal / n)
        let pMeal = max(20, proteinGrams / n)
        return picked.map { meal in
            var copy = meal
            copy.approxKcal = per
            if copy.keyMacro.lowercased().contains("protein") {
                copy.keyMacro = "Protein \(pMeal) g"
            }
            return copy
        }
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
    /// `minimumCount` defaults to 2 so IF 16-8 plans are accepted.
    static func parseGrokJSON(_ raw: String, minimumCount: Int = 2) -> [MealPlanMeal]? {
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
        return meals.count >= max(1, minimumCount) ? meals : nil
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
