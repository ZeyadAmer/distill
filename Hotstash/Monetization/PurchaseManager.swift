import Foundation
import StoreKit

// MARK: - PurchaseManager

/// Manages StoreKit 2 purchase and entitlement state for the Hotstash Pro product.
///
/// StoreKit is the authoritative source of truth.  UserDefaults is used only
/// as a local cache to avoid flickering on cold-launch before the async
/// entitlement check completes.
@MainActor
final class PurchaseManager: ObservableObject {

    // MARK: Singleton

    static let shared = PurchaseManager()

    // MARK: Constants

    let productID = "com.zeyadamer.hotstash.pro"

    private enum Keys {
        static let isPurchasedCache = "com.zeyadamer.hotstash.isPurchasedCache"
    }

    // MARK: Published state

    @Published var isPurchased: Bool = UserDefaults.standard.bool(forKey: "com.zeyadamer.hotstash.isPurchasedCache")
    @Published var isLoading: Bool = false

    // MARK: Init

    private init() {
        Task { await loadPurchaseState() }
    }

    // MARK: - Purchase

    /// Fetches the product from the App Store and initiates a purchase.
    func purchase() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else {
                // Product not found — could be a sandbox/configuration issue.
                return
            }

            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                if case .verified(let transaction) = verificationResult {
                    await transaction.finish()
                    markPurchased()
                }
            case .pending:
                // Deferred purchase (e.g. Ask to Buy) — wait for Transaction.updates.
                break
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            // Purchase errors are surfaced to the user via the UI layer;
            // log here to aid debugging without crashing.
            print("[PurchaseManager] Purchase failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Restore

    /// Syncs with the App Store to restore any prior purchases.
    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await loadPurchaseState()
        } catch {
            print("[PurchaseManager] Restore failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Transaction listener

    /// Long-lived listener for deferred or cross-device transactions.
    /// Call once from `applicationDidFinishLaunching`.
    func listenForTransactions() {
        Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result,
                      transaction.productID == productID else { continue }
                markPurchased()
                await transaction.finish()
            }
        }
    }

    // MARK: - Private helpers

    /// Iterates over current entitlements and updates `isPurchased` accordingly.
    private func loadPurchaseState() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == productID {
                markPurchased()
                return
            }
        }

        // No active entitlement found — only clear the cached flag if it was
        // previously set (avoid a false negative on the very first launch before
        // StoreKit data propagates).
        if isPurchased {
            isPurchased = false
            persistCache(false)
        }
    }

    private func markPurchased() {
        isPurchased = true
        persistCache(true)
        NotificationCenter.default.post(name: .purchaseStateChanged, object: nil)
    }

    private func persistCache(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Keys.isPurchasedCache)
    }
}
