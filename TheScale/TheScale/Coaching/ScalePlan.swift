import Foundation

/// Consumer plans. Industry-standard Free / Plus / Pro naming (ChatGPT, Notion, Apple+ adjacent).
enum ScalePlan: String, Codable, CaseIterable, Identifiable, Sendable {
    case free
    case plus
    case pro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free: return AppLanguageStore.text("plan.free", default: "Free")
        case .plus: return AppLanguageStore.text("plan.plus", default: "Plus")
        case .pro: return AppLanguageStore.text("plan.pro", default: "Pro")
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
        case .free: return AppLanguageStore.text("plan.free", default: "Free")
        case .plus: return AppLanguageStore.text("plan.plus.price", default: "$2 / month")
        case .pro: return AppLanguageStore.text("plan.pro.price", default: "$8 / month")
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
            return String(
                format: AppLanguageStore.text("plan.free.blurb", default: "Scale, Health, charts. %d live Keel asks a week."),
                weeklyGrokCredits
            )
        case .plus:
            return String(
                format: AppLanguageStore.text("plan.plus.blurb", default: "Daily heat. %d live Keel credits a week."),
                weeklyGrokCredits
            )
        case .pro:
            return String(
                format: AppLanguageStore.text("plan.pro.blurb", default: "No soft ceiling. %d live Keel credits a week."),
                weeklyGrokCredits
            )
        }
    }

    /// One-line Keel voice under each tier on Unlock Coach.
    var paywallArgument: String {
        switch self {
        case .free:
            return AppLanguageStore.text("plan.free.arg", default: "Taste the tone.")
        case .plus:
            return AppLanguageStore.text("plan.plus.arg", default: "A sharp ask a day.")
        case .pro:
            return AppLanguageStore.text("plan.pro.arg", default: "Never ration pressure.")
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
