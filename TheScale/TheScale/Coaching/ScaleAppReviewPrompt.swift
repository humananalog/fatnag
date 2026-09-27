import Foundation

/// Soft, non-invasive App Store review prompts after real success moments.
/// Soft sheet first (stars); only 4–5 open StoreKit `requestReview`.
/// System review is requested **at most once per install** after 6 successful weigh-ins.
@MainActor
enum ScaleAppReviewPrompt {
    private static let weighInCountKey = "thescale.review.successfulWeighIns"
    private static let lastPromptAtKey = "thescale.review.lastPromptAt"
    private static let lastDismissAtKey = "thescale.review.lastSoftDismissAt"
    private static let optedOutKey = "thescale.review.optedOutLowScore"
    private static let hasRequestedKey = "thescale.review.hasRequestedAppStoreReview"

    /// Confirmed Health weigh-in saves before we ever ask (happy-path signal).
    static let minimumWeighIns = 6
    /// Days between soft prompts if the user dismissed without rating (Apple also caps StoreKit).
    static let promptCooldownDays: Double = 90
    /// After "Later", wait this long before asking again.
    static let softDismissCooldownDays: Double = 45

    static var successfulWeighIns: Int {
        get { UserDefaults.standard.integer(forKey: weighInCountKey) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: weighInCountKey) }
    }

    /// True after we have invoked StoreKit `requestReview` once on this install.
    static var hasRequestedAppStoreReview: Bool {
        get { UserDefaults.standard.bool(forKey: hasRequestedKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasRequestedKey) }
    }

    static var hasOptedOutAfterLowScore: Bool {
        get { UserDefaults.standard.bool(forKey: optedOutKey) }
        set { UserDefaults.standard.set(newValue, forKey: optedOutKey) }
    }

    static func recordSuccessfulWeighIn() {
        successfulWeighIns += 1
    }

    /// Whether ContentView should present the soft star sheet.
    static func shouldOfferSoftPrompt(now: Date = Date()) -> Bool {
        guard !hasRequestedAppStoreReview else { return false }
        guard !hasOptedOutAfterLowScore else { return false }
        guard successfulWeighIns >= minimumWeighIns else { return false }
        if let last = UserDefaults.standard.object(forKey: lastPromptAtKey) as? Date {
            if now.timeIntervalSince(last) < promptCooldownDays * 86_400 { return false }
        }
        if let dismissed = UserDefaults.standard.object(forKey: lastDismissAtKey) as? Date {
            if now.timeIntervalSince(dismissed) < softDismissCooldownDays * 86_400 { return false }
        }
        return true
    }

    static func markSoftPromptShown(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: lastPromptAtKey)
    }

    static func markSoftDismissed(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: lastDismissAtKey)
    }

    static func markLowScoreOptOut() {
        hasOptedOutAfterLowScore = true
        markSoftDismissed()
    }

    /// Call immediately before / after `requestReview()` so we never spam.
    static func markAppStoreReviewRequested() {
        hasRequestedAppStoreReview = true
        markSoftPromptShown()
    }

    #if DEBUG
    static func debugReset() {
        UserDefaults.standard.removeObject(forKey: weighInCountKey)
        UserDefaults.standard.removeObject(forKey: lastPromptAtKey)
        UserDefaults.standard.removeObject(forKey: lastDismissAtKey)
        UserDefaults.standard.removeObject(forKey: optedOutKey)
        UserDefaults.standard.removeObject(forKey: hasRequestedKey)
    }
    #endif
}
