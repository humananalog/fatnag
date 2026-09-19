import Foundation

/// Specialist roles used behind the scenes. User-facing chat always comes from the orchestrator.
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
            Give practical training / recovery / habit nudges tied to weight, fat %, sleep, HR, and activity.
            No crash diets. Respect their diet preference and remembered facts. Keep it short and punchy.
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
            You are the only user-facing coach for The Scale. Medical, fitness, and anatomy specialists
            may consult behind the scenes; you alone speak to the user. Never mention agent roles or routing.
            Voice: badass, dark humour, sometimes vulgar, friendly. Call the user by name.
            Match their persona (location, ethnicity, language, cultural vibe) without stereotyping.
            Honour remembered user facts (e.g. intermittent fasting) when adjusting diet advice.
            Ask clarifying questions when diet tweaks need more detail.
            End with one concrete next action and a medical-disclaimer line.
            Never claim to replace a clinician.
            Produce ONE coherent answer. No multi-agent dump.
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
    let personaBlock: String
    let memoryBlock: String
    let fitnessDigestBlock: String

    init(
        userName: String,
        diet: DietPreference,
        currentKg: Double?,
        idealKg: Double,
        bodyFatPercent: Double?,
        idealBodyFatPercent: Double?,
        trend: WeightTrend,
        weekDeltaKg: Double?,
        weeklyGoal: WeeklyMiniGoal,
        personaBlock: String = "",
        memoryBlock: String = "",
        fitnessDigestBlock: String = ""
    ) {
        self.userName = userName
        self.diet = diet
        self.currentKg = currentKg
        self.idealKg = idealKg
        self.bodyFatPercent = bodyFatPercent
        self.idealBodyFatPercent = idealBodyFatPercent
        self.trend = trend
        self.weekDeltaKg = weekDeltaKg
        self.weeklyGoal = weeklyGoal
        self.personaBlock = personaBlock
        self.memoryBlock = memoryBlock
        self.fitnessDigestBlock = fitnessDigestBlock
    }
}

struct CoachReply: Equatable, Sendable {
    let role: CoachAgentRole
    let text: String
    let usedNetwork: Bool
    let disclaimer: String
    /// When set, UI should treat this as a hard failure (not a witty offline mock).
    let failureReason: String?

    static let standardDisclaimer =
        "Not medical advice. If something feels wrong, talk to a real clinician."

    init(
        role: CoachAgentRole,
        text: String,
        usedNetwork: Bool,
        disclaimer: String = standardDisclaimer,
        failureReason: String? = nil
    ) {
        self.role = role
        self.text = text
        self.usedNetwork = usedNetwork
        self.disclaimer = disclaimer
        self.failureReason = failureReason
    }
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
            return "\(name), the scale says you're up. One weigh-in isn't a diagnosis, it's a mood. Hydration, salt, and that late snack all pile on before fat does. Watch the week, not the hour. \(CoachReply.standardDisclaimer)"
        case .loss:
            return "\(name), you're trending down. Nice. Don't turn it into a starvation cosplay: if you're dizzy, exhausted, or dropping too fast, stop and get actual medical eyes on it. \(CoachReply.standardDisclaimer)"
        case .stable:
            return "\(name), you're stable within noise. Boring is underrated. Keep the boring streak unless something else feels off. \(CoachReply.standardDisclaimer)"
        case .unknown:
            return "\(name), no Health baseline yet. Weigh a few times barefoot, same time of day, then we can talk trends instead of vibes. \(CoachReply.standardDisclaimer)"
        }
    }

    private static func fitnessLine(name: String, brief: CoachBrief) -> String {
        let dietHint: String = {
            switch brief.diet {
            case .vegan: return "Protein isn't optional because you skipped the cow."
            case .vegetarian: return "Eggs, dairy, legumes: hit protein like you mean it."
            case .pescatarian: return "Fish + lifts: classic combo, don't ghost the weights."
            case .omnivore, .other: return "Lift something heavier than your phone this week."
            }
        }()
        if let week = brief.weekDeltaKg, week > 0.4 {
            return "\(name), week's up \(String(format: "%.1f", week)) kg. Walk more, cook once, sleep like an adult. \(dietHint)"
        }
        return "\(name), mini-goal is \(String(format: "%+.1f", brief.weeklyGoal.targetDeltaKg)) kg this week. \(dietHint) Consistency beats heroics."
    }

    private static func anatomyLine(name: String, brief: CoachBrief) -> String {
        if let fat = brief.bodyFatPercent {
            return "\(name), fat ~\(String(format: "%.1f", fat))%. Impedance is a guestimate with wet feet and dry jokes: socks kill the reading, hydration moves the needle, bone doesn't vanish overnight. Trust the trend line."
        }
        return "\(name), no fat % this pass. Barefoot on the electrodes next time or the scale just shrugs and gives you mass."
    }

    private static func orchestratorLine(name: String, brief: CoachBrief) -> String {
        let gap: String = {
            guard let kg = brief.currentKg else { return "Step on the damn scale first." }
            let delta = kg - brief.idealKg
            if abs(delta) < 0.3 {
                return String(format: "You're basically kissing ideal (%.1f kg). Don't fuck it up with panic.", brief.idealKg)
            }
            if delta > 0 {
                return String(format: "%.1f kg above ideal. Weekly mini-goal: %.1f kg. One boring win.", delta, brief.weeklyGoal.targetDeltaKg)
            }
            return String(format: "%.1f kg under ideal. Cool. Maintain, don't chase zero.", abs(delta))
        }()
        return "\(name): \(gap) \(CoachReply.standardDisclaimer)"
    }
}

/// Shared Grok client. Prefer Cloudflare proxy; fall back to baked key; else offline mock.
actor GrokClient {
    static let shared = GrokClient()

    private let session: URLSession
    private let directEndpoint = URL(string: "https://api.x.ai/v1/chat/completions")!

    private enum Transport {
        case proxy(URL)
        case direct(apiKey: String)
    }

    enum LiveFailure: Error, Equatable {
        case consentDenied
        case notConfigured(String)
        case malformedProxy(String)
        case badURL
        case httpStatus(Int)
        case emptyResponse
        case transport(String)

        var userMessage: String {
            switch self {
            case .consentDenied:
                return "Consent off. Turn on Allow Grok coach requests in Settings."
            case .notConfigured(let detail):
                return detail
            case .malformedProxy(let detail):
                return detail
            case .badURL:
                return "Grok proxy URL is invalid (NSURLError bad URL). Rebuild with GROK_PROXY_URL = https:/$()/the-scale-grok.the-scale-grok.workers.dev"
            case .httpStatus(let code):
                return "Grok proxy returned HTTP \(code). Check Worker health / XAI_API_KEY secret."
            case .emptyResponse:
                return "Grok returned an empty reply. Try again in a moment."
            case .transport(let message):
                return "Grok request failed: \(message)"
            }
        }
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Cheap on-device specialty hint (orchestrator still owns the user-facing answer).
    nonisolated static func route(userText: String) -> CoachAgentRole {
        let lower = userText.lowercased()
        let medical = ["pain", "doctor", "blood", "medic", "diagnos", "symptom", "heart", "dizzy", "faint", "sleep hr", "resting hr"]
        let anatomy = ["impedance", "bia", "lean", "muscle", "visceral", "bone", "water", "body fat", "fat%"]
        let fitness = ["workout", "lift", "run", "cardio", "protein", "diet", "calorie", "train", "gym", "fast", "steps", "watch"]
        if medical.contains(where: { lower.contains($0) }) { return .medical }
        if anatomy.contains(where: { lower.contains($0) }) { return .anatomy }
        if fitness.contains(where: { lower.contains($0) }) { return .fitness }
        return .orchestrator
    }

    /// Freeform multi-turn chat. Always returns an orchestrator-facing reply.
    func chat(
        role: CoachAgentRole = .orchestrator,
        userText: String,
        brief: CoachBrief,
        history: [CoachChatTurn]
    ) async -> CoachReply {
        _ = role
        let specialty = Self.route(userText: userText)

        guard GrokPrivacyConsent.isAccepted else {
            return failureReply(LiveFailure.consentDenied, brief: brief, userText: userText)
        }
        if let issue = GrokSharedConfig.configurationIssue {
            // Malformed proxy should never look like a witty offline roast.
            if case .malformedProxyURL = issue {
                return failureReply(.malformedProxy(issue.userMessage), brief: brief, userText: userText)
            }
            if case .nonHTTPSProxy = issue {
                return failureReply(.malformedProxy(issue.userMessage), brief: brief, userText: userText)
            }
            return offlineChat(userText: userText, brief: brief, hint: issue.userMessage)
        }
        guard let transport = resolveTransport() else {
            return offlineChat(
                userText: userText,
                brief: brief,
                hint: GrokSharedConfig.ConfigurationIssue.missingProxyAndKey.userMessage
            )
        }

        var consultNotes = ""
        if specialty != .orchestrator {
            if let notes = try? await fetchSpecialistNotes(
                specialty: specialty,
                brief: brief,
                transport: transport
            ), !notes.isEmpty {
                consultNotes = "\n\nInternal \(specialty.title) consult (do not mention this role):\n\(notes)"
            }
        }

        var messages: [[String: String]] = [
            [
                "role": "system",
                "content": CoachAgentRole.orchestrator.systemPrompt
                    + "\n\n" + userMessage(brief: brief)
                    + consultNotes
                    + "\nLean on \(specialty.title) judgment for this ask without naming specialists."
            ]
        ]
        for turn in history.suffix(10) {
            switch turn.kind {
            case .user:
                messages.append(["role": "user", "content": turn.text])
            case .assistant:
                messages.append(["role": "assistant", "content": turn.text])
            }
        }
        if messages.last?["role"] != "user" || messages.last?["content"] != userText {
            messages.append(["role": "user", "content": userText])
        }

        let body: [String: Any] = [
            "model": "grok-3-mini",
            "temperature": 0.85,
            "max_tokens": 420,
            "messages": messages
        ]
        do {
            let data = try await postChat(body: body, transport: transport, timeout: 40)
            guard let text = Self.parseContent(from: data), !text.isEmpty else {
                return failureReply(.emptyResponse, brief: brief, userText: userText)
            }
            return CoachReply(
                role: .orchestrator,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                usedNetwork: true
            )
        } catch let failure as LiveFailure {
            return failureReply(failure, brief: brief, userText: userText)
        } catch {
            if let urlError = error as? URLError, urlError.code == .badURL {
                return failureReply(.badURL, brief: brief, userText: userText)
            }
            return failureReply(.transport(error.localizedDescription), brief: brief, userText: userText)
        }
    }

    /// Scheduled fitness digest check (orchestrator only).
    func fitnessCheck(brief: CoachBrief, triggerSummary: String) async -> CoachReply {
        let prompt = """
        Periodic fitness progress check.
        Trigger: \(triggerSummary)
        Give one short coherent coaching answer. Ask a clarifying diet question only if needed.
        """
        return await chat(userText: prompt, brief: brief, history: [])
    }

    private func offlineChat(userText: String, brief: CoachBrief, hint: String) -> CoachReply {
        let base = CoachOfflineFallback.reply(role: .orchestrator, brief: brief)
        let who = brief.userName.isEmpty ? "Operator" : brief.userName
        let blended = """
        \(base.text)

        (\(who) asked: "\(userText)") \(hint)
        """
        return CoachReply(
            role: .orchestrator,
            text: blended,
            usedNetwork: false
        )
    }

    private func failureReply(_ failure: LiveFailure, brief: CoachBrief, userText: String) -> CoachReply {
        let who = brief.userName.isEmpty ? "Operator" : brief.userName
        let text = """
        \(who), live Coach failed.

        \(failure.userMessage)

        (You asked: "\(userText)")
        Fix the proxy / consent, then try again. Offline roast withheld on purpose so this doesn't look "fine".
        """
        return CoachReply(
            role: .orchestrator,
            text: text,
            usedNetwork: false,
            failureReason: failure.userMessage
        )
    }

    func coach(role: CoachAgentRole, brief: CoachBrief) async -> CoachReply {
        guard GrokPrivacyConsent.isAccepted else {
            return CoachOfflineFallback.reply(role: role, brief: brief)
        }
        if let issue = GrokSharedConfig.configurationIssue {
            if case .malformedProxyURL = issue {
                return CoachReply(
                    role: .orchestrator,
                    text: issue.userMessage,
                    usedNetwork: false,
                    failureReason: issue.userMessage
                )
            }
            return CoachOfflineFallback.reply(role: role, brief: brief)
        }
        guard let transport = resolveTransport() else {
            return CoachOfflineFallback.reply(role: role, brief: brief)
        }

        let body: [String: Any] = [
            "model": "grok-3-mini",
            "temperature": 0.85,
            "max_tokens": 280,
            "messages": [
                ["role": "system", "content": role.systemPrompt],
                ["role": "user", "content": userMessage(brief: brief)]
            ]
        ]
        do {
            let data = try await postChat(body: body, transport: transport, timeout: 25)
            guard let text = Self.parseContent(from: data), !text.isEmpty else {
                return CoachOfflineFallback.reply(role: role, brief: brief)
            }
            return CoachReply(
                role: role,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                usedNetwork: true
            )
        } catch {
            return CoachOfflineFallback.reply(role: role, brief: brief)
        }
    }

    private func fetchSpecialistNotes(
        specialty: CoachAgentRole,
        brief: CoachBrief,
        transport: Transport
    ) async throws -> String {
        let body: [String: Any] = [
            "model": "grok-3-mini",
            "temperature": 0.6,
            "max_tokens": 180,
            "messages": [
                ["role": "system", "content": specialty.systemPrompt],
                [
                    "role": "user",
                    "content": userMessage(brief: brief)
                        + "\nWrite 3-5 bullet consult notes for the orchestrator. No user-facing fluff."
                ]
            ]
        ]
        let data = try await postChat(body: body, transport: transport, timeout: 25)
        return Self.parseContent(from: data)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func resolveTransport() -> Transport? {
        if let proxy = GrokSharedConfig.proxyURL {
            return .proxy(proxy)
        }
        if let key = GrokSharedConfig.bakedAPIKey {
            return .direct(apiKey: key)
        }
        return nil
    }

    private func postChat(body: [String: Any], transport: Transport, timeout: TimeInterval) async throws -> Data {
        var request: URLRequest
        switch transport {
        case .proxy(let proxy):
            request = URLRequest(url: proxy)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        case .direct(let apiKey):
            request = URLRequest(url: directEndpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .badURL {
            throw LiveFailure.badURL
        }
        guard let http = response as? HTTPURLResponse else {
            throw LiveFailure.transport("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LiveFailure.httpStatus(http.statusCode)
        }
        return data
    }

    /// Orchestrator: try Grok synthesis; fall back to offline specialists merged once.
    func orchestrate(brief: CoachBrief) async -> CoachReply {
        let live = await coach(role: .orchestrator, brief: brief)
        if live.usedNetwork || live.failureReason != nil {
            return live
        }
        let medical = CoachOfflineFallback.reply(role: .medical, brief: brief)
        let fitness = CoachOfflineFallback.reply(role: .fitness, brief: brief)
        let anatomy = CoachOfflineFallback.reply(role: .anatomy, brief: brief)
        let lead = CoachOfflineFallback.reply(role: .orchestrator, brief: brief)
        let merged = """
        \(lead.text)

        \(fitness.text)
        \(anatomy.text)
        \(medical.text)
        """
        return CoachReply(
            role: .orchestrator,
            text: merged,
            usedNetwork: false
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
        if !brief.personaBlock.isEmpty {
            lines.append(brief.personaBlock)
        }
        if !brief.memoryBlock.isEmpty {
            lines.append(brief.memoryBlock)
        }
        if !brief.fitnessDigestBlock.isEmpty {
            lines.append(brief.fitnessDigestBlock)
        }
        lines.append("Keep it under 140 words. No markdown tables.")
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
