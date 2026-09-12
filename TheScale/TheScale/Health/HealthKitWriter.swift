import Foundation
import HealthKit

@MainActor
protocol HealthWriting: AnyObject {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorizationIfNeeded() async throws
    /// Recent body-mass samples from Apple Health (most recent first).
    func fetchRecentWeights(limit: Int) async throws -> [HealthWeightSample]
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

/// Reads recent weight history and writes confirmed scale readings to HealthKit.
///
/// Authorized:
/// - Read: bodyMass (trend baseline)
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

    private func metadata(for draft: EditableMeasurementDraft) -> [String: Any] {
        var meta: [String: Any] = [
            HKMetadataKeyWasUserEntered: false,
            "SourceDevice": "Xiaomi Mi Body Composition Scale 2 (XMTZC05HM)",
            "App": "The Scale"
        ]
        if let ohms = draft.impedanceOhms {
            meta["ImpedanceOhms"] = ohms
        }
        return meta
    }
}
