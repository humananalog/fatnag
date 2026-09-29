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

    func testSleepRewardNamesTheHours() {
        var digest = FitnessDigest.empty
        digest.sleepHoursLastNight = 7.6
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 8))!
        let pulse = ActivityPulseAnalyzer.evaluate(
            digest: digest,
            profileName: "Alex",
            now: now,
            calendar: cal
        )
        XCTAssertEqual(pulse?.tone, .reward)
        XCTAssertEqual(pulse?.id, "sleep-2026-09-29-banked")
        XCTAssertTrue(pulse?.phoneBody.contains("7.6") == true)
    }

    func testShortSleepIsAPunishment() {
        var digest = FitnessDigest.empty
        digest.sleepHoursLastNight = 4.2
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 7))!
        let pulse = ActivityPulseAnalyzer.evaluate(
            digest: digest,
            profileName: "Alex",
            sex: .female,
            now: now,
            calendar: cal
        )
        XCTAssertEqual(pulse?.tone, .punishment)
        XCTAssertEqual(pulse?.glanceTitle, "Short sleep")
    }

    func testStepMilestoneAndQuietDigest() {
        var digest = FitnessDigest.empty
        digest.stepsToday = 10_240
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 16))!
        let pulse = ActivityPulseAnalyzer.evaluate(
            digest: digest,
            profileName: "Alex",
            now: now,
            calendar: cal
        )
        XCTAssertEqual(pulse?.tone, .reward)
        XCTAssertEqual(pulse?.id, "steps-2026-09-29-10000")
        XCTAssertNil(ActivityPulseAnalyzer.evaluate(digest: .empty, profileName: "Alex", now: now, calendar: cal))
    }

    func testEveningSoftStepsAreAPunishment() {
        var digest = FitnessDigest.empty
        digest.stepsToday = 800
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 19))!
        let pulse = ActivityPulseAnalyzer.evaluate(
            digest: digest,
            profileName: "Alex",
            now: now,
            calendar: cal
        )
        XCTAssertEqual(pulse?.tone, .punishment)
        XCTAssertEqual(pulse?.id, "steps-low-2026-09-29")
    }

    func testPulseDoesNotRepeatTheSameBeat() {
        let pulse = ActivityPulse(
            id: "joke-1",
            tone: .joke,
            isStrong: false,
            glanceTitle: "Still moving",
            glanceLine: "2,000 steps",
            phoneBody: "Keep walking."
        )
        let now = Date()
        XCTAssertFalse(ActivityPulseAnalyzer.shouldDeliver(pulse: pulse, lastId: pulse.id, lastAt: nil, now: now))
        XCTAssertFalse(ActivityPulseAnalyzer.shouldDeliver(
            pulse: pulse,
            lastId: "other",
            lastAt: now.addingTimeInterval(-60),
            now: now
        ))
        XCTAssertTrue(ActivityPulseAnalyzer.shouldDeliver(
            pulse: pulse,
            lastId: "other",
            lastAt: now.addingTimeInterval(-50 * 60),
            now: now
        ))
    }

    func testTenMinuteModeDoesNotCallGrokEveryTenMinutes() {
        var prefs = FitnessMonitorPreferences.default
        prefs.enabled = true
        prefs.interval = .every10Minutes
        prefs.lastAutomatedCheckAt = Date().addingTimeInterval(-30 * 60)
        XCTAssertFalse(FitnessTriggerMonitor.isAutomatedCheckDue(prefs: prefs))
        prefs.lastAutomatedCheckAt = Date().addingTimeInterval(-7 * 3600)
        XCTAssertTrue(FitnessTriggerMonitor.isAutomatedCheckDue(prefs: prefs))
    }

    func testActivityPulseIsSignedNag() {
        let pulse = ActivityPulse(
            id: "sleep-test",
            tone: .reward,
            isStrong: true,
            glanceTitle: "Sleep banked",
            glanceLine: "7.6h last night",
            phoneBody: "7.6 hours in the bank. Reward accepted."
        )
        let content = ScaleNotificationContentFactory.make(
            ScaleNotificationCopy.activityPulse(pulse, profileName: "Alex")
        )
        XCTAssertEqual(content.title, "Nag")
        XCTAssertEqual(content.subtitle, "Sleep banked")
        XCTAssertTrue(content.body.contains("Alex"))
        XCTAssertEqual(
            content.userInfo[ScaleNotificationUserInfoKey.kind] as? String,
            ScaleNotificationKind.nag.rawValue
        )
        XCTAssertEqual(content.threadIdentifier, "thescale.nag")
        XCTAssertEqual(content.categoryIdentifier, ScaleNotificationCategoryID.nag)
        XCTAssertEqual(content.interruptionLevel, .active)
        XCTAssertNotNil(content.sound)
        XCTAssertEqual(
            content.userInfo[ScaleNotificationUserInfoKey.destination] as? String,
            ScaleNotificationDestination.progress.rawValue
        )
    }

    func testNagDestinationsFollowTone() {
        XCTAssertEqual(
            ScaleNotificationCopy.destination(for: ActivityPulse(
                id: "greet-1", tone: .greeting, isStrong: false,
                glanceTitle: "Morning", glanceLine: "Up", phoneBody: "Weigh"
            )),
            .weigh
        )
        XCTAssertEqual(
            ScaleNotificationCopy.destination(for: ActivityPulse(
                id: "steps-low-1", tone: .punishment, isStrong: true,
                glanceTitle: "Soft", glanceLine: "800", phoneBody: "Walk"
            )),
            .progress
        )
        XCTAssertEqual(
            ScaleNotificationCopy.destination(for: ActivityPulse(
                id: "workout-1", tone: .reward, isStrong: true,
                glanceTitle: "Banked", glanceLine: "Run", phoneBody: "Eat"
            )),
            .meals
        )
        XCTAssertEqual(
            ScaleNotificationCopy.destination(for: ActivityPulse(
                id: "joke-1", tone: .joke, isStrong: false,
                glanceTitle: "Moving", glanceLine: "2k", phoneBody: "Ha"
            )),
            .coach
        )
        XCTAssertEqual(ScaleNotificationKind.morningWeigh.destination, .weigh)
        XCTAssertEqual(ScaleNotificationKind.weeklyGoal.destination, .progress)
        XCTAssertEqual(ScaleNotificationKind.badTrend.destination, .history)
    }

    func testAcknowledgedAlertLeavesTheActiveInbox() {
        let fired = Date(timeIntervalSince1970: 1_758_000_000)
        let archive = [
            ArchivedAlert(
                id: "a",
                requestId: "thescale.activity-pulse",
                title: "Nag",
                body: "Sleep banked",
                deliveredAt: fired,
                acknowledgedAt: fired.addingTimeInterval(30)
            )
        ]
        XCTAssertTrue(NotificationArchiveStore.isAcknowledged(
            requestId: "thescale.activity-pulse",
            deliveredAt: fired.addingTimeInterval(0.4),
            in: archive
        ))
        XCTAssertFalse(NotificationArchiveStore.isAcknowledged(
            requestId: "thescale.activity-pulse",
            deliveredAt: fired.addingTimeInterval(4 * 3600),
            in: archive
        ))
        XCTAssertFalse(NotificationArchiveStore.isAcknowledged(
            requestId: "thescale.morning-weigh",
            deliveredAt: fired,
            in: archive
        ))
    }

    func testDeleteDropsOnlyThatArchivedAlert() {
        let kept = ArchivedAlert(
            id: "keep",
            requestId: "thescale.activity-pulse",
            title: "Nag",
            body: "Still here",
            deliveredAt: Date(timeIntervalSince1970: 10),
            acknowledgedAt: Date(timeIntervalSince1970: 20)
        )
        let gone = ArchivedAlert(
            id: "gone",
            requestId: "thescale.morning",
            title: "Weigh now",
            body: "Morning",
            deliveredAt: Date(timeIntervalSince1970: 30),
            acknowledgedAt: Date(timeIntervalSince1970: 40)
        )
        let left = NotificationArchiveStore.removing(id: "gone", from: [kept, gone])
        XCTAssertEqual(left.map(\.id), ["keep"])
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
