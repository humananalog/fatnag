import Foundation

/// Diet preference for coaching tone and offline tips (on-device only).
enum DietPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case omnivore
    case pescatarian
    case vegetarian
    case vegan
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .omnivore: return "Omnivore"
        case .pescatarian: return "Pescatarian"
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .other: return "Other / flexible"
        }
    }
}

/// Notification + coaching prefs (UserDefaults). Never leaves the phone except optional Grok calls.
struct NotificationPreferences: Equatable, Codable, Sendable {
    /// Only ping when weight trend is bad vs ideal / last week (gain while above ideal, or stall).
    var notifyOnBadTrend: Bool
    /// Soft weekly mini-goal reminders (Monday morning).
    var weeklyGoalReminders: Bool

    static let `default` = NotificationPreferences(
        notifyOnBadTrend: true,
        weeklyGoalReminders: true
    )
}

enum NotificationPreferencesStore {
    private static let key = "thescale.notificationPreferences"

    static func load() -> NotificationPreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let prefs = try? JSONDecoder().decode(NotificationPreferences.self, from: data)
        else {
            return .default
        }
        return prefs
    }

    static func save(_ prefs: NotificationPreferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Weekly mini-goal progress (local, no cloud).
struct WeeklyMiniGoal: Equatable, Codable, Sendable {
    /// Target kg change this week (negative = lose). Example: -0.3
    var targetDeltaKg: Double
    /// Weight at the start of the ISO week (kg).
    var weekStartKg: Double?
    var weekStartDate: Date?
    /// Optional short label shown in Progress.
    var title: String

    static let `default` = WeeklyMiniGoal(
        targetDeltaKg: -0.3,
        weekStartKg: nil,
        weekStartDate: nil,
        title: "Nudge −0.3 kg this week"
    )

    func progressFraction(currentKg: Double?) -> Double? {
        guard let currentKg, let weekStartKg, abs(targetDeltaKg) > 0.01 else { return nil }
        let moved = currentKg - weekStartKg
        // Progress toward a negative target: moved should go negative.
        let fraction = moved / targetDeltaKg
        return min(max(fraction, 0), 1.2)
    }

    func statusLine(currentKg: Double?) -> String {
        guard let currentKg, let weekStartKg else {
            return "Weigh in once to lock this week’s baseline."
        }
        let moved = currentKg - weekStartKg
        let remaining = targetDeltaKg - moved
        if targetDeltaKg < 0 {
            if moved <= targetDeltaKg {
                return String(format: "Crushed it: %.2f kg vs goal %.2f kg.", moved, targetDeltaKg)
            }
            return String(format: "Moved %.2f kg · %.2f kg still to go.", moved, remaining)
        }
        if moved >= targetDeltaKg {
            return String(format: "Hit %+.2f kg target (%.2f kg).", targetDeltaKg, moved)
        }
        return String(format: "Moved %.2f kg · %.2f kg still to go.", moved, remaining)
    }
}

enum WeeklyMiniGoalStore {
    private static let key = "thescale.weeklyMiniGoal"

    static func load() -> WeeklyMiniGoal {
        guard let data = UserDefaults.standard.data(forKey: key),
              let goal = try? JSONDecoder().decode(WeeklyMiniGoal.self, from: data)
        else {
            return .default
        }
        return goal
    }

    static func save(_ goal: WeeklyMiniGoal) {
        if let data = try? JSONEncoder().encode(goal) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum OnboardingStore {
    private static let key = "thescale.hasCompletedOnboarding"

    static var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
