import Foundation
import FoundationModels

// MARK: - Structured outputs

@Generable(description: "Local notification title and body for The Scale coach")
struct NotificationCopyDraft: Equatable, Sendable {
    @Guide(description: "Notification title. Include the user's name. Max ~40 characters. No em dashes. No AI markers.")
    var title: String

    @Guide(description: "Notification body. Friendly badass dark humour. Call user by name when natural. Max ~110 characters. No em dashes. No medical disclaimer. No AI markers.")
    var body: String
}

@Generable(description: "Whether a local notification is worth firing right now")
struct PingJudgment: Equatable, Sendable {
    @Guide(description: "True only if the ping is necessary: bad trend, Watch not worn, or pre-sleep HR missing/elevated. False for noise.")
    var shouldNotify: Bool

    @Guide(description: "One short plain reason for the decision.")
    var reason: String
}

@Generable(description: "Compact on-device memory facts extracted from user chat")
struct MemoryExtractionDraft: Equatable, Sendable {
    @Guide(description: "Zero to three durable facts worth remembering (diet, training, lifestyle). Empty if nothing sticky.")
    var facts: [String]
}

// MARK: - Coach

/// On-device Foundation Models helpers. Privacy-first; never sends Health off-device.
/// Graceful no-op / algorithmic fallback when Apple Intelligence is off or ineligible.
enum FoundationModelCoach {
    private static let voiceInstructions = """
        You write for The Scale, a private fitness coach on the user's iPhone.
        Call the user by name when given. Friendly, badass, dark humour; sometimes vulgar; never corporate.
        Never use em dashes or en dashes. Use ASCII hyphen or a period.
        Never say you are an AI, language model, or Apple Intelligence.
        Never add medical disclaimers, diagnoses, or "consult a doctor" lines.
        Keep copy short enough for iOS banners.
        """

    // MARK: Notifications

    /// Refine algorithmic notification title/body. Returns fallbacks unchanged if FM unavailable.
    static func refineNotificationCopy(
        profileName: String,
        kind: String,
        fallbackTitle: String,
        fallbackBody: String,
        context: String
    ) async -> (title: String, body: String, usedFoundationModel: Bool) {
        guard FoundationModelAvailability.isAvailable else {
            return (fallbackTitle, fallbackBody, false)
        }
        let name = profileName.isEmpty ? "Hey" : profileName
        do {
            let session = LanguageModelSession(instructions: voiceInstructions)
            let prompt = """
                Draft a local notification for \(name).
                Kind: \(kind)
                Context: \(context)
                Fallback title: \(fallbackTitle)
                Fallback body: \(fallbackBody)
                Prefer a sharper rewrite of the fallback; keep the same facts.
                """
            var options = GenerationOptions()
            options.temperature = 0.7
            options.maximumResponseTokens = 120
            let response = try await session.respond(
                to: prompt,
                generating: NotificationCopyDraft.self,
                options: options
            )
            let draft = response.content
            let title = CoachCopySanitize.clean(draft.title)
            let body = CoachCopySanitize.clean(draft.body)
            let safeTitle = title.isEmpty ? fallbackTitle : clamp(title, max: 48)
            let safeBody = body.isEmpty ? fallbackBody : clamp(body, max: 140)
            return (safeTitle, safeBody, true)
        } catch {
            return (fallbackTitle, fallbackBody, false)
        }
    }

    /// FM judgment layer on top of algorithmic triggers. Defaults to `true` (allow) when FM is off.
    static func shouldSendPing(
        profileName: String,
        kind: String,
        algorithmicReason: String,
        extraContext: String = ""
    ) async -> (shouldNotify: Bool, reason: String, usedFoundationModel: Bool) {
        guard FoundationModelAvailability.isAvailable else {
            return (true, "FM unavailable; algorithmic trigger stands.", false)
        }
        let name = profileName.isEmpty ? "Hey" : profileName
        do {
            let session = LanguageModelSession(instructions: voiceInstructions)
            let prompt = """
                Decide if \(name) should get a local notification now.
                Kind: \(kind)
                Algorithmic reason: \(algorithmicReason)
                Extra: \(extraContext.isEmpty ? "none" : extraContext)
                Rules: allow necessary bad-trend, Watch-wear, and pre-sleep HR missing/elevated pings.
                Suppress only if the signal is clearly noise, duplicate-feeling, or too mild to bother someone.
                When unsure, allow the ping (shouldNotify = true).
                """
            var options = GenerationOptions()
            options.temperature = 0.2
            options.maximumResponseTokens = 80
            let response = try await session.respond(
                to: prompt,
                generating: PingJudgment.self,
                options: options
            )
            let judgment = response.content
            return (
                judgment.shouldNotify,
                CoachCopySanitize.clean(judgment.reason),
                true
            )
        } catch {
            return (true, "FM judgment failed; algorithmic trigger stands.", false)
        }
    }

    // MARK: Digest / offline assist

    /// Short on-device summary of a Health digest before (or without) Grok.
    static func summarizeFitnessDigest(
        profileName: String,
        digestBlock: String
    ) async -> String? {
        guard FoundationModelAvailability.isAvailable else { return nil }
        guard !digestBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let name = profileName.isEmpty ? "Hey" : profileName
        do {
            let session = LanguageModelSession(instructions: voiceInstructions)
            let prompt = """
                \(name) asked for a quick private read of this Apple Health digest.
                Stay on-device. Under 90 words. One next action that fits the time of day if obvious.
                Digest:
                \(digestBlock)
                """
            var options = GenerationOptions()
            options.temperature = 0.6
            options.maximumResponseTokens = 180
            let response = try await session.respond(to: prompt, options: options)
            let text = CoachCopySanitize.clean(response.content)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    /// Optional FM pass to pull sticky facts; merges with heuristic extractor upstream.
    static func extractMemoryFacts(from userText: String) async -> [CoachMemoryFact] {
        guard FoundationModelAvailability.isAvailable else { return [] }
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return [] }
        do {
            let session = LanguageModelSession(instructions: voiceInstructions)
            let prompt = """
                Extract durable personal facts worth remembering for a fitness coach.
                Only keep diet, training, lifestyle constraints the user stated about themselves.
                Skip one-off questions and reminder scheduling.
                User said: \(trimmed)
                """
            var options = GenerationOptions()
            options.temperature = 0.2
            options.maximumResponseTokens = 120
            let response = try await session.respond(
                to: prompt,
                generating: MemoryExtractionDraft.self,
                options: options
            )
            return response.content.facts.compactMap { raw in
                let clean = CoachCopySanitize.clean(raw)
                guard clean.count >= 6 else { return nil }
                return CoachMemoryFact(text: clean, tags: ["fm", "lifestyle"])
            }
        } catch {
            return []
        }
    }

    // MARK: Helpers

    private static func clamp(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        let idx = text.index(text.startIndex, offsetBy: max - 1)
            return String(text[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
}
