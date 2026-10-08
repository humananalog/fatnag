import Foundation

/// One Keel chat thread with its own transcript + on-device memory facts.
struct CoachChatSession: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var turns: [CoachChatTurn]
    var memoryFacts: [CoachMemoryFact]
    /// True after a funny auto-title lands (or user renamed).
    var titleIsCustom: Bool

    init(
        id: UUID = UUID(),
        title: String = "New nag",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        turns: [CoachChatTurn] = [],
        memoryFacts: [CoachMemoryFact] = [],
        titleIsCustom: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.turns = turns
        self.memoryFacts = memoryFacts
        self.titleIsCustom = titleIsCustom
    }

    func promptMemoryBlock(limit: Int = 12) -> String {
        let facts = memoryFacts.suffix(limit)
        guard !facts.isEmpty else { return "" }
        let lines = facts.map { "- \($0.text)" }
        return """
        Remembered user facts for THIS chat only (on-device; honour these):
        \(lines.joined(separator: "\n"))
        """
    }
}

/// Multi-session chat archive. Migrates legacy single-transcript + global memory once.
enum CoachChatSessionStore {
    private static let sessionsKey = "thescale.coachChatSessions.v1"
    private static let activeKey = "thescale.coachChatActiveSession.v1"
    private static let legacyHistoryKey = "thescale.coachChatHistory.v1"
    private static let maxSessions = 40
    private static let maxTurnsPerSession = 80
    private static let maxFactsPerSession = 40

    static func loadSessions() -> [CoachChatSession] {
        migrateLegacyIfNeeded()
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              var sessions = try? JSONDecoder().decode([CoachChatSession].self, from: data)
        else {
            return []
        }
        sessions = sessions.map { session in
            var s = session
            s.turns = s.turns.filter { shouldPersistTurn($0) }
            return s
        }
        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func saveSessions(_ sessions: [CoachChatSession]) {
        let cleaned = sessions
            .map { session -> CoachChatSession in
                var s = session
                s.turns = Array(s.turns.filter { shouldPersistTurn($0) }.suffix(maxTurnsPerSession))
                s.memoryFacts = Array(s.memoryFacts.suffix(maxFactsPerSession))
                return s
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxSessions)
        if let data = try? JSONEncoder().encode(Array(cleaned)) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }

    static func activeSessionID() -> UUID? {
        migrateLegacyIfNeeded()
        guard let raw = UserDefaults.standard.string(forKey: activeKey) else { return nil }
        return UUID(uuidString: raw)
    }

    static func setActiveSessionID(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: activeKey)
    }

    @discardableResult
    static func ensureActiveSession() -> CoachChatSession {
        var sessions = loadSessions()
        if let id = activeSessionID(), let existing = sessions.first(where: { $0.id == id }) {
            return existing
        }
        if let newest = sessions.first {
            setActiveSessionID(newest.id)
            return newest
        }
        let fresh = CoachChatSession()
        sessions.insert(fresh, at: 0)
        saveSessions(sessions)
        setActiveSessionID(fresh.id)
        return fresh
    }

    @discardableResult
    static func createSession(welcomeName: String) -> CoachChatSession {
        let who = welcomeName.isEmpty ? "Operator" : welcomeName
        var session = CoachChatSession(
            title: "New nag",
            turns: [
                CoachChatTurn(
                    kind: .assistant,
                    agent: .orchestrator,
                    text: "\(who). What's the play?"
                )
            ]
        )
        var sessions = loadSessions()
        sessions.insert(session, at: 0)
        saveSessions(sessions)
        setActiveSessionID(session.id)
        return session
    }

    static func upsert(_ session: CoachChatSession) {
        var sessions = loadSessions()
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
        saveSessions(sessions)
        setActiveSessionID(session.id)
    }

    static func deleteSession(id: UUID) {
        var sessions = loadSessions().filter { $0.id != id }
        if sessions.isEmpty {
            let fresh = CoachChatSession()
            sessions = [fresh]
            setActiveSessionID(fresh.id)
        } else if activeSessionID() == id {
            setActiveSessionID(sessions[0].id)
        }
        saveSessions(sessions)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: sessionsKey)
        UserDefaults.standard.removeObject(forKey: activeKey)
        UserDefaults.standard.removeObject(forKey: legacyHistoryKey)
    }

    /// Compact memory for the active session (chat path). Falls back to global store if empty.
    static func activePromptMemoryBlock(limit: Int = 12) -> String {
        let session = ensureActiveSession()
        let local = session.promptMemoryBlock(limit: limit)
        if !local.isEmpty { return local }
        return CoachMemoryStore.promptBlock(limit: limit)
    }

    private static func shouldPersistTurn(_ turn: CoachChatTurn) -> Bool {
        if turn.isStreaming { return false }
        if turn.kind == .assistant && turn.text.isEmpty { return false }
        if turn.isFailure && !turn.isQuotaLock { return false }
        return true
    }

    private static func migrateLegacyIfNeeded() {
        if UserDefaults.standard.data(forKey: sessionsKey) != nil { return }

        let legacyTurns: [CoachChatTurn] = {
            guard let data = UserDefaults.standard.data(forKey: legacyHistoryKey),
                  let turns = try? JSONDecoder().decode([CoachChatTurn].self, from: data)
            else { return [] }
            return turns.filter { shouldPersistTurn($0) }
        }()
        let globalMemory = CoachMemoryStore.load()

        if legacyTurns.isEmpty && globalMemory.isEmpty {
            let fresh = CoachChatSession()
            saveSessions([fresh])
            setActiveSessionID(fresh.id)
            return
        }

        let migrated = CoachChatSession(
            title: "Keel classic",
            createdAt: legacyTurns.first?.createdAt ?? Date(),
            updatedAt: legacyTurns.last?.createdAt ?? Date(),
            turns: legacyTurns,
            memoryFacts: globalMemory,
            titleIsCustom: true
        )
        saveSessions([migrated])
        setActiveSessionID(migrated.id)
        // Keep legacy key until erase; active path is sessions.
    }
}

/// Back-compat shim used by GDPR erase / older call sites.
enum CoachChatHistoryStore {
    static func load() -> [CoachChatTurn] {
        CoachChatSessionStore.ensureActiveSession().turns
    }

    static func save(_ turns: [CoachChatTurn]) {
        var session = CoachChatSessionStore.ensureActiveSession()
        session.turns = turns
        session.updatedAt = Date()
        CoachChatSessionStore.upsert(session)
    }

    static func clear() {
        CoachChatSessionStore.clearAll()
    }
}
