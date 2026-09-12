import Foundation
import HealthKit

@MainActor
protocol HealthWriting: AnyObject {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorizationIfNeeded() async throws
    func write(
        measurement: ScaleMeasurement,
        composition: BodyCompositionResult?,
        profile: UserBodyProfile
    ) async throws
}

enum HealthKitWriterError: LocalizedError {
    case unavailable
    case missingType(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Health is not available on this device."
        case .missingType(let name):
            return "Missing HealthKit type: \(name)."
        case .saveFailed(let message):
            return message
        }
    }
}

/// Writes only the quantity types HealthKit supports for scale readings.
///
/// Authorized / written:
/// - bodyMass (kg)
/// - bodyMassIndex
/// - bodyFatPercentage
/// - leanBodyMass (kg)
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

    func requestAuthorizationIfNeeded() async throws {
        guard isHealthDataAvailable else { throw HealthKitWriterError.unavailable }
        if didAuthorize { return }
        try await store.requestAuthorization(toShare: shareTypes, read: [])
        didAuthorize = true
    }

    func write(
        measurement: ScaleMeasurement,
        composition: BodyCompositionResult?,
        profile: UserBodyProfile
    ) async throws {
        guard isHealthDataAvailable else { throw HealthKitWriterError.unavailable }

        let date = measurement.scaleDate ?? measurement.receivedAt
        var samples: [HKQuantitySample] = []

        guard let massType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitWriterError.missingType("bodyMass")
        }
        samples.append(
            HKQuantitySample(
                type: massType,
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: measurement.weightKg),
                start: date,
                end: date,
                metadata: metadata(for: measurement)
            )
        )

        // Always write BMI from profile height. Never invent body fat / lean without ohms.
        let bmiValue: Double
        if let composition {
            bmiValue = composition.bmi
        } else {
            bmiValue = BodyCompositionCalculator.bodyMassIndex(
                weightKg: measurement.weightKg,
                heightCm: profile.heightCm
            )
        }

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

        if measurement.hasImpedance, let composition {
            if let fatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
                samples.append(
                    HKQuantitySample(
                        type: fatType,
                        quantity: HKQuantity(
                            unit: .percent(),
                            doubleValue: composition.bodyFatPercent / 100.0
                        ),
                        start: date,
                        end: date
                    )
                )
            }
            if let leanType = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) {
                samples.append(
                    HKQuantitySample(
                        type: leanType,
                        quantity: HKQuantity(
                            unit: .gramUnit(with: .kilo),
                            doubleValue: composition.leanBodyMassKg
                        ),
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

    private func metadata(for measurement: ScaleMeasurement) -> [String: Any] {
        var meta: [String: Any] = [
            HKMetadataKeyWasUserEntered: false,
            "SourceDevice": "Xiaomi Mi Body Composition Scale 2 (XMTZC05HM)",
            "App": "The Scale"
        ]
        if let ohms = measurement.impedanceOhms {
            meta["ImpedanceOhms"] = ohms
        }
        return meta
    }
}
