import XCTest
@testable import TheScale

final class CoachReminderTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        return cal
    }

    /// Saturday 19 Sep 2026 21:00 HKT
    private var now: Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 9
        comps.day = 19
        comps.hour = 21
        comps.minute = 0
        return calendar.date(from: comps)!
    }

    func testExtractsTomorrowMorningBefore730AsWakeAt715() {
        let text = "send me a notification tomorrow morning before 7:30 am to remind me to wake up"
        let req = CoachReminderExtractor.extract(from: text, now: now, calendar: calendar)
        XCTAssertNotNil(req)
        guard let req else { return }
        XCTAssertEqual(req.kind, .wakeUp)

        let fire = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: req.fireAt)
        XCTAssertEqual(fire.year, 2026)
        XCTAssertEqual(fire.month, 9)
        XCTAssertEqual(fire.day, 20)
        XCTAssertEqual(fire.hour, 7)
        XCTAssertEqual(fire.minute, 15)

        XCTAssertNotNil(req.beforeDeadline)
        let deadline = calendar.dateComponents([.hour, .minute], from: req.beforeDeadline!)
        XCTAssertEqual(deadline.hour, 7)
        XCTAssertEqual(deadline.minute, 30)
    }

    func testExtractsAt730WithoutBefore() {
        let text = "remind me to wake up tomorrow at 7:30am"
        let req = CoachReminderExtractor.extract(from: text, now: now, calendar: calendar)
        XCTAssertNotNil(req)
        guard let req else { return }
        let fire = calendar.dateComponents([.hour, .minute, .day], from: req.fireAt)
        XCTAssertEqual(fire.day, 20)
        XCTAssertEqual(fire.hour, 7)
        XCTAssertEqual(fire.minute, 30)
        XCTAssertNil(req.beforeDeadline)
    }

    func testIgnoresNonReminderChat() {
        let req = CoachReminderExtractor.extract(
            from: "how is my weight trend this week",
            now: now,
            calendar: calendar
        )
        XCTAssertNil(req)
    }

    func testMorningDefaultWithoutClock() {
        let text = "ping me tomorrow morning to wake me up"
        let req = CoachReminderExtractor.extract(from: text, now: now, calendar: calendar)
        XCTAssertNotNil(req)
        guard let req else { return }
        let fire = calendar.dateComponents([.day, .hour, .minute], from: req.fireAt)
        XCTAssertEqual(fire.day, 20)
        XCTAssertEqual(fire.hour, 7)
        XCTAssertEqual(fire.minute, 0)
    }
}
