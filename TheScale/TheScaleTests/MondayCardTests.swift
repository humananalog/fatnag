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
        // 4 weeks to goal: 84 → 80 wants -1 kg/wk; biology caps near ~0.59.
        let goalDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let goal = MondayCardEngine.sundayGoal(
            currentKg: 84,
            idealKg: 80,
            goalDate: goalDate,
            fallbackWeeklyDeltaKg: -0.3,
            priorSundayTargetKg: nil,
            now: now,
            calendar: cal
        )
        let safe = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: 84)
        let expected = (safe * 100).rounded() / 100
        XCTAssertEqual(goal.weeklyDeltaKg, -expected, accuracy: 0.05)
        XCTAssertEqual(goal.targetKg, 84 + goal.weeklyDeltaKg, accuracy: 0.05)
        XCTAssertEqual(cal.component(.weekday, from: goal.sundayDate), 1)
    }

    func testSundayTargetUsesWeeklyFallbackWithoutGoalDate() {
        let goal = MondayCardEngine.sundayGoal(
            currentKg: 90,
            idealKg: 80,
            goalDate: nil,
            fallbackWeeklyDeltaKg: -0.4,
            priorSundayTargetKg: nil
        )
        // No goal date: still aggressive to safe max toward ideal (not soft fallback).
        let safe = TargetFeasibility.maxSafeLossKgPerWeek(currentKg: 90)
        let expected = (safe * 100).rounded() / 100
        XCTAssertEqual(goal.weeklyDeltaKg, -expected, accuracy: 0.05)
        XCTAssertEqual(goal.targetKg, 90 + goal.weeklyDeltaKg, accuracy: 0.05)
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

    func testStartOfWeekAlwaysMonday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 1 // Sunday-first locale must still yield Monday.
        // 2026-09-24 is a Thursday.
        let thursday = cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 15))!
        let monday = MondayCardEngine.startOfWeekMonday(now: thursday, calendar: cal)
        XCTAssertEqual(cal.component(.weekday, from: monday), 2)
        XCTAssertEqual(cal.component(.day, from: monday), 21)
        XCTAssertEqual(cal.component(.hour, from: monday), 0)
        // Sunday still belongs to the week that started the prior Monday.
        let sunday = cal.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 20))!
        let sundayMonday = MondayCardEngine.startOfWeekMonday(now: sunday, calendar: cal)
        XCTAssertEqual(cal.component(.day, from: sundayMonday), 21)
    }

    func testReconcileRestoresMondayWeightAfterTodayWipe() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 0))!
        let thursday = cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!
        let history: [(kg: Double, date: Date)] = [
            (84.0, cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 7))!),
            (83.6, cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 7))!),
            (83.4, thursday)
        ]
        // Preview wipe: weekStartDate = today, weekStartKg = live baseline.
        let result = MondayCardEngine.reconcileWeekStart(
            weekStartKg: 83.4,
            weekStartDate: thursday,
            currentBaselineKg: 83.4,
            history: history,
            now: thursday,
            calendar: cal
        )
        XCTAssertTrue(result.didChange)
        XCTAssertEqual(result.weekStartKg ?? -1, 84.0, accuracy: 0.01)
        XCTAssertEqual(cal.component(.day, from: result.weekStartDate), 21)
        XCTAssertEqual(cal.component(.weekday, from: result.weekStartDate), 2)
        XCTAssertTrue(result.reason.contains("align") || result.reason.contains("restore") || result.reason.contains("reanchor"))
        // Correct Monday stamp matching Health must not be overwritten by today's lower weight.
        let ok = MondayCardEngine.reconcileWeekStart(
            weekStartKg: 84.0,
            weekStartDate: monday,
            currentBaselineKg: 83.4,
            history: history,
            now: thursday,
            calendar: cal
        )
        XCTAssertFalse(ok.didChange)
        XCTAssertEqual(ok.weekStartKg ?? -1, 84.0, accuracy: 0.01)
    }

    func testWeekStartWeightPrefersMondayMorning() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 0))!
        let samples: [(kg: Double, date: Date)] = [
            (85.0, cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 8))!),
            (84.2, cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 6))!),
            (84.0, cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 9))!),
            (83.5, cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 8))!)
        ]
        let kg = MondayCardEngine.weekStartWeightKg(
            from: samples,
            weekStartMonday: monday,
            calendar: cal
        )
        XCTAssertEqual(kg ?? -1, 84.2, accuracy: 0.01)
    }

    func testWeekStartWeightFallsBackToCarryInBeforeTuesday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 0))!
        let samples: [(kg: Double, date: Date)] = [
            (85.1, cal.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 8))!),
            (84.7, cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 22))!),
            // Mid-week first weigh must NOT become week-start.
            (83.2, cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 7))!)
        ]
        let kg = MondayCardEngine.weekStartWeightKg(
            from: samples,
            weekStartMonday: monday,
            calendar: cal
        )
        XCTAssertEqual(kg ?? -1, 84.7, accuracy: 0.01)
    }

    func testReconcileAlignsDreamWeightAndWrongMondayStampToHistory() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 0))!
        let thursday = cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!
        let history: [(kg: Double, date: Date)] = [
            (84.0, cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 7))!),
            (83.5, thursday)
        ]
        // Dream / ideal stamped on Monday date must yield to Health Monday mass.
        let dream = MondayCardEngine.reconcileWeekStart(
            weekStartKg: 72.0,
            weekStartDate: monday,
            currentBaselineKg: 83.5,
            history: history,
            now: thursday,
            calendar: cal
        )
        XCTAssertTrue(dream.didChange)
        XCTAssertEqual(dream.weekStartKg ?? -1, 84.0, accuracy: 0.01)
        XCTAssertEqual(cal.component(.day, from: dream.weekStartDate), 21)
        XCTAssertEqual(dream.reason, "align-monday-from-history")

        // First mid-week weigh stamped as week-start also realigns.
        let midWeek = MondayCardEngine.reconcileWeekStart(
            weekStartKg: 83.5,
            weekStartDate: thursday,
            currentBaselineKg: 83.5,
            history: history,
            now: thursday,
            calendar: cal
        )
        XCTAssertEqual(midWeek.weekStartKg ?? -1, 84.0, accuracy: 0.01)
        XCTAssertEqual(cal.component(.weekday, from: midWeek.weekStartDate), 2)
    }

    func testReconcileWithoutHistoryKeepsSameWeekKg() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 0))!
        let thursday = cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!
        let result = MondayCardEngine.reconcileWeekStart(
            weekStartKg: 84.0,
            weekStartDate: thursday,
            currentBaselineKg: 83.2,
            history: [],
            now: thursday,
            calendar: cal
        )
        XCTAssertEqual(result.weekStartKg ?? -1, 84.0, accuracy: 0.01)
        XCTAssertEqual(cal.component(.day, from: result.weekStartDate), 21)
        // Must not invent loss by swapping to today's lower baseline.
        XCTAssertNotEqual(result.weekStartKg ?? -1, 83.2, accuracy: 0.01)
        _ = monday
    }

    func testWeekRollWithoutHistoryUsesLiveBaselineNotLastWeekWin() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        // Prior Monday 21 Sep week-start 90.0; today is next Monday 28 Sep at 89.35 (−650g last week).
        let priorMonday = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 0))!
        let thisMonday = cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 8))!
        let result = MondayCardEngine.reconcileWeekStart(
            weekStartKg: 90.0,
            weekStartDate: priorMonday,
            currentBaselineKg: 89.35,
            history: [],
            now: thisMonday,
            calendar: cal
        )
        XCTAssertEqual(result.reason, "roll-to-monday")
        XCTAssertEqual(result.weekStartKg ?? -1, 89.35, accuracy: 0.01)
        XCTAssertEqual(cal.component(.day, from: result.weekStartDate), 28)
        // Must not keep 90.0 or Progress paints last week's −650g as this week's win.
        XCTAssertNotEqual(result.weekStartKg ?? -1, 90.0, accuracy: 0.01)
    }
}
