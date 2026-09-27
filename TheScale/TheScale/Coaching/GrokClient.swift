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

    func systemPrompt(sex: UserBodyProfile.Sex) -> String {
        let voice = CoachVoice.llmRules(sex: sex)
        switch self {
        case .medical:
            return """
            You are the health-context specialist for The Scale, a privacy-first Mi Scale → Apple Health app.
            \(voice)
            Prefer trends over single weigh-ins. Be honest when data is thin.
            You are not a clinician and must not diagnose. Fitness guidance only.
            """
        case .fitness:
            return """
            You are the fitness specialist for The Scale.
            \(voice)
            Give practical training / recovery / habit nudges tied to weight, fat %, sleep stages, HRV, RHR, and activity.
            Match advice to Local now: morning can be training; night is wind-down, not a PR attempt.
            Use only the Fitness digest for last workout / activity / steps / energy / distance / HR / HRV / sleep / recovery band. If a metric says missing, say so. Never invent sleep stages, HRV, SpO2, VO2, or workouts. Never claim you can read AllTrails directly.
            No crash diets. Respect their diet preference and remembered facts.
            """
        case .anatomy:
            return """
            You are the anatomy / body-composition specialist for The Scale.
            \(voice)
            Explain fat %, lean %, impedance limits, and why day-to-day noise is normal.
            Never invent lab precision the scale cannot deliver.
            """
        case .orchestrator:
            return """
            You are the only user-facing coach for The Scale. Medical, fitness, and anatomy specialists
            may consult behind the scenes; you alone speak to the user. Never mention agent roles or routing.
            \(voice)
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
    /// Preferred display / prompt units (canonical storage stays metric).
    let unitSystem: PreferredUnitSystem

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
        localNow: Date = Date(),
        unitSystem: PreferredUnitSystem = .metric
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
        self.unitSystem = unitSystem
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
        let who = CoachVoice.who(name, sex: brief.sex)
        let dietHint: String = {
            switch (brief.sex, brief.diet) {
            case (.female, .vegan):
                return "Keep those plant palms honest: tofu or chickpeas on every plate."
            case (.female, .vegetarian):
                return "Eggs, yogurt, legumes: palm-size protein each meal."
            case (.female, .pescatarian):
                return "Fish palm at dinner plus a big handful of greens."
            case (.female, _):
                return "Palm of protein, fist of carbs, big handful of greens. Easy picture."
            case (.male, .vegan):
                return "Protein isn't optional because you skipped the cow."
            case (.male, .vegetarian):
                return "Eggs, dairy, legumes: hit protein like you mean it."
            case (.male, .pescatarian):
                return "Fish + lifts: classic combo, don't ghost the weights."
            case (.male, _):
                return "Lift something heavier than your phone this week."
            }
        }()
        if let week = brief.weekDeltaKg, week > 0.4 {
            let mass = UnitFormat.massDeltaString(week, system: brief.unitSystem)
            switch brief.sex {
            case .female:
                return "\(who), week drifted \(mass). Walk more, cook once, sleep like the main character. \(dietHint)"
            case .male:
                return "\(who), week's up \(mass). Walk more, cook once, sleep like an adult. \(dietHint)"
            }
        }
        let goal = UnitFormat.massDeltaString(brief.weeklyGoal.targetDeltaKg, system: brief.unitSystem)
        switch brief.sex {
        case .female:
            return "\(who), this week's nudge is \(goal). \(dietHint) Consistency looks gorgeous on you."
        case .male:
            return "\(who), mini-goal is \(goal) this week. \(dietHint) Consistency beats heroics."
        }
    }

    private static func anatomyLine(name: String, brief: CoachBrief) -> String {
        let who = CoachVoice.who(name, sex: brief.sex)
        if let fat = brief.bodyFatPercent {
            switch brief.sex {
            case .female:
                return "\(who), fat around \(String(format: "%.1f", fat))%. The scale is a chatty guestimate: wet feet help, socks kill the reading, hydration moves the needle. Trust the trend, not one awkward morning."
            case .male:
                return "\(who), fat ~\(String(format: "%.1f", fat))%. Impedance is a guestimate with wet feet and dry jokes: socks kill the reading, hydration moves the needle, bone doesn't vanish overnight. Trust the trend line."
            }
        }
        switch brief.sex {
        case .female:
            return "\(who), no fat % this pass. Barefoot on the electrodes next time, or the scale just shrugs and gives you mass."
        case .male:
            return "\(who), no fat % this pass. Barefoot on the electrodes next time or the scale just shrugs and gives you mass."
        }
    }

    private static func orchestratorLine(name: String, brief: CoachBrief) -> String {
        let who = CoachVoice.who(name, sex: brief.sex)
        let gap: String = {
            guard let kg = brief.currentKg else {
                return brief.sex == .female
                    ? "Step on the scale when you're ready. I'll cheer either way."
                    : "Step on the damn scale first."
            }
            let delta = kg - brief.idealKg
            let ideal = UnitFormat.massString(brief.idealKg, system: brief.unitSystem, fractionDigits: 1)
            let absDelta = UnitFormat.massString(abs(delta), system: brief.unitSystem, fractionDigits: 1)
            let week = UnitFormat.massDeltaString(
                brief.weeklyGoal.targetDeltaKg,
                system: brief.unitSystem
            )
            if abs(delta) < 0.3 {
                return brief.sex == .female
                    ? "You're basically kissing dream weight (\(ideal)). Soft hold. Don't panic-edit dinner."
                    : "You're basically kissing ideal (\(ideal)). Don't fuck it up with panic."
            }
            if delta > 0 {
                return brief.sex == .female
                    ? "\(absDelta) above dream weight. This week's nudge: \(week). One boring beautiful win."
                    : "\(absDelta) above ideal. Weekly mini-goal: \(week). One boring win."
            }
            return brief.sex == .female
                ? "\(absDelta) under dream weight. Cool. Maintain, don't chase zero."
                : "\(absDelta) under ideal. Cool. Maintain, don't chase zero."
        }()
        return "\(who): \(gap)"
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
                return "Consent off. Turn on Allow Keel coach requests in Settings."
            case .notConfigured(let detail):
                return detail
            case .malformedProxy(let detail):
                return detail
            case .badURL:
                return "Keel proxy URL is invalid (NSURLError bad URL). Rebuild with GROK_PROXY_URL = https:/$()/the-scale-grok.the-scale-grok.workers.dev"
            case .httpStatus(let code):
                return "Keel proxy returned HTTP \(code). Check Worker health / XAI_API_KEY secret."
            case .emptyResponse:
                return "Keel returned an empty reply. Try again in a moment."
            case .transport(let message):
                return "Keel request failed: \(message)"
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
        let box = StreamReplyBox(
            CoachReply(role: .orchestrator, text: "", usedNetwork: false)
        )
        await chatStreaming(
            role: role,
            userText: userText,
            brief: brief,
            history: history,
            quotaKind: quotaKind
        ) { reply in
            box.value = reply
        }
        return box.value
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
                "content": CoachAgentRole.orchestrator.systemPrompt(sex: brief.sex)
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
            let accumulated = StreamTextBox()
            try await postChatStream(body: body, transport: transport, timeout: 60) { delta in
                accumulated.append(delta)
                let partial = CoachReply(
                    role: .orchestrator,
                    text: accumulated.text,
                    usedNetwork: true
                )
                await onUpdate(partial)
            }
            let cleaned = CoachCopySanitize.clean(accumulated.text)
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
        let modeLine = "Weekly target mode: \(sundayGoal.mode.mondayHeroBadge). \(sundayGoal.mode.mondayHeroCTA)"
        let prompt = """
        Build the Monday morning post-weigh card. Reply ONLY with these three sections, exact headers:

        ===ENCOURAGEMENT===
        (1-2 lines. Call \(brief.userName.isEmpty ? "them" : brief.userName) by name. Badass, dark humour OK. Match mode: \(sundayGoal.mode.mondayHeroBadge). Respect goal difficulty flavor in persona if present.)

        ===MEALS===
        (Practical week meal pattern for their diet / IF / persona / Health context. Not a novel. Instructor pattern.)

        ===DIAGNOSTIC===
        (Energy-balance instructor block. Physics / plausible weekly weight-loss rates from the numbers.
        How to hit Sunday \(String(format: "%.2f", sundayGoal.targetKg)) kg on \(sundayLabel).
        Use last-week progress + Fitness digest only. Never invent missing Health samples.
        Do not diagnose medical conditions. Fitness coaching only. No disclaimer lecture.
        If sleep quality proxy / recovery is green after a solid night, do NOT call sleep bad.)

        Local progress summary: \(progress.summaryLine)
        Adherence: \(progress.adherenceLine)
        Signals: \(progress.signalLines.joined(separator: " · "))
        Sunday goal: \(String(format: "%.2f", sundayGoal.targetKg)) kg (\(String(format: "%+.2f", sundayGoal.weeklyDeltaKg)) kg/wk). \(sundayGoal.pacingLine)
        \(modeLine)
        Long-range: \(goalDateLine)
        """

        let system = """
        You are the Monday weigh-in instructor for The Scale.
        \(CoachAgentRole.orchestrator.systemPrompt(sex: brief.sex))
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
            let accumulated = StreamTextBox()
            try await postChatStream(body: body, transport: transport, timeout: 60) { delta in
                accumulated.append(delta)
                let snapshot = accumulated.text
                let parts = MondayCardEngine.parseSections(from: snapshot)
                await onUpdate(parts.encouragement, parts.meals, parts.diagnostic, snapshot)
            }
            let snapshot = accumulated.text
            let parts = MondayCardEngine.parseSections(from: snapshot)
            var encouragement = parts.encouragement
            var meals = parts.meals
            var diagnostic = parts.diagnostic
            if encouragement.isEmpty { encouragement = offline.encouragement }
            if meals.isEmpty { meals = offline.meals }
            if diagnostic.isEmpty {
                diagnostic = parts.diagnostic.isEmpty ? offline.diagnostic : CoachCopySanitize.clean(snapshot)
            }
            await onUpdate(encouragement, meals, diagnostic, snapshot)
            return (encouragement, meals, diagnostic, true)
        } catch {
            await onUpdate(offline.encouragement, offline.meals, offline.diagnostic, "")
            return (offline.encouragement, offline.meals, offline.diagnostic, false)
        }
    }

    /// Next-24h meal plan for home carousel. Compact JSON only. Token-efficient.
    /// Caller should check cache first; this always hits network when live (burns 1 credit).
    func mealPlan(
        brief: CoachBrief,
        maxKcal: Int,
        proteinGrams: Int,
        microHint: String,
        dayKey: String,
        weeklyDeltaKg: Double,
        fasting: FastingWindow = .none,
        now: Date = Date()
    ) async -> MealPlanPayload {
        let templated = MealPlanEngine.offlinePlan(
            name: brief.userName,
            diet: brief.diet,
            maxKcal: maxKcal,
            proteinGrams: proteinGrams,
            dayKey: dayKey,
            weeklyDeltaKg: weeklyDeltaKg,
            fasting: fasting,
            units: brief.unitSystem,
            now: now
        )

        // Weekly credits exhausted (or consent / transport missing): prefer on-device FM, else solid template.
        let quotaBlocked = !(await MainActor.run { CoachWeeklyQuota.canConsume(plan: ScaleSubscriptionStore.shared.plan) })
        let transportMissing = GrokSharedConfig.configurationIssue != nil || resolveTransport() == nil
        if !GrokPrivacyConsent.isAccepted || transportMissing || quotaBlocked {
            return await localMealPlanFallback(
                brief: brief,
                maxKcal: maxKcal,
                proteinGrams: proteinGrams,
                microHint: microHint,
                dayKey: dayKey,
                weeklyDeltaKg: weeklyDeltaKg,
                fasting: fasting,
                now: now,
                templated: templated,
                reason: quotaBlocked
                    ? "Weekly Keel credits used. On-device menu."
                    : "On-device menu (Keel offline or consent off)."
            )
        }

        guard let transport = resolveTransport() else {
            return await localMealPlanFallback(
                brief: brief,
                maxKcal: maxKcal,
                proteinGrams: proteinGrams,
                microHint: microHint,
                dayKey: dayKey,
                weeklyDeltaKg: weeklyDeltaKg,
                fasting: fasting,
                now: now,
                templated: templated,
                reason: "On-device menu (Keel offline)."
            )
        }

        if let _ = await consumeQuota(.mealPlan) {
            return await localMealPlanFallback(
                brief: brief,
                maxKcal: maxKcal,
                proteinGrams: proteinGrams,
                microHint: microHint,
                dayKey: dayKey,
                weeklyDeltaKg: weeklyDeltaKg,
                fasting: fasting,
                now: now,
                templated: templated,
                reason: "Weekly Keel credits used. On-device menu."
            )
        }

        let who = brief.userName.isEmpty ? "the user" : brief.userName
        let localTime = now.formatted(date: .omitted, time: .shortened)
        let plateCount = MealPlanEngine.preferredMealCount(for: fasting)
        let fastingLine: String = {
            if fasting.isActive {
                let open = MealPlanEngine.formatHour(fasting.eatingStartHour)
                let close = MealPlanEngine.formatHour(fasting.eatingEndHour)
                let fastingNow = fasting.isFasting(at: now) ? "CURRENTLY FASTING" : "inside eating window"
                return "Intermittent fasting active (\(fasting.cacheToken)). Eating window \(open)-\(close) local. Status now: \(fastingNow). Do NOT propose meals during the fasting window. First meal at or after window open. Exactly \(plateCount) meal\(plateCount == 1 ? "" : "s") inside the window. NEVER title a meal Breakfast or Break-fast when fasting is active. For 2 plates use Lunch then Dinner. For 3+ use First plate / Mid plate / Last plate."
            }
            return "No intermittent fasting window set. Exactly \(plateCount) meals."
        }()
        let memory = brief.memoryBlock.isEmpty ? "" : "\n\(brief.memoryBlock)"
        let portionRule = brief.unitSystem == .metric
            ? "Each ingredient must include a metric portion (g or ml)."
            : "Each ingredient must include a portion in oz / fl oz (imperial)."
        let system = """
        You write tight meal plans for The Scale. Fitness coaching only. Never diagnose.
        No medical disclaimer. No em dashes. JSON only. Honour fasting windows strictly.
        \(brief.unitSystem.coachPromptLine)
        """
        let prompt = """
        Next meals for \(who) from local now \(localTime) through ~24h. Diet: \(brief.diet.title). Daily max \(maxKcal) kcal, protein \(proteinGrams) g, micro focus: \(microHint).
        Weekly weight nudge \(String(format: "%+.1f", weeklyDeltaKg)) kg.
        \(fastingLine)\(memory)
        \(portionRule)
        Reply ONLY JSON:
        {"meals":[{"title":"Lunch","time":"~12:00","ingredients":["Chicken breast 140 g","Greens 120 g"],"macro":"Protein 35 g","micro":"Iron ~3 mg","kcal":420},{"title":"Dinner","time":"~19:00","ingredients":["Salmon 150 g","Broccoli 200 g"],"macro":"Protein 40 g","micro":"Omega-3","kcal":480}]}
        Exactly \(plateCount) meal\(plateCount == 1 ? "" : "s"). Stay under \(maxKcal) total. Match diet. Main ingredients with portions. Times must be inside any eating window and at/after local now. No extra snacks.
        """

        let body: [String: Any] = [
            "model": Self.liveModel,
            "temperature": 0.4,
            "max_tokens": 380,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt]
            ]
        ]

        do {
            let data = try await postChat(body: body, transport: transport, timeout: 35)
            let raw = Self.parseContent(from: data) ?? ""
            if let parsed = MealPlanEngine.parseGrokJSON(raw, minimumCount: plateCount) {
                let meals = MealPlanEngine.localizePortions(
                    MealPlanEngine.enforceFasting(parsed, fasting: fasting, now: now),
                    units: brief.unitSystem
                )
                guard meals.count >= plateCount else {
                    return await localMealPlanFallback(
                        brief: brief,
                        maxKcal: maxKcal,
                        proteinGrams: proteinGrams,
                        microHint: microHint,
                        dayKey: dayKey,
                        weeklyDeltaKg: weeklyDeltaKg,
                        fasting: fasting,
                        now: now,
                        templated: templated,
                        reason: "On-device menu (Keel parse thin)."
                    )
                }
                let key = MealPlanEngine.cacheKey(
                    dayKey: dayKey,
                    maxKcal: maxKcal,
                    proteinGrams: proteinGrams,
                    diet: brief.diet,
                    weeklyDeltaKg: weeklyDeltaKg,
                    fasting: fasting,
                    now: now
                )
                let note = fasting.isActive ? CoachPersona.liveBadge(fastingNote: "IF respected") : CoachPersona.liveBadge()
                return MealPlanPayload(
                    cacheKey: key,
                    dayKey: dayKey,
                    maxKcal: maxKcal,
                    proteinGrams: proteinGrams,
                    dietRaw: brief.diet.rawValue,
                    meals: meals,
                    generatedAt: Date(),
                    usedNetwork: true,
                    sourceNote: note,
                    targetMealCount: plateCount
                )
            }
            return await localMealPlanFallback(
                brief: brief,
                maxKcal: maxKcal,
                proteinGrams: proteinGrams,
                microHint: microHint,
                dayKey: dayKey,
                weeklyDeltaKg: weeklyDeltaKg,
                fasting: fasting,
                now: now,
                templated: templated,
                reason: "On-device menu (Keel empty)."
            )
        } catch {
            return await localMealPlanFallback(
                brief: brief,
                maxKcal: maxKcal,
                proteinGrams: proteinGrams,
                microHint: microHint,
                dayKey: dayKey,
                weeklyDeltaKg: weeklyDeltaKg,
                fasting: fasting,
                now: now,
                templated: templated,
                reason: "On-device menu (Keel error)."
            )
        }
    }

    /// FM first (metric portions), then preference-aware templated menu. Never an empty stub.
    private func localMealPlanFallback(
        brief: CoachBrief,
        maxKcal: Int,
        proteinGrams: Int,
        microHint: String,
        dayKey: String,
        weeklyDeltaKg: Double,
        fasting: FastingWindow,
        now: Date,
        templated: MealPlanPayload,
        reason: String
    ) async -> MealPlanPayload {
        if let fmMeals = await FoundationModelCoach.generateMealPlan(
            name: brief.userName,
            diet: brief.diet,
            maxKcal: maxKcal,
            proteinGrams: proteinGrams,
            microHint: microHint,
            weeklyDeltaKg: weeklyDeltaKg,
            fasting: fasting,
            memoryBlock: brief.memoryBlock,
            sex: brief.sex,
            now: now
        ) {
            let scheduled = MealPlanEngine.localizePortions(
                MealPlanEngine.enforceFasting(fmMeals, fasting: fasting, now: now),
                units: brief.unitSystem
            )
            let plateCount = MealPlanEngine.preferredMealCount(for: fasting)
            if scheduled.count >= plateCount {
                let key = MealPlanEngine.cacheKey(
                    dayKey: dayKey,
                    maxKcal: maxKcal,
                    proteinGrams: proteinGrams,
                    diet: brief.diet,
                    weeklyDeltaKg: weeklyDeltaKg,
                    fasting: fasting,
                    now: now
                )
                let fastingBit = fasting.isActive ? " IF respected." : ""
                return MealPlanPayload(
                    cacheKey: key,
                    dayKey: dayKey,
                    maxKcal: maxKcal,
                    proteinGrams: proteinGrams,
                    dietRaw: brief.diet.rawValue,
                    meals: scheduled,
                    generatedAt: now,
                    usedNetwork: false,
                    sourceNote: "\(reason) Apple Intelligence.\(fastingBit)",
                    targetMealCount: plateCount
                )
            }
        }
        var plan = templated
        plan.sourceNote = "\(reason) Preference-aware template with portions."
        return plan
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
                ["role": "system", "content": role.systemPrompt(sex: brief.sex)],
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
                ["role": "system", "content": specialty.systemPrompt(sex: brief.sex)],
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
            brief.unitSystem.coachPromptLine,
            "Profile (DO NOT re-ask these): height \(UnitFormat.heightString(brief.heightCm, system: brief.unitSystem)), age \(String(format: "%.0f", brief.ageYears)), sex \(brief.sex.title)",
            "Diet: \(brief.diet.title)",
            "Target weight: \(UnitFormat.massString(brief.idealKg, system: brief.unitSystem))",
            "Trend vs last Health weight: \(brief.trend.title)"
        ]
        if daypart == "evening" || daypart == "night" {
            lines.append(
                "Time gate: it is \(daypart). Prefer recovery / sleep / food timing / light mobility. Ban gym lifts, bench press, or 'train hard now' as the next action."
            )
        }
        if let kg = brief.currentKg {
            lines.append("Current weight: \(UnitFormat.massString(kg, system: brief.unitSystem))")
        }
        if let fat = brief.bodyFatPercent {
            lines.append("Body fat: \(String(format: "%.1f", fat))%")
        }
        if let idealFat = brief.idealBodyFatPercent {
            lines.append("Target body fat: \(String(format: "%.1f", idealFat))%")
        }
        if let week = brief.weekDeltaKg {
            lines.append("Week delta: \(UnitFormat.massDeltaString(week, system: brief.unitSystem))")
        }
        lines.append(
            "Weekly mini-goal: \(brief.weeklyGoal.title) (\(UnitFormat.massDeltaString(brief.weeklyGoal.targetDeltaKg, system: brief.unitSystem)))"
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

/// Thread-safe string accumulation for streaming callbacks (Swift 6 Sendable).
private final class StreamTextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ delta: String) {
        lock.lock()
        storage += delta
        lock.unlock()
    }
}

/// Holds the last CoachReply from a @MainActor streaming sink.
private final class StreamReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: CoachReply

    init(_ value: CoachReply) {
        storage = value
    }

    var value: CoachReply {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
