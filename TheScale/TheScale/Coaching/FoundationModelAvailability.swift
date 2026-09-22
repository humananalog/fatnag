import Foundation
import FoundationModels

/// On-device Apple Intelligence availability for The Scale.
/// Never throws into UI; callers treat unavailable as algorithmic / Keel fallback.
enum FoundationModelAvailability {
    enum Status: Equatable, Sendable {
        case available
        case unavailable(reason: String)
    }

    /// Snapshot of `SystemLanguageModel.default` availability.
    static var status: Status {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(reason: "This iPhone is not eligible for Apple Intelligence.")
            case .appleIntelligenceNotEnabled:
                return .unavailable(reason: "Apple Intelligence is off. Enable it in Settings → Apple Intelligence & Siri.")
            case .modelNotReady:
                return .unavailable(reason: "On-device model is still downloading or warming up.")
            @unknown default:
                return .unavailable(reason: "Apple Intelligence unavailable on this device.")
            }
        }
    }

    static var isAvailable: Bool {
        if case .available = status { return true }
        return false
    }

    /// Settings / Coach status line.
    static var statusSummary: String {
        switch status {
        case .available:
            return "Apple Intelligence: on-device model ready (notifications + private snippets)."
        case .unavailable(let reason):
            return "Apple Intelligence: \(reason) Algorithmic copy and Keel (when consented) still work."
        }
    }

    /// Short badge for Coach chrome.
    static var shortLabel: String {
        switch status {
        case .available:
            return "FM ready"
        case .unavailable:
            return "FM off"
        }
    }
}
