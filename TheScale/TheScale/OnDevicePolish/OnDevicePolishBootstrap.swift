import Foundation
import FoundationModels
import ScaleOnDevicePolish

/// Host bridge: Apple Intelligence capable phones never get the sidecar.
@MainActor
enum OnDevicePolishBootstrap {
    /// True when hardware can run Apple Intelligence (15 Pro / 16+), even if disabled.
    static var appleIntelligenceDeviceCapable: Bool {
        guard #available(iOS 26.0, *) else { return false }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return true
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return false
            case .appleIntelligenceNotEnabled, .modelNotReady:
                return true
            @unknown default:
                // Unknown: treat as capable so we do not clutter with a second model.
                return true
            }
        }
    }

    static func configureAndInstallIfNeeded() async {
        OnDevicePolishInstaller.shared.configure(
            appleIntelligenceDeviceCapable: appleIntelligenceDeviceCapable
        )
        await OnDevicePolishInstaller.shared.ensureInstalledIfEligible()
    }

    static var combinedOnDeviceLabel: String {
        if FoundationModelAvailability.isAvailable {
            return FoundationModelAvailability.shortLabel
        }
        let snap = OnDevicePolishInstaller.shared.snapshot
        switch snap.phase {
        case .ready:
            return snap.shortLabel
        case .downloading, .installing, .needsInstall:
            return snap.shortLabel
        default:
            return FoundationModelAvailability.shortLabel
        }
    }

    static var combinedStatusSummary: String {
        if FoundationModelAvailability.isAvailable {
            return FoundationModelAvailability.statusSummary
        }
        return OnDevicePolishInstaller.shared.snapshot.statusSummary
            + " "
            + FoundationModelAvailability.statusSummary
    }
}
