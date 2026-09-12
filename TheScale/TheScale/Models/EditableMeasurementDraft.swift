import Foundation

/// Editable copy of a weigh-in. Only confirmed drafts are written to HealthKit.
struct EditableMeasurementDraft: Equatable, Sendable {
    var weightKg: Double
    var impedanceOhms: Int?
    var bodyFatPercent: Double?
    var waterPercent: Double?
    var muscleMassKg: Double?
    var boneMassKg: Double?
    var leanBodyMassKg: Double?
    var visceralFat: Double?
    var bmi: Double?
    /// When false, Health write skips fat % / lean even if values are present.
    var includeCompositionInHealth: Bool
    var scaleDate: Date?
    var receivedAt: Date
    var sourceHasImpedance: Bool

    /// Lean mass as percent of body weight (companion to body fat %).
    var leanPercent: Double? {
        if let leanBodyMassKg, weightKg > 0.05 {
            return (leanBodyMassKg / weightKg) * 100.0
        }
        if let bodyFatPercent {
            return max(100.0 - bodyFatPercent, 0)
        }
        return nil
    }

    static func from(
        measurement: ScaleMeasurement,
        composition: BodyCompositionResult?,
        profile: UserBodyProfile
    ) -> EditableMeasurementDraft {
        let bmi = composition?.bmi
            ?? BodyCompositionCalculator.bodyMassIndex(
                weightKg: measurement.weightKg,
                heightCm: profile.heightCm
            )
        return EditableMeasurementDraft(
            weightKg: measurement.weightKg,
            impedanceOhms: measurement.impedanceOhms,
            bodyFatPercent: composition?.bodyFatPercent,
            waterPercent: composition?.waterPercent,
            muscleMassKg: composition?.muscleMassKg,
            boneMassKg: composition?.boneMassKg,
            leanBodyMassKg: composition?.leanBodyMassKg,
            visceralFat: composition?.visceralFat,
            bmi: bmi,
            includeCompositionInHealth: measurement.hasImpedance && composition != nil,
            scaleDate: measurement.scaleDate,
            receivedAt: measurement.receivedAt,
            sourceHasImpedance: measurement.hasImpedance
        )
    }

    /// Rebuild composition math from edited weight + ohms + profile.
    mutating func recalculate(using profile: UserBodyProfile) {
        bmi = BodyCompositionCalculator.bodyMassIndex(weightKg: weightKg, heightCm: profile.heightCm)
        guard let ohms = impedanceOhms,
              let result = BodyCompositionCalculator.calculate(
                  weightKg: weightKg,
                  impedanceOhms: ohms,
                  profile: profile
              )
        else {
            bodyFatPercent = nil
            waterPercent = nil
            muscleMassKg = nil
            boneMassKg = nil
            leanBodyMassKg = nil
            visceralFat = nil
            includeCompositionInHealth = false
            return
        }
        bodyFatPercent = result.bodyFatPercent
        waterPercent = result.waterPercent
        muscleMassKg = result.muscleMassKg
        boneMassKg = result.boneMassKg
        leanBodyMassKg = result.leanBodyMassKg
        visceralFat = result.visceralFat
        bmi = result.bmi
        includeCompositionInHealth = true
        sourceHasImpedance = true
    }

    func asMeasurement() -> ScaleMeasurement {
        ScaleMeasurement(
            weightKg: weightKg,
            impedanceOhms: impedanceOhms,
            scaleDate: scaleDate ?? receivedAt,
            hasImpedance: impedanceOhms != nil,
            biaPending: false,
            displayUnit: .kilogram,
            receivedAt: receivedAt,
            isStabilized: true
        )
    }

    func asComposition() -> BodyCompositionResult? {
        guard includeCompositionInHealth,
              let bodyFatPercent,
              let waterPercent,
              let muscleMassKg,
              let boneMassKg,
              let leanBodyMassKg,
              let visceralFat,
              let bmi
        else {
            return nil
        }
        return BodyCompositionResult(
            bmi: bmi,
            bodyFatPercent: bodyFatPercent,
            waterPercent: waterPercent,
            boneMassKg: boneMassKg,
            muscleMassKg: muscleMassKg,
            leanBodyMassKg: leanBodyMassKg,
            visceralFat: visceralFat
        )
    }
}
