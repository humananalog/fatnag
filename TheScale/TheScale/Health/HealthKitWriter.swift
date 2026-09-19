import Foundation
import HealthKit

@MainActor
protocol HealthWriting: AnyObject {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorizationIfNeeded() async throws
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
/// - Read: bodyMass, bodyFatPercentage, heartRate, restingHeartRate, stepCount,
///   activeEnergyBurned, sleepAnalysis, workout
/// - Write: bodyMass, bodyMassIndex, bodyFatPercentage, leanBodyMass
///
/// Shown in-app only (no first-class HealthKit quantity): muscle mass, bone mass,
/// body water %, visceral fat index, raw impedance.
@MainActor
final class HealthKitWriter: HealthWriting {
    private let store = HKHealthStore()
    private var didAuthorize = false

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

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
        if let mass = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(mass) }
        if let fat = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) { types.insert(fat) }
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(hr) }
        if let rhr = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.insert(rhr) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAuthorizationIfNeeded() async throws {
        guard isHealthDataAvailable else { throw HealthKitWriterError.unavailable }
        if didAuthorize { return }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        didAuthorize = true
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

    func fetchFitnessDigest(
        preSleepWindowMinutes: Int,
        now: Date = Date()
    ) async throws -> FitnessDigest {
        guard isHealthDataAvailable else { throw HealthKitWriterError.unavailable }
        try await requestAuthorizationIfNeeded()

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let last24h = now.addingTimeInterval(-24 * 3600)
        let hrUnit = HKUnit.count().unitDivided(by: .minute())

        async let steps = sumQuantity(.stepCount, unit: .count(), from: dayStart, to: now)
        async let energy = sumQuantity(
            .activeEnergyBurned,
            unit: .kilocalorie(),
            from: dayStart,
            to: now
        )
        async let resting = latestQuantity(
            .restingHeartRate,
            unit: hrUnit,
            from: now.addingTimeInterval(-7 * 86_400),
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
        async let workouts = workoutCount(from: last24h, to: now)
        async let sleep = sleepSummary(endingNear: now)

        let (stepsV, energyV, restingV, latestHRV, hrSamples, workoutN, sleepInfo) = try await (
            steps, energy, resting, latestHR, hrToday, workouts, sleep
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

        return FitnessDigest(
            stepsToday: stepsV,
            activeEnergyKcalToday: energyV,
            restingHeartRateBpm: restingV,
            latestHeartRateBpm: latestHRV,
            heartRateSampleCountToday: hrSamples.count,
            sleepHoursLastNight: sleepInfo.hours,
            sleepOnset: sleepInfo.onset,
            preSleepAverageHRBpm: preSleepAvg,
            preSleepHRSampleCount: preSleepCount,
            workoutCountLast24h: workoutN,
            generatedAt: now
        )
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
                    continuation.resume(throwing: HealthKitWriterError.readFailed(error.localizedDescription))
                    return
                }
                let value = stats?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
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
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitWriterError.readFailed(error.localizedDescription))
                    return
                }
                continuation.resume(returning: samples?.count ?? 0)
            }
            store.execute(query)
        }
    }

    private func sleepSummary(endingNear now: Date) async throws -> (hours: Double?, onset: Date?) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitWriterError.missingType("sleepAnalysis")
        }
        let start = now.addingTimeInterval(-36 * 3600)
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
                    continuation.resume(throwing: HealthKitWriterError.readFailed(error.localizedDescription))
                    return
                }
                let cats = (samples as? [HKCategorySample] ?? []).filter { sample in
                    Self.isAsleepValue(sample.value)
                }
                guard !cats.isEmpty else {
                    continuation.resume(returning: (nil, nil))
                    return
                }
                let onset = cats.map(\.startDate).min()
                let seconds = cats.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: (seconds / 3600.0, onset))
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

    nonisolated private static func isAsleepValue(_ value: Int) -> Bool {
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            1 // legacy HKCategoryValueSleepAnalysis.asleep
        ]
        return asleepValues.contains(value)
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
