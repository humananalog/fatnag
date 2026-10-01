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

/// Soft profile gaps we may ask about later (never spam).
enum ProfileGapKind: String, Codable, CaseIterable, Sendable {
    case location
    case foodAvoidances
    case diet

    var title: String {
        switch self {
        case .location: return "Where do you shop and train?"
        case .foodAvoidances: return "Anything to avoid?"
        case .diet: return "Confirm your diet"
        }
    }

    var subtitle: String {
        switch self {
        case .location:
            return "City helps meal prep (markets, staples) and nearby fitness options. Optional."
        case .foodAvoidances:
            return "Allergies and hard nos (peanuts, shellfish, no dairy). Leave blank if none."
        case .diet:
            return "Keel uses this for meal plans. Change anytime in Settings."
        }
    }
}

/// Notification + coaching prefs (UserDefaults). Never leaves the phone except optional Grok calls.
struct NotificationPreferences: Equatable, Codable, Sendable {
    /// Only ping when weight trend is bad vs ideal / last week (gain while above ideal, or stall).
    var notifyOnBadTrend: Bool
    /// Soft weekly mini-goal reminders (Monday morning).
    var weeklyGoalReminders: Bool
    /// After leaving sleep / bedtime, one sergeant ping to weigh (once per morning).
    var morningWeighDrill: Bool
    /// Calendar fallback hour (local) when sleep-wake HealthKit is missing or flaky.
    var morningWeighFallbackHour: Int
    /// Calendar fallback minute (local).
    var morningWeighFallbackMinute: Int

    /// Previous default fallback (replaced by 06:30 in 2.50.0).
    static let legacyMorningFallbackHour = 7
    static let legacyMorningFallbackMinute = 30
    /// Current default local fallback clock.
    static let defaultMorningFallbackHour = 6
    static let defaultMorningFallbackMinute = 30

    static let `default` = NotificationPreferences(
        notifyOnBadTrend: true,
        weeklyGoalReminders: true,
        morningWeighDrill: true,
        morningWeighFallbackHour: defaultMorningFallbackHour,
        morningWeighFallbackMinute: defaultMorningFallbackMinute
    )

    init(
        notifyOnBadTrend: Bool,
        weeklyGoalReminders: Bool,
        morningWeighDrill: Bool,
        morningWeighFallbackHour: Int = defaultMorningFallbackHour,
        morningWeighFallbackMinute: Int = defaultMorningFallbackMinute
    ) {
        self.notifyOnBadTrend = notifyOnBadTrend
        self.weeklyGoalReminders = weeklyGoalReminders
        self.morningWeighDrill = morningWeighDrill
        let clamped = ProfileNumericBounds.clampMorningFallback(
            hour: morningWeighFallbackHour,
            minute: morningWeighFallbackMinute
        )
        self.morningWeighFallbackHour = clamped.hour
        self.morningWeighFallbackMinute = clamped.minute
    }

    private enum CodingKeys: String, CodingKey {
        case notifyOnBadTrend
        case weeklyGoalReminders
        case morningWeighDrill
        case morningWeighFallbackHour
        case morningWeighFallbackMinute
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notifyOnBadTrend = try c.decodeIfPresent(Bool.self, forKey: .notifyOnBadTrend) ?? true
        weeklyGoalReminders = try c.decodeIfPresent(Bool.self, forKey: .weeklyGoalReminders) ?? true
        morningWeighDrill = try c.decodeIfPresent(Bool.self, forKey: .morningWeighDrill) ?? true
        let hour = try c.decodeIfPresent(Int.self, forKey: .morningWeighFallbackHour)
            ?? Self.defaultMorningFallbackHour
        let minute = try c.decodeIfPresent(Int.self, forKey: .morningWeighFallbackMinute)
            ?? Self.defaultMorningFallbackMinute
        let migrated = Self.migrateLegacyFallback(hour: hour, minute: minute)
        let clamped = ProfileNumericBounds.clampMorningFallback(
            hour: migrated.hour,
            minute: migrated.minute
        )
        morningWeighFallbackHour = clamped.hour
        morningWeighFallbackMinute = clamped.minute
    }

    /// Replace the old 07:30 default with 06:30; leave intentional custom clocks alone.
    static func migrateLegacyFallback(hour: Int, minute: Int) -> (hour: Int, minute: Int) {
        if hour == legacyMorningFallbackHour, minute == legacyMorningFallbackMinute {
            return (defaultMorningFallbackHour, defaultMorningFallbackMinute)
        }
        return (hour, minute)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(notifyOnBadTrend, forKey: .notifyOnBadTrend)
        try c.encode(weeklyGoalReminders, forKey: .weeklyGoalReminders)
        try c.encode(morningWeighDrill, forKey: .morningWeighDrill)
        try c.encode(morningWeighFallbackHour, forKey: .morningWeighFallbackHour)
        try c.encode(morningWeighFallbackMinute, forKey: .morningWeighFallbackMinute)
    }
}

enum NotificationPreferencesStore {
    private static let key = "thescale.notificationPreferences"

    static func load() -> NotificationPreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let prefs = try? JSONDecoder().decode(NotificationPreferences.self, from: data)
        else {
            return .default
        }
        // Persist 07:30 → 06:30 migration so consider() does not keep rewriting pending.
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hour = raw["morningWeighFallbackHour"] as? Int,
           let minute = raw["morningWeighFallbackMinute"] as? Int,
           hour == NotificationPreferences.legacyMorningFallbackHour,
           minute == NotificationPreferences.legacyMorningFallbackMinute
        {
            save(prefs)
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
    /// Weight at the start of the Mon→Sun week (kg). Always the last Monday body mass
    /// (prefer Monday morning Health sample); `weekStartDate` is that Monday 00:00 local.
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

    func statusLine(currentKg: Double?, system: PreferredUnitSystem = .metric) -> String {
        guard let currentKg, let weekStartKg else {
            return "Weigh in once to lock this week's baseline."
        }
        let moved = currentKg - weekStartKg
        let remaining = targetDeltaKg - moved
        if targetDeltaKg < 0 {
            if moved <= targetDeltaKg {
                return String(
                    format: "Crushed it: %@ vs goal %@.",
                    UnitFormat.massDeltaString(moved, system: system),
                    UnitFormat.massDeltaString(targetDeltaKg, system: system)
                )
            }
            return String(
                format: "Moved %@ · %@ still to go.",
                UnitFormat.massDeltaString(moved, system: system),
                UnitFormat.massDeltaString(remaining, system: system)
            )
        }
        if moved >= targetDeltaKg {
            return String(
                format: "Hit %@ target (%@).",
                UnitFormat.massDeltaString(targetDeltaKg, system: system),
                UnitFormat.massDeltaString(moved, system: system)
            )
        }
        return String(
            format: "Moved %@ · %@ still to go.",
            UnitFormat.massDeltaString(moved, system: system),
            UnitFormat.massDeltaString(remaining, system: system)
        )
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

    /// New installs and incomplete profiles always enter the onboarding sequence.
    static func shouldPresent(profile: UserBodyProfile) -> Bool {
        if !hasCompleted { return true }
        // Interrupted first-run leaves age below adult floor.
        if profile.ageYears + 0.01 < UserBodyProfile.minimumAgeYears { return true }
        return false
    }
}

/// How often Grok should review the latest Health digest (when consent + live config exist).
enum GrokCheckInterval: String, Codable, CaseIterable, Identifiable, Sendable {
    case manualOnly
    case every10Minutes
    case every6Hours
    case every12Hours
    case daily
    case morningAndEvening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manualOnly: return "Manual only (Coach tab)"
        case .every10Minutes: return "Every 10 minutes"
        case .every6Hours: return "Every 6 hours"
        case .every12Hours: return "Every 12 hours"
        case .daily: return "Once daily"
        case .morningAndEvening: return "Morning + evening"
        }
    }

    /// Nominal spacing between on-device activity reads. `nil` = never auto.
    var nominalSeconds: TimeInterval? {
        switch self {
        case .manualOnly: return nil
        case .every10Minutes: return 10 * 60
        case .every6Hours: return 6 * 3600
        case .every12Hours: return 12 * 3600
        case .daily: return 24 * 3600
        case .morningAndEvening: return 12 * 3600
        }
    }

    /// Grok stays on a multi-hour cadence. Ten minutes is the local Health analyzer, not a model call.
    var grokNominalSeconds: TimeInterval? {
        switch self {
        case .manualOnly: return nil
        case .every10Minutes: return 6 * 3600
        default: return nominalSeconds
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
        enabled: true,
        interval: .every10Minutes,
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

/// Apple Health workout snapshot for Coach (not limited to 24h).
struct HealthWorkoutSummary: Equatable, Sendable {
    var activityName: String
    var startDate: Date
    var endDate: Date
    var durationMinutes: Double
    var distanceKm: Double?
    var activeEnergyKcal: Double?
    var sourceName: String?

    /// One-line digest entry. `label` is usually "Last workout" or "Recent workout".
    func promptLine(label: String = "Last workout") -> String {
        let when = endDate.formatted(date: .abbreviated, time: .shortened)
        var line = String(
            format: "%@: %@ on %@, %.0f min",
            label,
            activityName,
            when,
            durationMinutes
        )
        if let km = distanceKm, km > 0 {
            line += String(format: ", %.1f km", km)
        }
        if let kcal = activeEnergyKcal {
            line += String(format: ", %.0f kcal", kcal)
        }
        if let source = sourceName, !source.isEmpty {
            line += " (\(source))"
        }
        return line
    }
}

/// Walking/running distance totals from HealthKit (not a workout object).
/// Used when third-party apps write distance without a Workout, or as a fallback signal.
struct HealthDistanceSpike: Equatable, Sendable {
    /// Sum of `distanceWalkingRunning` over the window (km).
    var distanceKmLast24h: Double
    /// Sum over the last 7 days (km).
    var distanceKmLast7d: Double
    /// True when 24h distance is large enough to imply a real outing without a Workout sample.
    var isNotableSpike: Bool

    static let notableSpikeKmThreshold: Double = 3.0

    static func from(km24h: Double?, km7d: Double?) -> HealthDistanceSpike? {
        let d24 = km24h ?? 0
        let d7 = km7d ?? 0
        guard d24 > 0 || d7 > 0 else { return nil }
        return HealthDistanceSpike(
            distanceKmLast24h: d24,
            distanceKmLast7d: d7,
            isNotableSpike: d24 >= notableSpikeKmThreshold
        )
    }

    func promptLines(workoutsEmpty: Bool) -> [String] {
        var lines = [
            String(format: "Walking/running distance last 24h: %.1f km", distanceKmLast24h),
            String(format: "Walking/running distance last 7d: %.1f km", distanceKmLast7d)
        ]
        if workoutsEmpty, isNotableSpike {
            lines.append(
                "Distance spike without a Workout sample: Health shows meaningful walking/running distance but no Workout titled hike/walk. Coach can say that plainly. Third-party apps (e.g. AllTrails, Strava) only appear here if they write to Apple Health. FATNAG reads HealthKit only, never AllTrails directly. Ask the user to enable Health sync in that app, then Allow Health access / Workouts + Distance for FATNAG."
            )
        }
        return lines
    }
}

/// Whether Coach can treat Health reads as usable.
enum HealthDigestAccess: String, Equatable, Sendable {
    case unavailable
    case notRequested
    case readable
    case readFailed
}

/// Compact today totals for home Horizon Arc Bank. Avoids the heavy Coach digest path.
struct HomeDailyMetrics: Equatable, Sendable {
    var stepsToday: Double
    var activeEnergyKcalToday: Double
    var dietaryEnergyKcalToday: Double
    var dietaryProteinGramsToday: Double
    var dietaryFiberGramsToday: Double
    var dietaryIronMgToday: Double
    var dietaryPotassiumMgToday: Double
    var generatedAt: Date

    static let zero = HomeDailyMetrics(
        stepsToday: 0,
        activeEnergyKcalToday: 0,
        dietaryEnergyKcalToday: 0,
        dietaryProteinGramsToday: 0,
        dietaryFiberGramsToday: 0,
        dietaryIronMgToday: 0,
        dietaryPotassiumMgToday: 0,
        generatedAt: Date()
    )
}

/// Compact fitness snapshot for Grok + local trigger algorithms.
struct FitnessDigest: Equatable, Sendable {
    var stepsToday: Double?
    var activeEnergyKcalToday: Double?
    /// Mean active energy (kcal/day) over the last ~7 days when Health has samples.
    var activeEnergyKcalLast7dAverage: Double?
    var appleExerciseMinutesToday: Double?
    /// Dietary energy logged in Apple Health today (kcal), when Nutrition writes exist.
    var dietaryEnergyKcalToday: Double?
    /// Dietary protein logged in Apple Health today (g).
    var dietaryProteinGramsToday: Double?
    /// Dietary fiber (g) logged today.
    var dietaryFiberGramsToday: Double?
    /// Dietary iron (mg) logged today.
    var dietaryIronMgToday: Double?
    /// Dietary potassium (mg) logged today.
    var dietaryPotassiumMgToday: Double?
    var restingHeartRateBpm: Double?
    var latestHeartRateBpm: Double?
    var heartRateSampleCountToday: Int
    /// Latest overnight / recent HRV (SDNN) in milliseconds.
    var hrvSDNNMs: Double?
    /// Median HRV SDNN over ~7 days (ms), for relative recovery checks.
    var hrvMedian7dMs: Double?
    var respiratoryRateBreathsPerMin: Double?
    /// Apple Watch sleeping wrist temperature delta (°C vs personal baseline) when present.
    var wristTemperatureDeltaC: Double?
    var oxygenSaturationPercent: Double?
    var vo2MaxMlKgMin: Double?
    var sleepHoursLastNight: Double?
    var sleepOnset: Date?
    var sleepWake: Date?
    var sleepStages: SleepStageHours?
    var bedtimeConsistencyStdDevHours: Double?
    var averageSleepHours7d: Double?
    var sleepNightsSampled: Int
    var preSleepAverageHRBpm: Double?
    var preSleepHRSampleCount: Int
    var workoutCountLast24h: Int
    /// Most recent workouts in lookback (default 90 days), newest first. Independent of 24h count.
    var recentWorkouts: [HealthWorkoutSummary]
    /// Walking/running distance totals (HealthKit quantity), even when no Workout exists.
    var walkingRunningDistance: HealthDistanceSpike?
    /// Transparent recovery / load band (nil until computed).
    var recovery: RecoveryLoadHeuristic?
    var access: HealthDigestAccess
    var accessDetail: String
    var generatedAt: Date

    /// Convenience: newest workout, if any.
    var lastWorkout: HealthWorkoutSummary? { recentWorkouts.first }

    static let empty = FitnessDigest(
        stepsToday: nil,
        activeEnergyKcalToday: nil,
        activeEnergyKcalLast7dAverage: nil,
        appleExerciseMinutesToday: nil,
        dietaryEnergyKcalToday: nil,
        dietaryProteinGramsToday: nil,
        dietaryFiberGramsToday: nil,
        dietaryIronMgToday: nil,
        dietaryPotassiumMgToday: nil,
        restingHeartRateBpm: nil,
        latestHeartRateBpm: nil,
        heartRateSampleCountToday: 0,
        hrvSDNNMs: nil,
        hrvMedian7dMs: nil,
        respiratoryRateBreathsPerMin: nil,
        wristTemperatureDeltaC: nil,
        oxygenSaturationPercent: nil,
        vo2MaxMlKgMin: nil,
        sleepHoursLastNight: nil,
        sleepOnset: nil,
        sleepWake: nil,
        sleepStages: nil,
        bedtimeConsistencyStdDevHours: nil,
        averageSleepHours7d: nil,
        sleepNightsSampled: 0,
        preSleepAverageHRBpm: nil,
        preSleepHRSampleCount: 0,
        workoutCountLast24h: 0,
        recentWorkouts: [],
        walkingRunningDistance: nil,
        recovery: nil,
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
            || (appleExerciseMinutesToday ?? 0) > 0
            || restingHeartRateBpm != nil
            || latestHeartRateBpm != nil
            || heartRateSampleCountToday > 0
            || hrvSDNNMs != nil
            || respiratoryRateBreathsPerMin != nil
            || wristTemperatureDeltaC != nil
            || oxygenSaturationPercent != nil
            || vo2MaxMlKgMin != nil
            || sleepHoursLastNight != nil
            || workoutCountLast24h > 0
            || !recentWorkouts.isEmpty
            || (walkingRunningDistance?.distanceKmLast24h ?? 0) > 0
            || (walkingRunningDistance?.distanceKmLast7d ?? 0) > 0
    }

    /// Overlay lean home-gauge totals without wiping Coach-only fields (HRV, sleep, …).
    /// Never clobber a fresher full-digest total with a suspiciously lower lean read.
    mutating func applyHomeDailyMetrics(_ metrics: HomeDailyMetrics) {
        let digestAge = Date().timeIntervalSince(generatedAt)
        if let existing = stepsToday, existing > 0,
           metrics.stepsToday < existing * 0.15,
           digestAge < 15 * 60 {
            // Keep digest steps.
        } else {
            stepsToday = metrics.stepsToday
        }
        if let existing = activeEnergyKcalToday, existing > 0,
           metrics.activeEnergyKcalToday < existing * 0.15,
           digestAge < 15 * 60 {
            // Keep digest move energy.
        } else {
            activeEnergyKcalToday = metrics.activeEnergyKcalToday
        }
        // Keep dietary nil when zero so Move-burn fallback still works when no food log.
        dietaryEnergyKcalToday = metrics.dietaryEnergyKcalToday > 0 ? metrics.dietaryEnergyKcalToday : nil
        dietaryProteinGramsToday = metrics.dietaryProteinGramsToday > 0 ? metrics.dietaryProteinGramsToday : nil
        dietaryFiberGramsToday = metrics.dietaryFiberGramsToday > 0 ? metrics.dietaryFiberGramsToday : nil
        dietaryIronMgToday = metrics.dietaryIronMgToday > 0 ? metrics.dietaryIronMgToday : nil
        dietaryPotassiumMgToday = metrics.dietaryPotassiumMgToday > 0 ? metrics.dietaryPotassiumMgToday : nil
        generatedAt = metrics.generatedAt
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
            if let sleep = sleepHoursLastNight, let recovery, recovery.band != .unknown {
                return String(
                    format: "Sleep %.1f h last night · recovery %@ · tap Coach for full digest.",
                    sleep,
                    recovery.band.rawValue
                )
            }
            if let workout = lastWorkout {
                return workout.promptLine()
            }
            if let dist = walkingRunningDistance, dist.isNotableSpike {
                return String(
                    format: "No Workout in Health, but %.1f km walking/running in last 24h. Third-party apps (AllTrails etc.) must write to Apple Health; FATNAG reads Health only.",
                    dist.distanceKmLast24h
                )
            }
            if hasAnyFitnessSignal {
                return "Health readable (steps/HR/HRV/sleep/distance present), but no Workouts in last 90 days. Enable Workouts + Distance + Sleep for FATNAG in Health, and turn on Health sync in third-party apps (AllTrails etc.)."
            }
            return "Health readable, but no steps / HR / sleep / workouts / distance found. Allow Health types for FATNAG, wear Apple Watch, or sync third-party apps into Health."
        }
    }

    func promptBlock(preSleepWindowMinutes: Int) -> String {
        let iso = ISO8601DateFormatter()
        let local = generatedAt.formatted(date: .abbreviated, time: .shortened)
        var lines = [
            "Fitness digest snapshot (Apple Health / HealthKit only, on-device read):",
            "Generated at: \(iso.string(from: generatedAt)) (local \(local))",
            "Access: \(access.rawValue)",
            "Access detail: \(accessDetail)"
        ]
        lines.append(
            "Honesty rule for Coach: this digest is the only activity / recovery source. Never invent missing metrics (sleep stages, HRV, SpO2, VO2, wrist temp, workouts). FATNAG cannot read AllTrails, Strava, or other apps directly; only what those apps write into Apple Health. When Recent workouts lists real sessions (type, distance km, duration, kcal, source), discuss those. If workouts are empty but walking/running distance shows a spike, say Health has distance without a Workout sample. Only claim total emptiness when listed signals are all missing."
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
        if let avg7 = activeEnergyKcalLast7dAverage {
            lines.append(String(format: "Active energy ~7d avg: %.0f kcal/day", avg7))
        } else {
            lines.append("Active energy ~7d avg: missing")
        }
        if let exercise = appleExerciseMinutesToday {
            lines.append(String(format: "Apple Exercise Time today: %.0f min", exercise))
        } else {
            lines.append("Apple Exercise Time today: missing")
        }
        if let dietKcal = dietaryEnergyKcalToday {
            lines.append(String(format: "Dietary energy today: %.0f kcal", dietKcal))
        } else {
            lines.append("Dietary energy today: missing (food not logged in Health)")
        }
        if let protein = dietaryProteinGramsToday {
            lines.append(String(format: "Dietary protein today: %.0f g", protein))
        } else {
            lines.append("Dietary protein today: missing")
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
        if let hrv = hrvSDNNMs {
            lines.append(String(format: "HRV SDNN (recent): %.0f ms", hrv))
        } else {
            lines.append("HRV SDNN: missing")
        }
        if let median = hrvMedian7dMs {
            lines.append(String(format: "HRV SDNN ~7d median: %.0f ms", median))
        }
        if let rr = respiratoryRateBreathsPerMin {
            lines.append(String(format: "Respiratory rate: %.1f breaths/min", rr))
        } else {
            lines.append("Respiratory rate: missing")
        }
        if let temp = wristTemperatureDeltaC {
            lines.append(String(format: "Sleeping wrist temperature delta: %+.2f C", temp))
        } else {
            lines.append("Sleeping wrist temperature: missing")
        }
        if let spo2 = oxygenSaturationPercent {
            lines.append(String(format: "SpO2: %.1f%%", spo2))
        } else {
            lines.append("SpO2: missing")
        }
        if let vo2 = vo2MaxMlKgMin {
            lines.append(String(format: "VO2 max: %.1f mL/kg/min", vo2))
        } else {
            lines.append("VO2 max: missing")
        }

        if let sleep = sleepHoursLastNight {
            lines.append(String(format: "Sleep last night (asleep): %.1f h", sleep))
        } else {
            lines.append("Sleep last night: missing")
        }
        if let onset = sleepOnset {
            lines.append("Sleep onset: \(iso.string(from: onset))")
        }
        if let wake = sleepWake {
            lines.append("Sleep wake: \(iso.string(from: wake))")
        }
        if let stages = sleepStages, stages.hasAnyStage {
            lines.append("Sleep stages last night (hours, only stages Health recorded):")
            if let core = stages.coreHours {
                lines.append(String(format: "  Core: %.1f h", core))
            }
            if let deep = stages.deepHours {
                lines.append(String(format: "  Deep: %.1f h", deep))
            }
            if let rem = stages.remHours {
                lines.append(String(format: "  REM: %.1f h", rem))
            }
            if let awake = stages.awakeHours {
                lines.append(String(format: "  Awake (in bed): %.1f h", awake))
            }
            if let unspecified = stages.unspecifiedAsleepHours {
                lines.append(String(format: "  Asleep (unspecified/legacy): %.1f h", unspecified))
            }
        } else if sleepHoursLastNight != nil {
            lines.append("Sleep stages: not broken out by Health (legacy asleep samples only).")
        }
        if let avg = averageSleepHours7d {
            lines.append(
                String(format: "Sleep ~7d average: %.1f h (%d nights)", avg, sleepNightsSampled)
            )
        }
        if let consistency = bedtimeConsistencyStdDevHours {
            lines.append(
                String(
                    format: "Bedtime consistency (onset std-dev): %.2f h over %d nights (lower is steadier)",
                    consistency,
                    sleepNightsSampled
                )
            )
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

        if let recovery {
            lines.append(recovery.summaryLine)
            for factor in recovery.factors.prefix(6) {
                lines.append("  Recovery factor: \(factor)")
            }
        }

        lines.append("Workouts last 24h: \(workoutCountLast24h)")
        if recentWorkouts.isEmpty {
            lines.append(
                "Recent workouts: none in last 90 days (denied Workouts permission, no Workout samples, or third-party hike never wrote to Health). Do not invent one. Tell the user: (1) Allow Health access / enable Workouts + Distance for FATNAG, (2) if they tracked in AllTrails or similar, turn on write-to-Apple-Health in that app. FATNAG cannot open AllTrails."
            )
        } else {
            lines.append("Recent workouts (newest first, all activity types including Hiking / Walking / Outdoor Walk / Running; source may be Watch, iPhone, or third-party):")
            for (index, workout) in recentWorkouts.enumerated() {
                let label = index == 0 ? "Last workout" : "Recent workout"
                lines.append(workout.promptLine(label: label))
            }
        }
        if let dist = walkingRunningDistance {
            lines.append(contentsOf: dist.promptLines(workoutsEmpty: recentWorkouts.isEmpty))
        } else {
            lines.append("Walking/running distance: missing (or Distance read denied).")
        }
        if !hasAnyFitnessSignal {
            lines.append(
                "Samples: empty across steps/HR/HRV/sleep/workouts/distance. Tell the user to allow FATNAG under Health → Data Access & Devices, wear Apple Watch, sync third-party apps into Health, then ask again."
            )
        }
        return lines.joined(separator: "\n")
    }

    /// DEBUG-friendly one-liner (no PII beyond activity type / distance).
    var debugSummaryLine: String {
        let workoutBits: String = {
            guard let w = lastWorkout else { return "lastWorkout=nil" }
            let km = w.distanceKm.map { String(format: "%.1fkm", $0) } ?? "nokm"
            return "lastWorkout=\(w.activityName)/\(km)/\(Int(w.durationMinutes))min/\(w.sourceName ?? "?")"
        }()
        let distBits: String = {
            guard let d = walkingRunningDistance else { return "dist=nil" }
            return String(
                format: "dist24h=%.1fkm dist7d=%.1fkm spike=%@",
                d.distanceKmLast24h,
                d.distanceKmLast7d,
                d.isNotableSpike ? "yes" : "no"
            )
        }()
        let sleepBits = sleepHoursLastNight.map { String(format: "sleep=%.1fh", $0) } ?? "sleep=nil"
        let hrvBits = hrvSDNNMs.map { String(format: "hrv=%.0fms", $0) } ?? "hrv=nil"
        let recoveryBits = recovery.map { "recovery=\($0.band.rawValue)" } ?? "recovery=nil"
        return "FitnessDigest access=\(access.rawValue) signals=\(hasAnyFitnessSignal) \(sleepBits) \(hrvBits) \(recoveryBits) workouts24h=\(workoutCountLast24h) recent=\(recentWorkouts.count) \(workoutBits) \(distBits)"
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
                let elevated = HealthScienceMath.isPreSleepHRElevated(
                    averageBpm: avg,
                    restingBpm: digest.restingHeartRateBpm,
                    aboveRestingDelta: thresholds.preSleepHRAboveRestingBpm,
                    absoluteFloorBpm: thresholds.preSleepHRAbsoluteBpm,
                    hrvSDNNMs: digest.hrvSDNNMs,
                    hrvMedian7dMs: digest.hrvMedian7dMs
                )
                if elevated {
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

        if HealthScienceMath.isWatchLikelyNotWorn(
            stepsToday: digest.stepsToday,
            workoutCountLast24h: digest.workoutCountLast24h,
            activeEnergyKcalToday: digest.activeEnergyKcalToday,
            distanceKmLast24h: digest.walkingRunningDistance?.distanceKmLast24h,
            heartRateSampleCountToday: digest.heartRateSampleCountToday,
            minSteps: thresholds.watchWearMinSteps,
            minHRSamples: thresholds.watchWearMinHRSamples
        ) {
            triggers.append(
                FitnessTrigger(
                    kind: .watchLikelyNotWorn,
                    message: "You moved today (steps, distance, energy, or a workout) but HR samples are sparse. Apple Watch probably wasn't on (or wrist detection was off).",
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
        guard let spacing = prefs.interval.grokNominalSeconds else { return false }
        guard let last = prefs.lastAutomatedCheckAt else { return true }
        return now.timeIntervalSince(last) >= spacing * 0.92
    }
}

// MARK: - Preferred unit system

/// User-facing mass / length / portion units. Stored preference; canonical values stay metric in models.
enum PreferredUnitSystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case metric
    case imperial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metric: return "Metric (kg, cm)"
        case .imperial: return "Imperial (lb, in)"
        }
    }

    var shortTitle: String {
        switch self {
        case .metric: return "Metric"
        case .imperial: return "Imperial"
        }
    }

    /// Prompt line for Grok / FM so replies match the user's units.
    var coachPromptLine: String {
        switch self {
        case .metric:
            return "Preferred units: metric. Use kg, cm, g, ml for weight, height, and food portions."
        case .imperial:
            return "Preferred units: imperial. Use lb, in (or ft/in), oz for weight, height, and food portions. Keep internal Health facts honest if only metric samples exist."
        }
    }

    var massLabel: String {
        switch self {
        case .metric: return "kg"
        case .imperial: return "lb"
        }
    }

    var heightLabel: String {
        switch self {
        case .metric: return "cm"
        case .imperial: return "in"
        }
    }
}

enum PreferredUnitSystemStore {
    private static let key = "thescale.preferredUnitSystem"

    static func load() -> PreferredUnitSystem {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let value = PreferredUnitSystem(rawValue: raw)
        else {
            return .metric
        }
        return value
    }

    static func save(_ system: PreferredUnitSystem) {
        UserDefaults.standard.set(system.rawValue, forKey: key)
    }
}

/// Format / convert display values. Models and HealthKit stay in kg / cm.
enum UnitFormat {
    static let kgPerLb = 0.45359237
    static let cmPerInch = 2.54

    static func kg(fromMass display: Double, system: PreferredUnitSystem) -> Double {
        switch system {
        case .metric: return display
        case .imperial: return display * kgPerLb
        }
    }

    static func mass(fromKg kg: Double, system: PreferredUnitSystem) -> Double {
        switch system {
        case .metric: return kg
        case .imperial: return kg / kgPerLb
        }
    }

    static func cm(fromHeight display: Double, system: PreferredUnitSystem) -> Double {
        switch system {
        case .metric: return display
        case .imperial: return display * cmPerInch
        }
    }

    static func height(fromCm cm: Double, system: PreferredUnitSystem) -> Double {
        switch system {
        case .metric: return cm
        case .imperial: return cm / cmPerInch
        }
    }

    static func massString(_ kg: Double, system: PreferredUnitSystem, fractionDigits: Int = 1) -> String {
        if abs(kg) < 1 {
            return compactSubKilogram(kg, system: system, signed: false)
        }
        let value = mass(fromKg: kg, system: system)
        return String(format: "%.\(fractionDigits)f %@", value, system.massLabel)
    }

    static func massDeltaString(_ kgDelta: Double, system: PreferredUnitSystem, fractionDigits: Int = 2) -> String {
        if abs(kgDelta) < 1 {
            return compactSubKilogram(kgDelta, system: system, signed: true)
        }
        let value = mass(fromKg: kgDelta, system: system)
        let sign = value >= 0 ? "+" : ""
        return String(format: "%@%.\(fractionDigits)f %@", sign, value, system.massLabel)
    }

    /// Sub-1 kg magnitudes → grams (metric) or ounces (imperial). Matches unit prefs.
    /// Examples: `650g`, `+650g`, `-350g`, `22.9 oz`, `+8.1 oz`.
    static func compactSubKilogram(
        _ kg: Double,
        system: PreferredUnitSystem,
        signed: Bool
    ) -> String {
        switch system {
        case .metric:
            let grams = Int((kg * 1000.0).rounded())
            if signed {
                if grams > 0 { return "+\(grams)g" }
                return "\(grams)g"
            }
            return "\(abs(grams))g"
        case .imperial:
            let oz = mass(fromKg: kg, system: .imperial) * 16.0
            let rounded = (oz * 10.0).rounded() / 10.0
            if signed {
                let sign = rounded >= 0 ? "+" : ""
                return String(format: "%@%.1f oz", sign, rounded)
            }
            return String(format: "%.1f oz", abs(rounded))
        }
    }

    static func heightString(_ cm: Double, system: PreferredUnitSystem, fractionDigits: Int = 0) -> String {
        let value = height(fromCm: cm, system: system)
        return String(format: "%.\(fractionDigits)f %@", value, system.heightLabel)
    }

    /// Ingredient portion hint for meal cards / prompts (always starts from grams).
    static func portionGrams(_ grams: Int, system: PreferredUnitSystem) -> String {
        switch system {
        case .metric:
            return "\(grams) g"
        case .imperial:
            let oz = Double(grams) / 28.349523125
            if oz >= 10 {
                return String(format: "%.0f oz", oz)
            }
            return String(format: "%.1f oz", oz)
        }
    }

    static func portionMl(_ ml: Int, system: PreferredUnitSystem) -> String {
        switch system {
        case .metric:
            return "\(ml) ml"
        case .imperial:
            let flOz = Double(ml) / 29.5735295625
            return String(format: "%.1f fl oz", flOz)
        }
    }

    /// Weekly mini-goal title: `Sunday 82.40 kg` or `Sunday 180.3 lb`.
    static func sundayTitle(kg: Double, system: PreferredUnitSystem) -> String {
        let mass = mass(fromKg: kg, system: system)
        let digits = system == .metric ? 2 : 1
        return String(format: "Sunday %.\(digits)f %@", mass, system.massLabel)
    }
}
