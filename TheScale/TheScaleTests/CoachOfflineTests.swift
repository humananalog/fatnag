import XCTest
@testable import TheScale

final class CoachOfflineTests: XCTestCase {
    func testOfflineOrchestratorUsesName() {
        let brief = CoachBrief(
            userName: "Alex",
            diet: .omnivore,
            currentKg: 78,
            idealKg: 75,
            bodyFatPercent: 18,
            idealBodyFatPercent: 15,
            trend: .gain(deltaKg: 0.4),
            weekDeltaKg: 0.5,
            weeklyGoal: .default
        )
        let reply = CoachOfflineFallback.reply(role: .orchestrator, brief: brief)
        XCTAssertTrue(reply.text.contains("Alex"))
        XCTAssertFalse(reply.usedNetwork)
        XCTAssertTrue(reply.disclaimer.lowercased().contains("not medical"))
    }

    func testBadTrendReasonFiresOnGainAboveIdeal() {
        let day: TimeInterval = 86_400
        let samples = [
            HealthMetricSample(value: 76, date: Date(timeIntervalSince1970: 0)),
            HealthMetricSample(value: 77, date: Date(timeIntervalSince1970: day * 3)),
            HealthMetricSample(value: 78.2, date: Date(timeIntervalSince1970: day * 6))
        ]
        // Shift samples to "now"
        let now = Date()
        let recent = samples.map {
            HealthMetricSample(value: $0.value, date: now.addingTimeInterval($0.date.timeIntervalSince1970 - day * 6))
        }
        let reason = TrendNotificationScheduler.badTrendReason(
            currentKg: 78.2,
            idealKg: 75,
            recent: recent
        )
        XCTAssertNotNil(reason)
    }

    func testBadTrendQuietWhenNearIdeal() {
        let now = Date()
        let recent = [
            HealthMetricSample(value: 75.1, date: now.addingTimeInterval(-3 * 86_400)),
            HealthMetricSample(value: 75.2, date: now)
        ]
        let reason = TrendNotificationScheduler.badTrendReason(
            currentKg: 75.2,
            idealKg: 75,
            recent: recent
        )
        XCTAssertNil(reason)
    }

    func testProfileNameAndDietMigrate() throws {
        let legacy = """
        {"heightCm":180,"ageYears":40,"sex":"male"}
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(UserBodyProfile.self, from: legacy)
        XCTAssertEqual(profile.displayName, "")
        XCTAssertEqual(profile.dietPreference, .omnivore)
    }

    func testWeeklyGoalProgress() {
        var goal = WeeklyMiniGoal.default
        goal.weekStartKg = 80
        goal.targetDeltaKg = -0.5
        let fraction = try XCTUnwrap(goal.progressFraction(currentKg: 79.75))
        XCTAssertEqual(fraction, 0.5, accuracy: 0.01)
    }

    func testRatePerWeek() throws {
        let day: TimeInterval = 86_400
        let samples = [
            HealthMetricSample(value: 80, date: Date(timeIntervalSince1970: 0)),
            HealthMetricSample(value: 79, date: Date(timeIntervalSince1970: day * 7))
        ]
        let rate = try XCTUnwrap(HealthChartMath.ratePerWeek(samples: samples))
        XCTAssertEqual(rate, -1.0, accuracy: 0.05)
    }
}
