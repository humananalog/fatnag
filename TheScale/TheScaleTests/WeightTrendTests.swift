import XCTest
@testable import TheScale

final class WeightTrendTests: XCTestCase {
    func testLossBelowThreshold() {
        let trend = WeightTrend.from(currentKg: 79.5, baselineKg: 80.0)
        XCTAssertEqual(trend, .loss(deltaKg: -0.5))
    }

    func testGainAboveThreshold() {
        let trend = WeightTrend.from(currentKg: 80.3, baselineKg: 80.0)
        guard case .gain(let delta) = trend else {
            return XCTFail("expected gain, got \(trend)")
        }
        XCTAssertEqual(delta, 0.3, accuracy: 0.000_1)
    }

    func testStableWithinBand() {
        let trend = WeightTrend.from(currentKg: 80.1, baselineKg: 80.0)
        guard case .stable(let delta) = trend else {
            return XCTFail("expected stable, got \(trend)")
        }
        XCTAssertEqual(delta, 0.1, accuracy: 0.000_1)
    }

    func testUnknownWithoutBaseline() {
        XCTAssertEqual(WeightTrend.from(currentKg: 80.0, baselineKg: nil), .unknown)
    }

    func testSubtitleUsesPreferredUnits() {
        let trend = WeightTrend.from(currentKg: 79.5, baselineKg: 80.0)
        let imperial = trend.subtitle(system: .imperial)
        XCTAssertTrue(imperial.contains("lb") || imperial.contains("oz"), imperial)
        XCTAssertFalse(imperial.contains(" kg"))
    }

    func testLiveDecodeUnstabilizedWeight() throws {
        var bytes = [UInt8](repeating: 0, count: 13)
        bytes[0] = 0x02
        bytes[1] = 0x00 // not stabilized
        bytes[11] = 0xB0; bytes[12] = 0x36 // 70.00 kg
        let measurement = try XCTUnwrap({
            if case .success(let m) = MiScale2FrameDecoder.decodeLive(Data(bytes)) { return m }
            return nil
        }())
        XCTAssertEqual(measurement.weightKg, 70.0, accuracy: 0.001)
        XCTAssertFalse(measurement.isStabilized)
        XCTAssertFalse(measurement.hasImpedance)
    }

    func testStrictDecodeStillRejectsUnstabilized() {
        var bytes = [UInt8](repeating: 0, count: 13)
        bytes[0] = 0x02
        bytes[1] = 0x00
        bytes[11] = 0xB0; bytes[12] = 0x36
        XCTAssertEqual(MiScale2FrameDecoder.decode(Data(bytes)), .failure(.notStabilized))
    }
}
