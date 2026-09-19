import Foundation

struct CoachChatTurn: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let kind: Kind
    let agent: CoachAgentRole?
    let text: String
    let usedNetwork: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        agent: CoachAgentRole? = nil,
        text: String,
        usedNetwork: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.agent = agent
        self.text = text
        self.usedNetwork = usedNetwork
        self.createdAt = createdAt
    }
}

@MainActor
final class CoachChatController: ObservableObject {
    @Published private(set) var turns: [CoachChatTurn] = []
    @Published var draft = ""
    @Published var selectedAgent: CoachAgentRole = .orchestrator
    @Published var autoRoute = true
    @Published private(set) var isSending = false

    func seedWelcome(name: String) {
        guard turns.isEmpty else { return }
        let who = name.isEmpty ? "Operator" : name
        turns = [
            CoachChatTurn(
                kind: .assistant,
                agent: .orchestrator,
                text: """
                \(who). Orchestrator here.
                Tap Med / Fit / Anat or leave Auto-route on. Dark humour included; reckless medical advice is not.
                Health stays on-device. Grok only sees this chat (+ a short trend snapshot) after consent.
                """
            )
        ]
    }

    func send(brief: CoachBrief) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        let role = autoRoute ? GrokClient.route(userText: text) : selectedAgent
        selectedAgent = role
        turns.append(CoachChatTurn(kind: .user, text: text))
        isSending = true
        defer { isSending = false }

        let reply = await GrokClient.shared.chat(
            role: role,
            userText: text,
            brief: brief,
            history: turns
        )
        turns.append(
            CoachChatTurn(
                kind: .assistant,
                agent: role,
                text: reply.text,
                usedNetwork: reply.usedNetwork
            )
        )
    }
}
