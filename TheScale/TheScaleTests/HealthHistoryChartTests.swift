import XCTest
@testable import TheScale

final class HealthHistoryChartTests: XCTestCase {
    func testRangeOrderMatchesPickerContract() {
        XCTAssertEqual(
            HealthHistoryRange.allCases.map(\.rawValue),
            ["lastWeek", "lastTwoWeeks", "lastMonth", "lastThreeMonths", "lastYear"]
        )
        XCTAssertEqual(HealthHistoryRange.default, .lastTwoWeeks)
    }

    func testTwoWeekStartIsFourteenDaysBack() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = HealthHistoryRange.lastTwoWeeks.startDate(relativeTo: now)
        let days = Calendar.current.dateComponents([.day], from: start, to: now).day
        XCTAssertEqual(days, 14)
    }

    func testWeightDomainIncludesIdealAndDataBelowIdeal() {
        let domain = HealthChartMath.weightDomain(values: [70, 71], idealKg: 72)
        XCTAssertLessThanOrEqual(domain.lowerBound, 70)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 72)
    }

    func testWeightDomainIncludesDataAboveIdeal() {
        let domain = HealthChartMath.weightDomain(values: [78, 80, 79.2], idealKg: 72)
        XCTAssertLessThanOrEqual(domain.lowerBound, 72)
        XCTAssertGreaterThan(domain.upperBound, 80)
    }

    func testWeightDomainKeepsIdealVisibleWhenDataIsHigher() {
        let domain = HealthChartMath.weightDomain(values: [90, 91], idealKg: 75)
        XCTAssertLessThanOrEqual(domain.lowerBound, 75)
        XCTAssertGreaterThan(domain.upperBound, 91)
    }

    func testWeightDomainVisibleDataFloorZoomsAboveTarget() {
        let targetFloor = HealthChartMath.weightDomain(
            values: [90, 91],
            idealKg: 75,
            floorMode: .target
        )
        let dataFloor = HealthChartMath.weightDomain(
            values: [90, 91],
            idealKg: 75,
            floorMode: .visibleData
        )
        XCTAssertLessThan(targetFloor.lowerBound, dataFloor.lowerBound)
        XCTAssertGreaterThan(dataFloor.lowerBound, 75)
        XCTAssertEqual(dataFloor.lowerBound, 90, accuracy: 1.0)
    }

    func testBodyFatDomainVisibleDataFloorIgnoresIdealBelowData() {
        let targetFloor = HealthChartMath.bodyFatDomain(
            values: [18, 20, 19],
            idealPercent: 12,
            floorMode: .target
        )
        let dataFloor = HealthChartMath.bodyFatDomain(
            values: [18, 20, 19],
            idealPercent: 12,
            floorMode: .visibleData
        )
        XCTAssertEqual(targetFloor.lowerBound, 12, accuracy: 0.001)
        XCTAssertGreaterThan(dataFloor.lowerBound, 12)
        XCTAssertEqual(dataFloor.lowerBound, 18, accuracy: 0.5)
    }

    func testYFloorModeRotates() {
        var mode = HealthChartMath.ChartYFloorMode.target
        mode.rotate()
        XCTAssertEqual(mode, .visibleData)
        mode.rotate()
        XCTAssertEqual(mode, .target)
    }

    func testValuesInVisibleXWindowFiltersByScroll() {
        let cal = Calendar(identifier: .gregorian)
        let day0 = cal.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let samples = (0..<10).map { i in
            HealthMetricSample(
                value: Double(80 + i),
                date: cal.date(byAdding: .day, value: i, to: day0)!
            )
        }
        let xDomain = day0...cal.date(byAdding: .day, value: 9, to: day0)!
        let visibleStart = cal.date(byAdding: .day, value: 5, to: day0)!
        let values = HealthChartMath.valuesInVisibleXWindow(
            samples: samples,
            visibleStart: visibleStart,
            visibleLength: 3 * 86_400,
            xDomain: xDomain
        )
        XCTAssertFalse(values.isEmpty)
        XCTAssertEqual(values.min()!, 85, accuracy: 0.001)
    }

    func testBodyFatDomainUsesIdealWhenPresent() {
        let domain = HealthChartMath.bodyFatDomain(values: [18, 20, 19], idealPercent: 15)
        XCTAssertEqual(domain.lowerBound, 15, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 20)
    }

    func testBodyFatDomainAutoscalesWithoutIdeal() {
        let domain = HealthChartMath.bodyFatDomain(values: [18, 22], idealPercent: nil)
        XCTAssertLessThan(domain.lowerBound, 18)
        XCTAssertGreaterThan(domain.upperBound, 22)
    }

    func testExtremaLabelsHighestAndLowest() throws {
        let samples = [
            HealthMetricSample(value: 80, date: Date(timeIntervalSince1970: 100)),
            HealthMetricSample(value: 78.5, date: Date(timeIntervalSince1970: 200)),
            HealthMetricSample(value: 81.2, date: Date(timeIntervalSince1970: 300))
        ]
        let extrema = try XCTUnwrap(HealthChartMath.extrema(in: samples))
        XCTAssertEqual(extrema.highest.value, 81.2, accuracy: 0.001)
        XCTAssertEqual(extrema.lowest.value, 78.5, accuracy: 0.001)
    }

    func testLinearTrendEndpointsNeedTwoPoints() throws {
        let one = [HealthMetricSample(value: 80, date: Date())]
        XCTAssertNil(HealthChartMath.linearTrendEndpoints(samples: one))

        let two = [
            HealthMetricSample(value: 80, date: Date(timeIntervalSince1970: 0)),
            HealthMetricSample(value: 78, date: Date(timeIntervalSince1970: 1000))
        ]
        let trend = try XCTUnwrap(HealthChartMath.linearTrendEndpoints(samples: two))
        XCTAssertEqual(trend.start.value, 80, accuracy: 0.01)
        XCTAssertEqual(trend.end.value, 78, accuracy: 0.01)
    }

    func testProjectWeightToIdealCrossesOnLosingTrend() throws {
        let day: TimeInterval = 86_400
        let samples = [
            HealthMetricSample(value: 80, date: Date(timeIntervalSince1970: 0)),
            HealthMetricSample(value: 79, date: Date(timeIntervalSince1970: day * 7)),
            HealthMetricSample(value: 78, date: Date(timeIntervalSince1970: day * 14))
        ]
        let projection = try XCTUnwrap(
            HealthChartMath.projectWeightToIdeal(
                windowSamples: samples,
                idealKg: 75,
                now: Date(timeIntervalSince1970: day * 14),
                maxHorizonDays: 365
            )
        )
        let crossing = try XCTUnwrap(projection.crossing)
        XCTAssertEqual(crossing.value, 75, accuracy: 0.01)
        XCTAssertGreaterThan(crossing.date.timeIntervalSince1970, day * 14)
        XCTAssertLessThan(projection.slopeKgPerDay, 0)
    }

    func testProjectWeightAwayFromIdealHasNoCrossing() throws {
        let day: TimeInterval = 86_400
        let samples = [
            HealthMetricSample(value: 78, date: Date(timeIntervalSince1970: 0)),
            HealthMetricSample(value: 79, date: Date(timeIntervalSince1970: day * 7)),
            HealthMetricSample(value: 80, date: Date(timeIntervalSince1970: day * 14))
        ]
        let projection = try XCTUnwrap(
            HealthChartMath.projectWeightToIdeal(
                windowSamples: samples,
                idealKg: 75,
                now: Date(timeIntervalSince1970: day * 14)
            )
        )
        XCTAssertNil(projection.crossing)
        XCTAssertGreaterThan(projection.slopeKgPerDay, 0)
    }

    func testNearestSampleSelection() throws {
        let samples = [
            HealthMetricSample(value: 80, date: Date(timeIntervalSince1970: 100)),
            HealthMetricSample(value: 79, date: Date(timeIntervalSince1970: 200)),
            HealthMetricSample(value: 78, date: Date(timeIntervalSince1970: 300))
        ]
        let nearest = try XCTUnwrap(
            HealthChartMath.nearestSample(in: samples, to: Date(timeIntervalSince1970: 210))
        )
        XCTAssertEqual(nearest.value, 79, accuracy: 0.001)
    }

    func testChartSeriesSortsAndMergesNearDuplicates() {
        let a = HealthMetricSample(value: 80, date: Date(timeIntervalSince1970: 300))
        let b = HealthMetricSample(value: 79, date: Date(timeIntervalSince1970: 100))
        let c = HealthMetricSample(value: 78.5, date: Date(timeIntervalSince1970: 101)) // within 2s of b
        let series = HealthChartMath.chartSeries([a, b, c], mergeWithinSeconds: 2)
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].value, 78.5, accuracy: 0.001)
        XCTAssertEqual(series[1].value, 80, accuracy: 0.001)
        XCTAssertTrue(series[0].date <= series[1].date)
    }

    func testChartSeriesPreservesDistinctDaySamples() {
        let day: TimeInterval = 86_400
        let samples = [
            HealthMetricSample(value: 80, date: Date(timeIntervalSince1970: 0)),
            HealthMetricSample(value: 79.5, date: Date(timeIntervalSince1970: day)),
            HealthMetricSample(value: 79, date: Date(timeIntervalSince1970: day * 2))
        ]
        let series = HealthChartMath.chartSeries(samples)
        XCTAssertEqual(series.count, 3)
    }

    func testHistoryXDomainSpansSelectedRangeNotSparseSamples() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let domain = HealthChartMath.historyXDomain(range: .lastThreeMonths, now: now)
        let start = HealthHistoryRange.lastThreeMonths.startDate(relativeTo: now)
        XCTAssertEqual(domain.lowerBound.timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 1)
        XCTAssertGreaterThanOrEqual(domain.upperBound.timeIntervalSince1970, now.timeIntervalSince1970)
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        XCTAssertGreaterThan(span, HealthHistoryRange.lastThreeMonths.visibleDomainLength)
    }

    func testHistoryXDomainYearLongerThanVisibleWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let domain = HealthChartMath.historyXDomain(range: .lastYear, now: now)
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        XCTAssertGreaterThan(span, HealthHistoryRange.lastYear.visibleDomainLength)
    }

    func testHistoryXDomainExtendsForProjectionPastNow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let future = now.addingTimeInterval(120 * 86_400)
        let domain = HealthChartMath.historyXDomain(
            range: .lastMonth,
            extraDates: [future],
            now: now
        )
        XCTAssertGreaterThanOrEqual(domain.upperBound, future)
    }

    func testScrollVisibleLengthNilWhenDomainTooShort() {
        let now = Date()
        // Artificial short domain (7 days) vs 3M preferred window (45 days).
        let short = now.addingTimeInterval(-7 * 86_400)...now
        XCTAssertNil(
            HealthChartMath.scrollVisibleDomainLength(for: .lastThreeMonths, xDomain: short)
        )
    }

    func testScrollVisibleLengthDisabledForThreeMonthAndYear() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let three = HealthChartMath.historyXDomain(range: .lastThreeMonths, now: now)
        let year = HealthChartMath.historyXDomain(range: .lastYear, now: now)
        XCTAssertNil(HealthChartMath.scrollVisibleDomainLength(for: .lastThreeMonths, xDomain: three))
        XCTAssertNil(HealthChartMath.scrollVisibleDomainLength(for: .lastYear, xDomain: year))
    }

    func testScrollVisibleLengthNilForShortRanges() {
        let now = Date()
        let domain = HealthChartMath.historyXDomain(range: .lastTwoWeeks, now: now)
        XCTAssertNil(
            HealthChartMath.scrollVisibleDomainLength(for: .lastTwoWeeks, xDomain: domain)
        )
    }

    func testScrollLeadingDatePinsToRecentWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let domain = HealthChartMath.historyXDomain(range: .lastThreeMonths, now: now)
        let length: TimeInterval = 45 * 86_400
        let leading = HealthChartMath.scrollLeadingDate(xDomain: domain, visibleLength: length)
        XCTAssertGreaterThan(leading, domain.lowerBound)
        let visibleEnd = leading.addingTimeInterval(length)
        XCTAssertEqual(visibleEnd.timeIntervalSince1970, domain.upperBound.timeIntervalSince1970, accuracy: 1)
    }

    func testSanitizeDomainRejectsNonFiniteAndDegenerate() {
        // ClosedRange cannot be built from NaN bounds; use ±infinity instead.
        let inf = HealthChartMath.sanitizeDomain((-Double.infinity)...Double.infinity)
        XCTAssertTrue(inf.lowerBound.isFinite)
        XCTAssertTrue(inf.upperBound.isFinite)
        XCTAssertGreaterThan(inf.upperBound, inf.lowerBound)

        let degenerate = HealthChartMath.sanitizeDomain(10...10)
        XCTAssertGreaterThan(degenerate.upperBound, degenerate.lowerBound)
    }

    func testWeightDomainIgnoresNonFiniteExtras() {
        let domain = HealthChartMath.weightDomain(
            values: [80, 81],
            idealKg: 75,
            extraValues: [.nan, .infinity]
        )
        XCTAssertTrue(domain.lowerBound.isFinite)
        XCTAssertTrue(domain.upperBound.isFinite)
        XCTAssertGreaterThan(domain.upperBound, domain.lowerBound)
        XCTAssertLessThanOrEqual(domain.lowerBound, 75)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 81)
    }

    func testManualDraftIsMassOnly() {
        let draft = EditableMeasurementDraft.manual(
            weightKg: 77.4,
            at: Date(timeIntervalSince1970: 1_700_000_000),
            profile: .default
        )
        XCTAssertTrue(draft.isManualEntry)
        XCTAssertFalse(draft.includeCompositionInHealth)
        XCTAssertNil(draft.bodyFatPercent)
        XCTAssertNil(draft.leanBodyMassKg)
        XCTAssertNil(draft.impedanceOhms)
        XCTAssertEqual(draft.weightKg, 77.4, accuracy: 0.001)
        XCTAssertNotNil(draft.bmi)
    }

    func testHistoryChartToneFromRate() {
        XCTAssertEqual(HistoryChartTone.from(ratePerWeek: -0.4), .losing)
        XCTAssertEqual(HistoryChartTone.from(ratePerWeek: 0.4), .gaining)
        XCTAssertEqual(HistoryChartTone.from(ratePerWeek: 0.01), .stable)
        XCTAssertEqual(HistoryChartTone.from(ratePerWeek: nil), .unknown)
    }

    func testXAxisMarksWeekUsesWeekdayLabels() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let domain = HealthChartMath.historyXDomain(range: .lastWeek, now: now, calendar: cal)
        let marks = HealthChartMath.xAxisMarks(
            range: .lastWeek,
            domain: domain,
            plotWidth: 320,
            now: now,
            calendar: cal
        )
        XCTAssertFalse(marks.isEmpty)
        XCTAssertLessThanOrEqual(marks.count, 7)
        // Weekday style: short names, no digits.
        for mark in marks {
            XCTAssertFalse(mark.text.contains { $0.isNumber }, mark.text)
            XCTAssertLessThanOrEqual(mark.text.count, 4)
        }
    }

    func testXAxisMarksTwoWeeksUsesMonthDayAndStaysSparse() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let domain = HealthChartMath.historyXDomain(range: .lastTwoWeeks, now: now, calendar: cal)
        let marks = HealthChartMath.xAxisMarks(
            range: .lastTwoWeeks,
            domain: domain,
            plotWidth: 300,
            now: now,
            calendar: cal
        )
        XCTAssertGreaterThanOrEqual(marks.count, 2)
        XCTAssertLessThanOrEqual(marks.count, 6)
        for mark in marks {
            XCTAssertTrue(mark.text.contains { $0.isNumber }, mark.text)
        }
        if marks.count >= 3 {
            let step = marks[1].date.timeIntervalSince(marks[0].date)
            XCTAssertGreaterThanOrEqual(step, 1.5 * 86_400)
        }
    }

    func testXAxisMarksYearUsesMonthLabelsAcrossFullDomain() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let domain = HealthChartMath.historyXDomain(range: .lastYear, now: now, calendar: cal)
        let visible = HealthChartMath.scrollVisibleDomainLength(for: .lastYear, xDomain: domain)
        let marks = HealthChartMath.xAxisMarks(
            range: .lastYear,
            domain: domain,
            visibleLength: visible,
            plotWidth: 320,
            now: now,
            calendar: cal
        )
        // Must span the year — not only the first ~7 days of the domain.
        XCTAssertGreaterThanOrEqual(marks.count, 4)
        let covered = marks.last!.date.timeIntervalSince(marks.first!.date)
        XCTAssertGreaterThan(covered, 180 * 86_400)
        for mark in marks {
            // Month ("Nov") or month+year ("Nov 22") — never day-of-month style ("Nov 14").
            XCTAssertLessThanOrEqual(mark.text.count, 8, mark.text)
            XCTAssertFalse(mark.text.isEmpty)
        }
    }

    func testXAxisMarksNarrowPlotDropsDensity() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let domain = HealthChartMath.historyXDomain(range: .lastMonth, now: now)
        let wide = HealthChartMath.xAxisMarks(range: .lastMonth, domain: domain, plotWidth: 360, now: now)
        let narrow = HealthChartMath.xAxisMarks(range: .lastMonth, domain: domain, plotWidth: 180, now: now)
        XCTAssertLessThanOrEqual(narrow.count, wide.count)
        XCTAssertLessThanOrEqual(narrow.count, 5)
    }

    func testXAxisLabelStyleFollowsSelectedPeriodNotDomainSpan() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Projection-stretched domain (months ahead) while picker is still 1W.
        let stretched = now.addingTimeInterval(-7 * 86_400)...now.addingTimeInterval(120 * 86_400)
        let weekMarks = HealthChartMath.xAxisMarks(
            range: .lastWeek,
            domain: stretched,
            plotWidth: 320,
            now: now,
            calendar: cal
        )
        XCTAssertFalse(weekMarks.isEmpty)
        for mark in weekMarks {
            XCTAssertFalse(
                mark.text.contains(where: \.isNumber),
                "1W must stay weekday labels even if projection stretches domain: \(mark.text)"
            )
        }

        let yearDomain = HealthChartMath.historyXDomain(range: .lastYear, now: now, calendar: cal)
        let yearLabel = HealthChartMath.formatXAxisLabel(
            yearDomain.lowerBound,
            range: .lastYear,
            now: now,
            calendar: cal
        )
        let weekLabel = HealthChartMath.formatXAxisLabel(
            yearDomain.lowerBound,
            range: .lastWeek,
            now: now,
            calendar: cal
        )
        XCTAssertNotEqual(yearLabel, weekLabel)
        XCTAssertFalse(weekLabel.contains(where: \.isNumber))
    }

    func testXAxisCadenceIsDistinctPerPeriod() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let week = HealthChartMath.xAxisMarks(
            range: .lastWeek,
            domain: HealthChartMath.historyXDomain(range: .lastWeek, now: now, calendar: cal),
            plotWidth: 320,
            now: now,
            calendar: cal
        )
        let month = HealthChartMath.xAxisMarks(
            range: .lastMonth,
            domain: HealthChartMath.historyXDomain(range: .lastMonth, now: now, calendar: cal),
            plotWidth: 320,
            now: now,
            calendar: cal
        )
        let year = HealthChartMath.xAxisMarks(
            range: .lastYear,
            domain: HealthChartMath.historyXDomain(range: .lastYear, now: now, calendar: cal),
            plotWidth: 320,
            now: now,
            calendar: cal
        )
        XCTAssertFalse(week.isEmpty)
        XCTAssertFalse(month.isEmpty)
        XCTAssertFalse(year.isEmpty)
        // Period picker drives format: 1W weekdays vs 1M month-day vs 1Y month.
        XCTAssertFalse(week[0].text.contains(where: \.isNumber), week[0].text)
        XCTAssertTrue(month[0].text.contains(where: \.isNumber), month[0].text)
        XCTAssertNotEqual(
            HealthChartMath.formatXAxisLabel(now, range: .lastWeek, now: now, calendar: cal),
            HealthChartMath.formatXAxisLabel(now, range: .lastYear, now: now, calendar: cal)
        )
    }

    func testAnnotationOpensLeadingNearTrailingEdge() {
        let lower = Date(timeIntervalSince1970: 0)
        let upper = Date(timeIntervalSince1970: 100)
        let domain = lower...upper
        XCTAssertFalse(HealthChartMath.annotationOpensLeading(at: Date(timeIntervalSince1970: 10), in: domain))
        XCTAssertTrue(HealthChartMath.annotationOpensLeading(at: Date(timeIntervalSince1970: 90), in: domain))
    }

    func testHistoryXDomainPadsProjectionCallouts() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let future = now.addingTimeInterval(30 * 86_400)
        let withProjection = HealthChartMath.historyXDomain(
            range: .lastMonth,
            extraDates: [future],
            now: now
        )
        let without = HealthChartMath.historyXDomain(range: .lastMonth, now: now)
        let padWith = withProjection.upperBound.timeIntervalSince(future)
        let padWithout = without.upperBound.timeIntervalSince(now)
        XCTAssertGreaterThan(padWith, padWithout)
        XCTAssertGreaterThanOrEqual(padWith, 4 * 86_400 - 1)
    }

    func testHistoryXDomainGrowsWithProjectionRevealProgress() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let future = now.addingTimeInterval(120 * 86_400)
        let start = HealthChartMath.historyXDomain(
            range: .lastThreeMonths,
            extraDates: [future],
            revealProgress: 0,
            now: now
        )
        let mid = HealthChartMath.historyXDomain(
            range: .lastThreeMonths,
            extraDates: [future],
            revealProgress: 0.5,
            now: now
        )
        let done = HealthChartMath.historyXDomain(
            range: .lastThreeMonths,
            extraDates: [future],
            revealProgress: 1,
            now: now
        )
        XCTAssertLessThan(start.upperBound, mid.upperBound)
        XCTAssertLessThan(mid.upperBound, done.upperBound)
        XCTAssertGreaterThanOrEqual(done.upperBound, future)
    }

    func testRevealedProjectionPathInterpolatesMidpoint() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 100)
        let path = [
            HealthMetricSample(value: 80, date: start),
            HealthMetricSample(value: 70, date: end)
        ]
        let none = HealthChartMath.revealedProjectionPath(path, progress: 0)
        XCTAssertEqual(none.count, 1)
        XCTAssertEqual(none[0].value, 80, accuracy: 0.001)

        let all = HealthChartMath.revealedProjectionPath(path, progress: 1)
        XCTAssertEqual(all.count, 2)

        let half = HealthChartMath.revealedProjectionPath(path, progress: 0.5)
        XCTAssertEqual(half.last?.date.timeIntervalSince1970 ?? -1, 50, accuracy: 0.01)
        XCTAssertEqual(half.last?.value ?? -1, 75, accuracy: 0.01)
    }

    func testProfileIdealWeightMigratesFromLegacyDecode() throws {
        let legacy = """
        {"heightCm":180,"ageYears":40,"sex":"male"}
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(UserBodyProfile.self, from: legacy)
        let expected = UserBodyProfile.suggestedIdealWeightKg(heightCm: 180)
        XCTAssertEqual(profile.idealWeightKg, expected, accuracy: 0.05)
        XCTAssertNil(profile.idealBodyFatPercent)
    }
}
