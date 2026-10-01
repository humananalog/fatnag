import XCTest
@testable import TheScale

final class ScaleStorefrontTests: XCTestCase {
    func testHumanAnalogProductIDsMatchPlans() {
        XCTAssertEqual(ScaleStorefront.bundleID, "app.thescale.ios")
        XCTAssertEqual(ScaleStorefront.developmentTeamID, "XHVW66YM39")
        XCTAssertEqual(ScaleStorefront.sellerName, "Human Analog Limited")
        XCTAssertEqual(ScaleStorefront.plusProductID, "app.thescale.ios.plus.monthly")
        XCTAssertEqual(ScaleStorefront.proProductID, "app.thescale.ios.pro.monthly")
        XCTAssertEqual(ScaleStorefront.plusAnnualProductID, "app.thescale.ios.plus.annual")
        XCTAssertEqual(ScaleStorefront.proAnnualProductID, "app.thescale.ios.pro.annual")
        XCTAssertEqual(
            ScaleStorefront.allPaidProductIDs,
            Set([
                "app.thescale.ios.plus.annual",
                "app.thescale.ios.plus.monthly",
                "app.thescale.ios.pro.annual",
                "app.thescale.ios.pro.monthly"
            ])
        )
        XCTAssertEqual(ScalePlan.plus.storeProductID(period: .monthly), ScaleStorefront.plusProductID)
        XCTAssertEqual(ScalePlan.pro.storeProductID(period: .annual), ScaleStorefront.proAnnualProductID)
    }

    func testAnnualIsCheaperThanTwelveMonths() {
        XCTAssertEqual(ScalePlan.plus.annualPriceUSD, Decimal(string: "19.99")!)
        XCTAssertEqual(ScalePlan.pro.annualPriceUSD, Decimal(string: "79.99")!)
        XCTAssertLessThan(
            ScalePlan.plus.annualPriceUSD,
            ScalePlan.plus.monthlyPriceUSD * 12
        )
        XCTAssertLessThan(
            ScalePlan.pro.annualPriceUSD,
            ScalePlan.pro.monthlyPriceUSD * 12
        )
    }

    func testProductIDMapsToPlanForMonthlyAndAnnual() {
        XCTAssertEqual(ScalePlan.plan(forProductID: "app.thescale.ios.plus.monthly"), .plus)
        XCTAssertEqual(ScalePlan.plan(forProductID: "app.thescale.ios.plus.annual"), .plus)
        XCTAssertEqual(ScalePlan.plan(forProductID: "app.thescale.ios.pro.monthly"), .pro)
        XCTAssertEqual(ScalePlan.plan(forProductID: "app.thescale.ios.pro.annual"), .pro)
        XCTAssertNil(ScalePlan.plan(forProductID: "unknown"))
    }

    func testBillingPeriodDefaultsOrderHasAnnualFirstInPickerCases() {
        // Paywall defaults to .annual in @State; CaseIterable order is annual then monthly.
        XCTAssertEqual(ScaleBillingPeriod.allCases.first, .annual)
    }

    func testCommerceLaneCopyMentionsHumanAnalog() {
        XCTAssertTrue(ScaleCommerceLane.localStoreKitConfig.title.contains("Human Analog"))
        XCTAssertTrue(ScaleCommerceLane.appStoreSandbox.title.contains("Human Analog"))
        XCTAssertTrue(ScaleCommerceLane.localStoreKitConfig.detail.contains("Products.storekit"))
        XCTAssertTrue(ScaleCommerceLane.debugOverride.detail.contains("Use StoreKit"))
    }
}
