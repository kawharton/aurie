import Foundation

/// The part styles the launch build can assign, their physical classes, and
/// the ONE place body↔part compatibility lives.
///
/// DESIGN (2026-09-12 part-variety pass):
/// - Every part id list is APPEND-ONLY: ids are persisted on saved Auries.
/// - Selection filters by explicit class metadata (below), never by scale
///   fudging after the pick. THE launch rule (2026-09-13 revision): a
///   long arm only ever accompanies long legs — on any body.
/// - If filtering ever produces an empty pool, selection falls back to the
///   known-good defaults (`arm_00` / `leg_00` / the baked tuft), which every
///   launch body ships art for — a malformed Aurie is impossible.
enum AurieLimbCatalog {

    // MARK: - Part ids (append-only)

    /// arm_03 (Bud Nubs), arm_04 (Soft Mittens) and arm_05 (Wing Flaps)
    /// were REMOVED 2026-09-13 by user direction — the roster is back to
    /// the original trio. All three ids are BURNED: they lived on test
    /// devices, so they must never be reused for different art; a
    /// persisted arm_03/04/05 falls back to arm_00 at render time.
    static let arms = ["arm_00", "arm_01", "arm_02"]     // launch trio
    /// 2026-09-13 renumbering (user instruction, pre-launch with no real
    /// saves): leg_04 = metaball Paw Steps (built as leg_07), leg_05 =
    /// metaball Bulb Boots (built as the leg-08 candidate). The ids
    /// leg_06 and leg_07 are BURNED — they briefly meant other geometry
    /// on test devices, so they must never be reused; a persisted burned
    /// or unknown id falls back to leg_00 at render time.
    static let legs = ["leg_00", "leg_01", "leg_02", "leg_03",
                       "leg_04", "leg_05"]

    /// The pool the LAUNCH build may select and render.
    static let launchLegs = ["leg_00", "leg_01", "leg_02", "leg_03",
                             "leg_04", "leg_05"]

    /// Hair styles. `tuft` is the body-baked crown sprout every creature had
    /// before hair existed — it stays the default and the migration value.
    /// The id list is append-only (ids are persisted on saved Auries).
    /// 2026-09-13 metaball pass: hair_00 = Cloud Puff (approved). The
    /// sculpted styles that briefly held ids hair_00…04 never shipped in
    /// any build (their imagesets were removed and rendering fell back to
    /// the tuft), so hair_00 safely carries the new art. 2026-09-14:
    /// hair_01 = Soft Mohawk (mesh petals, approved); Twin Poms
    /// (approved-but-held) takes the next free id when integrated;
    /// hair_02…04 stay reserved-unused.
    static let hair = ["tuft", "hair_00", "hair_01", "hair_02", "hair_03",
                       "hair_04"]

    /// The pool the LAUNCH build may select and render: the baked tuft,
    /// the metaball Cloud Puff (2026-09-13) and the mesh Soft Mohawk
    /// (approved 2026-09-14).
    static let launchHair = ["tuft", "hair_00", "hair_01"]

    // MARK: - Physical classes

    enum ArmLength: Int, Comparable {
        case short = 0, standard = 1, long = 2
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }
    enum LegLength: Int, Comparable {
        case short = 0, standard = 1, long = 2
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }
    /// Height/compactness read of a body SILHOUETTE, measured from the real
    /// rendered proportions in `AurieBlenderAssets` (body layer w:h) plus
    /// absolute size. `compact` bodies are the ones a long limb overwhelms.
    enum BodyStature { case compact, medium, tall }
    enum BodyBuild { case narrow, medium, wide }

    /// Arm length classes. Reaches from the sculpt sources
    /// (aurie_limb_styles.py, scene units on Round):
    /// flipper 0.38 / tiny-hands 0.16 / noodle 0.59.
    static let armLength: [String: ArmLength] = [
        "arm_00": .standard,    // Rounded Flipper
        "arm_01": .short,       // Tiny Hands
        "arm_02": .long,        // Noodle Arms
    ]

    /// Leg length classes (column height / body lift from the same source):
    /// short-standing 0.35 / bounce-feet none / chibi 0.38 / splayed pods /
    /// tall-walkers 0.70 / haunches none / pigeon 0.37.
    static let legLength: [String: LegLength] = [
        "leg_00": .standard,    // Short Standing
        "leg_01": .short,       // Bounce Feet
        "leg_02": .standard,    // Chibi Stance
        "leg_03": .standard,    // Splayed Feet
        "leg_04": .long,        // Paw Steps (metaball; longer column)
        "leg_05": .long,        // Bulb Boots (metaball; longest lift)
    ]

    /// Stature per launch body, from the rendered body layer's aspect
    /// (w/h — AurieBlenderAssets sizes) and absolute footprint:
    /// tall 0.76, oval 0.81 → tall · teardrop 0.86, egg 0.89, pear 0.90,
    /// heart 1.01, round 1.09 → medium · small 0.94 BUT smallest absolute
    /// body, dumpling 1.17, beanbag 1.29 → compact.
    static func stature(_ body: BodyType) -> BodyStature {
        switch body {
        case .tall, .oval: return .tall
        case .small, .dumpling, .beanbag, .lumpy: return .compact
        default: return .medium
        }
    }

    static func build(_ body: BodyType) -> BodyBuild {
        switch body {
        case .tall, .oval, .teardrop: return .narrow
        case .round, .dumpling, .beanbag, .wide, .lumpy: return .wide
        default: return .medium
        }
    }

    // MARK: - Compatibility rules

    /// 2026-09-13: the compact-body caps were LIFTED by user direction
    /// after visual review (aurie-review-evidence/legs/
    /// compact_long_combo.png): long legs raise even a compact body
    /// enough that the noodle arms clear the ground. Every body may now
    /// roll every length; the one remaining constraint is the PAIRING
    /// rule in `roll` — long arms only accompany long legs — which is
    /// exactly what makes the compact combination safe.
    static func maxArmLength(for body: BodyType) -> ArmLength { .long }

    static func maxLegLength(for body: BodyType) -> LegLength { .long }

    /// Hair styles a body cannot wear. The metaball Cloud Puff (hair_00)
    /// was the one suspect case on Heart's cleft crown, and the
    /// 2026-09-13 per-body renders show its adaptive sink nests it
    /// between the lobes cleanly.
    /// 2026-09-14 hair_01 rollout: Heart's cleft crown DOES break the
    /// Soft Mohawk — the flat between-lobes profile defeats the sagittal
    /// skull-circle fit (radius hits its clamp) and the rear spikes land
    /// detached behind the body (aurie-review-evidence/hair01_softmohawk/
    /// rollout). Excluded until the fit gets a per-axis crown measure;
    /// the other nine launch bodies passed.
    static let hairExcluded: [String: Set<BodyType>] = [
        "hair_01": [.heart],
    ]

    // MARK: - Compatible pools

    static func compatibleArms(for body: BodyType) -> [String] {
        let cap = maxArmLength(for: body)
        return arms.filter { (armLength[$0] ?? .long) <= cap }
    }

    static func compatibleLegs(for body: BodyType) -> [String] {
        let cap = maxLegLength(for: body)
        return launchLegs.filter { (legLength[$0] ?? .long) <= cap }
    }

    static func compatibleHair(for body: BodyType) -> [String] {
        launchHair.filter { !(hairExcluded[$0]?.contains(body) ?? false) }
    }

    // MARK: - Selection

    /// Fresh picks for a NEW creature, drawn from the hatch RNG so they are
    /// part of the seed's deterministic roll, then saved explicitly. Only
    /// compatible candidates enter the pool; an empty pool (impossible for
    /// the launch matrix, but the guard is the contract) falls back to the
    /// known-good defaults every body ships.
    ///
    /// 2026-09-13 selection shaping (user direction, two passes):
    /// - LONG arms only accompany LONG legs (a noodle arm without the tall
    ///   stance reads wrong); long legs pair with ANY arm.
    /// - arm_00 is the user's least-favourite arm: fixed 20% share.
    /// - Noodles were still too rare at ~13%, and the user chose to pay
    ///   for more with fewer short legs. So: HALF of all leg rolls come
    ///   from the long group (leg_04/leg_05), and when the leg is long the
    ///   long arm takes half of ALL arm rolls (arm_00 keeps its 20%; the
    ///   other arms split the remaining 30%). Net ≈ 25% of new creatures
    ///   get noodle arms.
    static let armZeroShare = 20   // percent of arm rolls that are arm_00
    static let legLongShare = 50   // percent of leg rolls that are long
    static let armLongShare = 50   // percent of arm rolls that are long,
                                   // when the rolled leg allows them

    static func roll(for body: BodyType, _ rng: inout SeededGenerator)
        -> (arm: String, leg: String, hair: String) {
        func pick(_ pool: [String], fallback: String) -> String {
            guard !pool.isEmpty else { return fallback }
            return pool[Int.random(in: 0..<pool.count, using: &rng)]
        }
        let legPool = compatibleLegs(for: body)
        let longLegs = legPool.filter { (legLength[$0] ?? .standard) == .long }
        let restLegs = legPool.filter { (legLength[$0] ?? .standard) < .long }
        let leg: String
        if longLegs.isEmpty || restLegs.isEmpty {
            leg = pick(legPool, fallback: "leg_00")
        } else if Int.random(in: 0..<100, using: &rng) < legLongShare {
            leg = pick(longLegs, fallback: "leg_00")
        } else {
            leg = pick(restLegs, fallback: "leg_00")
        }
        var armPool = compatibleArms(for: body)
        if (legLength[leg] ?? .standard) < .long {
            armPool.removeAll { (armLength[$0] ?? .long) == .long }
        }
        let arm: String
        let others = armPool.filter { $0 != "arm_00" }
        let longArms = others.filter { (armLength[$0] ?? .standard) == .long }
        let midArms = others.filter { (armLength[$0] ?? .standard) < .long }
        if others.isEmpty {
            arm = armPool.first ?? "arm_00"
        } else if armPool.contains("arm_00"),
                  Int.random(in: 0..<100, using: &rng) < armZeroShare {
            arm = "arm_00"
        } else if !longArms.isEmpty, !midArms.isEmpty,
                  Int.random(in: 0..<(100 - armZeroShare),
                             using: &rng) < armLongShare {
            arm = pick(longArms, fallback: "arm_00")
        } else if !midArms.isEmpty {
            arm = pick(midArms, fallback: "arm_00")
        } else {
            arm = pick(others, fallback: "arm_00")
        }
        return (arm, leg, pick(compatibleHair(for: body), fallback: "tuft"))
    }

    // MARK: - Migration fallbacks (FROZEN)

    /// The deterministic fallbacks used to resolve creatures saved before
    /// `armStyle`/`legStyle` were stored fields. FROZEN on the original
    /// 3-arm / 4-leg lists: these expressions must return the same style for
    /// the same seed forever, so they deliberately do NOT read the growing
    /// `arms`/`legs` lists above.
    private static let migrationArms = ["arm_00", "arm_01", "arm_02"]
    private static let migrationLegs = ["leg_00", "leg_01", "leg_02",
                                        "leg_03"]

    static func seededArm(_ seed: UInt64) -> String {
        migrationArms[Int(seed % UInt64(migrationArms.count))]
    }

    static func seededLeg(_ seed: UInt64) -> String {
        migrationLegs[Int((seed / 3) % UInt64(migrationLegs.count))]
    }
}
