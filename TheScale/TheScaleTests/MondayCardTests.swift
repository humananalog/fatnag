import XCTest
@testable import TheScale

final class MondayCardTests: XCTestCase {
    func testMondayMorningWindow() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        // 2026-09-21 is a Monday.
        let mondayMorning = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 7))!
        let mondayAfternoon = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 15))!
        let tuesdayMorning = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 7))!

        XCTAssertTrue(MondayCardEngine.shouldOfferAfterWeighIn(now: mondayMorning, calendar: cal))
        XCTAssertFalse(MondayCardEngine.shouldOfferAfterWeighIn(now: mondayAfternoon, calendar: cal))
        XCTAssertFalse(MondayCardEngine.shouldOfferAfterWeighIn(now: tuesdayMorning, calendar: cal))
    }

    func testSundayTargetPacesToGoalDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 8))!
        // 4 weeks to goal: 84 → 80 = -1 kg/wk → Sunday 83.
        let goalDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let goal = MondayCardEngine.sundayGoal(
            currentKg: 84,
            idealKg: 80,
            goalDate: goalDate,
            fallbackWeeklyDeltaKg: -0.3,
            now: now,
            calendar: cal
        )
        XCTAssertEqual(goal.weeklyDeltaKg, -1.0, accuracy: 0.05)
        XCTAssertEqual(goal.targetKg, 83.0, accuracy: 0.05)
        XCTAssertEqual(cal.component(.weekday, from: goal.sundayDate), 1)
    }

    func testSundayTargetUsesWeeklyFallbackWithoutGoalDate() {
        let goal = MondayCardEngine.sundayGoal(
            currentKg: 90,
            idealKg: 80,
            goalDate: nil,
            fallbackWeeklyDeltaKg: -0.4
        )
        XCTAssertEqual(goal.targetKg, 89.6, accuracy: 0.01)
        XCTAssertEqual(goal.weeklyDeltaKg, -0.4, accuracy: 0.01)
    }

    func testParseSections() {
        let raw = """
        ===ENCOURAGEMENT===
        Alex, move.
        ===MEALS===
        Eggs and greens.
        ===DIAGNOSTIC===
        Cut 400 kcal. Hit Sunday.
        """
        let parts = MondayCardEngine.parseSections(from: raw)
        XCTAssertTrue(parts.encouragement.contains("Alex"))
        XCTAssertTrue(parts.meals.contains("Eggs"))
        XCTAssertTrue(parts.diagnostic.contains("400"))
    }

    func testWeighInSignatureStable() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let a = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 7))!
        let b = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 9))!
        let sigA = MondayCardEngine.weighInSignature(kg: 83.25, at: a, calendar: cal)
        let sigB = MondayCardEngine.weighInSignature(kg: 83.25, at: b, calendar: cal)
        XCTAssertEqual(sigA, sigB)
        let sigC = MondayCardEngine.weighInSignature(kg: 83.40, at: a, calendar: cal)
        XCTAssertNotEqual(sigA, sigC)
    }
}
