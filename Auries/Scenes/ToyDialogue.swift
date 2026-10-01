import Foundation

/// Toy Box activity dialogue: what the Aurie says WHILE PLAYING with the
/// toy the player picked. This is separate from the Home greeting system —
/// a greeting may teach where the Toy Box is; once a toy is out, the Aurie
/// talks about playing and never about the UI.
///
/// Everything is organised by activity. The pools live here, keyed by the
/// thing being played with; the toys and the creature only report EVENTS.
/// `ToyDialogueDirector` turns events plus the clock into "say this now"
/// under one shared cooldown, so the toys never chatter. Foundation only,
/// so `Tools/toy-dialogue-tests` can exercise the policy headless.

/// The activities dialogue knows about. `PlayToy` maps onto this (see
/// `PlayToy.activity`); the radio is an activity too although it is not a
/// `PlayToy`. Star and Butterfly are not offered on the shelf today, so
/// they use the generic fallback pool.
enum ToyActivity: String, Equatable {
    case ball, bubbles, radio, star, butterfly
}

/// What the toys and the creature report. Coarse on purpose — nothing here
/// needs recognition the current toys don't already perform.
enum ToyEvent: Equatable {
    case selected(ToyActivity)      // shelf pick: the toy is out
    case deselected                 // the toy was put away
    case ballTossed(strong: Bool)   // the player flicked the ball
    case ballKicked(strong: Bool)   // the creature kicked/batted it; strong = sent down the field
    case ballRested                 // the ball rolled to a stop
    case bubblePopped(byAurie: Bool)
    case bubbleMissed               // reached for one and it drifted off
    case bubbleHigh                 // one is nearly at the top, still alive
    case bubbleEscaped              // drifted off the top unpopped
    case bubbleWatched              // the creature watched one float by
    case radioOn                    // music started
    case radioTrackChanged
    case radioOff                   // paused or put away
    case danceStarted               // a real dance move began (never Stone)
    case stoneRefused               // Stone: "not dancing"
    case stoneGaveIn                // Stone: the foot started tapping
    case stoneCaught                // Stone: touched while tapping
}

/// A line the director wants voiced. `isStart` marks the one line that is
/// retried (not dropped) when the host cannot show it.
struct ToyLine: Equatable {
    let text: String
    let isStart: Bool
}

/// Frequency rules. One line shortly after a pick, then quiet, then the
/// occasional line — the Aurie plays first and talks second.
enum ToySpeechPolicy {
    /// The first line comes shortly after the pick, once the toy is on screen.
    static let startDelay: TimeInterval = 1.1
    /// A start line the host could not show (another bubble was up) is
    /// retried after this.
    static let startRetry: TimeInterval = 2.0
    /// A start line never lands closer than this to the previous line.
    static let startMinGap: TimeInterval = 3.0
    /// Hard quiet period after any toy line.
    static let cooldown: TimeInterval = 12
    /// Chance an eligible in-play event produces a line.
    static let eventChance = 0.45
    /// Stone's refusals are the joke, so they land more often.
    static let stoneEventChance = 0.8
    /// Continued play with nothing said for this long earns one ambient line.
    static let ambientInterval: ClosedRange<TimeInterval> = 24 ... 40
    /// A resting ball nobody has touched for this long: "Kick it over here!"
    static let ballWaitingAfter: TimeInterval = 7
    /// Recent lines avoided when choosing the next one.
    static let noRepeatWindow = 3
}

// MARK: - Pools

/// The dialogue, per activity. Kept as Swift next to the rules that use
/// them (like `GreetingLines`); they can move to content JSON later
/// without touching the director.
enum ToyDialogue {
    struct Ball {
        let start: [String]
        let waiting: [String]     // the ball has sat still for a while
        let yourToss: [String]    // the player flicked it
        let yourBigToss: [String] // …hard
        let myKick: [String]      // the Aurie kicked or batted it
        let myBigKick: [String]   // …down the field
        let during: [String]      // continued play
    }
    static let ball = Ball(
        start: ["Yay! Let's play ball!",
                "I love playing ball with you!",
                "Okay, I'm ready!",
                "Kick it over here!"],
        waiting: ["Kick it over here!",
                  "Think you can get it past me?",
                  "Okay, I'm ready!"],
        yourToss: ["Again! Again!",
                   "Think you can get it past me?",
                   "I love playing ball with you!"],
        yourBigToss: ["That was a good one!",
                      "Let's see how far it goes!"],
        myKick: ["My turn!",
                 "Again! Again!"],
        myBigKick: ["Let's see how far it goes!",
                    "My turn!"],
        during: ["Again! Again!",
                 "I love playing ball with you!",
                 "Think you can get it past me?",
                 "Kick it over here!"])

    struct Bubbles {
        let start: [String]
        let popByAurie: [String]
        let popByPlayer: [String]
        let miss: [String]
        let high: [String]        // one is nearly at the top, still alive
        let escaped: [String]     // it drifted off unpopped
        let watched: [String]     // one floated by, close
        let during: [String]
    }
    static let bubbles = Bubbles(
        start: ["Bubbles!",
                "Look at all of them!",
                "I want to pop one!"],
        popByAurie: ["Pop!",
                     "I got it!",
                     "Did you see that one?"],
        popByPlayer: ["Pop!",
                      "Did you see that one?",
                      "Again! More bubbles!"],
        miss: ["I almost got it!"],
        high: ["Catch it before it floats away!",
               "Don't let that one get away!"],
        escaped: ["Whoa, that one went high!"],
        watched: ["Look at all of them!",
                  "So many bubbles!"],
        during: ["I want to pop one!",
                 "Pop that one!",
                 "Again! More bubbles!",
                 "Look at all of them!"])

    struct Radio {
        let start: [String]
        let trackChanged: [String]
        let dancing: [String]     // a dance move just began
        let during: [String]
    }
    /// Every family except Stone.
    static let radio = Radio(
        start: ["Yay! Let's dance!",
                "Dance with me!",
                "Come on! Dance with me!",
                "I love this song!"],
        trackChanged: ["I love this song!",
                       "Turn it up!",
                       "This is my favorite part!"],
        dancing: ["Look at my moves!",
                  "This is my favorite part!",
                  "I could dance all day!",
                  "Turn it up!"],
        during: ["Dance with me!",
                 "Come on! Dance with me!",
                 "I could dance all day!",
                 "Look at my moves!",
                 "I love this song!"])

    struct RadioStone {
        let start: [String]
        let refusal: [String]
        let givingIn: [String]    // the foot starts tapping
        let caught: [String]      // touched mid-tap
        let trackChanged: [String]
        let during: [String]
    }
    /// Stone claims to hate dancing and never gets the cheerful pool.
    static let radioStone = RadioStone(
        start: ["I told you not to turn that on.",
                "Really? We're dancing now?"],
        refusal: ["I am NOT dancing.",
                  "Me? Dance? No way.",
                  "Absolutely not.",
                  "Eww. Dancing.",
                  "Nope.",
                  "Not happening.",
                  "I'm good."],
        givingIn: ["...Fine. Maybe one song.",
                   "Don't tell anyone I'm having fun."],
        caught: ["That was not a dance move! I was just tapping my foot.",
                 "I was not dancing!",
                 "You saw nothing."],
        trackChanged: ["Really? We're dancing now?",
                       "I told you not to turn that on."],
        during: ["I am NOT dancing.",
                 "Really? We're dancing now?",
                 "Not happening."])

    /// Only for an activity with no pool of its own (Star and Butterfly are
    /// not on the shelf today). A dedicated pool always wins.
    static let fallback = ["Yay! Let's play!",
                           "This is fun!",
                           "Let's do that again!",
                           "I like playing with you.",
                           "What should we try next?"]
}

// MARK: - Director

/// Turns toy events and the clock into lines, under one cooldown. Pure
/// state, no timers, no scene: the host calls `handle` on events and
/// `tick` once per frame, shows what comes back if it can, and reports a
/// refusal so a start line is retried rather than lost.
struct ToyDialogueDirector {
    var family: AuraFamily?

    /// The activity that owns the start line and the ambient chatter: the
    /// most recently started one (a ball and the radio can both be out).
    private(set) var activity: ToyActivity?
    private var toyOut: ToyActivity?
    private var radioPlaying = false

    private var startDueAt: TimeInterval?
    private var quietUntil: TimeInterval = 0
    private var ambientDueAt: TimeInterval = .infinity
    private var ballRestedAt: TimeInterval?
    private var lastLineAt: TimeInterval = -.infinity
    private var recent: [String] = []
    /// Restored on a refusal, so a missed moment costs nothing.
    private var beforeLast: (quiet: TimeInterval, ambient: TimeInterval, lastAt: TimeInterval)?

    init(family: AuraFamily?) { self.family = family }

    private var isStone: Bool { family == .stone }

    /// An event happened. Returns a line to voice now, or nil.
    mutating func handle<R: RandomNumberGenerator>(_ event: ToyEvent, now: TimeInterval,
                                                   using rng: inout R) -> ToyLine? {
        let P = ToySpeechPolicy.self
        let D = ToyDialogue.self
        switch event {
        case .selected(let a):
            toyOut = a
            begin(a, now: now)
            return nil
        case .deselected:
            toyOut = nil
            end()
            return nil
        case .radioOn:
            radioPlaying = true
            begin(.radio, now: now)
            return nil
        case .radioOff:
            radioPlaying = false
            end()
            return nil
        case .ballRested:
            if toyOut == .ball { ballRestedAt = now }
            return nil
        case .ballTossed(let strong):
            guard toyOut == .ball else { return nil }
            ballRestedAt = nil
            return speak(from: strong ? D.ball.yourBigToss : D.ball.yourToss,
                         chance: strong ? P.eventChance + 0.2 : P.eventChance,
                         now: now, using: &rng)
        case .ballKicked(let strong):
            guard toyOut == .ball else { return nil }
            ballRestedAt = nil
            return speak(from: strong ? D.ball.myBigKick : D.ball.myKick,
                         chance: P.eventChance, now: now, using: &rng)
        case .bubblePopped(let byAurie):
            guard toyOut == .bubbles else { return nil }
            return speak(from: byAurie ? D.bubbles.popByAurie : D.bubbles.popByPlayer,
                         chance: P.eventChance, now: now, using: &rng)
        case .bubbleMissed:
            guard toyOut == .bubbles else { return nil }
            return speak(from: D.bubbles.miss, chance: P.eventChance, now: now, using: &rng)
        case .bubbleHigh:
            guard toyOut == .bubbles else { return nil }
            return speak(from: D.bubbles.high, chance: P.eventChance, now: now, using: &rng)
        case .bubbleEscaped:
            guard toyOut == .bubbles else { return nil }
            return speak(from: D.bubbles.escaped, chance: P.eventChance, now: now, using: &rng)
        case .bubbleWatched:
            guard toyOut == .bubbles else { return nil }
            return speak(from: D.bubbles.watched, chance: P.eventChance, now: now, using: &rng)
        case .radioTrackChanged:
            guard radioPlaying else { return nil }
            return speak(from: isStone ? D.radioStone.trackChanged : D.radio.trackChanged,
                         chance: P.eventChance, now: now, using: &rng)
        case .danceStarted:
            guard radioPlaying, !isStone else { return nil }
            return speak(from: D.radio.dancing, chance: P.eventChance, now: now, using: &rng)
        case .stoneRefused:
            guard radioPlaying, isStone else { return nil }
            return speak(from: D.radioStone.refusal, chance: P.stoneEventChance, now: now, using: &rng)
        case .stoneGaveIn:
            guard radioPlaying, isStone else { return nil }
            return speak(from: D.radioStone.givingIn, chance: P.stoneEventChance, now: now, using: &rng)
        case .stoneCaught:
            guard isStone else { return nil }
            // A direct answer to the player's touch: never rolled away, and
            // allowed inside the cooldown (the host still refuses overlap).
            return speak(from: D.radioStone.caught, chance: 1, now: now,
                         ignoringCooldown: true, using: &rng)
        }
    }

    /// Once per frame. Fires the delayed start line, the ball's waiting
    /// line, and the occasional ambient line.
    mutating func tick<R: RandomNumberGenerator>(now: TimeInterval, using rng: inout R) -> ToyLine? {
        if let due = startDueAt, now >= due {
            guard now - lastLineAt >= ToySpeechPolicy.startMinGap else {
                startDueAt = now + ToySpeechPolicy.startRetry
                return nil
            }
            startDueAt = nil
            guard let activity else { return nil }
            return speak(from: startPool(activity), chance: 1, now: now,
                         isStart: true, ignoringCooldown: true, using: &rng)
        }
        if startDueAt == nil, let restedAt = ballRestedAt, toyOut == .ball,
           now - restedAt >= ToySpeechPolicy.ballWaitingAfter {
            ballRestedAt = nil
            return speak(from: ToyDialogue.ball.waiting, chance: 0.7, now: now, using: &rng)
        }
        if let activity, now >= ambientDueAt {
            ambientDueAt = now + .random(in: ToySpeechPolicy.ambientInterval, using: &rng)
            return speak(from: ambientPool(activity), chance: 1, now: now, using: &rng)
        }
        return nil
    }

    /// The host could not show the line (another bubble was up, or speech
    /// is suppressed). A start line is retried shortly; anything else is
    /// dropped and the cooldown it would have started is lifted.
    mutating func refused(_ line: ToyLine, now: TimeInterval) {
        if let b = beforeLast {
            quietUntil = b.quiet
            ambientDueAt = b.ambient
            lastLineAt = b.lastAt
            beforeLast = nil
        }
        if let i = recent.lastIndex(of: line.text) { recent.remove(at: i) }
        if line.isStart { startDueAt = now + ToySpeechPolicy.startRetry }
    }

    // MARK: Internals

    private mutating func begin(_ a: ToyActivity, now: TimeInterval) {
        activity = a
        startDueAt = now + ToySpeechPolicy.startDelay
        ambientDueAt = .infinity
        if a == .ball { ballRestedAt = nil }
    }

    /// Whatever is still out carries on; the start line of a thing that
    /// was put away before it spoke is dropped.
    private mutating func end() {
        let remaining: ToyActivity? = toyOut ?? (radioPlaying ? .radio : nil)
        if remaining == nil || remaining != activity { startDueAt = nil }
        activity = remaining
        if activity == nil { ambientDueAt = .infinity }
        if toyOut != .ball { ballRestedAt = nil }
    }

    private mutating func speak<R: RandomNumberGenerator>(from pool: [String], chance: Double,
                                                          now: TimeInterval, isStart: Bool = false,
                                                          ignoringCooldown: Bool = false,
                                                          using rng: inout R) -> ToyLine? {
        guard !pool.isEmpty else { return nil }
        // The start line is always the first thing said about a new toy:
        // while it is pending, in-play events stay silent (Stone caught
        // mid-tap is the one direct answer that may not wait).
        if startDueAt != nil, !isStart, !ignoringCooldown { return nil }
        guard ignoringCooldown || now >= quietUntil else { return nil }
        if chance < 1, Double.random(in: 0 ..< 1, using: &rng) >= chance { return nil }
        let fresh = pool.filter { !recent.contains($0) }
        let choices = fresh.isEmpty ? pool : fresh
        let text = choices[Int.random(in: 0 ..< choices.count, using: &rng)]
        beforeLast = (quietUntil, ambientDueAt, lastLineAt)
        quietUntil = now + ToySpeechPolicy.cooldown
        ambientDueAt = now + .random(in: ToySpeechPolicy.ambientInterval, using: &rng)
        lastLineAt = now
        recent.append(text)
        if recent.count > ToySpeechPolicy.noRepeatWindow { recent.removeFirst() }
        return ToyLine(text: text, isStart: isStart)
    }

    private func startPool(_ a: ToyActivity) -> [String] {
        switch a {
        case .ball:    return ToyDialogue.ball.start
        case .bubbles: return ToyDialogue.bubbles.start
        case .radio:   return isStone ? ToyDialogue.radioStone.start : ToyDialogue.radio.start
        case .star, .butterfly: return ToyDialogue.fallback
        }
    }

    private func ambientPool(_ a: ToyActivity) -> [String] {
        switch a {
        case .ball:    return ToyDialogue.ball.during
        case .bubbles: return ToyDialogue.bubbles.during
        case .radio:   return isStone ? ToyDialogue.radioStone.during : ToyDialogue.radio.during
        case .star, .butterfly: return ToyDialogue.fallback
        }
    }
}
