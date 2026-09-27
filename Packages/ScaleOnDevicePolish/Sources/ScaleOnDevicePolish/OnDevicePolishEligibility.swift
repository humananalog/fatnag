import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Whether this handset should carry the Metal polish sidecar.
public enum OnDevicePolishInstallPolicy: Equatable, Sendable {
    /// Apple Intelligence capable phone (15 Pro / 16+). Never install sidecar.
    case appleIntelligenceDevice
    /// Compatible phone without Apple Intelligence. Auto-install.
    case installSidecar
    /// Hardware cannot run the 0.5B Metal path safely.
    case unsupported(reason: String)
}

public enum OnDevicePolishEligibility: Sendable {
    /// Consumer gate.
    /// - `appleIntelligenceDeviceCapable`: true when the phone can run Apple Intelligence
    ///   (eligible hardware), even if the user has not enabled it yet. Those devices must
    ///   **not** download the sidecar (avoid clutter / double models).
    public static func policy(
        appleIntelligenceDeviceCapable: Bool,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> OnDevicePolishInstallPolicy {
        if appleIntelligenceDeviceCapable {
            return .appleIntelligenceDevice
        }
        #if targetEnvironment(simulator)
        return .unsupported(reason: "Simulator skips Metal polish install.")
        #else
        guard physicalMemoryBytes >= OnDevicePolishCatalog.minimumPhysicalMemoryBytes else {
            return .unsupported(reason: "This iPhone does not have enough memory for on-device polish.")
        }
        #if canImport(UIKit)
        // iPhone only product. iPad / Mac Catalyst stay on heuristics.
        if UIDevice.current.userInterfaceIdiom != .phone {
            return .unsupported(reason: "On-device polish ships for iPhone only.")
        }
        #endif
        return .installSidecar
        #endif
    }

    public static func shouldAutoInstall(appleIntelligenceDeviceCapable: Bool) -> Bool {
        if case .installSidecar = policy(appleIntelligenceDeviceCapable: appleIntelligenceDeviceCapable) {
            return true
        }
        return false
    }

    public static var deviceModelIdentifier: String {
        #if canImport(UIKit)
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
        #else
        return "unknown"
        #endif
    }
}
