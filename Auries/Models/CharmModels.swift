import Foundation

// MARK: - The reusable charm system (2026-09-14, schema B1 2026-09-17)
//
// Distinct concepts, distinct owners — never collapsed:
//   CharmDefinition  — what a charm IS (catalog; no per-user state).
//                      Carries THREE independent multi-valued facets:
//                        placements          WHERE it can be worn
//                        categories          WHAT it represents
//                        acquisitionSources  HOW it can be earned
//   CharmCollection  — what the USER has unlocked (account-level file
//                      beside wallet.json; deleting an Aurie can never
//                      delete an unlock). See CharmCollection.swift.
//   EquippedCharm    — what one AURIE is wearing (persisted on the
//                      Aurie; a reference to an unlock, never a copy —
//                      charms are reusable cosmetics, not consumables,
//                      so there are no quantities anywhere).
//   BirthCharmTrigger — recognition→charm mapping for Birth Charms.
//                      A SEPARATE table: triggers name ONE charm each;
//                      categories never unlock anything.
//
// Future systems (environmental collectibles, food/eating, task
// rewards) are OBSERVERS that award charms through the single
// CharmService.unlock(...) path. A world object or food item is its
// own model that REFERENCES a rewardCharmID — it is never a charm, and
// none of its spawn/interaction/progress logic belongs on
// CharmDefinition.
//
// The catalog is GENERATED data (CharmCatalog.generated.swift) merged
// from the hand-authored taxonomy (charm_taxonomy.json — editorial
// truth the processor never overwrites) and the processing manifest
// (charms.json). Edit the taxonomy, re-run
// Design/Aurie3D/Scripts/generate_charm_catalog.py; never grow Swift
// tables by hand.
//
// Placement/rendering authority is the Blender pipeline: charms render
// as per-body, per-orientation layers (export_charm_layers.py) whose
// occlusion is carved into the pixels — the app never hand-places a
// charm. Belly stickers ride the belly-patch system (aurie_belly*.py).

/// Placement slots WITH an art pipeline behind them today. This enum
/// is a rendering convenience; the FULL placement vocabulary is data
/// (taxonomy `placements` → GeneratedCharmCatalog.placementDisplayNames)
/// and future placements (shoulder, neck, wrist, floating, aura, tail,
/// …) need no migration because `CharmDefinition.placements` and
/// `EquippedCharm.slot` both carry raw STRINGS, not this enum.
///
/// `belly` is the PRODUCT placement for the front torso (the
/// belly-patch sticker system). The library's `BODY_FRONT` attachment
/// type remains an import-side spelling that maps to `belly`.
public enum CharmSlot: String, Codable {
    case head, back, bodySide, bodyFront, hanging, belly
    /// New placement types (2026-09-19): `aura` = a small cluster of
    /// the charm's art living in the aura space around the creature;
    /// `floating` = ONE object hovering near the upper shoulder. Both
    /// obey the same one-charm-per-placement rule and coexist with
    /// belly/back. String-backed like everything here, so records
    /// written by any build round-trip unchanged.
    case aura, floating
}

/// One charm worn by one Aurie. Codable and deliberately lenient:
/// records written by a FUTURE build (new slots, new fields) must
/// still decode here without dropping the whole collection.
///
/// Deliberately an extensible RECORD, not a [String: String] — future
/// placements may need structured refinements beyond `side`.
public struct EquippedCharm: Codable, Equatable {
    /// Stable library id (`charm_object_backpack_01`). Never repurpose
    /// one — a saved Aurie is only its id plus these strings.
    public var charmID: String
    /// Placement raw value ("back", "belly", …). A String on disk so
    /// future placements survive a round-trip through an older build.
    public var slot: String
    /// Optional placement refinement ("left"/"right") for slots that
    /// need a side. Nil = the slot's default.
    public var side: String?

    public init(charmID: String, slot: String, side: String? = nil) {
        self.charmID = charmID
        self.slot = slot
        self.side = side
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        charmID = try c.decode(String.self, forKey: .charmID)
        // A missing slot resolves from the catalog rather than failing
        // the whole collection decode.
        slot = try c.decodeIfPresent(String.self, forKey: .slot)
            ?? AurieCharmCatalog.definition(charmID)?.primaryPlacement
            ?? CharmSlot.back.rawValue
        side = try c.decodeIfPresent(String.self, forKey: .side)
    }
}

/// What a charm IS — pure in-memory catalog metadata, never persisted,
/// so this type can evolve freely without save migrations.
///
/// The three facet arrays are INDEPENDENT: a charm may support several
/// placements, carry several category tags, and be reachable through
/// several acquisition paths. Empty `acquisitionSources` means the
/// product hasn't assigned any yet (nothing renders or grants from
/// this field alone).
public struct CharmDefinition {
    public let id: String
    public let displayName: String
    /// Theme tags — taxonomy category ids ("food", "fruit_vegetables").
    public let categories: [String]
    /// Wearable placements — taxonomy placement ids ("belly", "back").
    public let placements: [String]
    /// How this charm can be earned — taxonomy source ids
    /// ("birthPhoto", "taskReward", "environmentDiscovery", …). Every
    /// path ultimately grants through CharmService.unlock(...).
    public let acquisitionSources: [String]
    /// Back-references into GeneratedCharmCatalog.birthTriggers. The
    /// trigger table owns the recognition mapping, not the charm.
    public let birthTriggerIDs: [String]
    public let launch: Bool

    /// The placement an equip defaults to (and that slotless legacy
    /// records resolve to).
    public var primaryPlacement: String {
        placements.first ?? CharmSlot.back.rawValue
    }
}

/// Birth-Charm recognition mapping — SCHEMA ONLY in phase B1 (no hatch
/// granting yet). Labels are the app's CANONICAL recognition results
/// (Recognition.swift mappings), never raw Vision output. One trigger
/// unlocks exactly ONE charm; a broad label must never fan out to a
/// category of charms.
public struct BirthCharmTrigger {
    public let id: String
    public let acceptedRecognitionLabels: [String]
    public let unlockCharmID: String
}

/// Display-name lookups for the data-driven taxonomy. IDs are stable
/// strings; names are presentation. Unknown ids fall back to a
/// humanised id so future/removed taxonomy entries stay harmless.
public enum CharmTaxonomy {
    public static func categoryName(_ id: String) -> String {
        GeneratedCharmCatalog.categoryDisplayNames[id] ?? humanise(id)
    }

    public static func placementName(_ id: String) -> String {
        GeneratedCharmCatalog.placementDisplayNames[id] ?? humanise(id)
    }

    public static func acquisitionSourceName(_ id: String) -> String {
        GeneratedCharmCatalog.acquisitionSourceDisplayNames[id] ?? humanise(id)
    }

    private static func humanise(_ id: String) -> String {
        id.split(whereSeparator: { $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

/// The in-app charm catalog — a thin lookup over the GENERATED data
/// (CharmCatalog.generated.swift). Do not add entries here.
///
/// NO HEAD CHARM is listed: `charm_nature_flower_02` was removed
/// 2026-09-15 (wrong flower for hair) and the head slot awaits a
/// charm choice from the product owner. `CharmSlot.head` stays
/// defined — the slot is fine, only the asset pick is pending.
public enum AurieCharmCatalog {
    public static let all: [CharmDefinition] = GeneratedCharmCatalog.definitions

    private static let byID = Dictionary(uniqueKeysWithValues:
        all.map { ($0.id, $0) })

    public static func definition(_ id: String) -> CharmDefinition? {
        byID[id]
    }

    public static let birthTriggers: [BirthCharmTrigger] =
        GeneratedCharmCatalog.birthTriggers

    /// The Birth-Charm trigger a CANONICAL recognition label earns, or
    /// nil for the ordinary no-charm hatch. `label` must be the app's
    /// canonicalized hero label (RecognizedObject.label, e.g. "apple"),
    /// NEVER raw Vision text — Recognition.swift owns that mapping.
    /// The caller also owns the acceptance gate (confidence/category):
    /// AppModel mirrors the generator's rule so provenance can never
    /// disagree with the displayed "born from" identity.
    ///
    /// First matching trigger wins; `triggers` is injectable for tests.
    public static func birthTrigger(
        forCanonicalLabel label: String?,
        triggers: [BirthCharmTrigger] = birthTriggers
    ) -> BirthCharmTrigger? {
        guard let label else { return nil }
        return triggers.first { $0.acceptedRecognitionLabels.contains(label) }
    }

    /// The ONE equip-record rule (one charm per placement): replace any
    /// record in `placement`, keep every other placement. Every writer —
    /// the Charms page, the Birth-Charm grant, the hatch preview — goes
    /// through this, so the product rule can never fork.
    public static func equipping(_ records: [EquippedCharm],
                                 with charmID: String,
                                 at placement: String) -> [EquippedCharm] {
        records.filter { $0.slot != placement }
            + [EquippedCharm(charmID: charmID, slot: placement)]
    }

    /// RENDER-path resolution: the equipped charm to draw at `placement`.
    ///
    /// Requires an equipped record selecting that placement and a catalog
    /// definition that supports it. Deliberately does NOT check `launch`:
    /// launch is EDITORIAL metadata (membership in the initial content
    /// set), never a render permission — a seasonal, event, achievement
    /// or discovery charm ships with launch=false and must still render
    /// once unlocked and equipped. The four concepts stay separate:
    /// launch = catalog availability, unlocked = ownership, equipped =
    /// what this Aurie wears, placement+art = whether it can render.
    /// Asset existence is the caller's final graceful check (a missing
    /// processed image draws nothing, never crashes).
    ///
    /// `definitions` is injectable for tests; production uses the catalog.
    public static func equippedCharmID(
        in equipped: [EquippedCharm], placement: String,
        definitions: (String) -> CharmDefinition? = AurieCharmCatalog.definition
    ) -> String? {
        equipped.first { worn in
            guard worn.slot == placement,
                  let def = definitions(worn.charmID) else { return false }
            return def.placements.contains(placement)
        }?.charmID
    }
}
