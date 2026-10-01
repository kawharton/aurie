import Foundation

/// The user's charm unlocks — ACCOUNT-level, like the hatch wallet, and
/// for the same reason: deleting an Aurie must never delete something
/// the user owns. Charms are reusable cosmetics, not consumables: an id
/// is either unlocked or not, there are no quantities, and equipping a
/// charm on one Aurie never prevents equipping it on another.
struct CharmCollection: Codable {
    /// Every charm id the user has ever unlocked. Grows only.
    var unlockedCharmIDs: Set<String>
    /// Idempotency ledger for future grant flows (Birth Charms, play
    /// rewards): a grant id recorded here is never granted twice, the
    /// same contract HatchWallet.processedGrantIds already ships.
    var processedGrantIds: Set<String>

    init() {
        unlockedCharmIDs = []
        processedGrantIds = []
    }

    /// Lenient by construction, like HatchWallet: unknown future keys
    /// are ignored and missing keys default, so no schema change can
    /// invalidate an older charms.json.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unlockedCharmIDs = try c.decodeIfPresent(
            Set<String>.self, forKey: .unlockedCharmIDs) ?? []
        processedGrantIds = try c.decodeIfPresent(
            Set<String>.self, forKey: .processedGrantIds) ?? []
    }
}

/// Owner of charms.json (beside wallet.json / auries.json). The API is
/// deliberately tiny — unlock and ask — until acquisition flows ship.
final class CharmService {
    private(set) var collection: CharmCollection
    private let saveURL: URL?

    init(directory: URL?) {
        saveURL = directory?.appendingPathComponent("charms.json")
        if let saveURL, let data = try? Data(contentsOf: saveURL),
           let loaded = try? JSONDecoder().decode(CharmCollection.self,
                                                  from: data) {
            collection = loaded
        } else {
            collection = CharmCollection()
        }
    }

    #if DEBUG
    /// Wipe ownership AND the grant ledger. Greeting presets use this to
    /// reach the "no charm has ever been found" state on a seeded store,
    /// whose launch-time task scan otherwise awards Hearts immediately.
    func debugResetAll() {
        collection.unlockedCharmIDs = []
        collection.processedGrantIds = []
        save()
    }
    #endif

    func isUnlocked(_ id: String) -> Bool {
        collection.unlockedCharmIDs.contains(id)
    }

    /// Idempotent. Returns true only when the charm was NEWLY unlocked,
    /// so callers can celebrate first-time unlocks without tracking
    /// their own state.
    @discardableResult
    func unlock(_ id: String) -> Bool {
        let (inserted, _) = collection.unlockedCharmIDs.insert(id)
        if inserted { save() }
        return inserted
    }

    /// A ledgered GRANT EVENT (Birth Charms, future task rewards):
    /// unlocks `charmID` and records `grantID` so the same event can
    /// never reward twice. Returns false when this exact grant was
    /// already processed (a replayed commit) — callers must then skip
    /// EVERY side effect of the reward, not just the unlock. Distinct
    /// from `unlock`'s return: granting an ALREADY-OWNED charm through
    /// a NEW event still returns true (the event is real; ownership
    /// simply has nothing left to add).
    @discardableResult
    func processGrant(_ grantID: String, unlocking charmID: String) -> Bool {
        guard !collection.processedGrantIds.contains(grantID) else {
            return false
        }
        collection.processedGrantIds.insert(grantID)
        collection.unlockedCharmIDs.insert(charmID)
        save()
        return true
    }

    private func save() {
        guard let saveURL else { return }
        try? JSONEncoder().encode(collection)
            .write(to: saveURL, options: .atomic)
    }
}
