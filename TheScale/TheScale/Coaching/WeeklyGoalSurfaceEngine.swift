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
    /// Honest: food logging is not in-app yet.
    var intakeTracked: Bool

    var honestyLine: String {
        intakeTracked
            ? "Logged vs target"
            : "Goals only · food not logged yet"
    }
}

/// One-screen weekly goal snapshot for Home.
struct WeeklyGoalSurface: Equatable, Sendable {
    var completionPercent: Int
    var band: WeeklyTrackBand
    var weekTitle: String
    var detailLine: String
    var tomorrowAdvice: String
    var mealSuggestion: String?
    var energySnapshot: WeeklyEnergyBalanceSnapshot?
    var targets: DailyGoalTargets
    /// Fraction of ISO week elapsed (0...1), for pace math.
    var weekElapsedFraction: Double
    var expectedPaceFraction: Double
}

/// Atmosphere for the home weekly-goal hero.
/// Soft pastel field + near-black ink so type stays readable on every band.
struct WeeklyGoalAtmosphere: Equatable {
    let top: Color
    let mid: Color
    let bottom: Color
    let hazeA: Color
    let hazeB: Color
    let ink: Color
    let muted: Color
    let panel: Color

    /// Shared near-black for maximum contrast on pastel / haze fields.
    private static let deepInk = Color(red: 0.04, green: 0.05, blue: 0.07)
    private static let deepMuted = Color(red: 0.12, green: 0.13, blue: 0.16)

    static func forBand(_ band: WeeklyTrackBand) -> WeeklyGoalAtmosphere {
        switch band {
        case .crushed:
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.88, green: 0.96, blue: 0.90),
                mid: Color(red: 0.68, green: 0.88, blue: 0.74),
                bottom: Color(red: 0.48, green: 0.76, blue: 0.58),
                hazeA: Color(red: 0.35, green: 0.72, blue: 0.50).opacity(0.38),
                hazeB: Color(red: 0.62, green: 0.90, blue: 0.74).opacity(0.42),
                ink: deepInk,
                muted: deepMuted,
                panel: Color.clear
            )
        case .ahead:
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.88, green: 0.95, blue: 0.94),
                mid: Color(red: 0.64, green: 0.84, blue: 0.82),
                bottom: Color(red: 0.44, green: 0.70, blue: 0.68),
                hazeA: Color(red: 0.32, green: 0.66, blue: 0.64).opacity(0.36),
                hazeB: Color(red: 0.60, green: 0.86, blue: 0.84).opacity(0.40),
                ink: deepInk,
                muted: deepMuted,
                panel: Color.clear
            )
        case .onTrack:
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.90, green: 0.94, blue: 0.98),
                mid: Color(red: 0.70, green: 0.82, blue: 0.92),
                bottom: Color(red: 0.50, green: 0.66, blue: 0.82),
                hazeA: Color(red: 0.34, green: 0.54, blue: 0.76).opacity(0.34),
                hazeB: Color(red: 0.66, green: 0.80, blue: 0.92).opacity(0.40),
                ink: deepInk,
                muted: deepMuted,
                panel: Color.clear
            )
        case .atRisk:
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.99, green: 0.92, blue: 0.88),
                mid: Color(red: 0.94, green: 0.72, blue: 0.62),
                bottom: Color(red: 0.86, green: 0.50, blue: 0.42),
                hazeA: Color(red: 0.82, green: 0.36, blue: 0.28).opacity(0.32),
                hazeB: Color(red: 0.94, green: 0.66, blue: 0.54).opacity(0.38),
                ink: deepInk,
                muted: deepMuted,
                panel: Color.clear
            )
        case .unknown:
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.94, green: 0.95, blue: 0.96),
                mid: Color(red: 0.82, green: 0.84, blue: 0.88),
                bottom: Color(red: 0.66, green: 0.70, blue: 0.76),
                hazeA: Color(red: 0.42, green: 0.48, blue: 0.56).opacity(0.30),
                hazeB: Color(red: 0.74, green: 0.78, blue: 0.84).opacity(0.36),
                ink: deepInk,
                muted: deepMuted,
                panel: Color.clear
            )
        }
    }
}

/// Pure weekly-goal home math: progress %, track band, daily targets, tomorrow advice.
enum WeeklyGoalSurfaceEngine {
    /// ~7700 kcal ≈ 1 kg adipose (coaching ballpark, not a medical claim).
    static let kcalPerKg: Double = 7700

    static func build(
        weeklyGoal: WeeklyMiniGoal,
        currentKg: Double?,
        profile: UserBodyProfile,
        digest: FitnessDigest?,
        recentWeights: [HealthWeightSample] = [],
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
            stepsToday: digest?.stepsToday
        )

        let targets = dailyTargets(
            profile: profile,
            currentKg: currentKg,
            weeklyDeltaKg: weeklyGoal.targetDeltaKg,
            digest: digest,
            band: band
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
            return weeklyGoal.statusLine(currentKg: currentKg)
        }()

        let meals = WeeklyEnergyBalanceEvaluator.mealSuggestion(
            diet: profile.dietPreference,
            maxKcal: targets.maxCalories,
            proteinGrams: targets.proteinGrams
        )

        let advice = tomorrowAdvice(
            name: profile.greetingName,
            band: band,
            weeklyGoal: weeklyGoal,
            targets: targets,
            digest: digest,
            diet: profile.dietPreference,
            energy: energy,
            mealLine: meals
        )

        let showMeals: String? = {
            switch energy.diagnosis {
            case .overeatingWhileActive, .underMoving:
                return meals
            default:
                return nil
            }
        }()

        return WeeklyGoalSurface(
            completionPercent: percent,
            band: band,
            weekTitle: weeklyGoal.title,
            detailLine: detail,
            tomorrowAdvice: advice,
            mealSuggestion: showMeals,
            energySnapshot: energy,
            targets: targets,
            weekElapsedFraction: elapsed,
            expectedPaceFraction: expected
        )
    }

    // MARK: - Pace / band

    static func weekElapsedFraction(now: Date, calendar: Calendar = .current) -> Double {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0.5 }
        let total = interval.end.timeIntervalSince(interval.start)
        guard total > 0 else { return 0.5 }
        return min(1, max(0, now.timeIntervalSince(interval.start) / total))
    }

    static func trackBand(
        progressFraction: Double?,
        expectedPace: Double,
        recovery: RecoveryLoadHeuristic.Band?,
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

        if recovery == .red, band == .onTrack || band == .ahead {
            band = .atRisk
        }
        if recovery == .red, band == .crushed {
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
        band: WeeklyTrackBand
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
        maxCal = min(tdee + 500, maxCal)

        var steps = 8_500
        if band == .atRisk { steps = 10_000 }
        if band == .ahead || band == .crushed { steps = 7_500 }
        if digest?.recovery?.band == .red {
            steps = min(steps, 7_000)
        }
        // Don't inflate steps above what they already hit when intake is the issue.
        if let today = digest?.stepsToday, today > Double(steps), today < 12_000 {
            steps = Int(today.rounded())
        }

        let proteinPerKg = weeklyDeltaKg < -0.15 ? 1.8 : 1.6
        let protein = Int((weight * proteinPerKg).rounded())
        let micro = microPriority(profile: profile, weeklyDeltaKg: weeklyDeltaKg, diet: profile.dietPreference)

        return DailyGoalTargets(
            steps: steps,
            maxCalories: Int(maxCal.rounded()),
            proteinGrams: max(70, protein),
            proteinLabel: "Protein",
            microName: micro.name,
            microTargetLine: micro.line,
            intakeTracked: false
        )
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

    // MARK: - Tomorrow advice

    static func tomorrowAdvice(
        name: String,
        band: WeeklyTrackBand,
        weeklyGoal: WeeklyMiniGoal,
        targets: DailyGoalTargets,
        digest: FitnessDigest?,
        diet: DietPreference,
        energy: WeeklyEnergyBalanceSnapshot,
        mealLine: String
    ) -> String {
        let who = name.isEmpty ? "Operator" : name
        let recovery = digest?.recovery?.band
        let sleep = digest?.sleepHoursLastNight

        // Energy diagnosis wins over generic step pep talks.
        switch energy.diagnosis {
        case .overeatingWhileActive(let intake, let spend, let maxK, _, let obs, let days):
            return "\(who), you're moving (~\(spend) kcal out) but the scale barely budged (\(String(format: "%+.2f", obs)) kg / \(String(format: "%.0f", days))d). That's intake (~\(intake) implied), not steps. Get your act together: under \(maxK) kcal tomorrow. Open Meal plan."
        case .underMoving(_, let exp, let obs, _):
            return "\(who), movement was soft and weight went \(String(format: "%+.2f", obs)) kg (wanted \(String(format: "%+.2f", exp))). Tomorrow: under \(targets.maxCalories) kcal, then walk. Open Meal plan."
        case .aheadOfEnergy, .onPace, .insufficientData:
            break
        }

        if recovery == .red {
            return "\(who), recovery's in the red. Tomorrow: easy day, protein \(targets.proteinGrams) g, early lights-out, stay under \(targets.maxCalories) kcal. Ego lifts can wait."
        }
        if let sleep, sleep < 6.0 {
            return "\(who), \(String(format: "%.1f", sleep)) h sleep is thin. Tomorrow protect bedtime first, then stay under \(targets.maxCalories) kcal with \(targets.proteinGrams) g protein."
        }

        switch band {
        case .crushed:
            return "\(who), week already won. Tomorrow maintain under \(targets.maxCalories) kcal, \(targets.proteinGrams) g protein. Don't celebrate with chaos."
        case .ahead:
            return "\(who), you're ahead of pace. Tomorrow keep it boring: \(targets.proteinGrams) g protein, max \(targets.maxCalories) kcal."
        case .onTrack:
            let dietBit: String = {
                switch diet {
                case .vegan: return "Plant protein every plate."
                case .vegetarian: return "Eggs or legumes, no grazing."
                case .pescatarian: return "Fish or legumes at dinner."
                case .omnivore, .other: return "Palm-size protein each meal."
                }
            }()
            return "\(who), on track for \(weeklyGoal.title). Tomorrow under \(targets.maxCalories) kcal, \(targets.proteinGrams) g protein. \(dietBit)"
        case .atRisk:
            return "\(who), pace is slipping. Fix is the kitchen: max \(targets.maxCalories) kcal, \(targets.proteinGrams) g protein. Open Meal plan."
        case .unknown:
            return "\(who), step on the scale once, then tomorrow under \(targets.maxCalories) kcal. Baseline first, vibes second."
        }
    }
}
