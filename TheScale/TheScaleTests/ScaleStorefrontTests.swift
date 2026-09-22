import XCTest
@testable import TheScale

final class ScaleStorefrontTests: XCTestCase {
    func testHumanAnalogProductIDsMatchPlans() {
        XCTAssertEqual(ScaleStorefront.bundleID, "app.thescale.ios")
        XCTAssertEqual(ScaleStorefront.developmentTeamID, "XHVW66YM39")
        XCTAssertEqual(ScaleStorefront.sellerName, "Human Analog Limited")
        XCTAssertEqual(ScaleStorefront.plusProductID, "app.thescale.ios.plus.monthly")
        XCTAssertEqual(ScaleStorefront.proProductID, "app.thescale.ios.pro.monthly")
        XCTAssertEqual(ScaleStorefront.allPaidProductIDs, [
            "app.thescale.ios.plus.monthly",
            "app.thescale.ios.pro.monthly"
        ])
        XCTAssertEqual(ScalePlan.plus.storeProductID, ScaleStorefront.plusProductID)
        XCTAssertEqual(ScalePlan.pro.storeProductID, ScaleStorefront.proProductID)
    }

    func testCommerceLaneCopyMentionsHumanAnalog() {
        XCTAssertTrue(ScaleCommerceLane.localStoreKitConfig.title.contains("Human Analog"))
        XCTAssertTrue(ScaleCommerceLane.appStoreSandbox.title.contains("Human Analog"))
        XCTAssertTrue(ScaleCommerceLane.localStoreKitConfig.detail.contains("Products.storekit"))
        XCTAssertTrue(ScaleCommerceLane.debugOverride.detail.contains("Use StoreKit"))
    }
}
