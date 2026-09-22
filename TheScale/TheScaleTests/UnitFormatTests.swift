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
}
