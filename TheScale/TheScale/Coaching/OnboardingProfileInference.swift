import Foundation

/// Structured draft Grok (or on-device heuristics) fill from freeform onboarding text.
struct OnboardingInferenceDraft: Equatable, Sendable {
    var diet: DietPreference?
    var location: String?
    var ethnicity: String?
    var preferredLanguage: String?
    var culturalVibe: String?
    var idealWeightKg: Double?
    var idealBodyFatPercent: Double?
    /// Structured IF window when freeform mentions 16-8 / fasting.
    var intermittentFasting: FastingWindow?
    var usedNetwork: Bool
    var sourceLabel: String

    static let empty = OnboardingInferenceDraft(
        diet: nil,
        location: nil,
        ethnicity: nil,
        preferredLanguage: nil,
        culturalVibe: nil,
        idealWeightKg: nil,
        idealBodyFatPercent: nil,
        intermittentFasting: nil,
        usedNetwork: false,
        sourceLabel: "none"
    )
}

/// Local keyword / phrase fill when Grok is offline or declined. Never invents height/age/sex.
enum OnboardingLocalInference {
    static func infer(from raw: String, name: String) -> OnboardingInferenceDraft {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return OnboardingInferenceDraft(
                diet: nil,
                location: nil,
                ethnicity: nil,
                preferredLanguage: preferredLanguageHint(from: text),
                culturalVibe: nil,
                idealWeightKg: nil,
                idealBodyFatPercent: nil,
                intermittentFasting: nil,
                usedNetwork: false,
                sourceLabel: "empty"
            )
        }
        let lower = text.lowercased()
        let fasting = FastingWindow.detect(memoryBlock: lower)
        return OnboardingInferenceDraft(
            diet: dietHint(from: lower, hasIF: fasting.isActive),
            location: locationHint(from: text),
            ethnicity: ethnicityHint(from: text),
            preferredLanguage: preferredLanguageHint(from: lower) ?? "English",
            culturalVibe: vibeHint(from: text, name: name),
            idealWeightKg: weightGoalHint(from: lower),
            idealBodyFatPercent: bodyFatHint(from: lower),
            intermittentFasting: fasting.isActive ? fasting : nil,
            usedNetwork: false,
            sourceLabel: "on-device"
        )
    }

    /// Prefer remote fields when present; keep local as floor.
    static func merge(local: OnboardingInferenceDraft, remote: OnboardingInferenceDraft) -> OnboardingInferenceDraft {
        OnboardingInferenceDraft(
            diet: remote.diet ?? local.diet,
            location: remote.location ?? local.location,
            ethnicity: remote.ethnicity ?? local.ethnicity,
            preferredLanguage: remote.preferredLanguage ?? local.preferredLanguage,
            culturalVibe: remote.culturalVibe ?? local.culturalVibe,
            idealWeightKg: remote.idealWeightKg ?? local.idealWeightKg,
            idealBodyFatPercent: remote.idealBodyFatPercent ?? local.idealBodyFatPercent,
            intermittentFasting: remote.intermittentFasting ?? local.intermittentFasting,
            usedNetwork: remote.usedNetwork || local.usedNetwork,
            sourceLabel: remote.sourceLabel == "none" || remote.sourceLabel == "empty"
                ? local.sourceLabel
                : (remote.sourceLabel.isEmpty ? local.sourceLabel : remote.sourceLabel)
        )
    }

    private static func dietHint(from lower: String, hasIF: Bool) -> DietPreference? {
        if lower.contains("vegan") { return .vegan }
        if lower.contains("vegetarian") || lower.contains("veggie") { return .vegetarian }
        if lower.contains("pescatarian") || lower.contains("pescetarian") || lower.contains("fish but no meat") {
            return .pescatarian
        }
        if lower.contains("omnivore") || lower.contains("eat everything") || lower.contains("no diet") {
            return .omnivore
        }
        // IF alone is not a diet. Keep omnivore unless they said flexible/keto.
        if lower.contains("keto") || lower.contains("flexible") {
            return .other
        }
        if hasIF { return .omnivore }
        return nil
    }

    private static func locationHint(from text: String) -> String? {
        // "in Manila", "based in Hong Kong", "from Singapore"
        let patterns = [
            #"(?i)\b(?:in|from|based in|live in|living in)\s+([A-Z][\w\s\-']{1,40})"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text) {
                let city = String(text[range])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
                if city.count >= 2, city.count <= 48 { return city }
            }
        }
        return nil
    }

    private static func ethnicityHint(from text: String) -> String? {
        let lower = text.lowercased()
        let keys = [
            "filipina", "filipino", "pinoy", "pinay",
            "chinese", "cantonese", "hong kong",
            "japanese", "korean", "indian", "thai",
            "vietnamese", "malay", "indonesian",
            "french", "british", "american", "australian",
            "latinx", "latino", "latina", "hispanic"
        ]
        for key in keys where lower.contains(key) {
            return key.capitalized
        }
        return nil
    }

    private static func preferredLanguageHint(from lower: String) -> String? {
        let map: [(String, String)] = [
            ("tagalog", "Tagalog"),
            ("filipino", "Filipino"),
            ("cantonese", "Cantonese"),
            ("mandarin", "Mandarin"),
            ("french", "French"),
            ("spanish", "Spanish"),
            ("japanese", "Japanese"),
            ("korean", "Korean"),
            ("bahasa", "Bahasa Indonesia"),
            ("english", "English")
        ]
        for (needle, label) in map where lower.contains(needle) {
            return label
        }
        return nil
    }

    private static func vibeHint(from text: String, name: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return nil }
        // Keep a short coach-facing summary, not a novel.
        let clipped = trimmed.count > 160 ? String(trimmed.prefix(157)) + "…" : trimmed
        if name.isEmpty { return clipped }
        return clipped
    }

    private static func weightGoalHint(from lower: String) -> Double? {
        // "goal 72kg", "down to 68 kg", "target 70", "aiming for 62 kg"
        let pattern = #"(?i)(?:goal|target|down to|hit|aiming(?:\s+for)?|aim(?:\s+for)?)\s*(\d{2,3}(?:\.\d)?)\s*kg?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: lower),
              let value = Double(lower[range]),
              value >= 35, value <= 250
        else { return nil }
        return value
    }

    private static func bodyFatHint(from lower: String) -> Double? {
        let pattern = #"(?i)(?:body\s*fat|bf)\s*(?:to|of|at)?\s*(\d{1,2}(?:\.\d)?)\s*%?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: lower),
              let value = Double(lower[range]),
              value >= 4, value <= 45
        else { return nil }
        return value
    }
}
