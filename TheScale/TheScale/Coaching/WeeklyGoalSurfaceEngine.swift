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
    var targets: DailyGoalTargets
    /// Fraction of ISO week elapsed (0...1), for pace math.
    var weekElapsedFraction: Double
    var expectedPaceFraction: Double
}

/// Atmosphere for the home weekly-goal hero (light, readable on iPhone 15).
struct WeeklyGoalAtmosphere: Equatable {
    let top: Color
    let mid: Color
    let bottom: Color
    let ink: Color
    let muted: Color

    static func forBand(_ band: WeeklyTrackBand) -> WeeklyGoalAtmosphere {
        switch band {
        case .crushed:
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.72, green: 0.94, blue: 0.82),
                mid: Color(red: 0.38, green: 0.78, blue: 0.58),
                bottom: Color(red: 0.18, green: 0.52, blue: 0.38),
                ink: Color(red: 0.06, green: 0.28, blue: 0.18),
                muted: Color(red: 0.12, green: 0.36, blue: 0.26).opacity(0.78)
            )
        case .ahead:
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.78, green: 0.92, blue: 0.88),
                mid: Color(red: 0.48, green: 0.78, blue: 0.72),
                bottom: Color(red: 0.28, green: 0.58, blue: 0.54),
                ink: Color(red: 0.08, green: 0.30, blue: 0.28),
                muted: Color(red: 0.14, green: 0.38, blue: 0.36).opacity(0.78)
            )
        case .onTrack:
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.86, green: 0.93, blue: 0.98),
                mid: Color(red: 0.58, green: 0.76, blue: 0.90),
                bottom: Color(red: 0.34, green: 0.52, blue: 0.70),
                ink: Color(red: 0.10, green: 0.20, blue: 0.34),
                muted: Color(red: 0.16, green: 0.28, blue: 0.42).opacity(0.78)
            )
        case .atRisk:
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.98, green: 0.88, blue: 0.82),
                mid: Color(red: 0.94, green: 0.62, blue: 0.48),
                bottom: Color(red: 0.78, green: 0.34, blue: 0.28),
                ink: Color(red: 0.42, green: 0.12, blue: 0.10),
                muted: Color(red: 0.48, green: 0.18, blue: 0.14).opacity(0.80)
            )
        case .unknown:
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.92, green: 0.93, blue: 0.95),
                mid: Color(red: 0.78, green: 0.82, blue: 0.86),
                bottom: Color(red: 0.52, green: 0.56, blue: 0.62),
                ink: Color(red: 0.12, green: 0.14, blue: 0.18),
                muted: Color(red: 0.28, green: 0.32, blue: 0.38).opacity(0.80)
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
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyGoalSurface {
        let elapsed = weekElapsedFraction(now: now, calendar: calendar)
        let expected = max(0.08, elapsed) // early week: tiny expected progress
        let rawFraction = weeklyGoal.progressFraction(currentKg: currentKg)
        let fraction = rawFraction ?? 0
        let percent = Int((min(max(fraction, 0), 1.2) * 100).rounded())

        let band = trackBand(
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

        let detail: String = {
            if currentKg == nil || weeklyGoal.weekStartKg == nil {
                return "Weigh in once to lock this week's baseline."
            }
            return weeklyGoal.statusLine(currentKg: currentKg)
        }()

        let advice = tomorrowAdvice(
            name: profile.greetingName,
            band: band,
            weeklyGoal: weeklyGoal,
            targets: targets,
            digest: digest,
            diet: profile.dietPreference
        )

        return WeeklyGoalSurface(
            completionPercent: percent,
            band: band,
            weekTitle: weeklyGoal.title,
            detailLine: detail,
            tomorrowAdvice: advice,
            targets: targets,
            weekElapsedFraction: elapsed,
            expectedPaceFraction: expected
        )
    }

    // MARK: - Pace / band

    /// Fraction of the ISO week already elapsed (Mon start → next Mon = 1.0).
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

        // Recovery / activity can tip the color without inventing progress.
        if recovery == .red, band == .onTrack || band == .ahead {
            band = .atRisk
        }
        if recovery == .red, band == .crushed {
            band = .ahead // still winning the week, but body wants recovery
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

    /// Mifflin-St Jeor BMR (kcal/day). Coaching estimate only.
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

        // Lightly active default; bump if Health shows meaningful movement.
        var activity = 1.375
        if let steps = digest?.stepsToday, steps >= 10_000 {
            activity = 1.55
        } else if let kcal = digest?.activeEnergyKcalToday, kcal >= 450 {
            activity = 1.55
        } else if digest?.workoutCountLast24h ?? 0 >= 1 {
            activity = 1.45
        }
        let tdee = bmr * activity

        // Weekly kg target → daily energy budget. Negative delta = deficit.
        let dailyDeltaKcal = (weeklyDeltaKg * kcalPerKg) / 7.0
        var maxCal = tdee + dailyDeltaKcal
        // Floor: don't prescribe crash diets.
        let floor = bmr * 1.15
        maxCal = max(floor, maxCal)
        // Ceiling when gaining slowly.
        maxCal = min(tdee + 500, maxCal)

        var steps = 8_500
        if band == .atRisk { steps = 10_000 }
        if band == .ahead || band == .crushed { steps = 7_500 }
        if digest?.recovery?.band == .red {
            steps = min(steps, 7_000)
        }
        if let today = digest?.stepsToday, today > Double(steps) {
            // Nudge slightly above today's hit so the target stays aspirational.
            steps = Int((today * 1.05).rounded())
            steps = min(steps, 14_000)
        }

        // Protein: ~1.6–1.8 g/kg current (higher on cut).
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
        diet: DietPreference
    ) -> String {
        let who = name.isEmpty ? "Operator" : name
        let recovery = digest?.recovery?.band
        let sleep = digest?.sleepHoursLastNight
        let steps = digest?.stepsToday

        if recovery == .red {
            return "\(who), recovery's in the red. Tomorrow: easy steps (~\(targets.steps)), protein \(targets.proteinGrams) g, early lights-out. Ego lifts can wait."
        }
        if let sleep, sleep < 6.0 {
            return "\(who), \(String(format: "%.1f", sleep)) h sleep is thin. Tomorrow protect bedtime first, then hit \(targets.steps) steps under \(targets.maxCalories) kcal."
        }

        switch band {
        case .crushed:
            return "\(who), week already won. Tomorrow maintain: \(targets.steps) steps, protein \(targets.proteinGrams) g, stay under \(targets.maxCalories) kcal. Don't celebrate with chaos."
        case .ahead:
            return "\(who), you're ahead of pace. Tomorrow keep it boring: \(targets.proteinGrams) g protein, max \(targets.maxCalories) kcal, walk the \(targets.steps)."
        case .onTrack:
            let dietBit: String = {
                switch diet {
                case .vegan: return "Plant protein every plate."
                case .vegetarian: return "Eggs or legumes, no grazing."
                case .pescatarian: return "Fish or legumes at dinner."
                case .omnivore, .other: return "Palm-size protein each meal."
                }
            }()
            return "\(who), on track for \(weeklyGoal.title). Tomorrow: \(targets.steps) steps, under \(targets.maxCalories) kcal. \(dietBit)"
        case .atRisk:
            if let steps, steps < 4000 {
                return "\(who), steps were soft. Tomorrow crush \(targets.steps) and cap \(targets.maxCalories) kcal. \(targets.microName): \(targets.microTargetLine)."
            }
            return "\(who), pace is slipping. Tomorrow is the fix: \(targets.steps) steps, max \(targets.maxCalories) kcal, \(targets.proteinGrams) g protein. No heroics, just the number."
        case .unknown:
            return "\(who), step on the scale once, then tomorrow is \(targets.steps) steps and under \(targets.maxCalories) kcal. Baseline first, vibes second."
        }
    }
}
