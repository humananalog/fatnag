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

    init(
        id: UUID = UUID(),
        weightKg: Double,
        impedanceOhms: Int?,
        scaleDate: Date?,
        hasImpedance: Bool,
        biaPending: Bool = false,
        displayUnit: ScaleWeightUnit,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.weightKg = weightKg
        self.impedanceOhms = impedanceOhms
        self.scaleDate = scaleDate
        self.hasImpedance = hasImpedance
        self.biaPending = biaPending
        self.displayUnit = displayUnit
        self.receivedAt = receivedAt
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

    static let `default` = UserBodyProfile(heightCm: 170, ageYears: 30, sex: .male)
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
