import Foundation

/// User-facing Coach persona. Internal transport still talks to the shared proxy;
/// the operator sees this name, never the underlying model brand.
enum CoachPersona {
    static let name = "Keel"

    /// Short live badge, e.g. "Keel · live".
    static func liveBadge(memoryCount: Int = 0, fastingNote: String? = nil) -> String {
        var base = memoryCount > 0 ? "\(name) · \(memoryCount) mem" : "\(name) · live"
        if let fastingNote, !fastingNote.isEmpty {
            base += " · \(fastingNote)"
        }
        return base
    }

    static var consentToggleTitle: String {
        "Allow \(name) coach requests"
    }

    static var onboardingLiveToggleTitle: String {
        String(
            format: AppLanguageStore.text("onboarding.confirm.keel_later", default: "Allow live %@ Coach later"),
            name
        )
    }

    static var thinkingSpinnerLine: String {
        "\(name) is thinking. Snake is snacking."
    }
}
