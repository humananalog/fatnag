import Foundation

/// Algorithmic difficulty band for a dream-weight plan.
/// Flavor names differ by sex; safe biology caps still gate acceptance.
struct GoalDifficultyBand: Equatable, Sendable {
    /// 0 = chill … 4 = max flavor tier.
    let level: Int
    let title: String
    /// Short onboarding reveal line.
    let revealLine: String
    /// Compact coach-context tag.
    let coachTag: String
    /// Ratio of |required|/safeCap (nil when hold / unknown).
    let intensityRatio: Double?
}

enum GoalDifficultyFlavor {
    /// Men: Diablo-style difficulty ladder.
    static let maleTitles = [
        "Normal",
        "Nightmare",
        "Hell",
        "Inferno",
        "Torment"
    ]

    /// Women: girly-pop reference ladder.
    static let femaleTitles = [
        "Soft Launch",
        "Main Character",
        "Y2K Era",
        "Brat Mode",
        "Icon Status"
    ]

    /// Rate difficulty from required weekly pace vs safe cap.
    /// Call only after `GoalPaceGuard` accepts (or for reveal of a tempered plan).
    static func rate(
        sex: UserBodyProfile.Sex,
        currentKg: Double,
        targetKg: Double,
        goalDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> GoalDifficultyBand {
        let delta = targetKg - currentKg
        if abs(delta) < 0.15 {
            return band(sex: sex, level: 0, ratio: 0)
        }

        let towardLower = delta < 0
        let safeCap = towardLower
            ? TargetFeasibility.maxSafeLossKgPerWeek(currentKg: currentKg)
            : TargetFeasibility.maxSafeGainKgPerWeek(currentKg: currentKg)

        let required: Double = {
            guard let goalDate else {
                // No date: treat as mid aggressiveness toward safe max.
                return safeCap * 0.55
            }
            let days = max(
                calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: now),
                    to: calendar.startOfDay(for: goalDate)
                ).day ?? 0,
                1
            )
            let weeks = max(Double(days) / 7.0, 1.0 / 7.0)
            return abs(delta) / weeks
        }()

        let ratio = safeCap > 0.001 ? required / safeCap : 0
        let level: Int
        switch ratio {
        case ..<0.35: level = 0
        case ..<0.55: level = 1
        case ..<0.75: level = 2
        case ..<0.92: level = 3
        default: level = 4
        }
        return band(sex: sex, level: level, ratio: ratio)
    }

    static func band(sex: UserBodyProfile.Sex, level: Int, ratio: Double?) -> GoalDifficultyBand {
        let clamped = min(max(level, 0), 4)
        let titles = sex == .female ? femaleTitles : maleTitles
        let title = titles[clamped]
        let reveal: String
        let tag: String
        switch sex {
        case .male:
            reveal = maleReveal(level: clamped, title: title)
            tag = "Goal difficulty: \(title) (Diablo ladder)"
        case .female:
            reveal = femaleReveal(level: clamped, title: title)
            tag = "Goal difficulty: \(title) (pop ladder)"
        }
        return GoalDifficultyBand(
            level: clamped,
            title: title,
            revealLine: reveal,
            coachTag: tag,
            intensityRatio: ratio
        )
    }

    private static func maleReveal(level: Int, title: String) -> String {
        let key: String
        let fallback: String
        switch level {
        case 0:
            key = "onboarding.difficulty.male.0"
            fallback = "Difficulty: %@. Warm-up map. Keel will still notice if you coast."
        case 1:
            key = "onboarding.difficulty.male.1"
            fallback = "Difficulty: %@. Real dungeon. Consistency is the loot."
        case 2:
            key = "onboarding.difficulty.male.2"
            fallback = "Difficulty: %@. Act bosses every week. Miss a day and it bites."
        case 3:
            key = "onboarding.difficulty.male.3"
            fallback = "Difficulty: %@. You asked for fire. Biology still holds the ceiling."
        default:
            key = "onboarding.difficulty.male.4"
            fallback = "Difficulty: %@. Endgame pacing. Safe cap still wins over ego."
        }
        return String(format: AppLanguageStore.text(key, default: fallback), title)
    }

    private static func femaleReveal(level: Int, title: String) -> String {
        let key: String
        let fallback: String
        switch level {
        case 0:
            key = "onboarding.difficulty.female.0"
            fallback = "Difficulty: %@. Soft entry. Still show up for the plot."
        case 1:
            key = "onboarding.difficulty.female.1"
            fallback = "Difficulty: %@. Camera on. Habits are the outfit."
        case 2:
            key = "onboarding.difficulty.female.2"
            fallback = "Difficulty: %@. Glossy and demanding. Keel keeps the timeline honest."
        case 3:
            key = "onboarding.difficulty.female.3"
            fallback = "Difficulty: %@. Chaotic good energy. Biology is the bodyguard."
        default:
            key = "onboarding.difficulty.female.4"
            fallback = "Difficulty: %@. Full send fantasy. Safe weekly caps still rule."
        }
        return String(format: AppLanguageStore.text(key, default: fallback), title)
    }
}
