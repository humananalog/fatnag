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
        XCTAssertFalse(measurement.biaPending)
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

    /// Impedance flag set with 0 Ω means BIA still running: keep weight, mark pending.
    func testImpedanceFlagWithZeroOhmsIsPendingNotRejected() throws {
        var bytes = [UInt8](repeating: 0, count: 13)
        bytes[0] = 0x02
        bytes[1] = 0x22 // stable + impedance flag
        bytes[9] = 0; bytes[10] = 0 // 0 Ω
        bytes[11] = 0xB0; bytes[12] = 0x36

        let measurement = try XCTUnwrap(MiScale2FrameDecoder.decodeMeasurement(Data(bytes)))
        XCTAssertEqual(measurement.weightKg, 70.0, accuracy: 0.001)
        XCTAssertNil(measurement.impedanceOhms)
        XCTAssertFalse(measurement.hasImpedance)
        XCTAssertTrue(measurement.biaPending)
    }

    func testImpedanceFlagWithTooHighOhmsIsPending() throws {
        var bytes = [UInt8](repeating: 0, count: 13)
        bytes[0] = 0x02
        bytes[1] = 0x22
        bytes[9] = 0xB8; bytes[10] = 0x0B // 3000
        bytes[11] = 0xB0; bytes[12] = 0x36

        let measurement = try XCTUnwrap(MiScale2FrameDecoder.decodeMeasurement(Data(bytes)))
        XCTAssertNil(measurement.impedanceOhms)
        XCTAssertTrue(measurement.biaPending)
    }

    func testDecodeStabilizedWeightOnly() throws {
        var bytes = [UInt8](repeating: 0, count: 13)
        bytes[0] = 0x02
        bytes[1] = 0x20 // stabilized, no impedance bit
        bytes[11] = 0xB0; bytes[12] = 0x36

        let measurement = try XCTUnwrap(MiScale2FrameDecoder.decodeMeasurement(Data(bytes)))
        XCTAssertEqual(measurement.weightKg, 70.0, accuracy: 0.001)
        XCTAssertNil(measurement.impedanceOhms)
        XCTAssertFalse(measurement.hasImpedance)
        XCTAssertFalse(measurement.biaPending)
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

        let draft = EditableMeasurementDraft.from(
            measurement: ScaleMeasurement(
                weightKg: 70,
                impedanceOhms: 500,
                scaleDate: Date(),
                hasImpedance: true,
                biaPending: false,
                displayUnit: .kilogram,
                receivedAt: Date(),
                isStabilized: true
            ),
            composition: result,
            profile: profile
        )
        let leanPercent = try XCTUnwrap(draft.leanPercent)
        XCTAssertEqual(leanPercent, 100 - result.bodyFatPercent, accuracy: 0.05)
        XCTAssertEqual(leanPercent + result.bodyFatPercent, 100, accuracy: 0.05)
    }

    func testRejectsInvalidInputs() {
        let profile = UserBodyProfile.default
        XCTAssertNil(BodyCompositionCalculator.calculate(weightKg: 5, impedanceOhms: 500, profile: profile))
        XCTAssertNil(BodyCompositionCalculator.calculate(weightKg: 70, impedanceOhms: 0, profile: profile))
        XCTAssertNil(BodyCompositionCalculator.calculate(weightKg: 70, impedanceOhms: 3500, profile: profile))
    }
}

@MainActor
final class ScaleSessionImpedanceTests: XCTestCase {
    private final class FakeScanner: ScaleScanning {
        weak var delegate: ScaleScannerDelegate?
        func startScanning() {}
        func stop() {}
        func focus(on peripheralID: UUID) {}
        func emit(_ measurement: ScaleMeasurement) {
            delegate?.scaleScanner(self, didDecode: measurement)
        }
        func emitStatus(_ text: String) {
            delegate?.scaleScanner(self, transientStatus: text)
        }
    }

    private final class FakeHealth: HealthWriting {
        var isHealthDataAvailable: Bool { false }
        func requestAuthorizationIfNeeded() async throws {}
        func fetchRecentWeights(limit: Int) async throws -> [HealthWeightSample] { [] }
        func write(
            measurement: ScaleMeasurement,
            composition: BodyCompositionResult?,
            profile: UserBodyProfile
        ) async throws {}
        func write(draft: EditableMeasurementDraft, profile: UserBodyProfile) async throws {}
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool,
        timeoutSeconds: Double = 1.0
    ) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testUpgradesWeightOnlyToImpedance() async {
        let scanner = FakeScanner()
        let session = ScaleSessionViewModel(
            scanner: scanner,
            healthStore: FakeHealth(),
            profile: UserBodyProfile(heightCm: 175, ageYears: 35, sex: .male)
        )
        session.selectScale(
            DiscoveredScale(id: UUID(), name: "MIBFS", rssi: -40, lastSeen: Date())
        )

        let weightOnly = ScaleMeasurement(
            weightKg: 70,
            impedanceOhms: nil,
            scaleDate: nil,
            hasImpedance: false,
            biaPending: false,
            displayUnit: .kilogram
        )
        scanner.emit(weightOnly)
        await waitUntil { session.phase == .awaitingImpedance }
        XCTAssertEqual(session.phase, .awaitingImpedance)
        XCTAssertNil(session.composition)

        let withImpedance = ScaleMeasurement(
            weightKg: 70,
            impedanceOhms: 500,
            scaleDate: nil,
            hasImpedance: true,
            biaPending: false,
            displayUnit: .kilogram
        )
        scanner.emit(withImpedance)
        await waitUntil { session.latestMeasurement?.impedanceOhms == 500 }
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.latestMeasurement?.impedanceOhms, 500)
        XCTAssertNotNil(session.composition)
        XCTAssertGreaterThan(session.composition?.bodyFatPercent ?? 0, 5)
    }

    func testDoesNotDowngradeImpedanceToWeightOnly() async {
        let scanner = FakeScanner()
        let session = ScaleSessionViewModel(
            scanner: scanner,
            healthStore: FakeHealth(),
            profile: .default
        )
        session.selectScale(
            DiscoveredScale(id: UUID(), name: "MIBFS", rssi: -40, lastSeen: Date())
        )

        scanner.emit(
            ScaleMeasurement(
                weightKg: 70,
                impedanceOhms: 500,
                scaleDate: nil,
                hasImpedance: true,
                displayUnit: .kilogram
            )
        )
        await waitUntil { session.latestMeasurement?.impedanceOhms == 500 }
        scanner.emit(
            ScaleMeasurement(
                weightKg: 70.05,
                impedanceOhms: nil,
                scaleDate: nil,
                hasImpedance: false,
                displayUnit: .kilogram
            )
        )
        // Give the async hop a chance; value must remain impedance.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(session.latestMeasurement?.impedanceOhms, 500)
        XCTAssertNotNil(session.composition)
    }

    func testTransientHintsWhileAwaitingImpedance() async {
        let scanner = FakeScanner()
        let session = ScaleSessionViewModel(
            scanner: scanner,
            healthStore: FakeHealth(),
            profile: .default
        )
        session.selectScale(
            DiscoveredScale(id: UUID(), name: "MIBFS", rssi: -40, lastSeen: Date())
        )
        scanner.emit(
            ScaleMeasurement(
                weightKg: 70,
                impedanceOhms: nil,
                scaleDate: nil,
                hasImpedance: false,
                displayUnit: .kilogram
            )
        )
        await waitUntil { session.phase == .awaitingImpedance }
        scanner.emitStatus("Waiting for impedance sweep…")
        await waitUntil { session.liveHint == "Waiting for impedance sweep…" }
        XCTAssertEqual(session.liveHint, "Waiting for impedance sweep…")
    }
}

