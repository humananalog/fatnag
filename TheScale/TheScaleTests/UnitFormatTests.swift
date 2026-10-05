import XCTest
@testable import TheScale

final class UnitFormatTests: XCTestCase {
    func testMetricPassthrough() {
        XCTAssertEqual(UnitFormat.mass(fromKg: 78.5, system: .metric), 78.5, accuracy: 0.001)
        XCTAssertEqual(UnitFormat.height(fromCm: 178, system: .metric), 178, accuracy: 0.001)
        XCTAssertEqual(UnitFormat.portionGrams(140, system: .metric), "140 g")
        XCTAssertEqual(UnitFormat.portionMl(240, system: .metric), "240 ml")
    }

    func testImperialRoundTrip() {
        let kg = 80.0
        let lb = UnitFormat.mass(fromKg: kg, system: .imperial)
        let back = UnitFormat.kg(fromMass: lb, system: .imperial)
        XCTAssertEqual(back, kg, accuracy: 0.01)

        let cm = 180.0
        let inches = UnitFormat.height(fromCm: cm, system: .imperial)
        let backCm = UnitFormat.cm(fromHeight: inches, system: .imperial)
        XCTAssertEqual(backCm, cm, accuracy: 0.05)
    }

    func testCoachPromptMentionsUnits() {
        XCTAssertTrue(PreferredUnitSystem.metric.coachPromptLine.lowercased().contains("metric"))
        XCTAssertTrue(PreferredUnitSystem.imperial.coachPromptLine.lowercased().contains("imperial"))
    }

    func testStoreRoundTrip() {
        PreferredUnitSystemStore.save(.imperial)
        XCTAssertEqual(PreferredUnitSystemStore.load(), .imperial)
        PreferredUnitSystemStore.save(.metric)
        XCTAssertEqual(PreferredUnitSystemStore.load(), .metric)
    }

    /// Sub-1 kg absolute magnitude → grams (metric) / ounces (imperial).
    func testSubKilogramMassUsesGramsOrOunces() {
        XCTAssertEqual(UnitFormat.massString(0.65, system: .metric), "650g")
        XCTAssertEqual(UnitFormat.massDeltaString(0.65, system: .metric), "+650g")
        XCTAssertEqual(UnitFormat.massDeltaString(-0.35, system: .metric), "-350g")
        XCTAssertEqual(UnitFormat.massString(78.5, system: .metric, fractionDigits: 1), "78.5 kg")
        XCTAssertEqual(UnitFormat.massDeltaString(-1.2, system: .metric), "-1.20 kg")

        let oz = UnitFormat.massDeltaString(0.65, system: .imperial)
        XCTAssertTrue(oz.contains("oz"), oz)
        XCTAssertTrue(oz.hasPrefix("+"), oz)
        XCTAssertFalse(oz.contains("lb"), oz)

        let bigLb = UnitFormat.massString(80, system: .imperial, fractionDigits: 1)
        XCTAssertTrue(bigLb.contains("lb"), bigLb)
        XCTAssertFalse(bigLb.contains("oz"), bigLb)
    }

    func testSundayTitleAndParseRoundTrip() {
        let kg = 82.4
        let metricTitle = UnitFormat.sundayTitle(kg: kg, system: .metric)
        XCTAssertEqual(metricTitle, "Sunday 82.40 kg")
        XCTAssertEqual(WeeklyGoalSurfaceEngine.parseSundayKg(from: metricTitle) ?? -1, kg, accuracy: 0.01)

        let imperialTitle = UnitFormat.sundayTitle(kg: kg, system: .imperial)
        XCTAssertTrue(imperialTitle.contains("lb"), imperialTitle)
        XCTAssertEqual(WeeklyGoalSurfaceEngine.parseSundayKg(from: imperialTitle) ?? -1, kg, accuracy: 0.05)
    }

    func testMixedPoundsAndCentimetres() {
        let mixed = PreferredUnitSystem.poundsAndCentimeters
        XCTAssertEqual(mixed.massLabel, "lb")
        XCTAssertEqual(mixed.heightLabel, "cm")
        XCTAssertEqual(UnitFormat.mass(fromKg: 80, system: mixed), UnitFormat.mass(fromKg: 80, system: .imperial), accuracy: 0.001)
        XCTAssertEqual(UnitFormat.height(fromCm: 170, system: mixed), 170, accuracy: 0.001)
        XCTAssertTrue(mixed.coachPromptLine.contains("lb"))
        XCTAssertTrue(mixed.coachPromptLine.contains("cm"))

        PreferredUnitSystemStore.save(.poundsAndCentimeters)
        XCTAssertEqual(PreferredUnitSystemStore.load(), .poundsAndCentimeters)
        PreferredUnitSystemStore.save(.metric)
        XCTAssertEqual(PreferredUnitSystemStore.load(), .metric)
    }

    func testCombiningIndependentAxes() {
        XCTAssertEqual(PreferredUnitSystem.combining(massImperial: true, heightImperial: false), .poundsAndCentimeters)
        XCTAssertEqual(PreferredUnitSystem.combining(massImperial: false, heightImperial: true), .kilogramsAndInches)
        XCTAssertEqual(PreferredUnitSystem.combining(massImperial: false, heightImperial: false), .metric)
        XCTAssertEqual(PreferredUnitSystem.combining(massImperial: true, heightImperial: true), .imperial)
    }

    func testWeeklyMiniGoalStatusLineUsesPreferredUnits() {
        var goal = WeeklyMiniGoal.default
        goal.targetDeltaKg = -0.4
        goal.weekStartKg = 84.0
        let line = goal.statusLine(currentKg: 83.7, system: .imperial)
        XCTAssertTrue(line.contains("lb") || line.contains("oz"), line)
        XCTAssertFalse(line.contains(" kg"))
    }
}
