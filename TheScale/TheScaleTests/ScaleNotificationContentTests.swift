import XCTest
@testable import TheScale
import UserNotifications

final class ScaleNotificationContentTests: XCTestCase {
    func testSampleContentHasHierarchyCategoryAndThread() {
        let content = ScaleNotificationContentFactory.makeSample(
            profileName: "Alex",
            currentKg: 82.4
        )
        XCTAssertTrue(content.title.contains("Alex"))
        XCTAssertFalse(content.subtitle.isEmpty)
        XCTAssertFalse(content.body.isEmpty)
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
            .init(
                kind: .coachWake,
                title: "Alex: wake up",
                subtitle: "Before 7:30",
                body: "Up before 7:30. Open FATNAG when you're ready."
            )
        )
        XCTAssertEqual(content.interruptionLevel, .timeSensitive)
        XCTAssertEqual(content.categoryIdentifier, ScaleNotificationCategoryID.coachReminder)
        XCTAssertEqual(content.threadIdentifier, "thescale.coach")
        XCTAssertGreaterThan(content.relevanceScore, 0.9)
    }

    func testIntervalIsPassiveNoSound() {
        let content = ScaleNotificationContentFactory.make(
            .init(
                kind: .fitnessInterval,
                title: "Alex: fitness check",
                subtitle: "Every 12 hours",
                body: "Open Coach for the digest."
            )
        )
        XCTAssertEqual(content.interruptionLevel, .passive)
        XCTAssertNil(content.sound)
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
}
