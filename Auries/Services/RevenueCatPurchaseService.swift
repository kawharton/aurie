import Foundation
import RevenueCat

/// RevenueCat-backed purchases for the three CONSUMABLE hatch packs.
///
/// Quantities come from the PACKAGE identifier, never from the store product
/// id, so replacing the Test Store products with real Apple products later
/// changes nothing in this file or in gameplay.
///
/// No entitlements are involved. RevenueCat verifies and finishes the store
/// transaction; `WalletService` remains the source of truth for how many
/// purchased hatches remain.
struct RevenueCatPurchaseService: PurchaseService {

    static let offeringID = "hatch_packs"

    /// THE mapping gameplay depends on. Package identifier -> hatch credits.
    static let quantities: [String: Int] = [
        "hatches_5": 5,
        "hatches_10": 10,
        "hatches_20": 20,
    ]
    static let bestValuePackage = "hatches_20"

    var isAvailable: Bool { true }
    /// No ad network is integrated. Nothing may offer "watch an ad".
    var supportsRewardedAds: Bool { false }

    // MARK: - Offering

    /// The hatch-pack offering, preferring the explicitly named one and
    /// falling back to whatever RevenueCat marks current.
    private func hatchOffering() async throws -> Offering {
        let offerings = try await Purchases.shared.offerings()
        guard let offering = offerings.offering(identifier: Self.offeringID)
                ?? offerings.current else {
            throw PurchaseError.unavailable
        }
        return offering
    }

    func loadHatchProducts() async throws -> [HatchProduct] {
        let offering: Offering
        do { offering = try await hatchOffering() }
        catch { throw PurchaseError.unavailable }

        // A package we do not recognise is skipped rather than guessed at;
        // a missing package shows an unavailable state, never a crash.
        let products = offering.availablePackages
            .compactMap { pkg -> HatchProduct? in
                guard let amount = Self.quantities[pkg.identifier] else { return nil }
                return HatchProduct(
                    id: pkg.identifier,
                    amount: amount,
                    // Localized price straight from the store product —
                    // never a hardcoded "$2.99".
                    displayPrice: pkg.storeProduct.localizedPriceString,
                    bestValue: pkg.identifier == Self.bestValuePackage)
            }
            .sorted { $0.amount < $1.amount }

        guard !products.isEmpty else { throw PurchaseError.unavailable }
        return products
    }

    // MARK: - Purchase

    func purchaseHatchPack(_ product: HatchProduct) async throws -> HatchGrant {
        let offering = try await hatchOffering()
        guard let pkg = offering.availablePackages
                .first(where: { $0.identifier == product.id }),
              let amount = Self.quantities[pkg.identifier] else {
            throw PurchaseError.unavailable
        }

        let result: PurchaseResultData
        do {
            result = try await Purchases.shared.purchase(package: pkg)
        } catch {
            // RevenueCat surfaces user cancellation as an error on some
            // paths; treat it as the normal, silent outcome.
            if let rcError = error as? RevenueCat.ErrorCode,
               rcError == .purchaseCancelledError {
                throw PurchaseError.cancelled
            }
            let ns = error as NSError
            if ns.domain == RevenueCat.ErrorCode.errorDomain,
               ns.code == RevenueCat.ErrorCode.purchaseCancelledError.rawValue {
                throw PurchaseError.cancelled
            }
            throw PurchaseError.failed(ns.localizedDescription)
        }

        if result.userCancelled { throw PurchaseError.cancelled }

        // The store transaction id is what makes the credit exactly-once.
        // Without one we refuse to credit rather than invent an id.
        guard let txnID = result.transaction?.transactionIdentifier,
              !txnID.isEmpty else {
            throw PurchaseError.failed(
                "That purchase went through but didn’t return a receipt. "
                + "Reopen Aurie and it will be added.")
        }
        return HatchGrant(amount: amount, source: .purchase,
                          transactionId: txnID)
    }

    func grantRewardedAdHatch() async throws -> HatchGrant {
        // There is no ad network. Never fabricate a reward.
        throw PurchaseError.unavailable
    }

    // MARK: - Recovery

    /// Every consumable hatch-pack transaction RevenueCat has recorded for
    /// this app user. The wallet ledger decides which (if any) still need
    /// crediting, so replaying this is always safe.
    ///
    /// This narrows — but cannot fully close — the window where the store
    /// finishes a purchase and the app dies before the local save.
    func unrecordedGrants() async -> [HatchGrant] {
        guard let info = try? await Purchases.shared.customerInfo(),
              let offering = try? await hatchOffering() else { return [] }

        // Store product id -> credits, resolved through the packages so the
        // temporary Test Store product ids are never hardcoded.
        var creditsByProductID: [String: Int] = [:]
        for pkg in offering.availablePackages {
            if let amount = Self.quantities[pkg.identifier] {
                creditsByProductID[pkg.storeProduct.productIdentifier] = amount
            }
        }
        // `nonSubscriptions` (NOT the deprecated `nonSubscriptionTransactions`,
        // which yields StoreTransaction and has no store-side id).
        return info.nonSubscriptions.compactMap { txn -> HatchGrant? in
            guard let amount = creditsByProductID[txn.productIdentifier] else {
                return nil
            }
            // MUST be `storeTransactionIdentifier`, not `transactionIdentifier`.
            // RevenueCat exposes BOTH: `transactionIdentifier` is RevenueCat's
            // own id, `storeTransactionIdentifier` is the store's. The purchase
            // path credits using the STORE id (StoreTransaction), so keying
            // reconciliation on RevenueCat's id never matches the ledger and
            // re-credits every transaction. Caught by the live Test Store run
            // 2026-09-21: 5 purchases became a 90-hatch balance instead of 45.
            return HatchGrant(amount: amount, source: .purchase,
                              transactionId: txn.storeTransactionIdentifier)
        }
    }
}
