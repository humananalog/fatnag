import XCTest
@testable import TheScale

final class ScaleCalibrationTests: XCTestCase {
    func testMajorTicksLandOnRoundMass() {
        XCTAssertTrue(AnalogScaleMarks.isMajor(display: 80))
        XCTAssertTrue(AnalogScaleMarks.isMajor(display: 75))
        XCTAssertTrue(AnalogScaleMarks.isMajor(display: 70))
        XCTAssertTrue(AnalogScaleMarks.isMajor(display: 70.02))
        XCTAssertFalse(AnalogScaleMarks.isMajor(display: 77))
        XCTAssertFalse(AnalogScaleMarks.isMajor(display: 82))
        XCTAssertFalse(AnalogScaleMarks.isMajor(display: 78.5))
        XCTAssertTrue(AnalogScaleMarks.isMajor(display: 155, majorStep: 5))
        XCTAssertFalse(AnalogScaleMarks.isMajor(display: 157, majorStep: 5))
    }

    func testLayoutUsesOnlySelectedUnitGrid() {
        let boundsKg: ClosedRange<Double> = 60...90
        let metric = AnalogScaleLayout.make(boundsKg: boundsKg, system: .metric)
        XCTAssertEqual(metric.minorStep, 0.5)
        XCTAssertEqual(metric.system, .metric)
        let metricMajors = metric.majorLabels()
        XCTAssertFalse(metricMajors.isEmpty)
        for value in metricMajors {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 5), 0, accuracy: 0.05)
            // Metric majors stay in a plausible kg band for these bounds — not lb hundreds.
            XCTAssertLessThan(value, 120)
        }

        let imperial = AnalogScaleLayout.make(boundsKg: boundsKg, system: .imperial)
        XCTAssertEqual(imperial.minorStep, 1.0)
        XCTAssertEqual(imperial.system, .imperial)
        let imperialMajors = imperial.majorLabels()
        XCTAssertFalse(imperialMajors.isEmpty)
        for value in imperialMajors {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 5), 0, accuracy: 0.05)
            // Imperial majors are lb — well above typical kg dream-band numbers.
            XCTAssertGreaterThan(value, 120)
        }

        // The two grids must not share the same major set (would mean dual-unit marks).
        let metricSet = Set(metricMajors.map { Int($0.rounded()) })
        let imperialSet = Set(imperialMajors.map { Int($0.rounded()) })
        XCTAssertTrue(metricSet.isDisjoint(with: imperialSet))
    }

    func testMinAndMaxMarksSpan350DegreesPerUnitSystem() {
        let boundsKg: ClosedRange<Double> = 60...90
        let wideKg: ClosedRange<Double> = 40...180
        for system in [PreferredUnitSystem.metric, PreferredUnitSystem.imperial] {
            for bounds in [boundsKg, wideKg] {
                let layout = AnalogScaleLayout.make(boundsKg: bounds, system: system)
                let span = layout.boundsDisplay.upperBound - layout.boundsDisplay.lowerBound
                XCTAssertGreaterThan(span, 0)
                XCTAssertEqual(span * layout.degreesPerUnit, AnalogScaleLayout.dialArcDegrees, accuracy: 0.001)
                XCTAssertEqual(AnalogScaleLayout.dialArcDegrees, 350, accuracy: 0.001)
                // In-band marks stay on the arc and never lap a second time around the disc.
                let marks = layout.displayTicks()
                XCTAssertGreaterThanOrEqual(marks.count, 2)
                let first = (marks[0] - layout.boundsDisplay.lowerBound) * layout.degreesPerUnit
                let last = (marks[marks.count - 1] - layout.boundsDisplay.lowerBound) * layout.degreesPerUnit
                XCTAssertGreaterThanOrEqual(first, -0.001)
                XCTAssertLessThanOrEqual(last, AnalogScaleLayout.dialArcDegrees + 0.001)
            }
        }

        let metric = AnalogScaleLayout.make(boundsKg: boundsKg, system: .metric)
        let imperial = AnalogScaleLayout.make(boundsKg: boundsKg, system: .imperial)
        XCTAssertNotEqual(metric.degreesPerUnit, imperial.degreesPerUnit)
        XCTAssertGreaterThan(metric.degreesPerUnit, imperial.degreesPerUnit)
    }

    func testWideOnboardingRangeKeepsReadableTickSpacing() {
        let layout = AnalogScaleLayout.make(boundsKg: ProfileNumericBounds.weightKg, system: .metric)
        let minorDegrees = layout.degreesPerUnit * layout.minorStep
        XCTAssertGreaterThanOrEqual(minorDegrees, 2.15)
        XCTAssertLessThan(layout.tickCount, 200)
        XCTAssertEqual(
            (layout.boundsDisplay.upperBound - layout.boundsDisplay.lowerBound) * layout.degreesPerUnit,
            AnalogScaleLayout.dialArcDegrees,
            accuracy: 0.001
        )

        let lbCm = AnalogScaleLayout.make(boundsKg: ProfileNumericBounds.weightKg, system: .poundsAndCentimeters)
        XCTAssertEqual(lbCm.minorStep, AnalogScaleLayout.make(boundsKg: ProfileNumericBounds.weightKg, system: .imperial).minorStep, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(lbCm.degreesPerUnit * lbCm.minorStep, 2.15)
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
