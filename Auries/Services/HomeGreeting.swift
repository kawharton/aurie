import Foundation

/// The Aurie's Home greeting: ONE line per meaningful arrival, chosen from
/// the player's state rather than at random.
///
/// This file is deliberately pure — `Foundation` plus the `AuraFamily`
/// enum, no SwiftUI, no store — so the whole decision can be compiled and
/// exhaustively exercised by `Tools/greeting-tests` with a seeded RNG.
/// HomeView gathers a `GreetingContext` from the persisted settings, asks
/// `HomeGreetingEngine.choose`, shows the text in the existing speech bubble
/// and (for tutorials) pulses the control the line points at.
///
/// Three kinds of line live here:
///   • welcomes (first Aurie / long return / normal return)
///   • tutorials — each teaches ONE undiscovered feature and disappears for
///     good once that feature has been used
///   • personality — things the current Aurie wants to do; never expire
///
/// Tone rule, enforced by content not code: the Aurie is always glad to see
/// the player and never implies neglect or obligation.

// MARK: - Policy

/// Every tunable in one place. No magic numbers elsewhere.
enum GreetingPolicy {
    /// Calendar days away before a return counts as "long" (launch rule:
    /// 7 — no earlier product rule defined one).
    static let longReturnDays = 7
    /// Backgrounded for at least this long, then foregrounded, counts as a
    /// fresh arrival. Shorter trips (a text message, Control Center) do not.
    static let rearmAfterBackground: TimeInterval = 30 * 60
    /// The first N Home arrivals WITH a real Aurie are the "early" window
    /// where discovery prompts are weighted up.
    static let earlyVisitWindow = 6
    /// The very first Home visit with a real Aurie always teaches something.
    static let tutorialChanceFirstVisit = 1.0
    static let tutorialChanceEarly = 0.7
    static let tutorialChanceLate = 0.3
    /// When no tutorial is shown, how often a personality/play line replaces
    /// the plain return greeting.
    static let personalityChance = 0.4
    /// Playing with the current Aurie is the core loop, so the Toy Box
    /// outweighs the other undiscovered features while the window lasts.
    static let toyBoxEarlyWeight = 3
    /// How many times a pointed-at control pulses.
    static let blinkPulses = 3
}

// MARK: - Model

/// Features the Aurie can teach. Each one is removed from the tutorial pool
/// forever once the player has used it.
enum DiscoverableFeature: String, CaseIterable, Codable {
    case toyBox, calm, charms, shake

    /// Whether Home has a control the bubble can point at by pulsing it.
    /// Charms lives on the tab bar and Shake has no control at all, so
    /// neither can blink without redesigning a screen.
    var isBlinkable: Bool {
        switch self {
        case .toyBox, .calm: return true
        case .charms, .shake: return false
        }
    }
}

enum GreetingKind: Equatable {
    case firstAurie
    case longReturn
    case tutorial(DiscoverableFeature)
    case normalReturn
    case personality
}

struct HomeGreeting: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let kind: GreetingKind
    /// The control to pulse while the line shows, if any.
    var blink: DiscoverableFeature? {
        if case .tutorial(let f) = kind, f.isBlinkable { return f }
        return nil
    }
}

/// Everything the engine needs, read from persisted state by the caller.
struct GreetingContext {
    /// Persisted: at least one Aurie has ever hatched. Permanent.
    var hasHatchedFirstAurie: Bool
    /// A real creature is on Home right now (not the display-only greeter).
    var hasAurieNow: Bool
    var hasOpenedToyBox: Bool
    var hasOpenedCalm: Bool
    var hasOpenedCharmCollection: Bool
    var hasShakenPhone: Bool
    /// Account-level charms owned; `> 0` is "has discovered a charm".
    var ownedCharmCount: Int
    /// Whole calendar days since the previous meaningful arrival; nil on
    /// the first arrival ever.
    var daysSinceLastArrival: Int?
    /// Meaningful arrivals with a real Aurie BEFORE this one (0 = first).
    var homeArrivalCount: Int
    var family: AuraFamily?
    /// The creature's own permanent line — one more personality option.
    var aurieLine: String?
    /// The tutorial shown last time, so two-feature pools alternate rather
    /// than repeat. Not persisted; nil is fine.
    var avoidTutorial: DiscoverableFeature? = nil

    var hasDiscoveredAnyCharm: Bool { ownedCharmCount > 0 }

    /// Undiscovered features, in the order they are weighted.
    var undiscovered: [DiscoverableFeature] {
        var out: [DiscoverableFeature] = []
        if !hasOpenedToyBox { out.append(.toyBox) }
        if !hasOpenedCalm { out.append(.calm) }
        // Charms count as undiscovered until a charm has been found AND the
        // collection has been opened: two prompts, two different states.
        if !hasDiscoveredAnyCharm || !hasOpenedCharmCollection { out.append(.charms) }
        if !hasShakenPhone { out.append(.shake) }
        return out
    }
}

// MARK: - Lines

/// The dialogue pools. Kept as Swift rather than content JSON because each
/// pool is bound to a state rule above it; they can move to
/// `aurie_content.json` later without touching the engine.
enum GreetingLines {

    // Category 1 — no Aurie yet: lead into taking a photo.
    static let firstAurie = [
        "Let's look around. Your first Aurie could come from anywhere.",
        "Let's find something to turn into an Aurie!",
        "Everything has a little Aurie potential.",
        "What should we turn into an Aurie first?",
        "Find something you like. Let's see who it becomes.",
    ]

    // Category 3 — back after a long time: warm, never a guilt trip.
    static let longReturn = [
        "You're back! I'm so happy to see you!",
        "Welcome back! I'm happy you're here.",
        "There you are! It's nice to see you again.",
        "I'm glad you're here again.",
        "You're back! Want to see who we discover today?",
        "Yay! You're back!",
        "Hi! I'm really glad to see you.",
        "Welcome back! It's great to see you.",
        "I'm so happy you're back!",
    ]

    // Category 4 — an ordinary return.
    static let normalReturn = [
        "You're back! Want to see who we discover today?",
        "Hi! Want to make a new Aurie?",
        "You're here! Should we discover someone new today?",
        "I'm glad you're back. Want to explore together?",
        "Hi again! Let's see what we can find today.",
        "It's so nice to see you again. Let's discover someone new!",
        "Ready to explore?",
    ]

    // Category 5 — what the current Aurie feels like doing.
    static let personality = [
        "What should we do together today?",
        "I feel like doing something fun.",
        "Think you can kick the ball past me?",
        "I feel like playing ball!",
        "Maybe there's another Aurie waiting to be found.",
        "Play with me!",
    ]

    // Category 6 — Calm, until it has been opened once.
    static let calmTutorial = [
        "If you want to slow down for a little while, tap the Calm button.",
        "Need a quiet minute? Tap the Calm button. I can stay with you.",
    ]

    // Category 7 — Toy Box, until it has been opened once. The radio line
    // is the one family-specific line in this pass (see `radioLine`).
    static let toyBoxTutorial = [
        "Wanna play? Check out the Toy Box.",
        "Want to play? Open the Toy Box down there and pick something for us!",
    ]
    static let radioLine = "Let's dance! There's a radio in the Toy Box."
    static let radioLineStone = "I hate dancing. DO NOT turn on the radio in the Toy Box!"

    // Category 8A — no charm found yet. Never claims any have been found.
    static let charmsNoneFound = [
        "There are charms to discover. Think we can find one?",
        "I wonder what our first charm will be.",
        "Let's see if we can find a charm!",
    ]
    // Category 8B — has a charm, has never opened the collection.
    static let charmsCollectionUnopened = [
        "Want to see which charms we've found?",
    ]

    // Category 9 — charms understood; occasional play lines. Every line
    // presumes at least one charm is owned, which the eligibility rule
    // guarantees.
    static let charmsLater = [
        "Have you found any new charms lately?",
        "I wonder which charm would look good on me…",
        "Let's see what charms we've collected!",
        "Think we can find another charm today?",
        "Let's go charm hunting!",
        "I wonder what our next charm will be.",
    ]

    // Category 10 — shake, until the phone has been shaken once. The last
    // line is deliberate reverse psychology.
    static let shakeTutorial = [
        "Think you can make me dizzy?",
        "Try shaking your phone. I dare you.",
        "Psst… try giving your phone a little shake.",
        "Don't shake your phone. I get dizzy easily!",
    ]

    // Category 11 — after the first shake.
    static let shakeLater = [
        "I'm still recovering from the last shake.",
        "Bet you can't make me dizzy.",
    ]

    /// The one family-personality hook in this pass. Extend here (a
    /// per-family override of any pool) rather than sprinkling `family`
    /// checks through the engine.
    static func radioLine(for family: AuraFamily?) -> String {
        family == .stone ? radioLineStone : radioLine
    }
}

// MARK: - Engine

enum HomeGreetingEngine {

    /// Decide the ONE line for this arrival. Priority, top wins:
    ///   1. no Aurie (never hatched, or none on Home)  → first-Aurie pool
    ///   2. away ≥ `longReturnDays`                     → long-return pool
    ///   3. an undiscovered feature, by weighted chance → its tutorial
    ///   4. otherwise a normal return, or sometimes a personality line
    static func choose<R: RandomNumberGenerator>(_ c: GreetingContext,
                                                 using rng: inout R) -> HomeGreeting {
        // 1. Before the first Aurie exists — or with no creature on Home —
        //    every other pool would be talking to nobody.
        if !c.hasHatchedFirstAurie || !c.hasAurieNow {
            return HomeGreeting(text: pick(GreetingLines.firstAurie, &rng),
                                kind: .firstAurie)
        }

        // 2. Seeing the player again outranks teaching them anything today.
        if let days = c.daysSinceLastArrival, days >= GreetingPolicy.longReturnDays {
            return HomeGreeting(text: pick(GreetingLines.longReturn, &rng),
                                kind: .longReturn)
        }

        // 3. Tutorials: weighted up early, down later, never on a
        //    discovered feature, never every launch.
        let pool = c.undiscovered
        if !pool.isEmpty, Double.random(in: 0..<1, using: &rng) < tutorialChance(c) {
            let feature = pickFeature(from: pool, c, &rng)
            return HomeGreeting(text: tutorialLine(feature, c, &rng),
                                kind: .tutorial(feature))
        }

        // 4. A welcome, or — sometimes — something the Aurie wants to do.
        //    A first-ever arrival has nothing to "return" to, so it gets
        //    personality rather than "You're back!".
        let wantsPersonality = c.daysSinceLastArrival == nil
            || Double.random(in: 0..<1, using: &rng) < GreetingPolicy.personalityChance
        if wantsPersonality {
            return HomeGreeting(text: pick(personalityPool(c), &rng),
                                kind: .personality)
        }
        return HomeGreeting(text: pick(GreetingLines.normalReturn, &rng),
                            kind: .normalReturn)
    }

    // MARK: Pieces

    static func tutorialChance(_ c: GreetingContext) -> Double {
        if c.homeArrivalCount == 0 { return GreetingPolicy.tutorialChanceFirstVisit }
        if c.homeArrivalCount < GreetingPolicy.earlyVisitWindow {
            return GreetingPolicy.tutorialChanceEarly
        }
        return GreetingPolicy.tutorialChanceLate
    }

    /// Weighted pick over the undiscovered features. The Toy Box carries
    /// extra weight in the early window; the feature shown last time is
    /// skipped when there is any alternative, so two remaining tutorials
    /// alternate instead of one repeating.
    static func pickFeature<R: RandomNumberGenerator>(from pool: [DiscoverableFeature],
                                                      _ c: GreetingContext,
                                                      _ rng: inout R) -> DiscoverableFeature {
        var candidates = pool
        if candidates.count >= 2, let avoid = c.avoidTutorial {
            candidates.removeAll { $0 == avoid }
        }
        let early = c.homeArrivalCount < GreetingPolicy.earlyVisitWindow
        let weights = candidates.map { f -> Int in
            f == .toyBox && early ? GreetingPolicy.toyBoxEarlyWeight : 1
        }
        var roll = Int.random(in: 0 ..< weights.reduce(0, +), using: &rng)
        for (f, w) in zip(candidates, weights) {
            if roll < w { return f }
            roll -= w
        }
        return candidates[0]
    }

    static func tutorialLine<R: RandomNumberGenerator>(_ feature: DiscoverableFeature,
                                                       _ c: GreetingContext,
                                                       _ rng: inout R) -> String {
        switch feature {
        case .toyBox:
            return pick(GreetingLines.toyBoxTutorial + [GreetingLines.radioLine(for: c.family)], &rng)
        case .calm:
            return pick(GreetingLines.calmTutorial, &rng)
        case .charms:
            // 8A while nothing has been found; 8B once something has been
            // found but the collection is still unopened.
            return c.hasDiscoveredAnyCharm
                ? pick(GreetingLines.charmsCollectionUnopened, &rng)
                : pick(GreetingLines.charmsNoneFound, &rng)
        case .shake:
            return pick(GreetingLines.shakeTutorial, &rng)
        }
    }

    /// Category 5 plus the creature's own line, plus the later charm and
    /// shake pools once those are earned. Only lines that make sense for
    /// the current state are ever in here.
    static func personalityPool(_ c: GreetingContext) -> [String] {
        var pool = GreetingLines.personality
        if let line = c.aurieLine, !line.isEmpty { pool.append(line) }
        if c.hasDiscoveredAnyCharm && c.hasOpenedCharmCollection {
            pool += GreetingLines.charmsLater
        }
        if c.hasShakenPhone { pool += GreetingLines.shakeLater }
        return pool
    }

    private static func pick<R: RandomNumberGenerator>(_ lines: [String], _ rng: inout R) -> String {
        lines[Int.random(in: 0 ..< lines.count, using: &rng)]
    }
}
