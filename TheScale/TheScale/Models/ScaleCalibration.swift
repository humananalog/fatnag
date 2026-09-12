import Foundation

/// On-device single-point weight correction.
///
/// Formula: `correctedKg = rawKg * scaleFactor + offsetKg`
///
/// One reference mass cannot uniquely determine both factor and offset.
/// Capture sets **scale factor** (`reference / raw`) and clears offset to 0.
/// Offset is available for manual fine-tuning only.
struct ScaleCalibration: Equatable, Codable, Sendable {
    /// Known mass the user places on the scale (editable; default 5 kg).
    var referenceMassKg: Double
    /// Multiplier applied to raw BLE kg. Identity = 1.
    var scaleFactor: Double
    /// Additive kg after the factor. Identity = 0.
    var offsetKg: Double
    /// When the last capture was stored.
    var calibratedAt: Date?
    /// Raw (uncorrected) kg captured during the last calibration weigh-in.
    var lastCalibrationRawKg: Double?
    /// When false, `apply` returns the raw value unchanged.
    var isActive: Bool

    static let `default` = ScaleCalibration(
        referenceMassKg: 5.0,
        scaleFactor: 1.0,
        offsetKg: 0.0,
        calibratedAt: nil,
        lastCalibrationRawKg: nil,
        isActive: false
    )

    var hasCorrection: Bool {
        isActive && (abs(scaleFactor - 1.0) > 0.000_01 || abs(offsetKg) > 0.000_01)
    }

    /// Human-readable summary for Settings.
    var summaryLine: String {
        guard hasCorrection else {
            return "No correction applied (identity)."
        }
        let factorPct = (scaleFactor - 1.0) * 100.0
        return String(
            format: "Active: ×%.5f (%+.2f%%) + %+.3f kg",
            scaleFactor,
            factorPct,
            offsetKg
        )
    }

    func apply(toRawKg rawKg: Double) -> Double {
        guard isActive else { return rawKg }
        return rawKg * scaleFactor + offsetKg
    }

    /// Single-point capture: factor = reference / raw, offset = 0.
    mutating func capture(rawKg: Double, at date: Date = Date()) -> Bool {
        guard rawKg > 0.05, referenceMassKg > 0.05 else { return false }
        scaleFactor = referenceMassKg / rawKg
        offsetKg = 0
        lastCalibrationRawKg = rawKg
        calibratedAt = date
        isActive = true
        return true
    }

    mutating func reset() {
        scaleFactor = 1.0
        offsetKg = 0.0
        calibratedAt = nil
        lastCalibrationRawKg = nil
        isActive = false
        // Keep referenceMassKg so the user does not retype 5 kg every time.
    }
}

enum ScaleCalibrationStore {
    private static let key = "thescale.scaleCalibration"

    static func load() -> ScaleCalibration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(ScaleCalibration.self, from: data)
        else {
            return .default
        }
        return value
    }

    static func save(_ calibration: ScaleCalibration) {
        if let data = try? JSONEncoder().encode(calibration) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
