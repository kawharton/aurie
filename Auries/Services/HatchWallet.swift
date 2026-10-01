import Foundation
import Observation

/// The hatch balance (§11) — consumable-only, no dark patterns. The struct is
/// the brief's spec verbatim; `WalletService` owns the rules:
///   - Free hatches: 3 on the first-launch day, then 1/day, refreshed at
///     local midnight (tunable via `freeFirstDay` / `freePerDay`).
///   - Spend order: free → rewarded → paid.
///   - A hatch is consumed ONLY after the creature is generated and saved —
///     never deduct on failure or cancel.
///   - Grants are idempotent (transaction ids recorded; retries never
///     double-grant). Paid balance is local-only ("used on this device").
struct HatchWallet: Codable {
    var firstLaunchDate: Date
    var lastDailyRefreshDate: Date
    var freeHatchesToday: Int
    var paidHatchBalance: Int
    var rewardedHatchBalance: Int
    var processedGrantIds: Set<String>

    init(now: Date = Date(), freeFirstDay: Int) {
        firstLaunchDate = now
        lastDailyRefreshDate = now
        freeHatchesToday = freeFirstDay
        paidHatchBalance = 0
        rewardedHatchBalance = 0
        processedGrantIds = []
    }

    /// Lenient decoding (same rationale as Store.Settings): new fields must
    /// never invalidate an older wallet.json.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstLaunchDate = try c.decodeIfPresent(Date.self, forKey: .firstLaunchDate) ?? Date()
        lastDailyRefreshDate = try c.decodeIfPresent(Date.self, forKey: .lastDailyRefreshDate) ?? Date()
        freeHatchesToday = try c.decodeIfPresent(Int.self, forKey: .freeHatchesToday) ?? 0
        paidHatchBalance = try c.decodeIfPresent(Int.self, forKey: .paidHatchBalance) ?? 0
        rewardedHatchBalance = try c.decodeIfPresent(Int.self, forKey: .rewardedHatchBalance) ?? 0
        processedGrantIds = try c.decodeIfPresent(Set<String>.self, forKey: .processedGrantIds) ?? []
    }
}

@Observable
final class WalletService {

    /// Tunable free-hatch limits (§11): one obvious place to change for a
    /// fast paywall demo (set both to 1).
    static let freeFirstDay = 5     // 3 -> 5 on 2026-09-20 (product)
    static let freePerDay = 1

    private(set) var wallet: HatchWallet
    private let calendar: Calendar
    private let saveURL: URL?

    /// `directory: nil` gives an in-memory wallet (used by tests/harness).
    init(directory: URL?, calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        saveURL = directory?.appendingPathComponent("wallet.json")
        if let saveURL, let data = try? Data(contentsOf: saveURL),
           let loaded = try? JSONDecoder().decode(HatchWallet.self, from: data) {
            wallet = loaded
        } else {
            wallet = HatchWallet(now: now, freeFirstDay: Self.freeFirstDay)
        }
        refreshDaily(now: now)
    }

    var hatchesAvailable: Int {
        wallet.freeHatchesToday + wallet.rewardedHatchBalance + wallet.paidHatchBalance
    }

    /// Roll the free allowance forward if a new local day started.
    func refreshDaily(now: Date = Date()) {
        guard !calendar.isDate(now, inSameDayAs: wallet.lastDailyRefreshDate) else { return }
        wallet.lastDailyRefreshDate = now
        wallet.freeHatchesToday = calendar.isDate(now, inSameDayAs: wallet.firstLaunchDate)
            ? Self.freeFirstDay : Self.freePerDay
        save()
    }

    /// Spend one hatch: free → rewarded → paid. Call ONLY after the Aurie is
    /// generated and saved (§11 — never deduct on failure).
    func consumeHatch(now: Date = Date()) {
        refreshDaily(now: now)
        if wallet.freeHatchesToday > 0 {
            wallet.freeHatchesToday -= 1
        } else if wallet.rewardedHatchBalance > 0 {
            wallet.rewardedHatchBalance -= 1
        } else if wallet.paidHatchBalance > 0 {
            wallet.paidHatchBalance -= 1
        }
        save()
    }

    /// Apply a purchase/rewarded grant EXACTLY ONCE, and persist the ledger
    /// entry and the credit together in a single atomic write.
    ///
    /// Returns true only when this call actually credited the wallet, so a
    /// caller can tell "credited" from "already had it" without inspecting
    /// balances.
    ///
    /// A grant with no stable transaction id is REFUSED. It used to fall
    /// back to `UUID()`, which silently made every such grant unique and
    /// therefore always creditable — the exact double-credit hole this
    /// ledger exists to prevent. The store transaction id is the only thing
    /// that makes the credit idempotent across UI callbacks, relaunches,
    /// CustomerInfo refreshes and history re-fetches.
    @discardableResult
    func apply(_ grant: HatchGrant) -> Bool {
        guard let id = grant.transactionId,
              !id.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        guard !wallet.processedGrantIds.contains(id) else { return false }
        wallet.processedGrantIds.insert(id)
        switch grant.source {
        case .purchase, .debug: wallet.paidHatchBalance += grant.amount
        case .rewardedAd: wallet.rewardedHatchBalance += grant.amount
        }
        // Ledger + balance live in ONE struct written atomically, so there is
        // no window where the id is recorded but the credit is not.
        save()
        return true
    }

    /// Credit any store transaction that never reached this wallet (e.g. the
    /// app died right after the purchase completed). Safe to call on every
    /// launch: the ledger makes replays no-ops.
    @discardableResult
    func reconcile(_ grants: [HatchGrant]) -> Int {
        grants.reduce(into: 0) { credited, grant in
            if apply(grant) { credited += grant.amount }
        }
    }

    #if DEBUG
    /// Demo tools (§20): back to a fresh first-day wallet.
    func debugReset(now: Date = Date()) {
        wallet = HatchWallet(now: now, freeFirstDay: Self.freeFirstDay)
        save()
    }
    #endif

    private func save() {
        guard let saveURL else { return }
        try? JSONEncoder().encode(wallet).write(to: saveURL, options: .atomic)
    }
}
