import Foundation

/// On-device single-point weight correction.
///
/// Formula: `correctedKg = rawKg * scaleFactor + offsetKg`
///
/// Capture modes (single known mass):
/// - **offset**: `offset = reference - raw`, `scaleFactor = 1` (best when the error is a nearly constant bias)
/// - **factor**: `scaleFactor = reference / raw`, `offset = 0` (best when the error scales with mass)
///
/// One point cannot uniquely determine both; pick one mode. Honest UI states this limit.
struct ScaleCalibration: Equatable, Codable, Sendable {
    enum CaptureMode: String, Codable, CaseIterable, Identifiable, Sendable {
        case offset
        case factor

        var id: String { rawValue }

        var title: String {
            switch self {
            case .offset: return "Offset (kg)"
            case .factor: return "Scale factor"
            }
        }
    }

    /// Known mass the user places on the scale (editable; default 5 kg).
    var referenceMassKg: Double
    /// Multiplier applied to raw BLE kg. Identity = 1.
    var scaleFactor: Double
    /// Additive kg after the factor. Identity = 0.
    var offsetKg: Double
    /// Preferred capture mode for the next capture.
    var captureMode: CaptureMode
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
        captureMode: .offset,
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

    /// Capture using the current `captureMode`.
    @discardableResult
    mutating func capture(rawKg: Double, at date: Date = Date()) -> Bool {
        switch captureMode {
        case .offset:
            return captureAsOffset(rawKg: rawKg, at: date)
        case .factor:
            return captureAsFactor(rawKg: rawKg, at: date)
        }
    }

    /// Offset mode: `offset = reference - raw`, factor stays 1.
    @discardableResult
    mutating func captureAsOffset(rawKg: Double, at date: Date = Date()) -> Bool {
        guard rawKg > 0.05, referenceMassKg > 0.05 else { return false }
        scaleFactor = 1.0
        offsetKg = referenceMassKg - rawKg
        lastCalibrationRawKg = rawKg
        calibratedAt = date
        isActive = true
        captureMode = .offset
        return true
    }

    /// Factor mode: `factor = reference / raw`, offset cleared to 0.
    @discardableResult
    mutating func captureAsFactor(rawKg: Double, at date: Date = Date()) -> Bool {
        guard rawKg > 0.05, referenceMassKg > 0.05 else { return false }
        scaleFactor = referenceMassKg / rawKg
        offsetKg = 0
        lastCalibrationRawKg = rawKg
        calibratedAt = date
        isActive = true
        captureMode = .factor
        return true
    }

    mutating func reset() {
        scaleFactor = 1.0
        offsetKg = 0.0
        calibratedAt = nil
        lastCalibrationRawKg = nil
        isActive = false
        // Keep referenceMassKg + captureMode so the user does not retype every time.
    }
}

enum ScaleCalibrationStore {
    private static let key = "thescale.scaleCalibration.v2"
    /// Migrate from 1.2.0 key if present.
    private static let legacyKey = "thescale.scaleCalibration"

    static func load() -> ScaleCalibration {
        if let data = UserDefaults.standard.data(forKey: key),
           let value = try? JSONDecoder().decode(ScaleCalibration.self, from: data) {
            return value
        }
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let value = try? JSONDecoder().decode(ScaleCalibration.self, from: data) {
            // Legacy payloads lack `captureMode`; decode may fail. Try a soft migrate.
            save(value)
            return value
        }
        // Soft-migrate legacy JSON that may miss new fields by decoding a partial dict.
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var migrated = ScaleCalibration.default
            if let ref = obj["referenceMassKg"] as? Double { migrated.referenceMassKg = ref }
            if let f = obj["scaleFactor"] as? Double { migrated.scaleFactor = f }
            if let o = obj["offsetKg"] as? Double { migrated.offsetKg = o }
            if let active = obj["isActive"] as? Bool { migrated.isActive = active }
            if let raw = obj["lastCalibrationRawKg"] as? Double { migrated.lastCalibrationRawKg = raw }
            if let ts = obj["calibratedAt"] as? Double {
                migrated.calibratedAt = Date(timeIntervalSinceReferenceDate: ts)
            }
            save(migrated)
            return migrated
        }
        return .default
    }

    static func save(_ calibration: ScaleCalibration) {
        if let data = try? JSONEncoder().encode(calibration) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
