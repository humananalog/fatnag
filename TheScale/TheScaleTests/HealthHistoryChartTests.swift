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

    func testScrollVisibleLengthEnabledForFullThreeMonthDomain() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let domain = HealthChartMath.historyXDomain(range: .lastThreeMonths, now: now)
        let length = HealthChartMath.scrollVisibleDomainLength(for: .lastThreeMonths, xDomain: domain)
        XCTAssertNotNil(length)
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        XCTAssertLessThan(try XCTUnwrap(length), span)
    }

    func testScrollVisibleLengthNilForShortRanges() {
        let now = Date()
        let domain = HealthChartMath.historyXDomain(range: .lastTwoWeeks, now: now)
        XCTAssertNil(
            HealthChartMath.scrollVisibleDomainLength(for: .lastTwoWeeks, xDomain: domain)
        )
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
