import Foundation
import StoreKit

/// Human Analog App Store identity + how The Scale resolves commerce in debug vs device.
enum ScaleStorefront {
    /// App Store Connect seller / legal entity.
    static let sellerName = "Human Analog Limited"
    /// Apple Developer Team ID (signing + ASC).
    static let developmentTeamID = "XHVW66YM39"
    /// iOS app bundle id (must match ASC app record).
    static let bundleID = "app.thescale.ios"
    /// Subscription group display name in ASC (matches `Config/Products.storekit`).
    static let subscriptionGroupName = "Coach"
    /// Local StoreKit Configuration used by the Debug scheme.
    static let localStoreKitConfigPath = "Config/Products.storekit"
    /// Public privacy URL required by ASC.
    static var privacyPolicyURL: URL { ScaleLegal.privacyPolicyURL }

    static var plusProductID: String { ScalePlan.plus.storeProductID! }
    static var proProductID: String { ScalePlan.pro.storeProductID! }

    static var allPaidProductIDs: Set<String> {
        Set(ScalePlan.allCases.compactMap(\.storeProductID))
    }
}

/// How purchases are resolved right now (Settings + paywall honesty line).
enum ScaleCommerceLane: String, Sendable {
    /// DEBUG scheme with `Products.storekit` attached. Real purchase UI, local receipts.
    case localStoreKitConfig
    /// Device / TestFlight using Human Analog App Store Connect sandbox.
    case appStoreSandbox
    /// App Store production.
    case appStoreProduction
    /// DEBUG only: forced plan, StoreKit ignored.
    case debugOverride

    var title: String {
        switch self {
        case .localStoreKitConfig: return "Local StoreKit (Human Analog config)"
        case .appStoreSandbox: return "App Store sandbox (Human Analog)"
        case .appStoreProduction: return "App Store production"
        case .debugOverride: return "DEBUG plan override"
        }
    }

    var detail: String {
        switch self {
        case .localStoreKitConfig:
            return "Scheme uses \(ScaleStorefront.localStoreKitConfigPath). Buy Plus/Pro without ASC sandbox. Clear any DEBUG override first."
        case .appStoreSandbox:
            return "Signed into a Sandbox Apple ID. Products must exist under Human Analog (\(ScaleStorefront.developmentTeamID)) in App Store Connect."
        case .appStoreProduction:
            return "Live App Store. Human Analog seller of record."
        case .debugOverride:
            return "StoreKit purchases are ignored. Pick “Use StoreKit” in Settings to exercise the real paywall."
        }
    }
}
