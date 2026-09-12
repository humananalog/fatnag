import Foundation

/// Parses the 13-byte Mi Body Composition Scale 2 advertisement / GATT live frame.
///
/// Frame layout (service data UUID `0x181B`, device name typically `MIBFS`):
/// ```
/// [0]     control0: bit0 = lbs; otherwise kg (catty via control1 bit6)
/// [1]     control1: bit1 = impedance present, bit5 = stabilized,
///                    bit6 = catty/jin, bit7 = weight removed
/// [2-3]   year (uint16 LE)
/// [4]     month
/// [5]     day
/// [6]     hour
/// [7]     minute
/// [8]     second
/// [9-10]  impedance ohms (uint16 LE), when bit1 set
/// [11-12] weight raw (uint16 LE): /200 → kg, /100 → lbs or catty
/// ```
///
/// Sources:
/// - ESPHome `xiaomi_miscale` (v2 / 0x181B path)
/// - Theengs Decoder XMTZC05HM / MIBFS
/// - openScale / ble-scale-sync Mi Scale 2 adapters
///
/// Sequence on a real weigh-in: the scale usually broadcasts a stabilized
/// **weight-only** frame first, then a second stabilized frame with the
/// impedance bit set once the foot-to-foot BIA sweep finishes (barefoot).
///
/// Limitations: the scale only *broadcasts* weight and impedance. Fat %, muscle,
/// bone, and water are **not** sent by the hardware; they are estimated locally
/// from reverse-engineered Xiaomi formulas (see `BodyCompositionCalculator`).
enum MiScale2FrameDecoder {
    static let bodyCompositionServiceUUID = "181B"
    static let knownAdvertisedNames = ["MIBFS", "MIBCS", "MI SCALE", "MI_SCALE"]

    enum DecodeError: Error, Equatable {
        case wrongLength(Int)
        case notStabilized
        case weightRemoved
        case unsupportedUnit
    }

    /// Decode a complete stabilized measurement, or return an error explaining why the frame was ignored.
    ///
    /// When the impedance flag is set but ohms are `0` or `≥ 3000` (BIA still running),
    /// returns a weight-only measurement with `biaPending == true` so the UI can keep waiting
    /// instead of dropping the frame entirely.
    static func decode(_ data: Data) -> Result<ScaleMeasurement, DecodeError> {
        guard data.count == 13 else {
            return .failure(.wrongLength(data.count))
        }

        let bytes = [UInt8](data)
        let control0 = bytes[0]
        let control1 = bytes[1]

        let isLbs = (control0 & 0x01) != 0
        let impedanceFlag = (control1 & 0x02) != 0
        let isStabilized = (control1 & 0x20) != 0
        let isCatty = (control1 & 0x40) != 0
        let weightRemoved = (control1 & 0x80) != 0

        guard isStabilized else { return .failure(.notStabilized) }
        guard !weightRemoved else { return .failure(.weightRemoved) }

        let weightRaw = UInt16(bytes[11]) | (UInt16(bytes[12]) << 8)
        let displayUnit: ScaleWeightUnit
        let weightKg: Double

        if isLbs {
            displayUnit = .pound
            weightKg = (Double(weightRaw) / 100.0) * 0.45359237
        } else if isCatty {
            displayUnit = .catty
            // 1 jin/catty = 0.5 kg; raw is already in 0.01 catty units → /100 * 0.5
            weightKg = (Double(weightRaw) / 100.0) * 0.5
        } else if control0 == 0x02 || (control0 & 0x01) == 0 {
            displayUnit = .kilogram
            weightKg = Double(weightRaw) / 200.0
        } else {
            return .failure(.unsupportedUnit)
        }

        var impedance: Int?
        var biaPending = false
        if impedanceFlag {
            let rawImp = Int(UInt16(bytes[9]) | (UInt16(bytes[10]) << 8))
            // ESPHome rejects 0 and ≥ 3000 as incomplete / invalid BIA sweeps.
            // Publish weight anyway and mark BIA pending so the session can wait.
            if rawImp == 0 || rawImp >= 3000 {
                biaPending = true
                impedance = nil
            } else {
                impedance = rawImp
            }
        }

        let year = Int(UInt16(bytes[2]) | (UInt16(bytes[3]) << 8))
        let month = Int(bytes[4])
        let day = Int(bytes[5])
        let hour = Int(bytes[6])
        let minute = Int(bytes[7])
        let second = Int(bytes[8])
        let scaleDate = makeDate(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )

        return .success(
            ScaleMeasurement(
                weightKg: weightKg,
                impedanceOhms: impedance,
                scaleDate: scaleDate,
                hasImpedance: impedance != nil,
                biaPending: biaPending,
                displayUnit: displayUnit
            )
        )
    }

    /// Convenience for tests / callers that prefer optionals.
    static func decodeMeasurement(_ data: Data) -> ScaleMeasurement? {
        if case .success(let measurement) = decode(data) {
            return measurement
        }
        return nil
    }

    /// True when a BLE local name looks like a Xiaomi body composition scale.
    static func matchesAdvertisedName(_ name: String?) -> Bool {
        guard let name else { return false }
        let upper = name.uppercased()
        return knownAdvertisedNames.contains { upper.hasPrefix($0) || upper == $0 }
    }

    private static func makeDate(
        year: Int, month: Int, day: Int,
        hour: Int, minute: Int, second: Int
    ) -> Date? {
        guard year >= 2000, year <= 2100,
              (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...59).contains(second)
        else {
            return nil
        }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone.current
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date
    }
}
