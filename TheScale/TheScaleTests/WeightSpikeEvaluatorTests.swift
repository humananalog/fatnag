import XCTest
@testable import TheScale

final class WeightSpikeEvaluatorTests: XCTestCase {
    func testImpossibleJump70to90In24h() {
        let now = Date()
        let verdict = WeightSpikeEvaluator.evaluate(
            weighedKg: 90,
            priorKg: 70,
            priorDate: now.addingTimeInterval(-20 * 3_600),
            now: now
        )
        XCTAssertEqual(verdict?.kind, .impossible)
        XCTAssertEqual(verdict?.deltaKg ?? 0, 20, accuracy: 0.01)
    }

    func testNotableGainAbout3kg() {
        let now = Date()
        let verdict = WeightSpikeEvaluator.evaluate(
            weighedKg: 83.2,
            priorKg: 80.0,
            priorDate: now.addingTimeInterval(-18 * 3_600),
            now: now
        )
        XCTAssertEqual(verdict?.kind, .notableGain)
    }

    func testNormalDayDeltaIsNil() {
        let now = Date()
        let verdict = WeightSpikeEvaluator.evaluate(
            weighedKg: 80.4,
            priorKg: 80.1,
            priorDate: now.addingTimeInterval(-24 * 3_600),
            now: now
        )
        XCTAssertNil(verdict)
    }

    func testRecoveryIgnoresSpikeForWeekStart() {
        let spike = WeightSpikeVerdict(
            kind: .notableGain,
            deltaKg: 3.2,
            priorKg: 80,
            weighedKg: 83.2,
            hoursSincePrior: 20,
            reason: "test"
        )
        let plan = WeightSpikeEvaluator.recoveryPlan(
            name: "Alex",
            spike: spike,
            weekStartKg: 80,
            idealKg: 72,
            system: .metric
        )
        XCTAssertTrue(plan.ignoreSpikeForWeekStart)
        XCTAssertLessThan(plan.weeklyDeltaKg, 0)
        XCTAssertLessThan(plan.sundayTargetKg, spike.weighedKg)
        XCTAssertFalse(plan.kickHeadline.isEmpty)
        XCTAssertGreaterThanOrEqual(plan.actionLines.count, 3)
    }

    func testSafeLengthAndMaskedMass() {
        XCTAssertEqual(ProgressBounds.safeLength(-1), 0)
        XCTAssertTrue(MassPrivacyStore.maskedMass(system: .metric).contains("•"))
        XCTAssertTrue(MassPrivacyStore.maskedMass(system: .imperial).contains("•"))
    }
}
