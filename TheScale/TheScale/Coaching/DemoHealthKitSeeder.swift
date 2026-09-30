#if DEBUG
import Foundation
import HealthKit

/// Writes a realistic HealthKit corpus into the Simulator / device for demo personas.
/// There is no `simctl` Health fixture API — the app must save samples itself after share auth.
enum DemoHealthKitSeeder {
    private static let metadataKey = "app.thescale.demoPersona"
    private static let store = HKHealthStore()

    /// Full share set needed to inject steps / energy / diet / sleep / workouts (DEBUG only).
    private static var shareTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        let ids: [HKQuantityTypeIdentifier] = [
            .bodyMass,
            .bodyMassIndex,
            .bodyFatPercentage,
            .leanBodyMass,
            .stepCount,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .oxygenSaturation,
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryFiber,
            .dietaryIron,
            .dietaryPotassium,
        ]
        for id in ids {
            if let t = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(t)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    private static var readTypes: Set<HKObjectType> {
        Set(shareTypes.map { $0 as HKObjectType })
    }

    static func seed(
        persona: DemoPersonaSeeder.Persona,
        profile: UserBodyProfile,
        weights: [HealthMetricSample],
        bodyFat: [HealthMetricSample],
        digest: FitnessDigest,
        now: Date = Date()
    ) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitWriterError.unavailable
        }

        // Promo / ASC screenshot launches must never present the Health share sheet.
        // In-memory demo digest + weights already drive the UI for captures.
        if PromoCaptureMode.isActive || ProcessInfo.processInfo.arguments.contains("-debugMonthlyHero") {
            return
        }

        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)

        // Drop prior demo samples from this app so re-seeds stay clean.
        try await deletePriorDemoSamples(persona: persona)

        var objects: [HKObject] = []
        objects.append(contentsOf: massSamples(weights: weights, persona: persona, heightCm: profile.heightCm))
        objects.append(contentsOf: fatSamples(bodyFat: bodyFat, persona: persona, weights: weights))
        objects.append(contentsOf: activitySamples(persona: persona, digest: digest, now: now))
        objects.append(contentsOf: nutritionSamples(persona: persona, digest: digest, now: now))
        objects.append(contentsOf: vitalsSamples(persona: persona, digest: digest, now: now))
        objects.append(contentsOf: sleepSamples(persona: persona, digest: digest, now: now))

        if !objects.isEmpty {
            try await save(objects)
        }

        if let workout = makeWorkout(persona: persona, now: now) {
            try await save([workout])
        }
    }

    // MARK: - Sample builders

    private static func massSamples(
        weights: [HealthMetricSample],
        persona: DemoPersonaSeeder.Persona,
        heightCm: Double
    ) -> [HKObject] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let unit = HKUnit.gramUnit(with: .kilo)
        let heightM = max(heightCm, 100) / 100
        var out: [HKObject] = []
        for sample in weights {
            let q = HKQuantity(unit: unit, doubleValue: sample.value)
            out.append(
                HKQuantitySample(
                    type: type,
                    quantity: q,
                    start: sample.date,
                    end: sample.date,
                    metadata: meta(persona)
                )
            )
            if let bmiType = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
                let bmi = sample.value / (heightM * heightM)
                out.append(
                    HKQuantitySample(
                        type: bmiType,
                        quantity: HKQuantity(unit: HKUnit.count(), doubleValue: bmi),
                        start: sample.date,
                        end: sample.date,
                        metadata: meta(persona)
                    )
                )
            }
        }
        return out
    }

    private static func fatSamples(
        bodyFat: [HealthMetricSample],
        persona: DemoPersonaSeeder.Persona,
        weights: [HealthMetricSample]
    ) -> [HKObject] {
        guard let fatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else { return [] }
        var out: [HKObject] = []
        for sample in bodyFat {
            // HealthKit stores fraction 0…1.
            let fraction = min(max(sample.value / 100.0, 0.05), 0.6)
            out.append(
                HKQuantitySample(
                    type: fatType,
                    quantity: HKQuantity(unit: .percent(), doubleValue: fraction),
                    start: sample.date,
                    end: sample.date,
                    metadata: meta(persona)
                )
            )
            if let leanType = HKQuantityType.quantityType(forIdentifier: .leanBodyMass),
               let mass = nearestWeight(to: sample.date, in: weights)
            {
                let leanKg = mass * (1.0 - fraction)
                out.append(
                    HKQuantitySample(
                        type: leanType,
                        quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: leanKg),
                        start: sample.date,
                        end: sample.date,
                        metadata: meta(persona)
                    )
                )
            }
        }
        return out
    }

    /// Spread today's steps + move energy + distance across the morning so gauges look alive.
    private static func activitySamples(
        persona: DemoPersonaSeeder.Persona,
        digest: FitnessDigest,
        now: Date
    ) -> [HKObject] {
        let cal = Calendar.current
        let stepsTotal = digest.stepsToday ?? (persona == .male ? 9_420 : 8_150)
        let energyTotal = digest.activeEnergyKcalToday ?? (persona == .male ? 640 : 480)
        let distanceKm = persona == .male ? 7.2 : 6.1

        // Hourly buckets from 7:00 → now (or 17:00).
        let startHour = 7
        let endHour = max(startHour + 1, min(cal.component(.hour, from: now), 17))
        let buckets = max(endHour - startHour, 4)
        var out: [HKObject] = []

        guard let dayStart = cal.date(bySettingHour: startHour, minute: 5, second: 0, of: now) else {
            return out
        }

        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)

        for i in 0..<buckets {
            let weight = bucketWeight(i: i, count: buckets)
            guard let start = cal.date(byAdding: .hour, value: i, to: dayStart) else { continue }
            let end = cal.date(byAdding: .minute, value: 48, to: start) ?? start.addingTimeInterval(2_800)

            if let stepType {
                let steps = (stepsTotal * weight).rounded()
                out.append(
                    HKQuantitySample(
                        type: stepType,
                        quantity: HKQuantity(unit: .count(), doubleValue: steps),
                        start: start,
                        end: end,
                        metadata: meta(persona)
                    )
                )
            }
            if let energyType {
                let kcal = energyTotal * weight
                out.append(
                    HKQuantitySample(
                        type: energyType,
                        quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                        start: start,
                        end: end,
                        metadata: meta(persona)
                    )
                )
            }
            if let distType {
                let km = distanceKm * weight
                out.append(
                    HKQuantitySample(
                        type: distType,
                        quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: km),
                        start: start,
                        end: end,
                        metadata: meta(persona)
                    )
                )
            }
        }
        return out
    }

    private static func nutritionSamples(
        persona: DemoPersonaSeeder.Persona,
        digest: FitnessDigest,
        now: Date
    ) -> [HKObject] {
        let cal = Calendar.current
        let meals: [(hour: Int, minute: Int, energyFrac: Double, proteinFrac: Double)] = [
            (12, 15, 0.30, 0.28),
            (15, 30, 0.38, 0.40),
            (19, 10, 0.32, 0.32),
        ]
        let energy = digest.dietaryEnergyKcalToday ?? (persona == .male ? 1_820 : 1_420)
        let protein = digest.dietaryProteinGramsToday ?? (persona == .male ? 138 : 102)
        let fiber = digest.dietaryFiberGramsToday ?? (persona == .male ? 28 : 26)
        let iron = digest.dietaryIronMgToday ?? (persona == .male ? 14 : 16)
        let potassium = digest.dietaryPotassiumMgToday ?? (persona == .male ? 3_400 : 3_100)

        var out: [HKObject] = []
        for meal in meals {
            guard let when = cal.date(bySettingHour: meal.hour, minute: meal.minute, second: 0, of: now) else {
                continue
            }
            // Don't write future meal slots.
            guard when <= now.addingTimeInterval(60) else { continue }
            out.append(contentsOf: quantityMeal(
                persona: persona,
                at: when,
                energy: energy * meal.energyFrac,
                protein: protein * meal.proteinFrac,
                fiber: fiber / Double(meals.count),
                iron: iron / Double(meals.count),
                potassium: potassium / Double(meals.count)
            ))
        }
        return out
    }

    private static func quantityMeal(
        persona: DemoPersonaSeeder.Persona,
        at date: Date,
        energy: Double,
        protein: Double,
        fiber: Double,
        iron: Double,
        potassium: Double
    ) -> [HKObject] {
        var out: [HKObject] = []
        func add(_ id: HKQuantityTypeIdentifier, unit: HKUnit, value: Double) {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return }
            out.append(
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: unit, doubleValue: value),
                    start: date,
                    end: date,
                    metadata: meta(persona)
                )
            )
        }
        add(.dietaryEnergyConsumed, unit: .kilocalorie(), value: energy)
        add(.dietaryProtein, unit: .gram(), value: protein)
        add(.dietaryFiber, unit: .gram(), value: fiber)
        add(.dietaryIron, unit: .gramUnit(with: .milli), value: iron)
        add(.dietaryPotassium, unit: .gramUnit(with: .milli), value: potassium)
        return out
    }

    private static func vitalsSamples(
        persona: DemoPersonaSeeder.Persona,
        digest: FitnessDigest,
        now: Date
    ) -> [HKObject] {
        let cal = Calendar.current
        var out: [HKObject] = []
        let rhr = digest.restingHeartRateBpm ?? (persona == .male ? 58 : 62)
        let hrv = digest.hrvSDNNMs ?? (persona == .male ? 48 : 52)
        let spo2 = digest.oxygenSaturationPercent ?? 97

        if let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
           let when = cal.date(bySettingHour: 6, minute: 40, second: 0, of: now)
        {
            out.append(
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: rhr),
                    start: when,
                    end: when,
                    metadata: meta(persona)
                )
            )
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
           let when = cal.date(bySettingHour: 6, minute: 42, second: 0, of: now)
        {
            out.append(
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: hrv),
                    start: when,
                    end: when,
                    metadata: meta(persona)
                )
            )
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation),
           let when = cal.date(bySettingHour: 7, minute: 0, second: 0, of: now)
        {
            out.append(
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: .percent(), doubleValue: spo2 / 100.0),
                    start: when,
                    end: when,
                    metadata: meta(persona)
                )
            )
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            let latest = digest.latestHeartRateBpm ?? (persona == .male ? 72 : 76)
            // A few daytime HR pings.
            for (h, m, bpm) in [(9, 20, latest - 4), (12, 40, latest + 8), (15, 10, latest)] {
                guard let when = cal.date(bySettingHour: h, minute: m, second: 0, of: now),
                      when <= now
                else { continue }
                out.append(
                    HKQuantitySample(
                        type: type,
                        quantity: HKQuantity(
                            unit: .count().unitDivided(by: .minute()),
                            doubleValue: Double(bpm)
                        ),
                        start: when,
                        end: when,
                        metadata: meta(persona)
                    )
                )
            }
        }
        return out
    }

    private static func sleepSamples(
        persona: DemoPersonaSeeder.Persona,
        digest: FitnessDigest,
        now: Date
    ) -> [HKObject] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }
        let cal = Calendar.current
        let hours = digest.sleepHoursLastNight ?? 7.2
        guard let wake = cal.date(bySettingHour: 6, minute: 50, second: 0, of: now),
              let bed = cal.date(byAdding: .minute, value: -Int(hours * 60), to: wake)
        else { return [] }

        // Core block + short deep/REM slices (writable category values).
        var out: [HKObject] = []
        let stages: [(HKCategoryValueSleepAnalysis, TimeInterval)] = [
            (.asleepCore, hours * 0.55 * 3600),
            (.asleepDeep, hours * 0.25 * 3600),
            (.asleepREM, hours * 0.20 * 3600),
        ]
        var cursor = bed
        for (value, duration) in stages {
            let end = cursor.addingTimeInterval(duration)
            out.append(
                HKCategorySample(
                    type: sleepType,
                    value: value.rawValue,
                    start: cursor,
                    end: end,
                    metadata: meta(persona)
                )
            )
            cursor = end
        }
        return out
    }

    private static func makeWorkout(
        persona: DemoPersonaSeeder.Persona,
        now: Date
    ) -> HKWorkout? {
        let cal = Calendar.current
        // Yesterday evening session so "recent workouts" looks real.
        guard let day = cal.date(byAdding: .day, value: -1, to: now),
              let start = cal.date(bySettingHour: 18, minute: 30, second: 0, of: day)
        else { return nil }
        let duration: TimeInterval = persona == .male ? 55 * 60 : 40 * 60
        let end = start.addingTimeInterval(duration)
        let kcal = persona == .male ? 420.0 : 310.0
        let activity: HKWorkoutActivityType =
            persona == .male ? .traditionalStrengthTraining : .running

        // Deprecated HKWorkout convenience init is fine for DEBUG Simulator fixtures.
        return HKWorkout(
            activityType: activity,
            start: start,
            end: end,
            duration: duration,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
            totalDistance: persona == .female
                ? HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: 5.2)
                : nil,
            metadata: meta(persona)
        )
    }

    // MARK: - Persistence

    private static func save(_ objects: [HKObject]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(objects) { success, error in
                if let error {
                    continuation.resume(throwing: HealthKitWriterError.saveFailed(error.localizedDescription))
                } else if !success {
                    continuation.resume(throwing: HealthKitWriterError.saveFailed("HealthKit demo seed save returned false."))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func deletePriorDemoSamples(persona: DemoPersonaSeeder.Persona) async throws {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: metadataKey,
            allowedValues: [persona.rawValue]
        )
        // Delete per sample type we own.
        for type in shareTypes {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.deleteObjects(of: type, predicate: predicate) { _, _, error in
                    // No-data / nothing-to-delete is fine.
                    if let error, !isBenignDeleteError(error) {
                        continuation.resume(throwing: HealthKitWriterError.saveFailed(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private static func isBenignDeleteError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == HKErrorDomain {
            return ns.code == HKError.errorNoData.rawValue
                || ns.code == HKError.errorAuthorizationNotDetermined.rawValue
                || ns.code == HKError.errorAuthorizationDenied.rawValue
        }
        return false
    }

    private static func meta(_ persona: DemoPersonaSeeder.Persona) -> [String: Any] {
        [
            metadataKey: persona.rawValue,
            HKMetadataKeyWasUserEntered: true,
        ]
    }

    private static func bucketWeight(i: Int, count: Int) -> Double {
        // Emphasize morning + lunch movement.
        let raw: [Double] = (0..<count).map { idx in
            switch idx {
            case 0: return 1.4
            case 1: return 1.1
            case 2: return 0.9
            case 3: return 1.3
            default: return 0.85
            }
        }
        let sum = raw.reduce(0, +)
        return raw[i] / sum
    }

    private static func nearestWeight(to date: Date, in weights: [HealthMetricSample]) -> Double? {
        weights.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })?.value
    }
}
#endif
