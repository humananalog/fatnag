import UIKit

/// Gates Settings debug / demo tools so they never appear for general users.
///
/// - **Release / App Store:** always hidden.
/// - **DEBUG Simulator:** allowed (ASC promo / demo captures).
/// - **DEBUG device:** only allowlisted phone names (your dev iPhone).
enum ScaleDeveloperGate {
    /// True when Settings may show Diagnose / demo personas / monthly hero preview.
    static var showsDevSettings: Bool {
        #if DEBUG
        #if targetEnvironment(simulator)
        return true
        #else
        return allowedPhysicalDeviceNames.contains(UIDevice.current.name)
        #endif
        #else
        return false
        #endif
    }

    /// Physical device names that may see Debug Settings. Curly + straight apostrophes.
    private static let allowedPhysicalDeviceNames: Set<String> = [
        "Alexandre's iPhone",
        "Alexandre’s iPhone",
        "Alex's iPhone",
        "Alex’s iPhone",
    ]
}
