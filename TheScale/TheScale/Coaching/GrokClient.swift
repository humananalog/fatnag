import Foundation

/// Specialist roles used behind the scenes. User-facing chat always comes from the orchestrator.
enum CoachAgentRole: String, CaseIterable, Identifiable, Codable, Sendable {
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

    /// Shared voice + punctuation rules for every role.
    private static let voiceRules = """
        Voice: badass, dark humour, sometimes vulgar, always friendly. Call the user by name.
        Never use em dashes or en dashes. Use commas, periods, or ASCII hyphens (-).
        Never use AI tells ("As an AI…", "I'd be happy to…", "Certainly!", robotic hedging, markdown spoiler fluff).
        Do NOT append medical disclaimers or "not medical advice" boilerplate. That lives in onboarding and Settings → Legal only.
        You are not a clinician: no diagnosis, no drug doses, no telling them to ignore symptoms. Just don't recite disclaimer text.
        CRITICAL: Never ask for height, age, sex, name, diet, target weight, or body-fat goal if those fields are already in the profile block.
        CRITICAL: Be time-aware. Use Local now (weekday, clock, daypart). Evening / night / late = recovery, sleep, food timing, light mobility. Do NOT prescribe gym lifts, bench press, heavy training, or "hit the gym now" when the user is home at night or the clock says evening/night.
        CRITICAL: Do not rubber-stamp every idea. Push back when the ask is unsafe, unrealistic, or mismatched to the clock / context. Suggest what fits *this moment*.
        """

    var systemPrompt: String {
        switch self {
        case .medical:
            return """
            You are the health-context specialist for The Scale, a privacy-first Mi Scale → Apple Health app.
            \(Self.voiceRules)
            Prefer trends over single weigh-ins. Be honest when data is thin.
            You are not a clinician and must not diagnose. Fitness guidance only.
            """
        case .fitness:
            return """
            You are the fitness specialist for The Scale.
            \(Self.voiceRules)
            Give practical training / recovery / habit nudges tied to weight, fat %, sleep stages, HRV, RHR, and activity.
            Match advice to Local now: morning can be training; night is wind-down, not a PR attempt.
            Use only the Fitness digest for last workout / activity / steps / energy / distance / HR / HRV / sleep / recovery band. If a metric says missing, say so. Never invent sleep stages, HRV, SpO2, VO2, or workouts. Never claim you can read AllTrails directly.
            No crash diets. Respect their diet preference and remembered facts. Keep it short and punchy.
            """
        case .anatomy:
            return """
            You are the anatomy / body-composition specialist for The Scale.
            \(Self.voiceRules)
            Explain fat %, lean %, impedance limits, and why day-to-day noise is normal.
            Never invent lab precision the scale cannot deliver.
            """
        case .orchestrator:
            return """
            You are the only user-facing coach for The Scale. Medical, fitness, and anatomy specialists
            may consult behind the scenes; you alone speak to the user. Never mention agent roles or routing.
            \(Self.voiceRules)
            Match their persona (location, ethnicity, language, cultural vibe) without stereotyping.
            Honour remembered user facts (e.g. intermittent fasting) when adjusting diet advice.
            If the user states a weight or body-fat target, the app may have already gated it on-device.
            Honour "Target gate" notes in context: if a target was rejected as unsafe, push back and suggest the safer waypoint. Do not encourage essential-floor body-fat crashes.
            If the user asks for a wake-up or timed reminder / notification, the app schedules a real local notification on-device.
            Honour "Reminder gate" notes strictly:
            - SCHEDULED: confirm that exact local fire time once. Do not invent a second schedule.
            - NOT scheduled / FAILED / gate missing: do NOT claim a notification was set. Tell them to allow notifications or ask again.
            Do not pretend you can push from the cloud.
            CRITICAL: The Fitness digest block is the only source for workouts, last activity, steps, energy, distance, HR, HRV, respiratory rate, SpO2, VO2, wrist temperature, sleep (stages when present), and the recovery heuristic (HealthKit only). If Recent workouts lists sessions, discuss them (distance km included). If workouts are empty but walking/running distance spiked, say Health shows km without a Workout sample and suggest enabling Health sync in the tracking app (AllTrails etc.). If truly empty, say so and mention Allow Health / third-party write-to-Health. Never invent missing metrics. Never claim direct AllTrails access.
            Ask clarifying questions only when a needed fact is missing from the profile block. Never re-ask height/age/sex/targets already listed.
            End with one concrete next action that fits the current local time of day. Produce ONE coherent answer. No multi-agent dump.
            """
        }
    }
}

struct CoachBrief: Equatable, Sendable {
    let userName: String
    let diet: DietPreference
    let heightCm: Double
    let ageYears: Double
    let sex: UserBodyProfile.Sex
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
    /// Device-local clock for time-aware coaching (never invent a timezone).
    let localNow: Date

    init(
        userName: String,
        diet: DietPreference,
        heightCm: Double,
        ageYears: Double,
        sex: UserBodyProfile.Sex,
        currentKg: Double?,
        idealKg: Double,
        bodyFatPercent: Double?,
        idealBodyFatPercent: Double?,
        trend: WeightTrend,
        weekDeltaKg: Double?,
        weeklyGoal: WeeklyMiniGoal,
        personaBlock: String = "",
        memoryBlock: String = "",
        fitnessDigestBlock: String = "",
        localNow: Date = Date()
    ) {
        self.userName = userName
        self.diet = diet
        self.heightCm = heightCm
        self.ageYears = ageYears
        self.sex = sex
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
        self.localNow = localNow
    }
}

struct CoachReply: Equatable, Sendable {
    let role: CoachAgentRole
    let text: String
    let usedNetwork: Bool
    /// Kept empty; medical disclaimer is onboarding + Settings → Legal only.
    let disclaimer: String
    /// When set, UI should treat this as a hard failure (not a witty offline mock).
    let failureReason: String?
    /// Weekly Grok credit exhausted; UI should offer Plus / Pro unlock.
    let isQuotaLock: Bool

    init(
        role: CoachAgentRole,
        text: String,
        usedNetwork: Bool,
        disclaimer: String = "",
        failureReason: String? = nil,
        isQuotaLock: Bool = false
    ) {
        self.role = role
        self.text = CoachCopySanitize.clean(text)
        self.usedNetwork = usedNetwork
        self.disclaimer = disclaimer
        self.failureReason = failureReason
        self.isQuotaLock = isQuotaLock
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
            usedNetwork: false
        )
    }

    private static func medicalLine(name: String, brief: CoachBrief) -> String {
        switch brief.trend {
        case .gain:
            return "\(name), the scale says you're up. One weigh-in isn't a diagnosis, it's a mood. Hydration, salt, and that late snack all pile on before fat does. Watch the week, not the hour."
        case .loss:
            return "\(name), you're trending down. Nice. Don't turn it into a starvation cosplay: if you're dizzy, exhausted, or dropping too fast, stop and get actual medical eyes on it."
        case .stable:
            return "\(name), you're stable within noise. Boring is underrated. Keep the boring streak unless something else feels off."
        case .unknown:
            return "\(name), no Health baseline yet. Weigh a few times barefoot, same time of day, then we can talk trends instead of vibes."
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
        return "\(name): \(gap)"
    }
}

/// Shared Grok client. Prefer Cloudflare proxy; fall back to baked key; else offline mock.
actor GrokClient {
    static let shared = GrokClient()

    /// Console live model (Human Analog). Keep off reasoning SKUs for COGS.
    static let liveModel = "grok-4.20-non-reasoning"

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
        let fitness = [
            "workout", "activity", "activities", "exercise", "lift", "run", "cardio",
            "protein", "diet", "calorie", "train", "gym", "fast", "steps", "watch",
            "jog", "swim", "bike", "cycling", "hiit", "recovery", "active energy",
            "hike", "hiking", "walk", "walking", "outdoor", "trail", "alltrails",
            "strava", "insight", "insights", "km", "distance",
            "sleep", "hrv", "sdnn", "spo2", "oxygen", "vo2", "respiratory",
            "wrist temp", "temperature", "exercise time"
        ]
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
        history: [CoachChatTurn],
        quotaKind: CoachQuotaKind? = .chat
    ) async -> CoachReply {
        var final = CoachReply(role: .orchestrator, text: "", usedNetwork: false)
        await chatStreaming(
            role: role,
            userText: userText,
            brief: brief,
            history: history,
            quotaKind: quotaKind
        ) { reply in
            final = reply
        }
        return final
    }

    /// Streams token/chunk updates into `onUpdate`. Final call has the complete sanitized reply.
    func chatStreaming(
        role: CoachAgentRole = .orchestrator,
        userText: String,
        brief: CoachBrief,
        history: [CoachChatTurn],
        quotaKind: CoachQuotaKind? = .chat,
        onUpdate: @MainActor @Sendable (CoachReply) -> Void
    ) async {
        _ = role
        let specialty = Self.route(userText: userText)

        guard GrokPrivacyConsent.isAccepted else {
            await onUpdate(failureReply(LiveFailure.consentDenied, brief: brief, userText: userText))
            return
        }
        if let issue = GrokSharedConfig.configurationIssue {
            if case .malformedProxyURL = issue {
                await onUpdate(failureReply(.malformedProxy(issue.userMessage), brief: brief, userText: userText))
                return
            }
            if case .nonHTTPSProxy = issue {
                await onUpdate(failureReply(.malformedProxy(issue.userMessage), brief: brief, userText: userText))
                return
            }
            await onUpdate(offlineChat(userText: userText, brief: brief, hint: issue.userMessage))
            return
        }
        guard let transport = resolveTransport() else {
            await onUpdate(
                offlineChat(
                    userText: userText,
                    brief: brief,
                    hint: GrokSharedConfig.ConfigurationIssue.missingProxyAndKey.userMessage
                )
            )
            return
        }

        if let kind = quotaKind, let lock = await consumeQuota(kind) {
            await onUpdate(
                CoachReply(
                    role: .orchestrator,
                    text: lock,
                    usedNetwork: false,
                    failureReason: lock,
                    isQuotaLock: true
                )
            )
            return
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
            "model": Self.liveModel,
            "temperature": 0.55,
            "max_tokens": 420,
            "stream": true,
            "messages": messages
        ]

        do {
            var accumulated = ""
            try await postChatStream(body: body, transport: transport, timeout: 60) { delta in
                accumulated += delta
                let partial = CoachReply(
                    role: .orchestrator,
                    text: accumulated,
                    usedNetwork: true
                )
                await onUpdate(partial)
            }
            let cleaned = CoachCopySanitize.clean(accumulated)
            guard !cleaned.isEmpty else {
                await onUpdate(failureReply(.emptyResponse, brief: brief, userText: userText))
                return
            }
            await onUpdate(
                CoachReply(role: .orchestrator, text: cleaned, usedNetwork: true)
            )
        } catch let failure as LiveFailure {
            await onUpdate(failureReply(failure, brief: brief, userText: userText))
        } catch {
            if let urlError = error as? URLError, urlError.code == .badURL {
                await onUpdate(failureReply(.badURL, brief: brief, userText: userText))
            } else {
                await onUpdate(failureReply(.transport(error.localizedDescription), brief: brief, userText: userText))
            }
        }
    }

    /// Scheduled fitness digest check (orchestrator only).
    func fitnessCheck(brief: CoachBrief, triggerSummary: String) async -> CoachReply {
        let prompt = """
        Periodic fitness progress check.
        Trigger: \(triggerSummary)
        Give one short coherent coaching answer. Ask a clarifying diet question only if needed.
        """
        return await chat(
            userText: prompt,
            brief: brief,
            history: [],
            quotaKind: .fitnessCheck
        )
    }

    /// Monday post-weigh card: stream encouragement + meals + physics diagnostic.
    /// No medical disclaimer spam. Direct instructor voice. Never invent Health samples.
    func mondayCardStreaming(
        brief: CoachBrief,
        progress: MondayWeekProgress,
        sundayGoal: MondaySundayGoal,
        goalDateLine: String,
        onUpdate: @MainActor @Sendable (_ encouragement: String, _ meals: String, _ diagnostic: String, _ raw: String) -> Void
    ) async -> (encouragement: String, meals: String, diagnostic: String, usedNetwork: Bool) {
        let offline = MondayCardEngine.offlineCopy(
            name: brief.userName,
            progress: progress,
            goal: sundayGoal,
            diet: brief.diet,
            memoryBlock: brief.memoryBlock
        )

        guard GrokPrivacyConsent.isAccepted else {
            await onUpdate(offline.encouragement, offline.meals, offline.diagnostic, "")
            return (offline.encouragement, offline.meals, offline.diagnostic, false)
        }
        if GrokSharedConfig.configurationIssue != nil || resolveTransport() == nil {
            await onUpdate(offline.encouragement, offline.meals, offline.diagnostic, "")
            return (offline.encouragement, offline.meals, offline.diagnostic, false)
        }
        guard let transport = resolveTransport() else {
            await onUpdate(offline.encouragement, offline.meals, offline.diagnostic, "")
            return (offline.encouragement, offline.meals, offline.diagnostic, false)
        }

        if let _ = await consumeQuota(.mondayCard) {
            // Full card still shows via offline copy; unlock higher tier for live Grok rewrite.
            await onUpdate(offline.encouragement, offline.meals, offline.diagnostic, "")
            return (offline.encouragement, offline.meals, offline.diagnostic, false)
        }

        let sundayLabel = sundayGoal.sundayDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let prompt = """
        Build the Monday morning post-weigh card. Reply ONLY with these three sections, exact headers:

        ===ENCOURAGEMENT===
        (1-2 lines. Call \(brief.userName.isEmpty ? "them" : brief.userName) by name. Badass, dark humour OK.)

        ===MEALS===
        (Practical week meal pattern for their diet / IF / persona / Health context. Not a novel. Instructor pattern.)

        ===DIAGNOSTIC===
        (Energy-balance instructor block. Physics / plausible weekly weight-loss rates from the numbers.
        How to hit Sunday \(String(format: "%.2f", sundayGoal.targetKg)) kg on \(sundayLabel).
        Use last-week progress + Fitness digest only. Never invent missing Health samples.
        Do not diagnose medical conditions. Fitness coaching only. No disclaimer lecture.)

        Local progress summary: \(progress.summaryLine)
        Adherence: \(progress.adherenceLine)
        Signals: \(progress.signalLines.joined(separator: " · "))
        Sunday goal: \(String(format: "%.2f", sundayGoal.targetKg)) kg (\(String(format: "%+.2f", sundayGoal.weeklyDeltaKg)) kg/wk). \(sundayGoal.pacingLine)
        Long-range: \(goalDateLine)
        """

        let system = """
        You are the Monday weigh-in instructor for The Scale.
        \(CoachAgentRole.orchestrator.systemPrompt)
        This card is a direct coaching brief. Fitness guidance only. You are not a clinician and must not diagnose.
        Do NOT append medical disclaimers.
        Do NOT soft-pedal with generic safety caps. Talk energy balance and weekly rates from the data.
        Still never invent HealthKit samples that are missing.
        """

        let body: [String: Any] = [
            "model": Self.liveModel,
            "temperature": 0.55,
            "max_tokens": 520,
            "stream": true,
            "messages": [
                ["role": "system", "content": system + "\n\n" + userMessage(brief: brief)],
                ["role": "user", "content": prompt]
            ]
        ]

        do {
            var accumulated = ""
            try await postChatStream(body: body, transport: transport, timeout: 60) { delta in
                accumulated += delta
                let parts = MondayCardEngine.parseSections(from: accumulated)
                await onUpdate(parts.encouragement, parts.meals, parts.diagnostic, accumulated)
            }
            let parts = MondayCardEngine.parseSections(from: accumulated)
            var encouragement = parts.encouragement
            var meals = parts.meals
            var diagnostic = parts.diagnostic
            if encouragement.isEmpty { encouragement = offline.encouragement }
            if meals.isEmpty { meals = offline.meals }
            if diagnostic.isEmpty {
                diagnostic = parts.diagnostic.isEmpty ? offline.diagnostic : CoachCopySanitize.clean(accumulated)
            }
            await onUpdate(encouragement, meals, diagnostic, accumulated)
            return (encouragement, meals, diagnostic, true)
        } catch {
            await onUpdate(offline.encouragement, offline.meals, offline.diagnostic, "")
            return (offline.encouragement, offline.meals, offline.diagnostic, false)
        }
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

        if let lock = await consumeQuota(.chat) {
            return CoachReply(
                role: role,
                text: lock,
                usedNetwork: false,
                failureReason: lock,
                isQuotaLock: true
            )
        }

        let body: [String: Any] = [
            "model": Self.liveModel,
            "temperature": 0.55,
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
            "model": Self.liveModel,
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

    /// ISO-week credit burn. Returns lock copy when exhausted; nil when allowed (and increments).
    private func consumeQuota(_ kind: CoachQuotaKind) async -> String? {
        await MainActor.run {
            let plan = ScaleSubscriptionStore.shared.plan
            let lock = CoachWeeklyQuota.consume(kind, plan: plan)
            ScaleSubscriptionStore.shared.noteQuotaChange()
            return lock
        }
    }

    private func makeRequest(body: [String: Any], transport: Transport, timeout: TimeInterval) throws -> URLRequest {
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
        return request
    }

    private func postChat(body: [String: Any], transport: Transport, timeout: TimeInterval) async throws -> Data {
        let request = try makeRequest(body: body, transport: transport, timeout: timeout)
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

    /// Streams SSE chat.completions deltas. Calls `onDelta` for each content chunk.
    private func postChatStream(
        body: [String: Any],
        transport: Transport,
        timeout: TimeInterval,
        onDelta: @Sendable (String) async -> Void
    ) async throws {
        let request = try makeRequest(body: body, transport: transport, timeout: timeout)
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch let urlError as URLError where urlError.code == .badURL {
            throw LiveFailure.badURL
        }
        guard let http = response as? HTTPURLResponse else {
            throw LiveFailure.transport("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LiveFailure.httpStatus(http.statusCode)
        }

        for try await line in bytes.lines {
            if let delta = Self.parseSSEDelta(line: line) {
                await onDelta(delta)
            }
        }
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
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: brief.localNow)
        let daypart: String = {
            switch hour {
            case 5..<12: return "morning"
            case 12..<17: return "afternoon"
            case 17..<21: return "evening"
            default: return "night"
            }
        }()
        let weekday = brief.localNow.formatted(.dateTime.weekday(.wide))
        let clock = brief.localNow.formatted(date: .abbreviated, time: .shortened)
        var lines: [String] = [
            "Name: \(name)",
            "Local now: \(weekday) \(clock) (device local, daypart=\(daypart))",
            "Profile (DO NOT re-ask these): height \(String(format: "%.0f", brief.heightCm)) cm, age \(String(format: "%.0f", brief.ageYears)), sex \(brief.sex.title)",
            "Diet: \(brief.diet.title)",
            "Target weight: \(String(format: "%.1f", brief.idealKg)) kg",
            "Trend vs last Health weight: \(brief.trend.title)"
        ]
        if daypart == "evening" || daypart == "night" {
            lines.append(
                "Time gate: it is \(daypart). Prefer recovery / sleep / food timing / light mobility. Ban gym lifts, bench press, or 'train hard now' as the next action."
            )
        }
        if let kg = brief.currentKg {
            lines.append("Current weight: \(String(format: "%.1f", kg)) kg")
        }
        if let fat = brief.bodyFatPercent {
            lines.append("Body fat: \(String(format: "%.1f", fat))%")
        }
        if let idealFat = brief.idealBodyFatPercent {
            lines.append("Target body fat: \(String(format: "%.1f", idealFat))%")
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
        if brief.fitnessDigestBlock.isEmpty {
            lines.append(
                "Fitness digest: missing. Say you have no Apple Health snapshot yet. Do not invent workouts or activity."
            )
        } else {
            lines.append(brief.fitnessDigestBlock)
        }
        lines.append(
            "Keep it under 140 words. No markdown tables. No medical disclaimer footer. Next action must fit \(daypart)."
        )
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

    /// Parse one SSE line (`data: {...}` or `[DONE]`).
    nonisolated static func parseSSEDelta(line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" || payload.isEmpty { return nil }
        guard
            let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first
        else {
            return nil
        }
        if let delta = first["delta"] as? [String: Any], let content = delta["content"] as? String {
            return content.isEmpty ? nil : content
        }
        // Some gateways nest message.content mid-stream
        if let message = first["message"] as? [String: Any], let content = message["content"] as? String {
            return content.isEmpty ? nil : content
        }
        return nil
    }
}
