import Foundation

/// One body-mass sample for the first-of-month hero. Callers pass Health history plus today's weigh-in.
struct MonthlyWeighSample: Equatable, Sendable {
    var kg: Double
    var date: Date
}

enum MonthlyHeroEdge: String, Codable, Equatable, Sendable {
    /// Prior month and this morning are both real enough to compare.
    case ready
    /// A single honest weigh. The month starts here.
    case brandNew
    /// Nothing usable in Health.
    case noHistory
    /// History exists, but not a real previous month.
    case incomplete
    /// Readings failed the human-mass / outlier gate and nothing honest remains.
    case badRecords
}

enum MonthlyDirection: String, Codable, Equatable, Sendable {
    case loss
    case gain
    case stable
    case unknown
}

/// What the person is actually trying to do. Drives the one action, not the palette.
enum MonthlyIntent: String, Codable, Equatable, Sendable {
    case lose
    case gain
    case maintain
}

enum MonthlyPace: String, Codable, Equatable, Sendable {
    case calm
    case fastLoss
    case fastGain
}

/// Big type + emoji, or an animated line. Picked from the data, not the tier.
enum MonthlyHeroVisual: String, Codable, Equatable, Sendable {
    case bigType
    case graph
}

struct MonthlyRelatableUnit: Equatable, Codable, Sendable {
    var emoji: String
    var countLabel: String
    var phrase: String
    /// Repeated emoji for the burst (capped).
    var burstCount: Int
}

/// Deterministic first-of-month story. Grok may rewrite the insight for Plus/Pro; it must not rewrite these numbers.
struct MonthlyHeroFacts: Equatable, Codable, Sendable {
    var monthKey: String
    var month: Int
    var year: Int
    var monthName: String
    var festivalTitle: String
    var festivalEmoji: String
    var edge: MonthlyHeroEdge
    var direction: MonthlyDirection
    var intent: MonthlyIntent
    var pace: MonthlyPace
    var visual: MonthlyHeroVisual
    var currentKg: Double?
    var priorKg: Double?
    var deltaKg: Double?
    /// Oldest → newest. Empty when there is nothing honest to draw.
    var sparkline: [Double]
    var bigWord: String
    var sinceLine: String
    var numberCaption: String
    /// Absolute kg to count up. A delta when we compared months, otherwise today's weigh.
    var heroNumberKg: Double?
    var heroNumberIsDelta: Bool
    var unit: MonthlyRelatableUnit?
    var burst: [String]
    var ruleInsight: String
    var monthlyAction: String
    var medicalNote: String?
    var rejectedSampleCount: Int
    var plausibleSampleCount: Int

    /// Plus/Pro may ask Keel. New, empty, messy, or numberless cards stay on the rules.
    var canAskKeel: Bool {
        edge == .ready && direction != .unknown && deltaKg != nil
    }
}

struct MonthlyHeroPayload: Equatable, Codable, Sendable {
    var monthKey: String
    var weighInSignature: String
    var facts: MonthlyHeroFacts
    var insight: String
    var usedNetwork: Bool
    var planRaw: String
    var generatedAt: Date

    var isComplete: Bool {
        !insight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !facts.monthlyAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum MonthlyHeroStore {
    static let payloadKey = "thescale.monthlyHero.payload"

    static func load() -> MonthlyHeroPayload? {
        guard let data = UserDefaults.standard.data(forKey: payloadKey),
              let payload = try? JSONDecoder().decode(MonthlyHeroPayload.self, from: data)
        else { return nil }
        return payload
    }

    static func save(_ payload: MonthlyHeroPayload) {
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: payloadKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: payloadKey)
    }
}

/// First-of-month hero math: clean samples, month-over-month delta, a food-sized unit, one action.
enum MonthlyHeroEngine {
    /// Local calendar day 1, any hour. The first successful weigh-in of that day offers the card.
    static func shouldOfferAfterWeighIn(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.component(.day, from: now) == 1
    }

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return String(format: "%04d-%02d", year, month)
    }

    static func weighInSignature(kg: Double, at date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let stamp = Int(day.timeIntervalSince1970)
        let tenths = Int((kg * 10).rounded())
        return "\(monthKey(for: date, calendar: calendar))-\(stamp)-\(tenths)"
    }

    static func allowsLiveInsight(plan: ScalePlan) -> Bool {
        plan == .plus || plan == .pro
    }

    static func compose(
        samples: [MonthlyWeighSample],
        weighInKg: Double?,
        idealKg: Double?,
        name: String,
        units: PreferredUnitSystem = .metric,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MonthlyHeroFacts {
        var pool = samples
        if let weighInKg, ProfileNumericBounds.isPlausibleWeighKg(weighInKg) {
            let already = pool.contains {
                abs($0.kg - weighInKg) < 0.05 && calendar.isDate($0.date, inSameDayAs: now)
            }
            if !already {
                pool.append(MonthlyWeighSample(kg: weighInKg, date: now))
            }
        }

        let split = partition(pool)
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        let festival = festival(for: month)
        let thisStart = startOfMonth(now, calendar: calendar)
        let prevStart = calendar.date(byAdding: .month, value: -1, to: thisStart) ?? thisStart
        let nextStart = calendar.date(byAdding: .month, value: 1, to: thisStart) ?? now

        let currentSample = currentAnchor(
            kept: split.kept,
            weighInKg: weighInKg,
            now: now,
            thisStart: thisStart,
            nextStart: nextStart
        )
        let priorPick = priorAnchor(
            kept: split.kept,
            now: now,
            thisStart: thisStart,
            prevStart: prevStart,
            calendar: calendar
        )

        let edge = resolveEdge(
            kept: split.kept,
            rejected: split.rejected,
            current: currentSample,
            prior: priorPick,
            now: now,
            calendar: calendar
        )

        let currentKg = currentSample?.kg
        let priorKg = (edge == .ready) ? priorPick?.sample.kg : nil
        let deltaKg: Double? = {
            guard edge == .ready, let currentKg, let priorKg else { return nil }
            return currentKg - priorKg
        }()

        let intent = resolveIntent(currentKg: currentKg ?? weighInKg, idealKg: idealKg)
        let direction = resolveDirection(deltaKg: deltaKg, currentKg: currentKg)
        let pace = resolvePace(
            deltaKg: deltaKg,
            currentKg: currentKg,
            priorDate: priorPick?.sample.date,
            currentDate: currentSample?.date ?? now,
            edge: edge,
            calendar: calendar
        )

        let sparkline: [Double] = {
            guard let prior = priorPick?.sample, let current = currentSample, edge == .ready else {
                let recent = split.kept.suffix(8).map(\.kg)
                return recent.count >= 2 ? Array(recent) : []
            }
            return sparkline(kept: split.kept, from: prior.date, to: current.date, calendar: calendar)
        }()

        let visual: MonthlyHeroVisual = {
            guard edge == .ready, sparkline.count >= 4, direction != .unknown else { return .bigType }
            return .graph
        }()

        let unit: MonthlyRelatableUnit? = {
            guard edge == .ready, let deltaKg, direction == .loss || direction == .gain else { return nil }
            guard abs(deltaKg) >= 0.2 else { return nil }
            return relatableUnit(absKg: abs(deltaKg), month: month)
        }()

        let sinceLine = sinceLine(for: priorPick, edge: edge, calendar: calendar)
        let bigWord = bigWord(edge: edge, direction: direction)
        let heroIsDelta = deltaKg != nil
        let heroNumber = deltaKg.map { abs($0) } ?? currentKg
        let numberCaption: String = {
            if heroIsDelta { return sinceLine }
            if edge == .brandNew { return "starting line" }
            if currentKg != nil { return "today's weigh" }
            return ""
        }()

        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let insight = ruleInsight(
            name: who,
            edge: edge,
            direction: direction,
            intent: intent,
            pace: pace,
            deltaKg: deltaKg,
            unit: unit,
            rejected: split.rejected,
            units: units
        )
        let action = monthlyAction(
            month: month,
            edge: edge,
            direction: direction,
            intent: intent,
            pace: pace
        )
        let medical = medicalNote(
            pace: pace,
            currentKg: currentKg,
            deltaKg: deltaKg,
            priorDate: priorPick?.sample.date,
            currentDate: currentSample?.date ?? now,
            units: units,
            calendar: calendar
        )

        var burst = [festival.emoji]
        switch edge {
        case .brandNew, .noHistory:
            burst.append("🌱")
        case .incomplete:
            burst.append("🌙")
        case .badRecords:
            burst.append("🧹")
        case .ready:
            switch direction {
            case .loss: burst.append(pace == .fastLoss ? "🩺" : "📉")
            case .gain: burst.append(pace == .fastGain ? "🩺" : "📈")
            case .stable: burst.append("⚖️")
            case .unknown: burst.append("✨")
            }
        }
        if let unit { burst.append(unit.emoji) }
        burst.append(contentsOf: [festival.emoji, "✨"])

        return MonthlyHeroFacts(
            monthKey: monthKey(for: now, calendar: calendar),
            month: month,
            year: year,
            monthName: monthName(now, calendar: calendar),
            festivalTitle: festival.title,
            festivalEmoji: festival.emoji,
            edge: edge,
            direction: direction,
            intent: intent,
            pace: pace,
            visual: visual,
            currentKg: currentKg,
            priorKg: priorKg,
            deltaKg: deltaKg,
            sparkline: sparkline,
            bigWord: bigWord,
            sinceLine: sinceLine,
            numberCaption: numberCaption,
            heroNumberKg: heroNumber,
            heroNumberIsDelta: heroIsDelta,
            unit: unit,
            burst: burst,
            ruleInsight: insight,
            monthlyAction: action,
            medicalNote: medical,
            rejectedSampleCount: split.rejected,
            plausibleSampleCount: split.kept.count
        )
    }

    // MARK: - Anchors

    private struct PriorPick {
        enum Kind {
            case monthOpen
            case typical
            case aboutAMonth
        }
        var sample: MonthlyWeighSample
        var kind: Kind
    }

    private static func resolveEdge(
        kept: [MonthlyWeighSample],
        rejected: Int,
        current: MonthlyWeighSample?,
        prior: PriorPick?,
        now: Date,
        calendar: Calendar
    ) -> MonthlyHeroEdge {
        if kept.isEmpty {
            return rejected > 0 ? .badRecords : .noHistory
        }
        if let prior, current != nil {
            if prior.kind == .aboutAMonth {
                let days = calendar.dateComponents([.day], from: prior.sample.date, to: now).day ?? 99
                if days > 45 { return .incomplete }
            }
            return .ready
        }
        if kept.count <= 1 { return .brandNew }
        return .incomplete
    }

    private static func currentAnchor(
        kept: [MonthlyWeighSample],
        weighInKg: Double?,
        now: Date,
        thisStart: Date,
        nextStart: Date
    ) -> MonthlyWeighSample? {
        if let weighInKg, ProfileNumericBounds.isPlausibleWeighKg(weighInKg) {
            return MonthlyWeighSample(kg: weighInKg, date: now)
        }
        let inMonth = kept.filter { $0.date >= thisStart && $0.date < nextStart }
        if let latest = inMonth.max(by: { $0.date < $1.date }) { return latest }
        return kept.max(by: { $0.date < $1.date })
    }

    private static func priorAnchor(
        kept: [MonthlyWeighSample],
        now: Date,
        thisStart: Date,
        prevStart: Date,
        calendar: Calendar
    ) -> PriorPick? {
        let previous = kept.filter { $0.date >= prevStart && $0.date < thisStart }
        if !previous.isEmpty {
            let earlyCutoff = calendar.date(byAdding: .day, value: 7, to: prevStart) ?? thisStart
            let early = previous.filter { $0.date < earlyCutoff }.sorted { $0.date < $1.date }
            if let first = early.first {
                return PriorPick(sample: first, kind: .monthOpen)
            }
            let median = medianKg(previous.map(\.kg))
            let typical = previous.min(by: { abs($0.kg - median) < abs($1.kg - median) }) ?? previous[0]
            return PriorPick(sample: typical, kind: .typical)
        }

        // No calendar previous month. A weigh about 30 days back can still be "a month".
        let windowStart = calendar.date(byAdding: .day, value: -45, to: now) ?? now
        let windowEnd = calendar.date(byAdding: .day, value: -21, to: now) ?? now
        let target = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let candidates = kept.filter { $0.date >= windowStart && $0.date <= windowEnd && $0.date < thisStart }
        guard let nearest = candidates.min(by: {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        }) else { return nil }
        return PriorPick(sample: nearest, kind: .aboutAMonth)
    }

    // MARK: - Cleaning

    private static func partition(
        _ samples: [MonthlyWeighSample]
    ) -> (kept: [MonthlyWeighSample], rejected: Int) {
        var implausible = 0
        var plausible: [MonthlyWeighSample] = []
        for sample in samples.sorted(by: { $0.date < $1.date }) {
            guard sample.kg.isFinite, sample.date.timeIntervalSince1970.isFinite else {
                if sample.kg.isFinite == false { implausible += 1 }
                continue
            }
            if ProfileNumericBounds.isPlausibleWeighKg(sample.kg) {
                plausible.append(sample)
            } else {
                implausible += 1
            }
        }
        guard plausible.count >= 4 else {
            return (plausible, implausible)
        }
        let median = medianKg(plausible.map(\.kg))
        let band = max(6.0, median * 0.12)
        let kept = plausible.filter { abs($0.kg - median) <= band }
        if kept.count < 2 {
            return (plausible, implausible)
        }
        return (kept, implausible + (plausible.count - kept.count))
    }

    private static func sparkline(
        kept: [MonthlyWeighSample],
        from: Date,
        to: Date,
        calendar: Calendar
    ) -> [Double] {
        let start = calendar.startOfDay(for: min(from, to))
        let end = calendar.startOfDay(for: max(from, to))
        var buckets: [Date: [Double]] = [:]
        for sample in kept {
            let day = calendar.startOfDay(for: sample.date)
            guard day >= start, day <= end else { continue }
            buckets[day, default: []].append(sample.kg)
        }
        let days = buckets.keys.sorted()
        var values = days.map { medianKg(buckets[$0] ?? []) }
        if values.count > 14 {
            let last = values.count - 1
            var picked: [Double] = []
            for index in 0..<14 {
                let raw = Double(index) / 13.0 * Double(last)
                picked.append(values[Int(raw.rounded())])
            }
            values = picked
        }
        return values
    }

    static func medianKg(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    // MARK: - Direction, pace, intent

    private static func resolveIntent(currentKg: Double?, idealKg: Double?) -> MonthlyIntent {
        guard let currentKg, let idealKg, idealKg.isFinite, currentKg.isFinite else { return .lose }
        if idealKg < currentKg - 0.4 { return .lose }
        if idealKg > currentKg + 0.4 { return .gain }
        return .maintain
    }

    private static func resolveDirection(deltaKg: Double?, currentKg: Double?) -> MonthlyDirection {
        guard let deltaKg, let currentKg, currentKg > 0 else { return .unknown }
        let band = max(0.25, currentKg * 0.003)
        if abs(deltaKg) < band { return .stable }
        return deltaKg < 0 ? .loss : .gain
    }

    private static func resolvePace(
        deltaKg: Double?,
        currentKg: Double?,
        priorDate: Date?,
        currentDate: Date,
        edge: MonthlyHeroEdge,
        calendar: Calendar
    ) -> MonthlyPace {
        guard edge == .ready, let deltaKg, let currentKg, let priorDate else { return .calm }
        let days = max(calendar.dateComponents([.day], from: priorDate, to: currentDate).day ?? 30, 7)
        let weeks = Double(days) / 7.0
        let safeLoss = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: currentKg) * weeks
        let safeGain = TargetFeasibility.maxSafeGainKgPerWeek(currentKg: currentKg) * weeks
        if deltaKg < 0, -deltaKg > max(safeLoss * 1.15, currentKg * 0.04) {
            return .fastLoss
        }
        if deltaKg > 0, deltaKg > max(safeGain * 1.35, 2.0) {
            return .fastGain
        }
        return .calm
    }

    // MARK: - Festival + units

    private struct Festival {
        var title: String
        var emoji: String
    }

    static func festival(for month: Int) -> (title: String, emoji: String) {
        let fest = festivalValue(month)
        return (fest.title, fest.emoji)
    }

    private static func festivalValue(_ month: Int) -> Festival {
        switch month {
        case 1: return Festival(title: "New year, same scale", emoji: "🎆")
        case 2: return Festival(title: "Short month, sharp aim", emoji: "💌")
        case 3: return Festival(title: "The thaw", emoji: "🌱")
        case 4: return Festival(title: "April, honestly", emoji: "🌧️")
        case 5: return Festival(title: "Blossom month", emoji: "🌸")
        case 6: return Festival(title: "Long light", emoji: "☀️")
        case 7: return Festival(title: "High summer", emoji: "🏖️")
        case 8: return Festival(title: "Late heat", emoji: "🍉")
        case 9: return Festival(title: "New season", emoji: "🍂")
        case 10: return Festival(title: "October audit", emoji: "🎃")
        case 11: return Festival(title: "Gratitude, measured", emoji: "🦃")
        case 12: return Festival(title: "Festive, not feral", emoji: "❄️")
        default: return Festival(title: "This month", emoji: "✨")
        }
    }

    private struct UnitSpec {
        var emoji: String
        var singular: String
        var plural: String
        var grams: Double
    }

    /// Food-sized mass. Festival units go first; the picker keeps the count human (about 2 to 8).
    static func relatableUnit(absKg: Double, month: Int) -> MonthlyRelatableUnit? {
        let grams = absKg * 1000
        guard grams.isFinite, grams >= 50 else { return nil }
        let options = unitCatalog(month: month)
        var best: (spec: UnitSpec, count: Double, score: Double)?
        for (index, spec) in options.enumerated() {
            let count = grams / spec.grams
            let rounded = (count * 10).rounded() / 10
            var score = 0.0
            if (2.0...8.0).contains(rounded) {
                score += 100
            } else if (0.8...14).contains(rounded) {
                score += 40
            } else {
                score += 8
            }
            score -= abs(rounded - 4) * 1.5
            score -= Double(index) * 4
            if rounded > 24 { score -= 40 }
            if rounded < 0.8 { score -= 25 }
            if best == nil || score > best!.score {
                best = (spec, rounded, score)
            }
        }
        guard let best, best.count >= 0.8 else { return nil }
        let label = countLabel(best.count)
        let numeric = (label as NSString).doubleValue
        let noun = abs(numeric - 1) < 0.05 ? best.spec.singular : best.spec.plural
        let shown = max(Int(best.count.rounded()), 1)
        return MonthlyRelatableUnit(
            emoji: best.spec.emoji,
            countLabel: label,
            phrase: "\(label) \(noun)",
            burstCount: min(shown, 8)
        )
    }

    private static func unitCatalog(month: Int) -> [UnitSpec] {
        let rice = UnitSpec(emoji: "🍚", singular: "bowl of rice", plural: "bowls of rice", grams: 180)
        let egg = UnitSpec(emoji: "🥚", singular: "egg", plural: "eggs", grams: 55)
        let apple = UnitSpec(emoji: "🍎", singular: "apple", plural: "apples", grams: 180)
        let orange = UnitSpec(emoji: "🍊", singular: "orange", plural: "oranges", grams: 180)
        let chocolate = UnitSpec(emoji: "🍫", singular: "chocolate bar", plural: "chocolate bars", grams: 45)
        let dumpling = UnitSpec(emoji: "🥟", singular: "dumpling", plural: "dumplings", grams: 30)
        let mango = UnitSpec(emoji: "🥭", singular: "mango", plural: "mangoes", grams: 300)
        let soda = UnitSpec(emoji: "🥤", singular: "can of soda", plural: "cans of soda", grams: 330)
        let melon = UnitSpec(emoji: "🍉", singular: "watermelon", plural: "watermelons", grams: 4000)
        let scoop = UnitSpec(emoji: "🍨", singular: "scoop of ice cream", plural: "scoops of ice cream", grams: 70)
        let pumpkin = UnitSpec(emoji: "🎃", singular: "small pumpkin", plural: "small pumpkins", grams: 900)
        let pie = UnitSpec(emoji: "🥧", singular: "slice of pie", plural: "slices of pie", grams: 150)
        let cookie = UnitSpec(emoji: "🍪", singular: "cookie", plural: "cookies", grams: 30)
        let bag = UnitSpec(emoji: "🧺", singular: "bag of rice", plural: "bags of rice", grams: 1000)
        switch month {
        case 1: return [orange, dumpling, rice, egg, bag]
        case 2: return [chocolate, dumpling, rice, bag]
        case 3: return [egg, rice, apple, bag]
        case 4: return [rice, egg, apple, bag]
        case 5: return [mango, rice, apple, bag]
        case 6: return [mango, soda, rice, melon, bag]
        case 7: return [melon, mango, soda, rice, bag]
        case 8: return [melon, scoop, mango, rice, bag]
        case 9: return [apple, rice, egg, bag]
        case 10: return [pumpkin, apple, rice, bag]
        case 11: return [pie, apple, rice, bag]
        case 12: return [cookie, orange, chocolate, rice, bag]
        default: return [rice, egg, apple, bag]
        }
    }

    private static func countLabel(_ count: Double) -> String {
        let rounded = (count * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return String(Int(rounded.rounded()))
        }
        return String(format: "%.1f", rounded)
    }

    // MARK: - Copy

    private static func bigWord(edge: MonthlyHeroEdge, direction: MonthlyDirection) -> String {
        switch edge {
        case .brandNew: return "DAY ONE"
        case .noHistory: return "NO TAPE"
        case .incomplete: return "NOT YET"
        case .badRecords: return "CLEANED UP"
        case .ready:
            switch direction {
            case .loss: return "DOWN"
            case .gain: return "UP"
            case .stable: return "STEADY"
            case .unknown: return "HERE"
            }
        }
    }

    private static func sinceLine(for prior: PriorPick?, edge: MonthlyHeroEdge, calendar: Calendar) -> String {
        guard edge == .ready, let prior else { return "" }
        let name = monthName(prior.sample.date, calendar: calendar)
        switch prior.kind {
        case .monthOpen: return "since early \(name)"
        case .typical: return "versus a typical \(name)"
        case .aboutAMonth: return "versus about a month ago"
        }
    }

    static func ruleInsight(
        name: String,
        edge: MonthlyHeroEdge,
        direction: MonthlyDirection,
        intent: MonthlyIntent,
        pace: MonthlyPace,
        deltaKg: Double?,
        unit: MonthlyRelatableUnit?,
        rejected: Int,
        units: PreferredUnitSystem
    ) -> String {
        let lead = name.isEmpty ? "" : "\(name), "
        switch edge {
        case .brandNew:
            return "\(lead)first number on the board. No last month to roast, and I will not invent one."
        case .noHistory:
            return "\(lead)there is no history yet. This card refuses to fake a drop."
        case .incomplete:
            return "\(lead)last month is too thin to call. No invented loss, no invented win."
        case .badRecords:
            if rejected > 0 {
                let noun = rejected == 1 ? "reading" : "readings"
                return "\(lead)I tossed \(rejected) nonsense \(noun). What's left is the honest line."
            }
            return "\(lead)those records don't hold up. Nothing to celebrate until the scale tells the truth."
        case .ready:
            let mass = deltaKg.map { UnitFormat.massDeltaString($0, system: units) } ?? "unchanged"
            let thing = unit?.phrase ?? "a small shift"
            let junk: String = {
                guard rejected > 0 else { return "" }
                let noun = rejected == 1 ? "reading" : "readings"
                return "I tossed \(rejected) nonsense \(noun). "
            }()
            switch direction {
            case .loss:
                if pace == .fastLoss {
                    return "\(lead)\(junk)\(thing) down (\(mass)) is a sprint. Bodies prefer a jog."
                }
                if intent == .gain {
                    return "\(lead)\(junk)lighter by \(mass) (about \(thing)) while the goal is to build. Eat like you mean it."
                }
                return "\(lead)\(junk)\(mass) since last month. About \(thing) you are no longer hauling."
            case .gain:
                if intent == .gain, pace != .fastGain {
                    return "\(lead)\(junk)up \(mass), about \(thing). That's the direction you asked for. Keep it boring."
                }
                if pace == .fastGain {
                    return "\(lead)\(junk)up about \(thing) (\(mass)). That's a lot for one month."
                }
                return "\(lead)\(junk)up about \(thing) (\(mass)). Salt, sleep, or seconds. Not a verdict."
            case .stable:
                return "\(lead)\(junk)basically flat (\(mass)). Consistency is the unsexy superpower."
            case .unknown:
                return "\(lead)\(junk)not enough signal to call the month."
            }
        }
    }

    static func monthlyAction(
        month: Int,
        edge: MonthlyHeroEdge,
        direction: MonthlyDirection,
        intent: MonthlyIntent,
        pace: MonthlyPace
    ) -> String {
        switch edge {
        case .brandNew, .noHistory:
            return "This month: weigh most mornings. Same scale, after the bathroom, before breakfast."
        case .incomplete:
            return "This month: four morning weighs. Then we can compare for real."
        case .badRecords:
            return "This month: one clean morning weigh. Barefoot, still, same time."
        case .ready:
            if pace == .fastLoss {
                if month == 12 {
                    return "This month: one festive plate, not five. If the drop wasn't planned, tell a clinician."
                }
                if (6...8).contains(month) {
                    return "This month: eat a real lunch in the long light. Unplanned drops get a clinician, not a trophy."
                }
                return "This month: add one full meal back. If you didn't plan this drop, tell a clinician."
            }
            if pace == .fastGain {
                return "This month: a 20-minute walk after the meal you repeat. If you feel off, tell a clinician."
            }
            switch direction {
            case .loss:
                if intent == .gain {
                    return "This month: add a palm of protein to the meal you already eat."
                }
                return holdLine(month)
            case .gain:
                if intent == .gain {
                    return buildLine(month)
                }
                return trimLine(month)
            case .stable:
                if intent == .maintain {
                    return "This month: leave the plan alone. Keep the morning weigh."
                }
                return nudgeLine(month)
            case .unknown:
                return "This month: four morning weighs, then we talk."
            }
        }
    }

    private static func holdLine(_ month: Int) -> String {
        switch month {
        case 1: return "This month: keep last month's plate. New year, same dinner."
        case 6, 7: return "This month: keep the same plate, and walk once while the evening is still bright."
        case 10: return "This month: keep the plate. Candy is a guest, not a roommate."
        case 11: return "This month: one grateful plate, then the kitchen closes."
        case 12: return "This month: keep the usual plate, and cap the festive one at a single serving."
        default: return "This month: keep the same dinner plate, and weigh each morning."
        }
    }

    private static func trimLine(_ month: Int) -> String {
        switch month {
        case 6, 7, 8: return "This month: a 20-minute walk after dinner, while the light is still up."
        case 11: return "This month: vegetables first at the big meal, then everything else."
        case 12: return "This month: the second festive drink becomes sparkling water."
        default: return "This month: a 20-minute walk after dinner, every day."
        }
    }

    private static func buildLine(_ month: Int) -> String {
        switch month {
        case 12: return "This month: add a palm of food to dinner, not a second dessert."
        case 6, 7, 8: return "This month: a real lunch in the heat, plus the walk you already like."
        default: return "This month: add one planned snack with protein. Same time, most days."
        }
    }

    private static func nudgeLine(_ month: Int) -> String {
        switch month {
        case 6: return "This month: one extra walk in the long evening."
        case 12: return "This month: swap the second festive drink for water."
        case 1: return "This month: vegetables first at dinner. The resolution can be that small."
        default: return "This month: vegetables first at dinner, every night."
        }
    }

    private static func medicalNote(
        pace: MonthlyPace,
        currentKg: Double?,
        deltaKg: Double?,
        priorDate: Date?,
        currentDate: Date,
        units: PreferredUnitSystem,
        calendar: Calendar
    ) -> String? {
        guard let currentKg, let priorDate else { return nil }
        let days = max(calendar.dateComponents([.day], from: priorDate, to: currentDate).day ?? 30, 7)
        let weeks = Double(days) / 7.0
        switch pace {
        case .fastLoss:
            let safe = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: currentKg) * weeks
            let safeText = UnitFormat.massString(safe, system: units, fractionDigits: 1)
            return "A calmer month from here is about \(safeText) down. Faster than that, if you didn't plan it, belongs with a clinician."
        case .fastGain:
            _ = deltaKg
            return "A little up can be dinner and salt. This much in a month, if you feel unwell, is a clinician conversation."
        case .calm:
            return nil
        }
    }

    // MARK: - Dates

    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? calendar.startOfDay(for: date)
    }

    private static func monthName(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }

}
