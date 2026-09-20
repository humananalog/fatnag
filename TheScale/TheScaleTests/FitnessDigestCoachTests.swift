import XCTest
@testable import TheScale

final class FitnessDigestCoachTests: XCTestCase {
    func testPromptBlockIncludesLastWorkoutDetails() {
        let workout = HealthWorkoutSummary(
            activityName: "Strength training",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            durationMinutes: 60,
            distanceKm: nil,
            activeEnergyKcal: 320,
            sourceName: "Apple Watch"
        )
        var digest = FitnessDigest.empty
        digest.access = .readable
        digest.accessDetail = "ok"
        digest.stepsToday = 4_200
        digest.recentWorkouts = [workout]
        digest.workoutCountLast24h = 1

        let block = digest.promptBlock(preSleepWindowMinutes: 30)
        XCTAssertTrue(block.contains("Last workout: Strength training"))
        XCTAssertTrue(block.contains("320 kcal"))
        XCTAssertTrue(block.contains("Apple Watch"))
        XCTAssertTrue(block.contains("Never invent"))
        XCTAssertFalse(block.contains("\u{2014}"))
        XCTAssertFalse(block.contains("\u{2013}"))
    }

    func testPromptBlockIncludesHikeLikeWorkoutWithDistance() {
        let hike = HealthWorkoutSummary(
            activityName: "Hiking",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_010_800),
            durationMinutes: 180,
            distanceKm: 8.2,
            activeEnergyKcal: 710,
            sourceName: "AllTrails"
        )
        var digest = FitnessDigest.empty
        digest.access = .readable
        digest.accessDetail = "ok"
        digest.recentWorkouts = [hike]
        digest.workoutCountLast24h = 1
        digest.walkingRunningDistance = HealthDistanceSpike(
            distanceKmLast24h: 8.2,
            distanceKmLast7d: 12.0,
            isNotableSpike: true
        )

        let block = digest.promptBlock(preSleepWindowMinutes: 30)
        XCTAssertTrue(block.contains("Last workout: Hiking"))
        XCTAssertTrue(block.contains("8.2 km"))
        XCTAssertTrue(block.contains("AllTrails"))
        XCTAssertTrue(block.contains("710 kcal"))
        XCTAssertTrue(block.contains("Walking/running distance last 24h: 8.2 km"))
        XCTAssertFalse(block.contains("none in last 90 days"))
        XCTAssertTrue(digest.settingsStatusLine.contains("Hiking"))
        XCTAssertTrue(digest.settingsStatusLine.contains("8.2 km"))
    }

    func testPromptBlockSurfacesDistanceSpikeWithoutWorkout() {
        var digest = FitnessDigest.empty
        digest.access = .readable
        digest.accessDetail = "sheet done"
        digest.stepsToday = 12_000
        digest.recentWorkouts = []
        digest.walkingRunningDistance = HealthDistanceSpike(
            distanceKmLast24h: 8.0,
            distanceKmLast7d: 8.0,
            isNotableSpike: true
        )

        let block = digest.promptBlock(preSleepWindowMinutes: 30)
        XCTAssertTrue(block.contains("Recent workouts: none"))
        XCTAssertTrue(block.contains("Walking/running distance last 24h: 8.0 km"))
        XCTAssertTrue(block.contains("Distance spike without a Workout sample"))
        XCTAssertTrue(block.contains("AllTrails"))
        XCTAssertTrue(block.contains("never AllTrails directly") || block.contains("cannot read AllTrails"))
        XCTAssertTrue(digest.settingsStatusLine.contains("8.0 km"))
        XCTAssertTrue(digest.settingsStatusLine.lowercased().contains("alltrails")
            || digest.settingsStatusLine.lowercased().contains("third-party"))
        XCTAssertTrue(digest.hasAnyFitnessSignal)
    }

    func testPromptBlockHonestWhenEmptyReadable() {
        var digest = FitnessDigest.empty
        digest.access = .readable
        digest.accessDetail = "sheet done"
        let block = digest.promptBlock(preSleepWindowMinutes: 30)
        XCTAssertTrue(block.contains("Recent workouts: none"))
        XCTAssertTrue(block.contains("Samples: empty"))
        XCTAssertTrue(block.contains("third-party") || block.contains("AllTrails"))
        XCTAssertTrue(block.contains("Do not invent") || block.contains("Never invent"))
        XCTAssertTrue(digest.settingsStatusLine.lowercased().contains("no steps")
            || digest.settingsStatusLine.lowercased().contains("distance"))
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

    func testWalkingStoredAsWorkoutStillShowsDistance() {
        let walk = HealthWorkoutSummary(
            activityName: "Walking",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_007_200),
            durationMinutes: 120,
            distanceKm: 8.0,
            activeEnergyKcal: 480,
            sourceName: "Apple Watch"
        )
        var digest = FitnessDigest.empty
        digest.access = .readable
        digest.recentWorkouts = [walk]
        let line = walk.promptLine()
        XCTAssertTrue(line.contains("Walking"))
        XCTAssertTrue(line.contains("8.0 km"))
        XCTAssertTrue(digest.promptBlock(preSleepWindowMinutes: 30).contains("8.0 km"))
    }

    func testRouteActivityKeywordsToFitness() {
        XCTAssertEqual(GrokClient.route(userText: "What was my last activity?"), .fitness)
        XCTAssertEqual(GrokClient.route(userText: "what was my last workout?"), .fitness)
        XCTAssertEqual(GrokClient.route(userText: "How many steps today?"), .fitness)
        XCTAssertEqual(GrokClient.route(userText: "insights from my hike"), .fitness)
        XCTAssertEqual(GrokClient.route(userText: "8km outdoor walk"), .fitness)
        XCTAssertEqual(GrokClient.route(userText: "did AllTrails sync?"), .fitness)
    }

    func testDistanceSpikeFactory() {
        XCTAssertNil(HealthDistanceSpike.from(km24h: nil, km7d: nil))
        XCTAssertNil(HealthDistanceSpike.from(km24h: 0, km7d: 0))
        let spike = HealthDistanceSpike.from(km24h: 8, km7d: 10)
        XCTAssertEqual(spike?.distanceKmLast24h, 8)
        XCTAssertEqual(spike?.isNotableSpike, true)
        let small = HealthDistanceSpike.from(km24h: 1.5, km7d: 4)
        XCTAssertEqual(small?.isNotableSpike, false)
    }
}
