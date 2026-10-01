import Foundation

// Every edge case from the greeting spec, each run across SEEDS different
// rolls, asserting pool membership / exclusion — the engine is random by
// design, so a single roll proves nothing.
let SEEDS = 600
var pass = 0, fail = 0
func check(_ name: String, _ ok: Bool) {
    if ok { pass += 1 } else { fail += 1; print("FAIL \(name)") }
}

/// Run one context across all seeds; return every distinct (kind, text).
func rolls(_ c: GreetingContext) -> [HomeGreeting] {
    (0 ..< SEEDS).map { i in
        var rng = SeededGenerator(seed: UInt64(i &+ 1) &* 0x9E3779B97F4A7C15)
        return HomeGreetingEngine.choose(c, using: &rng)
    }
}
func texts(_ gs: [HomeGreeting]) -> Set<String> { Set(gs.map(\.text)) }
func kinds(_ gs: [HomeGreeting]) -> Set<String> { Set(gs.map { "\($0.kind)" }) }
func tutorials(_ gs: [HomeGreeting]) -> Set<DiscoverableFeature> {
    Set(gs.compactMap { if case .tutorial(let f) = $0.kind { return f }; return nil })
}
let L = GreetingLines.self
func isSubset(_ a: Set<String>, of pools: [[String]]) -> Bool {
    a.isSubset(of: Set(pools.flatMap { $0 }))
}

/// A player who has hatched and discovered everything, mid-life.
func base() -> GreetingContext {
    GreetingContext(hasHatchedFirstAurie: true, hasAurieNow: true,
                    hasOpenedToyBox: true, hasOpenedCalm: true,
                    hasOpenedCharmCollection: true, hasShakenPhone: true,
                    ownedCharmCount: 3, daysSinceLastArrival: 1,
                    homeArrivalCount: 12, family: .tide,
                    aurieLine: "Marina likes to make a splash.")
}

// 1. First launch, no Aurie: only the pre-photo pool, never anything else.
do {
    var c = base(); c.hasHatchedFirstAurie = false; c.hasAurieNow = false
    c.hasOpenedToyBox = false; c.hasOpenedCalm = false
    c.hasOpenedCharmCollection = false; c.hasShakenPhone = false
    c.ownedCharmCount = 0; c.daysSinceLastArrival = nil; c.homeArrivalCount = 0
    let g = rolls(c)
    check("1 no-Aurie: every line from the first-Aurie pool", isSubset(texts(g), of: [L.firstAurie]))
    check("1 no-Aurie: all five lines reachable", texts(g) == Set(L.firstAurie))
    check("1 no-Aurie: never blinks", g.allSatisfy { $0.blink == nil })
}

// 2. (Pending-egg state REMOVED per correction — there is no persisted egg.)
//    The pre-photo pool is the only pre-hatch greeting; verified in 1.

// 3. First Aurie hatched: the first-launch pool can never appear again —
//    even after the collection is emptied (featured gone → greeter shown).
do {
    var c = base(); c.homeArrivalCount = 0; c.daysSinceLastArrival = nil
    check("3 hatched: first-Aurie pool absent", texts(rolls(c)).isDisjoint(with: L.firstAurie))
    var e = base(); e.hasAurieNow = false   // collection emptied later
    let g = rolls(e)
    check("3 hatched but no creature on Home: falls back to first-Aurie pool, no tutorials",
          isSubset(texts(g), of: [L.firstAurie]))
}

// 4. Calm opened once: explicit Calm tutorial never returns.
do {
    var c = base(); c.hasOpenedCalm = true
    c.hasOpenedToyBox = false; c.hasShakenPhone = false; c.homeArrivalCount = 1
    let g = rolls(c)
    check("4 calm discovered: no Calm tutorial", texts(g).isDisjoint(with: L.calmTutorial))
    check("4 calm discovered: never blinks calm", g.allSatisfy { $0.blink != .calm })
    var u = base(); u.hasOpenedCalm = false; u.homeArrivalCount = 1
    check("4 calm undiscovered: Calm tutorial reachable", !texts(rolls(u)).isDisjoint(with: L.calmTutorial))
}

// 5. Toy Box opened once: explicit Toy Box tutorial never returns.
do {
    var c = base(); c.hasOpenedToyBox = true; c.hasOpenedCalm = false; c.homeArrivalCount = 1
    let g = rolls(c)
    let toy = L.toyBoxTutorial + [L.radioLine, L.radioLineStone]
    check("5 toybox discovered: no Toy Box tutorial", texts(g).isDisjoint(with: toy))
    check("5 toybox discovered: never blinks toybox", g.allSatisfy { $0.blink != .toyBox })
    var u = base(); u.hasOpenedToyBox = false; u.homeArrivalCount = 1
    check("5 toybox undiscovered: tutorial reachable + blinks",
          rolls(u).contains { $0.blink == .toyBox })
}

// 6. No charm found yet: never "see the ones we've found".
do {
    var c = base(); c.ownedCharmCount = 0; c.hasOpenedCharmCollection = false; c.homeArrivalCount = 1
    let g = rolls(c)
    check("6 no charm: never the 8B line", texts(g).isDisjoint(with: L.charmsCollectionUnopened))
    check("6 no charm: never later-charm lines", texts(g).isDisjoint(with: L.charmsLater))
    check("6 no charm: 8A pool reachable", !texts(g).isDisjoint(with: L.charmsNoneFound))
    var o = base(); o.ownedCharmCount = 0; o.hasOpenedCharmCollection = true; o.homeArrivalCount = 1
    check("6 no charm, collection opened: still no later-charm lines", texts(rolls(o)).isDisjoint(with: L.charmsLater))
}

// 7. Charm found, collection never opened: 8B eligible, 8A gone.
do {
    var c = base(); c.ownedCharmCount = 1; c.hasOpenedCharmCollection = false; c.homeArrivalCount = 1
    let g = rolls(c)
    check("7 charm found, unopened: 8B reachable", !texts(g).isDisjoint(with: L.charmsCollectionUnopened))
    check("7 charm found, unopened: 8A gone", texts(g).isDisjoint(with: L.charmsNoneFound))
    check("7 charm found, unopened: later-charm lines withheld", texts(g).isDisjoint(with: L.charmsLater))
}

// 8. Charm collection opened (and a charm owned): collection tutorial disappears.
do {
    let c = base()
    let g = rolls(c)
    check("8 charms understood: no 8A/8B", texts(g).isDisjoint(with: L.charmsNoneFound + L.charmsCollectionUnopened))
    check("8 charms understood: later-charm lines reachable", !texts(g).isDisjoint(with: L.charmsLater))
}

// 9. Phone shaken once: shake tutorial gone, later-shake lines eligible.
do {
    let c = base()
    let g = rolls(c)
    check("9 shaken: no shake tutorial", texts(g).isDisjoint(with: L.shakeTutorial))
    check("9 shaken: later-shake reachable", !texts(g).isDisjoint(with: L.shakeLater))
    var u = base(); u.hasShakenPhone = false; u.homeArrivalCount = 1
    let ug = rolls(u)
    check("9 unshaken: shake tutorial reachable", !texts(ug).isDisjoint(with: L.shakeTutorial))
    check("9 unshaken: later-shake withheld", texts(ug).isDisjoint(with: L.shakeLater))
    check("9 shake tutorial never blinks", ug.allSatisfy { $0.blink != .shake })
}

// 10. Long absence: warm welcome, never a tutorial on that launch, even
//     with every feature undiscovered.
do {
    var c = base(); c.daysSinceLastArrival = GreetingPolicy.longReturnDays
    c.hasOpenedToyBox = false; c.hasOpenedCalm = false
    c.hasOpenedCharmCollection = false; c.hasShakenPhone = false; c.ownedCharmCount = 0
    c.homeArrivalCount = 0
    let g = rolls(c)
    check("10 long return: only the long-return pool", isSubset(texts(g), of: [L.longReturn]))
    check("10 long return: no tutorial, no blink", g.allSatisfy { $0.blink == nil && kinds([$0]) == ["longReturn"] })
    var s = c; s.daysSinceLastArrival = GreetingPolicy.longReturnDays - 1
    check("10 one day short: NOT the long-return pool (normal/tutorial instead)",
          kinds(rolls(s)).isDisjoint(with: ["longReturn"]))
    check("10 no guilt words anywhere",
          !L.longReturn.joined().lowercased().contains("where have you") &&
          !L.longReturn.joined().lowercased().contains("forgot") &&
          !L.longReturn.joined().lowercased().contains("waiting forever"))
}

// 11 / 12. Stone gets its radio line; nobody else ever does.
do {
    var s = base(); s.family = .stone; s.hasOpenedToyBox = false; s.homeArrivalCount = 0
    let sg = texts(rolls(s))
    check("11 stone: Stone radio line reachable", sg.contains(L.radioLineStone))
    check("11 stone: never the dance line", !sg.contains(L.radioLine))
    for fam in AuraFamily.allCases where fam != .stone {
        var c = base(); c.family = fam; c.hasOpenedToyBox = false; c.homeArrivalCount = 0
        let g = texts(rolls(c))
        check("12 \(fam): never Stone's line", !g.contains(L.radioLineStone))
        check("12 \(fam): dance line reachable", g.contains(L.radioLine))
    }
}

// Tutorial weighting: first real visit ALWAYS teaches; early window favours
// the Toy Box; late visits are mostly not tutorials.
do {
    var f = base(); f.hasOpenedToyBox = false; f.hasOpenedCalm = false; f.hasShakenPhone = false
    f.homeArrivalCount = 0; f.daysSinceLastArrival = nil
    let fg = rolls(f)
    check("first visit: always a tutorial", fg.allSatisfy { if case .tutorial = $0.kind { return true }; return false })
    let toyShare = Double(fg.filter { $0.blink == .toyBox }.count) / Double(SEEDS)
    check("first visit: Toy Box leads (\(Int(toyShare*100))%)", toyShare > 0.45)
    var l = f; l.homeArrivalCount = 30; l.daysSinceLastArrival = 1
    let lg = rolls(l)
    let tutShare = Double(lg.filter { if case .tutorial = $0.kind { return true }; return false }.count) / Double(SEEDS)
    check("late visits: tutorials a minority (\(Int(tutShare*100))%)", tutShare < 0.45 && tutShare > 0.15)
    check("late visits: welcomes and personality both appear",
          kinds(lg).isSuperset(of: ["normalReturn", "personality"]))
    var a = f; a.homeArrivalCount = 2; a.avoidTutorial = .toyBox
    check("rotation: avoided feature not repeated when alternatives exist", tutorials(rolls(a)).contains(.toyBox) == false)
}

// All discovered: no tutorial ever, personality + welcomes only.
do {
    let g = rolls(base())
    check("all discovered: no tutorial kind", tutorials(g).isEmpty)
    check("all discovered: never blinks", g.allSatisfy { $0.blink == nil })
    check("all discovered: the Aurie's own line is in the personality pool",
          texts(g).contains("Marina likes to make a splash."))
}

print("\(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
