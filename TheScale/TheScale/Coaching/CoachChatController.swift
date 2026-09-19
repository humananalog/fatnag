import Foundation

struct CoachChatTurn: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
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

@MainActor
final class CoachChatController: ObservableObject {
    @Published private(set) var turns: [CoachChatTurn] = []
    @Published var draft = ""
    @Published private(set) var isSending = false
    @Published private(set) var rememberedCount = 0

    func seedWelcome(name: String) {
        guard turns.isEmpty else { return }
        let who = name.isEmpty ? "Operator" : name
        rememberedCount = CoachMemoryStore.load().count
        turns = [
            CoachChatTurn(
                kind: .assistant,
                agent: .orchestrator,
                text: """
                \(who). Coach here (one voice; specialists stay backstage).
                Tell me habits like "I'm doing intermittent fasting" and I'll remember them on-device for diet tweaks.
                Dark humour included. Health stays on-device until you consent to Grok.
                """
            )
        ]
    }

    func send(brief: CoachBrief) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""

        for fact in CoachMemoryExtractor.extract(from: text) {
            CoachMemoryStore.remember(fact)
        }
        rememberedCount = CoachMemoryStore.load().count

        let briefWithMemory = CoachBrief(
            userName: brief.userName,
            diet: brief.diet,
            currentKg: brief.currentKg,
            idealKg: brief.idealKg,
            bodyFatPercent: brief.bodyFatPercent,
            idealBodyFatPercent: brief.idealBodyFatPercent,
            trend: brief.trend,
            weekDeltaKg: brief.weekDeltaKg,
            weeklyGoal: brief.weeklyGoal,
            personaBlock: brief.personaBlock,
            memoryBlock: CoachMemoryStore.promptBlock(),
            fitnessDigestBlock: brief.fitnessDigestBlock
        )

        turns.append(CoachChatTurn(kind: .user, text: text))
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
            brief: briefWithMemory,
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
            var finished = turns[idx]
            finished = CoachChatTurn(
                id: assistantID,
                kind: .assistant,
                agent: .orchestrator,
                text: finished.text,
                usedNetwork: finished.usedNetwork,
                isFailure: finished.isFailure,
                isStreaming: false
            )
            turns[idx] = finished
        }
    }
}
