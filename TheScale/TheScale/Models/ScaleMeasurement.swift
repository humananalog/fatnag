import Foundation

/// Decoded BLE frame from Mi Body Composition Scale 2 (XMTZC05HM / MIBFS).
struct ScaleMeasurement: Equatable, Identifiable, Sendable {
    let id: UUID
    /// Weight in kilograms.
    let weightKg: Double
    /// Bioelectrical impedance in ohms, when the scale finished the BIA sweep.
    let impedanceOhms: Int?
    /// Scale-reported timestamp from the advertisement frame.
    let scaleDate: Date?
    /// Whether the frame included a valid impedance reading.
    let hasImpedance: Bool
    /// True when the scale set the impedance flag but ohms were not yet valid (BIA still running).
    let biaPending: Bool
    /// Unit the scale was configured to display (weight is always stored as kg).
    let displayUnit: ScaleWeightUnit
    let receivedAt: Date
    /// False for live settling frames shown while the scale is still locking weight.
    let isStabilized: Bool

    init(
        id: UUID = UUID(),
        weightKg: Double,
        impedanceOhms: Int?,
        scaleDate: Date?,
        hasImpedance: Bool,
        biaPending: Bool = false,
        displayUnit: ScaleWeightUnit,
        receivedAt: Date = Date(),
        isStabilized: Bool = true
    ) {
        self.id = id
        self.weightKg = weightKg
        self.impedanceOhms = impedanceOhms
        self.scaleDate = scaleDate
        self.hasImpedance = hasImpedance
        self.biaPending = biaPending
        self.displayUnit = displayUnit
        self.receivedAt = receivedAt
        self.isStabilized = isStabilized
    }
}

enum ScaleWeightUnit: String, Sendable {
    case kilogram
    case pound
    case catty
}

/// User profile needed to estimate body composition from impedance.
struct UserBodyProfile: Equatable, Codable, Sendable {
    enum Sex: String, Codable, CaseIterable, Identifiable, Sendable {
        case female
        case male

        var id: String { rawValue }

        var title: String {
            switch self {
            case .female: return "Female"
            case .male: return "Male"
            }
        }
    }

    var heightCm: Double
    var ageYears: Double
    var sex: Sex
    /// Goal weight (kg). Used as the weight chart axis floor + ideal reference line.
    var idealWeightKg: Double
    /// Optional goal body fat %. When set, fat chart uses it as floor / reference.
    var idealBodyFatPercent: Double?

    static let `default` = UserBodyProfile(
        heightCm: 170,
        ageYears: 30,
        sex: .male,
        idealWeightKg: suggestedIdealWeightKg(heightCm: 170),
        idealBodyFatPercent: nil
    )

    /// BMI ~22 suggestion used when seeding a new profile or migrating old saves.
    static func suggestedIdealWeightKg(heightCm: Double) -> Double {
        let meters = max(heightCm, 100) / 100.0
        return (22.0 * meters * meters).rounded(toPlaces: 1)
    }

    init(
        heightCm: Double,
        ageYears: Double,
        sex: Sex,
        idealWeightKg: Double? = nil,
        idealBodyFatPercent: Double? = nil
    ) {
        self.heightCm = heightCm
        self.ageYears = ageYears
        self.sex = sex
        self.idealWeightKg = idealWeightKg ?? Self.suggestedIdealWeightKg(heightCm: heightCm)
        self.idealBodyFatPercent = idealBodyFatPercent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heightCm = try c.decode(Double.self, forKey: .heightCm)
        ageYears = try c.decode(Double.self, forKey: .ageYears)
        sex = try c.decode(Sex.self, forKey: .sex)
        idealWeightKg = try c.decodeIfPresent(Double.self, forKey: .idealWeightKg)
            ?? Self.suggestedIdealWeightKg(heightCm: heightCm)
        idealBodyFatPercent = try c.decodeIfPresent(Double.self, forKey: .idealBodyFatPercent)
    }

    private enum CodingKeys: String, CodingKey {
        case heightCm, ageYears, sex, idealWeightKg, idealBodyFatPercent
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}

/// Body composition derived on-device from weight + impedance + profile.
struct BodyCompositionResult: Equatable, Sendable {
    let bmi: Double
    let bodyFatPercent: Double
    let waterPercent: Double
    let boneMassKg: Double
    let muscleMassKg: Double
    let leanBodyMassKg: Double
    let visceralFat: Double
}
