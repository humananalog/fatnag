import XCTest
@testable import TheScale
import UserNotifications

final class ScaleNotificationContentTests: XCTestCase {
    func testSampleContentHasHierarchyCategoryAndThread() {
        let content = ScaleNotificationContentFactory.makeSample(
            profileName: "Alex",
            currentKg: 82.4
        )
        XCTAssertEqual(content.title, "Sample ping")
        XCTAssertFalse(content.subtitle.isEmpty)
        XCTAssertTrue(content.body.contains("Alex"))
        XCTAssertEqual(content.categoryIdentifier, ScaleNotificationCategoryID.sample)
        XCTAssertEqual(content.threadIdentifier, "thescale.sample")
        XCTAssertEqual(
            content.userInfo[ScaleNotificationUserInfoKey.destination] as? String,
            ScaleNotificationDestination.coach.rawValue
        )
        XCTAssertFalse(content.body.contains("—"))
        XCTAssertFalse(content.body.lowercased().contains("not a substitute"))
    }

    func testWakeUsesTimeSensitiveAndCoachCategory() {
        let content = ScaleNotificationContentFactory.make(
            ScaleNotificationCopy.coachWake(profileName: "Alex", beforeDeadline: nil)
        )
        XCTAssertEqual(content.interruptionLevel, .timeSensitive)
        XCTAssertEqual(content.categoryIdentifier, ScaleNotificationCategoryID.coachReminder)
        XCTAssertEqual(content.threadIdentifier, "thescale.coach")
        XCTAssertEqual(content.title, "Wake up")
        XCTAssertLessThanOrEqual(content.title.count, 22)
        XCTAssertGreaterThan(content.relevanceScore, 0.9)
    }

    func testIntervalIsPassiveNoSound() {
        let content = ScaleNotificationContentFactory.make(
            ScaleNotificationCopy.fitnessInterval(
                profileName: "Alex",
                intervalTitle: "Every 12 hours"
            )
        )
        XCTAssertEqual(content.interruptionLevel, .passive)
        XCTAssertNil(content.sound)
        XCTAssertEqual(content.title, "Coach check")
    }

    func testGlanceSanitizeStripsEmojiAndNamePrefix() {
        let cleaned = ScaleNotificationCopy.glanceSanitize("Alex: Keel · 💩 drill")
        XCTAssertFalse(cleaned.contains("💩"))
        XCTAssertFalse(cleaned.hasPrefix("Alex"))
        XCTAssertLessThanOrEqual(cleaned.count, 22)
    }

    func testBadTrendMomentIsMetricFirst() {
        let moment = ScaleNotificationCopy.badTrend(
            profileName: "Alex",
            currentKg: 81.0,
            idealKg: 75.0,
            reason: "Up +0.6 kg this week and still above ideal."
        )
        let content = ScaleNotificationContentFactory.make(moment)
        XCTAssertTrue(content.title.contains("81") || content.title.lowercased().contains("kg"))
        XCTAssertTrue(content.body.contains("Alex"))
        XCTAssertEqual(content.categoryIdentifier, ScaleNotificationCategoryID.badTrend)
    }

    func testVisualPNGRenders() {
        let data = ScaleNotificationVisuals.renderPNG(
            style: .trendUp,
            headline: "82.4 kg",
            detail: "+0.6 this week"
        )
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 500)
    }

    func testBadTrendReasonIncludesKg() {
        let now = Date()
        let recent = [
            HealthMetricSample(value: 80.0, date: now.addingTimeInterval(-6 * 86_400)),
            HealthMetricSample(value: 81.0, date: now)
        ]
        let reason = TrendNotificationScheduler.badTrendReason(
            currentKg: 81.0,
            idealKg: 75.0,
            recent: recent
        )
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("kg") == true)
    }

    func testFirstGlancePhrasePullsMassToken() {
        let phrase = ScaleNotificationCopy.firstGlancePhrase(
            from: "You're up +0.6 kg this week. Keep dinner tight."
        )
        XCTAssertNotNil(phrase)
        XCTAssertTrue(phrase?.contains("0.6") == true)
    }
}
