import XCTest
@testable import TheScale

final class ScaleCalibrationTests: XCTestCase {
    func testMajorTicksLandOnRoundMass() {
        XCTAssertTrue(AnalogScaleMarks.isMajor(display: 80))
        XCTAssertTrue(AnalogScaleMarks.isMajor(display: 75))
        XCTAssertTrue(AnalogScaleMarks.isMajor(display: 70))
        XCTAssertFalse(AnalogScaleMarks.isMajor(display: 77))
        XCTAssertFalse(AnalogScaleMarks.isMajor(display: 82))
        XCTAssertFalse(AnalogScaleMarks.isMajor(display: 78.5))
        XCTAssertTrue(AnalogScaleMarks.isMajor(display: 155, majorStep: 5))
        XCTAssertFalse(AnalogScaleMarks.isMajor(display: 157, majorStep: 5))
    }

    func testIdentityByDefault() {
        let cal = ScaleCalibration.default
        XCTAssertEqual(cal.apply(toRawKg: 80.0), 80.0, accuracy: 0.0001)
        XCTAssertFalse(cal.hasCorrection)
    }

    func testOffsetCaptureMatchesAlexMass() {
        var cal = ScaleCalibration.default
        cal.referenceMassKg = 7.926
        cal.captureMode = .offset
        XCTAssertTrue(cal.capture(rawKg: 7.90))
        XCTAssertTrue(cal.isActive)
        XCTAssertEqual(cal.scaleFactor, 1.0, accuracy: 0.00001)
        XCTAssertEqual(cal.offsetKg, 0.026, accuracy: 0.0001)
        XCTAssertEqual(cal.apply(toRawKg: 7.90), 7.926, accuracy: 0.0001)
    }

    func testFactorCaptureSetsMultiplier() {
        var cal = ScaleCalibration.default
        cal.referenceMassKg = 5.0
        cal.captureMode = .factor
        XCTAssertTrue(cal.capture(rawKg: 5.1))
        XCTAssertEqual(cal.scaleFactor, 5.0 / 5.1, accuracy: 0.00001)
        XCTAssertEqual(cal.offsetKg, 0, accuracy: 0.00001)
        XCTAssertEqual(cal.apply(toRawKg: 5.1), 5.0, accuracy: 0.001)
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
        cal.referenceMassKg = 7.926
        _ = cal.captureAsOffset(rawKg: 7.90)
        cal.reset()
        XCTAssertEqual(cal.referenceMassKg, 7.926, accuracy: 0.0001)
        XCTAssertFalse(cal.hasCorrection)
        XCTAssertEqual(cal.apply(toRawKg: 70.0), 70.0, accuracy: 0.0001)
    }

    func testCaptureRejectsTinyMass() {
        var cal = ScaleCalibration.default
        XCTAssertFalse(cal.capture(rawKg: 0.01))
        XCTAssertFalse(cal.isActive)
    }

    func testShortTrendTitleFitsChip() {
        XCTAssertEqual(WeightTrend.unknown.shortTitle, "None")
        XCTAssertLessThanOrEqual(WeightTrend.unknown.shortTitle.count, 8)
    }
}
