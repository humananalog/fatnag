import XCTest
@testable import TheScale

final class WeighMissLadderSchedulerTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        return cal
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps)!
    }

    override func setUp() {
        super.setUp()
        WeighMissLadderScheduler.resetForTests()
        NotificationDailyBudget.resetForTests()
        TrendNotificationScheduler.resetBadTrendForTests()
    }

    func testConsecutiveMissDaysFromLastWeigh() {
        let now = date(year: 2026, month: 9, day: 30, hour: 18)
        XCTAssertEqual(
            WeighMissLadderScheduler.consecutiveMissDays(
                lastWeighDate: date(year: 2026, month: 9, day: 29, hour: 7),
                now: now,
                calendar: calendar
            ),
            1
        )
        XCTAssertEqual(
            WeighMissLadderScheduler.consecutiveMissDays(
                lastWeighDate: date(year: 2026, month: 9, day: 27, hour: 7),
                now: now,
                calendar: calendar
            ),
            3
        )
        XCTAssertEqual(
            WeighMissLadderScheduler.consecutiveMissDays(
                lastWeighDate: nil,
                now: now,
                calendar: calendar
            ),
            0
        )
    }

    func testEveningRungAfterMorningDeadline() {
        let now = date(year: 2026, month: 9, day: 30, hour: 18, minute: 40)
        let rung = WeighMissLadderScheduler.resolveRung(
            alreadyWeighedToday: false,
            consecutiveMissDays: 1,
            now: now,
            calendar: calendar,
            morningDeadlinePassed: true
        )
        XCTAssertEqual(rung, .eveningSameDay)
    }

    func testNoEveningBeforeWindow() {
        let now = date(year: 2026, month: 9, day: 30, hour: 14)
        let rung = WeighMissLadderScheduler.resolveRung(
            alreadyWeighedToday: false,
            consecutiveMissDays: 1,
            now: now,
            calendar: calendar,
            morningDeadlinePassed: true
        )
        XCTAssertNil(rung)
    }

    func testDay2AndDay3Rungs() {
        let now = date(year: 2026, month: 9, day: 30, hour: 15, minute: 30)
        XCTAssertEqual(
            WeighMissLadderScheduler.resolveRung(
                alreadyWeighedToday: false,
                consecutiveMissDays: 2,
                now: now,
                calendar: calendar,
                morningDeadlinePassed: true
            ),
            .day2
        )
        XCTAssertEqual(
            WeighMissLadderScheduler.resolveRung(
                alreadyWeighedToday: false,
                consecutiveMissDays: 4,
                now: now,
                calendar: calendar,
                morningDeadlinePassed: true
            ),
            .day3Plus
        )
    }

    func testWeighedTodaySkipsAllRungs() {
        let now = date(year: 2026, month: 9, day: 30, hour: 19)
        XCTAssertNil(
            WeighMissLadderScheduler.resolveRung(
                alreadyWeighedToday: true,
                consecutiveMissDays: 5,
                now: now,
                calendar: calendar,
                morningDeadlinePassed: true
            )
        )
    }

    func testMissCopyIsGentleNotSergeant() {
        let evening = ScaleNotificationCopy.weighMiss(profileName: "Alex", rung: .eveningSameDay)
        XCTAssertEqual(evening.kind, .weighMiss)
        XCTAssertEqual(evening.kind.interruptionLevel, .active)
        XCTAssertFalse(evening.glanceTitle.contains("💩"))
        let day3 = ScaleNotificationCopy.weighMiss(profileName: "Alex", rung: .day3Plus)
        XCTAssertTrue(day3.phoneBody.contains("Alex"))
    }

    func testMondaySkipAndSundayWrapCopy() {
        let mon = ScaleNotificationCopy.mondaySkip(profileName: "Alex")
        XCTAssertEqual(mon.kind, .mondaySkip)
        XCTAssertEqual(mon.kind.destination, .progress)
        let wrap = ScaleNotificationCopy.sundayWrap(
            profileName: "Alex",
            weeklyGoal: WeeklyMiniGoal(
                targetDeltaKg: -0.5,
                weekStartKg: nil,
                weekStartDate: nil,
                title: "Cut"
            ),
            band: .onTrack,
            weighCount: 3
        )
        XCTAssertEqual(wrap.kind, .sundayWrap)
        XCTAssertTrue(wrap.glanceLine.contains("3"))
    }

    func testDailyBudgetExemptsMorning() {
        NotificationDailyBudget.resetForTests()
        XCTAssertTrue(NotificationDailyBudget.canSpend(.morningWeigh))
        NotificationDailyBudget.record(.missLadder)
        NotificationDailyBudget.record(.nag)
        XCTAssertEqual(NotificationDailyBudget.remaining(), 0)
        XCTAssertFalse(NotificationDailyBudget.canSpend(.badTrend))
        XCTAssertTrue(NotificationDailyBudget.canSpend(.morningWeigh))
        XCTAssertTrue(NotificationDailyBudget.canSpend(.weightSpike))
    }

    func testBadTrendRequiresDistinctDays() {
        let now = date(year: 2026, month: 9, day: 30, hour: 12)
        let sparse = [
            HealthMetricSample(value: 80, date: date(year: 2026, month: 9, day: 29, hour: 7)),
            HealthMetricSample(value: 80.5, date: date(year: 2026, month: 9, day: 30, hour: 7))
        ]
        XCTAssertFalse(
            TrendNotificationScheduler.badTrendEligible(
                recent: sparse,
                lastFireDay: nil,
                now: now,
                calendar: calendar
            )
        )
        let dense = [
            HealthMetricSample(value: 79.5, date: date(year: 2026, month: 9, day: 27, hour: 7)),
            HealthMetricSample(value: 79.8, date: date(year: 2026, month: 9, day: 28, hour: 7)),
            HealthMetricSample(value: 80.1, date: date(year: 2026, month: 9, day: 29, hour: 7)),
            HealthMetricSample(value: 80.5, date: date(year: 2026, month: 9, day: 30, hour: 7))
        ]
        XCTAssertTrue(
            TrendNotificationScheduler.badTrendEligible(
                recent: dense,
                lastFireDay: nil,
                now: now,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            TrendNotificationScheduler.badTrendEligible(
                recent: dense,
                lastFireDay: "2026-09-29",
                now: now,
                calendar: calendar
            )
        )
        XCTAssertTrue(
            TrendNotificationScheduler.badTrendEligible(
                recent: dense,
                lastFireDay: "2026-09-26",
                now: now,
                calendar: calendar
            )
        )
    }

    func testMondayWeeklyFireDateASAPAfter815() {
        let now = date(year: 2026, month: 9, day: 28, hour: 9, minute: 0) // Monday
        let fire = TrendNotificationScheduler.mondayWeeklyFireDate(now: now, calendar: calendar)
        XCTAssertGreaterThan(fire, now)
        XCTAssertLessThan(fire.timeIntervalSince(now), 10)
    }

    func testMondayWeeklyFireDateBefore815() {
        let now = date(year: 2026, month: 9, day: 28, hour: 7, minute: 0)
        let fire = TrendNotificationScheduler.mondayWeeklyFireDate(now: now, calendar: calendar)
        let comps = calendar.dateComponents([.hour, .minute], from: fire)
        XCTAssertEqual(comps.hour, 8)
        XCTAssertEqual(comps.minute, 15)
    }

    func testWeeklyGoalCopyMissAware() {
        let goal = WeeklyMiniGoal(
            targetDeltaKg: -0.5,
            weekStartKg: nil,
            weekStartDate: nil,
            title: "Cut"
        )
        let missing = ScaleNotificationCopy.weeklyGoal(
            profileName: "Alex",
            weeklyGoal: goal,
            alreadyWeighedToday: false
        )
        XCTAssertTrue(missing.phoneBody.lowercased().contains("scale"))
        let locked = ScaleNotificationCopy.weeklyGoal(
            profileName: "Alex",
            weeklyGoal: goal,
            alreadyWeighedToday: true
        )
        XCTAssertTrue(locked.glanceLine.lowercased().contains("lock"))
    }
}
