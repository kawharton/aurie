import Foundation

public enum AurieGenerator {

    // MARK: Tuning
    public static let starlightChance: Double = 0.04
    static let neutralSatCutoff: Float = 0.18
    static let darkValueCutoff: Float  = 0.12
    static let recognitionConfidenceThreshold: Float = 0.40

    static let eyesCount = 8, mouthCount = 6, limbsCount = 6

    static let auraColors: [AuraFamily: Rgb] = [
        .ember:     Rgb(255,  94,  58),
        .glow:      Rgb(255, 209,  84),
        .moss:      Rgb(120, 190, 110),
        .tide:      Rgb( 74, 165, 200),
        .dusk:      Rgb(150, 110, 200),
        .stone:     Rgb(150, 150, 150),
        .starlight: Rgb(180, 200, 255),
    ]

    // MARK: - Hatch

    /// Build a finished, saveable Aurie from colour + shape (+ optional recognition).
    /// The creature's ONE permanent line is composed here and stored on it.
    public static func generate(
        dominantColor: Rgb,
        shape: ShapeSignal,
        recognized: RecognizedObject?,
        existingNames: Set<String>,
        content: AurieContent,
        forcedSeed: UInt64? = nil
    ) -> Aurie {
        let seed = forcedSeed ?? UInt64.random(in: 0 ... UInt64.max)
        var rng = SeededGenerator(seed: seed)

        // ---- Layer 1: always on ----
        let family = rollFamily(dominantColor, &rng)
        var body = shapeToBody(shape, &rng)
        let fc = content.family(family)
        let name = makeName(fc, existing: existingNames, &rng)

        var slots = DetailSlots()
        var category: ObjectCategory = .unknown
        var bornFrom = "a mysterious shape"

        // ---- Layers 2 + 3: only if recognised ----
        if let r = recognized,
           r.confidence >= recognitionConfidenceThreshold,
           r.category != .unknown {
            category = r.category
            if let label = r.label { bornFrom = label }
            if let cc = content.category(r.category) {
                slots.headCharmId    = pickOptional(cc.headCharms, &rng)
                slots.bellyPatternId = pickOptional(cc.bellyPatterns, &rng)
                slots.sideDetailId   = pickOptional(cc.sideDetails, &rng)
                slots.tailCharmId    = pickOptional(cc.tailCharms, &rng)
                slots.textureId      = pickOptional(cc.textures, &rng)
            }
            if let label = r.label, let hero = content.hero(label) {
                hero.apply(to: &slots)
            }
            // BODY NUDGE: let the recognised OBJECT have a say in the
            // silhouette. `shapeToBody` only ever sees two scalars — bbox
            // aspect and roundness — so a pear and an apple of similar
            // proportions are the same input, and the pear body was
            // effectively unreachable from a photo of a pear. Recognition
            // knows better, so when it is confident it wins.
            //
            // Consumes no RNG, so a creature whose label has no hint is
            // bit-identical to what the same seed produced before.
            if let hinted = Self.hintedBody(for: r.label) {
                body = hinted
            }
        }

        // Parts roll AFTER the body is known: only body-compatible arms,
        // legs and hair enter the pool (AurieLimbCatalog owns the rules).
        let limbs = AurieLimbCatalog.roll(for: body, &rng)
        return Aurie(
            id: UUID().uuidString,
            name: name,
            family: family,
            body: body,
            category: category,
            bornFrom: bornFrom,
            parts: rollParts(body, &rng),
            slots: slots,
            baseColor: nudgeTowardFamily(dominantColor, family),
            auraColor: auraColors[family]!,
            line: composeLine(fc, name: name, &rng),
            traits: Array(fc.traits.shuffled(using: &rng).prefix(3)),
            sourceThumbnail: nil,
            hatchedAt: Date(),
            seed: seed,
            // Personality face: family-weighted (preferred 3 / secondary 2 /
            // rest 1), drawn from the SAME seeded stream as the rest of the
            // creature so one seed still rebuilds an identical Aurie. Saved
            // permanently here and never rerolled afterwards.
            baseExpression: AuriePersonality.pick(
                AuriePersonality.expressionWeights(for: family)
            ) { Int.random(in: 0 ..< $0, using: &rng) },
            // Body pattern: the launch-weighted roll, drawn LAST from the same
            // seeded stream so one seed still rebuilds an identical Aurie and
            // every earlier trait pick is unchanged. Saved permanently here and
            // never rerolled — the render just reads `resolvedPattern`.
            pattern: PatternType.roll(&rng),
            // The compatibility-filtered part picks, saved explicitly at
            // hatch. (Before the 2026-09-12 pass the roll's result was
            // dropped and Store's seeded migration filled these instead.)
            armStyle: limbs.arm,
            legStyle: limbs.leg,
            hairStyle: limbs.hair
        )
    }

    // MARK: - The permanent line (composed once, at hatch)

    /// Pick one of the family's templates and fill {name} + {mood}. Deterministic
    /// for a given seed, so a creature always rebuilds the identical line.
    static func composeLine(_ fc: FamilyContent, name: String, _ rng: inout SeededGenerator) -> String {
        guard var line = fc.lineTemplates.randomElement(using: &rng) else { return name }
        line = line.replacingOccurrences(of: "{name}", with: name)
        if line.contains("{mood}") {
            let mood = fc.moods.randomElement(using: &rng) ?? ""
            line = line.replacingOccurrences(of: "{mood}", with: mood)
        }
        return line
    }

    // MARK: - Reaction lines (repeat freely; NOT stored on the creature)

    /// Shake reaction, in the creature's family voice.
    public static func shakeLine(for aurie: Aurie, content: AurieContent) -> String {
        content.family(aurie.family).shake.randomElement() ?? ""
    }
    /// Pet reaction, in the creature's family voice.
    public static func petLine(for aurie: Aurie, content: AurieContent) -> String {
        content.family(aurie.family).pet.randomElement() ?? ""
    }
    /// Tickle reaction - shared pool, any creature.
    public static func tickleLine(_ content: AurieContent) -> String {
        content.sharedPlay.tickle.randomElement() ?? ""
    }
    /// Pick-up reaction - shared pool, any creature.
    public static func pickupLine(_ content: AurieContent) -> String {
        content.sharedPlay.pickup.randomElement() ?? ""
    }

    // MARK: - Colour -> family

    static func rollFamily(_ c: Rgb, _ rng: inout SeededGenerator) -> AuraFamily {
        if Double.random(in: 0..<1, using: &rng) < starlightChance { return .starlight }
        let (h, s, v) = toHSV(c)
        if s < neutralSatCutoff || v < darkValueCutoff { return .stone }
        switch h {
        case ..<40, 330...: return .ember
        case ..<70:  return .glow
        case ..<165: return .moss
        case ..<255: return .tide
        default:     return .dusk
        }
    }

    /// The family a colour WOULD land in, without rolling Starlight — the
    /// egg screen uses this to pick a shell palette before the creature
    /// exists, so the shell belongs to the right world without revealing a
    /// rare override early.
    static func likelyFamily(_ c: Rgb) -> AuraFamily {
        let (h, s, v) = toHSV(c)
        if s < neutralSatCutoff || v < darkValueCutoff { return .stone }
        switch h {
        case ..<40, 330...: return .ember
        case ..<70:  return .glow
        case ..<165: return .moss
        case ..<255: return .tide
        default:     return .dusk
        }
    }

    /// Shell colour for the hatch egg. The body nudges the photo colour 25%
    /// toward the family aura; the shell goes further (60%) so it reads as
    /// that family's world — a Dusk hatch gets a violet/indigo shell rather
    /// than the photo's raw blue — while still not being the exact creature
    /// colour. The neutral shell render is mid-grey, so multiplying by this
    /// lands deeper and more atmospheric than the revealed Aurie.
    static func shellColor(_ c: Rgb) -> Rgb {
        let a = auraColors[likelyFamily(c)]!
        let t = 0.60
        return Rgb(Int(Double(c.r) + Double(a.r - c.r) * t),
                   Int(Double(c.g) + Double(a.g - c.g) * t),
                   Int(Double(c.b) + Double(a.b - c.b) * t))
    }

    static func toHSV(_ c: Rgb) -> (Float, Float, Float) {
        let r = Float(c.r) / 255, g = Float(c.g) / 255, b = Float(c.b) / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h: Float = 0
        if d > 1e-5 {
            if mx == r      { h = 60 * (((g - b) / d).truncatingRemainder(dividingBy: 6)) }
            else if mx == g { h = 60 * (((b - r) / d) + 2) }
            else            { h = 60 * (((r - g) / d) + 4) }
        }
        if h < 0 { h += 360 }
        let s = mx <= 0 ? 0 : d / mx
        return (h, s, mx)
    }

    // MARK: - Recognised object -> body

    /// Label -> body, applied only when recognition is confident (the same
    /// gate as Layers 2 and 3). An UNLISTED label changes nothing, so this
    /// is a nudge over `shapeToBody`, never a replacement for it.
    ///
    /// Only labels whose body genuinely evokes the object are listed —
    /// a wrong-but-confident mapping would be worse than the shape roll.
    /// Boxy and flat objects — book, phone, key, box, card — are
    /// deliberately ABSENT: the launch pool has no square body, so there
    /// is nothing honest to map them to. Add them when one ships.
    static let bodyHint: [String: BodyType] = [
        // Spherical
        "apple": .round, "bagel": .round, "ball": .round,
        "balloon": .round, "beach ball": .round, "biscuit": .round,
        "bubble": .round, "cherry": .round, "coconut": .round,
        "cookie": .round, "cupcake": .round, "dish": .round,
        "donut": .round, "doughnut": .round, "globe": .round,
        "grapefruit": .round, "marble": .round, "meatball": .round,
        "melon": .round, "muffin": .round, "onion": .round,
        "orange": .round, "pancake": .round, "peach": .round,
        "pie": .round, "plate": .round, "plum": .round, "pumpkin": .round,
        "saucer": .round, "tomato": .round,
        // Ovoid
        "almond": .egg, "egg": .egg, "kiwi": .egg, "lemon": .egg,
        "lime": .egg, "mango": .egg, "nut": .egg, "olive": .egg,
        "pebble": .egg, "potato": .egg, "rock": .egg, "stone": .egg,
        "walnut": .egg,
        // Bottom-heavy taper
        "aubergine": .pear, "avocado": .pear, "bulb": .pear,
        "eggplant": .pear, "fig": .pear, "gourd": .pear,
        "lightbulb": .pear, "pear": .pear, "squash": .pear,
        // Long and rounded
        "football": .oval, "papaya": .oval, "rugby ball": .oval,
        "watermelon": .oval,
        // Cone / petal taper
        "blossom": .teardrop, "carrot": .teardrop, "chili": .teardrop,
        "cone": .teardrop, "daisy": .teardrop, "flower": .teardrop,
        "ice cream": .teardrop, "icecream": .teardrop, "leaf": .teardrop,
        "orchid": .teardrop, "pepper": .teardrop, "petal": .teardrop,
        "pine cone": .teardrop, "pinecone": .teardrop, "rose": .teardrop,
        "strawberry": .teardrop, "sunflower": .teardrop,
        "tulip": .teardrop,
        // Long — one pool now, whichever way the photo was held
        "paper towel": .tall, "paper towels": .tall,
        "toilet paper": .tall, "kitchen roll": .tall,
        "tissue": .tall, "tissues": .tall, "paper roll": .tall,
        "soda": .tall, "soft drink": .tall, "soda can": .tall,
        "cola": .tall, "beverage": .tall, "drink": .tall, "juice": .tall,
        "energy drink": .tall, "tin can": .tall, "aluminum can": .tall,
        "aluminium can": .tall, "beer": .tall,
        "asparagus": .tall, "baguette": .tall, "bamboo": .tall,
        "banana": .tall, "bottle": .tall, "brush": .tall, "cactus": .tall,
        "can": .tall, "canteen": .tall, "celery": .tall, "corn": .tall,
        "crayon": .tall, "cucumber": .tall, "flask": .tall, "jug": .tall,
        "leek": .tall, "marker": .tall, "pen": .tall, "pencil": .tall,
        "pitcher": .tall, "thermos": .tall, "tin": .tall,
        "toothbrush": .tall, "tree": .tall, "vase": .tall,
        "zucchini": .tall,
        // Squat and wide
        "backpack": .dumpling, "bag": .dumpling, "barrel": .dumpling,
        "basket": .dumpling, "bowl": .dumpling, "bread": .dumpling,
        "bucket": .dumpling, "burger": .dumpling, "cake": .dumpling,
        "cup": .dumpling, "cushion": .dumpling, "hamburger": .dumpling,
        "handbag": .dumpling, "jar": .dumpling, "kettle": .dumpling,
        "knapsack": .dumpling, "loaf": .dumpling, "mug": .dumpling,
        "pillow": .dumpling, "pot": .dumpling, "purse": .dumpling,
        "rucksack": .dumpling, "sandwich": .dumpling, "teacup": .dumpling,
        "teapot": .dumpling,
        // Slouchy / plush
        "blanket": .beanbag, "cloth": .beanbag, "doll": .beanbag,
        "glove": .beanbag, "hoodie": .beanbag, "jacket": .beanbag,
        "mitten": .beanbag, "plush": .beanbag, "plushie": .beanbag,
        "puppet": .beanbag, "scarf": .beanbag, "sock": .beanbag,
        "stuffed animal": .beanbag, "sweater": .beanbag,
        "teddy": .beanbag, "towel": .beanbag,
        // Heart-shaped
        "heart": .heart,
    ]

    /// The hint for a recognised label, or nil to leave `shapeToBody` alone.
    ///
    /// Matches the whole label first, then any WHOLE WORD inside it, so a
    /// raw classifier identifier like "water bottle" or "bartlett pear"
    /// still resolves. Whole-word only, never substring: the same trap
    /// `Recognition.matches` documents — substring matching turns
    /// "pineapple" into "apple".
    static func hintedBody(for rawLabel: String?) -> BodyType? {
        guard let label = rawLabel?.lowercased() else { return nil }
        if let hit = bodyHint[label], BodyType.launchPool.contains(hit) {
            return hit
        }
        for word in label.split(separator: " ") {
            if let hit = bodyHint[String(word)],
               BodyType.launchPool.contains(hit) {
                return hit
            }
        }
        return nil
    }

    // MARK: - Shape -> body

    /// The photo's shape still chooses the FAMILY of silhouette, but the
    /// launch pool now has ten bodies, so each bucket offers a couple of
    /// candidates and the seed picks within it. Deferred bodies (wide,
    /// lumpy) are never generated while they sit outside `launchPool`.
    static func shapeToBody(_ s: ShapeSignal,
                            _ rng: inout SeededGenerator) -> BodyType {
        // ELONGATION IS ORIENTATION-INDEPENDENT (2026-09-26). The old rule
        // read the raw bbox ratio, so a LANDSCAPE long object took the
        // aspect > 1.4 branch and a PORTRAIT one took aspect < 0.7 — the
        // same banana hatched a beanbag lying down and a tall standing up,
        // purely from how the photo was framed. Measured over the stress
        // set, one object produced three different bodies across rotation,
        // crop and exposure.
        //
        // `elongation` collapses both directions onto one number (>= 1),
        // so "long" means long however the photo was held, and the long
        // bodies share a single pool. Every launch body is still
        // reachable: round/dumpling/oval (blobby), tall/teardrop/beanbag
        // (long), heart/teardrop/pear (angular), small/pear/egg (ordinary).
        let a = max(s.aspectRatio, 0.0001)
        let elongation = max(a, 1 / a)
        let candidates: [BodyType]
        if s.roundness > 0.75 {
            candidates = [.round, .dumpling, .oval]
        } else if elongation > 1.4 {
            candidates = [.tall, .teardrop, .beanbag]
        } else if s.roundness < 0.35 {
            candidates = [.heart, .teardrop, .pear]
        } else {
            candidates = [.small, .pear, .egg]
        }
        let pool = candidates.filter { BodyType.launchPool.contains($0) }
        guard !pool.isEmpty else { return .round }
        return pool[Int.random(in: 0..<pool.count, using: &rng)]
    }

    // MARK: - Parts

    static func rollParts(_ body: BodyType, _ rng: inout SeededGenerator) -> AurieParts {
        AurieParts(
            bodyId: BodyType.allCases.firstIndex(of: body)!,
            eyesId: Int.random(in: 0..<eyesCount, using: &rng),
            mouthId: Int.random(in: 0..<mouthCount, using: &rng),
            limbsId: Int.random(in: 0..<limbsCount, using: &rng)
        )
    }

    static func nudgeTowardFamily(_ c: Rgb, _ f: AuraFamily) -> Rgb {
        let a = auraColors[f]!
        let t = 0.25
        return Rgb(
            Int(Double(c.r) + Double(a.r - c.r) * t),
            Int(Double(c.g) + Double(a.g - c.g) * t),
            Int(Double(c.b) + Double(a.b - c.b) * t)
        )
    }

    // MARK: - Naming

    static func makeName(_ fc: FamilyContent, existing: Set<String>, _ rng: inout SeededGenerator) -> String {
        let free = fc.names.filter { !existing.contains($0) }
        if !free.isEmpty { return free[Int.random(in: 0..<free.count, using: &rng)] }
        for _ in 0..<30 {
            let cand = cap(pick(fc.nameSyllables, &rng) + pick(fc.nameSyllables, &rng))
            if !existing.contains(cand) { return cand }
        }
        let base = cap(pick(fc.nameSyllables, &rng) + pick(fc.nameSyllables, &rng))
        var i = 2
        while existing.contains("\(base) \(i)") { i += 1 }
        return "\(base) \(i)"
    }

    // MARK: - Helpers

    static func pick(_ a: [String], _ rng: inout SeededGenerator) -> String {
        a[Int.random(in: 0..<a.count, using: &rng)]
    }
    static func pickOptional(_ a: [Int], _ rng: inout SeededGenerator) -> Int? {
        a.isEmpty ? nil : a[Int.random(in: 0..<a.count, using: &rng)]
    }
    static func cap(_ s: String) -> String {
        s.isEmpty ? s : s.prefix(1).uppercased() + s.dropFirst()
    }
}

/// Small deterministic RNG (SplitMix64) so a given seed always rebuilds the same
/// creature. Conforms to RandomNumberGenerator, so `.random(in:using:)` and
/// `.randomElement(using:)` work with it.
