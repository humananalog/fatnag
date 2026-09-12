import XCTest
@testable import TheScale

final class ScaleCalibrationTests: XCTestCase {
    func testIdentityByDefault() {
        let cal = ScaleCalibration.default
        XCTAssertEqual(cal.apply(toRawKg: 80.0), 80.0, accuracy: 0.0001)
        XCTAssertFalse(cal.hasCorrection)
    }

    func testSinglePointCaptureSetsFactor() {
        var cal = ScaleCalibration.default
        cal.referenceMassKg = 5.0
        XCTAssertTrue(cal.capture(rawKg: 5.1))
        XCTAssertTrue(cal.isActive)
        XCTAssertEqual(cal.scaleFactor, 5.0 / 5.1, accuracy: 0.00001)
        XCTAssertEqual(cal.offsetKg, 0, accuracy: 0.00001)
        let corrected = cal.apply(toRawKg: 5.1)
        XCTAssertEqual(corrected, 5.0, accuracy: 0.001)
    }

    func testOffsetAppliesAfterFactor() {
        var cal = ScaleCalibration.default
        cal.scaleFactor = 1.0
        cal.offsetKg = -0.05
        cal.isActive = true
        XCTAssertEqual(cal.apply(toRawKg: 80.0), 79.95, accuracy: 0.0001)
    }

    func testResetKeepsReferenceMass() {
        var cal = ScaleCalibration.default
        cal.referenceMassKg = 5.0
        _ = cal.capture(rawKg: 4.9)
        cal.reset()
        XCTAssertEqual(cal.referenceMassKg, 5.0, accuracy: 0.0001)
        XCTAssertFalse(cal.hasCorrection)
        XCTAssertEqual(cal.apply(toRawKg: 70.0), 70.0, accuracy: 0.0001)
    }

    func testCaptureRejectsTinyMass() {
        var cal = ScaleCalibration.default
        XCTAssertFalse(cal.capture(rawKg: 0.01))
        XCTAssertFalse(cal.isActive)
    }
}
