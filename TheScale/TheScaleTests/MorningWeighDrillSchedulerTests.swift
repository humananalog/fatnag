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
        let now = date(year: 2026, month: 9, day: 23, hour: 9, minute: 0)
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
