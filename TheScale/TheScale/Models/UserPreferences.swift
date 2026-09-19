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
        title: "Nudge -0.3 kg this week"
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
            return "Weigh in once to lock this week's baseline."
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

/// How often Grok should review the latest Health digest (when consent + live config exist).
enum GrokCheckInterval: String, Codable, CaseIterable, Identifiable, Sendable {
    case manualOnly
    case every6Hours
    case every12Hours
    case daily
    case morningAndEvening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manualOnly: return "Manual only (Coach tab)"
        case .every6Hours: return "Every 6 hours"
        case .every12Hours: return "Every 12 hours"
        case .daily: return "Once daily"
        case .morningAndEvening: return "Morning + evening"
        }
    }

    /// Nominal spacing between automated checks. `nil` = never auto.
    var nominalSeconds: TimeInterval? {
        switch self {
        case .manualOnly: return nil
        case .every6Hours: return 6 * 3600
        case .every12Hours: return 12 * 3600
        case .daily: return 24 * 3600
        case .morningAndEvening: return 12 * 3600
        }
    }
}

/// Tunable keep / threshold parameters for algorithm triggers.
struct FitnessMonitorThresholds: Equatable, Codable, Sendable {
    /// Minutes of HR samples to pull before sleep onset.
    var preSleepHRWindowMinutes: Int
    /// Flag if average pre-sleep HR is this many bpm above resting HR.
    var preSleepHRAboveRestingBpm: Double
    /// Absolute floor: average pre-sleep HR at or above this is notable (when resting unknown).
    var preSleepHRAbsoluteBpm: Double
    /// Steps in a day that count as "moved" for Watch-wear detection.
    var watchWearMinSteps: Double
    /// Minimum HR samples expected in that active day; below → likely not wearing Watch.
    var watchWearMinHRSamples: Int
    /// Hours between Watch-wear nudges (anti-spam).
    var watchWearNotifyCooldownHours: Double

    static let `default` = FitnessMonitorThresholds(
        preSleepHRWindowMinutes: 30,
        preSleepHRAboveRestingBpm: 15,
        preSleepHRAbsoluteBpm: 90,
        watchWearMinSteps: 2_000,
        watchWearMinHRSamples: 8,
        watchWearNotifyCooldownHours: 36
    )
}

struct FitnessMonitorPreferences: Equatable, Codable, Sendable {
    var enabled: Bool
    var interval: GrokCheckInterval
    var notifyOnTriggers: Bool
    var thresholds: FitnessMonitorThresholds
    var lastAutomatedCheckAt: Date?
    var lastWatchWearNotifyAt: Date?
    var lastPreSleepAlertAt: Date?

    static let `default` = FitnessMonitorPreferences(
        enabled: false,
        interval: .daily,
        notifyOnTriggers: true,
        thresholds: .default,
        lastAutomatedCheckAt: nil,
        lastWatchWearNotifyAt: nil,
        lastPreSleepAlertAt: nil
    )
}

enum FitnessMonitorPreferencesStore {
    private static let key = "thescale.fitnessMonitorPreferences"

    static func load() -> FitnessMonitorPreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let prefs = try? JSONDecoder().decode(FitnessMonitorPreferences.self, from: data)
        else {
            return .default
        }
        return prefs
    }

    static func save(_ prefs: FitnessMonitorPreferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Latest Apple Health workout snapshot for Coach (not limited to 24h).
struct HealthWorkoutSummary: Equatable, Sendable {
    var activityName: String
    var startDate: Date
    var endDate: Date
    var durationMinutes: Double
    var activeEnergyKcal: Double?
    var sourceName: String?

    func promptLine() -> String {
        let when = endDate.formatted(date: .abbreviated, time: .shortened)
        var line = String(
            format: "Last workout: %@ on %@, %.0f min",
            activityName,
            when,
            durationMinutes
        )
        if let kcal = activeEnergyKcal {
            line += String(format: ", %.0f kcal", kcal)
        }
        if let source = sourceName, !source.isEmpty {
            line += " (\(source))"
        }
        return line
    }
}

/// Whether Coach can treat Health reads as usable.
enum HealthDigestAccess: String, Equatable, Sendable {
    case unavailable
    case notRequested
    case readable
    case readFailed
}

/// Compact fitness snapshot for Grok + local trigger algorithms.
struct FitnessDigest: Equatable, Sendable {
    var stepsToday: Double?
    var activeEnergyKcalToday: Double?
    var restingHeartRateBpm: Double?
    var latestHeartRateBpm: Double?
    var heartRateSampleCountToday: Int
    var sleepHoursLastNight: Double?
    var sleepOnset: Date?
    var preSleepAverageHRBpm: Double?
    var preSleepHRSampleCount: Int
    var workoutCountLast24h: Int
    /// Most recent workout in lookback (default 90 days), independent of 24h count.
    var lastWorkout: HealthWorkoutSummary?
    var access: HealthDigestAccess
    var accessDetail: String
    var generatedAt: Date

    static let empty = FitnessDigest(
        stepsToday: nil,
        activeEnergyKcalToday: nil,
        restingHeartRateBpm: nil,
        latestHeartRateBpm: nil,
        heartRateSampleCountToday: 0,
        sleepHoursLastNight: nil,
        sleepOnset: nil,
        preSleepAverageHRBpm: nil,
        preSleepHRSampleCount: 0,
        workoutCountLast24h: 0,
        lastWorkout: nil,
        access: .notRequested,
        accessDetail: "Health digest not loaded yet.",
        generatedAt: Date()
    )

    static func unavailable(now: Date = Date()) -> FitnessDigest {
        var digest = FitnessDigest.empty
        digest.access = .unavailable
        digest.accessDetail = "Apple Health is not available on this device."
        digest.generatedAt = now
        return digest
    }

    static func readFailed(message: String, now: Date = Date()) -> FitnessDigest {
        var digest = FitnessDigest.empty
        digest.access = .readFailed
        digest.accessDetail = message
        digest.generatedAt = now
        return digest
    }

    var hasAnyFitnessSignal: Bool {
        (stepsToday ?? 0) > 0
            || (activeEnergyKcalToday ?? 0) > 0
            || restingHeartRateBpm != nil
            || latestHeartRateBpm != nil
            || heartRateSampleCountToday > 0
            || sleepHoursLastNight != nil
            || workoutCountLast24h > 0
            || lastWorkout != nil
    }

    /// Short line for Settings → Health status.
    var settingsStatusLine: String {
        switch access {
        case .unavailable:
            return "Health unavailable on this device."
        case .notRequested:
            return "Health access not requested yet. Tap Allow Health access."
        case .readFailed:
            return "Health read failed: \(accessDetail)"
        case .readable:
            if let workout = lastWorkout {
                return workout.promptLine()
            }
            if hasAnyFitnessSignal {
                return "Health readable. Recent activity signals present (no workout in last 90 days)."
            }
            return "Health readable, but no steps / HR / sleep / workouts found. Allow The Scale in Health → Data Access & Devices, or wear Apple Watch."
        }
    }

    func promptBlock(preSleepWindowMinutes: Int) -> String {
        var lines = [
            "Fitness digest (Apple Health, on-device read):",
            "Access: \(access.rawValue)",
            "Access detail: \(accessDetail)"
        ]
        lines.append(
            "Honesty rule for Coach: this digest is authoritative for workouts, steps, energy, HR, and sleep. If Access is not readable, samples are empty, or Last workout is none, say that clearly (Settings → Allow Health access / Health → Data Access for The Scale / wear Apple Watch). Never invent a workout, step count, HR, or sleep session."
        )

        switch access {
        case .unavailable, .notRequested, .readFailed:
            lines.append("Samples: unavailable. Do not invent activity.")
            return lines.joined(separator: "\n")
        case .readable:
            break
        }

        if let steps = stepsToday {
            lines.append(String(format: "Steps today: %.0f", steps))
        } else {
            lines.append("Steps today: missing")
        }
        if let kcal = activeEnergyKcalToday {
            lines.append(String(format: "Active energy today: %.0f kcal", kcal))
        } else {
            lines.append("Active energy today: missing")
        }
        if let rhr = restingHeartRateBpm {
            lines.append(String(format: "Resting HR: %.0f bpm", rhr))
        } else {
            lines.append("Resting HR: missing")
        }
        if let hr = latestHeartRateBpm {
            lines.append(String(format: "Latest HR: %.0f bpm", hr))
        } else {
            lines.append("Latest HR: missing")
        }
        lines.append("HR samples today: \(heartRateSampleCountToday)")
        if let sleep = sleepHoursLastNight {
            lines.append(String(format: "Sleep last night: %.1f h", sleep))
        } else {
            lines.append("Sleep last night: missing")
        }
        if let onset = sleepOnset {
            lines.append("Sleep onset: \(ISO8601DateFormatter().string(from: onset))")
        }
        if let pre = preSleepAverageHRBpm {
            lines.append(
                String(
                    format: "Avg HR in %d min before sleep: %.0f bpm (%d samples)",
                    preSleepWindowMinutes,
                    pre,
                    preSleepHRSampleCount
                )
            )
        } else if sleepOnset != nil {
            lines.append("Pre-sleep HR window: no samples (advise wearing Apple Watch to bed).")
        }
        lines.append("Workouts last 24h: \(workoutCountLast24h)")
        if let workout = lastWorkout {
            lines.append(workout.promptLine())
        } else {
            lines.append(
                "Last workout: none in last 90 days (or Health read denied for Workouts). Do not invent one."
            )
        }
        if !hasAnyFitnessSignal {
            lines.append(
                "Samples: empty across steps/HR/sleep/workouts. Tell the user to allow The Scale under Health → Data Access & Devices, wear Apple Watch, then ask again."
            )
        }
        return lines.joined(separator: "\n")
    }
}

enum FitnessTriggerKind: String, Equatable, Sendable {
    case preSleepHRElevated
    case preSleepHRMissing
    case watchLikelyNotWorn
}

struct FitnessTrigger: Equatable, Sendable {
    let kind: FitnessTriggerKind
    let message: String
    let severity: Int
}

/// Pure algorithms over Health digests (unit-testable).
enum FitnessTriggerMonitor {
    static func evaluate(
        digest: FitnessDigest,
        thresholds: FitnessMonitorThresholds,
        now: Date = Date()
    ) -> [FitnessTrigger] {
        var triggers: [FitnessTrigger] = []

        if digest.sleepOnset != nil {
            if digest.preSleepHRSampleCount == 0 || digest.preSleepAverageHRBpm == nil {
                triggers.append(
                    FitnessTrigger(
                        kind: .preSleepHRMissing,
                        message: "Sleep logged but no HR in the pre-sleep window. Wear the Apple Watch to bed next time if you want that check.",
                        severity: 2
                    )
                )
            } else if let avg = digest.preSleepAverageHRBpm {
                let elevatedVsResting: Bool = {
                    guard let rhr = digest.restingHeartRateBpm else { return false }
                    return avg >= rhr + thresholds.preSleepHRAboveRestingBpm
                }()
                let elevatedAbsolute = avg >= thresholds.preSleepHRAbsoluteBpm
                if elevatedVsResting || elevatedAbsolute {
                    triggers.append(
                        FitnessTrigger(
                            kind: .preSleepHRElevated,
                            message: String(
                                format: "Heart rate averaged %.0f bpm in the %d min before sleep. Worth a calm look (caffeine, stress, late training). Not a diagnosis.",
                                avg,
                                thresholds.preSleepHRWindowMinutes
                            ),
                            severity: 3
                        )
                    )
                }
            }
        }

        let moved = (digest.stepsToday ?? 0) >= thresholds.watchWearMinSteps
            || digest.workoutCountLast24h > 0
            || (digest.activeEnergyKcalToday ?? 0) >= 150
        if moved, digest.heartRateSampleCountToday < thresholds.watchWearMinHRSamples {
            triggers.append(
                FitnessTrigger(
                    kind: .watchLikelyNotWorn,
                    message: "You moved today but HR samples are sparse. Apple Watch probably wasn't on (or wrist detection was off).",
                    severity: 2
                )
            )
        }

        _ = now
        return triggers.sorted { $0.severity > $1.severity }
    }

    /// Whether an automated Grok check is due given interval prefs.
    static func isAutomatedCheckDue(
        prefs: FitnessMonitorPreferences,
        now: Date = Date()
    ) -> Bool {
        guard prefs.enabled else { return false }
        guard let spacing = prefs.interval.nominalSeconds else { return false }
        guard let last = prefs.lastAutomatedCheckAt else { return true }
        return now.timeIntervalSince(last) >= spacing * 0.92
    }
}
