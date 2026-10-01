import SpriteKit
import QuartzCore
import UIKit

/// The live creature scene, in one of two modes that never compete (Calm Mode
/// spec):
///
/// **.play** — the six play gestures (§7): tap → bounce, tap empty space →
/// hop, pet-stroke → wiggle + hearts, rapid taps → tickle giggle,
/// press-and-hold → pick up / drag / drop, device shake → fly all over the
/// screen. Reaction lines surface through `onReactionLine`.
///
/// **.calm** — the quiet table: tap → slow blink + tiny nod, stroke/hold →
/// gentle lean with eyes nearly closed (+ soft haptic pulse while held), drag
/// → drifting sparkles the eyes follow, tap empty space → look, stay seated,
/// shake → mostly ignored (occasionally the tiniest wobble + exhale). No
/// energetic reactions, no barks.
///
/// The scene anchors at its centre (anchorPoint 0.5/0.5) so the creature's
/// (0,0) home is the middle of the view no matter how the hosting SpriteView
/// resizes during SwiftUI's layout passes.
final class CreatureScene: SKScene {

    enum Mode { case play, calm }

    private var aurie: Aurie
    let mode: Mode
    private var creature: AurieNode!
    /// Family ambient life (Home only). Owned here so it is torn down with
    /// the scene and cannot leak actions into the next presentation.
    private var ambient: FamilyAmbientNode?

    /// Whether the creature is currently following an ambient visitor, so a
    /// first sighting can play a one-off beat and the glance can be released
    /// exactly once when the visitor leaves.
    private var watchingVisitor = false
    /// One close-approach beat per visit, so a butterfly that lingers nearby
    /// does not make the creature giggle on a loop.
    private var greetedVisitor = false

    /// The creature NOTICES ambient life, and goes after it. Called from
    /// `FamilyAmbientNode` with the visitor's scene position, `nil` when it
    /// leaves.
    ///
    /// The chase reuses the TOY-PLAY beat machinery (`canToyBeat`,
    /// `lastCreatureBeatAt`, `sceneHop`) rather than driving the creature
    /// directly, so it inherits every guard that already exists: it cannot
    /// fight a carry, a running reaction, a hop in flight, or a finger on the
    /// screen, and `sceneHop` keeps it inside the play area.
    private func watchAmbientVisitor(_ point: CGPoint?) {
        guard let creature else { return }
        // OFF SCREEN IS GONE. The butterfly's exit carries it well past the
        // frame edge, and it keeps reporting the whole way — so without this
        // the creature goes on hopping after something it cannot see.
        let visible: Bool = {
            guard let point else { return false }
            return abs(point.x) <= size.width * 0.47
                && abs(point.y) <= size.height * 0.47
        }()
        guard let point, visible else {
            if watchingVisitor {
                watchingVisitor = false
                greetedVisitor = false
                creature.endGlance()
                // Wander back to the resting spot now the chase is over.
                sceneHopHome()
            }
            return
        }
        guard !wonderActive, mode == .play else { return }
        let first = !watchingVisitor
        watchingVisitor = true
        // Eye tracking is a NICE-TO-HAVE, not a gate. `glanceToward` returns
        // false whenever the sparkle is hidden — which every half-lidded or
        // arc-eyed expression does on the Blender skin — and gating the chase
        // on it meant Aurie stopped following the butterfly the moment it
        // blinked sleepily (2026-09-25).
        _ = creature.glanceToward(point)
        if first {
            creature.face(point.x < creature.position.x ? -1 : 1)
            creature.reactBounce()
        }

        let now = CACurrentMediaTime()
        #if DEBUG
        let logChase = ProcessInfo.processInfo
            .environment["AURIE_AMBIENT_LOG"] == "1"
        #endif
        let d = point.distance(to: creature.position)
        // TWO different rhythms. Following has to be responsive or the
        // creature trails hopelessly behind something that crosses the frame
        // in ten seconds; reaching has to be RARE or it pumps its arms the
        // whole visit (7 reaches in one crossing, first cut).
        // Tighter again: the creature should sit just behind the butterfly,
        // not a body-length off it. At +55 it stopped following while still
        // visibly trailing.
        let close = d < creatureReach + 15
        guard canToyBeat(now, minGap: close ? 3.4 : 0.42) else { return }
        if close {
            // Close enough to touch: reach for it, and one warmer beat the
            // first time it comes within range on a given visit.
            lastCreatureBeatAt = now
            #if DEBUG
            if logChase { NSLog("AURIE_CHASE reach d=%.0f", d) }
            #endif
            _ = creature.armReach(toward: point, hold: 0.45)
            if !greetedVisitor {
                greetedVisitor = true
                creature.reactGiggle()
            }
        } else {
            // Too far: hop a step after it. Short hops, not a sprint — it is
            // following something delicate, not chasing a ball.
            lastCreatureBeatAt = now
            // SHORT hops, several of them. 118pt covered the ground in one
            // leap, which reads as teleporting to the butterfly rather than
            // following it; ~56pt at more than twice the rate closes the same
            // distance in three or four steps.
            // Short hops, and never past the target: the last step shrinks
            // to whatever is left, so it settles in behind the butterfly
            // instead of overshooting and bouncing back.
            let gap = point.x - creature.position.x
            let step = (gap < 0 ? -1 : 1) * min(56, max(20, abs(gap) * 0.65))
            #if DEBUG
            if logChase {
                NSLog("AURIE_CHASE hop d=%.0f from x=%.0f step=%.0f",
                      d, creature.position.x, step)
            }
            #endif
            sceneHop(to: CGPoint(x: creature.position.x + step,
                                 y: creature.position.y),
                     hopHeight: 18, duration: 0.20)
        }
    }

    /// MEASUREMENT CONTROL (DEBUG, `AURIE_AMBIENT_OFF=1`). Home is never
    /// perfectly still even with no ambient life — Aurie bobs and wanders, and
    /// the background parallaxes with it — so "how much moved between frames"
    /// measures the whole scene, not the effect. Capturing the same family
    /// with this set gives a parallax-only control to subtract. Without it a
    /// visibility number is meaningless: the first run of this pass reported
    /// near-identical motion for four very different families.
    static var ambientSuppressed: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AURIE_AMBIENT_OFF"] == "1"
        #else
        return false
        #endif
    }

    /// Asks the hosting view to *consider* a short play bark (repeat freely,
    /// not stored). The closure generates a fresh line on demand: the view
    /// owns the speech gate (chance, cooldown, no stacking) and may re-request
    /// to avoid an immediate duplicate, so the physical reaction never waits
    /// on line generation.
    var onReactionLine: ((_ makeLine: () -> String) -> Void)?
    /// Toy Box activity dialogue (see `ToyDialogue`): the scene reports
    /// events, the director decides when to speak, and the host shows the
    /// line if no other bubble is up — returning false so a start line is
    /// retried instead of lost.
    var onToyLine: ((String) -> Bool)?
    private lazy var toyTalk = ToyDialogueDirector(family: aurie.family)
    /// The player genuinely touched their Aurie (a body-region tap or a
    /// pet stroke) — NOT an empty-space hop and NOT an autonomous fidget.
    /// Fires only in `.play` mode. Feeds the "Old Friends" task through
    /// the model; the model collapses it to one event per calendar day.
    var onInteraction: (() -> Void)?

    // MARK: Presentation anchor (Stage C)

    /// What a hosting view needs to keep a speech bubble attached to the
    /// creature: its centre plus the scaled *physical* half-extents (the same
    /// body+limbs footprint as the movement clamp — aura, contact shadow,
    /// particles, and reaction effects excluded), the scene size for
    /// coordinate mapping, and whether the creature is currently visible.
    struct PresentationAnchor: Equatable {
        var center: CGPoint      // scene coordinates (centre-origin, y up)
        var halfWidth: CGFloat
        var halfUp: CGFloat
        var halfDown: CGFloat
        var sceneSize: CGSize
        var visible: Bool
    }

    /// Fired from the render loop, but only when the anchor actually changed —
    /// a resting creature publishes nothing, so SwiftUI sees no 60 Hz churn
    /// while idle.
    var onAnchorChange: ((PresentationAnchor) -> Void)?
    private var lastPublishedAnchor: PresentationAnchor?

    override func update(_ currentTime: TimeInterval) {
        publishAnchorIfNeeded()
        let dt = lastUpdateTime > 0
            ? CGFloat(min(currentTime - lastUpdateTime, 1.0 / 20)) : 0
        lastUpdateTime = currentTime
        wonderSwirl?.update(TimeInterval(dt))
        stepWonderCarry(dt)
        if toyBox.active != nil {
            toyBox.tick(dt: dt, now: currentTime, in: self)
            updateToyCreatureInteractions(now: currentTime)
        }
        if radio.isPlaying { tickDance(currentTime) }
        tickToyTalk(currentTime)
        if environment.isActive, let creature {
            let halfTravel = max(size.width / 2 - collisionHalfExtent.x, 1)
            environment.updateParallax(normalizedX: creature.position.x / halfTravel)
        }
    }
    private var lastUpdateTime: TimeInterval = 0

    private func publishAnchorIfNeeded() {
        guard let creature, let onAnchorChange else { return }
        let anchor = PresentationAnchor(
            center: creature.position,
            halfWidth: AssetLoader.collisionHalfWidth * creatureScale,
            halfUp: AssetLoader.collisionHalfHeightUp * creatureScale,
            halfDown: AssetLoader.collisionHalfHeightDown * creatureScale,
            sceneSize: size,
            visible: creature.parent != nil && creature.alpha > 0.05)
        if let last = lastPublishedAnchor,
           last.halfWidth == anchor.halfWidth,
           last.sceneSize == anchor.sceneSize,
           last.visible == anchor.visible,
           abs(last.center.x - anchor.center.x) < 0.25,
           abs(last.center.y - anchor.center.y) < 0.25 {
            return   // nothing the bubble cares about moved
        }
        lastPublishedAnchor = anchor
        onAnchorChange(anchor)
    }

    // MARK: Gesture tracking

    private let carryHoldDelay: TimeInterval = 0.35
    private let calmHoldDelay: TimeInterval = 0.6
    private var touchBeganAt: TimeInterval = 0
    private var startedOnCreature = false
    private var accumulatedDrag: CGFloat = 0
    private var lastTouchLocation: CGPoint = .zero
    private var lastSparkleLocation: CGPoint = .zero
    private var petTriggeredThisTouch = false
    private var calmHolding = false
    private var shakeObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private let softHaptic = UIImpactFeedbackGenerator(style: .soft)

    /// When true, the scene opens with the family hatch burst + a birth
    /// reaction (used by the reveal screen).
    var celebratesBirth = false

    /// Home passes true so the layered SwiftUI HomeBackgroundView shows through
    /// (the creature and its aura render over the atmosphere). Everywhere else
    /// keeps the opaque family-tint backdrop — Detail / reveal / Calm unchanged.
    var transparentBackground = false

    init(aurie: Aurie, mode: Mode = .play) {
        self.aurie = aurie
        self.mode = mode
        super.init(size: CGSize(width: 400, height: 800))
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func didMove(to view: SKView) {
        toyBox.onEvent = { [weak self] event in self?.toyEvent(event) }
        // Family-colour tint fallback (§9); Calm Mode softens it further but
        // keeps the family identity — Ember still feels like Ember.
        if transparentBackground {
            backgroundColor = .clear
        } else {
            let c = mode == .calm
                ? calmBackdropComponents(aurie.auraColor)
                : familyBackdropComponents(aurie.auraColor)
            backgroundColor = SKColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        }

        #if DEBUG
        // Stage 1 verification: force the Home creature to Round in a chosen
        // family colour so the Blender skin can be checked against the
        // approved render. Debug-only; never alters saved data.
        if let fam = ProcessInfo.processInfo.environment["AURIE_BLENDER_DEMO"] {
            let forced = ProcessInfo.processInfo
                .environment["AURIE_BLENDER_BODY"] ?? "round"
            aurie.body = BodyType(rawValue: forced) ?? .round
            if let a = ProcessInfo.processInfo.environment["AURIE_BLENDER_ARM"] {
                aurie.armStyle = a
            }
            if let l = ProcessInfo.processInfo.environment["AURIE_BLENDER_LEG"] {
                aurie.legStyle = l
            }
            let palette: [String: Rgb] = ["ember": Rgb(232, 115, 74),
                                          "moss": Rgb(124, 184, 110),
                                          "dusk": Rgb(154, 120, 200)]
            if let c = palette[fam] { aurie.baseColor = c }
            if let e = ProcessInfo.processInfo.environment["AURIE_BLENDER_FACE"],
               let face = BaseExpression(rawValue: e) {
                aurie.baseExpression = face
            }
            if let p = ProcessInfo.processInfo.environment["AURIE_BLENDER_PATTERN"],
               let pat = PatternType(rawValue: p) {
                aurie.pattern = pat
            }
        }
        #endif

        let buildStart = CACurrentMediaTime()
        creature = AurieNode(
            textures: AssetLoader.textures(for: aurie),
            baseColor: skColor(aurie.baseColor),
            auraColor: skColor(aurie.auraColor),
            body: aurie.body,         // selects the Blender skin where it exists
            armStyle: aurie.resolvedArmStyle,
            legStyle: aurie.resolvedLegStyle,
            hairStyle: aurie.resolvedHairStyle,
            patternLayer: aurie.patternMaskLayer,
            charmLayers: charmLayerKeys(for: aurie),
            bellyStickerCharmID: bellyStickerID(for: aurie),
            auraCharmID: auraCharmID(for: aurie),
            floatingCharmID: floatingCharmID(for: aurie)
        )
        #if DEBUG
        if ProcessInfo.processInfo.environment["AURIE_SK_STATS"] == "1" {
            func count(_ n: SKNode) -> Int {
                n.children.reduce(1) { $0 + count($1) }
            }
            var textures = Set<ObjectIdentifier>()
            func walk(_ n: SKNode) {
                if let s = n as? SKSpriteNode, let t = s.texture {
                    textures.insert(ObjectIdentifier(t))
                }
                n.children.forEach(walk)
            }
            walk(creature)
            NSLog("AURIE_STATS skin=%@ nodes=%d textures=%d buildMs=%.1f",
                  creature.usesBlenderSkin ? "blender" : "placeholder",
                  count(creature), textures.count,
                  (CACurrentMediaTime() - buildStart) * 1000)
        }
        #endif
        creature.position = .zero   // scene centre, thanks to the anchorPoint
        addChild(creature)
        applyCreatureScale()        // size the creature to this play area
        creature.startIdle()
        setupEnvironment()
        // The saved personality face is the creature's resting state from
        // the first frame; every reaction returns here.
        creature.adoptBaseExpression(aurie.resolvedBaseExpression)

        // Calm mode plants the creature: it must never hop, from any source.
        creature.hopsEnabled = (mode == .play)

        if mode == .calm {
            creature.enterCalm()
            // Entering Calm Mode is itself a settling moment.
            creature.run(.sequence([.wait(forDuration: 0.6), .run { [weak self] in
                self?.creature?.play(.calmSettle)
            }]))
        } else {
            scheduleIdleMoments()
        }

        // A reaction must never outlive the visible scene: backgrounding
        // mid-reaction would otherwise leave the creature wearing a
        // temporary face when the user comes back.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.creature?.cancelReactions()
            // Ambient life is NOT paused here on purpose: SpriteKit stops
            // advancing actions while the app is inactive and resumes on
            // return, whereas an explicit pause here would need a matching
            // foreground observer and can strand the scene frozen.
        }

        // Fade in so the first frame or two of SwiftUI/SpriteView layout
        // settling isn't visible as the creature snapping into place.
        creature.alpha = 0
        creature.run(.sequence([.wait(forDuration: 0.08), .fadeIn(withDuration: 0.4)]))

        if celebratesBirth {
            run(.sequence([.wait(forDuration: 0.5), .run { [weak self] in
                guard let self else { return }
                self.playHatchBurst()
                self.creature.playBirthReaction()
                self.playCelebration()
            }]))
        }

        shakeObserver = NotificationCenter.default.addObserver(
            forName: .deviceDidShake, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleShake()
        }

        #if DEBUG
        startReactionSelfTestIfRequested()
        showSingleFaceIfRequested()
        startHomeInteractionDemoIfRequested()
        startWaveDemoIfRequested()
        startGlanceDemoIfRequested()
        logRegionAuditIfRequested()
        logRestReportIfRequested()
        #endif
    }

    #if DEBUG
    /// Repeated slow waves so a recording can inspect the shoulder through
    /// the whole arc. Enabled with `AURIE_WAVE_DEMO=1`.
    func startWaveDemoIfRequested() {
        guard ProcessInfo.processInfo.environment["AURIE_WAVE_DEMO"] == "1",
              let creature else { return }
        creature.removeAction(forKey: "blinkLoop")
        run(.repeatForever(.sequence([
            .wait(forDuration: 2.6),
            .run { NSLog("AURIE_WAVE"); creature.littleWave(big: true) },
        ])), withKey: "waveDemo")
    }

    /// Log the transform-rest report after a chosen delay, so an untouched
    /// autonomous-life run can prove zero cumulative drift at its end.
    /// `AURIE_REST_REPORT=<seconds>`.
    func logRestReportIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment["AURIE_REST_REPORT"],
              let delay = TimeInterval(raw), let creature else { return }
        run(.sequence([.wait(forDuration: delay), .run {
            NSLog("AURIE_REST %@", creature.debugTransformReport())
        }]))
    }

    /// Log every touch-region rectangle in VIEW coordinates so an overlay can
    /// be compared against a screenshot — proof the zones sit on the visible
    /// sprites for each body. Enabled with `AURIE_REGION_AUDIT=1`.
    func logRegionAuditIfRequested() {
        guard ProcessInfo.processInfo.environment["AURIE_REGION_AUDIT"] == "1",
              let creature else { return }
        run(.sequence([.wait(forDuration: 1.5), .run { [weak self] in
            guard let self, let view = self.view else { return }
            let screen = view.window?.bounds.size ?? view.bounds.size
            for (name, rect) in creature.debugRegionFrames() {
                let bl = self.convertPoint(toView: CGPoint(x: rect.minX, y: rect.minY))
                let tr = self.convertPoint(toView: CGPoint(x: rect.maxX, y: rect.maxY))
                let vr = CGRect(x: min(bl.x, tr.x), y: min(bl.y, tr.y),
                                width: abs(tr.x - bl.x), height: abs(tr.y - bl.y))
                NSLog("AURIE_REGION %@ view=(%.0f,%.0f,%.0f,%.0f) viewSize=(%.0f,%.0f)",
                      name, vr.minX, vr.minY, vr.width, vr.height,
                      view.bounds.width, view.bounds.height)
                // Same rect in WINDOW coordinates, for driving real UI-test taps.
                let wc = view.convert(CGPoint(x: vr.midX, y: vr.midY), to: nil)
                let wtl = view.convert(CGPoint(x: vr.minX, y: vr.minY), to: nil)
                NSLog("AURIE_REGION_WIN %@ centre=(%.1f,%.1f) tl=(%.1f,%.1f) size=(%.1f,%.1f) screen=(%.0f,%.0f)",
                      name, wc.x, wc.y, wtl.x, wtl.y, vr.width, vr.height,
                      screen.width, screen.height)
            }
        }]))
    }

    /// Hold the eyes looking in fixed directions so a screenshot can confirm
    /// the eyes (not the body) track. Enabled with `AURIE_GLANCE_DEMO=1`.
    func startGlanceDemoIfRequested() {
        guard ProcessInfo.processInfo.environment["AURIE_GLANCE_DEMO"] == "1",
              let creature else { return }
        creature.removeAction(forKey: "blinkLoop")
        let far: CGFloat = 400
        let pts: [(String, CGPoint)] = [
            ("left", CGPoint(x: -far, y: 0)), ("right", CGPoint(x: far, y: 0)),
            ("up", CGPoint(x: 0, y: far)), ("down-left", CGPoint(x: -far, y: -far)),
            ("center", .zero)]
        for (i, (lab, p)) in pts.enumerated() {
            run(.sequence([.wait(forDuration: 2.0 + Double(i) * 1.4), .run {
                NSLog("AURIE_GLANCE %@", lab)
                if lab == "center" { creature.endGlance() }
                else { creature.glanceToward(p) }
            }]))
        }
    }
    #endif

    #if DEBUG
    /// Debug-only Home interaction demo. The simulator cannot be tapped from a
    /// script here, so this drives the SAME entry points the touch handler
    /// calls — `dispatchPlayTap` with points synthesized at the head / belly /
    /// foot regions (through the real region classifier), the real pet and
    /// finger-notice paths, and the real autonomous library — so a recording
    /// shows shipping behaviour, not a bespoke animation. Enabled with
    /// `AURIE_HOME_DEMO=1`. Reports the transform state after a 20-interaction
    /// burst so drift is provable, not assumed.
    func startHomeInteractionDemoIfRequested() {
        guard ProcessInfo.processInfo.environment["AURIE_HOME_DEMO"] == "1",
              let creature else { return }

        func point(_ region: TouchRegion) -> CGPoint {
            let c = creature.position
            let halfW = AssetLoader.collisionHalfWidth * creatureScale
            let up = AssetLoader.collisionHalfHeightUp * creatureScale
            let down = AssetLoader.collisionHalfHeightDown * creatureScale
            switch region {
            case .head:      return CGPoint(x: c.x, y: c.y + up * 0.6)
            case .belly:     return CGPoint(x: c.x, y: c.y)
            case .footLeft:  return CGPoint(x: c.x - halfW * 0.5, y: c.y - down * 0.72)
            case .footRight: return CGPoint(x: c.x + halfW * 0.5, y: c.y - down * 0.72)
            case .armLeft:   return CGPoint(x: c.x - halfW * 0.92, y: c.y - down * 0.18)
            case .armRight:  return CGPoint(x: c.x + halfW * 0.92, y: c.y - down * 0.18)
            }
        }
        func tap(_ region: TouchRegion) {
            dispatchPlayTap(at: point(region), now: CACurrentMediaTime())
        }
        func at(_ t: TimeInterval, _ work: @escaping () -> Void) {
            run(.sequence([.wait(forDuration: t), .run(work)]))
        }

        creature.removeAction(forKey: "blinkLoop")   // deterministic captures
        NSLog("AURIE_HOMEDEMO start body=%@ family=%@",
              aurie.body.rawValue, aurie.family.rawValue)

        // ~10 s of untouched idle first (breathing, blinking, autonomous fire
        // on their own), then each interaction in turn with room to settle.
        at(3.0) { creature.slowBlink() }
        at(6.0) { self.performAutonomousBehavior() }      // one autonomous beat
        at(11.0) { NSLog("AURIE_HOMEDEMO head-tap"); tap(.head) }
        at(13.0) { NSLog("AURIE_HOMEDEMO belly-tap"); tap(.belly) }
        at(15.5) { NSLog("AURIE_HOMEDEMO foot-tap-L"); tap(.footLeft) }
        at(17.0) { NSLog("AURIE_HOMEDEMO foot-tap-R"); tap(.footRight) }
        // Repeated poke escalation: five quick belly pokes.
        for i in 0..<5 {
            at(19.5 + Double(i) * 0.4) {
                NSLog("AURIE_HOMEDEMO poke-%d", i + 1); tap(.belly)
            }
        }
        // Pet / swipe (the real pet path).
        at(23.0) {
            NSLog("AURIE_HOMEDEMO pet")
            creature.interruptIdleBehavior()
            creature.reactPet(toward: 1)
            creature.flashFace(BaseExpression.happy.rawValue, for: 1.2)
            self.emitFamilyPuff(3)
        }
        // Finger-notice: a finger sweeping through empty space beside the Aurie.
        at(26.0) {
            NSLog("AURIE_HOMEDEMO finger-notice")
            let y = creature.position.y + 40
            let xs: [CGFloat] = [-220, -140, -60, 60, 140, 220, 140, 60]
            for (i, x) in xs.enumerated() {
                self.run(.sequence([.wait(forDuration: Double(i) * 0.22), .run {
                    self.lastNoticeAt = 0                 // let each step through
                    self.creature?.glanceToward(CGPoint(x: x, y: y))
                }]))
            }
            self.run(.sequence([.wait(forDuration: 2.2),
                                .run { self.creature?.endGlance() }]))
        }
        at(30.0) { NSLog("AURIE_HOMEDEMO autonomous-2"); self.performAutonomousBehavior() }

        // Drift proof: 20 mixed interactions back to back, then report. Every
        // value should be at rest (rotation ~0, squash ~1, limbs ~0 off home).
        at(33.0) {
            NSLog("AURIE_HOMEDEMO drift-burst")
            let seq: [TouchRegion] = [.head, .belly, .footLeft, .footRight]
            for i in 0..<20 {
                self.run(.sequence([.wait(forDuration: Double(i) * 0.18), .run {
                    tap(seq[i % seq.count])
                }]))
            }
        }
        at(38.0) {
            creature.interruptIdleBehavior()
            creature.cancelReactions()
        }
        at(40.0) {
            NSLog("AURIE_HOMEDEMO drift-report %@", creature.debugTransformReport())
            NSLog("AURIE_HOMEDEMO done")
        }
    }
    #endif

    override func willMove(from view: SKView) {
        if let shakeObserver { NotificationCenter.default.removeObserver(shakeObserver) }
        shakeObserver = nil
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        backgroundObserver = nil
        // Drop any temporary face with the scene, so the creature is never
        // left mid-reaction for the next presentation.
        creature?.cancelReactions()
        // Ambient life stops with the screen: these are repeatForever
        // actions and a timed visitor spawner, so leaving Home must drop
        // them rather than let them run under another tab.
        ambient?.teardown()
        ambient = nil
        // The music dies with its screen: SoundPlayer.musicPlayer is a
        // static loop, so an un-stopped radio would keep playing under Calm
        // Mode or another tab with no owning UI left to silence it.
        setRadio(out: false)
    }

    /// Switch this scene to a different creature (used if a host swaps the
    /// active Aurie without rebuilding the scene). Cancels first so the
    /// previous creature's reaction cannot play out on the new face.
    func adopt(_ next: Aurie) {
        aurie = next
        toyTalk = ToyDialogueDirector(family: next.family)
        creature?.adoptBaseExpression(next.resolvedBaseExpression)
    }

    /// LIVE equipment refresh: the SAME Aurie changed what it wears
    /// (equip/remove/replace) while this scene is on screen. Adopt the
    /// new value and hand the resolved charm keys to the node, which
    /// rebuilds only its layer stack — movement, position and ambient
    /// state are untouched. Called by the host view when the store's
    /// Aurie value changes; the scene never watches the store itself.
    func refreshEquipment(_ next: Aurie) {
        guard next.id == aurie.id else { return }   // a swap is adopt/rebuild
        aurie = next
        creature?.setEquipment(
            charmLayers: charmLayerKeys(for: next),
            bellyStickerCharmID: bellyStickerID(for: next),
            auraCharmID: auraCharmID(for: next),
            floatingCharmID: floatingCharmID(for: next))
    }

    /// The big celebratory reaction: hatch reveal, Starlight reveal, and
    /// later Today's Wonder. High priority, so it wins over idle chatter.
    func playCelebration() {
        // Compact stages: cap the hop so its peak stays inside the
        // stage. The RESTING size has priority — the hop shortens, the
        // creature does not shrink. Node-unit cap = headroom / scale.
        if let creature, size.height > 1 {
            let scale = max(creature.xScale, 0.001)
            let footY = playfield.footY(depth: fieldPos.depth,
                                        sceneSize: size)
            let crownTop = footY + creature.crownRiseAboveFeet() * scale
            creature.celebrationLiftCap =
                max(0, size.height / 2 - 6 - crownTop) / scale
        }
        creature?.play(.excitedHop)
    }

    #if DEBUG
    /// Debug-only: hold five obviously-different faces for 2s each, with NO
    /// body animation, to prove the visible face renderer can actually draw
    /// distinct expressions. Enabled with `AURIE_FACE_PARADE=1`.
    /// Debug-only: pin ONE face for the whole session. Capturing a parade
    /// by timing screenshots against a running sequence is inherently racy;
    /// one face per launch is deterministic.
    func showSingleFaceIfRequested() {
        guard let id = ProcessInfo.processInfo.environment["AURIE_FACE_ONE"],
              let creature else { return }
        creature.removeAction(forKey: "blinkLoop")
        run(.sequence([.wait(forDuration: 0.4), .run {
            creature.debugShowFace(id)
            NSLog("AURIE_ONEFACE face=%@", id)
        }]))
    }



    /// Debug-only integration driver. There is no UI-test target, and the
    /// simulator cannot be tapped from a script here, so this calls the
    /// SAME entry points the touch handler and the shake observer call and
    /// logs what the creature is actually wearing at each step. Enabled
    /// with `AURIE_REACTION_SELFTEST=1`; never runs in a release build and
    /// never runs unless that variable is set.
    func startReactionSelfTestIfRequested() {
        guard ProcessInfo.processInfo.environment["AURIE_REACTION_SELFTEST"] == "1",
              let creature else { return }
        func log(_ stage: String, _ extra: String = "") {
            NSLog("AURIE_SELFTEST stage=%@ name=%@ family=%@ base=%@ showing=%@ %@",
                  stage, aurie.name, aurie.family.rawValue,
                  creature.baseExpression.rawValue,
                  creature.currentReaction?.overrideFace
                    ?? creature.baseExpression.rawValue,
                  extra)
        }
        // Idle blink off: it is verified explicitly in the last frame, and
        // a 0.13s blink landing during a capture makes the sheet lie.
        creature.removeAction(forKey: "blinkLoop")
        func at(_ t: TimeInterval, _ work: @escaping () -> Void) {
            run(.sequence([.wait(forDuration: t), .run(work)]))
        }
        at(1.0) { log("rest") }
        at(1.6) {
            let reaction = AuriePersonality.positiveReaction(family: self.aurie.family) {
                Int.random(in: 0 ..< $0)
            }
            let played = creature.play(reaction)
            log("tap", "picked=\(reaction.rawValue) played=\(played)")
        }
        at(1.9) {
            let blinked = creature.play(.blink)
            log("tap-peak", "blink_during_reaction_accepted=\(blinked)")
        }
        at(3.2) { log("after-tap") }
        at(4.0) {
            creature.playShakeSequence()
            log("shake-startled")
        }
        at(4.8) { log("shake-dizzy") }
        at(5.2) {
            let yawned = creature.play(.sleepyYawn)
            log("shake-hold", "low_priority_idle_accepted=\(yawned)")
        }
        at(6.0) { log("shake-recover") }
        at(6.8) { log("after-shake") }
        at(7.4) {
            creature.play(.excitedHop)
            log("celebration")
        }
        at(9.0) { log("after-celebration") }
        at(9.4) {
            creature.cancelReactions()
            log("after-cancel")
        }
    }
    #endif

    /// The full shake flow, callable without a device shake — this is the
    /// hook Wonderglobe will use so it reuses the same character reaction
    /// instead of scripting its own.
    func playShakeReaction() {
        creature?.playShakeSequence()
    }

    // MARK: External control (Calm Mode UI)

    func beginBreatheTogether(cycle: TimeInterval = 8) {
        creature?.startBreathing(cycle: cycle)
    }

    func endBreatheTogether() {
        creature?.stopBreathing()
    }

    /// A SUBTLE family shimmer alongside the worry release: a few small
    /// family motifs drift up from around the jar's mouth while the
    /// fireflies (the main element) are being born. Secondary by
    /// construction — small, translucent, sparse.
    func playWorryRelease() {
        // Count DOUBLED 2026-09-25 at the owner's request (7 -> 14).
        for i in 0..<14 {
            let sprite = SKSpriteNode(texture: FamilyEffects.trailMotif(for: aurie.family))
            sprite.position = CGPoint(x: CGFloat.random(in: -55...55),
                                      y: -size.height * 0.06 + CGFloat.random(in: -8...8))
            sprite.alpha = 0
            // ABOVE the whole creature. The AurieNode's own layers run
            // aura 0 … eyes 5.3 … mouth 6, and z accumulates from the
            // parent, so a scene-level 5 used to slice these motifs
            // between the body and the eyes — particles in front of the
            // belly but behind the face. 9 clears the face; it matches
            // the drag sparkles in `spawnSparkle`.
            sprite.zPosition = 9
            sprite.setScale(CGFloat.random(in: 0.65...1.0))
            addChild(sprite)
            let rise = SKAction.moveBy(x: CGFloat.random(in: -70...70),
                                       y: size.height * 0.55,
                                       duration: Double.random(in: 3.6...5.0))
            rise.timingMode = .easeOut
            let sway = SKAction.repeatForever(.sequence([
                .moveBy(x: 10, y: 0, duration: 0.9),
                .moveBy(x: -10, y: 0, duration: 0.9),
            ]))
            sprite.run(sway)
            sprite.run(.sequence([
                .wait(forDuration: Double(i) * 0.16),
                .fadeAlpha(to: 0.55, duration: 0.6),
                rise,
                .fadeOut(withDuration: 0.8),
                .removeFromParent(),
            ]))
        }
        creature?.slowBlink()
        softHaptic.impactOccurred(intensity: 0.7)
    }

    // MARK: Phase-5 delight (§8)

    /// Gentle family burst at the reveal moment (denser for rare Starlight).
    func playHatchBurst() {
        // Starlight stays the richer burst — that difference is a rarity tell.
        effects.celebrate(at: .zero,
                          spread: aurie.family == .starlight ? 210 : 190)
    }

    /// Host for one-shot family effects. Carries no pooled particles of its
    /// own (`count: 0`) — it exists so every burst in this scene draws from the
    /// shared family art and motion instead of hand-rolling its own.
    private lazy var effects: ParticleField = {
        let field = ParticleField(
            family: aurie.family,
            area: CGRect(x: -size.width/2, y: -size.height/2,
                         width: size.width, height: size.height),
            motion: .ambient, count: 0)
        field.zPosition = 6
        addChild(field)
        return field
    }()

    /// A small puff of family particles near the creature (reactions).
    private func emitFamilyPuff(_ count: Int) {
        guard let creature else { return }
        effects.burst(count: count * 3, at: creature.position, spread: 86)
    }

    // MARK: - Autonomous creature life

    /// The eight launch behaviours. ONE library for every family; family and
    /// the saved base expression only WEIGHT the pick, never restrict it.
    private static let behaviourLibrary = [
        "wave", "curiousLook", "miniBounce", "sleepy",
        "shyWiggle", "stretch", "inspectFoot", "greeting",
    ]
    /// The last two picks, for variety suppression: the most recent behaviour
    /// is excluded outright, the one before runs at half weight.
    private var recentBehaviours: [String] = []

    /// Quiet → small behaviour → quiet. Noticeable beats land at irregular
    /// 8–20 s spacing (the first arrives sooner so a fresh Home feels alive);
    /// a skipped slot (carried, mid-reaction) retries in a few seconds rather
    /// than leaving a long dead stretch. Breathing/blinking run underneath on
    /// their own loops throughout.
    private func scheduleIdleMoments() {
        scheduleNextBehaviour(in: .random(in: 5 ... 9))
    }

    private func scheduleNextBehaviour(in delay: TimeInterval) {
        removeAction(forKey: "idleMoments")
        run(.sequence([.wait(forDuration: delay), .run { [weak self] in
            guard let self else { return }
            let ran = self.performAutonomousBehavior()
            self.scheduleNextBehaviour(in: ran ? .random(in: 8 ... 20)
                                              : .random(in: 3 ... 6))
        }]), withKey: "idleMoments")
    }

    /// One noticeable autonomous beat: a weighted pick from the library, a
    /// ~1.5–3 s whole-character moment pairing a gesture with a temporary
    /// face, always returning to the saved base expression and exact rest.
    /// Returns false when the slot was skipped (so the scheduler retries
    /// sooner). Never stacks: a beat only starts from quiet.
    @discardableResult
    private func performAutonomousBehavior() -> Bool {
        guard let creature, !creature.isCarried, !userTouching,
              action(forKey: "flail") == nil,
              creature.action(forKey: "hopArc") == nil,
              creature.currentReaction == nil,
              // The radio owns the creature while music is on: idle life must
              // never interrupt (or stack on top of) a dance.
              !creature.isDancing, !radio.isPlaying,
              CACurrentMediaTime() - lastCreatureBeatAt > 4 else { return false }
        lastCreatureBeatAt = CACurrentMediaTime()

        var weights = autonomousWeights(for: aurie.family)
        weights = Self.biased(weights, by: aurie.resolvedBaseExpression)
        if let last = recentBehaviours.last {
            weights.removeAll { $0.0 == last }        // never twice in a row
        }
        if recentBehaviours.count > 1 {
            let older = recentBehaviours[recentBehaviours.count - 2]
            weights = weights.map { ($0.0, $0.0 == older ? max(1, $0.1 / 2) : $0.1) }
        }
        let choice = AuriePersonality.pick(weights) { Int.random(in: 0 ..< $0) }
        recentBehaviours = Array((recentBehaviours + [choice]).suffix(2))
        // Every beat is expression-led (and wave/greet address the viewer):
        // a back-facing Aurie turns around before performing.
        faceUserForInteraction()
        #if DEBUG
        if ProcessInfo.processInfo.environment["AURIE_REACTION_SELFTEST"] == "1"
            || ProcessInfo.processInfo.environment["AURIE_AUTO_LOG"] == "1" {
            NSLog("AURIE_AUTO family=%@ behavior=%@", aurie.family.rawValue, choice)
        }
        #endif

        switch choice {
        case "wave":
            // Pause → glance toward the viewer → the approved wave, wearing a
            // face that matches this creature's personality.
            let face: BaseExpression = {
                switch aurie.resolvedBaseExpression {
                case .shy:                  return .shy
                case .delighted, .excited:  return .delighted
                default:                    return .happy
                }
            }()
            creature.autonomousExpression(face.rawValue, for: 2.2)
            creature.sparkleGlance(dx: 0, dy: -2, hold: 0.7, out: 0.25)
            creature.run(.sequence([.wait(forDuration: 0.4), .run { [weak creature] in
                creature?.littleWave(big: true, side: Bool.random() ? 1 : -1)
            }]), withKey: "autoStage")
        case "curiousLook":
            creature.autonomousExpression(BaseExpression.curious.rawValue, for: 2.6)
            creature.curiousLook()
        case "miniBounce":
            let face: BaseExpression = aurie.resolvedBaseExpression == .delighted
                ? .delighted : .happy
            creature.autonomousExpression(face.rawValue, for: 1.4)
            creature.reactBounce()
        case "sleepy":
            creature.autonomousExpression("yawn", for: 2.4)
            creature.sleepyMoment()
        case "shyWiggle":
            creature.autonomousExpression(BaseExpression.shy.rawValue, for: 1.6)
            creature.shyWiggle()
        case "stretch":
            creature.autonomousExpression("calm", for: 2.2)
            creature.stretchSoft()
        case "inspectFoot":
            creature.autonomousExpression(BaseExpression.curious.rawValue, for: 2.2)
            creature.inspectFoot()
        default:  // greeting — "Oh! You're here!"
            creature.autonomousExpression(BaseExpression.delighted.rawValue, for: 1.8)
            creature.greetUser()
            emitFamilyPuff(2)
        }
        return true
    }

    /// Family bias — a weighting, never a restriction: every family can still
    /// perform every behaviour. Mirrors the personality language used
    /// elsewhere (Ember bouncy/greeting, Stone quiet, Moss/Dusk shy-curious,
    /// Glow/Starlight outgoing, Tide curious-calm).
    private func autonomousWeights(for family: AuraFamily) -> [(String, Int)] {
        let pref: [String]
        switch family {
        case .stone:     pref = ["sleepy", "stretch", "shyWiggle", "curiousLook"]
        case .ember:     pref = ["miniBounce", "wave", "greeting", "curiousLook"]
        case .glow:      pref = ["greeting", "miniBounce", "wave", "stretch"]
        case .moss:      pref = ["curiousLook", "inspectFoot", "shyWiggle", "wave"]
        case .tide:      pref = ["curiousLook", "stretch", "sleepy", "inspectFoot"]
        case .dusk:      pref = ["curiousLook", "inspectFoot", "shyWiggle", "wave"]
        case .starlight: pref = ["greeting", "miniBounce", "curiousLook", "wave"]
        }
        return Self.behaviourLibrary.map { ($0, pref.contains($0) ? 3 : 1) }
    }

    /// The persisted base expression nudges (never dominates) the pick: a
    /// sleepy Aurie yawns and stretches a little more, a curious one peers
    /// and inspects, an excited one bounces and greets, a shy one wiggles
    /// and waves small, a mischievous one does the quirky ones.
    private static func biased(_ weights: [(String, Int)],
                               by expression: BaseExpression) -> [(String, Int)] {
        let boost: Set<String>
        switch expression {
        case .sleepy:               boost = ["sleepy", "stretch"]
        case .curious:              boost = ["inspectFoot", "curiousLook"]
        case .delighted, .excited:  boost = ["miniBounce", "greeting"]
        case .shy:                  boost = ["shyWiggle", "wave"]
        case .mischievous:          boost = ["curiousLook", "inspectFoot"]
        default:                    boost = []
        }
        guard !boost.isEmpty else { return weights }
        return weights.map { ($0.0, boost.contains($0.0) ? $0.1 + 2 : $0.1) }
    }

    // MARK: - Home environment (universal 2.5D engine)

    let environment = HomeEnvironment()
    /// The perspective playfield this Home uses — the active family's tuned
    /// shape once an environment activates, `.standard` otherwise.
    private(set) var playfield = HomeEnvironment.Playfield.standard
    /// THE authoritative logical position on the walkable ground. Everything
    /// renders one-way from this — never from the creature's already-rendered
    /// screen position, which is what caused the drag feedback loop.
    ///
    ///     (depth 0…1, across -1…1)
    ///         -> row foot line + row width
    ///         -> foot contact point
    ///         -> creature position (foot + scaled foot offset)
    ///         -> creature scale
    ///         -> shadow weight
    struct PlayfieldPosition { var depth: CGFloat; var across: CGFloat }
    private var fieldPos = PlayfieldPosition(depth: 0.62, across: 0)
    /// Home rest spot on the field.
    private let fieldHome = PlayfieldPosition(depth: 0.62, across: 0)
    var creatureDepth: CGFloat { fieldPos.depth }
    /// Grab relationship captured ONCE at drag start (foot point − touch), so
    /// scale changes never shift the perceived grip.
    private var carryGrabOffset = CGPoint.zero
    private var lastFieldDragPoint: CGPoint?

    /// One-way render of a field position (pure — no reads of rendered state).
    private func fieldRender(_ fp: PlayfieldPosition)
        -> (position: CGPoint, scale: CGFloat) {
        let d = min(max(fp.depth, 0), 1)
        let a = min(max(fp.across, -1), 1)
        var scale = creatureScale * playfield.scaleMultiplier(depth: d)
        // COMPACT-HEIGHT FIT (2026-09-18): width-only sizing let a
        // shortened stage — the hatch reveal with the Birth-Charm card
        // on compact-height phones — crop the crown out of the frame.
        // Clamp the RENDERED scale at THIS depth so the standing
        // creature (feet on the line, crown including the worn hair's
        // overshoot) keeps `stageFitClearance` below the stage top:
        // footY(d) + rise·scale ≤ h/2 − clearance. Depth-local and
        // continuous, and it only ever reduces — on full-height stages
        // the clamp sits far above the width sizing, so approved Home /
        // iPad compositions are untouched by construction.
        if size.height > 1, let rise = creature?.crownRiseAboveFeet(),
           rise > 0 {
            let room = size.height / 2 - Self.stageFitClearance
                - playfield.footY(depth: d, sceneSize: size)
            if room > 0 { scale = min(scale, room / rise) }
        }
        let footX = a * playfield.halfWidth(depth: d, sceneSize: size)
        let footY = playfield.footY(depth: d, sceneSize: size)
        return (CGPoint(x: footX, y: footY + footOffset(atScale: scale)), scale)
    }

    /// Immediate application (drag-grade: finger-attached, zero smoothing).
    private func applyFieldPosition() {
        guard let creature, environment.isActive else { return }
        let r = fieldRender(fieldPos)
        creature.position = r.position
        creature.setScale(r.scale)
        creature.applyDepthShadow(
            alpha: playfield.shadowAlphaMultiplier(depth: fieldPos.depth),
            scale: playfield.shadowScaleMultiplier(depth: fieldPos.depth))
    }

    /// Project a FOOT-space scene point into field coordinates. `across` is
    /// normalized to the row's width, so a diagonal drag toward the horizon
    /// converges naturally instead of snapping between absolute X clamps.
    private func fieldProject(footPoint pt: CGPoint) -> PlayfieldPosition {
        let d = playfield.depth(forFootY: pt.y, sceneSize: size)
        let half = max(playfield.halfWidth(depth: d, sceneSize: size), 1)
        return PlayfieldPosition(depth: d,
                                 across: min(max(pt.x / half, -1), 1))
    }

    // MARK: - Movement-driven facing (front/back, launch scope 2026-09-14)

    /// Dead zones for the facing rule. The environment's away-axis is FIELD
    /// DEPTH — verified against `Playfield.footY` (= lerp(farY, nearY,
    /// depth)): depth 0 is the far row high on screen, depth 1 the near row
    /// at the bottom, so depth DECREASING means moving away from the user.
    /// Without an environment the away-axis is scene Y (up-screen = away).
    /// Travel whose away component stays inside the dead zone keeps the
    /// current facing — mostly-horizontal moves can never flicker.
    private static let orientDepthDeadZone: CGFloat = 0.06   // ≈33 pt vertical
    private static let orientPointDeadZone: CGFloat = 26     // scene points

    /// THE facing decision — one owner, called at MOVE LAUNCH (never per
    /// frame) with the travel's away-axis component. Swaps only when the
    /// wanted facing differs; the dead zone returns nil (= keep). Skipped
    /// while carried (grabs force front), during the shake flail (the dizzy
    /// show stays front through its careening hops), and while dancing
    /// (performances stay front).
    private func orientForTravel(awayDelta: CGFloat, deadZone: CGFloat) {
        // ANY new movement cancels a pending post-arrival front turn —
        // the newest move owns the facing story from here (a back-facing
        // arrival will schedule its own fresh return).
        removeAction(forKey: "arrivalFace")
        guard let creature, !creature.isCarried, !creature.isDancing,
              action(forKey: "flail") == nil else { return }
        let wanted: AurieOrientation? = awayDelta > deadZone ? .back
            : awayDelta < -deadZone ? .front : nil
        guard let wanted, wanted != creature.orientation else { return }
        creature.setOrientation(wanted)
    }

    /// Interactions that read on the face turn the Aurie to FRONT first.
    /// Movement decisions can turn it back afterwards; this is a reset, not
    /// a pin.
    private func faceUserForInteraction() {
        removeAction(forKey: "arrivalFace")   // the interaction wins outright
        guard let creature, creature.orientation != .front else { return }
        creature.setOrientation(.front)
    }

    /// ARRIVAL-IDLE BEAT: a move that leaves the Aurie showing its back
    /// lingers there just long enough to read, then it turns around to
    /// face the user. ONE keyed scene action owns the wait — a newer
    /// movement or interaction replaces/cancels it, so repeated wandering
    /// can never stack timers — and the turn itself re-checks at fire
    /// time that the creature is genuinely idle, so a stale callback can
    /// never override a carry, dance, reaction, flail, touch, or a move
    /// still in flight. Called at move launch with that move's travel
    /// time; no-op unless the move ended back-facing.
    private static let arrivalFaceDelay: TimeInterval = 1.0
    private func scheduleArrivalFaceReturn(travel: TimeInterval) {
        guard let creature, creature.orientation == .back else { return }
        removeAction(forKey: "arrivalFace")
        run(.sequence([
            .wait(forDuration: travel + Self.arrivalFaceDelay),
            .run { [weak self] in
                guard let self, let creature = self.creature,
                      creature.orientation == .back,
                      !creature.isCarried, !creature.isDancing,
                      creature.currentReaction == nil, !self.userTouching,
                      self.action(forKey: "flail") == nil,
                      creature.action(forKey: "hopArc") == nil,
                      creature.action(forKey: "depthShift") == nil
                else { return }        // not idle: drop, never reschedule
                creature.setOrientation(.front)
            },
        ]), withKey: "arrivalFace")
    }

    /// Activate the featured family's environment when its art is complete;
    /// otherwise Home keeps the existing gradient. The DEBUG grey-box flag
    /// forces the mechanics rig for validation.
    private func setupEnvironment() {
        guard mode == .play else { return }
        addChild(environment)
        #if DEBUG
        if ProcessInfo.processInfo.environment["AURIE_ENV_GREYBOX"] == "1" {
            environment.activateGreyBox(in: self)
            if ProcessInfo.processInfo.environment["AURIE_ENV_ZONES"] == "1" {
                drawZoneOverlays()
            }
            startEnvironmentDemoIfRequested()
            startDanceDemoIfRequested()
        }
        #endif
        if !environment.isActive {
            var family = aurie.family
            #if DEBUG
            // Capture aid: force a specific family's environment regardless
            // of the featured creature (AURIE_ENV_FAMILY=moss).
            if let raw = ProcessInfo.processInfo.environment["AURIE_ENV_FAMILY"],
               let forced = AuraFamily(rawValue: raw) {
                family = forced
            }
            #endif
            if environment.activate(family: family, in: self),
               let config = HomeEnvironment.FamilyEnvironment.registry[family] {
                playfield = config.playfield
            }
            // Ambient environment life — HOME ONLY. Calm Mode has its own
            // night sky and deliberately stays still, and the hatch reveal
            // must not compete with the newborn.
            // The aura is additive, so it has to be re-weighted for how
            // bright this family's backdrop is — otherwise it reads strongly
            // on Dusk and vanishes on Stone.
            if environment.isActive, let creature {
                creature.applyAuraStrength(
                    backdropLuminance: environment.backdropLuminance)
            }
            if mode == .play, environment.isActive, !Self.ambientSuppressed {
                let node = FamilyAmbientNode(family: family, sceneSize: size,
                                             skyLayer: environment.skyLayer)
                node.onVisitorMove = { [weak self] point in
                    self?.watchAmbientVisitor(point)
                }
                ambient = node
                addChild(node)
            }
        }
        if environment.isActive {
            // Enter the perspective field at the home spot, feet on the
            // ground plane. COMPACT-HEIGHT FIT second pass (2026-09-18):
            // on a height-constrained stage the home spot pins the feet
            // near MID-frame, which starved the fit clamp from above and
            // shrank the creature to ~half the stage's real capacity —
            // so the ENTRY walks nearer (feet lower) just far enough
            // that the width-sized creature fits whole. Full-height
            // stages fit at the home spot and never move.
            applyCreatureScale()   // idempotent; entry needs the scale
            fieldPos = entryFieldPosition()
            applyFieldPosition()
            #if DEBUG
            logHomeGeometry()
            logFitIfRequested()
            startEnvironmentDemoIfRequested()
            startDanceDemoIfRequested()
            #endif
        }
        #if DEBUG
        if let config = HomeEnvironment.FamilyEnvironment.registry[aurie.family],
           !config.isComplete {
            NSLog("AURIE_ENV family=%@ awaiting art: %@", aurie.family.rawValue,
                  config.missingAssets.joined(separator: ", "))
        }
        #endif
    }

    // The four equipment resolvers now live in `AurieEquipmentRender` so
    // the STILL-PORTRAIT path (Auries grid, widget, Settings thumbnail)
    // uses the exact same source of truth as Home. Before 2026-09-21 the
    // portrait path passed no charm arguments at all and drew bare
    // creatures. These forwarders keep Home's call sites unchanged.
    private func charmLayerKeys(for a: Aurie) -> [String] {
        AurieEquipmentRender.charmLayerKeys(for: a)
    }
    private func bellyStickerID(for a: Aurie) -> String? {
        AurieEquipmentRender.bellyStickerID(for: a)
    }
    private func auraCharmID(for a: Aurie) -> String? {
        AurieEquipmentRender.auraCharmID(for: a)
    }
    private func floatingCharmID(for a: Aurie) -> String? {
        AurieEquipmentRender.floatingCharmID(for: a)
    }

    /// The creature's foot offset below its node origin at a given total
    /// scale — placement is FOOT-anchored: the feet sit on the ground plane,
    /// never the body centre.
    private func footOffset(atScale scale: CGFloat) -> CGFloat {
        AssetLoader.collisionHalfHeightDown * scale
    }

    /// Move to a field position. Animated moves ease position AND scale
    /// together over the same curve, shadow easing alongside — continuous by
    /// construction, no bands or thresholds.
    func setFieldPosition(depth: CGFloat, across: CGFloat? = nil,
                          animated: Bool = true,
                          duration: TimeInterval = 0.5) {
        guard let creature, environment.isActive else { return }
        let newDepth = min(max(depth, 0), 1)
        orientForTravel(awayDelta: fieldPos.depth - newDepth,
                        deadZone: Self.orientDepthDeadZone)
        fieldPos.depth = newDepth
        if let across { fieldPos.across = min(max(across, -1), 1) }
        let r = fieldRender(fieldPos)
        creature.removeAction(forKey: "depthShift")
        if animated {
            let move = SKAction.move(to: r.position, duration: duration)
            move.timingMode = .easeInEaseOut
            let grow = SKAction.scale(to: r.scale, duration: duration)
            grow.timingMode = .easeInEaseOut
            creature.run(.group([move, grow]), withKey: "depthShift")
        } else {
            creature.position = r.position
            creature.setScale(r.scale)
        }
        creature.applyDepthShadow(
            alpha: playfield.shadowAlphaMultiplier(depth: fieldPos.depth),
            scale: playfield.shadowScaleMultiplier(depth: fieldPos.depth),
            duration: animated ? duration * 0.8 : 0)
        scheduleArrivalFaceReturn(travel: animated ? duration : 0)
    }

    func setCreatureDepth(_ depth: CGFloat, animated: Bool = true) {
        setFieldPosition(depth: depth, animated: animated)
    }

    /// A hop expressed in field terms: the target field position is committed
    /// AT LAUNCH (single owner — no post-hoc adoption), the arc plays to its
    /// rendered point while scale eases in parallel, and the depth shadow
    /// re-asserts after the hop's own landing choreography.
    func sceneHop(to point: CGPoint, hopHeight: CGFloat? = nil,
                  duration: TimeInterval? = nil) {
        guard let creature else { return }
        guard environment.isActive else {
            let target = clampedToPlayArea(point)
            // Facing decided BEFORE the hop so its choreography lands on
            // the new rig. Up-screen = away in the flat Home too.
            orientForTravel(awayDelta: target.y - creature.position.y,
                            deadZone: Self.orientPointDeadZone)
            let dist = hypot(target.x - creature.position.x,
                             target.y - creature.position.y)
            creature.hop(to: target, hopHeight: hopHeight, duration: duration)
            // Mirrors hop's own duration formula when none was passed.
            scheduleArrivalFaceReturn(
                travel: duration ?? (0.32 + 0.20 * min(dist / 420, 1)))
            return
        }
        let scaleNow = creatureScale * playfield.scaleMultiplier(depth: fieldPos.depth)
        let foot = CGPoint(x: point.x, y: point.y - footOffset(atScale: scaleNow))
        let newFP = fieldProject(footPoint: foot)
        // Away-axis = field depth, which DECREASES toward the horizon.
        orientForTravel(awayDelta: fieldPos.depth - newFP.depth,
                        deadZone: Self.orientDepthDeadZone)
        fieldPos = newFP
        let r = fieldRender(fieldPos)
        let dist = hypot(r.position.x - creature.position.x,
                         r.position.y - creature.position.y)
        let travel = duration ?? (0.32 + 0.20 * min(dist / 420, 1))
        creature.hop(to: r.position, hopHeight: hopHeight, duration: travel)
        creature.removeAction(forKey: "depthShift")
        let grow = SKAction.scale(to: r.scale, duration: travel)
        grow.timingMode = .easeInEaseOut
        creature.run(grow, withKey: "depthShift")
        // The hop's own land choreography restores the REST shadow; once it
        // finishes, the row's depth weight re-asserts with a soft ease.
        creature.run(.sequence([.wait(forDuration: travel + 0.45),
                                .run { [weak self] in
            guard let self else { return }
            creature.applyDepthShadow(
                alpha: self.playfield.shadowAlphaMultiplier(depth: self.fieldPos.depth),
                scale: self.playfield.shadowScaleMultiplier(depth: self.fieldPos.depth),
                duration: 0.2)
        }]), withKey: "shadowDepthFix")
        scheduleArrivalFaceReturn(travel: travel)
    }

    /// Hop back to the Home rest spot on the field (the compact-fit
    /// entry spot when the stage is height-constrained, so a post-
    /// interaction hop never returns the creature to a spot where the
    /// clamp would shrink it).
    private func sceneHopHome() {
        let r = fieldRender(entryFieldPosition())
        sceneHop(to: r.position)
    }

    /// Vertical room (scene pt) between the foot line at `depth` and
    /// the stage top minus `stageFitClearance` — what the clamp allows.
    private func fitRoom(at depth: CGFloat) -> CGFloat {
        size.height / 2 - Self.stageFitClearance
            - playfield.footY(depth: depth, sceneSize: size)
    }

    /// True when the width-sized creature, standing at `depth`, keeps
    /// `stageFitClearance` below the stage top.
    private func widthSizedCreatureFits(at depth: CGFloat) -> Bool {
        guard let rise = creature?.crownRiseAboveFeet(), rise > 0,
              size.height > 1 else { return true }
        let scale = creatureScale * playfield.scaleMultiplier(depth: depth)
        return rise * scale <= fitRoom(at: depth)
    }

    /// The rest/entry spot. ENGAGES only when resting at the home spot
    /// would clamp the creature below HALF the stage (second-pass rule:
    /// the card-shortened SE reveal engages; the approved no-card SE
    /// reveal and every full-height stage rest at home untouched).
    /// When engaged, walk nearer only until the width-sized creature
    /// fits whole OR the clamped presentation reaches the target share
    /// of the stage — short bodies stop early at their natural size,
    /// tall ones land mid-band instead of pressed against the near
    /// line.
    private func entryFieldPosition() -> PlayfieldPosition {
        guard size.height > 1,
              !widthSizedCreatureFits(at: fieldHome.depth),
              fitRoom(at: fieldHome.depth)
                  < Self.compactEntryEngageShare * size.height
        else { return fieldHome }
        var d = fieldHome.depth
        while d < 1 {
            d = min(1, d + 0.05)
            if widthSizedCreatureFits(at: d)
                || fitRoom(at: d)
                    >= Self.compactEntryTargetShare * size.height {
                break
            }
        }
        return PlayfieldPosition(depth: d, across: fieldHome.across)
    }

    #if DEBUG
    /// AURIE_FIT_LOG=1 — measured RESting reveal geometry in scene
    /// points (bob-independent: derived from the foot line, not the
    /// animated node position), logged once the entry has settled.
    private func logFitIfRequested() {
        guard ProcessInfo.processInfo
            .environment["AURIE_FIT_LOG"] == "1" else { return }
        run(.sequence([.wait(forDuration: 3.0), .run { [weak self] in
            guard let self, let creature = self.creature else { return }
            let scale = creature.xScale
            let rendered = creature.crownRiseAboveFeet() * scale
            let footY = self.playfield.footY(depth: self.fieldPos.depth,
                                             sceneSize: self.size)
            let h = self.size.height
            NSLog("AURIE_FIT stageH=%.0f body=%@ hair=%@ depth=%.2f renderedH=%.0f topClear=%.0f bottomClear=%.0f pct=%.0f%%",
                  h, self.aurie.body.rawValue,
                  self.aurie.resolvedHairStyle, self.fieldPos.depth,
                  rendered, h / 2 - (footY + rendered), h / 2 + footY,
                  100 * rendered / h)
        }]), withKey: "fitLog")
    }
    #endif

    #if DEBUG
    /// Scripted validation for the perspective rig: near -> half -> far ->
    /// far corners -> near corners -> the "foreground greeting" run (far to
    /// near through the plane, then a wave). `AURIE_ENV_DEMO=1`.
    private func startEnvironmentDemoIfRequested() {
        guard ProcessInfo.processInfo.environment["AURIE_ENV_DEMO"] == "1",
              let creature, action(forKey: "envDemo") == nil else { return }
        creature.removeAction(forKey: "blinkLoop")
        // The demo owns the field exclusively: autonomous idle beats (e.g. a
        // greeting walk) would otherwise race the scripted positions and
        // contaminate corner captures.
        removeAction(forKey: "idleMoments")
        var steps: [SKAction] = []
        var clock: TimeInterval = 0
        func at(_ t: TimeInterval, _ label: String, _ work: @escaping () -> Void) {
            steps.append(.wait(forDuration: t - clock)); clock = t
            steps.append(.run { NSLog("AURIE_ENVDEMO %@", label); work() })
        }
        func go(_ depth: CGFloat, _ acrossT: CGFloat) {
            setFieldPosition(depth: depth, across: acrossT, animated: true)
        }
        at(2.0,  "near")      { go(1.0, 0) }
        at(4.5,  "half")      { go(0.5, 0) }
        at(7.0,  "far")       { go(0.0, 0) }
        at(9.5,  "farleft")   { go(0.0, -1) }
        at(11.5, "farright")  { go(0.0, 1) }
        at(13.5, "nearleft")  { go(1.0, -1) }
        at(15.5, "nearright") { go(1.0, 1) }
        at(18.0, "greetstart") { go(0.15, 0.2) }
        at(20.5, "greetmid")   { go(0.55, 0.1) }
        at(22.5, "greetnear")  { go(0.95, 0) }
        at(24.5, "greetwave")  { creature.littleWave(big: true, side: 1) }
        run(.sequence(steps), withKey: "envDemo")
    }

    /// Draw the walkable polygon + depth rungs + zones (grey-box aid).
    private func drawZoneOverlays() {
        // The perspective polygon itself.
        let poly = playfield.polygon(sceneSize: size)
        let path = CGMutablePath()
        path.addLines(between: poly + [poly[0]])
        let shape = SKShapeNode(path: path)
        shape.strokeColor = .green
        shape.lineWidth = 2.5
        shape.zPosition = 71
        addChild(shape)
        // Depth rungs at 0, 0.25, 0.5, 0.75, 1 with labels.
        for d in [CGFloat(0), 0.25, 0.5, 0.75, 1.0] {
            let half = playfield.halfWidth(depth: d, sceneSize: size)
            let y = playfield.footY(depth: d, sceneSize: size)
            let rung = SKShapeNode(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: -half, y: y))
                p.addLine(to: CGPoint(x: half, y: y))
                return p
            }())
            rung.strokeColor = .green
            rung.alpha = 0.5
            rung.lineWidth = 1
            rung.zPosition = 71
            let label = SKLabelNode(text: String(format: "d=%.2f", d))
            label.fontSize = 11
            label.fontName = "Menlo-Bold"
            label.fontColor = .green
            label.position = CGPoint(x: half + 6, y: y - 4)
            label.horizontalAlignmentMode = .left
            rung.addChild(label)
            addChild(rung)
        }
        // The airborne band zones.
        for zone in [HomeEnvironment.Zone.skyEvent, .airEvent, .foregroundPass] {
            let rect = HomeEnvironment.zoneRect(zone, sceneSize: size,
                                                playfield: playfield)
            let z = SKShapeNode(rect: rect)
            z.strokeColor = .cyan
            z.lineWidth = 1.5
            z.alpha = 0.5
            z.zPosition = 70
            let label = SKLabelNode(text: zone.rawValue)
            label.fontSize = 13
            label.fontName = "Menlo-Bold"
            label.fontColor = .cyan
            label.position = CGPoint(x: rect.minX + 8, y: rect.maxY - 18)
            label.horizontalAlignmentMode = .left
            z.addChild(label)
            addChild(z)
        }
    }
    #endif

    // MARK: - Play toys (Play Shelf pass)

    let toyBox = ToyBox()
    /// One noticeable creature beat at a time, shared between the autonomous
    /// scheduler and toy-triggered responses so they can never stack.
    private var lastCreatureBeatAt: TimeInterval = 0
    private var lastChaseAt: TimeInterval = 0
    private var userTouching = false

    /// The stylised floor toys rest on: the creature's home foot line.
    /// Where a toy sitting at `depth` belongs: its floor line, its render
    /// scale, and how wide its field is there. Depth motion needs all three
    /// TOGETHER — a ball kicked away has to rise up-screen, shrink, and find
    /// narrower walls, or it slides out of the perspective the playfield
    /// establishes for everything else.
    ///
    /// Walls are deliberately NOT `playfield.halfWidth`: that is the
    /// creature's walkable corridor (13-21% of width) and would pen the ball
    /// into a narrow strip. The ball gets most of the frame, narrowing with
    /// distance by the same ratio.
    func toyField(depth: CGFloat) -> (floorY: CGFloat, scale: CGFloat,
                                      halfWidth: CGFloat) {
        let d = min(max(depth, 0), 1)
        guard environment.isActive else {
            return (toyGroundY, 1, size.width / 2 - 10)
        }
        let narrow = 0.58 + 0.42 * d
        return (playfield.footY(depth: d, sceneSize: size),
                playfield.scaleMultiplier(depth: d),
                (size.width / 2 - 10) * narrow)
    }

    /// The depth the creature itself stands at, for toys that want to know
    /// whether they are in front of it or behind.
    var toyCreatureDepth: CGFloat { environment.isActive ? creatureDepth : 0.7 }

    var toyGroundY: CGFloat {
        if environment.isActive {
            return playfield.footY(depth: creatureDepth, sceneSize: size)
        }
        return -AssetLoader.collisionHalfHeightDown * creatureScale
    }

    /// Shelf entry point. Selecting a toy swaps it in; selecting the active
    /// toy (or nil) puts it away. Play mode only — Calm stays quiet.
    func setActiveToy(_ toy: PlayToy?) {
        guard mode == .play else { return }
        removeAction(forKey: "toyPlay")
        starCaughtThisSession = false
        endDance()                 // a toy swap always wins over the dance
        if let toy, toyBox.active != toy {
            toyBox.activate(toy, in: self)
            toyEvent(.selected(toy.activity))
        } else {
            let hadToy = toyBox.active != nil
            toyBox.deactivate()
            creature?.interruptIdleBehavior()   // everything eases home
            if hadToy { toyEvent(.deselected) }
        }
    }

    // MARK: - Toy talk

    #if DEBUG
    private static let toyTalkLog = ProcessInfo.processInfo.environment["AURIE_TOY_LOG"] == "1"
    #endif

    /// Forward a play event to the dialogue director and voice its answer.
    func toyEvent(_ event: ToyEvent) {
        guard mode == .play else { return }
        let now = CACurrentMediaTime()
        var rng = SystemRandomNumberGenerator()
        if let line = toyTalk.handle(event, now: now, using: &rng) {
            voice(line, now: now)
            return
        }
        #if DEBUG
        if Self.toyTalkLog {
            NSLog("AURIE_TOYTALK event=%@ silent", String(describing: event))
        }
        #endif
    }

    /// Per frame: the delayed start line and the occasional ambient line.
    private func tickToyTalk(_ now: TimeInterval) {
        guard mode == .play else { return }
        var rng = SystemRandomNumberGenerator()
        if let line = toyTalk.tick(now: now, using: &rng) { voice(line, now: now) }
    }

    private func voice(_ line: ToyLine, now: TimeInterval) {
        let shown = onToyLine?(line.text) ?? false
        if !shown { toyTalk.refused(line, now: now) }
        #if DEBUG
        if Self.toyTalkLog {
            NSLog("AURIE_TOYTALK %@ start=%d \"%@\"",
                  shown ? "shown" : "refused", line.isStart ? 1 : 0, line.text)
        }
        #endif
    }

    // MARK: - Radio / dance director

    /// The music box. Owns its own audio and beat clock; everything the
    /// CREATURE does about the music is decided here.
    let radio = RadioBox()

    /// When the director may next act (also used to land the first dance step
    /// ON a beat rather than wherever the frame happened to fall).
    private var danceNextAt: TimeInterval = 0
    private var lastDanceMove: AurieNode.DanceMove?
    private var noticedMusic = false
    /// Stone: true while it is quietly tapping, so catching it can embarrass it.
    private(set) var stoneIsTapping = false
    private var stoneRefusedAt: TimeInterval = 0

    /// Shelf entry point for the radio, mirroring `setActiveToy`.
    func setRadio(out: Bool) {
        guard mode == .play else { return }
        if out {
            guard !radio.isOut else { return }
            radio.bringOut(in: self, at: radioSpot())
            noticedMusic = false
            danceNextAt = 0
        } else {
            endDance()
            radio.putAway()
            toyEvent(.radioOff)
        }
    }

    /// Play/pause from the radio's own control (or the shelf).
    func toggleRadio() {
        guard radio.isOut else { return }
        if radio.togglePlay() {
            noticedMusic = false            // notice the music again
            danceNextAt = 0
            toyEvent(.radioOn)
        } else {
            endDance()
            toyEvent(.radioOff)
        }
    }

    func radioNextTrack() {
        guard radio.isOut else { return }
        endDance()
        radio.nextTrack()
        noticedMusic = false
        danceNextAt = 0
        if radio.isPlaying { toyEvent(.radioTrackChanged) }
    }

    /// Where the radio sits: the play area's bottom-LEFT corner, with the
    /// bottom of its charcoal plinth on the SAME line as the bottom of the
    /// Play Shelf button in the bottom-right one. Screen-anchored rather than
    /// placed on the ground, so the pair reads as a matching set and the radio
    /// never wanders into the walking corridor behind the Aurie.
    private func radioSpot() -> CGPoint {
        let inset: CGFloat = 8                  // matches the shelf's edge padding
        // The shelf button's 10pt padding is measured against the play VIEW,
        // while this is scene space, whose bottom edge sits a little below the
        // visible play area. 15pt is the measured equivalent that puts the two
        // bottoms on one line.
        let shelfBottomInset: CGFloat = 15
        // The sprite is taller than the radio — antenna above, feet and ground
        // shadow below — so seat it by its visual BASE, not its bounding box.
        return CGPoint(x: -size.width / 2 + inset + RadioBox.footprint.width / 2,
                       y: -size.height / 2 + shelfBottomInset - RadioBox.baseMargin
                          + RadioBox.footprint.height / 2)
    }

    /// Stop dancing and hand the face back to the saved expression. The single
    /// exit used by every interruption: touch, carry, toy swap, radio off.
    func endDance() {
        guard let creature else { return }
        let wasDancing = creature.isDancing || stoneIsTapping
        stoneIsTapping = false
        creature.stopDancing()
        if wasDancing {
            creature.adoptBaseExpression(aurie.resolvedBaseExpression)
        }
        danceNextAt = CACurrentMediaTime() + 0.6
    }

    /// Per-frame director. Quiet by construction: it only acts at `danceNextAt`
    /// and always schedules the next decision on a beat boundary.
    private func tickDance(_ now: TimeInterval) {
        guard radio.isPlaying, let creature, mode == .play,
              !creature.isCarried, !userTouching,
              !creature.isDancing,
              creature.currentReaction == nil,
              action(forKey: "flail") == nil,
              creature.action(forKey: "hopArc") == nil,
              now >= danceNextAt else { return }

        // 1. Notice the radio first — a look and a small reaction, never an
        // instant dance, so it reads as hearing the music start.
        if !noticedMusic {
            noticedMusic = true
            let dx = radio.position.x - creature.position.x
            creature.sparkleGlance(dx: dx * 0.05, dy: -2, hold: 1.0, out: 0.25)
            if aurie.family == .stone {
                // Annoyed from the first bar, and it stays that way until the
                // foot starts tapping.
                creature.autonomousExpression(BaseExpression.pouty.rawValue, for: 6)
                maybeRefuseToDance(now)
            } else {
                creature.autonomousExpression(BaseExpression.curious.rawValue, for: 1.8)
            }
            danceNextAt = radio.nextBeat(after: now + 1.7)
            return
        }

        // 2. Stone never picks a dance — it only ever gives in a little.
        if aurie.family == .stone {
            stoneMusicBeat(now)
            return
        }

        // 3. Everyone else: one dance, held for a few measures, then a rest
        // before the next — listening to music, not cycling a demo reel.
        let move = pickDance()
        let length = startDance(move, measures: Int.random(in: 2 ... 3))
        lastDanceMove = move
        let rest = radio.beatInterval * Double(Int.random(in: 2 ... 4))
        danceNextAt = radio.nextBeat(after: now + length + rest)
    }

    /// The ONLY way a dance ever starts. Every caller — the director, Stone's
    /// own beat, and the debug harness — goes through here, so the Stone
    /// exclusion cannot be bypassed by a new entry point later: a Stone Aurie
    /// is silently downgraded to its foot tap whatever was requested.
    @discardableResult
    private func startDance(_ move: AurieNode.DanceMove, measures: Int) -> TimeInterval {
        guard let creature else { return 0 }
        faceUserForInteraction()   // performances play to the viewer
        let allowed: AurieNode.DanceMove = aurie.family == .stone ? .footTap : move
        let length = creature.dance(allowed, beat: radio.beatInterval, measures: measures)
        toyBox.toyLog("dance \(allowed.rawValue) x\(measures)")
        if allowed != .footTap { toyEvent(.danceStarted) }
        #if DEBUG
        if ProcessInfo.processInfo.environment["AURIE_DANCE_LOG"] == "1" {
            NSLog("AURIE_DANCE family=%@ move=%@ measures=%d bpm=%.0f",
                  aurie.family.rawValue, allowed.rawValue, measures, radio.track.bpm)
        }
        if allowed != move {
            NSLog("AURIE_DANCE BLOCKED %@ for stone -> footTap", move.rawValue)
        }
        #endif
        return length
    }

    /// Stone: annoyed by the music, and mostly motionless — except when it
    /// forgets itself and keeps the beat with one foot for a stretch. The
    /// annoyed face is held for as long as it is NOT tapping; while the foot
    /// is going, that face drops (it has stopped minding, which is the joke).
    private func stoneMusicBeat(_ now: TimeInterval) {
        guard let creature else { return }
        let b = radio.beatInterval
        /// Stand there looking unimpressed for a while.
        func sulk(_ beats: ClosedRange<Int>) {
            let span = b * Double(Int.random(in: beats))
            creature.autonomousExpression(BaseExpression.pouty.rawValue,
                                          for: span + 1.5)
            danceNextAt = radio.nextBeat(after: now + span)
        }
        switch Int.random(in: 0 ..< 100) {
        case ..<16:                       // "Absolutely not."
            maybeRefuseToDance(now)
            sulk(10 ... 16)
        case ..<45:                       // just stand there, annoyed
            sulk(8 ... 16)
        default:
            // Gives in: keeps the beat for 5–15 s, however many bars that is
            // at this tempo. The annoyance drops while the foot is going.
            let seconds = Double.random(in: 5 ... 15)
            let bars = max(1, Int((seconds / (b * 4)).rounded()))
            let gap = b * Double(Int.random(in: 6 ... 12))
            stoneIsTapping = true
            toyEvent(.stoneGaveIn)
            // While the foot is going the annoyance drops — Stone has stopped
            // minding, which is the whole joke.
            creature.autonomousExpression(aurie.resolvedBaseExpression.rawValue,
                                          for: b * 4 * Double(bars))
            let length = startDance(.footTap, measures: bars)
            run(.sequence([.wait(forDuration: length),
                           .run { [weak self] in
                               guard let self, let creature = self.creature else { return }
                               self.stoneIsTapping = false
                               // …and it is annoyed again the moment it stops,
                               // for the whole quiet stretch that follows.
                               creature.autonomousExpression(
                                   BaseExpression.pouty.rawValue, for: gap + 1.5)
                           }]), withKey: "stoneTap")
            danceNextAt = radio.nextBeat(after: now + length + gap)
        }
    }

    /// "Me? Dance? No way." — occasional, never every time (the speech policy
    /// upstream also rate-limits it).
    private func maybeRefuseToDance(_ now: TimeInterval) {
        guard let creature else { return }
        creature.autonomousExpression(BaseExpression.pouty.rawValue, for: 3.0)
        guard now - stoneRefusedAt > 14 else { return }
        stoneRefusedAt = now
        toyEvent(.stoneRefused)          // lines live in ToyDialogue.radioStone
    }

    /// Caught mid-tap: the foot stops instantly and Stone looks anywhere else.
    private func stoneCaughtDancing() {
        guard let creature else { return }
        removeAction(forKey: "stoneTap")
        stoneIsTapping = false
        creature.stopDancing()
        creature.autonomousExpression(BaseExpression.shy.rawValue, for: 2.4)
        creature.sparkleGlance(dx: -6, dy: -3, hold: 1.2, out: 0.3)
        toyEvent(.stoneCaught)           // lines live in ToyDialogue.radioStone
        danceNextAt = CACurrentMediaTime() + radio.beatInterval * 8
    }

    #if DEBUG
    /// Choreography gate: brings the radio out, starts the music, and runs
    /// every move in order with a fixed measure count, logging the exact-rest
    /// transform report after each one settles. `AURIE_DANCE_DEMO=1`, or
    /// `AURIE_DANCE_DEMO=<move>` for a single move on repeat (drift check).
    func startDanceDemoIfRequested() {
        // Plain radio soak: bring the radio out and start it, then let the REAL
        // director choose everything. This is how the Stone gate gets tested —
        // the scripted demo below drives moves itself and would mask it.
        // Shake soak: fire the real shake handler on a timer so the depth/size
        // relationship can be measured without a device gesture.
        if ProcessInfo.processInfo.environment["AURIE_SHAKE_DEMO"] == "1" {
            removeAction(forKey: "idleMoments")
            var steps: [SKAction] = []
            for _ in 0 ..< 5 {
                steps += [.wait(forDuration: 4.0),
                          .run { [weak self] in self?.handleShake() },
                          .wait(forDuration: 1.4),
                          .run { [weak self] in
                              guard let self, let creature = self.creature else { return }
                              NSLog("AURIE_SHAKE depth=%.3f scale=%.3f expected=%.3f y=%.0f",
                                    self.fieldPos.depth, creature.xScale,
                                    self.creatureScale * self.playfield
                                        .scaleMultiplier(depth: self.fieldPos.depth),
                                    creature.position.y)
                          }]
            }
            run(.sequence(steps), withKey: "shakeDemo")
        }
        if ProcessInfo.processInfo.environment["AURIE_RADIO_ON"] == "1",
           !radio.isOut {
            removeAction(forKey: "idleMoments")
            setRadio(out: true)
            radio.play()
            toyEvent(.radioOn)
        }
        // Soak variant that exercises the transport the way a user would:
        // next-track, pause, resume. Each of those re-enters the director, so
        // it is what proves the Stone gate holds on every path.
        if ProcessInfo.processInfo.environment["AURIE_RADIO_CYCLE"] == "1" {
            run(.sequence([
                .wait(forDuration: 22), .run { [weak self] in
                    NSLog("AURIE_DANCE CYCLE nextTrack"); self?.radioNextTrack() },
                .wait(forDuration: 22), .run { [weak self] in
                    NSLog("AURIE_DANCE CYCLE pause"); self?.toggleRadio() },
                .wait(forDuration: 6), .run { [weak self] in
                    NSLog("AURIE_DANCE CYCLE resume"); self?.toggleRadio() },
                .wait(forDuration: 22), .run { [weak self] in
                    NSLog("AURIE_DANCE CYCLE nextTrack2"); self?.radioNextTrack() },
            ]), withKey: "radioCycle")
        }
        guard let raw = ProcessInfo.processInfo.environment["AURIE_DANCE_DEMO"],
              let creature, action(forKey: "danceDemo") == nil else { return }
        creature.removeAction(forKey: "blinkLoop")
        removeAction(forKey: "idleMoments")
        setRadio(out: true)
        radio.play()
        noticedMusic = true                 // the demo drives the moves itself
        danceNextAt = .greatestFiniteMagnitude
        let single = AurieNode.DanceMove(rawValue: raw)
        let moves: [AurieNode.DanceMove] = single.map { Array(repeating: $0, count: 6) }
            ?? AurieNode.DanceMove.allCases
        let beat = radio.beatInterval
        var steps: [SKAction] = [.wait(forDuration: 1.2)]
        for move in moves {
            steps.append(.run { [weak self] in
                guard let self, let creature = self.creature else { return }
                NSLog("AURIE_DANCEDEMO begin %@ rest=%@",
                      move.rawValue, creature.debugTransformReport())
                self.startDance(move, measures: 2)
            })
            steps.append(.wait(forDuration: beat * 8 + 1.4))
            steps.append(.run { [weak self] in
                guard let self, let creature = self.creature else { return }
                NSLog("AURIE_DANCEDEMO   end %@ rest=%@",
                      move.rawValue, creature.debugTransformReport())
            })
            steps.append(.wait(forDuration: 0.8))
        }
        run(.sequence(steps), withKey: "danceDemo")
    }
    #endif

    /// Family bias — a weighting, never a restriction (Stone excepted: it has
    /// no normal dance selection at all).
    private func pickDance() -> AurieNode.DanceMove {
        // HARD exclusion, not a weighting: Stone has no normal dance at all.
        // (Its own `pref` below would otherwise leave every normal move at
        // weight 1, which is exactly how a stray caller could make it disco.)
        guard aurie.family != .stone else { return .footTap }
        let pref: [AurieNode.DanceMove]
        switch aurie.family {
        case .ember:     pref = [.breakdance, .jumpShake, .sprinkler]
        case .glow:      pref = [.disco, .floss, .jumpShake]
        case .moss:      pref = [.sprinkler, .jumpShake, .floss]
        case .tide:      pref = [.floss, .sprinkler, .jumpShake]
        case .dusk:      pref = [.disco, .split]
        case .starlight: pref = [.disco, .breakdance, .split, .jumpShake]
        case .stone:     pref = [.footTap]
        }
        var pool: [AurieNode.DanceMove] = []
        for move in AurieNode.DanceMove.allCases where move != .footTap {
            guard move != lastDanceMove else { continue }   // never twice running
            pool += Array(repeating: move, count: pref.contains(move) ? 3 : 1)
        }
        return pool.randomElement() ?? .jumpShake
    }

    /// A creature beat may fire when the user isn't touching, nothing else is
    /// playing, and the last beat was a little while ago. Toy responses run
    /// through the SAME primitives and gate as autonomous life.
    private func canToyBeat(_ now: TimeInterval, minGap: TimeInterval = 5) -> Bool {
        guard let creature, !userTouching, !creature.isCarried,
              creature.currentReaction == nil,
              action(forKey: "flail") == nil,
              creature.action(forKey: "hopArc") == nil,
              now - lastCreatureBeatAt > minGap else { return false }
        return true
    }

    /// Per-frame creature awareness of the active toy. Physical first: the
    /// arms and body do the playing, the pupils support. Every beat runs the
    /// SAME gates as autonomous life, picks from a variety roll so no two
    /// sessions read identically, and ends at exact rest.
    private func updateToyCreatureInteractions(now: TimeInterval) {
        guard let creature else { return }
        switch toyBox.active {
        case .bubble:    bubblePlayBeat(creature, now: now)
        case .ball:      ballPlayBeat(creature, now: now)
        case .star:      starPlayBeat(creature, now: now)
        case .butterfly: butterflyPlayBeat(creature, now: now)
        case nil:        break
        }
        returnHomeIfIdle(creature, now: now)
    }

    private var creatureReach: CGFloat {
        AssetLoader.collisionHalfWidth * creatureScale
    }

    /// After toy play moved the Aurie around, it wanders back to its Home
    /// resting spot once things go quiet — a small playground, not roaming.
    private func returnHomeIfIdle(_ creature: AurieNode, now: TimeInterval) {
        guard creature.position.distance(to: .zero) > 60,
              now - lastCreatureBeatAt > 6.5,
              canToyBeat(now, minGap: 6.5) else { return }
        lastCreatureBeatAt = now
        toyBox.toyLog("return home")
        if environment.isActive { sceneHopHome() }
        else {
            orientForTravel(awayDelta: -creature.position.y,
                            deadZone: Self.orientPointDeadZone)
            let dist = creature.position.distance(to: .zero)
            creature.hop(to: .zero)
            scheduleArrivalFaceReturn(
                travel: 0.32 + 0.20 * min(dist / 420, 1))
        }
    }

    // MARK: Bubble — reach for it with a hand

    private func bubblePlayBeat(_ creature: AurieNode, now: TimeInterval) {
        let reach = creatureReach
        // Drifted onto the body: pops on contact with a pleased squish.
        if let touching = toyBox.bubbleNear(creature.position, within: reach * 0.8) {
            toyBox.pop(touching)
            if canToyBeat(now, minGap: 3) {
                lastCreatureBeatAt = now
                creature.reactBounce()
                creature.autonomousExpression(BaseExpression.happy.rawValue, for: 1.2)
            }
            return
        }
        guard let bubble = toyBox.nearestBubble(to: creature.position),
              canToyBeat(now, minGap: 5) else { return }
        let dx = bubble.position.x - creature.position.x
        let dy = bubble.position.y - creature.position.y
        let up = AssetLoader.collisionHalfHeightUp * creatureScale
        let inReach = abs(dx) < reach + 60 && dy > -40 && dy < up * 1.05
        let highButClose = abs(dx) < reach + 46 && dy >= up * 1.05 && dy < up + 95

        let roll = Int.random(in: 0 ..< 100)
        if inReach, roll < 65 {
            lastCreatureBeatAt = now
            reachForBubble(creature, hop: false)
        } else if highButClose, roll < 55 {
            lastCreatureBeatAt = now
            reachForBubble(creature, hop: true)
        } else if abs(dx) < reach + 130, dy < up + 120 {
            // Just watch this one float by.
            lastCreatureBeatAt = now
            creature.sparkleGlance(dx: dx * 0.06, dy: dy * 0.04, hold: 1.1)
            creature.autonomousExpression(BaseExpression.curious.rawValue, for: 1.8)
            toyBox.toyLog("bubble watch")
            toyEvent(.bubbleWatched)
        }
    }

    /// Lean + reach the near arm at the bubble (with a little hop first when
    /// it floats high). Contact is checked AT THE ARM APEX: still in range
    /// -> pop + happy; drifted off -> an honest miss, watch it float away.
    private func reachForBubble(_ creature: AurieNode, hop: Bool) {
        toyBox.toyLog(hop ? "bubble hop-reach" : "bubble reach")
        removeAction(forKey: "toyPlay")
        var steps: [SKAction] = []
        if hop, let b = toyBox.nearestBubble(to: creature.position) {
            let under = clampedToPlayArea(CGPoint(x: b.position.x,
                                                  y: creature.position.y))
            steps.append(.run { [weak self] in
                self?.sceneHop(to: under, hopHeight: 34, duration: 0.3) })
            steps.append(.wait(forDuration: 0.55))
        }
        steps.append(.run { [weak self] in
            guard let self, let b = self.toyBox.nearestBubble(to: creature.position)
            else { return }
            creature.sparkleGlance(dx: (b.position.x - creature.position.x) * 0.06,
                                   dy: (b.position.y - creature.position.y) * 0.05,
                                   hold: 0.8, out: 0.2)
            creature.armReach(toward: b.position, hold: 0.4)
        })
        steps.append(.wait(forDuration: 0.26))       // arm apex
        steps.append(.run { [weak self] in
            guard let self else { return }
            let reachRadius = self.creatureReach + 74
            if let b = self.toyBox.nearestBubble(to: creature.position),
               b.position.distance(to: creature.position) < reachRadius {
                self.toyBox.pop(b, reason: "hand")
                creature.flashFace(BaseExpression.happy.rawValue, for: 1.0)
                creature.reactBounce()
            } else {
                // Missed — it floated off. A beat of wistful watching.
                self.toyBox.toyLog("bubble miss")
                self.toyEvent(.bubbleMissed)
                creature.autonomousExpression(BaseExpression.curious.rawValue, for: 1.4)
            }
        })
        run(.sequence(steps), withKey: "toyPlay")
    }

    // MARK: Ball — feet low, hands mid/high

    private var lastBatAt: TimeInterval = 0

    /// Ball play reads on the face: a trot up-screen leaves the Aurie
    /// showing its back, and the kick came before the arrival turn could.
    /// Turn to the viewer BEFORE the kick/bat/push choreography starts (a
    /// facing swap rebuilds the joints, so it must never land mid-gesture).
    private func faceBallPlay(_ creature: AurieNode, _ what: String) {
        let wasBack = creature.orientation == .back
        faceUserForInteraction()
        toyBox.toyLog("ball \(what) facing \(wasBack ? "back->front" : "front")")
    }

    private func ballPlayBeat(_ creature: AurieNode, now: TimeInterval) {
        guard let ballPos = toyBox.ballPosition, !toyBox.ballGrabbed else { return }

        // THE BALL CAN NOW BE BEHIND THE CREATURE. Kicking it from here would
        // mean striking backwards through its own body, so no kick, bat or
        // push is allowed while it is back there. Instead the creature walks
        // AROUND it — deeper into the field than the ball — and the ordinary
        // kick takes over next beat, now aimed back toward the viewer.
        if environment.isActive {
            let ballDepth = toyBox.ballFieldDepth
            if ballDepth < fieldPos.depth - 0.06 {
                guard canToyBeat(now, minGap: 0.8) else { return }
                lastCreatureBeatAt = now
                // Only just past it: enough to be behind, not a trek to the
                // horizon where the creature renders tiny.
                let was = fieldPos.depth
                let target = max(ballDepth - 0.07, 0.20)
                let scaleNow = creatureScale
                    * playfield.scaleMultiplier(depth: was)
                let y = playfield.footY(depth: target, sceneSize: size)
                    + footOffset(atScale: scaleNow)
                sceneHop(to: CGPoint(x: ballPos.x, y: y))
                // `was`, NOT fieldPos.depth — sceneHop has already moved the
                // creature by this point, so logging the live value prints
                // the destination and makes the test look wrong.
                toyBox.toyLog(String(format:
                    "ball behind (ball %.2f < aurie %.2f) — going around to %.2f",
                    ballDepth, was, target))
                return
            }
        }

        let reach = creatureReach
        let dx = ballPos.x - creature.position.x
        let dy = ballPos.y - creature.position.y
        let up = AssetLoader.collisionHalfHeightUp * creatureScale

        // NEAR now means near in ALL THREE axes. Screen-space `dx` was a
        // sufficient test while the ball could only travel left and right;
        // with a depth axis a ball at the same x can be halfway down the
        // field, and the creature would kick thin air. Nothing may touch the
        // ball unless it is also alongside it in depth.
        let depthGap = environment.isActive
            ? abs(toyBox.ballFieldDepth - fieldPos.depth) : 0
        let withinDepth = depthGap < 0.10

        // Mid-air ball inside arm range: bat it away with the near hand at
        // the actual contact moment. Faster gate than full beats so the
        // rally feels responsive, still never twice in quick succession.
        if toyBox.ballMoving, now - lastBatAt > 1.6, !userTouching,
           creature.currentReaction == nil,
           withinDepth, abs(dx) < reach + 64, dy > -10, dy < up + 55 {
            lastBatAt = now
            lastCreatureBeatAt = now
            let side: CGFloat = dx >= 0 ? 1 : -1
            let high = dy > up * 0.55
            faceBallPlay(creature, "bat")
            creature.armBat(side: side, up: high)
            creature.sparkleGlance(dx: dx * 0.05, dy: dy * 0.04, hold: 0.5, out: 0.15)
            // Contact at the swing apex — only if the ball is still there.
            removeAction(forKey: "toyPlay")
            run(.sequence([.wait(forDuration: 0.13), .run { [weak self] in
                guard let self, let p = self.toyBox.ballPosition else { return }
                let ddx = p.x - creature.position.x
                let ddy = p.y - creature.position.y
                if abs(ddx) < self.creatureReach + 80, ddy > -20, ddy < up + 70 {
                    self.toyBox.batBall(direction: side, up: high)
                    creature.flashFace(BaseExpression.happy.rawValue, for: 0.9)
                }
            }]), withKey: "toyPlay")
            return
        }

        if toyBox.ballIsResting || toyBox.ballIsSlow {
            if withinDepth, abs(dx) < reach * 0.45, canToyBeat(now, minGap: 1.2),
               Int.random(in: 0 ..< 100) < 30 {
                // Right at the toes: an occasional two-hand push.
                lastCreatureBeatAt = now
                let side: CGFloat = Bool.random() ? 1 : -1
                faceBallPlay(creature, "push")
                creature.twoHandReach(hold: 0.25)
                removeAction(forKey: "toyPlay")
                run(.sequence([.wait(forDuration: 0.24), .run { [weak self] in
                    self?.toyBox.kickBall(direction: side)
                    creature.flashFace(BaseExpression.happy.rawValue, for: 1.0)
                }]), withKey: "toyPlay")
                toyBox.toyLog("ball two-hand push")
            } else if withinDepth, abs(dx) < reach + 46,
                      canToyBeat(now, minGap: 0.9) {
                // The approved foot kick stays the low-ball answer.
                lastCreatureBeatAt = now
                let side: CGFloat = dx >= 0 ? 1 : -1
                // DEPTH: the ball can now be sent down the field as well as
                // across it. Which way is decided by where the ball already
                // is — deep in the field it gets brought back, close to the
                // viewer it gets booted away — so the rally travels both
                // ways instead of drifting to one end and staying there.
                // A third of kicks stay purely sideways, to keep the old
                // left/right rally in the mix.
                let ballDepth = toyBox.ballFieldDepth
                var depth: CGFloat = 0
                if Int.random(in: 0 ..< 100) < 66 {
                    depth = ballDepth > 0.62
                        ? -CGFloat.random(in: 0.20...0.34)   // away
                        :  CGFloat.random(in: 0.16...0.26)   // back toward us
                }
                faceBallPlay(creature, "kick")
                creature.kickFoot(side)
                creature.autonomousExpression(BaseExpression.happy.rawValue, for: 1.4)
                toyBox.kickBall(direction: side, depth: depth)
            } else if !withinDepth || abs(dx) >= reach + 46,
                      canToyBeat(now, minGap: 0.5) {
                // Out of range in x, in depth, or both: trot over. The target
                // closes BOTH gaps — standing alongside in x while still a
                // third of the field away was what let the old approach
                // "arrive" and then kick at nothing.
                lastCreatureBeatAt = now
                let x = ballPos.x - (dx > 0 ? reach * 0.7 : -reach * 0.7)
                var y = creature.position.y
                if environment.isActive {
                    let scaleNow = creatureScale
                        * playfield.scaleMultiplier(depth: fieldPos.depth)
                    y = playfield.footY(depth: toyBox.ballFieldDepth,
                                        sceneSize: size)
                        + footOffset(atScale: scaleNow)
                }
                sceneHop(to: CGPoint(x: x, y: y), hopHeight: 30,
                         duration: 0.26)
            }
        } else if canToyBeat(now, minGap: 0.6) {
            lastCreatureBeatAt = now
            creature.sparkleGlance(dx: dx * 0.05, dy: dy * 0.04, hold: 0.8)
            // A MOVING ball that is out of range used to be watched and
            // nothing more, so the creature stood still through the whole
            // rally it had just started. Go after it.
            if !withinDepth || abs(dx) > reach + 40 {
                let x = ballPos.x - (dx > 0 ? reach * 0.7 : -reach * 0.7)
                var y = creature.position.y
                if environment.isActive {
                    let scaleNow = creatureScale
                        * playfield.scaleMultiplier(depth: fieldPos.depth)
                    y = playfield.footY(depth: toyBox.ballFieldDepth,
                                        sceneSize: size)
                        + footOffset(atScale: scaleNow)
                }
                sceneHop(to: CGPoint(x: x, y: y), hopHeight: 30,
                         duration: 0.26)
            }
        }
    }

    // MARK: Star — continuous attention, reach, rare two-hand catch

    private var starCaughtThisSession = false

    private func starPlayBeat(_ creature: AurieNode, now: TimeInterval) {
        guard let starPos = toyBox.starPosition, toyBox.starGrabbed else { return }
        let reach = creatureReach
        let dx = starPos.x - creature.position.x
        let dy = starPos.y - creature.position.y
        let up = AssetLoader.collisionHalfHeightUp * creatureScale
        let d = starPos.distance(to: creature.position)

        guard now - lastCreatureBeatAt > 2.4, creature.currentReaction == nil
        else { return }

        // The rare catch: star held right at the chest — both hands curl in.
        if !starCaughtThisSession, abs(dx) < 34, dy > -30, dy < up * 0.7 {
            starCaughtThisSession = true
            lastCreatureBeatAt = now
            creature.twoHandReach(hold: 0.7)
            removeAction(forKey: "toyPlay")
            run(.sequence([.wait(forDuration: 0.3), .run { [weak self] in
                self?.toyBox.starBurst()
                creature.flashFace(BaseExpression.delighted.rawValue, for: 1.6)
            }]), withKey: "toyPlay")
            return
        }
        if d < reach + 80 {
            // In range: reach out and touch it — the star answers.
            lastCreatureBeatAt = now
            creature.armReach(toward: starPos, hold: 0.45)
            removeAction(forKey: "toyPlay")
            run(.sequence([.wait(forDuration: 0.24), .run { [weak self] in
                self?.toyBox.starPulse()
                let faces: [BaseExpression] = [.delighted, .happy, .curious]
                creature.flashFace(faces.randomElement()!.rawValue, for: 1.2)
                self?.toyBox.toyLog("star touch")
            }]), withKey: "toyPlay")
        } else if abs(dx) < 60, dy > up + 40 {
            // Held high overhead: look up and stretch for it, tiny hop.
            lastCreatureBeatAt = now
            creature.sparkleGlance(dx: 0, dy: 5, hold: 1.0, out: 0.2)
            creature.armReach(toward: starPos, hold: 0.5)
            creature.hop(to: creature.position, hopHeight: 26, duration: 0.3)
            toyBox.toyLog("star stretch up")
        } else if d < reach + 200, Int.random(in: 0 ..< 100) < 40 {
            // A little far: shuffle a step toward it.
            lastCreatureBeatAt = now
            let step = CGPoint(x: creature.position.x + (dx > 0 ? 70 : -70),
                               y: creature.position.y)
            sceneHop(to: step, hopHeight: 22, duration: 0.28)
            toyBox.toyLog("star approach")
        }
    }

    // MARK: Butterfly — watch, reach, and the little chase

    private func butterflyPlayBeat(_ creature: AurieNode, now: TimeInterval) {
        guard let bPos = toyBox.butterflyPosition,
              action(forKey: "toyPlay") == nil else { return }
        let reach = creatureReach
        let d = bPos.distance(to: creature.position)
        let dx = bPos.x - creature.position.x
        let dy = bPos.y - creature.position.y
        let up = AssetLoader.collisionHalfHeightUp * creatureScale
        guard d < reach + 150, canToyBeat(now, minGap: 7) else { return }

        if now - lastChaseAt > 16 {
            lastChaseAt = now
            lastCreatureBeatAt = now
            butterflyChase(creature)
            return
        }
        lastCreatureBeatAt = now
        if abs(dx) < reach + 70, dy < up * 1.1, Int.random(in: 0 ..< 100) < 55 {
            // Hovering beside: slowly reach — it darts away just before touch.
            toyBox.toyLog("butterfly almost-catch")
            creature.sparkleGlance(dx: dx * 0.06, dy: dy * 0.045, hold: 0.9, out: 0.25)
            creature.autonomousExpression(BaseExpression.curious.rawValue, for: 2.0)
            creature.armReach(toward: bPos, hold: 0.5)
            removeAction(forKey: "toyPlay")
            run(.sequence([.wait(forDuration: 0.20), .run { [weak self] in
                guard let self else { return }
                self.toyBox.butterflyDart(in: self, awayFrom: creature.position)
                creature.flashFace(BaseExpression.happy.rawValue, for: 1.2)
            }]), withKey: "toyPlay")
        } else {
            // Charmed watching (the pass the user liked — kept).
            toyBox.toyLog("watch butterfly")
            creature.sparkleGlance(dx: dx * 0.05, dy: dy * 0.035, hold: 1.2)
            creature.autonomousExpression(BaseExpression.curious.rawValue, for: 2.0)
        }
    }

    /// The 2-4 s playful pursuit: lean -> hop after it -> it darts -> second
    /// hop -> reach up for it -> it escapes upward -> watch it go -> settle
    /// (the idle homing brings the Aurie back afterwards). Every step
    /// re-reads the butterfly's REAL position, so no two chases match.
    private func butterflyChase(_ creature: AurieNode) {
        toyBox.toyLog("chase")
        removeAction(forKey: "toyPlay")
        func hopToward(_ maxStep: CGFloat) -> SKAction {
            .run { [weak self] in
                guard let self, let b = self.toyBox.butterflyPosition else { return }
                let dx = b.x - creature.position.x
                let step = max(-maxStep, min(maxStep, dx))
                let target = CGPoint(x: creature.position.x + step,
                                     y: creature.position.y)
                self.sceneHop(to: target, hopHeight: 30, duration: 0.3)
            }
        }
        let steps: [SKAction] = [
            // Notice + anticipation lean.
            .run { [weak self] in
                guard let self, let b = self.toyBox.butterflyPosition else { return }
                creature.autonomousExpression(BaseExpression.curious.rawValue, for: 3.6)
                creature.sparkleGlance(dx: (b.x - creature.position.x) * 0.06,
                                       dy: 4, hold: 0.6, out: 0.2)
            },
            .wait(forDuration: 0.55),
            hopToward(120),                       // first pursuit beat
            .run { [weak self] in
                guard let self else { return }
                self.toyBox.butterflyDart(in: self, awayFrom: creature.position)
            },
            .wait(forDuration: 0.75),
            hopToward(110),                       // it turned — follow again
            .wait(forDuration: 0.55),
            .run { [weak self] in                  // reach up for it
                guard let self, let b = self.toyBox.butterflyPosition else { return }
                creature.armReach(toward: b, hold: 0.4)
            },
            .wait(forDuration: 0.25),
            .run { [weak self] in                  // it escapes upward
                guard let self else { return }
                self.toyBox.butterflyFlee(in: self)
            },
            .run { [weak self] in                  // watch it go, charmed
                guard let self, let b = self.toyBox.butterflyPosition else { return }
                creature.sparkleGlance(dx: (b.x - creature.position.x) * 0.04,
                                       dy: 5, hold: 1.2)
                creature.flashFace(BaseExpression.happy.rawValue, for: 1.4)
            },
        ]
        run(.sequence(steps), withKey: "toyPlay")
    }

    // MARK: Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let creature else { return }
        let point = touch.location(in: self)
        touchBeganAt = CACurrentMediaTime()
        lastTouchLocation = point
        lastSparkleLocation = point
        // Classify by the PHYSICAL body/limb footprint — never SKNode.contains(),
        // whose accumulated frame includes the aura halo and contact shadow. A
        // tap in the soft halo beside the Aurie is empty play space (→ hop), not
        // a touch on the Aurie.
        startedOnCreature = isOnCreatureBody(point)
        accumulatedDrag = 0
        petTriggeredThisTouch = false
        endNotice()   // fresh gesture: clear any prior finger-notice dwell
        touchLog("began mode=\(mode) scene=(\(Int(point.x)),\(Int(point.y))) "
                 + "onCreature=\(startedOnCreature)")
        userTouching = true

        // The user always wins over the music: any touch ends the dance and
        // eases every posed transform back to exact rest. Catching Stone
        // mid-tap is its own little moment.
        if startedOnCreature, stoneIsTapping {
            stoneCaughtDancing()
        } else if creature.isDancing {
            endDance()
        }

        // A tap on the radio works its own compact controls rather than
        // reaching the creature or the empty-space hop.
        if mode == .play, let control = radio.control(at: point) {
            switch control {
            case .playPause: toggleRadio()
            case .nextTrack: radioNextTrack()
            }
            Haptics.light()
            userTouching = false
            return
        }

        // A touch that lands ON a grabbable toy takes it — the creature's own
        // regions and empty-space meanings are untouched everywhere else.
        if mode == .play, toyBox.grab(at: point, now: CACurrentMediaTime()) {
            creature.interruptIdleBehavior()
            removeAction(forKey: "toyPlay")
            return
        }

        switch mode {
        case .play:
            // Holding still on the creature for a moment lifts it (pick up).
            removeAction(forKey: "carryArm")
            if startedOnCreature {
                // A touch on the body interrupts any autonomous fidget at once.
                creature.interruptIdleBehavior()
                run(.sequence([.wait(forDuration: carryHoldDelay), .run { [weak self] in
                    self?.armCarry()
                }]), withKey: "carryArm")
            }
        case .calm:
            // Holding becomes quiet comfort: lean + soft rhythmic pulses.
            removeAction(forKey: "calmHold")
            if startedOnCreature {
                let dx = point.x - creature.position.x
                run(.sequence([.wait(forDuration: calmHoldDelay), .run { [weak self] in
                    guard let self, self.startedOnCreature, self.accumulatedDrag < 24 else { return }
                    self.calmHolding = true
                    self.removeAction(forKey: "sparkleFlow")
                    self.creature.calmLean(toward: dx)
                    self.startComfortPulses()
                }]), withKey: "calmHold")
            } else {
                // Sparkles flow for as long as the finger is down, even held
                // still — not just while it moves.
                run(.repeatForever(.sequence([
                    .run { [weak self] in
                        guard let self, !self.calmHolding else { return }
                        let jitter = CGPoint(x: self.lastTouchLocation.x + .random(in: -8...8),
                                             y: self.lastTouchLocation.y + .random(in: -8...8))
                        self.spawnSparkle(at: jitter)
                    },
                    .wait(forDuration: 0.12),
                ])), withKey: "sparkleFlow")
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let creature else { return }
        let point = touch.location(in: self)
        accumulatedDrag += hypot(point.x - lastTouchLocation.x, point.y - lastTouchLocation.y)
        lastTouchLocation = point

        // A grabbed toy owns the whole gesture. The star doubles as a wand:
        // the pupils live-track it through the SAME gated glance the finger
        // uses, so the frozen tracking look carries over unchanged.
        if toyBox.dragging {
            let now = CACurrentMediaTime()
            toyBox.drag(to: point, in: self, now: now)
            if toyBox.starGrabbed, now - lastNoticeAt > 0.12 {
                lastNoticeAt = now
                creature.glanceToward(point)
            }
            return
        }

        switch mode {
        case .play:
            if creature.isCarried {
                if environment.isActive {
                    // ONE owner: touch -> foot target -> field coords ->
                    // render. Immediate (finger-attached); nothing else may
                    // write the position while carried.
                    let dx = point.x - (lastFieldDragPoint?.x ?? point.x)
                    lastFieldDragPoint = point
                    let foot = CGPoint(x: point.x + carryGrabOffset.x,
                                       y: point.y + carryGrabOffset.y)
                    fieldPos = fieldProject(footPoint: foot)
                    applyFieldPosition()
                    creature.carryTilt(dx: dx)
                } else {
                    creature.carryMove(to: clampedToPlayArea(point))
                }
            } else if startedOnCreature, !petTriggeredThisTouch, accumulatedDrag > 60 {
                // A deliberate stroke across the creature: pet. The drag
                // threshold is what separates this from a tap and from a
                // finger merely passing NEAR the Aurie.
                removeAction(forKey: "carryArm")
                petTriggeredThisTouch = true
                faceUserForInteraction()   // the content face must show
                creature.interruptIdleBehavior()
                creature.reactPet(toward: point.x - creature.position.x)
                // Eyes soften and the saved face gives way to a content one
                // for the length of the stroke.
                creature.flashFace(BaseExpression.happy.rawValue, for: 1.2)
                emitFamilyPuff(3)
                SoundPlayer.play("sfx_pet")
                if mode == .play { onInteraction?() }
                onReactionLine?({ AurieGenerator.petLine(for: self.aurie, content: ContentService.content) })
            } else if !startedOnCreature {
                // Finger moving through empty Home space near the Aurie: it
                // NOTICES, with a whole-body lean — never a face-distorting
                // fake gaze (the eye pupils are baked into the art). Eases
                // rather than snapping, and never escalates to the dizzy shake
                // no matter how the finger circles.
                touchLog("moved-empty scene=(\(Int(point.x)),\(Int(point.y))) drag=\(Int(accumulatedDrag))")
                noticeFinger(point)
            }
        case .calm:
            // Dragging anywhere trails gentle sparkles; the eyes follow them.
            // 11pt, halved from 22 on 2026-09-25 so a drag trails twice
            // as many sparkles.
            if hypot(point.x - lastSparkleLocation.x, point.y - lastSparkleLocation.y) > 11 {
                lastSparkleLocation = point
                spawnSparkle(at: point)
                creature.lookToward(point)
            }
            if startedOnCreature, !calmHolding, !petTriggeredThisTouch, accumulatedDrag > 50 {
                removeAction(forKey: "calmHold")
                petTriggeredThisTouch = true
                creature.calmLean(toward: point.x - creature.position.x)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let creature else { return }
        let point = touch.location(in: self)
        let now = CACurrentMediaTime()
        userTouching = false

        // Toy gestures resolve first: a grabbed ball/star releases (the ball
        // takes its toss), and a clean tap on a bubble pops it.
        if toyBox.dragging {
            toyBox.release(now: now)
            creature.interruptIdleBehavior()   // pupils, lean, arms ease home
            return
        }
        if mode == .play,
           accumulatedDrag < 18, now - touchBeganAt < carryHoldDelay,
           toyBox.tapPop(at: point) {
            Haptics.light()
            return
        }

        switch mode {
        case .play:
            removeAction(forKey: "carryArm")
            endNotice()                   // relax lean + clear dwell
            if creature.isCarried {
                creature.endCarry()
                lastFieldDragPoint = nil
                if environment.isActive {
                    // Hand control back to the field: settle at the exact
                    // rendered rest for the final logical position.
                    setFieldPosition(depth: fieldPos.depth,
                                     across: fieldPos.across,
                                     animated: true, duration: 0.18)
                } else {
                    SoundPlayer.play("sfx_drop")
                }
                return
            }
            guard !petTriggeredThisTouch else { return }
            let isTap = accumulatedDrag < 18 && now - touchBeganAt < carryHoldDelay
            guard isTap else { return }
            dispatchPlayTap(at: point, now: now)

        case .calm:
            removeAction(forKey: "calmHold")
            removeAction(forKey: "sparkleFlow")
            stopComfortPulses()
            if calmHolding || petTriggeredThisTouch {
                calmHolding = false
                creature.endCalmLean()
                return
            }
            let isTap = accumulatedDrag < 18 && now - touchBeganAt < calmHoldDelay
            guard isTap else {
                run(.sequence([.wait(forDuration: 1.8), .run { [weak self] in
                    self?.creature.lookForward()
                }]), withKey: "lookBack")
                return
            }
            if startedOnCreature {
                creature.calmNod()
            } else {
                // Look toward it, but stay seated.
                creature.lookToward(point)
                run(.sequence([.wait(forDuration: 2.2), .run { [weak self] in
                    self?.creature.lookForward()
                }]), withKey: "lookBack")
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        userTouching = false
        if toyBox.dragging {
            toyBox.release(now: CACurrentMediaTime())
            creature?.endGlance()
        }
        removeAction(forKey: "carryArm")
        removeAction(forKey: "calmHold")
        removeAction(forKey: "sparkleFlow")
        stopComfortPulses()
        endNotice()
        if creature?.isCarried == true {
            creature.endCarry()
            lastFieldDragPoint = nil
            if environment.isActive {
                setFieldPosition(depth: fieldPos.depth, across: fieldPos.across,
                                 animated: true, duration: 0.18)
            }
        }
        if calmHolding {
            calmHolding = false
            creature?.endCalmLean()
        }
    }

    /// A completed play-mode tap. On the Aurie's body it reacts (bounce, or a
    /// giggle on the third quick tap); on empty play space it hops to the tapped
    /// point, clamped so the whole body stays on-screen. A tap beyond the legal
    /// centre range is never rejected — it is clamped to the nearest reachable
    /// landing.
    private func dispatchPlayTap(at point: CGPoint, now: TimeInterval) {
        guard let creature else { return }
        guard let region = creatureRegion(point) else {
            sceneHop(to: point)
            return
        }
        // A tap always wins over an autonomous fidget: stop it and ease limbs
        // home first so the reaction reads cleanly. Tap reactions read on
        // the face, so a back-facing Aurie turns around for them.
        faceUserForInteraction()
        creature.interruptIdleBehavior()
        removeAction(forKey: "toyPlay")   // user beats any toy choreography
        touchLog("tap region=\(region.rawValue) scene=(\(Int(point.x)),\(Int(point.y)))")
        if mode == .play { onInteraction?() }

        // ONE simple, playful reaction per poke — no escalation, no counter,
        // no persistent state. Repeated pokes just retrigger this; the newest
        // squash/face cleanly replaces the last (the shared "motionSquash"
        // key and the reaction timer are the only "cooldown" there is). A poke
        // is never punished and never turns the Aurie sad, pouty or annoyed.
        switch region {
        case .armLeft:
            // Touch an arm -> Aurie waves THAT arm. The one intentional,
            // discoverable way to ask for the wave.
            creature.littleWave(big: true, side: -1)
            creature.flashFace(BaseExpression.happy.rawValue, for: 1.0)
        case .armRight:
            creature.littleWave(big: true, side: 1)
            creature.flashFace(BaseExpression.happy.rawValue, for: 1.0)
        case .head:
            creature.headBoop()                  // clear startled pop-and-settle
            creature.flashFace(BaseExpression.surprised.rawValue, for: 0.8)
        case .belly:
            creature.reactGiggle()               // playful wiggle
            creature.rockSideToSide()
            creature.play(AuriePersonality.positiveReaction(family: aurie.family) {
                Int.random(in: 0 ..< $0)          // Happy / Delighted
            })
        case .footLeft, .footRight:
            creature.kickFoot(region == .footRight ? 1 : -1)
            creature.flashFace(BaseExpression.surprised.rawValue, for: 0.6)
        }
        SoundPlayer.play("sfx_tap")
        Haptics.light()
    }

    /// Finger-notice: the Aurie eases toward a passing finger. Throttled to a
    /// smooth ~8/s (not every 60 Hz frame), and after the finger lingers near
    /// for half a second it also puts on a Curious face — once per gesture.
    private var lastNoticeAt: TimeInterval = 0
    private var noticeBeganAt: TimeInterval = 0
    private var noticedCurious = false
    private func noticeFinger(_ point: CGPoint) {
        let now = CACurrentMediaTime()
        if noticeBeganAt == 0 { noticeBeganAt = now; noticedCurious = false }
        guard now - lastNoticeAt > 0.12 else { return }
        lastNoticeAt = now
        let applied = creature?.glanceToward(point) ?? false
        if applied, !noticedCurious, now - noticeBeganAt > 0.5 {
            noticedCurious = true
            creature?.autonomousExpression(BaseExpression.curious.rawValue, for: 1.8)
        }
        touchLog("notice scene=(\(Int(point.x)),\(Int(point.y))) "
                 + "applied=\(applied) dwell=\(String(format: "%.2f", now - noticeBeganAt))")
    }

    private func endNotice() {
        noticeBeganAt = 0
        noticedCurious = false
        creature?.endGlance()
    }

    /// Temporary input tracing for the real-drag debug (env AURIE_TOUCH_LOG=1).
    private func touchLog(_ msg: @autoclosure () -> String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AURIE_TOUCH_LOG"] == "1" {
            NSLog("AURIE_TOUCH %@", msg())
        }
        #endif
    }

    private func armCarry() {
        guard let creature, startedOnCreature, !creature.isCarried, accumulatedDrag < 24 else { return }
        if environment.isActive {
            // Ground drag through the perspective field: feet stay planted,
            // and the grab relationship is captured ONCE — scale changes
            // can never shift the perceived grip. The field takes EXCLUSIVE
            // position ownership: any hop, depth shift, demo step or toy
            // choreography in flight yields immediately.
            creature.removeAction(forKey: "hopArc")
            creature.removeAction(forKey: "depthShift")
            creature.removeAction(forKey: "shadowDepthFix")
            removeAction(forKey: "envDemo")
            removeAction(forKey: "toyPlay")
            faceUserForInteraction()   // the dangle face must show
            creature.beginCarry(lifted: false)
            let r = fieldRender(fieldPos)
            let foot = CGPoint(x: r.position.x,
                               y: r.position.y - footOffset(atScale: r.scale))
            carryGrabOffset = CGPoint(x: foot.x - lastTouchLocation.x,
                                      y: foot.y - lastTouchLocation.y)
        } else {
            faceUserForInteraction()   // same rule off-environment
            creature.beginCarry()
        }
        creature.setExpression(.surprised)
        Haptics.soft()
        SoundPlayer.play("sfx_pickup")
        onReactionLine?({ AurieGenerator.pickupLine(ContentService.content) })
    }

    /// Home's scene stays alive under a full-screen cover and observes the
    /// same notification. Wonderglobe switches this off while it is presented
    /// so one physical shake drives one reaction, not two.
    var respondsToShake = true

    private func handleShake() {
        guard respondsToShake else { return }
        guard let creature else { return }
        #if DEBUG
        // Every shake the scene acts on, so a "why is it spinning?" report can
        // be traced to a real motion event rather than guessed at.
        NSLog("AURIE_SHAKE_EVENT mode=%@ carried=%d",
              mode == .calm ? "calm" : "play", creature.isCarried ? 1 : 0)
        #endif

        if mode == .calm {
            // Mostly ignored; occasionally the tiniest self-settling wobble.
            if Int.random(in: 0..<4) == 0 { creature.calmWobble() }
            return
        }

        guard !creature.isCarried, action(forKey: "flail") == nil else { return }

        // Fly all over the screen: spin while careening through a chain of
        // fast wild hops to random spots, then settle dizzy.
        // Startled -> dizzy -> recovery -> saved base expression. One call,
        // so Wonderglobe can trigger exactly the same flow later.
        // The whole show is face-forward (startled/dizzy expressions), so a
        // back-facing Aurie turns front first; the "flail" key then keeps
        // movement decisions out of the careening hops.
        faceUserForInteraction()
        creature.playShakeSequence()
        emitFamilyPuff(4)
        var actions: [SKAction] = []
        for _ in 0..<4 {
            actions.append(.run { [weak self] in
                guard let self else { return }
                // Through the FIELD, not a raw hop: each careening landing is
                // projected onto the walkable plane, so the Aurie takes the
                // size and contact shadow of wherever it ends up. A raw hop
                // moved it forward/back while it kept its old size.
                self.sceneHop(to: self.randomPlayPoint(),
                              hopHeight: .random(in: 60...150),
                              duration: 0.22)
            })
            actions.append(.wait(forDuration: 0.24))
        }
        run(.sequence(actions), withKey: "flail")
        onReactionLine?({ AurieGenerator.shakeLine(for: self.aurie, content: ContentService.content) })
    }

    // MARK: Calm helpers

    /// Soft rhythmic haptic while holding (hold-to-comfort). Respects the
    /// system haptics setting automatically.
    private func startComfortPulses() {
        softHaptic.impactOccurred(intensity: 0.5)
        run(.repeatForever(.sequence([
            .wait(forDuration: 1.4),
            .run { [weak self] in self?.softHaptic.impactOccurred(intensity: 0.5) },
        ])), withKey: "comfortPulse")
    }

    private func stopComfortPulses() {
        removeAction(forKey: "comfortPulse")
    }

    private func spawnSparkle(at point: CGPoint) {
        let sparkle = SKSpriteNode(texture: FamilyEffects.trailMotif(for: aurie.family))
        sparkle.position = point
        sparkle.alpha = 0
        sparkle.zPosition = 8
        sparkle.setScale(CGFloat.random(in: 0.5...1.0))
        addChild(sparkle)
        let drift = SKAction.moveBy(x: CGFloat.random(in: -20...20),
                                    y: CGFloat.random(in: 24...48), duration: 2.0)
        drift.timingMode = .easeOut
        let twinkle = SKAction.sequence([
            .fadeAlpha(to: 0.9, duration: 0.2),
            .fadeAlpha(to: 0.5, duration: 0.5),
            .fadeAlpha(to: 0.8, duration: 0.5),
            .fadeOut(withDuration: 0.8),
        ])
        sparkle.run(.group([drift, twinkle, .rotate(byAngle: .random(in: -0.8...0.8), duration: 2.0)]))
        sparkle.run(.sequence([.wait(forDuration: 2.1), .removeFromParent()]))
    }

    // MARK: Proportional creature scale (Stage B)

    /// The visible body+limb width fills this fraction of the play-area width —
    /// a smaller fraction on the roomier iPad so there is ample hop space. Kept
    /// modest so the creature is an *interactive* character with real travel
    /// room, not a screenshot-filling static image.
    // The ONE Aurie visual-sizing system (2026-08-29): body+limb footprint
    // as a fraction of play width, shared by every family. Family must never
    // influence scale — only the shared playfield's depth multiplier does.
    static let bodyFractionCompact: CGFloat = 0.54   // narrow play (iPhone)
    static let bodyFractionRegular: CGFloat = 0.46   // wide play (iPad)
    static let minCreatureScale: CGFloat = 0.40
    static let maxCreatureScale: CGFloat = 1.60
    /// COMPACT-HEIGHT FIT: minimum gap kept between the highest crown
    /// pixel and the stage top — 16 pt of visible clearance plus the
    /// ~10 pt idle-bob rise, so breathing never kisses the edge.
    static let stageFitClearance: CGFloat = 26
    // PRODUCT RULE (frozen 2026-09-18): on compact reveal stages, make
    // the Aurie AS LARGE AS SAFELY POSSIBLE while keeping the complete
    // visible creature inside the scenic frame with the approved
    // top/bottom safety margins. The two shares below are TUNING for
    // that rule — where the compact entry engages and where the walk
    // stops — not product targets: the on-screen percentage any given
    // body/hair reaches is an OUTCOME of its proportions and the
    // stage, and may drift as bodies/hairstyles are added.
    /// Compact ENTRY engages only when resting at home would clamp the
    /// creature below this share of the stage height…
    static let compactEntryEngageShare: CGFloat = 0.50
    /// …and then walks the feet nearer until the clamped presentation
    /// reaches this share (or the width-sized creature fits whole).
    static let compactEntryTargetShare: CGFloat = 0.58
    private var creatureScale: CGFloat = 1

    /// Interpolate the body fraction from the play width (narrow → wide).
    private func targetBodyFraction() -> CGFloat {
        let t = min(max((size.width - 360) / (742 - 360), 0), 1)
        return Self.bodyFractionCompact - t * (Self.bodyFractionCompact - Self.bodyFractionRegular)
    }

    #if DEBUG
    /// One-line geometry audit (AURIE_HOMEGEO): scene size, the shared
    /// playfield lines, and the creature's displayed footprint — the numbers
    /// that must be IDENTICAL across families on a given device.
    private func logHomeGeometry() {
        let s = size
        let farY = playfield.footY(depth: 0, sceneSize: s)
        let nearY = playfield.footY(depth: 1, sceneSize: s)
        let scaleNow = creatureScale * playfield.scaleMultiplier(depth: fieldPos.depth)
        let bodyW = AssetLoader.collisionHalfWidth * 2 * scaleNow
        let bodyH = (AssetLoader.collisionHalfHeightUp
                     + AssetLoader.collisionHalfHeightDown) * scaleNow
        NSLog("AURIE_HOMEGEO family=%@ scene=%.0fx%.0f farY=%.1f nearY=%.1f skyFracInScene=%.3f halfW0=%.1f halfW1=%.1f baseScale=%.3f depth=%.2f bodyW=%.1f bodyH=%.1f",
              aurie.family.rawValue, s.width, s.height, farY, nearY,
              0.5 - Double(playfield.farY),
              playfield.halfWidth(depth: 0, sceneSize: s),
              playfield.halfWidth(depth: 1, sceneSize: s),
              creatureScale, fieldPos.depth, bodyW, bodyH)
    }
    #endif

    private func applyCreatureScale() {
        guard let creature, size.width > 1 else { return }
        // Scale from the physical body+limb footprint (never the aura).
        let footprintWidth = AssetLoader.collisionHalfWidth * 2
        // Calm: the creature is a figure IN the painted clearing, not a
        // portrait — smaller, with breathing room for sky and copy.
        // Calm's approved composition predates the larger Home base size;
        // 1.20 x 0.54 == the frozen 1.38 x 0.47 footprint exactly.
        let calmFactor: CGFloat = mode == .calm ? 1.20 : 1.0
        let target = size.width * targetBodyFraction() * calmFactor
        var s = min(max(target / footprintWidth, Self.minCreatureScale), Self.maxCreatureScale)
        // COMPACT-HEIGHT FIT (2026-09-18), centred-stage half: when the
        // creature is NOT on the walkable field it stands at the scene
        // centre, so cap the scale to keep crown AND feet inside the
        // stage with the visible margin. The FIT WINS over the aesthetic
        // minimum — a complete small creature beats a cropped one. The
        // field-placed half of this rule lives in `fieldRender`, which
        // clamps per depth. Full-height stages never reach either cap,
        // so approved Home / Calm / iPad compositions are untouched.
        if !environment.isActive, size.height > 1 {
            let crownUp = creature.crownRiseAboveFeet()
                - AssetLoader.collisionHalfHeightDown
            let room = size.height / 2 - Self.stageFitClearance
            if room > 0 {
                if crownUp > 0 { s = min(s, room / crownUp) }
                s = min(s, room / AssetLoader.collisionHalfHeightDown)
            }
        }
        creatureScale = s
        if environment.isActive {
            applyFieldPosition()   // one-way re-render at the new metrics
        } else {
            creature.setScale(s)
        }
    }

    /// Re-scale idempotently when SwiftUI relays out the hosting SpriteView.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        applyCreatureScale()
        environment.layout(for: size)
        // COMPACT-HEIGHT FIT: if the creature is resting at the home
        // spot and this (re)layout leaves it height-constrained there,
        // re-seat it at the compact entry spot — covers a first layout
        // pass that ran before the final stage height was known. Never
        // touches a creature the player or wander has moved.
        if environment.isActive, creature != nil,
           fieldPos.depth == fieldHome.depth,
           fieldPos.across == fieldHome.across {
            let entry = entryFieldPosition()
            if entry.depth != fieldPos.depth {
                fieldPos = entry
                applyFieldPosition()
            }
        }
        // The play area grows when the Daily card is dismissed; the radio is
        // anchored to its corner, so it has to be re-seated.
        radio.reposition(to: radioSpot())
    }

    /// The scaled creature's PHYSICAL collision half-extents (body + arms +
    /// feet only) plus a little edge padding. Explicitly excludes aura, contact
    /// shadow, particles, reaction effects, and speech bubbles, so those may
    /// softly approach the boundary without shrinking the travel range.
    private var collisionHalfExtent: (x: CGFloat, y: CGFloat) {
        let padX: CGFloat = 14, padY: CGFloat = 14
        let x = AssetLoader.collisionHalfWidth * creatureScale + padX
        let y = max(AssetLoader.collisionHalfHeightUp, AssetLoader.collisionHalfHeightDown)
              * creatureScale + padY
        return (x, y)
    }

    /// Whether a scene point lands on the Aurie's PHYSICAL body/limbs, centred on
    /// its current position and scaled with it. Uses the same footprint as
    /// collision — deliberately EXCLUDING the aura halo, contact shadow,
    /// particles, and speech bubbles. This is what separates a tap-on-Aurie
    /// (reaction) from a tap on empty play space (hop): the glow beside the
    /// creature is empty space, so a tap there sends it there rather than reading
    /// as touching it. Replaces `SKNode.contains`, whose accumulated frame would
    /// fold the aura and shadow into the hit area.
    private func isOnCreatureBody(_ p: CGPoint) -> Bool {
        creatureRegion(p) != nil
    }

    /// Which part of the Aurie a point lands on, or nil for empty play space.
    /// Resolved by the creature itself from its LIVE sprite frames (arms,
    /// feet, body/tuft), so the zones match the pixels the player sees on
    /// every body type and limb style; the placeholder art keeps the old
    /// footprint-fraction rectangle inside `AurieNode.hitRegion`.
    typealias TouchRegion = AurieNode.Region
    private func creatureRegion(_ p: CGPoint) -> TouchRegion? {
        creature?.hitRegion(p)
    }

    /// Clamp a target so the whole physical creature lands inside the play area
    /// (coordinates are centre-origin because of the anchorPoint).
    private func clampedToPlayArea(_ p: CGPoint) -> CGPoint {
        if environment.isActive {
            // Perspective field: the target's y picks a depth row (foot
            // line), and x clamps to that row's walkable width — the field
            // narrows toward the horizon.
            let scaleNow = creatureScale * playfield.scaleMultiplier(depth: creatureDepth)
            let footTarget = p.y - footOffset(atScale: scaleNow)
            let d = playfield.depth(forFootY: footTarget, sceneSize: size)
            let half = playfield.halfWidth(depth: d, sceneSize: size)
            let scale = creatureScale * playfield.scaleMultiplier(depth: d)
            let y = playfield.footY(depth: d, sceneSize: size)
                + footOffset(atScale: scale)
            return CGPoint(x: min(max(p.x, -half), half), y: y)
        }
        let e = collisionHalfExtent
        let halfW = max(size.width / 2 - e.x, 0)
        let halfH = max(size.height / 2 - e.y, 0)
        return CGPoint(x: min(max(p.x, -halfW), halfW),
                       y: min(max(p.y, -halfH), halfH))
    }

    private func randomPlayPoint() -> CGPoint {
        let e = collisionHalfExtent
        let halfW = max(size.width / 2 - e.x, 10)
        let halfH = max(size.height / 2 - e.y, 10)
        return CGPoint(x: .random(in: -halfW...halfW), y: .random(in: -halfH...halfH))
    }

    private func skColor(_ c: Rgb) -> SKColor {
        SKColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }


    // MARK: - Today's Wonder (Home shake magic)

    /// The shared `.swirl` field, built AROUND THE LIVE HOME CREATURE.
    ///
    /// There is deliberately no second `AurieNode` here: the whole point of
    /// the Home-based design is that the same creature the player has been
    /// looking at is the one the magic happens to. The field is created lazily
    /// on the first shake and torn down when the effect settles, so an idle
    /// Home carries no extra nodes.
    private var wonderSwirl: ParticleField?

    /// True while a Wonder sequence owns the scene.
    private(set) var wonderActive = false

    /// WAKE + BUILD. Wakes the swirl and starts the existing dizzy reaction.
    /// Aurie's Wonder choreography, held as a TEMPORARY OFFSET on top of the
    /// canonical world position. Nothing here writes to the field coordinate,
    /// so no drift can accumulate and `endWonderCarry` restores an exactly
    /// clean transform.
    private var wonderCarry = CGPoint.zero
    private var wonderCarryVel = CGVector.zero
    private var wonderHome = CGPoint.zero
    /// The creature's ACTUAL on-screen scale when the globe started. The
    /// rendered scale is `creatureScale * playfield.scaleMultiplier(depth:)`
    /// (plus the compact-height clamp), so the old `creatureScale` baseline
    /// was ~17% too large at the home depth: the globe animated around the
    /// wrong size and the settle restored the wrong size (2026-09-21).
    private var wonderCapturedScale: CGFloat = 1
    private var wonderPhase: CGFloat = 0
    private var wonderShaking = false
    private var wonderFalling = false
    private var wonderLanded = true

    /// How long the globe will keep churning without a shake-STOP before it
    /// lets go by itself. This does NOT end the globe — it only de-energizes
    /// the field, after which the particles fall, land and fade on their own
    /// clock and the sequence ends the usual way, on `isGlobeFinished`.
    ///
    /// It exists because the wind-down used to hang off the accelerometer and
    /// nothing else: the Home "Snow Globe" chip called `beginWonderSwirl`
    /// directly, no stop ever arrived, so particles stayed energized,
    /// `isGlobeFinished` never became true, `wonderActive` never cleared, and
    /// `stepWonderCarry` rescaled the creature ±10% every frame forever
    /// (2026-09-21). Longer than any real shake, so a player never feels it.
    private static let wonderMaxShakeSeconds: TimeInterval = 12

    func beginWonderSwirl() {
        guard let creature else { return }
        let wasActive = wonderActive
        wonderActive = true
        // Let go by ourselves if no shake-STOP arrives, so the particles
        // always get to settle — which is the one thing that ends a globe.
        run(.sequence([
            .wait(forDuration: Self.wonderMaxShakeSeconds),
            .run { [weak self] in self?.releaseWonderShake() }]),
            withKey: "wonderShakeCap")
        wonderHome = creature.position
        // RE-ENTRY. Home re-opens the shake 1s after its 8.5s timer, but the
        // teardown here is particle-driven and often still polling then — so
        // globes 2..n legitimately arrive with a globe still active (verified:
        // 4 shakes produced only 1 restore). The capture below reads the LIVE
        // scale, which mid-sequence ranges over base×0.90 ... base×1.12, so
        // re-reading it would adopt an inflated baseline and keep it for every
        // later globe — a permanent, cumulative size change. Today the
        // ordering hides that (re-entry lands after `wonderLanded` has reset
        // the scale exactly), which is luck, not design. Keep the baseline we
        // already hold: it is the same creature at the same depth. Nothing is
        // torn down — the live field simply carries on into the new globe, so
        // no particle is removed mid-air.
        if wasActive {
            removeAction(forKey: "wonderSettle")
            removeAction(forKey: "wonderFall")
            creature.setScale(wonderCapturedScale)
        } else {
            wonderCapturedScale = creature.xScale
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["AURIE_GLOBE_SCALE_LOG"] == "1" {
            NSLog("AURIE_GLOBE begin baseline=%.4f (%@)", wonderCapturedScale,
                  wasActive ? "kept, re-entry" : "captured fresh")
        }
        #endif
        wonderCarry = .zero
        wonderCarryVel = .zero
        wonderPhase = 0
        wonderShaking = true
        wonderFalling = false
        wonderLanded = false
        if wonderSwirl == nil {
            // A SNOW GLOBE, not an orbit: the field covers the whole visible
            // scene so particles travel across the environment rather than
            // ringing the creature.
            let field = ParticleField(
                family: aurie.family,
                area: CGRect(x: -size.width / 2, y: -size.height / 2,
                             width: size.width, height: size.height),
                motion: .globe)
            // z 0 — the same plane as the creature, so ±3 straddles it and
            // some particles pass behind the body.
            field.zPosition = 0
            addChild(field)
            wonderSwirl = field
        }
        wonderSwirl?.fling(from: creature.position, power: 1.0)
        wonderSwirl?.setGlobeEnergized(true)
        creature.beginWonderTumble()
    }

    /// The player is still shaking: keep the current alive.
    func sustainWonderShake(energy: CGFloat) {
        wonderSwirl?.setGlobeEnergized(true, energy: energy)
    }

    /// Shaking stopped. The swirl decays, Aurie is carried toward the FRONT of
    /// the playfield, and only then does it begin its slow fall.
    func releaseWonderShake() {
        guard wonderActive, wonderShaking else { return }
        removeAction(forKey: "wonderShakeCap")
        wonderShaking = false
        wonderSwirl?.setGlobeEnergized(false)
        creature?.endWonderTumble()
        // Foreground drift first, fall second — Aurie reads as having been
        // tossed toward the viewer before gravity takes it.
        run(.sequence([.wait(forDuration: 1.1),
                       .run { [weak self] in self?.wonderFalling = true }]),
            withKey: "wonderFall")
        // Watch our OWN particles from here. The scene used to sit and wait
        // for Home to call `settleWonder()` off an 8.5s timer, so a globe
        // Home hadn't sequenced (the removed chip, or any future entry point)
        // was never told to finish and stayed active forever. Arming the poll
        // here makes "the particles have settled" the end of every globe,
        // whatever started it.
        settleWonder()
    }

    /// Per-frame carry. Called from `update`.
    private func stepWonderCarry(_ dt: CGFloat) {
        guard wonderActive, let creature else { return }
        wonderPhase += dt
        let bounds = wonderSafeBounds()

        if wonderShaking {
            // Carried by the same broad current as the particles: two slow
            // incommensurate sines, so the path never repeats or looks like
            // an orbit. Wide, but always inside the safe box.
            let t = wonderPhase
            let target = CGPoint(
                x: sin(t * 1.15) * bounds.width * 0.42
                 + sin(t * 0.47 + 1.3) * bounds.width * 0.16,
                y: sin(t * 0.83 + 0.7) * bounds.height * 0.34
                 + cos(t * 1.61) * bounds.height * 0.12)
            wonderCarry.x += (target.x - wonderCarry.x) * min(1, 2.6 * dt)
            wonderCarry.y += (target.y - wonderCarry.y) * min(1, 2.6 * dt)
            // A little depth wobble, so it reads as tumbling through space.
            let depth = 1 + 0.10 * sin(t * 0.91)
            creature.setScale(wonderBaseScale * depth)
        } else if !wonderFalling {
            // Settling toward the FRONT/NEAR of the playfield, still elevated.
            let target = CGPoint(x: wonderCarry.x * 0.35,
                                 y: bounds.height * 0.30)
            wonderCarry.x += (target.x - wonderCarry.x) * min(1, 1.5 * dt)
            wonderCarry.y += (target.y - wonderCarry.y) * min(1, 1.5 * dt)
            // Nearer the viewer.
            let s = creature.xScale
            creature.setScale(s + (wonderBaseScale * 1.12 - s) * min(1, 1.4 * dt))
        } else if !wonderLanded {
            // Slow dreamy fall, matched to the particles' settle.
            wonderCarryVel.dy -= bounds.height * 0.85 * dt
            let terminal = -bounds.height * 0.42
            if wonderCarryVel.dy < terminal { wonderCarryVel.dy = terminal }
            wonderCarry.y += wonderCarryVel.dy * dt
            wonderCarry.x += wonderCarryVel.dx * dt
            wonderCarryVel.dx *= (1 - min(0.9, 1.2 * dt))
            let s = creature.xScale
            creature.setScale(s + (wonderBaseScale - s) * min(1, 1.1 * dt))
            if wonderCarry.y <= 0 {
                wonderCarry.y = 0
                wonderLanded = true
                creature.setScale(wonderBaseScale)
                creature.landingSquash()
            }
        }
        // Clamp so the body can never clip out or reach the Home chrome.
        wonderCarry.x = min(max(wonderCarry.x, -bounds.width * 0.5), bounds.width * 0.5)
        wonderCarry.y = min(max(wonderCarry.y, 0), bounds.height * 0.5)
        creature.position = CGPoint(x: wonderHome.x + wonderCarry.x,
                                    y: wonderHome.y + wonderCarry.y)
    }

    /// Safe travel box: generous, but never off-screen and never up into the
    /// Home header or down under the Daily card.
    private func wonderSafeBounds() -> CGSize {
        CGSize(width: size.width * 0.52, height: size.height * 0.34)
    }

    private var wonderBaseScale: CGFloat { wonderCapturedScale }

    /// Hand the creature back exactly as Home expects it.
    private func endWonderCarry() {
        guard let creature else { return }
        creature.zRotation = 0
        wonderCarry = .zero
        wonderCarryVel = .zero
        // Re-assert the FIELD state, which is what every normal move ends
        // with: position, depth-correct scale AND the depth contact shadow.
        // Setting a bare scale here left the creature oversized for its
        // depth and never restored the shadow, and it only self-corrected
        // if SwiftUI happened to relayout.
        if environment.isActive {
            applyFieldPosition()
        } else {
            creature.position = wonderHome
            creature.setScale(wonderCapturedScale)
        }
        #if DEBUG
        // Scale-restoration proof: `now` must equal `captured` after every
        // globe, and `captured` must be identical across repeated runs
        // (no drift). AURIE_GLOBE_SCALE_LOG=1
        if ProcessInfo.processInfo
            .environment["AURIE_GLOBE_SCALE_LOG"] == "1" {
            NSLog("AURIE_GLOBE restore captured=%.4f now=%.4f delta=%.4f",
                  wonderCapturedScale, creature.xScale,
                  creature.xScale - wonderCapturedScale)
        }
        #endif
    }

    /// PEAK. One restrained family accent at the top of the sequence.
    func wonderPeak() {
        guard let creature else { return }
        // Deliberately does NOT re-fling. The globe is one continuous
        // current now; a second impulse resets every particle's velocity and
        // breaks the long curved paths the whole effect depends on.
        _ = creature
    }

    /// SETTLE. Globe particles fade themselves out as they land; this tears
    /// the field down afterwards so Home returns to exactly its normal state.
    ///
    /// Armed by `releaseWonderShake` — Home may also call it, which is
    /// harmless but redundant. Safe to call repeatedly: the poll holds no
    /// progress of its own, it only ever asks the field whether it has
    /// finished, so re-arming cannot restart or delay a settle in flight.
    func settleWonder() {
        guard wonderActive, action(forKey: "wonderSettle") == nil else { return }
        // Poll rather than wait a fixed duration: a fixed timer tore the field
        // down while particles were still falling, which is exactly the
        // mid-air disappearance this is meant to prevent.
        run(.repeatForever(.sequence([
            .wait(forDuration: 0.5),
            .run { [weak self] in
                guard let self, let field = self.wonderSwirl else { return }
                #if DEBUG
                if ProcessInfo.processInfo.environment["AURIE_GLOBE_SCALE_LOG"] == "1" {
                    field.logGlobePhases()
                }
                #endif
                guard field.isGlobeFinished else { return }
                self.removeAction(forKey: "wonderSettle")
                self.endWonderCarry()
                field.removeFromParent()
                self.wonderSwirl = nil
                self.wonderActive = false
            }])), withKey: "wonderSettle")
    }

}
