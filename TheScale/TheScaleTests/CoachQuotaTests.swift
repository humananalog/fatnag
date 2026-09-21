import XCTest
@testable import TheScale

@MainActor
final class CoachQuotaTests: XCTestCase {
    override func setUp() async throws {
        CoachWeeklyQuota.debugReset()
    }

    override func tearDown() async throws {
        CoachWeeklyQuota.debugReset()
    }

    func testPlanCreditsMatchPricingTiers() {
        XCTAssertEqual(ScalePlan.free.weeklyGrokCredits, 5)
        XCTAssertEqual(ScalePlan.plus.weeklyGrokCredits, 28)
        XCTAssertEqual(ScalePlan.pro.weeklyGrokCredits, 120)
        XCTAssertEqual(ScalePlan.free.monthlyPriceUSD, 0)
        XCTAssertEqual(ScalePlan.plus.monthlyPriceUSD, 2)
        XCTAssertEqual(ScalePlan.pro.monthlyPriceUSD, 8)
        XCTAssertEqual(ScalePlan.plus.storeProductID, "app.thescale.ios.plus.monthly")
        XCTAssertEqual(ScalePlan.pro.storeProductID, "app.thescale.ios.pro.monthly")
    }

    func testUpgradeTargets() {
        XCTAssertEqual(ScalePlan.free.upgradeTarget, .plus)
        XCTAssertEqual(ScalePlan.plus.upgradeTarget, .pro)
        XCTAssertNil(ScalePlan.pro.upgradeTarget)
        XCTAssertEqual(ScalePlan.best(of: [.free, .plus, .pro]), .pro)
        XCTAssertEqual(ScalePlan.best(of: [.free, .plus]), .plus)
    }

    func testFreeExhaustsThenLocksWithUpgradeCopy() {
        for _ in 0..<5 {
            XCTAssertNil(CoachWeeklyQuota.consume(.chat, plan: .free))
        }
        let lock = CoachWeeklyQuota.consume(.chat, plan: .free)
        XCTAssertNotNil(lock)
        XCTAssertTrue(lock!.contains("Plus"))
        XCTAssertTrue(lock!.contains("$2"))
        XCTAssertTrue(CoachWeeklyQuota.snapshot(plan: .free).isExhausted)
    }

    func testHigherTierAllowMoreCreditsSameWeek() {
        CoachWeeklyQuota.debugSetUsed(5)
        XCTAssertTrue(CoachWeeklyQuota.snapshot(plan: .free).isExhausted)
        XCTAssertFalse(CoachWeeklyQuota.snapshot(plan: .plus).isExhausted)
        XCTAssertEqual(CoachWeeklyQuota.snapshot(plan: .plus).remaining, 23)
        XCTAssertNil(CoachWeeklyQuota.consume(.chat, plan: .plus))
        XCTAssertEqual(CoachWeeklyQuota.snapshot(plan: .plus).used, 6)
    }

    func testPlusSupportsActiveWeeklyBudget() {
        // ≈4 live Grok asks/day × 7 ≈ 28 for Plus.
        for _ in 0..<28 {
            XCTAssertNil(CoachWeeklyQuota.consume(.fitnessCheck, plan: .plus))
        }
        XCTAssertNotNil(CoachWeeklyQuota.consume(.fitnessCheck, plan: .plus))
        XCTAssertTrue(CoachWeeklyQuota.canConsume(plan: .pro))
    }

    func testLiveModelIsNonReasoning() {
        XCTAssertEqual(GrokClient.liveModel, "grok-4.20-non-reasoning")
        XCTAssertTrue(GrokClient.liveModel.hasSuffix("non-reasoning"))
        XCTAssertFalse(GrokClient.liveModel.contains("mini"))
    }
}
