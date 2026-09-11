import XCTest
@testable import TheScale

final class MiScale2FrameDecoderTests: XCTestCase {
    /// Stabilized kg frame with impedance: 70.00 kg, 500 Ω.
    /// control0=0x02 (kg), control1=0x22 (stable|impedance), year=2024, weight raw=14000 (/200=70).
    func testDecodeStabilizedKgWithImpedance() throws {
        var bytes = [UInt8](repeating: 0, count: 13)
        bytes[0] = 0x02
        bytes[1] = 0x22 // bit1 impedance, bit5 stabilized
        bytes[2] = 0xE8; bytes[3] = 0x07 // 2024 LE
        bytes[4] = 9; bytes[5] = 11; bytes[6] = 12; bytes[7] = 30; bytes[8] = 0
        bytes[9] = 0xF4; bytes[10] = 0x01 // 500
        bytes[11] = 0xB0; bytes[12] = 0x36 // 14000

        let measurement = try XCTUnwrap(MiScale2FrameDecoder.decodeMeasurement(Data(bytes)))
        XCTAssertEqual(measurement.weightKg, 70.0, accuracy: 0.001)
        XCTAssertEqual(measurement.impedanceOhms, 500)
        XCTAssertTrue(measurement.hasImpedance)
        XCTAssertEqual(measurement.displayUnit, .kilogram)
    }

    func testRejectsUnstabilizedFrame() {
        var bytes = [UInt8](repeating: 0, count: 13)
        bytes[0] = 0x02
        bytes[1] = 0x02 // impedance only, not stable
        bytes[11] = 0xB0; bytes[12] = 0x36

        let result = MiScale2FrameDecoder.decode(Data(bytes))
        XCTAssertEqual(result, .failure(.notStabilized))
    }

    func testRejectsWeightRemoved() {
        var bytes = [UInt8](repeating: 0, count: 13)
        bytes[0] = 0x02
        bytes[1] = 0xA0 // stable + removed
        bytes[11] = 0xB0; bytes[12] = 0x36

        let result = MiScale2FrameDecoder.decode(Data(bytes))
        XCTAssertEqual(result, .failure(.weightRemoved))
    }

    func testDecodeLbs() throws {
        var bytes = [UInt8](repeating: 0, count: 13)
        bytes[0] = 0x03 // lbs bit
        bytes[1] = 0x20 // stabilized, no impedance
        // 154.32 lb ≈ 70.00 kg → raw = 15432
        bytes[11] = 0x48; bytes[12] = 0x3C

        let measurement = try XCTUnwrap(MiScale2FrameDecoder.decodeMeasurement(Data(bytes)))
        XCTAssertEqual(measurement.displayUnit, .pound)
        XCTAssertEqual(measurement.weightKg, 70.0, accuracy: 0.05)
        XCTAssertNil(measurement.impedanceOhms)
    }

    func testWrongLength() {
        XCTAssertEqual(MiScale2FrameDecoder.decode(Data([0x00])), .failure(.wrongLength(1)))
    }

    func testMatchesAdvertisedName() {
        XCTAssertTrue(MiScale2FrameDecoder.matchesAdvertisedName("MIBFS"))
        XCTAssertTrue(MiScale2FrameDecoder.matchesAdvertisedName("mibfs-abc"))
        XCTAssertFalse(MiScale2FrameDecoder.matchesAdvertisedName("Apple Watch"))
    }
}

final class BodyCompositionCalculatorTests: XCTestCase {
    func testBMI() {
        let bmi = BodyCompositionCalculator.bodyMassIndex(weightKg: 70, heightCm: 175)
        XCTAssertEqual(bmi, 22.857, accuracy: 0.01)
    }

    func testCompositionInPlausibleRange() throws {
        let profile = UserBodyProfile(heightCm: 175, ageYears: 35, sex: .male)
        let result = try XCTUnwrap(
            BodyCompositionCalculator.calculate(weightKg: 70, impedanceOhms: 500, profile: profile)
        )
        XCTAssertEqual(result.bmi, 22.857, accuracy: 0.01)
        XCTAssertGreaterThan(result.bodyFatPercent, 5)
        XCTAssertLessThan(result.bodyFatPercent, 40)
        XCTAssertGreaterThan(result.waterPercent, 40)
        XCTAssertLessThan(result.waterPercent, 70)
        XCTAssertGreaterThan(result.boneMassKg, 1)
        XCTAssertLessThan(result.boneMassKg, 5)
        XCTAssertGreaterThan(result.muscleMassKg, 20)
        XCTAssertLessThan(result.muscleMassKg, 70)
        XCTAssertEqual(
            result.leanBodyMassKg,
            70 - (70 * result.bodyFatPercent / 100),
            accuracy: 0.01
        )
    }

    func testRejectsInvalidInputs() {
        let profile = UserBodyProfile.default
        XCTAssertNil(BodyCompositionCalculator.calculate(weightKg: 5, impedanceOhms: 500, profile: profile))
        XCTAssertNil(BodyCompositionCalculator.calculate(weightKg: 70, impedanceOhms: 0, profile: profile))
        XCTAssertNil(BodyCompositionCalculator.calculate(weightKg: 70, impedanceOhms: 3500, profile: profile))
    }
}
