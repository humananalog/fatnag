import XCTest
@testable import TheScale

final class MorningWeighDrillSchedulerTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        return cal
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps)!
    }

    func testFallbackSchedulesTodayWhenStillBeforeClock() {
        let now = date(year: 2026, month: 9, day: 23, hour: 6, minute: 0)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 7,
            minute: 30,
            alreadyWeighedToday: false,
            alreadyFiredToday: false,
            now: now,
            calendar: calendar
        )
        let comps = calendar.dateComponents([.day, .hour, .minute], from: fire)
        XCTAssertEqual(comps.day, 23)
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 30)
    }

    func testFallbackRollsTomorrowWhenPastClock() {
        let now = date(year: 2026, month: 9, day: 23, hour: 8, minute: 0)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 7,
            minute: 30,
            alreadyWeighedToday: false,
            alreadyFiredToday: false,
            now: now,
            calendar: calendar
        )
        let comps = calendar.dateComponents([.day, .hour, .minute], from: fire)
        XCTAssertEqual(comps.day, 24)
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 30)
    }

    func testFallbackRollsTomorrowWhenPastNine() {
        let now = date(year: 2026, month: 9, day: 23, hour: 9, minute: 5)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 7,
            minute: 30,
            alreadyWeighedToday: false,
            alreadyFiredToday: false,
            now: now,
            calendar: calendar
        )
        let comps = calendar.dateComponents([.day, .hour], from: fire)
        XCTAssertEqual(comps.day, 24)
        XCTAssertEqual(comps.hour, 7)
    }

    func testFallbackClampsHourAtOrAfterNineToBeforeNine() {
        let now = date(year: 2026, month: 9, day: 23, hour: 6, minute: 0)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 10,
            minute: 0,
            alreadyWeighedToday: false,
            alreadyFiredToday: false,
            now: now,
            calendar: calendar
        )
        let comps = calendar.dateComponents([.day, .hour, .minute], from: fire)
        XCTAssertEqual(comps.day, 23)
        XCTAssertEqual(comps.hour, 8)
        XCTAssertEqual(comps.minute, 59)
    }

    func testFallbackRollsTomorrowWhenAlreadyWeighed() {
        let now = date(year: 2026, month: 9, day: 23, hour: 6, minute: 0)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 7,
            minute: 30,
            alreadyWeighedToday: true,
            alreadyFiredToday: false,
            now: now,
            calendar: calendar
        )
        let comps = calendar.dateComponents([.day, .hour], from: fire)
        XCTAssertEqual(comps.day, 24)
        XCTAssertEqual(comps.hour, 7)
    }

    func testFallbackRollsTomorrowWhenAlreadyFired() {
        let now = date(year: 2026, month: 9, day: 23, hour: 6, minute: 0)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 7,
            minute: 30,
            alreadyWeighedToday: false,
            alreadyFiredToday: true,
            now: now,
            calendar: calendar
        )
        let comps = calendar.dateComponents([.day], from: fire)
        XCTAssertEqual(comps.day, 24)
    }

    func testPendingFireMatchesIntended() {
        let intended = date(year: 2026, month: 9, day: 24, hour: 7, minute: 30)
        XCTAssertTrue(
            MorningWeighDrillScheduler.pendingFireMatchesIntended(
                pending: intended.addingTimeInterval(5),
                intended: intended
            )
        )
        XCTAssertFalse(
            MorningWeighDrillScheduler.pendingFireMatchesIntended(
                pending: intended.addingTimeInterval(120),
                intended: intended
            )
        )
        XCTAssertFalse(
            MorningWeighDrillScheduler.pendingFireMatchesIntended(pending: nil, intended: intended)
        )
    }

    func testFallbackPastNineUsesTomorrowLocalMorning() {
        // 21:46 HKT on Sep 23 → next slot is Sep 24 07:30 HKT (= Sep 23 23:30 UTC).
        let now = date(year: 2026, month: 9, day: 23, hour: 21, minute: 46)
        let fire = MorningWeighDrillScheduler.nextFallbackFireDate(
            hour: 7,
            minute: 30,
            alreadyWeighedToday: false,
            alreadyFiredToday: false,
            now: now,
            calendar: calendar,
            forceTomorrow: true
        )
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        XCTAssertEqual(comps.day, 24)
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 30)
        // Absolute instant must be 2026-09-23 23:30 UTC when TZ is HKT.
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let utc = utcCal.dateComponents([.day, .hour, .minute], from: fire)
        XCTAssertEqual(utc.day, 23)
        XCTAssertEqual(utc.hour, 23)
        XCTAssertEqual(utc.minute, 30)
    }

    func testDetectWeighInTodayFromRecentHealth() {
        let now = date(year: 2026, month: 9, day: 23, hour: 10, minute: 0)
        let sample = HealthWeightSample(id: UUID(), weightKg: 80, date: now)
        XCTAssertTrue(
            ScaleSessionViewModel.detectWeighInToday(
                historyWeights: [],
                trendWeights: [],
                recentWeights: [sample],
                now: now,
                calendar: calendar
            )
        )
        let yesterday = date(year: 2026, month: 9, day: 22, hour: 8, minute: 0)
        let old = HealthWeightSample(id: UUID(), weightKg: 80, date: yesterday)
        XCTAssertFalse(
            ScaleSessionViewModel.detectWeighInToday(
                historyWeights: [],
                trendWeights: [],
                recentWeights: [old],
                now: now,
                calendar: calendar
            )
        )
    }

    func testNotificationPreferencesDefaultMorningDrillOn() {
        let prefs = NotificationPreferences.default
        XCTAssertTrue(prefs.morningWeighDrill)
        XCTAssertTrue(prefs.notifyOnBadTrend)
        XCTAssertTrue(prefs.weeklyGoalReminders)
        XCTAssertEqual(prefs.morningWeighFallbackHour, 7)
        XCTAssertEqual(prefs.morningWeighFallbackMinute, 30)
    }

    func testNotificationPreferencesDecodesMissingFallbackKeys() throws {
        let json = """
        {"notifyOnBadTrend":true,"weeklyGoalReminders":true,"morningWeighDrill":true}
        """.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(NotificationPreferences.self, from: json)
        XCTAssertEqual(prefs.morningWeighFallbackHour, 7)
        XCTAssertEqual(prefs.morningWeighFallbackMinute, 30)
        XCTAssertTrue(prefs.morningWeighDrill)
    }
}

final class ProfileNumericBoundsTests: XCTestCase {
    func testAgeClamp() {
        XCTAssertEqual(ProfileNumericBounds.clampAgeYears(17).value, 18)
        XCTAssertEqual(ProfileNumericBounds.clampAgeYears(101).value, 100)
        XCTAssertFalse(ProfileNumericBounds.clampAgeYears(30).didClamp)
    }

    func testHeightClamp() {
        XCTAssertEqual(ProfileNumericBounds.clampHeightCm(90).value, 120, accuracy: 0.01)
        XCTAssertEqual(ProfileNumericBounds.clampHeightCm(300).value, 250, accuracy: 0.01)
    }

    func testWeightClamp() {
        XCTAssertEqual(ProfileNumericBounds.clampWeightKg(10).value, 30, accuracy: 0.01)
        XCTAssertEqual(ProfileNumericBounds.clampWeightKg(400).value, 300, accuracy: 0.01)
    }

    func testBodyFatOptional() {
        XCTAssertNil(ProfileNumericBounds.clampOptionalBodyFatPercent(nil).value)
        XCTAssertNil(ProfileNumericBounds.clampOptionalBodyFatPercent(0).value)
        XCTAssertEqual(ProfileNumericBounds.clampOptionalBodyFatPercent(18).value ?? -1, 18, accuracy: 0.01)
        let high = ProfileNumericBounds.clampOptionalBodyFatPercent(90)
        XCTAssertEqual(high.value ?? -1, 60, accuracy: 0.01)
        XCTAssertNotNil(high.message)
    }

    func testMorningFallbackClamp() {
        let late = ProfileNumericBounds.clampMorningFallback(hour: 10, minute: 0)
        XCTAssertEqual(late.hour, 8)
        XCTAssertEqual(late.minute, 59)
        let ok = ProfileNumericBounds.clampMorningFallback(hour: 7, minute: 30)
        XCTAssertEqual(ok.hour, 7)
        XCTAssertEqual(ok.minute, 30)
    }
}
