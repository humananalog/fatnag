import Foundation

/// Light client-side cleanup when the model slips on punctuation / AI tells.
enum CoachCopySanitize {
    /// Shared medical disclaimer: onboarding once + Settings → Legal only. Never chat.
    static var medicalDisclaimer: String {
        AppLanguageStore.text(
            "onboarding.confirm.medical_body",
            default: "Coach is educational fitness coaching, not medical advice. It does not diagnose, treat, or replace a clinician. If something feels wrong, talk to a real doctor."
        )
    }

    static func clean(_ text: String) -> String {
        var out = text
        // Em dash / en dash → ASCII
        out = out.replacingOccurrences(of: "\u{2014}", with: " - ")
        out = out.replacingOccurrences(of: "\u{2013}", with: "-")
        out = out.replacingOccurrences(of: "\u{2015}", with: " - ")
        // Collapse spaces around rewritten hyphens
        while out.contains("  -  ") {
            out = out.replacingOccurrences(of: "  -  ", with: " - ")
        }
        out = stripTrailingDisclaimerBoilerplate(out)
        out = stripObviousAITells(out)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTrailingDisclaimerBoilerplate(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        while let last = lines.last {
            let trimmed = last.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.isEmpty {
                lines.removeLast()
                continue
            }
            let isDisclaimer =
                trimmed.contains("not medical advice")
                || trimmed.contains("not a substitute for professional medical")
                || trimmed.contains("consult a doctor")
                || trimmed.contains("consult your doctor")
                || trimmed.contains("see a clinician")
                || trimmed.contains("talk to a real clinician")
                || trimmed.hasPrefix("disclaimer:")
            if isDisclaimer {
                lines.removeLast()
                continue
            }
            break
        }
        return lines.joined(separator: "\n")
    }

    private static func stripObviousAITells(_ text: String) -> String {
        var out = text
        let patterns = [
            #"^As an AI[, ][^\n]*\n?"#,
            #"^I'm an AI[, ][^\n]*\n?"#,
            #"^I am an AI[, ][^\n]*\n?"#,
            #"^I'd be happy to[^\n]*\n?"#,
            #"^I would be happy to[^\n]*\n?"#,
            #"^Certainly[!., ]+"#,
            #"^Of course[!., ]+"#,
            #"^As a language model[, ][^\n]*\n?"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "")
            }
        }
        return out
    }
}
