import Foundation

struct CoachChatTurn: Identifiable, Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let kind: Kind
    let agent: CoachAgentRole?
    var text: String
    let usedNetwork: Bool
    let isFailure: Bool
    let isStreaming: Bool
    let isQuotaLock: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        agent: CoachAgentRole? = nil,
        text: String,
        usedNetwork: Bool = false,
        isFailure: Bool = false,
        isStreaming: Bool = false,
        isQuotaLock: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.agent = agent
        self.text = text
        self.usedNetwork = usedNetwork
        self.isFailure = isFailure
        self.isStreaming = isStreaming
        self.isQuotaLock = isQuotaLock
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, agent, text, usedNetwork, isFailure, isStreaming, isQuotaLock, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        agent = try c.decodeIfPresent(CoachAgentRole.self, forKey: .agent)
        text = try c.decode(String.self, forKey: .text)
        usedNetwork = try c.decodeIfPresent(Bool.self, forKey: .usedNetwork) ?? false
        isFailure = try c.decodeIfPresent(Bool.self, forKey: .isFailure) ?? false
        isStreaming = try c.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        isQuotaLock = try c.decodeIfPresent(Bool.self, forKey: .isQuotaLock) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

@MainActor
final class CoachChatController: ObservableObject {
    @Published private(set) var sessions: [CoachChatSession] = []
    @Published private(set) var activeSessionID: UUID?
    @Published private(set) var turns: [CoachChatTurn] = []
    @Published var draft = ""
    @Published private(set) var isSending = false
    @Published private(set) var rememberedCount = 0
    @Published var showPaywall = false
    @Published var paywallLockMessage: String?
    @Published var paywallHighlight: ScalePlan = .plus
    /// Brief non-technical notice when a live call fails (never the operator dump).
    @Published var transientNotice: String?
    /// User turn currently being edited (draft prefilled).
    @Published private(set) var editingTurnID: UUID?

    var activeSessionTitle: String {
        sessions.first(where: { $0.id == activeSessionID })?.title ?? "Coach"
    }

    /// Open Unlock Coach from a rate-limit bubble (or auto after lock).
    func openPaywall(from turn: CoachChatTurn? = nil) {
        if let turn, turn.isQuotaLock {
            paywallLockMessage = turn.text
        }
        paywallHighlight = ScaleSubscriptionStore.shared.plan.upgradeTarget ?? .plus
        showPaywall = true
    }

    func seedWelcome(name: String) {
        reloadSessions()
        var session = CoachChatSessionStore.ensureActiveSession()
        activeSessionID = session.id
        if session.turns.isEmpty {
            let who = name.isEmpty ? "Operator" : name
            session.turns = [
                CoachChatTurn(
                    kind: .assistant,
                    agent: .orchestrator,
                    text: "\(who). What's the play?"
                )
            ]
            session.updatedAt = Date()
            CoachChatSessionStore.upsert(session)
        }
        applySession(session)
        ScaleTelemetry.track("coach.open", props: ["sessions": sessions.count])
    }

    func reloadSessions() {
        sessions = CoachChatSessionStore.loadSessions()
        activeSessionID = CoachChatSessionStore.activeSessionID()
    }

    func selectSession(_ id: UUID) {
        guard !isSending else { return }
        cancelEdit()
        CoachChatSessionStore.setActiveSessionID(id)
        activeSessionID = id
        if let session = sessions.first(where: { $0.id == id }) {
            applySession(session)
        } else {
            reloadSessions()
            if let session = sessions.first(where: { $0.id == id }) {
                applySession(session)
            }
        }
        ScaleTelemetry.track("coach.session.select")
    }

    @discardableResult
    func createSession(name: String) -> CoachChatSession {
        cancelEdit()
        let session = CoachChatSessionStore.createSession(welcomeName: name)
        reloadSessions()
        applySession(session)
        ScaleTelemetry.track("coach.session.create")
        return session
    }

    func deleteSession(_ id: UUID, welcomeName: String) {
        guard !isSending else { return }
        cancelEdit()
        CoachChatSessionStore.deleteSession(id: id)
        reloadSessions()
        if let active = CoachChatSessionStore.activeSessionID(),
           let session = sessions.first(where: { $0.id == active }) {
            applySession(session)
        } else {
            seedWelcome(name: welcomeName)
        }
        ScaleTelemetry.track("coach.session.delete")
    }

    func clearConversation(name: String) {
        deleteSession(activeSessionID ?? UUID(), welcomeName: name)
        if sessions.isEmpty {
            _ = createSession(name: name)
        }
    }

    /// Prefill composer from a past user message for edit + resend.
    func beginEdit(turnID: UUID) {
        guard let turn = turns.first(where: { $0.id == turnID && $0.kind == .user }) else { return }
        guard !isSending else { return }
        editingTurnID = turnID
        draft = turn.text
    }

    func cancelEdit() {
        editingTurnID = nil
    }

    func send(session: ScaleSessionViewModel) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""

        var chatSession = currentSessionMutating()
        let editID = editingTurnID
        editingTurnID = nil

        // Edit path: truncate transcript after the edited user turn, then resend.
        if let editID,
           let idx = chatSession.turns.firstIndex(where: { $0.id == editID && $0.kind == .user }) {
            chatSession.turns = Array(chatSession.turns.prefix(idx))
        }

        for fact in CoachMemoryExtractor.extract(from: text) {
            rememberInSession(&chatSession, fact)
        }
        for fact in await FoundationModelCoach.extractMemoryFacts(from: text) {
            rememberInSession(&chatSession, fact)
        }

        // Gate + apply stated weight / body-fat targets before Grok sees the brief.
        let targetResults = session.processCoachStatedTargets(from: text)
        rememberedCount = chatSession.memoryFacts.count

        // Schedule local wake / reminder pings on-device (UNUserNotificationCenter).
        var reminderResults: [CoachReminderResult] = []
        if let reminder = CoachReminderExtractor.extract(from: text) {
            let scheduled = await CoachReminderScheduler.schedule(
                reminder,
                profileName: session.profile.greetingName
            )
            reminderResults.append(scheduled)
            if scheduled.status == .scheduled {
                rememberInSession(
                    &chatSession,
                    CoachMemoryFact(
                        text: scheduled.coachNote,
                        tags: ["reminder", "notification"]
                    )
                )
            }
            rememberedCount = chatSession.memoryFacts.count
        }

        chatSession.turns.append(CoachChatTurn(kind: .user, text: text))
        for result in targetResults {
            chatSession.turns.append(
                CoachChatTurn(
                    kind: .assistant,
                    agent: .orchestrator,
                    text: result.coachNote,
                    usedNetwork: false
                )
            )
        }
        for result in reminderResults {
            chatSession.turns.append(
                CoachChatTurn(
                    kind: .assistant,
                    agent: .orchestrator,
                    text: result.coachNote,
                    usedNetwork: false
                )
            )
        }
        chatSession.updatedAt = Date()
        commitSession(chatSession)
        ScaleTelemetry.track("coach.send", props: ["edited": editID != nil])

        // Always attach a fresh Apple Health snapshot to Coach (not only background monitor jobs).
        let digest = await session.refreshFitnessDigestForCoach()
        let brief = session.makeCoachBrief(digest: digest)
        let targetContext: String = {
            guard !targetResults.isEmpty else { return "" }
            let lines = targetResults.map { r -> String in
                switch r.verdict {
                case .accepted:
                    return "Target applied: \(r.coachNote)"
                case .acceptedWithCaution:
                    return "Target applied with caution: \(r.coachNote)"
                case .rejected:
                    return "Target REJECTED (do not store; reinforce this warning): \(r.coachNote)"
                }
            }
            return "\n\nTarget gate (on-device, honour this):\n" + lines.joined(separator: "\n")
        }()

        let reminderContext: String = {
            guard !reminderResults.isEmpty else { return "" }
            // Local wall-clock for the model (device timezone), not bare UTC ISO.
            let fmt = DateFormatter()
            fmt.locale = .current
            fmt.timeZone = .current
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            let tz = TimeZone.current.identifier
            let lines = reminderResults.map { r -> String in
                let fireLocal = fmt.string(from: r.request.fireAt)
                switch r.status {
                case .scheduled:
                    return "Reminder SCHEDULED on-device at \(fireLocal) (\(tz)): \(r.coachNote)"
                case .denied:
                    return "Reminder NOT scheduled (notifications denied) for \(fireLocal) (\(tz)): \(r.coachNote)"
                case .failed:
                    return "Reminder FAILED for \(fireLocal) (\(tz)): \(r.coachNote)"
                }
            }
            return "\n\nReminder gate (on-device, honour this):\n" + lines.joined(separator: "\n")
        }()

        let sessionMemory = chatSession.promptMemoryBlock()
        let briefWithExtras = CoachBrief(
            userName: brief.userName,
            diet: brief.diet,
            heightCm: brief.heightCm,
            ageYears: brief.ageYears,
            sex: brief.sex,
            currentKg: brief.currentKg,
            idealKg: brief.idealKg,
            bodyFatPercent: brief.bodyFatPercent,
            idealBodyFatPercent: brief.idealBodyFatPercent,
            trend: brief.trend,
            weekDeltaKg: brief.weekDeltaKg,
            weeklyGoal: brief.weeklyGoal,
            personaBlock: brief.personaBlock,
            memoryBlock: (sessionMemory.isEmpty ? brief.memoryBlock : sessionMemory)
                + targetContext + reminderContext,
            fitnessDigestBlock: brief.fitnessDigestBlock,
            localNow: brief.localNow,
            unitSystem: brief.unitSystem
        )

        let assistantID = UUID()
        chatSession.turns.append(
            CoachChatTurn(
                id: assistantID,
                kind: .assistant,
                agent: .orchestrator,
                text: "",
                usedNetwork: false,
                isStreaming: true
            )
        )
        turns = chatSession.turns
        isSending = true
        KeelIslandActivityController.begin(label: "Keel")
        defer {
            isSending = false
            KeelIslandActivityController.end()
        }

        // Never feed prior failure / quota-lock bubbles back into Keel as "assistant" history.
        let historySnapshot = chatSession.turns.filter {
            $0.id != assistantID && !$0.isFailure && !$0.isQuotaLock && !$0.text.isEmpty
        }

        await GrokClient.shared.chatStreaming(
            userText: text,
            brief: briefWithExtras,
            history: historySnapshot
        ) { [weak self] reply in
            guard let self else { return }
            guard let idx = self.turns.firstIndex(where: { $0.id == assistantID }) else { return }
            let failed = reply.failureReason != nil && !reply.isQuotaLock
            self.turns[idx] = CoachChatTurn(
                id: assistantID,
                kind: .assistant,
                agent: .orchestrator,
                text: failed ? "" : reply.text,
                usedNetwork: reply.usedNetwork,
                isFailure: reply.failureReason != nil,
                isStreaming: true,
                isQuotaLock: reply.isQuotaLock
            )
            if reply.isQuotaLock {
                self.paywallLockMessage = reply.text
                self.paywallHighlight = ScaleSubscriptionStore.shared.plan.upgradeTarget ?? .plus
                if !self.showPaywall {
                    self.showPaywall = true
                }
            }
        }

        chatSession.turns = turns
        if let idx = chatSession.turns.firstIndex(where: { $0.id == assistantID }) {
            let finished = chatSession.turns[idx]
            if finished.isFailure && !finished.isQuotaLock {
                chatSession.turns.remove(at: idx)
                transientNotice = "Couldn't reach Coach. Try again in a moment."
            } else {
                chatSession.turns[idx] = CoachChatTurn(
                    id: assistantID,
                    kind: .assistant,
                    agent: .orchestrator,
                    text: finished.text,
                    usedNetwork: finished.usedNetwork,
                    isFailure: finished.isFailure,
                    isStreaming: false,
                    isQuotaLock: finished.isQuotaLock
                )
            }
        }
        chatSession.updatedAt = Date()
        commitSession(chatSession)

        await maybeAutoRename(session: chatSession)
    }

    func clearTransientNotice() {
        transientNotice = nil
    }

    // MARK: - Private

    private func applySession(_ session: CoachChatSession) {
        activeSessionID = session.id
        turns = session.turns
        rememberedCount = session.memoryFacts.count
    }

    private func currentSessionMutating() -> CoachChatSession {
        if let id = activeSessionID,
           var existing = CoachChatSessionStore.loadSessions().first(where: { $0.id == id }) {
            existing.turns = turns
            return existing
        }
        return CoachChatSessionStore.ensureActiveSession()
    }

    private func commitSession(_ session: CoachChatSession) {
        CoachChatSessionStore.upsert(session)
        reloadSessions()
        applySession(session)
    }

    private func rememberInSession(_ session: inout CoachChatSession, _ fact: CoachMemoryFact) {
        let normalized = fact.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let lower = normalized.lowercased()
        if session.memoryFacts.contains(where: { $0.text.lowercased() == lower }) { return }
        session.memoryFacts.append(
            CoachMemoryFact(id: fact.id, text: normalized, createdAt: fact.createdAt, tags: fact.tags)
        )
        // Mirror diet/lifestyle facts into global store for weigh/meal brief continuity.
        CoachMemoryStore.remember(fact)
    }

    /// Funny short title via on-device FM first, else Grok with burnsCredit=false (system tokens).
    private func maybeAutoRename(session: CoachChatSession) async {
        guard !session.titleIsCustom else { return }
        let userTurns = session.turns.filter { $0.kind == .user && !$0.text.isEmpty }
        guard userTurns.count == 1 || (userTurns.count == 2 && session.title == "New nag") else { return }
        let snippet = userTurns.prefix(2).map(\.text).joined(separator: " · ")
        guard snippet.count >= 8 else { return }

        var title: String?
        if let fm = await FoundationModelCoach.funnyChatTitle(from: snippet) {
            title = fm
        } else if GrokPrivacyConsent.isAccepted {
            title = await GrokClient.shared.funnyChatTitle(from: snippet)
        }
        guard var cleaned = title?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else {
            return
        }
        cleaned = cleaned
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
        if cleaned.count > 36 {
            cleaned = String(cleaned.prefix(36)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var updated = session
        updated.title = cleaned
        updated.titleIsCustom = true
        updated.updatedAt = Date()
        commitSession(updated)
        ScaleTelemetry.track("coach.session.rename")
    }
}
