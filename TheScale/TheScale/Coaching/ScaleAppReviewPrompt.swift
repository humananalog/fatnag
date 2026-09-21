import Foundation

/// Soft, non-invasive App Store review prompts after real success moments.
/// Soft sheet first (stars); only 4–5 open StoreKit. Cooldowns respect Apple rate limits.
@MainActor
enum ScaleAppReviewPrompt {
    private static let weighInCountKey = "thescale.review.successfulWeighIns"
    private static let lastPromptAtKey = "thescale.review.lastPromptAt"
    private static let lastDismissAtKey = "thescale.review.lastSoftDismissAt"
    private static let optedOutKey = "thescale.review.optedOutLowScore"

    /// Minimum confirmed Health saves before we ever ask.
    static let minimumWeighIns = 3
    /// Days between soft prompts (Apple also caps StoreKit).
    static let promptCooldownDays: Double = 90
    /// After "Later", wait this long before asking again.
    static let softDismissCooldownDays: Double = 45

    static var successfulWeighIns: Int {
        get { UserDefaults.standard.integer(forKey: weighInCountKey) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: weighInCountKey) }
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

    #if DEBUG
    static func debugReset() {
        UserDefaults.standard.removeObject(forKey: weighInCountKey)
        UserDefaults.standard.removeObject(forKey: lastPromptAtKey)
        UserDefaults.standard.removeObject(forKey: lastDismissAtKey)
        UserDefaults.standard.removeObject(forKey: optedOutKey)
    }
    #endif
}
