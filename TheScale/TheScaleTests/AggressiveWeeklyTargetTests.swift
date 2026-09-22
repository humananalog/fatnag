import XCTest
@testable import TheScale

final class AggressiveWeeklyTargetTests: XCTestCase {
    func testAggressiveUsesSafeCapNotSofterCalendar() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 8))!
        // 12 weeks to goal: 84 → 80 = -0.33/wk calendar, but safe ~0.59 → push hard.
        let goalDate = cal.date(from: DateComponents(year: 2026, month: 12, day: 14))!
        let hit = AggressiveWeeklyTargetEngine.compute(
            currentKg: 84,
            idealKg: 80,
            goalDate: goalDate,
            priorSundayTargetKg: nil,
            fallbackWeeklyDeltaKg: -0.3,
            now: now,
            calendar: cal
        )
        let safe = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: 84)
        let expected = (safe * 100).rounded() / 100
        XCTAssertEqual(hit.weeklyDeltaKg, -expected, accuracy: 0.02)
        XCTAssertEqual(hit.mode, .aggressive)
        XCTAssertFalse(hit.pacingLine.contains("—"))
    }

    func testMissedLastWeekHardcoreCatchUp() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 8))!
        let goalDate = cal.date(from: DateComponents(year: 2026, month: 12, day: 14))!
        // Prior Sunday wanted 83.4; still at 84.0 → missed by 0.6.
        let hit = AggressiveWeeklyTargetEngine.compute(
            currentKg: 84.0,
            idealKg: 78,
            goalDate: goalDate,
            priorSundayTargetKg: 83.4,
            fallbackWeeklyDeltaKg: -0.3,
            now: now,
            calendar: cal
        )
        XCTAssertEqual(hit.mode, .hardcoreCatchUp)
        let safe = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: 84)
        XCTAssertGreaterThanOrEqual(hit.weeklyDeltaKg, -safe - 0.01)
        XCTAssertLessThan(hit.weeklyDeltaKg, -0.4)
        XCTAssertTrue(hit.pacingLine.lowercased().contains("hardcore") || hit.pacingLine.lowercased().contains("catch"))
    }

    func testAheadAcceleratesNoCoast() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 8))!
        let goalDate = cal.date(from: DateComponents(year: 2026, month: 12, day: 14))!
        // Prior Sunday 83.5; now 83.0 → ahead by 0.5.
        let hit = AggressiveWeeklyTargetEngine.compute(
            currentKg: 83.0,
            idealKg: 78,
            goalDate: goalDate,
            priorSundayTargetKg: 83.5,
            fallbackWeeklyDeltaKg: -0.3,
            now: now,
            calendar: cal
        )
        XCTAssertEqual(hit.mode, .accelerate)
        let safe = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: 83)
        let expected = (safe * 100).rounded() / 100
        XCTAssertEqual(hit.weeklyDeltaKg, -expected, accuracy: 0.02)
        XCTAssertTrue(hit.pacingLine.lowercased().contains("accelerate") || hit.pacingLine.lowercased().contains("coast"))
    }

    func testCapsAboveSafeWhenCalendarDemandsTooMuch() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 8))!
        // 4 weeks: 84 → 80 needs -1.0/wk; safe ~0.59.
        let goalDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let hit = AggressiveWeeklyTargetEngine.compute(
            currentKg: 84,
            idealKg: 80,
            goalDate: goalDate,
            priorSundayTargetKg: nil,
            fallbackWeeklyDeltaKg: -0.3,
            now: now,
            calendar: cal
        )
        let safe = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: 84)
        let expected = (safe * 100).rounded() / 100
        XCTAssertEqual(abs(hit.weeklyDeltaKg), expected, accuracy: 0.02)
        XCTAssertGreaterThan(hit.weeklyDeltaKg, -1.0)
    }

    func testCoachPersonaNameIsKeel() {
        XCTAssertEqual(CoachPersona.name, "Keel")
        XCTAssertTrue(CoachPersona.liveBadge().contains("Keel"))
        XCTAssertFalse(CoachPersona.consentToggleTitle.contains("Grok"))
        XCTAssertFalse(CoachPersona.thinkingSpinnerLine.contains("Grok"))
    }
}
