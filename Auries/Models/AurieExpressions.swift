import Foundation

// MARK: - Base expression (PERSISTED personality)

/// The ten launch expressions. One is chosen at hatch, saved with the
/// Aurie, and never rerolled. Reaction faces are deliberately NOT in
/// this enum: a reaction borrows the face for a moment, it never becomes
/// the creature's personality.
///
/// String-backed and append-only, like `BodyType` — do not reorder or
/// remove cases, existing saves decode by raw value.
public enum BaseExpression: String, Codable, CaseIterable {
    case happy, excited, sleepy, shy, curious
    case surprised, mischievous, worried, pouty, delighted

    public var displayName: String {
        switch self {
        case .happy: return "Classic Happy"
        case .excited: return "Excited"
        case .sleepy: return "Sleepy"
        case .shy: return "Shy"
        case .curious: return "Curious"
        case .surprised: return "Surprised"
        case .mischievous: return "Mischievous"
        case .worried: return "Worried"
        case .pouty: return "Pouty"
        case .delighted: return "Big Happy / Delighted"
        }
    }
}

// MARK: - Reactions (TEMPORARY overrides)

/// A short reusable reaction. It overrides the visible face and nudges
/// the body, then hands both back to the saved base expression. Never
/// persisted.
public enum AurieReaction: String, CaseIterable {
    case blink, dizzy, happyBounce, startled
    case curiousLook, sleepyYawn, calmSettle, excitedHop

    /// Higher wins. High interrupts anything; medium interrupts idle;
    /// blink yields to everything (see `canInterrupt`).
    public var priority: Int {
        switch self {
        case .excitedHop, .dizzy, .startled: return 30
        case .happyBounce, .curiousLook, .calmSettle: return 20
        case .blink, .sleepyYawn: return 10
        }
    }

    /// Intended total length. The scene owns the real easing; these are
    /// the durations the art was posed for, not a new timing system.
    public var duration: TimeInterval {
        switch self {
        case .blink: return 0.30
        case .startled: return 0.55
        case .happyBounce: return 0.60
        case .excitedHop: return 1.10
        case .curiousLook: return 1.30
        case .dizzy: return 1.60
        case .sleepyYawn: return 1.80
        case .calmSettle: return 2.40
        }
    }

    /// Can fire spontaneously during idle. Happy Bounce is included —
    /// a small self-bounce is fine unprompted, and Ember/Glow's whole
    /// personality bias depends on it being reachable when idle.
    /// Excited Hop stays OUT: it is the celebration reaction, and
    /// letting it fire at random would spend its impact.
    public var isIdle: Bool {
        switch self {
        case .blink, .curiousLook, .sleepyYawn, .calmSettle,
             .happyBounce: return true
        case .dizzy, .startled, .excitedHop: return false
        }
    }

    /// Face shown at the reaction's peak. `nil` = keep the base
    /// expression (blink only changes the lids, so the Aurie's own
    /// expression stays on screen through it).
    public var overrideFace: String? {
        switch self {
        case .blink: return nil
        // Delighted's closed arcs, never the baked "dizzy" face — its
        // catchlight layer renders as a multi-pupil alien stare.
        case .dizzy: return BaseExpression.delighted.rawValue
        case .happyBounce: return BaseExpression.happy.rawValue
        case .startled: return BaseExpression.surprised.rawValue
        case .curiousLook: return BaseExpression.curious.rawValue
        case .sleepyYawn: return "yawn"
        case .calmSettle: return "calm"
        case .excitedHop: return BaseExpression.delighted.rawValue
        }
    }

    /// One temporary facial override at a time: a new reaction replaces
    /// the current one only if it is at least as important. Blink is the
    /// exception — it never displaces a reaction in progress.
    public func canInterrupt(_ current: AurieReaction?) -> Bool {
        guard let current else { return true }
        if self == .blink { return false }
        return priority >= current.priority
    }
}

// MARK: - Family personality weights

/// One table, one place. Preferred = 3, secondary = 2, everything else
/// = 1, normalised at selection time. Family BIASES personality; it
/// never restricts it, so every expression stays reachable for every
/// family.
public enum AuriePersonality {

    public static let preferredExpressions: [AuraFamily: [BaseExpression]] = [
        .stone: [.sleepy, .shy, .happy],
        .ember: [.excited, .mischievous, .delighted],
        .glow: [.delighted, .excited, .happy],
        .moss: [.shy, .curious, .happy],
        .tide: [.curious, .sleepy, .happy],
        .dusk: [.mischievous, .curious, .pouty],
        .starlight: [.delighted, .curious, .surprised],
    ]

    public static let secondaryExpressions: [AuraFamily: [BaseExpression]] = [
        .stone: [.worried, .curious],
        .ember: [.surprised, .happy],
        .glow: [.curious, .surprised],
        .moss: [.sleepy, .delighted],
        .tide: [.surprised, .shy],
        .dusk: [.shy, .sleepy],
        .starlight: [.happy, .excited],
    ]

    /// Idle reactions are biased the same way, reusing the same eight
    /// animations — no per-family animation assets.
    public static let preferredIdleReactions: [AuraFamily: [AurieReaction]] = [
        .stone: [.sleepyYawn, .calmSettle],
        .ember: [.happyBounce, .excitedHop],
        .glow: [.happyBounce, .excitedHop],
        .moss: [.curiousLook],
        .tide: [.curiousLook, .sleepyYawn],
        .dusk: [.curiousLook],
        .starlight: [.curiousLook, .excitedHop],
    ]

    public static let preferredWeight = 3
    public static let secondaryWeight = 2
    public static let baseWeight = 1

    public static func expressionWeights(
        for family: AuraFamily
    ) -> [(BaseExpression, Int)] {
        let pref = Set(preferredExpressions[family] ?? [])
        let sec = Set(secondaryExpressions[family] ?? [])
        return BaseExpression.allCases.map { expr in
            if pref.contains(expr) { return (expr, preferredWeight) }
            if sec.contains(expr) { return (expr, secondaryWeight) }
            return (expr, baseWeight)
        }
    }

    public static func idleReactionWeights(
        for family: AuraFamily
    ) -> [(AurieReaction, Int)] {
        let pref = Set(preferredIdleReactions[family] ?? [])
        return AurieReaction.allCases.filter(\.isIdle).map { reaction in
            (reaction, pref.contains(reaction) ? preferredWeight : baseWeight)
        }
    }

    /// Weighted pick. `roll` supplies a value in 0..<total so the caller
    /// decides the randomness source (seeded at hatch, or system RNG for
    /// idle behaviour).
    public static func pick<T>(_ weighted: [(T, Int)],
                               roll: (Int) -> Int) -> T {
        let total = weighted.reduce(0) { $0 + $1.1 }
        var cursor = roll(total)
        for (value, weight) in weighted {
            cursor -= weight
            if cursor < 0 { return value }
        }
        return weighted[weighted.count - 1].0
    }

    /// Base expression for a NEW Aurie. Deterministic in the hatch seed,
    /// so the same seed always rebuilds the same creature — and so an
    /// Aurie saved before this field existed still resolves to a stable
    /// expression instead of being rerolled on every launch.
    public static func baseExpression(family: AuraFamily,
                                      seed: UInt64) -> BaseExpression {
        var rng = SplitMix64(seed: seed ^ 0x9E37_79B9_7F4A_7C15)
        return pick(expressionWeights(for: family)) { total in
            Int(rng.next() % UInt64(total))
        }
    }

    public static func idleReaction(family: AuraFamily,
                                    roll: (Int) -> Int) -> AurieReaction {
        pick(idleReactionWeights(for: family), roll: roll)
    }

    /// Families listed as preferring Excited Hop may escalate a small
    /// positive event (a tap) into the big reaction now and then.
    /// Scripted celebrations — hatch reveal, Starlight, Today's Wonder —
    /// call `.excitedHop` directly and do not roll for it.
    public static func positiveReaction(family: AuraFamily,
                                        roll: (Int) -> Int) -> AurieReaction {
        let likesBig = (preferredIdleReactions[family] ?? [])
            .contains(.excitedHop)
        return pick([(AurieReaction.happyBounce, likesBig ? 2 : 5),
                     (AurieReaction.excitedHop, 1)], roll: roll)
    }
}

/// Tiny deterministic PRNG (SplitMix64) so seeded selection is stable
/// across launches and platforms.
public struct SplitMix64 {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Visible face resolution

/// What the face should show right now: the saved base expression,
/// unless a reaction is currently overriding it. Nothing here is
/// persisted — `Aurie.baseExpression` is the only saved value.
public struct VisibleFace {
    public let base: BaseExpression
    public private(set) var reaction: AurieReaction?

    public init(base: BaseExpression) { self.base = base }

    /// Returns true if the reaction was accepted.
    @discardableResult
    public mutating func begin(_ next: AurieReaction) -> Bool {
        guard next.canInterrupt(reaction) else { return false }
        reaction = next
        return true
    }

    /// Always returns to the saved base expression.
    public mutating func end() { reaction = nil }

    /// Face id for the renderer: a reaction face, or the base.
    public var faceId: String {
        reaction?.overrideFace ?? base.rawValue
    }
}
