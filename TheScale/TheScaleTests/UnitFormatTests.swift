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
}
