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

    func testWeightDomainFloorsAtIdeal() {
        let domain = HealthChartMath.weightDomain(values: [78, 80, 79.2], idealKg: 72)
        XCTAssertEqual(domain.lowerBound, 72, accuracy: 0.001)
        XCTAssertGreaterThan(domain.upperBound, 80)
    }

    func testWeightDomainKeepsIdealFloorEvenIfDataIsHigher() {
        let domain = HealthChartMath.weightDomain(values: [90, 91], idealKg: 75)
        XCTAssertEqual(domain.lowerBound, 75, accuracy: 0.001)
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
