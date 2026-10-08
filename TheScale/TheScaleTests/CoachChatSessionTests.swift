import XCTest
@testable import TheScale

final class CoachChatSessionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CoachChatSessionStore.clearAll()
        UserDefaults.standard.removeObject(forKey: "thescale.coachChatHistory.v1")
    }

    override func tearDown() {
        CoachChatSessionStore.clearAll()
        super.tearDown()
    }

    func testCreateSessionHasSeparateMemory() {
        let a = CoachChatSessionStore.createSession(welcomeName: "Alex")
        var aMut = a
        aMut.memoryFacts = [CoachMemoryFact(text: "I do 16/8 fasting", tags: ["diet"])]
        CoachChatSessionStore.upsert(aMut)

        let b = CoachChatSessionStore.createSession(welcomeName: "Alex")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertTrue(b.memoryFacts.isEmpty)
        let reloadedA = CoachChatSessionStore.loadSessions().first(where: { $0.id == a.id })
        XCTAssertEqual(reloadedA?.memoryFacts.first?.text, "I do 16/8 fasting")
    }

    func testLegacyHistoryMigratesOnce() {
        let turns = [
            CoachChatTurn(kind: .user, text: "Hello keel"),
            CoachChatTurn(kind: .assistant, agent: .orchestrator, text: "Hey.")
        ]
        if let data = try? JSONEncoder().encode(turns) {
            UserDefaults.standard.set(data, forKey: "thescale.coachChatHistory.v1")
        }
        let sessions = CoachChatSessionStore.loadSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.turns.count, 2)
        XCTAssertEqual(sessions.first?.title, "Keel classic")
    }
}
