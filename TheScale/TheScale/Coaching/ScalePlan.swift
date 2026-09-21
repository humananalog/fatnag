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

    /// Live Grok credits per ISO week (chat + Monday card + fitness Grok check = 1 each).
    /// Sized for Grok 4.20 Non-Reasoning COGS (~$0.004–0.011 / call) and 50% margin after Apple.
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
            return "Full weigh-in, Health, charts, and on-device Coach. \(weeklyGrokCredits) live Grok asks per week."
        case .plus:
            return "Active daily Coach. \(weeklyGrokCredits) live Grok credits per week (chat, Monday card, fitness checks)."
        case .pro:
            return "Heavy Coach use. \(weeklyGrokCredits) live Grok credits per week with room for power days."
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
