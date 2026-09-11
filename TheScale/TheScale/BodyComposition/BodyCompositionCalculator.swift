import Foundation

/// Estimates body composition from weight + 50 kHz foot-to-foot impedance.
///
/// Formulas are ported from reverse-engineered Xiaomi / Holtek `libBodyfat`
/// math used by:
/// - lolouk44/xiaomi_mi_scale (`Xiaomi_Scale_Body_Metrics.py`)
/// - openScale `MiScaleLib` / prototux MIBCS reverse-engineering
/// - ble-scale-sync `MiScaleCalc`
///
/// These are **estimates**, not medical measurements. Values can differ from
/// Zepp/Zapp Lite by a few points. Bone / muscle / water are shown in-app;
/// HealthKit only accepts a subset of quantity types (see `HealthKitWriter`).
enum BodyCompositionCalculator {
    static func calculate(
        weightKg: Double,
        impedanceOhms: Int,
        profile: UserBodyProfile
    ) -> BodyCompositionResult? {
        guard weightKg >= 10, weightKg <= 200 else { return nil }
        guard impedanceOhms > 0, impedanceOhms < 3000 else { return nil }
        guard profile.heightCm > 90, profile.heightCm <= 220 else { return nil }
        guard profile.ageYears > 0, profile.ageYears <= 99 else { return nil }

        let sex = profile.sex
        let height = profile.heightCm
        let age = profile.ageYears
        let weight = weightKg
        let impedance = Double(impedanceOhms)

        let lbmCoeff = leanBodyMassCoefficient(
            heightCm: height,
            weightKg: weight,
            ageYears: age,
            impedanceOhms: impedance
        )

        let bodyFat = fatPercentage(
            sex: sex,
            age: age,
            heightCm: height,
            weightKg: weight,
            lbmCoefficient: lbmCoeff
        )

        let water = waterPercentage(bodyFatPercent: bodyFat)
        let bone = boneMassKg(sex: sex, lbmCoefficient: lbmCoeff)
        let muscle = muscleMassKg(sex: sex, weightKg: weight, bodyFatPercent: bodyFat, boneMassKg: bone)
        let bmi = bodyMassIndex(weightKg: weight, heightCm: height)
        let visceral = visceralFat(sex: sex, weightKg: weight, heightCm: height, ageYears: age)
        let lean = max(weight - (weight * bodyFat / 100.0), 0)

        return BodyCompositionResult(
            bmi: bmi,
            bodyFatPercent: bodyFat,
            waterPercent: water,
            boneMassKg: bone,
            muscleMassKg: muscle,
            leanBodyMassKg: lean,
            visceralFat: visceral
        )
    }

    // MARK: - Core formulas

    static func leanBodyMassCoefficient(
        heightCm: Double,
        weightKg: Double,
        ageYears: Double,
        impedanceOhms: Double
    ) -> Double {
        var lbm = (heightCm * 9.058 / 100.0) * (heightCm / 100.0)
        lbm += weightKg * 0.32 + 12.226
        lbm -= impedanceOhms * 0.0068
        lbm -= ageYears * 0.0542
        return lbm
    }

    static func fatPercentage(
        sex: UserBodyProfile.Sex,
        age: Double,
        heightCm: Double,
        weightKg: Double,
        lbmCoefficient: Double
    ) -> Double {
        let constant: Double
        switch sex {
        case .female where age <= 49: constant = 9.25
        case .female: constant = 7.25
        case .male: constant = 0.8
        }

        var coefficient = 1.0
        if sex == .male && weightKg < 61 {
            coefficient = 0.98
        } else if sex == .female && weightKg > 60 {
            coefficient = 0.96
            if heightCm > 160 { coefficient *= 1.03 }
        } else if sex == .female && weightKg < 50 {
            coefficient = 1.02
            if heightCm > 160 { coefficient *= 1.03 }
        }

        var fat = (1.0 - (((lbmCoefficient - constant) * coefficient) / weightKg)) * 100.0
        if fat > 63 { fat = 75 }
        return clamp(fat, min: 5, max: 75)
    }

    static func waterPercentage(bodyFatPercent: Double) -> Double {
        var water = (100.0 - bodyFatPercent) * 0.7
        let coefficient = water <= 50 ? 1.02 : 0.98
        water *= coefficient
        if water >= 65 { water = 75 }
        return clamp(water, min: 35, max: 75)
    }

    static func boneMassKg(sex: UserBodyProfile.Sex, lbmCoefficient: Double) -> Double {
        let base = sex == .female ? 0.245691014 : 0.18016894
        var bone = (base - (lbmCoefficient * 0.05158)) * -1.0
        bone += bone > 2.2 ? 0.1 : -0.1
        if sex == .female && bone > 5.1 { bone = 8 }
        if sex == .male && bone > 5.2 { bone = 8 }
        return clamp(bone, min: 0.5, max: 8)
    }

    static func muscleMassKg(
        sex: UserBodyProfile.Sex,
        weightKg: Double,
        bodyFatPercent: Double,
        boneMassKg: Double
    ) -> Double {
        var muscle = weightKg - ((bodyFatPercent * 0.01) * weightKg) - boneMassKg
        if sex == .female && muscle >= 84 { muscle = 120 }
        if sex == .male && muscle >= 93.5 { muscle = 120 }
        return clamp(muscle, min: 10, max: 120)
    }

    static func bodyMassIndex(weightKg: Double, heightCm: Double) -> Double {
        let meters = heightCm / 100.0
        return clamp(weightKg / (meters * meters), min: 10, max: 90)
    }

    static func visceralFat(
        sex: UserBodyProfile.Sex,
        weightKg: Double,
        heightCm: Double,
        ageYears: Double
    ) -> Double {
        let vf: Double
        if sex == .female {
            if weightKg > (13 - (heightCm * 0.5)) * -1 {
                let subsub = ((heightCm * 1.45) + (heightCm * 0.1158) * heightCm) - 120
                let sub = weightKg * 500 / subsub
                vf = (sub - 6) + (ageYears * 0.07)
            } else {
                let sub = 0.691 + (heightCm * -0.0024) + (heightCm * -0.0024)
                vf = (((heightCm * 0.027) - (sub * weightKg)) * -1) + (ageYears * 0.07) - ageYears
            }
        } else if heightCm < weightKg * 1.6 {
            let sub = ((heightCm * 0.4) - (heightCm * (heightCm * 0.0826))) * -1
            vf = ((weightKg * 305) / (sub + 48)) - 2.9 + (ageYears * 0.15)
        } else {
            let sub = 0.765 + heightCm * -0.0015
            vf = (((heightCm * 0.143) - (weightKg * sub)) * -1) + (ageYears * 0.15) - 5.0
        }
        return clamp(vf, min: 1, max: 50)
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}
