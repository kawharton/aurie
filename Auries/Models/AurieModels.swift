import Foundation

// MARK: - Enums

/// The seven aura families. Chosen from the object's dominant colour
/// (Starlight is a rare override). String-backed so it's Codable and matches JSON.
public enum AuraFamily: String, Codable, CaseIterable {
    case ember, glow, moss, tide, dusk, stone, starlight
}

/// Rough body silhouette, chosen from the object's shape (Layer 1).
public enum BodyType: String, Codable, CaseIterable {
    // APPEND ONLY. These raw values are persisted with every saved Aurie and
    // `AssetLoader.bodyName` derives an index from allCases order, so
    // reordering or removing a case would silently repaint existing
    // creatures. `wide` and `lumpy` are deferred from the Sept 1 pool but
    // MUST stay: older saves may reference them.
    case round, tall, wide, small, lumpy
    // Added 2026-08-18 for the approved launch body pool.
    case egg, pear, dumpling, teardrop, beanbag, oval, heart

    /// The ten shapes the launch build generates. Deferred bodies (wide,
    /// lumpy, plus the Blender-only bean/puff/star/squircle) are excluded
    /// here rather than deleted, so re-enabling one is a one-line change.
    public static let launchPool: [BodyType] = [
        .round, .tall, .small, .egg, .pear,
        .dumpling, .teardrop, .beanbag, .oval, .heart,
    ]
}

/// Broad object families the recogniser buckets Vision labels into.
/// Drives the Layer 2 "object flavour". `.unknown` means Layer 1 only.
public enum ObjectCategory: String, Codable, CaseIterable {
    case food, plant, toy, tech, fabric, tool, paper, container, metal, unknown
}

/// The body pattern chosen ONCE at hatch and persisted with the Aurie. Rendered
/// as a family-independent greyscale MASK on the real Blender body: the runtime
/// tints the neutral body by `mix(familyTint, patternTint, mask)`, so the
/// pattern inherits every highlight and curve instead of covering them (see
/// `build_pattern_masks.py`). Masks are bodies × patterns, not × families.
public enum PatternType: String, Codable, CaseIterable {
    // APPEND ONLY. These raw values are persisted with every saved Aurie;
    // reordering or renaming a case would silently repattern existing
    // creatures. The launch set is the five approved patterns plus `none`.
    case none, stripes, speckles, spots, stars, hearts

    /// Seeded patterns are baked as three VARIANTS; the app picks one from the
    /// Aurie's seed so a creature's layout is stable forever without a mask per
    /// creature. Stripes is a single deterministic band field.
    var variantCount: Int {
        switch self {
        case .none, .stripes: return 1
        default:              return 3
        }
    }

    /// The Blender mask layer id for this pattern given an Aurie's seed, or nil
    /// for `.none`. e.g. `pattern_stripes`, `pattern_spots_v2`. The variant is
    /// derived from the seed (high bits, to avoid correlating with the other
    /// seed-derived trait picks), so it never changes once the seed is fixed.
    func maskLayer(seed: UInt64) -> String? {
        guard self != .none else { return nil }
        guard variantCount > 1 else { return "pattern_\(rawValue)" }
        let v = Int((seed >> 41) % UInt64(variantCount))
        return "pattern_\(rawValue)_v\(v)"
    }

    /// The launch-weighted roll. Simple weights, no rarity tiers; ~a third of
    /// creatures stay plain so a pattern reads as a treat rather than default.
    static func roll(_ rng: inout SeededGenerator) -> PatternType {
        let weights: [(PatternType, Int)] = [
            (.none, 30), (.stripes, 16), (.speckles, 16),
            (.spots, 16), (.stars, 11), (.hearts, 11),
        ]
        let total = weights.reduce(0) { $0 + $1.1 }
        var r = Int.random(in: 0 ..< total, using: &rng)
        for (pattern, w) in weights {
            if r < w { return pattern }
            r -= w
        }
        return .none
    }
}

// MARK: - Value types

/// Plain 0-255 RGB colour. Convert to/from SwiftUI Color / UIColor at the edge.
public struct Rgb: Codable, Equatable {
    public var r: Int, g: Int, b: Int
    public init(_ r: Int, _ g: Int, _ b: Int) { self.r = r; self.g = g; self.b = b }
    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
}

/// Shape signal from your Vision / image step.
///   aspectRatio = width / height of the object's bounding box.
///   roundness   = 0 (jagged / rectangular) ... 1 (circular).
public struct ShapeSignal {
    public var aspectRatio: Float
    public var roundness: Float
    public init(aspectRatio: Float, roundness: Float) {
        self.aspectRatio = aspectRatio
        self.roundness = roundness
    }
}

/// Result of object recognition. Pass `nil` to the generator (or `.unknown`
/// category / low confidence) and the creature is pure Layer 1.
public struct RecognizedObject {
    public var label: String?
    public var category: ObjectCategory
    public var confidence: Float
    public init(label: String?, category: ObjectCategory, confidence: Float) {
        self.label = label
        self.category = category
        self.confidence = confidence
    }
}

// MARK: - Creature composition

/// The always-drawn base parts (Layer 1). IDs index your sprite atlas.
public struct AurieParts: Codable, Equatable {
    public var bodyId: Int
    public var eyesId: Int
    public var mouthId: Int
    public var limbsId: Int
}

/// Object-inspired detail slots. All optional - `nil` means the slot is empty.
public struct DetailSlots: Codable, Equatable {
    public var headCharmId: Int?
    public var cheekMarkId: Int?
    public var bellyPatternId: Int?
    public var sideDetailId: Int?
    public var tailCharmId: Int?
    public var textureId: Int?
    public init() {}
}

/// One saved creature - fully self-contained (the original photo is never kept).
public struct Aurie: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var family: AuraFamily
    public var body: BodyType
    public var category: ObjectCategory   // what it hatched from (or .unknown)
    public var bornFrom: String           // profile line: label or "a mysterious shape"

    public var parts: AurieParts
    public var slots: DetailSlots

    public var baseColor: Rgb             // tints body / limbs / pattern
    public var auraColor: Rgb             // the glow tint

    public var line: String               // the ONE permanent line, composed at hatch
    public var traits: [String]           // 3 personality adjectives, chosen at hatch
    public var sourceThumbnail: String?   // small object thumbnail reference
    public var hatchedAt: Date
    public var seed: UInt64               // rebuilds the exact same creature

    /// The saved personality face, chosen once at hatch from the family
    /// weighting. OPTIONAL only so collections written before this field
    /// existed still decode — synthesized Codable treats a missing key as
    /// nil for Optionals, whereas a non-optional would throw and (given
    /// Store's `?? []`) silently wipe the whole collection on update.
    /// `Store` migrates those records on load and persists the resolved
    /// value, after which this is always set.
    ///
    /// Read `resolvedBaseExpression`, never this, so no caller has to
    /// think about the pre-migration nil.
    public var baseExpression: BaseExpression?

    /// The body pattern, chosen ONCE at hatch and never rerolled. OPTIONAL for
    /// the same migration reason as `baseExpression`: collections written
    /// before patterns existed must still decode. Unlike the limb styles the
    /// fallback is NOT seed-based — a pre-pattern Aurie stays plain (`.none`)
    /// so integrating patterns never changes an existing creature's look.
    /// `Store` resolves and persists it on load. Read `resolvedPattern`.
    public var pattern: PatternType?

    /// The saved limb styles, chosen once at hatch. OPTIONAL for exactly the
    /// same reason as `baseExpression`: collections written before these
    /// fields existed must still decode. `Store` resolves and persists them
    /// on load, after which they are always set.
    ///
    /// Read `resolvedArmStyle` / `resolvedLegStyle`, never these.
    public var armStyle: String?
    public var legStyle: String?

    /// Hair style id (`tuft` or `hair_00`…). Optional for save
    /// compatibility: creatures hatched before hair existed decode to nil
    /// and resolve to the baked crown tuft they have always worn.
    /// Read `resolvedHairStyle`, never this.
    public var hairStyle: String?

    /// CHARMS THIS AURIE WEARS (2026-09-14, replaces the never-written
    /// tail/head/backAccessoryID trio while it was still safe to do so:
    /// no build ever wrote those fields, and Codable ignores their keys
    /// in any save that somehow carries them).
    ///
    /// An extensible ARRAY, not per-slot fields, so future slots
    /// (forehead, cheek, neck, shoulder, wrist, ankle, floating, aura…)
    /// are data instead of migrations. OPTIONAL for the same
    /// decode-compat reason as `baseExpression`: collections written
    /// before charms existed decode to nil and resolve to []. Read
    /// `resolvedEquippedCharms`, never this.
    ///
    /// Equipping is a REFERENCE to an account-level unlock
    /// (CharmCollection), never a copy — deleting this Aurie deletes
    /// nothing the user owns, and one owned charm may dress any number
    /// of Auries. NOT legacy `DetailSlots` (`headCharmId` etc.), which
    /// is a frozen 2D sprite-index system.
    public var equippedCharms: [EquippedCharm]?

    /// BIRTH CHARM provenance (Phase D, 2026-09-18): the charm this
    /// Aurie's hatch photo earned, recorded ONCE at commitHatch and
    /// never rewritten. Pure history — it is NOT an equipment slot:
    /// the newborn merely STARTS with this charm equipped (through the
    /// ordinary one-per-placement rule), and removing/replacing that
    /// equipment later leaves this field untouched, exactly as the
    /// account-level unlock stays owned. OPTIONAL for the same
    /// decode-compat reason as `baseExpression`: every save written
    /// before Birth Charms existed decodes to nil (an ordinary hatch),
    /// and synthesized Codable omits the key when nil, so older app
    /// builds reading a newer save simply ignore it. No migration —
    /// unlike the limb styles there is nothing to resolve or backfill:
    /// nil permanently means "hatched without a Birth Charm".
    public var birthCharmID: String?
}

/// Which way the RENDERED creature faces. RUNTIME STATE ONLY — never
/// persisted on the saved Aurie: a creature saved mid-walk must not
/// reopen backwards, so this is not Codable and no Aurie field stores
/// it.
///
/// Launch scope is front/back. Future orientations are added as new
/// cases (left, right, threeQuarterLeft, threeQuarterRight) whose art
/// and placement come from the Blender export pipeline — orientation
/// is NEVER faked by flipping, rotating or hand-repositioning front
/// sprites (baked lighting and asymmetric hair make every fake read
/// wrong; see AurieNode.face()'s pin note).
public enum AurieOrientation: String, CaseIterable {
    case front
    case back
    // future: left, right, threeQuarterLeft ("3q_left"),
    // threeQuarterRight ("3q_right")

    /// Asset-name suffix. FRONT IS IMPLICIT: the existing catalog
    /// (aurie_round_body, …) predates orientation and stays
    /// suffix-less; other orientations append their key
    /// (aurie_round_body_back; future …_left, …_3q_left).
    public var assetSuffix: String {
        self == .front ? "" : "_" + rawValue
    }
}

public extension Aurie {
    /// The limb styles this Aurie wears. Prefers the SAVED value and only
    /// falls back to the deterministic seed pick for records written before
    /// the fields existed — so adding limb styles, changing the weighting,
    /// or changing compatibility rules can never re-limb an Aurie that
    /// already exists. `Store` persists the fallback on first load.
    var resolvedArmStyle: String {
        armStyle ?? AurieLimbCatalog.seededArm(seed)
    }

    /// The charms this Aurie wears. Pre-charm records resolve to bare
    /// (empty), and an empty list stays empty forever — nothing is ever
    /// auto-equipped.
    var resolvedEquippedCharms: [EquippedCharm] { equippedCharms ?? [] }

    var resolvedLegStyle: String {
        legStyle ?? AurieLimbCatalog.seededLeg(seed)
    }

    /// The hair this Aurie wears. Pre-hair records resolve to the baked
    /// crown tuft (what they have always shown), NOT to a seed pick, so
    /// adding hair styles never re-hairs a creature that already exists.
    var resolvedHairStyle: String { hairStyle ?? "tuft" }

    /// The face this Aurie shows at rest. Falls back to the deterministic
    /// seed-based pick for records written before `baseExpression`
    /// existed, so an Aurie that already exists keeps its face forever
    /// even if the weighting table changes later.
    var resolvedBaseExpression: BaseExpression {
        baseExpression
            ?? AuriePersonality.baseExpression(family: family, seed: seed)
    }

    /// The pattern this Aurie wears. Pre-pattern records fall back to `.none`
    /// (they stay plain), NOT to a seed pick, so adding the pattern system
    /// never repaints a creature that already exists. `Store` persists this.
    var resolvedPattern: PatternType { pattern ?? .none }

    /// The Blender mask layer id to composite for this Aurie's pattern, or nil
    /// when it is plain / the body has no mask for that pattern. Stable for the
    /// life of the creature because it derives only from the persisted seed.
    var patternMaskLayer: String? { resolvedPattern.maskLayer(seed: seed) }
}
