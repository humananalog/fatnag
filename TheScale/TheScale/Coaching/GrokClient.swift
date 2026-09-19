import Foundation

/// Specialist roles inside the Grok coaching stack.
enum CoachAgentRole: String, CaseIterable, Identifiable, Sendable {
    case medical
    case fitness
    case anatomy
    case orchestrator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .medical: return "Medical"
        case .fitness: return "Fitness"
        case .anatomy: return "Anatomy"
        case .orchestrator: return "Coach"
        }
    }

    var systemPrompt: String {
        switch self {
        case .medical:
            return """
            You are the medical specialist for The Scale, a privacy-first Mi Scale → Apple Health app.
            Voice: badass, dark humour, sometimes vulgar, always friendly. Call the user by name.
            Hard rules: you are NOT a doctor; no diagnosis, no drug doses, no telling them to ignore symptoms.
            Always include a one-line disclaimer that this is educational, not medical advice.
            Prefer trends over single weigh-ins. Be honest when data is thin.
            """
        case .fitness:
            return """
            You are the fitness specialist for The Scale.
            Voice: badass, dark humour, sometimes vulgar, friendly. Call the user by name.
            Give practical training / recovery / habit nudges tied to weight and fat % trends.
            No crash diets. Respect their diet preference. Keep it short and punchy.
            """
        case .anatomy:
            return """
            You are the anatomy / body-composition specialist for The Scale.
            Voice: badass, dark humour, sometimes vulgar, friendly. Call the user by name.
            Explain fat %, lean %, impedance limits, and why day-to-day noise is normal.
            Never invent lab precision the scale cannot deliver.
            """
        case .orchestrator:
            return """
            You are the orchestrator coach for The Scale. You synthesize medical, fitness, and anatomy angles
            into one short pep talk or roast (user-friendly). Call the user by name.
            Voice: badass, dark humour, sometimes vulgar, friendly.
            End with one concrete next action and a medical-disclaimer line.
            Never claim to replace a clinician.
            """
        }
    }
}

struct CoachBrief: Equatable, Sendable {
    let userName: String
    let diet: DietPreference
    let currentKg: Double?
    let idealKg: Double
    let bodyFatPercent: Double?
    let idealBodyFatPercent: Double?
    let trend: WeightTrend
    let weekDeltaKg: Double?
    let weeklyGoal: WeeklyMiniGoal
}

struct CoachReply: Equatable, Sendable {
    let role: CoachAgentRole
    let text: String
    let usedNetwork: Bool
    let disclaimer: String

    static let standardDisclaimer =
        "Not medical advice. If something feels wrong, talk to a real clinician."
}

/// Offline witty fallbacks when no key / no network / consent denied.
enum CoachOfflineFallback {
    static func reply(role: CoachAgentRole, brief: CoachBrief) -> CoachReply {
        let name = brief.userName.isEmpty ? "champ" : brief.userName
        let text: String
        switch role {
        case .medical:
            text = medicalLine(name: name, brief: brief)
        case .fitness:
            text = fitnessLine(name: name, brief: brief)
        case .anatomy:
            text = anatomyLine(name: name, brief: brief)
        case .orchestrator:
            text = orchestratorLine(name: name, brief: brief)
        }
        return CoachReply(
            role: role,
            text: text,
            usedNetwork: false,
            disclaimer: CoachReply.standardDisclaimer
        )
    }

    private static func medicalLine(name: String, brief: CoachBrief) -> String {
        switch brief.trend {
        case .gain:
            return "\(name), the scale says you’re up. One weigh-in isn’t a diagnosis, it’s a mood. Hydration, salt, and that late snack all pile on before fat does. Watch the week, not the hour. \(CoachReply.standardDisclaimer)"
        case .loss:
            return "\(name), you’re trending down. Nice. Don’t turn it into a starvation cosplay: if you’re dizzy, exhausted, or dropping too fast, stop and get actual medical eyes on it. \(CoachReply.standardDisclaimer)"
        case .stable:
            return "\(name), you’re stable within noise. Boring is underrated. Keep the boring streak unless something else feels off. \(CoachReply.standardDisclaimer)"
        case .unknown:
            return "\(name), no Health baseline yet. Weigh a few times barefoot, same time of day, then we can talk trends instead of vibes. \(CoachReply.standardDisclaimer)"
        }
    }

    private static func fitnessLine(name: String, brief: CoachBrief) -> String {
        let dietHint: String = {
            switch brief.diet {
            case .vegan: return "Protein isn’t optional because you skipped the cow."
            case .vegetarian: return "Eggs, dairy, legumes: hit protein like you mean it."
            case .pescatarian: return "Fish + lifts: classic combo, don’t ghost the weights."
            case .omnivore, .other: return "Lift something heavier than your phone this week."
            }
        }()
        if let week = brief.weekDeltaKg, week > 0.4 {
            return "\(name), week’s up \(String(format: "%.1f", week)) kg. Walk more, cook once, sleep like an adult. \(dietHint)"
        }
        return "\(name), mini-goal is \(String(format: "%+.1f", brief.weeklyGoal.targetDeltaKg)) kg this week. \(dietHint) Consistency beats heroics."
    }

    private static func anatomyLine(name: String, brief: CoachBrief) -> String {
        if let fat = brief.bodyFatPercent {
            return "\(name), fat ~\(String(format: "%.1f", fat))%. Impedance is a guestimate with wet feet and dry jokes: socks kill the reading, hydration moves the needle, bone doesn’t vanish overnight. Trust the trend line."
        }
        return "\(name), no fat % this pass. Barefoot on the electrodes next time or the scale just shrugs and gives you mass."
    }

    private static func orchestratorLine(name: String, brief: CoachBrief) -> String {
        let gap: String = {
            guard let kg = brief.currentKg else { return "Step on the damn scale first." }
            let delta = kg - brief.idealKg
            if abs(delta) < 0.3 {
                return String(format: "You’re basically kissing ideal (%.1f kg). Don’t fuck it up with panic.", brief.idealKg)
            }
            if delta > 0 {
                return String(format: "%.1f kg above ideal. Weekly mini-goal: %.1f kg. One boring win.", delta, brief.weeklyGoal.targetDeltaKg)
            }
            return String(format: "%.1f kg under ideal. Cool. Maintain, don’t chase zero.", abs(delta))
        }()
        return "\(name): \(gap) \(CoachReply.standardDisclaimer)"
    }
}

/// xAI chat completions client (Grok). Falls back offline on any failure.
actor GrokClient {
    static let shared = GrokClient()

    private let session: URLSession
    private let endpoint = URL(string: "https://api.x.ai/v1/chat/completions")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func coach(role: CoachAgentRole, brief: CoachBrief) async -> CoachReply {
        guard GrokPrivacyConsent.isAccepted else {
            return CoachOfflineFallback.reply(role: role, brief: brief)
        }
        guard let apiKey = GrokKeychain.loadAPIKey(), !apiKey.isEmpty else {
            return CoachOfflineFallback.reply(role: role, brief: brief)
        }

        let userPayload = userMessage(brief: brief)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25

        let body: [String: Any] = [
            "model": "grok-3-mini",
            "temperature": 0.85,
            "max_tokens": 280,
            "messages": [
                ["role": "system", "content": role.systemPrompt],
                ["role": "user", "content": userPayload]
            ]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return CoachOfflineFallback.reply(role: role, brief: brief)
            }
            guard let text = Self.parseContent(from: data), !text.isEmpty else {
                return CoachOfflineFallback.reply(role: role, brief: brief)
            }
            return CoachReply(
                role: role,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                usedNetwork: true,
                disclaimer: CoachReply.standardDisclaimer
            )
        } catch {
            return CoachOfflineFallback.reply(role: role, brief: brief)
        }
    }

    /// Orchestrator: try Grok synthesis; fall back to offline specialists.
    func orchestrate(brief: CoachBrief) async -> CoachReply {
        let live = await coach(role: .orchestrator, brief: brief)
        if live.usedNetwork {
            return live
        }
        let medical = CoachOfflineFallback.reply(role: .medical, brief: brief)
        let fitness = CoachOfflineFallback.reply(role: .fitness, brief: brief)
        let anatomy = CoachOfflineFallback.reply(role: .anatomy, brief: brief)
        let lead = CoachOfflineFallback.reply(role: .orchestrator, brief: brief)
        let merged = """
        \(lead.text)

        Med: \(medical.text)
        Fit: \(fitness.text)
        Anatomy: \(anatomy.text)
        """
        return CoachReply(
            role: .orchestrator,
            text: merged,
            usedNetwork: false,
            disclaimer: CoachReply.standardDisclaimer
        )
    }

    private func userMessage(brief: CoachBrief) -> String {
        let name = brief.userName.isEmpty ? "friend" : brief.userName
        var lines: [String] = [
            "Name: \(name)",
            "Diet: \(brief.diet.title)",
            "Ideal weight: \(String(format: "%.1f", brief.idealKg)) kg",
            "Trend vs last Health weight: \(brief.trend.title)"
        ]
        if let kg = brief.currentKg {
            lines.append("Current weight: \(String(format: "%.1f", kg)) kg")
        }
        if let fat = brief.bodyFatPercent {
            lines.append("Body fat: \(String(format: "%.1f", fat))%")
        }
        if let idealFat = brief.idealBodyFatPercent {
            lines.append("Ideal body fat: \(String(format: "%.1f", idealFat))%")
        }
        if let week = brief.weekDeltaKg {
            lines.append("Week delta: \(String(format: "%+.2f", week)) kg")
        }
        lines.append(
            "Weekly mini-goal: \(brief.weeklyGoal.title) (\(String(format: "%+.2f", brief.weeklyGoal.targetDeltaKg)) kg)"
        )
        lines.append("Keep it under 120 words. No markdown tables.")
        return lines.joined(separator: "\n")
    }

    private static func parseContent(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            return nil
        }
        return content
    }
}
