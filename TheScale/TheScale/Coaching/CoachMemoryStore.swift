import Foundation

/// One durable fact the coach remembers on-device (diet habits, constraints, etc.).
struct CoachMemoryFact: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var text: String
    var createdAt: Date
    /// Loose tags for relevance (diet, training, medical, lifestyle).
    var tags: [String]

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        tags: [String] = []
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.tags = tags
    }
}

/// On-device chat memory. Never uploaded except as short context when the user consents to Grok.
enum CoachMemoryStore {
    private static let key = "thescale.coachMemoryFacts"
    private static let maxFacts = 40

    static func load() -> [CoachMemoryFact] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let facts = try? JSONDecoder().decode([CoachMemoryFact].self, from: data)
        else {
            return []
        }
        return facts
    }

    static func save(_ facts: [CoachMemoryFact]) {
        let trimmed = Array(facts.suffix(maxFacts))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    @discardableResult
    static func remember(_ fact: CoachMemoryFact) -> [CoachMemoryFact] {
        var facts = load()
        let normalized = fact.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return facts }
        let lower = normalized.lowercased()
        if facts.contains(where: { $0.text.lowercased() == lower }) {
            return facts
        }
        facts.append(
            CoachMemoryFact(id: fact.id, text: normalized, createdAt: fact.createdAt, tags: fact.tags)
        )
        save(facts)
        return facts
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Compact block for Grok system context (no PII beyond what the user typed).
    static func promptBlock(limit: Int = 12) -> String {
        let facts = load().suffix(limit)
        guard !facts.isEmpty else { return "" }
        let lines = facts.map { "- \($0.text)" }
        return """
        Remembered user facts (on-device; honour these when adjusting diet / training):
        \(lines.joined(separator: "\n"))
        """
    }
}

/// Cheap on-device fact extractor from chat (no network).
enum CoachMemoryExtractor {
    static func extract(from userText: String) -> [CoachMemoryFact] {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return [] }

        var facts: [CoachMemoryFact] = []
        let lower = trimmed.lowercased()

        let starters = [
            "i'm ", "i am ", "i’ve ", "i've ", "i prefer ", "i can't ", "i cannot ",
            "i don’t ", "i don't ", "i do ", "my diet ", "i follow ", "i practice "
        ]
        if starters.contains(where: { lower.hasPrefix($0) }) || lower.contains("intermittent fasting")
            || lower.contains("i eat ") || lower.contains("allergic") || lower.contains("intolerant")
        {
            let tags = tags(for: lower)
            facts.append(CoachMemoryFact(text: trimmed, tags: tags))
        }

        // Short habit phrases anywhere in the message
        let phrases = [
            "intermittent fasting", "16/8", "omad", "keto", "low carb", "high protein",
            "no dairy", "no gluten", "plant based", "plant-based"
        ]
        for phrase in phrases where lower.contains(phrase) {
            let text = "User mentioned: \(phrase)"
            if !facts.contains(where: { $0.text.lowercased().contains(phrase) }) {
                facts.append(CoachMemoryFact(text: text, tags: ["diet"]))
            }
        }

        return facts
    }

    private static func tags(for lower: String) -> [String] {
        var tags: [String] = []
        if ["diet", "fast", "eat", "vegan", "keto", "protein", "calorie", "food"].contains(where: {
            lower.contains($0)
        }) {
            tags.append("diet")
        }
        if ["gym", "lift", "run", "train", "workout", "cardio"].contains(where: { lower.contains($0) }) {
            tags.append("training")
        }
        if ["pain", "medic", "doctor", "allerg"].contains(where: { lower.contains($0) }) {
            tags.append("medical")
        }
        if tags.isEmpty { tags = ["lifestyle"] }
        return tags
    }
}
