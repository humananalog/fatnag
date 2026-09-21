import Foundation

/// ISO-week Grok credit ledger. Resets each Monday (locale calendar).
@MainActor
enum CoachWeeklyQuota {
    private static let countKey = "thescale.coachWeeklyQuota.count"
    private static let weekKey = "thescale.coachWeeklyQuota.week"

    struct Snapshot: Equatable, Sendable {
        let plan: ScalePlan
        let used: Int
        let limit: Int
        let weekLabel: String

        var remaining: Int { max(limit - used, 0) }
        var isExhausted: Bool { remaining <= 0 }

        var statusLine: String {
            "\(plan.displayName) · \(remaining)/\(limit) Grok this week"
        }
    }

    static func snapshot(plan: ScalePlan, now: Date = Date(), calendar: Calendar = .current) -> Snapshot {
        let week = weekIdentity(now: now, calendar: calendar)
        let used = loadUsed(for: week)
        return Snapshot(
            plan: plan,
            used: used,
            limit: plan.weeklyGrokCredits,
            weekLabel: week
        )
    }

    /// Returns nil if allowed (and increments). Returns a user-facing lock message if blocked.
    static func consume(
        _ kind: CoachQuotaKind,
        plan: ScalePlan,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        let week = weekIdentity(now: now, calendar: calendar)
        var used = loadUsed(for: week)
        let limit = plan.weeklyGrokCredits
        if used >= limit {
            return lockMessage(kind: kind, plan: plan, used: used, limit: limit)
        }
        used += 1
        save(used: used, week: week)
        return nil
    }

    /// Peek without consuming.
    static func canConsume(plan: ScalePlan, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        !snapshot(plan: plan, now: now, calendar: calendar).isExhausted
    }

    static func lockMessage(kind: CoachQuotaKind, plan: ScalePlan, used: Int, limit: Int) -> String {
        let name = plan.displayName
        if let next = plan.upgradeTarget {
            return "\(kind.title) blocked: weekly Grok limit hit on \(name) (\(used)/\(limit)). Unlock \(next.displayName) (\(next.priceLabel)) for \(next.weeklyGrokCredits)/week, or wait until next Monday."
        }
        return "\(kind.title) blocked: weekly Grok limit hit on \(name) (\(used)/\(limit)). Resets Monday."
    }

    #if DEBUG
    static func debugReset() {
        UserDefaults.standard.removeObject(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: weekKey)
    }

    static func debugSetUsed(_ used: Int, now: Date = Date(), calendar: Calendar = .current) {
        save(used: max(used, 0), week: weekIdentity(now: now, calendar: calendar))
    }
    #endif

    private static func weekIdentity(now: Date, calendar: Calendar) -> String {
        let y = calendar.component(.yearForWeekOfYear, from: now)
        let w = calendar.component(.weekOfYear, from: now)
        return String(format: "%04d-W%02d", y, w)
    }

    private static func loadUsed(for week: String) -> Int {
        let storedWeek = UserDefaults.standard.string(forKey: weekKey)
        if storedWeek != week {
            return 0
        }
        return max(UserDefaults.standard.integer(forKey: countKey), 0)
    }

    private static func save(used: Int, week: String) {
        UserDefaults.standard.set(week, forKey: weekKey)
        UserDefaults.standard.set(used, forKey: countKey)
    }
}
