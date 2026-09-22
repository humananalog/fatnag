import Foundation
import HealthKit

@MainActor
protocol HealthWriting: AnyObject {
    var isHealthDataAvailable: Bool { get }
    /// True after the system Health permission sheet has been presented at least once.
    var authorizationWasRequested: Bool { get }
    func requestAuthorizationIfNeeded() async throws
    /// Call again after the user taps Allow Health access in Settings (sheet may no-op if already decided).
    func reRequestAuthorization() async throws
    /// Recent body-mass samples from Apple Health (most recent first).
    func fetchRecentWeights(limit: Int) async throws -> [HealthWeightSample]
    /// Body mass samples in `[start, end]` (oldest first).
    func fetchWeights(from start: Date, to end: Date) async throws -> [HealthMetricSample]
    /// Body fat % samples in `[start, end]` (oldest first). Values are percent (e.g. 18.5).
    func fetchBodyFatPercents(from start: Date, to end: Date) async throws -> [HealthMetricSample]
    /// Fitness / recovery digest for Grok monitoring (HR, sleep, steps, energy, workouts).
    func fetchFitnessDigest(
        preSleepWindowMinutes: Int,
        now: Date
    ) async throws -> FitnessDigest
    /// Lean today totals for home gauges only (steps + move + nutrition). Fast path.
    func fetchHomeDailyMetrics(now: Date) async throws -> HomeDailyMetrics
    func write(
        measurement: ScaleMeasurement,
        composition: BodyCompositionResult?,
        profile: UserBodyProfile
    ) async throws
    func write(draft: EditableMeasurementDraft, profile: UserBodyProfile) async throws
}

enum HealthKitWriterError: LocalizedError {
    case unavailable
    case missingType(String)
    case saveFailed(String)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Health is not available on this device."
        case .missingType(let name):
            return "Missing HealthKit type: \(name)."
        case .saveFailed(let message):
            return message
        case .readFailed(let message):
            return message
        }
    }
}

/// Reads weight / body-fat / fitness signals and writes confirmed scale readings to HealthKit.
///
/// Authorized:
/// - Read: bodyMass, bodyFatPercentage, heartRate, restingHeartRate,
///   heartRateVariabilitySDNN, respiratoryRate, appleSleepingWristTemperature,
///   oxygenSaturation, vo2Max, stepCount, activeEnergyBurned, appleExerciseTime,
///   sleepAnalysis, workout, distanceWalkingRunning
/// - Write: bodyMass, bodyMassIndex, bodyFatPercentage, leanBodyMass
///
/// Shown in-app only (no first-class HealthKit quantity): muscle mass, bone mass,
/// body water %, visceral fat index, raw impedance.
///
/// We only request types the digest / charts / algorithms actually use.
@MainActor
final class HealthKitWriter: HealthWriting {
    private static let authorizationRequestedKey = "thescale.healthKitAuthorizationRequested"
    /// Bump when `readTypes` gains new identifiers so upgrades re-prompt (HRV, sleep stages, …).
    private static let readAuthSchemaVersion = 4
    private static let readAuthSchemaKey = "thescale.healthKitReadAuthSchema"
    private static let lastWorkoutLookbackDays = 90
    private static let recentWorkoutLimit = 5

    private let store = HKHealthStore()
    private var didAuthorize = false

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var authorizationWasRequested: Bool {
        didAuthorize || UserDefaults.standard.bool(forKey: Self.authorizationRequestedKey)
    }

    private var shareTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        if let mass = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(mass) }
        if let bmi = HKObjectType.quantityType(forIdentifier: .bodyMassIndex) { types.insert(bmi) }
        if let fat = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) { types.insert(fat) }
        if let lean = HKObjectType.quantityType(forIdentifier: .leanBodyMass) { types.insert(lean) }
        return types
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let quantityIds: [HKQuantityTypeIdentifier] = [
            .bodyMass,
            .bodyFatPercentage,
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .respiratoryRate,
            .appleSleepingWristTemperature,
            .oxygenSaturation,
            .vo2Max,
            .stepCount,
            .activeEnergyBurned,
            .appleExerciseTime,
            .distanceWalkingRunning,
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryFiber,
            .dietaryIron,
            .dietaryPotassium
        ]
        for id in quantityIds {
            if let type = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    private var needsReadAuthRefresh: Bool {
        let stored = UserDefaults.standard.integer(forKey: Self.readAuthSchemaKey)
        return stored < Self.readAuthSchemaVersion
    }

    func requestAuthorizationIfNeeded() async throws {
        guard isHealthDataAvailable else { throw HealthKitWriterError.unavailable }
        if didAuthorize, !needsReadAuthRefresh {
            // Still ask iOS if new types appeared (no-op when already decided for those types).
            let status = try await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)
            if status != .shouldRequest { return }
        }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        markAuthorizationRequested()
    }

    func reRequestAuthorization() async throws {
        guard isHealthDataAvailable else { throw HealthKitWriterError.unavailable }
        didAuthorize = false
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        markAuthorizationRequested()
    }

    private func markAuthorizationRequested() {
        didAuthorize = true
        UserDefaults.standard.set(true, forKey: Self.authorizationRequestedKey)
        UserDefaults.standard.set(Self.readAuthSchemaVersion, forKey: Self.readAuthSchemaKey)
    }

    func fetchRecentWeights(limit: Int = 14) async throws -> [HealthWeightSample] {
        guard isHealthDataAvailable else { throw HealthKitWriterError.unavailable }
        try await requestAuthorizationIfNeeded()
        guard let massType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitWriterError.missingType("bodyMass")
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: massType,
                predicate: nil,
                limit: max(limit, 1),
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: [])
                        return
                    }
                    continuation.resume(throwing: HealthKitWriterError.readFailed(error.localizedDescription))
                    return
                }
                let unit = HKUnit.gramUnit(with: .kilo)
                let mapped: [HealthWeightSample] = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HealthWeightSample(
                        id: sample.uuid,
                        weightKg: sample.quantity.doubleValue(for: unit),
                        date: sample.endDate
                    )
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    func fetchWeights(from start: Date, to end: Date) async throws -> [HealthMetricSample] {
        try await fetchQuantitySamples(
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo),
            from: start,
            to: end,
            scale: 1
        )
    }

    func fetchBodyFatPercents(from start: Date, to end: Date) async throws -> [HealthMetricSample] {
        // HealthKit stores body fat as a fraction (0.185); charts use percent (18.5).
        try await fetchQuantitySamples(
            identifier: .bodyFatPercentage,
            unit: .percent(),
            from: start,
            to: end,
            scale: 100
        )
    }

    func fetchHomeDailyMetrics(now: Date = Date()) async throws -> HomeDailyMetrics {
        guard isHealthDataAvailable else { throw HealthKitWriterError.unavailable }
        try await requestAuthorizationIfNeeded()

        let dayStart = Calendar.current.startOfDay(for: now)
        // Per-type soft sums: one empty dietary type must not kill steps/move gauges.
        async let steps = softSumQuantity(.stepCount, unit: .count(), from: dayStart, to: now)
        async let energy = softSumQuantity(
            .activeEnergyBurned,
            unit: .kilocalorie(),
            from: dayStart,
            to: now
        )
        async let dietaryEnergy = softSumQuantity(
            .dietaryEnergyConsumed,
            unit: .kilocalorie(),
            from: dayStart,
            to: now
        )
        async let dietaryProtein = softSumQuantity(
            .dietaryProtein,
            unit: .gram(),
            from: dayStart,
            to: now
        )
        async let dietaryFiber = softSumQuantity(
            .dietaryFiber,
            unit: .gram(),
            from: dayStart,
            to: now
        )
        async let dietaryIron = softSumQuantity(
            .dietaryIron,
            unit: .gramUnit(with: .milli),
            from: dayStart,
            to: now
        )
        async let dietaryPotassium = softSumQuantity(
            .dietaryPotassium,
            unit: .gramUnit(with: .milli),
            from: dayStart,
            to: now
        )

        let (
            stepsV,
            energyV,
            dietEnergyV,
            dietProteinV,
            dietFiberV,
            dietIronV,
            dietPotassiumV
        ) = await (
            steps, energy, dietaryEnergy, dietaryProtein, dietaryFiber, dietaryIron, dietaryPotassium
        )

        return HomeDailyMetrics(
            stepsToday: stepsV,
            activeEnergyKcalToday: energyV,
            dietaryEnergyKcalToday: dietEnergyV,
            dietaryProteinGramsToday: dietProteinV,
            dietaryFiberGramsToday: dietFiberV,
            dietaryIronMgToday: dietIronV,
            dietaryPotassiumMgToday: dietPotassiumV,
            generatedAt: now
        )
    }

    func fetchFitnessDigest(
        preSleepWindowMinutes: Int,
        now: Date = Date()
    ) async throws -> FitnessDigest {
        guard isHealthDataAvailable else { throw HealthKitWriterError.unavailable }
        try await requestAuthorizationIfNeeded()

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let last24h = now.addingTimeInterval(-24 * 3600)
        let last7d = now.addingTimeInterval(-7 * 86_400)
        let hrUnit = HKUnit.count().unitDivided(by: .minute())
        let meter = HKUnit.meter()
        let msUnit = HKUnit.secondUnit(with: .milli)
        let breathUnit = HKUnit.count().unitDivided(by: .minute())
        let spo2Unit = HKUnit.percent()
        let vo2Unit = HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute()))

        async let steps = sumQuantity(.stepCount, unit: .count(), from: dayStart, to: now)
        async let energy = sumQuantity(
            .activeEnergyBurned,
            unit: .kilocalorie(),
            from: dayStart,
            to: now
        )
        async let energy7d = sumQuantity(
            .activeEnergyBurned,
            unit: .kilocalorie(),
            from: last7d,
            to: now
        )
        async let exerciseMin = sumQuantity(
            .appleExerciseTime,
            unit: .minute(),
            from: dayStart,
            to: now
        )
        async let resting = latestQuantity(
            .restingHeartRate,
            unit: hrUnit,
            from: last7d,
            to: now
        )
        async let latestHR = latestQuantity(.heartRate, unit: hrUnit, from: dayStart, to: now)
        async let hrToday = fetchQuantitySamples(
            identifier: .heartRate,
            unit: hrUnit,
            from: dayStart,
            to: now,
            scale: 1
        )
        async let hrvRecent = latestQuantity(
            .heartRateVariabilitySDNN,
            unit: msUnit,
            from: last24h,
            to: now
        )
        async let hrvWeekSamples = fetchQuantitySamples(
            identifier: .heartRateVariabilitySDNN,
            unit: msUnit,
            from: last7d,
            to: now,
            scale: 1
        )
        async let respiratory = latestQuantity(
            .respiratoryRate,
            unit: breathUnit,
            from: last24h,
            to: now
        )
        async let wristTemp = latestQuantity(
            .appleSleepingWristTemperature,
            unit: .degreeCelsius(),
            from: last7d,
            to: now
        )
        async let spo2 = latestQuantity(
            .oxygenSaturation,
            unit: spo2Unit,
            from: last24h,
            to: now
        )
        async let vo2 = latestQuantity(
            .vo2Max,
            unit: vo2Unit,
            from: now.addingTimeInterval(-90 * 86_400),
            to: now
        )
        async let workouts = workoutCount(from: last24h, to: now)
        async let sleep = sleepSnapshot(endingNear: now)
        async let recent = recentWorkouts(
            lookbackDays: Self.lastWorkoutLookbackDays,
            limit: Self.recentWorkoutLimit,
            now: now
        )
        async let dist24hMeters = sumQuantity(
            .distanceWalkingRunning,
            unit: meter,
            from: last24h,
            to: now
        )
        async let dist7dMeters = sumQuantity(
            .distanceWalkingRunning,
            unit: meter,
            from: last7d,
            to: now
        )
        async let dietaryEnergy = sumQuantity(
            .dietaryEnergyConsumed,
            unit: .kilocalorie(),
            from: dayStart,
            to: now
        )
        async let dietaryProtein = sumQuantity(
            .dietaryProtein,
            unit: .gram(),
            from: dayStart,
            to: now
        )
        async let dietaryFiber = sumQuantity(
            .dietaryFiber,
            unit: .gram(),
            from: dayStart,
            to: now
        )
        async let dietaryIron = sumQuantity(
            .dietaryIron,
            unit: .gramUnit(with: .milli),
            from: dayStart,
            to: now
        )
        async let dietaryPotassium = sumQuantity(
            .dietaryPotassium,
            unit: .gramUnit(with: .milli),
            from: dayStart,
            to: now
        )

        let (
            stepsV,
            energyV,
            energy7dV,
            exerciseV,
            restingV,
            latestHRV,
            hrSamples,
            hrvV,
            hrvWeek,
            respiratoryV,
            wristTempV,
            spo2Fraction,
            vo2V,
            workoutN,
            sleepInfo,
            workoutSummaries,
            dist24m,
            dist7m,
            dietEnergyV,
            dietProteinV,
            dietFiberV,
            dietIronV,
            dietPotassiumV
        ) = try await (
            steps, energy, energy7d, exerciseMin, resting, latestHR, hrToday, hrvRecent, hrvWeekSamples,
            respiratory, wristTemp, spo2, vo2, workouts, sleep, recent, dist24hMeters, dist7dMeters,
            dietaryEnergy, dietaryProtein, dietaryFiber, dietaryIron, dietaryPotassium
        )

        var preSleepAvg: Double?
        var preSleepCount = 0
        if let onset = sleepInfo.onset {
            let windowStart = onset.addingTimeInterval(-Double(preSleepWindowMinutes) * 60)
            let preSamples = try await fetchQuantitySamples(
                identifier: .heartRate,
                unit: hrUnit,
                from: windowStart,
                to: onset,
                scale: 1
            )
            preSleepCount = preSamples.count
            if !preSamples.isEmpty {
                preSleepAvg = preSamples.map(\.value).reduce(0, +) / Double(preSamples.count)
            }
        }

        let hrvMedian7d: Double? = {
            let values = hrvWeek.map(\.value).sorted()
            guard !values.isEmpty else { return nil }
            return values[values.count / 2]
        }()

        let spo2Percent = spo2Fraction.map { $0 * 100.0 }

        let access: HealthDigestAccess = authorizationWasRequested ? .readable : .notRequested
        let detail: String = {
            if !authorizationWasRequested {
                return "Health permission sheet not completed yet."
            }
            return "Health permission sheet completed. Read grants are private to iOS; empty samples may mean denial, no data, or a third-party app that never wrote to Health."
        }()

        let distanceSpike = HealthDistanceSpike.from(
            km24h: dist24m.map { $0 / 1000.0 },
            km7d: dist7m.map { $0 / 1000.0 }
        )

        let recovery = HealthScienceMath.recoveryHeuristic(
            sleepHours: sleepInfo.totalAsleepHours,
            stages: sleepInfo.stages,
            hrvSDNNMs: hrvV,
            hrvMedian7dMs: hrvMedian7d,
            restingHRBpm: restingV,
            workoutCountLast24h: workoutN,
            lastWorkoutDurationMinutes: workoutSummaries.first?.durationMinutes,
            lastWorkoutKcal: workoutSummaries.first?.activeEnergyKcal
        )

        let energy7dAvg: Double? = {
            guard let total = energy7dV, total > 0 else { return nil }
            return total / 7.0
        }()

        let digest = FitnessDigest(
            stepsToday: stepsV ?? 0,
            activeEnergyKcalToday: energyV ?? 0,
            activeEnergyKcalLast7dAverage: energy7dAvg,
            appleExerciseMinutesToday: exerciseV,
            dietaryEnergyKcalToday: dietEnergyV,
            dietaryProteinGramsToday: dietProteinV,
            dietaryFiberGramsToday: dietFiberV,
            dietaryIronMgToday: dietIronV,
            dietaryPotassiumMgToday: dietPotassiumV,
            restingHeartRateBpm: restingV,
            latestHeartRateBpm: latestHRV,
            heartRateSampleCountToday: hrSamples.count,
            hrvSDNNMs: hrvV,
            hrvMedian7dMs: hrvMedian7d,
            respiratoryRateBreathsPerMin: respiratoryV,
            wristTemperatureDeltaC: wristTempV,
            oxygenSaturationPercent: spo2Percent,
            vo2MaxMlKgMin: vo2V,
            sleepHoursLastNight: sleepInfo.totalAsleepHours,
            sleepOnset: sleepInfo.onset,
            sleepWake: sleepInfo.wake,
            sleepStages: sleepInfo.stages,
            bedtimeConsistencyStdDevHours: sleepInfo.bedtimeConsistencyStdDevHours,
            averageSleepHours7d: sleepInfo.averageAsleepHours7d,
            sleepNightsSampled: sleepInfo.nightsSampled,
            preSleepAverageHRBpm: preSleepAvg,
            preSleepHRSampleCount: preSleepCount,
            workoutCountLast24h: workoutN,
            recentWorkouts: workoutSummaries,
            walkingRunningDistance: distanceSpike,
            recovery: recovery,
            access: access,
            accessDetail: detail,
            generatedAt: now
        )
        #if DEBUG
        print("[TheScale] \(digest.debugSummaryLine)")
        #endif
        return digest
    }

    private func sumQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthKitWriterError.missingType(identifier.rawValue)
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error {
                    // Empty day / no samples for this type: treat as nil, never fail the whole digest.
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: HealthKitWriterError.readFailed(error.localizedDescription))
                    return
                }
                let value = stats?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// Soft sum for home gauges: never throws. Missing / denied / empty → 0.
    private func softSumQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async -> Double {
        do {
            return try await sumQuantity(identifier, unit: unit, from: start, to: end) ?? 0
        } catch {
            #if DEBUG
            print("[TheScale] softSum \(identifier.rawValue) soft-fail: \(error.localizedDescription)")
            #endif
            return 0
        }
    }

    /// HealthKit often surfaces empty ranges as `HKError.errorNoData` instead of empty stats.
    nonisolated private static func isNoDataError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == HKError.errorDomain, ns.code == HKError.Code.errorNoData.rawValue {
            return true
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("no data available for the specified predicate")
            || message.contains("no data available")
    }

    private func latestQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async throws -> Double? {
        let samples = try await fetchQuantitySamples(
            identifier: identifier,
            unit: unit,
            from: start,
            to: end,
            scale: 1
        )
        return samples.last?.value
    }

    private func workoutCount(from start: Date, to end: Date) async throws -> Int {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictEndDate
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: 0)
                        return
                    }
                    continuation.resume(throwing: HealthKitWriterError.readFailed(error.localizedDescription))
                    return
                }
                continuation.resume(returning: samples?.count ?? 0)
            }
            store.execute(query)
        }
    }

    /// All workout activity types (Hiking, Walking, Running, Other, third-party). Newest first.
    private func recentWorkouts(
        lookbackDays: Int,
        limit: Int,
        now: Date
    ) async throws -> [HealthWorkoutSummary] {
        let start = now.addingTimeInterval(-Double(lookbackDays) * 86_400)
        // Prefer end-date window so a long hike that started earlier still qualifies.
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: now,
            options: .strictEndDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: max(limit, 1),
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: [])
                        return
                    }
                    continuation.resume(throwing: HealthKitWriterError.readFailed(error.localizedDescription))
                    return
                }
                let workouts = (samples as? [HKWorkout] ?? []).map { workout -> HealthWorkoutSummary in
                    HealthWorkoutSummary(
                        activityName: Self.workoutActivityName(workout.workoutActivityType),
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        durationMinutes: workout.duration / 60.0,
                        distanceKm: Self.distanceKilometers(from: workout),
                        activeEnergyKcal: Self.activeEnergyKcal(from: workout),
                        sourceName: workout.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    nonisolated private static func distanceKilometers(from workout: HKWorkout) -> Double? {
        if let total = workout.totalDistance {
            let km = total.doubleValue(for: .meter()) / 1000.0
            if km > 0 { return km }
        }
        let identifiers: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming
        ]
        for identifier in identifiers {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier),
                  let sum = workout.statistics(for: type)?.sumQuantity()
            else { continue }
            let km = sum.doubleValue(for: .meter()) / 1000.0
            if km > 0 { return km }
        }
        return nil
    }

    nonisolated private static func activeEnergyKcal(from workout: HKWorkout) -> Double? {
        if let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let sum = workout.statistics(for: type)?.sumQuantity() {
            return sum.doubleValue(for: .kilocalorie())
        }
        return nil
    }

    private func sleepSnapshot(endingNear now: Date) async throws -> HealthSleepSnapshot {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitWriterError.missingType("sleepAnalysis")
        }
        // ~8 days covers last night + 7-night consistency / average.
        let start = now.addingTimeInterval(-8 * 86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    if Self.isNoDataError(error) {
                        let empty = HealthScienceMath.buildSleepSnapshot(samples: [], now: now)
                        continuation.resume(returning: empty)
                        return
                    }
                    continuation.resume(throwing: HealthKitWriterError.readFailed(error.localizedDescription))
                    return
                }
                let mapped: [(value: Int, start: Date, end: Date)] = (samples as? [HKCategorySample] ?? []).map {
                    (value: $0.value, start: $0.startDate, end: $0.endDate)
                }
                let snapshot = HealthScienceMath.buildSleepSnapshot(samples: mapped, now: now)
                continuation.resume(returning: snapshot)
            }
            store.execute(query)
        }
    }

    private func fetchQuantitySamples(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date,
        scale: Double
    ) async throws -> [HealthMetricSample] {
        guard isHealthDataAvailable else { throw HealthKitWriterError.unavailable }
        try await requestAuthorizationIfNeeded()
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthKitWriterError.missingType(identifier.rawValue)
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: [])
                        return
                    }
                    continuation.resume(throwing: HealthKitWriterError.readFailed(error.localizedDescription))
                    return
                }
                let mapped: [HealthMetricSample] = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HealthMetricSample(
                        id: sample.uuid,
                        value: sample.quantity.doubleValue(for: unit) * scale,
                        date: sample.endDate
                    )
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    func write(
        measurement: ScaleMeasurement,
        composition: BodyCompositionResult?,
        profile: UserBodyProfile
    ) async throws {
        let draft = EditableMeasurementDraft.from(
            measurement: measurement,
            composition: composition,
            profile: profile
        )
        try await write(draft: draft, profile: profile)
    }

    func write(draft: EditableMeasurementDraft, profile: UserBodyProfile) async throws {
        guard isHealthDataAvailable else { throw HealthKitWriterError.unavailable }

        let date = draft.scaleDate ?? draft.receivedAt
        var samples: [HKQuantitySample] = []

        guard let massType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitWriterError.missingType("bodyMass")
        }
        samples.append(
            HKQuantitySample(
                type: massType,
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: draft.weightKg),
                start: date,
                end: date,
                metadata: metadata(for: draft)
            )
        )

        let bmiValue = draft.bmi
            ?? BodyCompositionCalculator.bodyMassIndex(
                weightKg: draft.weightKg,
                heightCm: profile.heightCm
            )

        if let bmiType = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            samples.append(
                HKQuantitySample(
                    type: bmiType,
                    quantity: HKQuantity(unit: .count(), doubleValue: bmiValue),
                    start: date,
                    end: date
                )
            )
        }

        if draft.includeCompositionInHealth {
            if let fat = draft.bodyFatPercent,
               let fatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
                samples.append(
                    HKQuantitySample(
                        type: fatType,
                        quantity: HKQuantity(unit: .percent(), doubleValue: fat / 100.0),
                        start: date,
                        end: date
                    )
                )
            }
            if let lean = draft.leanBodyMassKg,
               let leanType = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) {
                samples.append(
                    HKQuantitySample(
                        type: leanType,
                        quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: lean),
                        start: date,
                        end: date
                    )
                )
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(samples) { success, error in
                if let error {
                    continuation.resume(throwing: HealthKitWriterError.saveFailed(error.localizedDescription))
                } else if !success {
                    continuation.resume(throwing: HealthKitWriterError.saveFailed("HealthKit save returned false."))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    nonisolated private static func workoutActivityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .dance: return "Dance"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair climbing"
        case .traditionalStrengthTraining: return "Strength training"
        case .functionalStrengthTraining: return "Functional strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .coreTraining: return "Core training"
        case .flexibility: return "Flexibility"
        case .cooldown: return "Cooldown"
        case .mindAndBody: return "Mind and body"
        case .mixedCardio: return "Mixed cardio"
        case .crossTraining: return "Cross training"
        case .tennis: return "Tennis"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .golf: return "Golf"
        case .climbing: return "Climbing"
        case .other: return "Other workout"
        default: return "Workout"
        }
    }

    private func metadata(for draft: EditableMeasurementDraft) -> [String: Any] {
        var meta: [String: Any] = [
            HKMetadataKeyWasUserEntered: draft.isManualEntry,
            "SourceDevice": draft.isManualEntry
                ? "Manual entry"
                : "Xiaomi Mi Body Composition Scale 2 (XMTZC05HM)",
            "App": "The Scale"
        ]
        if let ohms = draft.impedanceOhms {
            meta["ImpedanceOhms"] = ohms
        }
        return meta
    }
}
