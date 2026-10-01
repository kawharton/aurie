import Foundation

// The Toy Box dialogue rules, each run across SEEDS different rolls on a
// simulated 30 fps clock — the director is random by design, so a single
// roll proves nothing.
let SEEDS = 300
var pass = 0, fail = 0
func check(_ name: String, _ ok: Bool) {
    if ok { pass += 1 } else { fail += 1; print("FAIL \(name)") }
}
func seeded(_ i: Int) -> SeededGenerator {
    SeededGenerator(seed: UInt64(i &+ 1) &* 0x9E3779B97F4A7C15)
}

let D = ToyDialogue.self
let P = ToySpeechPolicy.self
let allStone = Set(D.radioStone.start + D.radioStone.refusal + D.radioStone.givingIn
                   + D.radioStone.caught + D.radioStone.trackChanged + D.radioStone.during)
let allRadio = Set(D.radio.start + D.radio.trackChanged + D.radio.dancing + D.radio.during)
let allBall = Set(D.ball.start + D.ball.waiting + D.ball.yourToss + D.ball.yourBigToss
                  + D.ball.myKick + D.ball.myBigKick + D.ball.during)
let allBubbles = Set(D.bubbles.start + D.bubbles.popByAurie + D.bubbles.popByPlayer + D.bubbles.miss
                     + D.bubbles.high + D.bubbles.escaped + D.bubbles.watched + D.bubbles.during)
let fallback = Set(D.fallback)

/// A simulated play session: scripted (time, event) pairs on a frame clock;
/// every line the director produces is recorded with its time. The host can
/// be told to refuse lines for a while (another bubble is up).
struct Session {
    var director: ToyDialogueDirector
    var rng: SeededGenerator
    var lines: [(t: TimeInterval, line: ToyLine)] = []
    var refuseUntil: TimeInterval = -1
    var now: TimeInterval = 0
    init(_ family: AuraFamily?, seed: Int) {
        director = ToyDialogueDirector(family: family)
        rng = seeded(seed)
    }
    mutating func event(_ e: ToyEvent) {
        if let l = director.handle(e, now: now, using: &rng) { deliver(l) }
    }
    mutating func deliver(_ l: ToyLine) {
        if now < refuseUntil { director.refused(l, now: now) } else { lines.append((now, l)) }
    }
    mutating func run(until end: TimeInterval, events: [(TimeInterval, ToyEvent)] = []) {
        var pending = events.sorted { $0.0 < $1.0 }
        let step = 1.0 / 30
        while now < end - 1e-9 {
            now += step
            while let first = pending.first, first.0 <= now + 1e-9 {
                pending.removeFirst(); event(first.1)
            }
            if let l = director.tick(now: now, using: &rng) { deliver(l) }
        }
    }
    var texts: [String] { lines.map(\.line.text) }
}
func every(_ f: (Int) -> Bool) -> Bool { (0 ..< SEEDS).allSatisfy(f) }
func union(_ f: (Int) -> [String]) -> Set<String> { Set((0 ..< SEEDS).flatMap(f)) }
func near(_ t: TimeInterval, _ target: TimeInterval, tol: TimeInterval = 0.08) -> Bool { abs(t - target) <= tol }

// 0. Pool hygiene: every pool non-empty; activities never share lines with
//    each other, and Stone's radio pools never overlap the cheerful ones.
check("0 pools non-empty", ![D.ball.start, D.ball.waiting, D.ball.yourToss, D.ball.yourBigToss, D.ball.myKick, D.ball.myBigKick, D.ball.during,
    D.bubbles.start, D.bubbles.popByAurie, D.bubbles.popByPlayer, D.bubbles.miss, D.bubbles.high,
    D.bubbles.escaped, D.bubbles.watched, D.bubbles.during, D.radio.start, D.radio.trackChanged,
    D.radio.dancing, D.radio.during, D.radioStone.start, D.radioStone.refusal, D.radioStone.givingIn,
    D.radioStone.caught, D.radioStone.trackChanged, D.radioStone.during, D.fallback].contains { $0.isEmpty })
check("0 ball/bubbles disjoint", allBall.isDisjoint(with: allBubbles))
check("0 stone/cheerful radio disjoint", allStone.isDisjoint(with: allRadio))
check("0 fallback disjoint from every dedicated pool",
      fallback.isDisjoint(with: allBall.union(allBubbles).union(allRadio).union(allStone)))
check("0 every pool has ~5-8+ lines per activity",
      allBall.count >= 5 && allBubbles.count >= 5 && allRadio.count >= 5 && allStone.count >= 5)

// 1. One start line shortly after the pick, from that toy's own pool.
func startCheck(_ name: String, _ family: AuraFamily?, _ e: ToyEvent, _ pool: Set<String>) {
    check("1 \(name): exactly one line in 5 s, at +\(P.startDelay)s, marked start, from own pool",
          every { i in
        var s = Session(family, seed: i); s.event(e); s.run(until: 5)
        return s.lines.count == 1 && s.lines[0].line.isStart && near(s.lines[0].t, P.startDelay)
            && pool.contains(s.lines[0].line.text)
    })
    check("1 \(name): the whole start pool is reachable",
          union { i in var s = Session(family, seed: i); s.event(e); s.run(until: 5); return s.texts }.count >= 2)
}
startCheck("ball", .tide, .selected(.ball), Set(D.ball.start))
startCheck("bubbles", .moss, .selected(.bubbles), Set(D.bubbles.start))
startCheck("radio non-Stone", .ember, .radioOn, Set(D.radio.start))
startCheck("radio Stone", .stone, .radioOn, Set(D.radioStone.start))
startCheck("star -> fallback", .tide, .selected(.star), fallback)
startCheck("butterfly -> fallback", .tide, .selected(.butterfly), fallback)

// 2. Cooldown: nothing for 12 s after a line however many events arrive;
//    afterwards a strong kick can speak, from the strong-kick pool only.
check("2 cooldown: kicks every 0.5 s for 12 s after the start line say nothing", every { i in
    var s = Session(.tide, seed: i); s.event(.selected(.ball))
    let kicks = stride(from: 2.0, through: 12.9, by: 0.5).map { ($0, ToyEvent.ballKicked(strong: true)) }
    s.run(until: 13.0, events: kicks)
    return s.lines.count == 1
})
check("2 cooldown: after 12 s a strong kick speaks (some seeds), only strong-kick lines, never before +12 s", {
    var any = false, ok = true
    for i in 0 ..< SEEDS {
        var s = Session(.tide, seed: i); s.event(.selected(.ball))
        let kicks = stride(from: 2.0, through: 24.0, by: 0.5).map { ($0, ToyEvent.ballKicked(strong: true)) }
        s.run(until: 24.5, events: kicks)
        let extra = s.lines.dropFirst()
        if !extra.isEmpty { any = true }
        ok = ok && extra.allSatisfy { D.ball.myBigKick.contains($0.line.text) && $0.t >= P.startDelay + P.cooldown - 1e-6 }
        if let first = extra.first, let second = extra.dropFirst().first { ok = ok && second.t - first.t >= P.cooldown - 1e-6 }
    }
    return any && ok
}())

// 3. Ambient: with a toy out and nothing happening, one line every 24–40 s,
//    never closer, from the rally pool, no two in a row alike.
check("3 ambient: gaps within 24–40 s, 7–13 lines in 5 min, rally pool, no immediate repeats", every { i in
    var s = Session(.tide, seed: i); s.event(.selected(.ball)); s.run(until: 300)
    let ts = s.lines.map(\.t)
    let gaps = zip(ts.dropFirst(), ts).map { $0 - $1 }
    let gapsOK = gaps.allSatisfy { $0 >= P.ambientInterval.lowerBound - 0.05 && $0 <= P.ambientInterval.upperBound + 0.05 }
    let poolOK = s.lines.dropFirst().allSatisfy { D.ball.during.contains($0.line.text) }
    let noRepeat = zip(s.texts.dropFirst(), s.texts).allSatisfy { $0 != $1 }
    return gapsOK && poolOK && noRepeat && (7 ... 13).contains(s.lines.count)
})

// 4. Heavy play never spams: a pop every 0.7 s for 5 minutes stays under
//    the cooldown bound, and only bubble lines are ever used.
check("4 heavy bubble play: ≤ 27 lines in 5 min, ≥ 8, all bubble lines", every { i in
    var s = Session(.dusk, seed: i); s.event(.selected(.bubbles))
    var ev = stride(from: 2.0, through: 300, by: 0.7).map { ($0, ToyEvent.bubblePopped(byAurie: true)) }
    ev += stride(from: 5.0, through: 300, by: 5).map { ($0, ToyEvent.bubbleHigh) }
    s.run(until: 300, events: ev)
    let ts = s.lines.map(\.t)
    let spaced = zip(ts.dropFirst(), ts).allSatisfy { $0 - $1 >= P.cooldown - 1e-6 }
    return spaced && s.lines.count <= 27 && s.lines.count >= 8 && s.texts.allSatisfy { allBubbles.contains($0) }
})

// 5. Contextual pools: each event speaks from its own pool.
func onlyFrom(_ family: AuraFamily, _ open: ToyEvent, _ e: ToyEvent, _ pool: [String]) -> Bool {
    var seen = Set<String>(), ok = true
    for i in 0 ..< SEEDS {
        var s = Session(family, seed: i); s.event(open); s.run(until: 14)
        let before = s.lines.count
        s.event(e)
        let new = s.lines.dropFirst(before)
        ok = ok && new.allSatisfy { pool.contains($0.line.text) }
        new.forEach { seen.insert($0.line.text) }
    }
    return ok && !seen.isEmpty && seen.isSubset(of: Set(pool))
}
check("5 strong toss -> yourBigToss", onlyFrom(.tide, .selected(.ball), .ballTossed(strong: true), D.ball.yourBigToss))
check("5 weak toss -> yourToss", onlyFrom(.tide, .selected(.ball), .ballTossed(strong: false), D.ball.yourToss))
check("5 creature kick -> myKick", onlyFrom(.tide, .selected(.ball), .ballKicked(strong: false), D.ball.myKick))
check("5 creature field kick -> myBigKick", onlyFrom(.tide, .selected(.ball), .ballKicked(strong: true), D.ball.myBigKick))
check("5 Aurie pop -> popByAurie", onlyFrom(.tide, .selected(.bubbles), .bubblePopped(byAurie: true), D.bubbles.popByAurie))
check("5 player pop -> popByPlayer", onlyFrom(.tide, .selected(.bubbles), .bubblePopped(byAurie: false), D.bubbles.popByPlayer))
check("5 miss -> miss", onlyFrom(.tide, .selected(.bubbles), .bubbleMissed, D.bubbles.miss))
check("5 high -> high", onlyFrom(.tide, .selected(.bubbles), .bubbleHigh, D.bubbles.high))
check("5 escaped -> escaped", onlyFrom(.tide, .selected(.bubbles), .bubbleEscaped, D.bubbles.escaped))
check("5 watched -> watched", onlyFrom(.tide, .selected(.bubbles), .bubbleWatched, D.bubbles.watched))
check("5 dance started -> dancing (non-Stone)", onlyFrom(.glow, .radioOn, .danceStarted, D.radio.dancing))
check("5 track changed -> trackChanged (non-Stone)", onlyFrom(.glow, .radioOn, .radioTrackChanged, D.radio.trackChanged))
check("5 Stone refused -> refusal", onlyFrom(.stone, .radioOn, .stoneRefused, D.radioStone.refusal))
check("5 Stone gave in -> givingIn", onlyFrom(.stone, .radioOn, .stoneGaveIn, D.radioStone.givingIn))
check("5 Stone caught -> caught", onlyFrom(.stone, .radioOn, .stoneCaught, D.radioStone.caught))
check("5 Stone track changed -> Stone trackChanged", onlyFrom(.stone, .radioOn, .radioTrackChanged, D.radioStone.trackChanged))

// 6. Stone vs everyone else: a full radio session never crosses pools, and
//    the events that belong to the other side are silent.
let radioScript: [(TimeInterval, ToyEvent)] = [(0, .radioOn), (3, .stoneRefused), (16, .danceStarted), (17, .stoneGaveIn),
    (30, .radioTrackChanged), (31, .stoneCaught), (45, .danceStarted), (58, .stoneRefused), (72, .stoneGaveIn),
    (86, .radioTrackChanged), (100, .danceStarted), (114, .stoneCaught), (130, .danceStarted), (145, .stoneRefused)]
check("6 Stone: every line from the Stone pools, never a cheerful one", every { i in
    var s = Session(.stone, seed: i); s.run(until: 160, events: radioScript)
    return !s.lines.isEmpty && s.texts.allSatisfy { allStone.contains($0) && !allRadio.contains($0) }
})
check("6 Stone: never says 'Yay! Let's dance!' or any dancing line", union { i in
    var s = Session(.stone, seed: i); s.run(until: 160, events: radioScript); return s.texts
}.isDisjoint(with: allRadio))
for fam in AuraFamily.allCases where fam != .stone {
    check("6 \(fam.rawValue): every line cheerful, never a Stone line", every { i in
        var s = Session(fam, seed: i); s.run(until: 160, events: radioScript)
        return !s.lines.isEmpty && s.texts.allSatisfy { allRadio.contains($0) && !allStone.contains($0) }
    })
}
check("6 non-Stone: refusal/gave-in/caught events are silent", every { i in
    var s = Session(.tide, seed: i); s.run(until: 2)
    s.event(.radioOn); s.run(until: 14)
    let n = s.lines.count
    s.event(.stoneRefused); s.event(.stoneGaveIn); s.event(.stoneCaught)
    return s.lines.count == n
})
check("6 Stone: a dance-started event is silent", every { i in
    var s = Session(.stone, seed: i); s.event(.radioOn); s.run(until: 14)
    let n = s.lines.count; s.event(.danceStarted); return s.lines.count == n
})

// 7. Events for a toy that is not out say nothing; no toy, no talk.
check("7 bubble events while the ball is out are silent", every { i in
    var s = Session(.tide, seed: i); s.event(.selected(.ball)); s.run(until: 14)
    let n = s.lines.count
    for e in [ToyEvent.bubblePopped(byAurie: true), .bubbleHigh, .bubbleEscaped, .bubbleMissed, .bubbleWatched] { s.event(e) }
    return s.lines.count == n
})
check("7 ball events while bubbles are out are silent", every { i in
    var s = Session(.tide, seed: i); s.event(.selected(.bubbles)); s.run(until: 14)
    let n = s.lines.count
    for e in [ToyEvent.ballTossed(strong: true), .ballKicked(strong: true), .ballRested] { s.event(e) }
    s.run(until: 40); return s.lines.count == n || s.lines.dropFirst(n).allSatisfy { D.bubbles.during.contains($0.line.text) }
})
check("7 nothing selected: every event is silent for 2 minutes", every { i in
    var s = Session(.tide, seed: i)
    let ev: [(TimeInterval, ToyEvent)] = [(1, .ballKicked(strong: true)), (2, .bubblePopped(byAurie: true)), (3, .danceStarted),
                                          (4, .stoneRefused), (5, .radioTrackChanged), (6, .bubbleHigh)]
    s.run(until: 120, events: ev); return s.lines.isEmpty
})

// 8. Ball waiting: a ball that sits still for 7 s (outside the cooldown)
//    earns "Kick it over here!"-type lines; a toss before then cancels it.
check("8 waiting: nothing before +7 s of rest; then a waiting line for most seeds", {
    var got = 0, ok = true
    for i in 0 ..< SEEDS {
        var s = Session(.tide, seed: i); s.event(.selected(.ball)); s.run(until: 14)
        s.event(.ballRested); s.run(until: 20.9)
        ok = ok && s.lines.count == 1
        s.run(until: 22)
        if s.lines.count == 2 { got += 1; ok = ok && D.ball.waiting.contains(s.lines[1].line.text) && near(s.lines[1].t, 21) }
    }
    return ok && got > SEEDS / 2 && got < SEEDS
}())
check("8 waiting cancelled by a toss at +4 s of rest", every { i in
    var s = Session(.tide, seed: i); s.event(.selected(.ball)); s.run(until: 14)
    s.event(.ballRested); s.run(until: 18); s.event(.ballTossed(strong: false))
    let n = s.lines.count
    s.run(until: 24.9)
    return s.lines.count == n   // no waiting line at 21; the ambient is not due before 25.1
})

// 9. Put away / switched: a toy put away before it spoke never speaks; a
//    quick switch speaks once, for the new toy.
check("9 deselected at 0.5 s: silent forever", every { i in
    var s = Session(.tide, seed: i); s.event(.selected(.bubbles)); s.run(until: 0.5); s.event(.deselected)
    s.run(until: 60); return s.lines.isEmpty
})
check("9 ball then bubbles at 0.5 s: one start line, bubbles, at 1.6 s", every { i in
    var s = Session(.tide, seed: i); s.event(.selected(.ball)); s.run(until: 0.5); s.event(.selected(.bubbles))
    s.run(until: 6)
    return s.lines.count == 1 && D.bubbles.start.contains(s.lines[0].line.text) && near(s.lines[0].t, 1.6)
})
check("9 radio off: ambient stops", every { i in
    var s = Session(.tide, seed: i); s.event(.radioOn); s.run(until: 5); s.event(.radioOff); s.run(until: 120)
    return s.lines.count == 1
})

// 10. Refusal: a start line the host cannot show is retried, not lost;
//     a refused event line lifts the cooldown it would have started.
check("10 refused start retried 2 s later, exactly once, still a start line", every { i in
    var s = Session(.tide, seed: i); s.refuseUntil = 3.0; s.event(.selected(.ball)); s.run(until: 8)
    return s.lines.count == 1 && s.lines[0].line.isStart && s.lines[0].t >= 3.1 - 1e-6 && s.lines[0].t <= 3.25
        && D.ball.start.contains(s.lines[0].line.text)
})
check("10 refused event line does not start a cooldown", {
    var spoke = 0
    for i in 0 ..< SEEDS {
        var s = Session(.tide, seed: i); s.event(.selected(.ball)); s.run(until: 16)
        s.refuseUntil = 17; s.event(.ballTossed(strong: true))     // refused if it rolled a line
        s.run(until: 17.5); s.refuseUntil = -1
        let n = s.lines.count
        s.event(.ballTossed(strong: true)); s.event(.ballTossed(strong: true)); s.event(.ballTossed(strong: true))
        if s.lines.count > n { spoke += 1 }
    }
    return spoke > SEEDS / 2
}())

// 11. Ball and radio together: each gets its start line (never closer than
//     3 s to the previous line); when the radio stops, ambient returns to the ball.
check("11 ball then radio at 10 s: two start lines, own pools, ambient after radio-off from ball", every { i in
    var s = Session(.tide, seed: i); s.event(.selected(.ball))
    s.run(until: 200, events: [(10, .radioOn), (30, .radioOff)])
    let starts = s.lines.filter { $0.line.isStart }
    let afterOff = s.lines.filter { $0.t > 30 }
    return starts.count == 2 && D.ball.start.contains(starts[0].line.text) && near(starts[0].t, 1.1)
        && D.radio.start.contains(starts[1].line.text) && near(starts[1].t, 11.1)
        && !afterOff.isEmpty && afterOff.allSatisfy { D.ball.during.contains($0.line.text) }
})
check("11 radio 1.5 s after the ball: its start waits for the 3 s gap (lands ~4.6 s)", every { i in
    var s = Session(.tide, seed: i); s.event(.selected(.ball))
    s.run(until: 8, events: [(1.5, .radioOn)])
    return s.lines.count == 2 && near(s.lines[0].t, 1.1) && s.lines[1].t >= 4.6 - 1e-6 && s.lines[1].t <= 4.75
        && D.radio.start.contains(s.lines[1].line.text) && s.lines[1].line.isStart
})

// 12. Stone caught mid-tap answers at once, even inside the cooldown; an
//     ordinary refusal right after stays quiet.
check("12 Stone caught bypasses the cooldown; the next refusal does not", every { i in
    var s = Session(.stone, seed: i); s.event(.radioOn); s.run(until: 2)
    s.event(.stoneCaught); let n = s.lines.count
    s.event(.stoneRefused)
    return n == 2 && s.lines.count == 2 && D.radioStone.caught.contains(s.lines[1].line.text)
})

// 14. The start line is always the FIRST line for a new toy, even when the
//     host refuses it for a while and play events keep arriving.
check("14 start first: kicks during a refused start never speak before it", every { i in
    var s = Session(.tide, seed: i); s.refuseUntil = 3.0; s.event(.selected(.ball))
    let kicks = stride(from: 0.5, through: 30, by: 0.5).map { ($0, ToyEvent.ballKicked(strong: true)) }
    s.run(until: 30, events: kicks)
    guard let first = s.lines.first else { return false }
    return first.line.isStart && first.t >= 3.1 - 1e-6 && first.t <= 3.25
        && s.lines.dropFirst().allSatisfy { !$0.line.isStart && D.ball.myBigKick.contains($0.line.text) }
})
check("14 Stone caught mid-tap is the one line allowed before the start line", every { i in
    var s = Session(.stone, seed: i); s.event(.radioOn); s.run(until: 0.5); s.event(.stoneCaught)
    s.run(until: 6)
    // The start retries in 2 s steps until it is 3 s clear of the caught line: 1.1 -> 3.1 -> 5.1.
    return s.lines.count == 2 && D.radioStone.caught.contains(s.lines[0].line.text) && near(s.lines[0].t, 0.5)
        && s.lines[1].line.isStart && near(s.lines[1].t, 5.1, tol: 0.1)
})
check("14 'Catch me if you can!' is gone; owner's Stone caught lines are in", !allBall.contains("Catch me if you can!")
      && D.radioStone.caught.contains("I was not dancing!")
      && D.radioStone.caught.contains("That was not a dance move! I was just tapping my foot.")
      && !allStone.contains("That wasn't dancing.") && !allStone.contains("I wasn't dancing."))

// 13. Fallback only for the unshipped toys; ambient too.
check("13 star: every line over 2 minutes is a fallback line", every { i in
    var s = Session(.tide, seed: i); s.event(.selected(.star)); s.run(until: 120)
    return s.lines.count >= 3 && s.texts.allSatisfy { fallback.contains($0) }
})

print("\(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
