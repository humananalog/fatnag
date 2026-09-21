import Foundation
import StoreKit

/// StoreKit 2 subscription + DEBUG tier override. Effective plan drives weekly Grok limits.
@MainActor
final class ScaleSubscriptionStore: ObservableObject {
    static let shared = ScaleSubscriptionStore()

    @Published private(set) var plan: ScalePlan = .free
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseError: String?
    @Published private(set) var isLoading = false
    /// Bumps when weekly Grok credits change so Settings / Coach refresh status lines.
    @Published private(set) var quotaEpoch: Int = 0

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
    #endif

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { await listenForTransactions() }
        Task { await refresh() }
    }

    var quotaSnapshot: CoachWeeklyQuota.Snapshot {
        CoachWeeklyQuota.snapshot(plan: plan)
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
        let ids = Set(ScalePlan.allCases.compactMap(\.storeProductID))
        guard !ids.isEmpty else { return }
        do {
            products = try await Product.products(for: ids)
                .sorted { $0.price < $1.price }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func product(for plan: ScalePlan) -> Product? {
        guard let id = plan.storeProductID else { return nil }
        return products.first { $0.id == id }
    }

    @discardableResult
    func purchase(_ plan: ScalePlan) async -> Bool {
        guard let product = product(for: plan) else {
            purchaseError = "\(plan.displayName) isn’t available in StoreKit yet. Add product \(plan.storeProductID ?? "") in App Store Connect (or use the StoreKit config in DEBUG)."
            return false
        }
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshPlanFromEntitlements()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshPlanFromEntitlements()
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
