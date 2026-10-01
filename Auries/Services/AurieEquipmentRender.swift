import Foundation

/// The ONE place that turns an Aurie's persisted equipment records into the
/// render arguments `AurieNode` takes.
///
/// Extracted from `CreatureScene` (2026-09-21) because the still-portrait
/// path did not pass ANY charm arguments, so the Auries grid, the widget and
/// the Settings thumbnail all drew bare creatures while Home drew dressed
/// ones. Both paths now call these, so there is exactly one source of truth
/// and no second charm renderer to drift.
///
/// Pure functions over `resolvedEquippedCharms` — no inventory of their own,
/// no persistence, no `launch` gating (that flag is editorial catalog
/// metadata, never a render permission).
enum AurieEquipmentRender {

    /// Layer keys for body-layer charms (today: the backpack on `back`).
    /// Layer key == charm id by the export convention. Whether a layer
    /// actually draws is decided by per-body art existing for the current
    /// orientation, inside `AurieNode`.
    static func charmLayerKeys(for a: Aurie) -> [String] {
        var equipped = a.resolvedEquippedCharms
        #if DEBUG
        // Capture aid: AURIE_CHARM_PROOF=1 dresses the creature in the proof
        // backpack IN MEMORY only — nothing persists.
        if ProcessInfo.processInfo.environment["AURIE_CHARM_PROOF"] == "1",
           equipped.isEmpty {
            equipped = [EquippedCharm(charmID: "charm_object_backpack_01",
                                      slot: CharmSlot.back.rawValue)]
        }
        #endif
        return equipped.compactMap { worn in
            guard AurieCharmCatalog.definition(worn.charmID) != nil
            else { return nil }
            return worn.charmID
        }
    }

    /// The equipped BELLY charm, drawn as a sticker.
    static func bellyStickerID(for a: Aurie) -> String? {
        var equipped = a.resolvedEquippedCharms
        #if DEBUG
        // Capture aid: AURIE_BELLY_PROOF=<charm_id>, in memory only.
        if let id = ProcessInfo.processInfo
            .environment["AURIE_BELLY_PROOF"], equipped.isEmpty {
            equipped = [EquippedCharm(charmID: id,
                                      slot: CharmSlot.belly.rawValue)]
        }
        #endif
        return AurieCharmCatalog.equippedCharmID(
            in: equipped, placement: CharmSlot.belly.rawValue)
    }

    /// The equipped AURA charm. On a still portrait the cluster is captured
    /// in its deterministic rest layout — the approved static representation
    /// — rather than being dropped.
    static func auraCharmID(for a: Aurie) -> String? {
        var equipped = a.resolvedEquippedCharms
        #if DEBUG
        if let id = ProcessInfo.processInfo
            .environment["AURIE_AURA_PROOF"], equipped.isEmpty ||
            !equipped.contains(where: { $0.slot == CharmSlot.aura.rawValue }) {
            equipped.append(EquippedCharm(charmID: id,
                                          slot: CharmSlot.aura.rawValue))
        }
        #endif
        return AurieCharmCatalog.equippedCharmID(
            in: equipped, placement: CharmSlot.aura.rawValue)
    }

    /// FLOATING is paused for launch (`AurieNode.floatingPlacementActive`
    /// gates the drawing); the record still resolves so nothing is lost.
    static func floatingCharmID(for a: Aurie) -> String? {
        var equipped = a.resolvedEquippedCharms
        #if DEBUG
        if let id = ProcessInfo.processInfo
            .environment["AURIE_FLOAT_PROOF"], equipped.isEmpty ||
            !equipped.contains(where: {
                $0.slot == CharmSlot.floating.rawValue }) {
            equipped.append(EquippedCharm(charmID: id,
                                          slot: CharmSlot.floating.rawValue))
        }
        #endif
        return AurieCharmCatalog.equippedCharmID(
            in: equipped, placement: CharmSlot.floating.rawValue)
    }

    /// A stable signature of everything that changes how an Aurie LOOKS
    /// when its equipment changes. Used to key the portrait cache so a
    /// newly equipped charm actually refreshes the tile — the cache was
    /// keyed on the Aurie id alone, which made the grid stale forever.
    static func equipmentSignature(for a: Aurie) -> String {
        a.resolvedEquippedCharms
            .map { "\($0.slot):\($0.charmID)" }
            .sorted()
            .joined(separator: "|")
    }
}
