import Foundation

/// Sparse live-Grok polish for phones without Apple Intelligence (iPhone XR / iOS 18).
///
/// Order of preference for polish jobs:
/// 1. Foundation Models (free, on-device)
/// 2. Metal 0.5B sidecar when ready (free, on-device)
/// 3. This light Grok path — tiny prompts, hard weekly caps, always leave chat credits
/// 4. Algorithmic / template copy
///
/// Light assists burn the same weekly Keel credit as chat, but a separate soft cap
/// keeps Free from spending its whole teaser on background polish.
@MainActor
enum LightGrokAssist {
    private static let countKey = "thescale.lightGrokAssist.count"
    private static let weekKey = "thescale.lightGrokAssist.week"
    private static let lastDayKey = "thescale.lightGrokAssist.lastDay"

    /// True when on-device Apple Intelligence cannot cover polish.
    static var needsNetworkAssist: Bool {
        !FoundationModelAvailability.isAvailable
    }

    /// Soft weekly ceiling for light assists (in addition to plan credit pool).
    static func weeklyCap(for plan: ScalePlan) -> Int {
        plan.weeklyLightGrokAssists
    }

    /// Keep this many Keel credits untouched for user-initiated chat / Monday card.
    static func chatReserve(for plan: ScalePlan) -> Int {
        plan.lightAssistChatReserve
    }

    static func snapshot(plan: ScalePlan, now: Date = Date(), calendar: Calendar = .current) -> (used: Int, cap: Int) {
        let week = weekIdentity(now: now, calendar: calendar)
        return (loadUsed(for: week), weeklyCap(for: plan))
    }

    /// Gate only — does not consume.
    static func canSpend(
        plan: ScalePlan,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard needsNetworkAssist else { return false }
        guard GrokPrivacyConsent.isAccepted else { return false }
        guard GrokSharedConfig.configurationIssue == nil else { return false }

        let week = weekIdentity(now: now, calendar: calendar)
        let lightUsed = loadUsed(for: week)
        guard lightUsed < weeklyCap(for: plan) else { return false }

        let quota = CoachWeeklyQuota.snapshot(plan: plan, now: now, calendar: calendar)
        // After this burn, leave `chatReserve` credits for real Coach turns.
        guard quota.remaining > chatReserve(for: plan) else { return false }
        return true
    }

    /// At most one light network polish per local calendar day (notifications + home line share this).
    static func alreadySpentToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let day = dayIdentity(now: now, calendar: calendar)
        return UserDefaults.standard.string(forKey: lastDayKey) == day
    }

    /// Compact one-line rewrite. Returns nil when gated or network fails (caller keeps fallback).
    static func polishOneLiner(
        system: String,
        user: String,
        maxTokens: Int = 72,
        plan: ScalePlan = ScaleSubscriptionStore.shared.plan,
        now: Date = Date(),
        requireFreshDay: Bool = true
    ) async -> String? {
        guard canSpend(plan: plan, now: now) else { return nil }
        if requireFreshDay, alreadySpentToday(now: now) { return nil }

        guard let text = await GrokClient.shared.lightPolish(
            system: system,
            user: user,
            maxTokens: maxTokens
        ) else { return nil }

        let cleaned = CoachCopySanitize.clean(text)
        guard !cleaned.isEmpty else { return nil }
        noteSpend(plan: plan, now: now)
        return cleaned
    }

    /// Notification title/body when FM + Metal sidecar are both unavailable.
    static func refineNotificationCopy(
        profileName: String,
        kind: String,
        fallbackTitle: String,
        fallbackBody: String,
        context: String,
        voiceRules: String,
        plan: ScalePlan = ScaleSubscriptionStore.shared.plan,
        now: Date = Date()
    ) async -> (title: String, body: String, usedNetwork: Bool) {
        guard canSpend(plan: plan, now: now) else {
            return (fallbackTitle, fallbackBody, false)
        }
        // Banners fire often — never burn more than one light credit per local day.
        if alreadySpentToday(now: now) {
            return (fallbackTitle, fallbackBody, false)
        }

        let name = profileName.isEmpty ? "Hey" : profileName
        let system = """
            \(voiceRules)
            You rewrite one local iOS notification. Keep the same facts. No medical disclaimer.
            Reply with exactly two lines:
            TITLE: ...
            BODY: ...
            TITLE max 20 characters (Watch glance). BODY max 120 characters (iPhone).
            """
        let user = """
            Name: \(name)
            Kind: \(kind)
            Context: \(String(context.prefix(220)))
            Fallback title: \(fallbackTitle)
            Fallback body: \(fallbackBody)
            """

        guard let raw = await GrokClient.shared.lightPolish(
            system: system,
            user: user,
            maxTokens: 90
        ) else {
            return (fallbackTitle, fallbackBody, false)
        }

        var title = fallbackTitle
        var body = fallbackBody
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.uppercased().hasPrefix("TITLE:") {
                title = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.uppercased().hasPrefix("BODY:") {
                body = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }
        title = CoachCopySanitize.clean(title)
        body = CoachCopySanitize.clean(body)
        if title.isEmpty { title = fallbackTitle }
        if body.isEmpty { body = fallbackBody }
        title = ScaleNotificationCopy.glanceSanitize(title, max: 22)
        if body.count > 140 { body = String(body.prefix(140)) }

        noteSpend(plan: plan, now: now)
        return (title, body, true)
    }

    #if DEBUG
    static func debugReset() {
        UserDefaults.standard.removeObject(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: weekKey)
        UserDefaults.standard.removeObject(forKey: lastDayKey)
    }
    #endif

    private static func noteSpend(plan: ScalePlan, now: Date, calendar: Calendar = .current) {
        let week = weekIdentity(now: now, calendar: calendar)
        let used = loadUsed(for: week) + 1
        UserDefaults.standard.set(week, forKey: weekKey)
        UserDefaults.standard.set(used, forKey: countKey)
        UserDefaults.standard.set(dayIdentity(now: now, calendar: calendar), forKey: lastDayKey)
        ScaleSubscriptionStore.shared.noteQuotaChange()
        _ = plan
    }

    private static func weekIdentity(now: Date, calendar: Calendar) -> String {
        let y = calendar.component(.yearForWeekOfYear, from: now)
        let w = calendar.component(.weekOfYear, from: now)
        return String(format: "%04d-W%02d", y, w)
    }

    private static func dayIdentity(now: Date, calendar: Calendar) -> String {
        let y = calendar.component(.year, from: now)
        let d = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
        return String(format: "%04d-D%03d", y, d)
    }

    private static func loadUsed(for week: String) -> Int {
        let storedWeek = UserDefaults.standard.string(forKey: weekKey)
        if storedWeek != week { return 0 }
        return max(UserDefaults.standard.integer(forKey: countKey), 0)
    }
}
