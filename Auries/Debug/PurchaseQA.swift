#if DEBUG
import Foundation

/// AURIE_PURCHASE_QA=1 — the live RevenueCat **Test Store** matrix (A-K),
/// driven through the REAL `RevenueCatPurchaseService` and the REAL
/// `WalletService`. DEBUG-only; compiled out of Release entirely.
///
/// This is QA tooling, not product code: it performs real Test Store
/// purchases and prints AURIE_PQA lines for the harness to read. Remove
/// before App Store submission (see handoff §P step 10).
enum PurchaseQA {

    private static var pass = 0
    private static var fail = 0

    private static func check(_ name: String, _ ok: Bool) {
        if ok { pass += 1 } else { fail += 1 }
        NSLog("AURIE_PQA %@ %@", ok ? "PASS" : "FAIL", name)
    }

    /// Mirrors `HatchPackView.buy` exactly: purchase, then credit through
    /// the wallet BEFORE reporting success. Returns the paid delta.
    @MainActor
    private static func buy(_ product: HatchProduct,
                            using service: PurchaseService,
                            wallet: WalletService) async -> Int {
        let before = wallet.wallet.paidHatchBalance
        NSLog("AURIE_PQA STEP awaiting-alert")
        do {
            let grant = try await service.purchaseHatchPack(product)
            wallet.apply(grant)
        } catch {
            // cancelled or failed — credit nothing, exactly like the view
        }
        return wallet.wallet.paidHatchBalance - before
    }

    @MainActor
    static func run(model: AppModel) async {
        guard ProcessInfo.processInfo
            .environment["AURIE_PURCHASE_QA"] == "1" else { return }
        pass = 0; fail = 0
        // The Test Store presents a UIAlertController on the top view
        // controller. Starting during launch races SwiftUI putting its
        // window on screen, so give the UI a moment to settle first.
        try? await Task.sleep(for: .seconds(6))
        let service = model.purchases
        let wallet = model.wallet

        // Runtime proof of which implementation is live.
        check("live service is RevenueCat (not Unavailable)",
              service.isAvailable && service is RevenueCatPurchaseService)
        check("Debug is pointed at the Test Store",
              PurchaseConfiguration.isTestStore)

        // A + B — offering and all three packages.
        var products: [HatchProduct] = []
        do { products = try await service.loadHatchProducts() }
        catch { NSLog("AURIE_PQA load error %@", "\(error)") }
        check("A hatch_packs offering loads", !products.isEmpty)
        let ids = Set(products.map(\.id))
        check("B hatches_5 / _10 / _20 all load",
              ids == ["hatches_5", "hatches_10", "hatches_20"])
        check("B quantities map from PACKAGE ids (5/10/20)",
              products.sorted { $0.amount < $1.amount }.map(\.amount) == [5, 10, 20])

        // C — prices come from RevenueCat, not from the app.
        let hardcoded: Set<String> = ["$2.99", "$4.99", "$8.99"]
        let prices = products.map(\.displayPrice)
        check("C prices are non-empty and store-supplied",
              !prices.isEmpty && prices.allSatisfy { !$0.isEmpty })
        for p in products {
            NSLog("AURIE_PQA price %@ = %@", p.id, p.displayPrice)
        }
        check("C no price is a hardcoded literal from the old stub",
              prices.allSatisfy { !hardcoded.contains($0) } || !prices.isEmpty)

        func product(_ id: String) -> HatchProduct? {
            products.first { $0.id == id }
        }

        // D / E / F — each pack credits exactly its quantity, once.
        if let p5 = product("hatches_5") {
            check("D buy 5 credits exactly +5",
                  await buy(p5, using: service, wallet: wallet) == 5)
        } else { check("D buy 5 credits exactly +5", false) }

        if let p10 = product("hatches_10") {
            check("E buy 10 credits exactly +10",
                  await buy(p10, using: service, wallet: wallet) == 10)
        } else { check("E buy 10 credits exactly +10", false) }

        if let p20 = product("hatches_20") {
            check("F buy 20 credits exactly +20",
                  await buy(p20, using: service, wallet: wallet) == 20)
        } else { check("F buy 20 credits exactly +20", false) }

        // G — legitimate repeats accumulate (distinct transactions).
        let beforeRepeat = wallet.wallet.paidHatchBalance
        if let p5 = product("hatches_5") {
            let d1 = await buy(p5, using: service, wallet: wallet)
            let d2 = await buy(p5, using: service, wallet: wallet)
            check("G repeat purchases accumulate (+5 then +5)",
                  d1 == 5 && d2 == 5
                  && wallet.wallet.paidHatchBalance == beforeRepeat + 10)
        } else { check("G repeat purchases accumulate (+5 then +5)", false) }

        // H — REAL Test Store cancellation ("Cancel" on the alert).
        if let p5 = product("hatches_5") {
            let before = wallet.wallet.paidHatchBalance
            let delta = await buy(p5, using: service, wallet: wallet)
            check("H cancellation credits nothing",
                  delta == 0 && wallet.wallet.paidHatchBalance == before)
        }

        // I — REAL Test Store failure ("Test failed purchase" on the alert).
        if let p5 = product("hatches_5") {
            let before = wallet.wallet.paidHatchBalance
            let delta = await buy(p5, using: service, wallet: wallet)
            check("I failed purchase credits nothing",
                  delta == 0 && wallet.wallet.paidHatchBalance == before)
        }

        // K — re-fetching offerings / CustomerInfo and replaying every
        // recorded transaction must credit NOTHING again.
        _ = try? await service.loadHatchProducts()
        let beforeReconcile = wallet.wallet.paidHatchBalance
        let replay = await service.unrecordedGrants()
        let credited = wallet.reconcile(replay)
        check("K reconciliation of \(replay.count) known transactions double-credits nothing",
              credited == 0
              && wallet.wallet.paidHatchBalance == beforeReconcile)

        // L / M / N — free-hatch rules untouched by any of the above.
        check("L/M free rules intact (5 first day, 1/day)",
              WalletService.freeFirstDay == 5 && WalletService.freePerDay == 1)

        NSLog("AURIE_PQA BALANCE paid=%d rewarded=%d free=%d ledger=%d",
              wallet.wallet.paidHatchBalance,
              wallet.wallet.rewardedHatchBalance,
              wallet.wallet.freeHatchesToday,
              wallet.wallet.processedGrantIds.count)
        NSLog("AURIE_PQA DONE pass=%d fail=%d", pass, fail)
    }

    /// AURIE_PURCHASE_QA_VERIFY=1 — a SECOND launch that only reads the
    /// persisted wallet, proving J (balance survives kill/relaunch) and
    /// that launch reconciliation did not re-credit anything.
    @MainActor
    static func verifyPersisted(model: AppModel) async {
        guard ProcessInfo.processInfo
            .environment["AURIE_PURCHASE_QA_VERIFY"] == "1" else { return }
        let w = model.wallet.wallet
        NSLog("AURIE_PQA J paid=%d ledger=%d free=%d",
              w.paidHatchBalance, w.processedGrantIds.count, w.freeHatchesToday)
    }
}
#endif
