import Foundation

/// Soft global cap so coaching channels don't stack into spam.
/// Morning weigh, user-asked Coach wake, and spike red cards are exempt.
enum NotificationDailyBudget {
    static let maxNonMorningPerDay = 2

    enum SpendKind: String, Sendable {
        case morningWeigh
        case coachWake
        case weightSpike
        case missLadder
        case badTrend
        case weeklyGoal
        case mondaySkip
        case sundayWrap
        case fitness
        case nag
        case other
    }

    private static let dayKey = "thescale.notifBudget.day"
    private static let countKey = "thescale.notifBudget.count"

    nonisolated static func isExempt(_ kind: SpendKind) -> Bool {
        switch kind {
        case .morningWeigh, .coachWake, .weightSpike:
            return true
        case .missLadder, .badTrend, .weeklyGoal, .mondaySkip, .sundayWrap, .fitness, .nag, .other:
            return false
        }
    }

    /// Remaining non-exempt slots for the local day (0…max).
    nonisolated static func remaining(
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Int {
        let stamp = dayStamp(now, calendar: calendar)
        if defaults.string(forKey: dayKey) != stamp {
            return maxNonMorningPerDay
        }
        let used = defaults.integer(forKey: countKey)
        return max(0, maxNonMorningPerDay - used)
    }

    /// True when this kind may schedule (exempt always; else if a slot remains).
    /// Does not mutate storage — call `record` after a successful schedule.
    nonisolated static func canSpend(
        _ kind: SpendKind,
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if isExempt(kind) { return true }
        return remaining(now: now, calendar: calendar, defaults: defaults) > 0
    }

    /// Record a successful non-exempt schedule/fire for the local day.
    nonisolated static func record(
        _ kind: SpendKind,
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        guard !isExempt(kind) else { return }
        let stamp = dayStamp(now, calendar: calendar)
        if defaults.string(forKey: dayKey) != stamp {
            defaults.set(stamp, forKey: dayKey)
            defaults.set(1, forKey: countKey)
            return
        }
        let next = defaults.integer(forKey: countKey) + 1
        defaults.set(next, forKey: countKey)
    }

    /// Test helper: wipe budget counters.
    nonisolated static func resetForTests(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: dayKey)
        defaults.removeObject(forKey: countKey)
    }

    nonisolated static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
