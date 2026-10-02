import CoreBluetooth
import Foundation

/// Brand/model-agnostic BLE advertisement decoder.
///
/// Register new scales in `ScaleFrameDecoderRegistry.all`. The scanner tries each
/// decoder against ads. Mi Body Composition Scale 2 is the first (and currently only) entry.
protocol ScaleFrameDecoding: Sendable {
    /// Short Health / UI label when this decoder produced the frame.
    var sourceDeviceLabel: String { get }
    /// Fallback local name when the advertisement omits one.
    var fallbackAdvertisedName: String { get }

    /// Whether this peripheral name / service-data map looks like this scale family.
    func matches(advertisedName: String?, serviceData: [CBUUID: Data]?) -> Bool

    /// Decode one service-data blob for live UI (unstabilized frames allowed).
    func decodeLive(_ data: Data) -> Result<ScaleMeasurement, ScaleFrameDecodeError>
}

enum ScaleFrameDecodeError: Error, Equatable, Sendable {
    case wrongLength(Int)
    case notStabilized
    case weightRemoved
    case unsupportedUnit
    case unrecognized
}

enum ScaleFrameDecodeOutcome: Sendable {
    case measurement(ScaleMeasurement, sourceDeviceLabel: String)
    case weightRemoved
    case none
}

/// Ordered registry. First match wins for discovery + decode.
enum ScaleFrameDecoderRegistry {
    /// Primary: Xiaomi / Mi Body Composition Scale 2 (`0x181B`). Add other adapters behind it.
    static let all: [any ScaleFrameDecoding] = [
        MiScale2FrameDecoderAdapter()
    ]

    static func matching(
        advertisedName: String?,
        serviceData: [CBUUID: Data]?
    ) -> (any ScaleFrameDecoding)? {
        all.first { $0.matches(advertisedName: advertisedName, serviceData: serviceData) }
    }

    /// Try every decoder against every service-data value; first success wins.
    static func decodeLive(serviceData: [CBUUID: Data]) -> ScaleFrameDecodeOutcome {
        var sawRemoved = false
        for decoder in all {
            for (_, data) in serviceData {
                switch decoder.decodeLive(data) {
                case .success(let measurement):
                    let tagged = ScaleMeasurement(
                        id: measurement.id,
                        weightKg: measurement.weightKg,
                        impedanceOhms: measurement.impedanceOhms,
                        scaleDate: measurement.scaleDate,
                        hasImpedance: measurement.hasImpedance,
                        biaPending: measurement.biaPending,
                        displayUnit: measurement.displayUnit,
                        receivedAt: measurement.receivedAt,
                        isStabilized: measurement.isStabilized,
                        sourceDeviceLabel: decoder.sourceDeviceLabel
                    )
                    return .measurement(tagged, sourceDeviceLabel: decoder.sourceDeviceLabel)
                case .failure(.weightRemoved):
                    sawRemoved = true
                case .failure:
                    continue
                }
            }
        }
        return sawRemoved ? .weightRemoved : .none
    }
}

/// Adapter so the existing Mi Scale 2 parser plugs into the agnostic registry.
struct MiScale2FrameDecoderAdapter: ScaleFrameDecoding {
    var sourceDeviceLabel: String { "Bluetooth body scale" }
    var fallbackAdvertisedName: String { "Body scale" }

    func matches(advertisedName: String?, serviceData: [CBUUID: Data]?) -> Bool {
        if MiScale2FrameDecoder.matchesAdvertisedName(advertisedName) { return true }
        return serviceData?.keys.contains(where: {
            $0.uuidString.uppercased().hasSuffix(MiScale2FrameDecoder.bodyCompositionServiceUUID)
        }) == true
    }

    func decodeLive(_ data: Data) -> Result<ScaleMeasurement, ScaleFrameDecodeError> {
        switch MiScale2FrameDecoder.decodeLive(data) {
        case .success(let measurement):
            return .success(measurement)
        case .failure(.wrongLength(let n)):
            return .failure(.wrongLength(n))
        case .failure(.notStabilized):
            return .failure(.notStabilized)
        case .failure(.weightRemoved):
            return .failure(.weightRemoved)
        case .failure(.unsupportedUnit):
            return .failure(.unsupportedUnit)
        }
    }
}
