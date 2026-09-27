import Foundation

public enum OnDevicePolishPhase: Equatable, Sendable {
    case notApplicable(reason: String)
    case needsInstall
    case downloading(progress: Double)
    case installing
    case ready
    case failed(message: String)
}

public struct OnDevicePolishSnapshot: Equatable, Sendable {
    public var phase: OnDevicePolishPhase
    public var modelID: String
    public var deviceModel: String
    public var localBytes: Int64
    public var expectedBytes: Int64

    public init(
        phase: OnDevicePolishPhase,
        modelID: String = OnDevicePolishCatalog.modelID,
        deviceModel: String = OnDevicePolishEligibility.deviceModelIdentifier,
        localBytes: Int64 = 0,
        expectedBytes: Int64 = OnDevicePolishCatalog.expectedByteCount
    ) {
        self.phase = phase
        self.modelID = modelID
        self.deviceModel = deviceModel
        self.localBytes = localBytes
        self.expectedBytes = expectedBytes
    }

    public var statusSummary: String {
        switch phase {
        case .notApplicable(let reason):
            return "On-device polish: \(reason)"
        case .needsInstall:
            return "On-device polish: will download \(OnDevicePolishCatalog.displayName) (~470 MB, Wi-Fi preferred)."
        case .downloading(let progress):
            let pct = Int((progress * 100).rounded())
            return "On-device polish: downloading \(pct)%."
        case .installing:
            return "On-device polish: preparing Metal model."
        case .ready:
            return "On-device polish: \(OnDevicePolishCatalog.displayName) ready on this iPhone (\(deviceModel))."
        case .failed(let message):
            return "On-device polish: \(message) Algorithmic copy still works."
        }
    }

    public var shortLabel: String {
        switch phase {
        case .ready: return "Polish ready"
        case .downloading: return "Polish…"
        case .needsInstall, .installing: return "Polish setup"
        case .failed: return "Polish off"
        case .notApplicable: return "Polish n/a"
        }
    }
}
