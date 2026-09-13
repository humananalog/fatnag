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
