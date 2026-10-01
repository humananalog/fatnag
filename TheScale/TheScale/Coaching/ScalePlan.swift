import Foundation

/// Paywall cadence. Annual is the default (cheaper for the user, cash up front for us).
enum ScaleBillingPeriod: String, CaseIterable, Identifiable, Sendable {
    case annual
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .annual: return AppLanguageStore.text("plan.period.annual", default: "Annual")
        case .monthly: return AppLanguageStore.text("plan.period.monthly", default: "Monthly")
        }
    }

    /// Short suffix for price rows ("/ year", "/ month").
    var priceSuffix: String {
        switch self {
        case .annual: return AppLanguageStore.text("plan.period.per_year", default: "/ year")
        case .monthly: return AppLanguageStore.text("plan.period.per_month", default: "/ month")
        }
    }
}

/// Consumer plans. Industry-standard Free / Plus / Pro naming (ChatGPT, Notion, Apple+ adjacent).
enum ScalePlan: String, Codable, CaseIterable, Identifiable, Sendable {
    case free
    case plus
    case pro

    var id: String { rawValue }

    /// Free < Plus < Pro. Used to tell a new subscription from a step up or a goodbye.
    var rank: Int {
        switch self {
        case .free: return 0
        case .plus: return 1
        case .pro: return 2
        }
    }

    var displayName: String {
        switch self {
        case .free: return AppLanguageStore.text("plan.free", default: "Free")
        case .plus: return AppLanguageStore.text("plan.plus", default: "Plus")
        case .pro: return AppLanguageStore.text("plan.pro", default: "Pro")
        }
    }

    /// Marketing list price (USD / month). App Store X.99 tiers.
    var monthlyPriceUSD: Decimal {
        switch self {
        case .free: return 0
        case .plus: return Decimal(string: "1.99")!
        case .pro: return Decimal(string: "7.99")!
        }
    }

    /// Marketing list price (USD / year). ~2 months free vs 12× monthly → cash up front.
    var annualPriceUSD: Decimal {
        switch self {
        case .free: return 0
        case .plus: return Decimal(string: "19.99")! // vs $23.88 if paid monthly
        case .pro: return Decimal(string: "79.99")! // vs $95.88 if paid monthly
        }
    }

    var priceLabel: String {
        priceLabel(period: .monthly)
    }

    func priceLabel(period: ScaleBillingPeriod) -> String {
        switch self {
        case .free:
            return AppLanguageStore.text("plan.free", default: "Free")
        case .plus:
            switch period {
            case .monthly:
                return AppLanguageStore.text("plan.plus.price", default: "$1.99 / month")
            case .annual:
                return AppLanguageStore.text("plan.plus.price.annual", default: "$19.99 / year")
            }
        case .pro:
            switch period {
            case .monthly:
                return AppLanguageStore.text("plan.pro.price", default: "$7.99 / month")
            case .annual:
                return AppLanguageStore.text("plan.pro.price.annual", default: "$79.99 / year")
            }
        }
    }

    /// Shown under annual tiers — honest vs paying monthly all year.
    var annualSavingsLabel: String? {
        switch self {
        case .free: return nil
        case .plus, .pro:
            return AppLanguageStore.text("plan.annual.save", default: "2 months free")
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

    /// Monthly product ID (legacy alias). Prefer `storeProductID(period:)`.
    var storeProductID: String? {
        storeProductID(period: .monthly)
    }

    func storeProductID(period: ScaleBillingPeriod) -> String? {
        switch (self, period) {
        case (.free, _): return nil
        case (.plus, .monthly): return "app.thescale.ios.plus.monthly"
        case (.plus, .annual): return "app.thescale.ios.plus.annual"
        case (.pro, .monthly): return "app.thescale.ios.pro.monthly"
        case (.pro, .annual): return "app.thescale.ios.pro.annual"
        }
    }

    /// Map any paid product ID back to Free/Plus/Pro entitlement.
    static func plan(forProductID id: String) -> ScalePlan? {
        switch id {
        case "app.thescale.ios.plus.monthly", "app.thescale.ios.plus.annual":
            return .plus
        case "app.thescale.ios.pro.monthly", "app.thescale.ios.pro.annual":
            return .pro
        default:
            return nil
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

/// A plan change worth a card. Higher rank is a welcome. Lower rank is a goodbye.
enum SubscriptionMoment: Equatable, Identifiable, Sendable {
    case thanks(from: ScalePlan, to: ScalePlan)
    case farewell(from: ScalePlan, to: ScalePlan)

    var id: String {
        switch self {
        case .thanks(let from, let to): return "thanks-\(from.rawValue)-\(to.rawValue)"
        case .farewell(let from, let to): return "farewell-\(from.rawValue)-\(to.rawValue)"
        }
    }

    var isThanks: Bool {
        if case .thanks = self { return true }
        return false
    }

    var arrived: ScalePlan {
        switch self {
        case .thanks(_, let to), .farewell(_, let to): return to
        }
    }

    var departed: ScalePlan {
        switch self {
        case .thanks(let from, _), .farewell(let from, _): return from
        }
    }

    static func resolve(from previous: ScalePlan, to next: ScalePlan) -> SubscriptionMoment? {
        if next.rank > previous.rank { return .thanks(from: previous, to: next) }
        if next.rank < previous.rank { return .farewell(from: previous, to: next) }
        return nil
    }

    var eyebrow: String {
        switch self {
        case .thanks:
            return AppLanguageStore.text("subscription.thanks.eyebrow", default: "You're in")
        case .farewell:
            return AppLanguageStore.text("subscription.farewell.eyebrow", default: "A quiet close")
        }
    }

    var title: String {
        switch self {
        case .thanks:
            return AppLanguageStore.text("subscription.thanks.title", default: "Thank you.")
        case .farewell:
            return AppLanguageStore.text("subscription.farewell.title", default: "Sorry to see you go.")
        }
    }

    var message: String {
        switch self {
        case .thanks(let from, let to) where from == .free:
            return String(
                format: AppLanguageStore.text(
                    "subscription.thanks.welcome",
                    default: "Welcome to %@. Keel has more room for you this week — %d credits. We're glad you're here."
                ),
                to.displayName,
                to.weeklyGrokCredits
            )
        case .thanks(_, let to):
            return String(
                format: AppLanguageStore.text(
                    "subscription.thanks.upgrade",
                    default: "%@ is yours now. More Keel this week (%d), same coach."
                ),
                to.displayName,
                to.weeklyGrokCredits
            )
        case .farewell(let from, let to) where to == .free:
            return String(
                format: AppLanguageStore.text(
                    "subscription.farewell.free",
                    default: "%@ has ended. You're on Free, and your weigh-ins stay on this iPhone."
                ),
                from.displayName
            )
        case .farewell(let from, let to):
            return String(
                format: AppLanguageStore.text(
                    "subscription.farewell.step",
                    default: "%@ has ended. You're on %@. Everything you logged stays here."
                ),
                from.displayName,
                to.displayName
            )
        }
    }

    var feedbackLine: String {
        switch self {
        case .thanks:
            return AppLanguageStore.text(
                "subscription.thanks.feedback",
                default: "The feedback form is in Settings. A bug, an idea, or a note about what you love — we read it."
            )
        case .farewell:
            return AppLanguageStore.text(
                "subscription.farewell.feedback",
                default: "If you want to tell us why, the feedback form is in Settings. No pressure."
            )
        }
    }
}

enum CoachQuotaKind: String, Sendable {
    case chat
    case mondayCard
    case monthlyCard
    case fitnessCheck
    case mealPlan

    var title: String {
        switch self {
        case .chat: return "Coach chat"
        case .mondayCard: return "Monday card"
        case .monthlyCard: return "Monthly card"
        case .fitnessCheck: return "Fitness check"
        case .mealPlan: return "Meal plan"
        }
    }
}
