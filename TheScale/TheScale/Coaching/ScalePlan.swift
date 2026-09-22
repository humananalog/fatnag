import Foundation

/// Consumer plans. Industry-standard Free / Plus / Pro naming (ChatGPT, Notion, Apple+ adjacent).
enum ScalePlan: String, Codable, CaseIterable, Identifiable, Sendable {
    case free
    case plus
    case pro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .plus: return "Plus"
        case .pro: return "Pro"
        }
    }

    /// Marketing list price (USD / month). Annual can come later.
    var monthlyPriceUSD: Decimal {
        switch self {
        case .free: return 0
        case .plus: return 2
        case .pro: return 8
        }
    }

    var priceLabel: String {
        switch self {
        case .free: return "Free"
        case .plus: return "$2 / month"
        case .pro: return "$8 / month"
        }
    }

    /// Live Keel credits per ISO week (chat + Monday card + fitness check = 1 each).
    /// Sized for shared live-model COGS and 50% margin after Apple.
    var weeklyGrokCredits: Int {
        switch self {
        case .free: return 5 // teaser; full scale/Health/FM still unlimited
        case .plus: return 28 // active ≈ 4 / day
        case .pro: return 120 // power ≈ 17 / day
        }
    }

    var blurb: String {
        switch self {
        case .free:
            return "Scoreboard only. Full weigh-in, Health, charts, on-device Coach. \(weeklyGrokCredits) live Keel asks a week so you can taste the heat. When you stall, you wait until Monday or you upgrade."
        case .plus:
            return "Daily accountability. \(weeklyGrokCredits) live Keel credits a week (chat, Monday card, fitness checks). Enough to get called out when you skip the scale or invent excuses. Adults who want a habit, not a toy."
        case .pro:
            return "No soft ceiling. \(weeklyGrokCredits) live Keel credits a week with room for ugly weeks, double checks, and power days. You pay for volume because consistency is expensive when you actually use the coach."
        }
    }

    /// Hard paywall argument (Keel voice). Shown under each tier.
    var paywallArgument: String {
        switch self {
        case .free:
            return "You get the hardware loop for free: scale, Health, charts. \(weeklyGrokCredits) live Keel asks a week. Enough to learn the tone. Not enough to hide behind when you go soft."
        case .plus:
            return "\(weeklyGrokCredits) live credits a week. Roughly a sharp ask a day. Monday card, fitness checks, chat when you start lying to yourself. This is the adult default if you mean it."
        case .pro:
            return "\(weeklyGrokCredits) live credits a week. Use Coach hard on bad weeks without rationing. Pro is for people who already know consistency is the failure mode and refuse to run out of pressure mid-spiral."
        }
    }

    var storeProductID: String? {
        switch self {
        case .free: return nil
        case .plus: return "app.thescale.ios.plus.monthly"
        case .pro: return "app.thescale.ios.pro.monthly"
        }
    }

    /// Next unlock target when this plan is exhausted.
    var upgradeTarget: ScalePlan? {
        switch self {
        case .free: return .plus
        case .plus: return .pro
        case .pro: return nil
        }
    }

    static func best(of plans: [ScalePlan]) -> ScalePlan {
        if plans.contains(.pro) { return .pro }
        if plans.contains(.plus) { return .plus }
        return .free
    }
}

enum CoachQuotaKind: String, Sendable {
    case chat
    case mondayCard
    case fitnessCheck
    case mealPlan

    var title: String {
        switch self {
        case .chat: return "Coach chat"
        case .mondayCard: return "Monday card"
        case .fitnessCheck: return "Fitness check"
        case .mealPlan: return "Meal plan"
        }
    }
}
