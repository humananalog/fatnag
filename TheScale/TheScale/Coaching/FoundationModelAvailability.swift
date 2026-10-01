import Foundation
import FoundationModels

/// On-device Apple Intelligence availability for FATNAG.
/// Never throws into UI; callers treat unavailable as algorithmic / Keel / polish fallback.
enum FoundationModelAvailability {
    enum Status: Equatable, Sendable {
        case available
        case unavailable(reason: String)
    }

    /// Process-lifetime trip after a host / prompt-template failure so we stop spamming ModelManager.
    private static let box = RuntimeGateBox()

    /// Snapshot of `SystemLanguageModel.default` availability, plus simulator / runtime gates.
    static var status: Status {
        if let disabled = runtimeDisabledReason {
            return .unavailable(reason: disabled)
        }
        guard #available(iOS 26.0, *) else {
            return .unavailable(reason: "Apple Intelligence needs iOS 26. Light Keel polish stays within your plan; chat still uses weekly credits.")
        }
        #if targetEnvironment(simulator)
        // Simulator often reports `.available` then fails every request with
        // `promptTemplateNotFound` (safety / instruct templates missing). Skip FM on sim.
        return .unavailable(reason: "Simulator skips Apple Intelligence. Algorithmic copy and Keel still work.")
        #else
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
        #endif
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

    private static var runtimeDisabledReason: String? {
        box.lock.lock()
        defer { box.lock.unlock() }
        return box.reason
    }

    /// Call after a LanguageModelSession / ModelManager host failure so later calls skip FM.
    static func noteRuntimeFailure(_ error: Error) {
        let text = String(describing: error)
        let lower = text.lowercased()
        let looksLikeHostGap =
            lower.contains("prompttemplatenotfound")
            || lower.contains("hostfailed")
            || lower.contains("modelmanagererror")
            || lower.contains("inferencefailed")
            || lower.contains("sensitivecontentanalysis")
        guard looksLikeHostGap else { return }
        box.lock.lock()
        defer { box.lock.unlock() }
        if box.reason == nil {
            box.reason =
                "On-device model host failed (prompt template missing). Using algorithmic copy until relaunch."
        }
    }

    /// Test hook.
    static func resetRuntimeFailureForTests() {
        box.lock.lock()
        defer { box.lock.unlock() }
        box.reason = nil
    }
}

private final class RuntimeGateBox: @unchecked Sendable {
    let lock = NSLock()
    var reason: String?
}
