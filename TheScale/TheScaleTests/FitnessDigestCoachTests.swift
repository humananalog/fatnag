import XCTest
@testable import TheScale

final class FitnessDigestCoachTests: XCTestCase {
    func testPromptBlockIncludesLastWorkoutDetails() {
        let workout = HealthWorkoutSummary(
            activityName: "Strength training",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            durationMinutes: 60,
            activeEnergyKcal: 320,
            sourceName: "Apple Watch"
        )
        var digest = FitnessDigest.empty
        digest.access = .readable
        digest.accessDetail = "ok"
        digest.stepsToday = 4_200
        digest.lastWorkout = workout
        digest.workoutCountLast24h = 1

        let block = digest.promptBlock(preSleepWindowMinutes: 30)
        XCTAssertTrue(block.contains("Last workout: Strength training"))
        XCTAssertTrue(block.contains("320 kcal"))
        XCTAssertTrue(block.contains("Apple Watch"))
        XCTAssertTrue(block.contains("Never invent"))
        XCTAssertFalse(block.contains("\u{2014}"))
        XCTAssertFalse(block.contains("\u{2013}"))
    }

    func testPromptBlockHonestWhenEmptyReadable() {
        var digest = FitnessDigest.empty
        digest.access = .readable
        digest.accessDetail = "sheet done"
        let block = digest.promptBlock(preSleepWindowMinutes: 30)
        XCTAssertTrue(block.contains("Last workout: none"))
        XCTAssertTrue(block.contains("Samples: empty"))
        XCTAssertTrue(block.contains("Do not invent"))
        XCTAssertTrue(digest.settingsStatusLine.lowercased().contains("no steps"))
    }

    func testPromptBlockHonestWhenNotRequested() {
        var digest = FitnessDigest.empty
        digest.access = .notRequested
        digest.accessDetail = "not yet"
        let block = digest.promptBlock(preSleepWindowMinutes: 30)
        XCTAssertTrue(block.contains("Access: notRequested"))
        XCTAssertTrue(block.contains("Samples: unavailable"))
        XCTAssertFalse(block.contains("Steps today:"))
    }

    func testRouteActivityKeywordsToFitness() {
        XCTAssertEqual(GrokClient.route(userText: "What was my last activity?"), .fitness)
        XCTAssertEqual(GrokClient.route(userText: "what was my last workout?"), .fitness)
        XCTAssertEqual(GrokClient.route(userText: "How many steps today?"), .fitness)
    }
}
