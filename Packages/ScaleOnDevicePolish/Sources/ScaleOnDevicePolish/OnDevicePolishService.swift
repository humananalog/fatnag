import Foundation

/// High-level polish API used when Apple Intelligence is unavailable on compatible iPhones.
@MainActor
public final class OnDevicePolishService: ObservableObject {
    public static let shared = OnDevicePolishService()

    private let engine = LlamaMetalEngine()
    private var loadedPath: String?
    private let defaultVoice = """
        You write for FATNAG, a private fitness coach on the user's iPhone.
        Call the user by name when given. Friendly, badass, dark humour; sometimes vulgar; never corporate.
        Never use em dashes or en dashes. Use ASCII hyphen or a period.
        Never say you are an AI, language model, or Apple Intelligence.
        Never add medical disclaimers, diagnoses, or consult-a-doctor lines.
        Keep copy short enough for iOS banners.
        """

    public var isReady: Bool {
        OnDevicePolishInstaller.shared.isModelPresent
            && {
                if case .ready = OnDevicePolishInstaller.shared.snapshot.phase { return true }
                return false
            }()
    }

    public var snapshot: OnDevicePolishSnapshot {
        OnDevicePolishInstaller.shared.snapshot
    }

    private func ensureLoaded() throws {
        let path = OnDevicePolishInstaller.shared.modelFileURL.path
        if loadedPath == path { return }
        try engine.load(modelPath: path)
        loadedPath = path
    }

    public func refineNotificationCopy(
        profileName: String,
        kind: String,
        fallbackTitle: String,
        fallbackBody: String,
        context: String,
        voiceRules: String? = nil
    ) async -> (title: String, body: String, usedSidecar: Bool) {
        guard isReady else { return (fallbackTitle, fallbackBody, false) }
        let name = profileName.isEmpty ? "Hey" : profileName
        let voice = voiceRules ?? defaultVoice
        let prompt = """
            \(voice)

            Draft a local notification for \(name).
            Kind: \(kind)
            Context: \(context)
            Fallback title: \(fallbackTitle)
            Fallback body: \(fallbackBody)
            Prefer a sharper rewrite of the fallback; keep the same facts.
            TITLE is Watch glance: max 20 chars, verb or number first, no emoji, no name prefix.
            BODY is iPhone expanded: name OK, max ~120 chars.
            Reply with exactly two lines:
            TITLE: ...
            BODY: ...
            """
        do {
            try ensureLoaded()
            let raw = try engine.complete(prompt: prompt, maxTokens: 120)
            let parsed = OnDevicePolishParsers.parseTitleBody(
                raw,
                fallbackTitle: fallbackTitle,
                fallbackBody: fallbackBody
            )
            return (parsed.title, parsed.body, true)
        } catch {
            return (fallbackTitle, fallbackBody, false)
        }
    }

    public func shouldSendPing(
        profileName: String,
        kind: String,
        algorithmicReason: String,
        extraContext: String = "",
        voiceRules: String? = nil
    ) async -> (shouldNotify: Bool, reason: String, usedSidecar: Bool) {
        guard isReady else {
            return (true, "On-device polish unavailable; algorithmic trigger stands.", false)
        }
        let name = profileName.isEmpty ? "Hey" : profileName
        let voice = voiceRules ?? defaultVoice
        let prompt = """
            \(voice)

            Decide if \(name) should get a local notification now.
            Kind: \(kind)
            Algorithmic reason: \(algorithmicReason)
            Extra: \(extraContext.isEmpty ? "none" : extraContext)
            Rules: allow necessary bad-trend, Watch-wear, and pre-sleep HR missing/elevated pings.
            Suppress only if the signal is clearly noise.
            When unsure, allow the ping.
            Reply with exactly two lines:
            NOTIFY: yes|no
            REASON: ...
            """
        do {
            try ensureLoaded()
            let raw = try engine.complete(prompt: prompt, maxTokens: 80)
            let parsed = OnDevicePolishParsers.parseNotify(raw)
            return (parsed.shouldNotify, parsed.reason, true)
        } catch {
            return (true, "On-device polish failed; algorithmic trigger stands.", false)
        }
    }

    public func summarizeFitnessDigest(
        profileName: String,
        digestBlock: String,
        voiceRules: String? = nil
    ) async -> String? {
        guard isReady else { return nil }
        let digest = digestBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digest.isEmpty else { return nil }
        let name = profileName.isEmpty ? "Hey" : profileName
        let voice = voiceRules ?? defaultVoice
        let prompt = """
            \(voice)

            \(name) asked for a quick private read of this Apple Health digest.
            Stay on-device. Under 90 words. One next action if obvious.
            Digest:
            \(digest)
            """
        do {
            try ensureLoaded()
            let raw = try engine.complete(prompt: prompt, maxTokens: 180)
            let clean = OnDevicePolishParsers.sanitize(raw)
            return clean.isEmpty ? nil : clean
        } catch {
            return nil
        }
    }

    public func extractMemoryFacts(
        from userText: String,
        voiceRules: String? = nil
    ) async -> [String] {
        guard isReady else { return [] }
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return [] }
        let voice = voiceRules ?? defaultVoice
        let prompt = """
            \(voice)

            Extract durable personal facts worth remembering for a fitness coach.
            Only keep diet, training, lifestyle constraints the user stated about themselves.
            Skip one-off questions and reminder scheduling.
            User said: \(trimmed)
            Reply as a bullet list, one fact per line starting with "- ". Empty if none.
            """
        do {
            try ensureLoaded()
            let raw = try engine.complete(prompt: prompt, maxTokens: 120)
            return raw
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { line -> String in
                    var s = line
                    if s.hasPrefix("- ") { s = String(s.dropFirst(2)) }
                    if s.hasPrefix("* ") { s = String(s.dropFirst(2)) }
                    return OnDevicePolishParsers.sanitize(s)
                }
                .filter { $0.count >= 6 }
                .prefix(3)
                .map { String($0) }
        } catch {
            return []
        }
    }
}

enum OnDevicePolishParsers: Sendable {
    static func parseTitleBody(
        _ raw: String,
        fallbackTitle: String,
        fallbackBody: String
    ) -> (title: String, body: String) {
        var title = fallbackTitle
        var body = fallbackBody
        for line in raw.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            let upper = line.uppercased()
            if upper.hasPrefix("TITLE:") {
                let value = sanitize(String(line.dropFirst(6)))
                if !value.isEmpty { title = clamp(value, max: 48) }
            } else if upper.hasPrefix("BODY:") {
                let value = sanitize(String(line.dropFirst(5)))
                if !value.isEmpty { body = clamp(value, max: 140) }
            }
        }
        return (title, body)
    }

    static func parseNotify(_ raw: String) -> (shouldNotify: Bool, reason: String) {
        var should = true
        var reason = "On-device polish judgment"
        for line in raw.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            let upper = line.uppercased()
            if upper.hasPrefix("NOTIFY:") {
                let value = line.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if value.hasPrefix("no") || value.hasPrefix("false") || value.hasPrefix("0") {
                    should = false
                }
            } else if upper.hasPrefix("REASON:") {
                let value = sanitize(String(line.dropFirst(7)))
                if !value.isEmpty { reason = value }
            }
        }
        return (should, reason)
    }

    static func sanitize(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "\u{2014}", with: "-")
        s = s.replacingOccurrences(of: "\u{2013}", with: "-")
        return s
    }

    private static func clamp(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        let idx = text.index(text.startIndex, offsetBy: max - 1)
        return String(text[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
