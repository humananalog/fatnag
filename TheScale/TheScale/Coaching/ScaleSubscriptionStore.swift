import Foundation
import StoreKit

/// StoreKit 2 subscription + optional DEBUG override. Effective plan drives weekly Grok limits.
@MainActor
final class ScaleSubscriptionStore: ObservableObject {
    static let shared = ScaleSubscriptionStore()

    @Published private(set) var plan: ScalePlan = .free
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseError: String?
    @Published private(set) var restoreMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    /// Bumps when weekly Grok credits change so Settings / Coach refresh status lines.
    @Published private(set) var quotaEpoch: Int = 0
    /// Last product-load note for Settings / paywall diagnostics.
    @Published private(set) var productsStatusLine: String = "Products not loaded yet."

    /// True when paid products failed to load and the paywall cannot sell yet.
    var hasEmptyCatalog: Bool {
        !isLoading && products.isEmpty
    }

    var isBusy: Bool { isLoading || isPurchasing || isRestoring }

    /// DEBUG / TestFlight QA: force a plan without StoreKit.
    #if DEBUG
    private static let debugOverrideKey = "thescale.debugPlanOverride"
    var debugOverride: ScalePlan? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.debugOverrideKey) else { return nil }
            return ScalePlan(rawValue: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: Self.debugOverrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.debugOverrideKey)
            }
            Task { await refreshPlanFromEntitlements() }
        }
    }

    /// Clear forced plan and reload real StoreKit products (local config or sandbox).
    func useRealStoreKit() {
        debugOverride = nil
        purchaseError = nil
        Task { await refresh() }
    }

    /// Instant Free / Plus / Pro for DEBUG paywall and Settings. No StoreKit sheet.
    @discardableResult
    func applyDevPlan(_ plan: ScalePlan) -> Bool {
        purchaseError = nil
        debugOverride = plan
        self.plan = plan
        noteQuotaChange()
        return true
    }

    /// True while a DEBUG override is driving the effective plan.
    var isDevPlanOverrideActive: Bool { debugOverride != nil }
    #endif

    /// DEBUG builds always allow on-the-fly tier taps from the paywall.
    var allowsInstantDevTier: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { await listenForTransactions() }
        Task { await refresh() }
    }

    var quotaSnapshot: CoachWeeklyQuota.Snapshot {
        CoachWeeklyQuota.snapshot(plan: plan)
    }

    var commerceLane: ScaleCommerceLane {
        #if DEBUG
        if debugOverride != nil { return .debugOverride }
        return .localStoreKitConfig
        #else
        // TestFlight and App Store both use ASC products under Human Analog.
        // Sandbox Apple IDs apply on TestFlight; production receipts after App Store release.
        return .appStoreProduction
        #endif
    }

    var commerceStatusLine: String {
        "\(commerceLane.title). \(productsStatusLine)"
    }

    func noteQuotaChange() {
        quotaEpoch &+= 1
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await loadProducts()
        await refreshPlanFromEntitlements()
    }

    func loadProducts() async {
        let ids = ScaleStorefront.allPaidProductIDs
        guard !ids.isEmpty else { return }
        do {
            let loaded = try await Product.products(for: ids)
                .sorted { $0.price < $1.price }
            products = loaded
            if loaded.isEmpty {
                productsStatusLine = "0 products for \(ids.sorted().joined(separator: ", ")). Check Human Analog ASC or \(ScaleStorefront.localStoreKitConfigPath)."
            } else {
                let labels = loaded.map { "\($0.id)=\($0.displayPrice)" }.joined(separator: ", ")
                productsStatusLine = "Loaded \(loaded.count): \(labels)"
            }
        } catch {
            products = []
            purchaseError = error.localizedDescription
            productsStatusLine = "Product load failed: \(error.localizedDescription)"
        }
    }

    func product(for plan: ScalePlan) -> Product? {
        guard let id = plan.storeProductID else { return nil }
        return products.first { $0.id == id }
    }

    /// Prefer live StoreKit price; fall back to marketing label.
    func priceLabel(for plan: ScalePlan) -> String {
        if plan == .free { return plan.priceLabel }
        if let product = product(for: plan) {
            return "\(product.displayPrice) / month"
        }
        return plan.priceLabel
    }

    @discardableResult
    func purchase(_ plan: ScalePlan) async -> Bool {
        #if DEBUG
        // Dev: paywall tier taps apply instantly (no StoreKit sheet).
        return applyDevPlan(plan)
        #else
        guard let product = product(for: plan) else {
            purchaseError = """
            \(plan.displayName) isn’t available yet. Product \(plan.storeProductID ?? "?"). \
            Human Analog team \(ScaleStorefront.developmentTeamID): add it in App Store Connect \
            (or run Debug with \(ScaleStorefront.localStoreKitConfigPath) on the scheme).
            """
            restoreMessage = nil
            return false
        }
        purchaseError = nil
        restoreMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshPlanFromEntitlements()
                return true
            case .userCancelled:
                return false
            case .pending:
                purchaseError = "Purchase is pending approval. You’ll unlock when Apple finishes it."
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
        #endif
    }

    func restore() async {
        purchaseError = nil
        restoreMessage = nil
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshPlanFromEntitlements()
            if plan == .free {
                restoreMessage = "No active Plus or Pro subscription found for this Apple ID."
            } else {
                restoreMessage = "Restored \(plan.displayName)."
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func refreshPlanFromEntitlements() async {
        #if DEBUG
        if let override = debugOverride {
            plan = override
            noteQuotaChange()
            return
        }
        #endif
        var owned: [ScalePlan] = [.free]
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == ScalePlan.pro.storeProductID {
                owned.append(.pro)
            } else if transaction.productID == ScalePlan.plus.storeProductID {
                owned.append(.plus)
            }
        }
        plan = ScalePlan.best(of: owned)
        noteQuotaChange()
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            if case .verified(let transaction) = update {
                await transaction.finish()
                await refreshPlanFromEntitlements()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: LocalizedError {
        case failedVerification
        var errorDescription: String? { "StoreKit purchase couldn’t be verified." }
    }
}
