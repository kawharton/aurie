import Foundation

// The brief's purchase seam (§10), verbatim: the UI only ever talks to this
// protocol, so swapping implementations touches no screens.

protocol PurchaseService {
    /// False when no usable API key is configured for this build
    /// configuration. The UI shows a quiet unavailable state rather than
    /// letting a player start a purchase that cannot complete.
    var isAvailable: Bool { get }
    /// False unless a real rewarded-ad network is wired. Nothing may offer
    /// "watch an ad" while this is false.
    var supportsRewardedAds: Bool { get }
    func loadHatchProducts() async throws -> [HatchProduct]
    func purchaseHatchPack(_ product: HatchProduct) async throws -> HatchGrant
    func grantRewardedAdHatch() async throws -> HatchGrant
    /// Store transactions that completed but may never have reached the
    /// local wallet — e.g. the app was killed between the store finishing
    /// the purchase and our atomic save. Credited through the same
    /// transaction-id ledger, so replaying them can never double-credit.
    func unrecordedGrants() async -> [HatchGrant]
}

extension PurchaseService {
    var supportsRewardedAds: Bool { false }
    func unrecordedGrants() async -> [HatchGrant] { [] }
}

/// What the purchase UI needs to distinguish. Cancellation is NORMAL and must
/// never be reported as an error.
enum PurchaseError: LocalizedError {
    case cancelled
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:    return nil
        case .unavailable:  return "Hatch packs aren’t available right now."
        case .failed(let m): return m
        }
    }
}

/// `id` is the RevenueCat PACKAGE identifier (`hatches_5`…), never the store
/// product id — the store products change when the real Apple products
/// replace the Test Store ones, the package identities do not.
struct HatchProduct: Identifiable, Equatable {
    let id: String
    let amount: Int
    let displayPrice: String
    let bestValue: Bool
}

struct HatchGrant: Codable, Equatable {
    let amount: Int
    let source: HatchGrantSource
    /// The STORE transaction id. Required for a purchase: the wallet refuses
    /// to credit a grant that has no stable id, because that is the only
    /// thing making the credit exactly-once.
    let transactionId: String?
}

enum HatchGrantSource: String, Codable { case purchase, rewardedAd, debug }

/// Used whenever no usable API key is configured — notably any Release build
/// before the production Apple key exists. Fails cleanly and buys nothing.
struct UnavailablePurchaseService: PurchaseService {
    var isAvailable: Bool { false }
    func loadHatchProducts() async throws -> [HatchProduct] {
        throw PurchaseError.unavailable
    }
    func purchaseHatchPack(_ product: HatchProduct) async throws -> HatchGrant {
        throw PurchaseError.unavailable
    }
    func grantRewardedAdHatch() async throws -> HatchGrant {
        throw PurchaseError.unavailable
    }
}
