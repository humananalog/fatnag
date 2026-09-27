import Foundation
import SwiftUI

/// On-track / at-risk / ahead / crushed for the home weekly-goal hero.
enum WeeklyTrackBand: String, Equatable, Sendable {
    case crushed
    case ahead
    case onTrack
    case atRisk
    case unknown

    var statusLabel: String {
        switch self {
        case .crushed: return "Crushed"
        case .ahead: return "Ahead"
        case .onTrack: return "On track"
        case .atRisk: return "At risk"
        case .unknown: return "Set baseline"
        }
    }
}

/// Daily coaching targets derived from profile + activity (not logged food %).
struct DailyGoalTargets: Equatable, Sendable {
    var steps: Int
    var maxCalories: Int
    /// Key macro to hit (grams).
    var proteinGrams: Int
    var proteinLabel: String
    /// Key micronutrient priority / cap.
    var microName: String
    var microTargetLine: String
    /// True only when Apple Health has a *robust* nutrition log today (not a stray snack).
    var intakeTracked: Bool

    var honestyLine: String {
        intakeTracked
            ? "Logged vs target (Apple Health nutrition)"
            : "Daily targets · food not logged in Health"
    }
}

/// Compact home target chip when nutrition gauges are hidden.
struct HomeDailyTargetChip: Equatable, Sendable, Identifiable {
    var id: String { title }
    var title: String
    var valueLine: String
}

/// One home row: today's progress against a daily target.
struct DailyMetricProgress: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case steps
        case energy
        case protein
        case micro
    }

    enum Status: String, Equatable, Sendable {
        /// Hit or under-cap for the day.
        case complete
        /// Partial progress with Health samples.
        case inProgress
        /// No sample yet (or nutrition missing).
        case unknown
        /// Over a calorie max.
        case over
    }

    var kind: Kind
    var title: String
    /// e.g. "4,200 / 8,500"
    var currentLine: String
    /// 0...1.2 for bar fill (may exceed 1 when over).
    var fraction: Double
    var status: Status
    var accessibilitySummary: String
}

/// One-screen weekly goal snapshot for Home.
struct WeeklyGoalSurface: Equatable, Sendable {
    var completionPercent: Int
    var band: WeeklyTrackBand
    var weekTitle: String
    /// Locked Monday (week-start) weigh-in baseline (kg). Hero number on Progress.
    var weekStartKg: Double?
    /// Absolute Sunday weigh-in target (kg). Hero number on Home / Progress.
    var sundayTargetKg: Double?
    /// Signed weekly delta (kg), e.g. -0.35.
    var weeklyDeltaKg: Double
    var detailLine: String
    /// What's ahead for the rest of TODAY (local clock), not tomorrow-after-weigh-in.
    var todayAdvice: String
    var mealSuggestion: String?
    var energySnapshot: WeeklyEnergyBalanceSnapshot?
    var targets: DailyGoalTargets
    /// Today completion for steps / move / (nutrition only when robustly logged).
    var todayProgress: [DailyMetricProgress]
    /// Shown when nutrition is not robustly logged: kcal / protein / micro as targets, not gauges.
    var dailyTargetChips: [HomeDailyTargetChip]
    /// ETA to ideal weight at current pace vs planned goal date.
    var macroGoalETA: MacroGoalETA
    /// Fraction of ISO week elapsed (0...1), for pace math.
    var weekElapsedFraction: Double
    var expectedPaceFraction: Double
    /// How this week's target was shaped (catch-up / accelerate / aggressive).
    var targetMode: WeeklyTargetMode
}

/// Atmosphere for the home weekly-goal hero + Progress haze.
/// Color rules: band semantics (green / lime / coral) tinted by `ScalePaletteUniverse`
/// (male Glacier Forge vs female Bloom Copper). Factory: `forBand(_:colorScheme:sex:)`.
/// Dark scheme keeps tinted haze on void with ivory ink for contrast.
struct WeeklyGoalAtmosphere: Equatable {
    let top: Color
    let mid: Color
    let bottom: Color
    let hazeA: Color
    let hazeB: Color
    let ink: Color
    let muted: Color
    let accent: Color
    let panel: Color
}

/// Pure weekly-goal home math: progress %, track band, daily targets, today-ahead advice.
enum WeeklyGoalSurfaceEngine {
    /// ~7700 kcal ≈ 1 kg adipose (coaching ballpark, not a medical claim).
    static let kcalPerKg: Double = 7700

    static func build(
        weeklyGoal: WeeklyMiniGoal,
        currentKg: Double?,
        profile: UserBodyProfile,
        digest: FitnessDigest?,
        recentWeights: [HealthWeightSample] = [],
        targetMode: WeeklyTargetMode = .aggressive,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyGoalSurface {
        let elapsed = weekElapsedFraction(now: now, calendar: calendar)
        let expected = max(0.08, elapsed)
        let rawFraction = weeklyGoal.progressFraction(currentKg: currentKg)
        let fraction = rawFraction ?? 0
        let percent = Int((min(max(fraction, 0), 1.2) * 100).rounded())

        var band = trackBand(
            progressFraction: rawFraction,
            expectedPace: expected,
            recovery: digest?.recovery?.band,
            sleepHours: digest?.sleepHoursLastNight,
            stepsToday: digest?.stepsToday
        )

        let targets = dailyTargets(
            profile: profile,
            currentKg: currentKg,
            weeklyDeltaKg: weeklyGoal.targetDeltaKg,
            digest: digest,
            band: band,
            targetMode: targetMode
        )

        let energy = WeeklyEnergyBalanceEvaluator.evaluate(
            profile: profile,
            weeklyGoal: weeklyGoal,
            currentKg: currentKg,
            recentWeights: recentWeights,
            digest: digest,
            targetMaxKcal: targets.maxCalories,
            now: now,
            calendar: calendar
        )

        // Energy diagnosis can push at-risk when overeating while "on track" by kg pace alone.
        if case .overeatingWhileActive = energy.diagnosis, band == .onTrack || band == .ahead {
            band = .atRisk
        }
        if case .underMoving = energy.diagnosis, band == .onTrack {
            band = .atRisk
        }

        let detail: String = {
            if currentKg == nil || weeklyGoal.weekStartKg == nil {
                return "Weigh in once to lock this week's baseline."
            }
            let base = weeklyGoal.statusLine(currentKg: currentKg)
            switch targetMode {
            case .hardcoreCatchUp:
                return base + " Hardcore catch-up week."
            case .accelerate:
                return base + " Accelerate: no coast."
            case .aggressive, .hold:
                return base
            }
        }()

        let meals = WeeklyEnergyBalanceEvaluator.mealSuggestion(
            diet: profile.dietPreference,
            maxKcal: targets.maxCalories,
            proteinGrams: targets.proteinGrams
        )

        let advice = todayAdvice(
            name: profile.greetingName,
            band: band,
            weeklyGoal: weeklyGoal,
            targets: targets,
            digest: digest,
            diet: profile.dietPreference,
            energy: energy,
            mealLine: meals,
            targetMode: targetMode,
            sex: profile.sex,
            unitSystem: PreferredUnitSystemStore.load(),
            now: now,
            calendar: calendar
        )

        let showMeals: String? = {
            switch energy.diagnosis {
            case .overeatingWhileActive, .underMoving:
                return meals
            default:
                return nil
            }
        }()

        let units = PreferredUnitSystemStore.load()
        let eta = MacroGoalETA.compute(
            currentKg: currentKg,
            idealKg: profile.idealWeightKg,
            plannedDate: profile.goalDate,
            recentWeights: recentWeights,
            weeklyDeltaKg: weeklyGoal.targetDeltaKg,
            sex: profile.sex,
            unitSystem: units,
            now: now,
            calendar: calendar
        )

        let progress = todayMetricProgress(targets: targets, digest: digest)
        let chips = Self.dailyTargetChips(
            targets: targets,
            showNutritionTargets: !targets.intakeTracked,
            sex: profile.sex,
            diet: profile.dietPreference
        )
        let sundayKg = sundayTargetKg(from: weeklyGoal, currentKg: currentKg)

        return WeeklyGoalSurface(
            completionPercent: percent,
            band: band,
            weekTitle: weeklyGoal.title,
            weekStartKg: weeklyGoal.weekStartKg,
            sundayTargetKg: sundayKg,
            weeklyDeltaKg: weeklyGoal.targetDeltaKg,
            detailLine: detail,
            todayAdvice: advice,
            mealSuggestion: showMeals,
            energySnapshot: energy,
            targets: targets,
            todayProgress: progress,
            dailyTargetChips: chips,
            macroGoalETA: eta,
            weekElapsedFraction: elapsed,
            expectedPaceFraction: expected,
            targetMode: targetMode
        )
    }

    /// Absolute Sunday target kg. Prefer live math from week-start / current + clamped delta.
    /// Never trust a freeform title number (pacing lines embed other "X kg" tokens).
    static func sundayTargetKg(from weeklyGoal: WeeklyMiniGoal, currentKg: Double?) -> Double? {
        if let start = weeklyGoal.weekStartKg, abs(weeklyGoal.targetDeltaKg) > 0.001 {
            return round2(start + weeklyGoal.targetDeltaKg)
        }
        if let current = currentKg, abs(weeklyGoal.targetDeltaKg) > 0.001 {
            return round2(current + weeklyGoal.targetDeltaKg)
        }
        if let parsed = parseSundayKg(from: weeklyGoal.title) {
            return parsed
        }
        return nil
    }

    /// Parse only `"Sunday 82.40 kg"` (number immediately after Sunday). Ignores other kg tokens.
    static func parseSundayKg(from title: String) -> Double? {
        let cleaned = title.replacingOccurrences(of: ",", with: ".")
        guard let regex = try? NSRegularExpression(
            pattern: #"sunday\s+(\d+(?:\.\d+)?)\s*kg"#,
            options: [.caseInsensitive]
        ),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let range = Range(match.range(at: 1), in: cleaned),
              let value = Double(cleaned[range])
        else { return nil }
        return value
    }

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    // MARK: - Pace / band

    static func weekElapsedFraction(now: Date, calendar: Calendar = .current) -> Double {
        // Mon 00:00 → next Mon 00:00 (never locale Sunday-first weekOfYear).
        let cal = MondayCardEngine.mondayBasedCalendar(from: calendar)
        let start = MondayCardEngine.startOfWeekMonday(now: now, calendar: calendar)
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0.5 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    static func trackBand(
        progressFraction: Double?,
        expectedPace: Double,
        recovery: RecoveryLoadHeuristic.Band?,
        sleepHours: Double? = nil,
        stepsToday: Double?
    ) -> WeeklyTrackBand {
        guard let progressFraction else { return .unknown }

        var band: WeeklyTrackBand
        if progressFraction >= 1.0 {
            band = .crushed
        } else if progressFraction >= expectedPace + 0.18 {
            band = .ahead
        } else if progressFraction >= expectedPace - 0.18 {
            band = .onTrack
        } else {
            band = .atRisk
        }

        // Only tip pace down for red recovery when sleep was actually short / missing.
        // Strong HealthKit sleep nights must not flip On track → At risk.
        let sleepLooksSolid = (sleepHours ?? 0) >= 6.5
        if recovery == .red, !sleepLooksSolid, band == .onTrack || band == .ahead {
            band = .atRisk
        }
        if recovery == .red, !sleepLooksSolid, band == .crushed {
            band = .ahead
        }
        if let steps = stepsToday, steps < 2500, expectedPace > 0.35, band == .onTrack {
            band = .atRisk
        }
        if recovery == .green, band == .atRisk, progressFraction >= expectedPace - 0.05 {
            band = .onTrack
        }
        return band
    }

    // MARK: - Targets

    static func mifflinBMR(profile: UserBodyProfile, weightKg: Double) -> Double {
        let w = max(40, weightKg)
        let h = max(120, profile.heightCm)
        let a = max(14, profile.ageYears)
        switch profile.sex {
        case .male:
            return 10 * w + 6.25 * h - 5 * a + 5
        case .female:
            return 10 * w + 6.25 * h - 5 * a - 161
        }
    }

    static func dailyTargets(
        profile: UserBodyProfile,
        currentKg: Double?,
        weeklyDeltaKg: Double,
        digest: FitnessDigest?,
        band: WeeklyTrackBand,
        targetMode: WeeklyTargetMode = .aggressive
    ) -> DailyGoalTargets {
        let weight = currentKg ?? profile.idealWeightKg
        let bmr = mifflinBMR(profile: profile, weightKg: weight)

        // Prefer measured spend when Health has active energy.
        let spend = WeeklyEnergyBalanceEvaluator.estimatedDailySpendKcal(
            profile: profile,
            weightKg: weight,
            digest: digest
        )
        let tdee = spend

        let dailyDeltaKcal = (weeklyDeltaKg * kcalPerKg) / 7.0
        var maxCal = tdee + dailyDeltaKcal
        let floor = bmr * 1.15
        maxCal = max(floor, maxCal)
        // Biology ceiling: don't invent surplus above a modest buffer when cutting hard.
        maxCal = min(tdee + 500, maxCal)

        var steps = 8_500
        if band == .atRisk || targetMode == .hardcoreCatchUp { steps = 10_500 }
        if targetMode == .accelerate { steps = max(steps, 9_500) }
        // Ahead of week pace: do not coast with a soft step floor.
        if band == .ahead || band == .crushed {
            steps = max(steps, targetMode == .accelerate ? 9_500 : 8_500)
        }
        if digest?.recovery?.band == .red, (digest?.sleepHoursLastNight ?? 0) < 6.5 {
            steps = min(steps, 7_000)
        }
        // Don't inflate steps above what they already hit when intake is the issue.
        if let today = digest?.stepsToday, today > Double(steps), today < 12_000 {
            steps = Int(today.rounded())
        }

        let proteinPerKg = weeklyDeltaKg < -0.15 || targetMode == .hardcoreCatchUp ? 1.8 : 1.6
        let protein = Int((weight * proteinPerKg).rounded())
        let micro = microPriority(profile: profile, weeklyDeltaKg: weeklyDeltaKg, diet: profile.dietPreference)
        let intakeTracked = hasRobustNutritionLog(digest: digest)

        return DailyGoalTargets(
            steps: steps,
            maxCalories: Int(maxCal.rounded()),
            proteinGrams: max(70, protein),
            proteinLabel: "Protein",
            microName: micro.name,
            microTargetLine: micro.line,
            intakeTracked: intakeTracked
        )
    }

    /// People rarely log full macros in Health. Require real meal signal before showing nutrition gauges.
    static func hasRobustNutritionLog(digest: FitnessDigest?) -> Bool {
        let energy = digest?.dietaryEnergyKcalToday ?? 0
        let protein = digest?.dietaryProteinGramsToday ?? 0
        return energy >= 200 && protein >= 15
    }

    static func dailyTargetChips(
        targets: DailyGoalTargets,
        showNutritionTargets: Bool,
        sex: UserBodyProfile.Sex = .male,
        diet: DietPreference = .omnivore
    ) -> [HomeDailyTargetChip] {
        guard showNutritionTargets else { return [] }
        return [
            HomeDailyTargetChip(
                title: "Energy",
                valueLine: CoachVoice.energyChipLine(
                    kcal: targets.maxCalories,
                    diet: diet,
                    sex: sex
                )
            ),
            HomeDailyTargetChip(
                title: targets.proteinLabel,
                valueLine: CoachVoice.proteinChipLine(
                    grams: targets.proteinGrams,
                    diet: diet,
                    sex: sex
                )
            ),
            HomeDailyTargetChip(title: targets.microName, valueLine: targets.microTargetLine)
        ]
    }

    /// Today completion rows for home.
    /// Activity gauges always (steps + move). Nutrition gauges only with robust Health food log.
    static func todayMetricProgress(
        targets: DailyGoalTargets,
        digest: FitnessDigest?
    ) -> [DailyMetricProgress] {
        let stepsCurrent = digest?.stepsToday
        let steps = progressRow(
            kind: .steps,
            title: "Steps",
            current: stepsCurrent,
            target: Double(targets.steps),
            higherIsBetter: true,
            formatCurrent: { Int($0.rounded()).formatted() },
            formatTarget: { Int($0.rounded()).formatted() }
        )

        var rows: [DailyMetricProgress] = [steps]

        let moveBurn = digest?.activeEnergyKcalToday
        let moveTarget = max(250.0, Double(targets.maxCalories) * 0.22)
        if let burn = moveBurn {
            rows.append(
                progressRow(
                    kind: .energy,
                    title: "Move",
                    current: burn,
                    target: moveTarget,
                    higherIsBetter: true,
                    formatCurrent: { "\(Int($0.rounded()))" },
                    formatTarget: { "\(Int($0.rounded())) burn" }
                )
            )
        }

        guard targets.intakeTracked else {
            return rows
        }

        // Robust nutrition log: replace Move with dietary Energy when available, add protein + micro.
        if let dietKcal = digest?.dietaryEnergyKcalToday, dietKcal > 0 {
            // Keep Move if we already added it; also show dietary Energy as the energy kind
            // Prefer a single Energy gauge from diet when logged.
            rows.removeAll { $0.kind == .energy && $0.title == "Move" }
            rows.append(
                progressRow(
                    kind: .energy,
                    title: "Energy",
                    current: dietKcal,
                    target: Double(targets.maxCalories),
                    higherIsBetter: false,
                    formatCurrent: { "\(Int($0.rounded()))" },
                    formatTarget: { "\(Int($0.rounded())) max" }
                )
            )
        }

        if let proteinCurrent = digest?.dietaryProteinGramsToday, proteinCurrent > 0 {
            rows.append(
                progressRow(
                    kind: .protein,
                    title: targets.proteinLabel,
                    current: proteinCurrent,
                    target: Double(targets.proteinGrams),
                    higherIsBetter: true,
                    formatCurrent: { "\(Int($0.rounded()))" },
                    formatTarget: { "\(Int($0.rounded())) g" }
                )
            )
        }

        let microTarget = microNumericTarget(name: targets.microName, line: targets.microTargetLine)
        let microCurrent: Double? = {
            switch targets.microName.lowercased() {
            case "fiber": return digest?.dietaryFiberGramsToday
            case "iron": return digest?.dietaryIronMgToday
            case "potassium": return digest?.dietaryPotassiumMgToday
            default: return nil
            }
        }()
        let microUnit = targets.microName.lowercased() == "fiber" ? "g" : "mg"
        if let microCurrent, microCurrent > 0, let microTarget, microTarget > 0 {
            rows.append(
                progressRow(
                    kind: .micro,
                    title: targets.microName,
                    current: microCurrent,
                    target: microTarget,
                    higherIsBetter: true,
                    formatCurrent: { "\(Int($0.rounded()))" },
                    formatTarget: { "\(Int($0.rounded())) \(microUnit)" }
                )
            )
        }

        return rows
    }

    private static func progressRow(
        kind: DailyMetricProgress.Kind,
        title: String,
        current: Double?,
        target: Double,
        higherIsBetter: Bool,
        formatCurrent: (Double) -> String,
        formatTarget: (Double) -> String
    ) -> DailyMetricProgress {
        guard let current, target > 0 else {
            return DailyMetricProgress(
                kind: kind,
                title: title,
                currentLine: "- / \(formatTarget(target))",
                fraction: 0,
                status: .unknown,
                accessibilitySummary: "\(title) unknown today."
            )
        }
        let raw = current / target
        let fraction = min(max(raw, 0), 1.2)
        let status: DailyMetricProgress.Status
        if higherIsBetter {
            status = raw >= 1 ? .complete : .inProgress
        } else if raw > 1.02 {
            status = .over
        } else if raw >= 0.85 {
            status = .complete
        } else {
            status = .inProgress
        }
        let line = "\(formatCurrent(current)) / \(formatTarget(target))"
        let pct = Int((min(raw, 1.2) * 100).rounded())
        return DailyMetricProgress(
            kind: kind,
            title: title,
            currentLine: line,
            fraction: fraction,
            status: status,
            accessibilitySummary: "\(title) \(pct) percent today. \(line)."
        )
    }

    /// Parse "≥ 30 g" / "≥ 18 mg" / "≥ 3,500 mg" style micro lines.
    static func microNumericTarget(name: String, line: String) -> Double? {
        let cleaned = line.replacingOccurrences(of: ",", with: "")
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)"#) else { return nil }
        let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        guard let match = regex.firstMatch(in: cleaned, range: range),
              let r = Range(match.range(at: 1), in: cleaned),
              let value = Double(cleaned[r])
        else {
            switch name.lowercased() {
            case "fiber": return 30
            case "iron": return 18
            case "potassium": return 3500
            default: return nil
            }
        }
        return value
    }

    private static func microPriority(
        profile: UserBodyProfile,
        weeklyDeltaKg: Double,
        diet: DietPreference
    ) -> (name: String, line: String) {
        if diet == .vegan || diet == .vegetarian {
            return ("Iron", "Hit ≥ 18 mg · pair with vitamin C")
        }
        if profile.sex == .female {
            return ("Iron", "Prioritize ≥ 18 mg with meals")
        }
        if weeklyDeltaKg < -0.1 {
            return ("Fiber", "Hit ≥ 30 g · keeps the cut sane")
        }
        return ("Potassium", "Aim ≥ 3,500 mg from food")
    }

    // MARK: - Today-ahead advice

    static func todayAdvice(
        name: String,
        band: WeeklyTrackBand,
        weeklyGoal: WeeklyMiniGoal,
        targets: DailyGoalTargets,
        digest: FitnessDigest?,
        diet: DietPreference,
        energy: WeeklyEnergyBalanceSnapshot,
        mealLine: String,
        targetMode: WeeklyTargetMode = .aggressive,
        sex: UserBodyProfile.Sex = .male,
        unitSystem: PreferredUnitSystem = .metric,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let who = CoachVoice.who(name, sex: sex)
        let recovery = digest?.recovery?.band
        let sleep = digest?.sleepHoursLastNight
        let hour = calendar.component(.hour, from: now)
        let dayPart: String = {
            if hour < 11 { return "this morning" }
            if hour < 17 { return "this afternoon" }
            return "tonight"
        }()
        let energyCap = CoachVoice.energyBudgetPhrase(
            kcal: targets.maxCalories,
            diet: diet,
            sex: sex
        )
        let proteinBit = CoachVoice.proteinPhrase(
            grams: targets.proteinGrams,
            diet: diet,
            sex: sex
        )

        // Energy diagnosis wins over generic step pep talks.
        switch energy.diagnosis {
        case .overeatingWhileActive(_, _, let maxK, _, let obs, let days):
            let massBit = UnitFormat.massDeltaString(obs, system: unitSystem)
            let daysBit = String(format: "%.0f", days)
            let cap = CoachVoice.energyBudgetPhrase(kcal: maxK, diet: diet, sex: sex)
            switch sex {
            case .female:
                return "\(who), you moved plenty, but the scale barely budged (\(massBit) over \(daysBit) days). That usually means the plates ran generous. \(dayPart.capitalized): keep it to \(cap). You've got this. Open Meal plan."
            case .male:
                return "\(who), you're moving but the scale barely budged (\(massBit) / \(daysBit)d). That's intake, not steps. Get your act together: \(cap) \(dayPart). Open Meal plan."
            }
        case .underMoving(_, let exp, let obs, _):
            let obsBit = UnitFormat.massDeltaString(obs, system: unitSystem)
            let expBit = UnitFormat.massDeltaString(exp, system: unitSystem)
            switch sex {
            case .female:
                return "\(who), movement was soft and weight went \(obsBit) (wanted \(expBit)). \(dayPart.capitalized): \(energyCap), then a cheerful walk. Proud you're checking in. Open Meal plan."
            case .male:
                return "\(who), movement was soft and weight went \(obsBit) (wanted \(expBit)). \(dayPart.capitalized): \(energyCap), then walk. Open Meal plan."
            }
        case .aheadOfEnergy, .onPace, .insufficientData:
            break
        }

        if recovery == .red, (sleep ?? 0) < 6.5 {
            switch sex {
            case .female:
                return "\(who), your body is asking for gentleness after a short night. \(dayPart.capitalized): easy day, \(proteinBit), early lights-out, \(energyCap). Rest is part of the glow."
            case .male:
                return "\(who), recovery is flagged soft after a short night. \(dayPart.capitalized): easy day, \(proteinBit), early lights-out, stay \(energyCap)."
            }
        }
        if recovery == .green, let sleep, sleep >= 6.5 {
            // Do not bury a strong sleep night under unrelated pep talk.
            // Fall through to pace / mode lines below.
        } else if let sleep, sleep < 6.0 {
            switch sex {
            case .female:
                return "\(who), \(String(format: "%.1f", sleep)) hours of sleep is thin. Protect bedtime \(dayPart), keep \(energyCap) with \(proteinBit). You're still showing up."
            case .male:
                return "\(who), \(String(format: "%.1f", sleep)) h sleep is thin. Protect bedtime \(dayPart), stay \(energyCap) with \(proteinBit)."
            }
        }

        if targetMode == .hardcoreCatchUp {
            switch sex {
            case .female:
                return "\(who), catch-up week with kindness: \(dayPart) stick to \(energyCap), \(proteinBit), and \(targets.steps) steps. No shame snacks, just the plan."
            case .male:
                return "\(who), hardcore catch-up week. \(dayPart.capitalized): \(energyCap), \(proteinBit), \(targets.steps) steps. No mercy snacks."
            }
        }
        if targetMode == .accelerate {
            switch sex {
            case .female:
                return "\(who), you're ahead and glowing. Keep the momentum \(dayPart): \(energyCap), \(proteinBit), keep \(targets.steps) steps. Don't coast into chaos."
            case .male:
                return "\(who), you're ahead: accelerate, don't coast. \(dayPart.capitalized) \(energyCap), \(proteinBit), keep \(targets.steps) steps."
            }
        }

        switch band {
        case .crushed:
            switch sex {
            case .female:
                return "\(who), you already won the week. Still finish beautifully: \(energyCap), \(proteinBit) \(dayPart). Celebrate without wrecking the plot."
            case .male:
                return "\(who), week already won. Still finish the line: \(energyCap), \(proteinBit) \(dayPart). Don't celebrate with chaos."
            }
        case .ahead:
            switch sex {
            case .female:
                return "\(who), ahead of pace. Keep it pretty: \(proteinBit), \(energyCap), \(targets.steps) steps \(dayPart)."
            case .male:
                return "\(who), ahead of pace. Tighten: \(proteinBit), \(energyCap), \(targets.steps) steps \(dayPart)."
            }
        case .onTrack:
            let dietBit: String = {
                switch diet {
                case .vegan: return "Plant protein every plate."
                case .vegetarian: return "Eggs or legumes, no grazing."
                case .pescatarian: return "Fish or legumes at dinner."
                case .omnivore, .other: return "Palm-size protein each meal."
                }
            }()
            switch sex {
            case .female:
                return "\(who), on track for \(weeklyGoal.title). \(dayPart.capitalized) keep \(energyCap) with \(proteinBit). \(dietBit) You're doing this."
            case .male:
                return "\(who), on track for \(weeklyGoal.title). \(dayPart.capitalized) \(energyCap), \(proteinBit). \(dietBit)"
            }
        case .atRisk:
            switch sex {
            case .female:
                return "\(who), pace is slipping a little. Kitchen fix \(dayPart): \(energyCap) and \(proteinBit). Open Meal plan. Still proud you're here."
            case .male:
                return "\(who), pace is slipping. Fix is the kitchen \(dayPart): \(energyCap), \(proteinBit). Open Meal plan."
            }
        case .unknown:
            switch sex {
            case .female:
                return "\(who), step on the scale once, then keep \(energyCap) \(dayPart). Baseline first, then we paint the week."
            case .male:
                return "\(who), step on the scale once, then stay \(energyCap) \(dayPart). Baseline first, vibes second."
            }
        }
    }
}
