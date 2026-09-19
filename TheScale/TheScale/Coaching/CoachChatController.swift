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
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        agent: CoachAgentRole? = nil,
        text: String,
        usedNetwork: Bool = false,
        isFailure: Bool = false,
        isStreaming: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.agent = agent
        self.text = text
        self.usedNetwork = usedNetwork
        self.isFailure = isFailure
        self.isStreaming = isStreaming
        self.createdAt = createdAt
    }
}

/// On-device conversation transcript (UserDefaults). Separate from habit/target fact memory.
enum CoachChatHistoryStore {
    private static let key = "thescale.coachChatHistory.v1"
    /// Keep enough for multi-session continuity without bloating UserDefaults.
    private static let maxTurns = 80

    static func load() -> [CoachChatTurn] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let turns = try? JSONDecoder().decode([CoachChatTurn].self, from: data)
        else {
            return []
        }
        // Never restore a mid-stream placeholder.
        return turns.filter { !($0.isStreaming || ($0.kind == .assistant && $0.text.isEmpty)) }
    }

    static func save(_ turns: [CoachChatTurn]) {
        let cleaned = turns
            .filter { !($0.isStreaming || ($0.kind == .assistant && $0.text.isEmpty)) }
            .suffix(maxTurns)
        if let data = try? JSONEncoder().encode(Array(cleaned)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

@MainActor
final class CoachChatController: ObservableObject {
    @Published private(set) var turns: [CoachChatTurn] = []
    @Published var draft = ""
    @Published private(set) var isSending = false
    @Published private(set) var rememberedCount = 0

    func seedWelcome(name: String) {
        rememberedCount = CoachMemoryStore.load().count
        let saved = CoachChatHistoryStore.load()
        if !saved.isEmpty {
            turns = saved
            return
        }
        guard turns.isEmpty else { return }
        let who = name.isEmpty ? "Operator" : name
        turns = [
            CoachChatTurn(
                kind: .assistant,
                agent: .orchestrator,
                text: "\(who). What's the play?"
            )
        ]
        persist()
    }

    func clearConversation(name: String) {
        CoachChatHistoryStore.clear()
        turns = []
        seedWelcome(name: name)
    }

    func send(session: ScaleSessionViewModel) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""

        for fact in CoachMemoryExtractor.extract(from: text) {
            CoachMemoryStore.remember(fact)
        }

        // Gate + apply stated weight / body-fat targets before Grok sees the brief.
        let targetResults = session.processCoachStatedTargets(from: text)
        rememberedCount = CoachMemoryStore.load().count

        // Schedule local wake / reminder pings on-device (UNUserNotificationCenter).
        var reminderResults: [CoachReminderResult] = []
        if let reminder = CoachReminderExtractor.extract(from: text) {
            let scheduled = await CoachReminderScheduler.schedule(
                reminder,
                profileName: session.profile.greetingName
            )
            reminderResults.append(scheduled)
            if scheduled.status == .scheduled {
                CoachMemoryStore.remember(
                    CoachMemoryFact(
                        text: scheduled.coachNote,
                        tags: ["reminder", "notification"]
                    )
                )
            }
            rememberedCount = CoachMemoryStore.load().count
        }

        turns.append(CoachChatTurn(kind: .user, text: text))
        for result in targetResults {
            turns.append(
                CoachChatTurn(
                    kind: .assistant,
                    agent: .orchestrator,
                    text: result.coachNote,
                    usedNetwork: false
                )
            )
        }
        for result in reminderResults {
            turns.append(
                CoachChatTurn(
                    kind: .assistant,
                    agent: .orchestrator,
                    text: result.coachNote,
                    usedNetwork: false
                )
            )
        }
        persist()

        let brief = session.makeCoachBrief()
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
            let lines = reminderResults.map { r -> String in
                switch r.status {
                case .scheduled:
                    return "Reminder SCHEDULED on-device: \(r.coachNote)"
                case .denied:
                    return "Reminder NOT scheduled (notifications denied): \(r.coachNote)"
                case .failed:
                    return "Reminder FAILED: \(r.coachNote)"
                }
            }
            return "\n\nReminder gate (on-device, honour this):\n" + lines.joined(separator: "\n")
        }()

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
            memoryBlock: brief.memoryBlock + targetContext + reminderContext,
            fitnessDigestBlock: brief.fitnessDigestBlock,
            localNow: brief.localNow
        )

        let assistantID = UUID()
        turns.append(
            CoachChatTurn(
                id: assistantID,
                kind: .assistant,
                agent: .orchestrator,
                text: "",
                usedNetwork: false,
                isStreaming: true
            )
        )
        isSending = true
        defer { isSending = false }

        let historySnapshot = turns.filter { $0.id != assistantID }

        await GrokClient.shared.chatStreaming(
            userText: text,
            brief: briefWithExtras,
            history: historySnapshot
        ) { [weak self] reply in
            guard let self else { return }
            guard let idx = self.turns.firstIndex(where: { $0.id == assistantID }) else { return }
            self.turns[idx] = CoachChatTurn(
                id: assistantID,
                kind: .assistant,
                agent: .orchestrator,
                text: reply.text,
                usedNetwork: reply.usedNetwork,
                isFailure: reply.failureReason != nil,
                isStreaming: true
            )
        }

        if let idx = turns.firstIndex(where: { $0.id == assistantID }) {
            let finished = turns[idx]
            turns[idx] = CoachChatTurn(
                id: assistantID,
                kind: .assistant,
                agent: .orchestrator,
                text: finished.text,
                usedNetwork: finished.usedNetwork,
                isFailure: finished.isFailure,
                isStreaming: false
            )
        }
        persist()
    }

    private func persist() {
        CoachChatHistoryStore.save(turns)
    }
}
