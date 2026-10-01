import SpriteKit
import UIKit

/// The Home play objects (Play Shelf pass): Bubble, Ball, Star, Butterfly.
///
/// One toy is active at a time (bubbles count as one toy: a few gentle
/// bubbles). Every visual is PROCEDURAL — drawn once into textures at the
/// right scale, matching how the rest of the scene builds its aura/shadow —
/// so the toys read as part of the Aurie world without new art dependencies.
///
/// `ToyBox` owns only the toy nodes and their motion. Everything about the
/// CREATURE (noticing, kicking, chasing, faces) stays in `CreatureScene`,
/// which reads toy state each frame and reacts through the same primitives
/// and priority rules the autonomous-life pass established.
enum PlayToy: String, CaseIterable {
    case bubble, ball, star, butterfly

    /// The toys the Play Shelf OFFERS. Star and Butterfly were removed from
    /// the shelf 2026-09-21: the butterfly became Moss's ambient decorative
    /// accent, and a background butterfly must never look interactive. The
    /// cases, spawn code, chase choreography and art all remain — they are
    /// simply no longer reachable from the shelf, so re-offering either one
    /// is a one-line change here.
    static var shelf: [PlayToy] { [.bubble, .ball] }

    var label: String {
        switch self {
        case .bubble: return "Bubbles"
        case .ball: return "Ball"
        case .star: return "Star"
        case .butterfly: return "Butterfly"
        }
    }

    /// The dialogue activity this toy is (see `ToyDialogue`).
    var activity: ToyActivity {
        switch self {
        case .bubble:    return .bubbles
        case .ball:      return .ball
        case .star:      return .star
        case .butterfly: return .butterfly
        }
    }
}

final class ToyBox {

    // MARK: State

    private(set) var active: PlayToy?
    /// Play events the dialogue director listens to (see `ToyDialogue`).
    /// Reporting only: nothing about the toys' motion depends on it.
    var onEvent: ((ToyEvent) -> Void)?
    /// Root for everything the toy pass adds, so deactivation is one removal.
    private let root = SKNode()

    // Bubble state
    private var bubbles: [SKSpriteNode] = []
    // Ball state
    private var ball: SKSpriteNode?
    private var ballShadow: SKSpriteNode?
    private var ballVelocity = CGVector.zero
    /// DEPTH, 0 far … 1 near. The ball used to live on a single vertical
    /// plane: x across, y as height. Depth adds the third axis so it can be
    /// kicked away from the viewer and roll back, matching the perspective
    /// playfield everything else already uses.
    private var ballDepth: CGFloat = 0.78
    private var ballDepthVel: CGFloat = 0
    /// Height ABOVE the floor in world units, kept separate from the sprite's
    /// y: the floor itself moves when depth changes, so storing absolute y
    /// would make a ball kicked away appear to leap into the air.
    private var ballHeight: CGFloat = 0
    private(set) var ballGrabbed = false
    private var ballResting = false
    // Star state
    private var star: SKSpriteNode?
    private(set) var starGrabbed = false
    private var lastTrailAt: TimeInterval = 0
    // Butterfly state
    private var butterfly: SKNode?
    private(set) var butterflyPos = CGPoint.zero
    // Drag velocity sampling (ball toss)
    private var dragSamples: [(p: CGPoint, t: TimeInterval)] = []

    // MARK: Tuning

    private let maxBubbles = 3
    private let ballRadius: CGFloat = 30
    /// Furthest the ball may roll away. Not 0: at the very far edge it is
    /// tiny and sits on the horizon line, which reads as stuck to the
    /// backdrop rather than as a ball in the world.
    private static let ballDepthFar: CGFloat = 0.34
    private let starRadius: CGFloat = 24
    private let gravity: CGFloat = -1350
    private let bounceKeep: CGFloat = 0.52     // velocity kept per floor bounce
    private let rollFriction: CGFloat = 0.985  // per-frame at 60 Hz

    func toyLog(_ msg: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AURIE_TOY_LOG"] == "1" {
            NSLog("AURIE_TOY %@", msg)
        }
        #endif
    }

    // MARK: Activation

    func activate(_ toy: PlayToy, in scene: SKScene) {
        deactivate()
        active = toy
        root.zPosition = 30            // above creature, below speech overlays
        scene.addChild(root)
        switch toy {
        case .bubble:    startBubbles(in: scene)
        case .ball:      spawnBall(in: scene)
        case .star:      spawnStar(in: scene)
        case .butterfly: spawnButterfly(in: scene)
        }
        toyLog("activate \(toy.rawValue)")
    }

    func deactivate() {
        guard active != nil else { return }
        toyLog("deactivate \(active!.rawValue)")
        active = nil
        root.removeAllActions()
        root.removeAllChildren()
        root.removeFromParent()
        bubbles.removeAll()
        ball = nil; ballShadow = nil; ballGrabbed = false; ballResting = false
        ballVelocity = .zero
        star = nil; starGrabbed = false
        butterfly = nil
        dragSamples.removeAll()
    }

    // MARK: - Touch routing (scene calls these first; true = handled)

    /// A touch landing on a grabbable toy grabs it.
    func grab(at p: CGPoint, now: TimeInterval) -> Bool {
        if let ball, active == .ball,
           ball.position.distance(to: p) < ballRadius + 16 {
            ballGrabbed = true
            ballResting = false
            ballVelocity = .zero
            ball.removeAction(forKey: "spin")
            dragSamples = [(ball.position, now)]
            SoundPlayer.play("sfx_pickup")
            toyLog("ball grab")
            return true
        }
        if let star, active == .star,
           star.position.distance(to: p) < starRadius + 20 {
            starGrabbed = true
            toyLog("star grab")
            return true
        }
        return false
    }

    var dragging: Bool { ballGrabbed || starGrabbed }

    /// Follow the finger while grabbed. Returns the toy's new position.
    @discardableResult
    func drag(to p: CGPoint, in scene: SKScene, now: TimeInterval) -> CGPoint? {
        let half = CGSize(width: scene.size.width / 2, height: scene.size.height / 2)
        let clamped = CGPoint(x: max(-half.width + 30, min(half.width - 30, p.x)),
                              y: max(-half.height + 30, min(half.height - 40, p.y)))
        if ballGrabbed, let ball {
            ball.position = clamped
            ballShadowFollow()
            dragSamples.append((clamped, now))
            if dragSamples.count > 6 { dragSamples.removeFirst() }
            return clamped
        }
        if starGrabbed, let star {
            star.position = clamped
            spawnStarTrail(at: clamped, now: now)
            return clamped
        }
        return nil
    }

    /// Release a grab; the ball takes a toss velocity from the recent drag.
    func release(now: TimeInterval) {
        if ballGrabbed {
            ballGrabbed = false
            if let first = dragSamples.first, let last = dragSamples.last,
               last.t - first.t > 0.01 {
                let dt = CGFloat(last.t - first.t)
                // A flick up-screen throws it AWAY, not just upward: the
                // vertical drag is split between height and depth so the
                // player can put the ball into the distance too.
                ballDepthVel = -(last.p.y - first.p.y) / dt * 0.0011
                ballVelocity = CGVector(dx: (last.p.x - first.p.x) / dt * 0.9,
                                        dy: (last.p.y - first.p.y) / dt * 0.9)
            }
            dragSamples.removeAll()
            toyLog(String(format: "ball toss v=(%.0f,%.0f)",
                          ballVelocity.dx, ballVelocity.dy))
            onEvent?(.ballTossed(strong: hypot(ballVelocity.dx, ballVelocity.dy) > 900))
        }
        if starGrabbed {
            starGrabbed = false
            toyLog("star release")
            starIdleBob()
        }
    }

    /// A completed TAP on a bubble pops it.
    func tapPop(at p: CGPoint) -> Bool {
        guard active == .bubble else { return false }
        if let hit = bubbles.first(where: { $0.parent != nil
            && $0.position.distance(to: p) < $0.size.width / 2 + 14 }) {
            pop(hit, reason: "tap")
            return true
        }
        return false
    }

    // MARK: - Frame tick (scene.update)

    func tick(dt: CGFloat, now: TimeInterval, in scene: SKScene) {
        if active == .ball { tickBall(dt: dt, in: scene) }
        bubbles.removeAll { $0.parent == nil }
    }

    // MARK: - Bubbles

    private func startBubbles(in scene: SKScene) {
        let spawn = SKAction.run { [weak self, weak scene] in
            guard let self, let scene else { return }
            self.spawnBubble(in: scene)
        }
        root.run(.repeatForever(.sequence([
            spawn, .wait(forDuration: 3.4, withRange: 2.2),
        ])), withKey: "bubbleSpawner")
    }

    private func spawnBubble(in scene: SKScene) {
        guard bubbles.filter({ $0.parent != nil }).count < maxBubbles else { return }
        let r = CGFloat.random(in: 20...30)
        let bubble = SKSpriteNode(texture: Self.bubbleTexture)
        bubble.size = CGSize(width: r * 2, height: r * 2)
        bubble.alpha = 0
        let halfW = scene.size.width / 2
        bubble.position = CGPoint(x: .random(in: -halfW * 0.7 ... halfW * 0.7),
                                  y: -scene.size.height / 2 + 40)
        root.addChild(bubble)
        bubbles.append(bubble)
        toyLog(String(format: "bubble spawn (%.0f,%.0f) r=%.0f",
                      bubble.position.x, bubble.position.y, r))

        bubble.run(.fadeAlpha(to: 0.9, duration: 0.5))
        // Buoyant rise with a gentle sway; pops softly on its own at the top.
        let riseTime = TimeInterval(scene.size.height / .random(in: 26...38))
        let rise = SKAction.moveBy(x: 0, y: scene.size.height - 90, duration: riseTime)
        let sway = SKAction.repeatForever(.sequence([
            .moveBy(x: 13, y: 0, duration: 1.4),
            .moveBy(x: -13, y: 0, duration: 1.4),
        ]))
        sway.timingMode = .easeInEaseOut
        bubble.run(sway, withKey: "sway")
        bubble.run(.sequence([rise, .run { [weak self, weak bubble] in
            guard let self, let bubble, bubble.parent != nil else { return }
            self.pop(bubble, quiet: true, reason: "drift")
        }]), withKey: "rise")
        // Dialogue only: "it's getting away" while it is still catchable.
        bubble.run(.sequence([.wait(forDuration: riseTime * 0.72),
                              .run { [weak self, weak bubble] in
            guard let self, let bubble, bubble.parent != nil else { return }
            self.onEvent?(.bubbleHigh)
        }]), withKey: "highNotice")
    }

    func pop(_ bubble: SKSpriteNode, quiet: Bool = false, reason: String = "touch") {
        guard bubbles.contains(where: { $0 === bubble }) else { return }
        bubbles.removeAll { $0 === bubble }   // one pop per bubble, ever
        toyLog(String(format: "bubble pop[%@] (%.0f,%.0f)", reason,
                      bubble.position.x, bubble.position.y))
        onEvent?(reason == "drift" ? .bubbleEscaped
                                   : .bubblePopped(byAurie: reason != "tap"))
        bubble.removeAllActions()
        // Gentle, satisfying: a quick swell + fade with a few tiny droplets.
        bubble.run(.sequence([
            .group([.scale(to: 1.3, duration: 0.10),
                    .fadeOut(withDuration: 0.10)]),
            .removeFromParent(),
        ]))
        for _ in 0 ..< 5 {
            let d = SKSpriteNode(texture: Self.dropletTexture)
            d.size = CGSize(width: 6, height: 6)
            d.position = bubble.position
            d.alpha = 0.85
            root.addChild(d)
            let a = CGFloat.random(in: 0 ..< .pi * 2)
            let dist = CGFloat.random(in: 14...30)
            d.run(.sequence([
                .group([.moveBy(x: cos(a) * dist, y: sin(a) * dist - 8, duration: 0.35),
                        .fadeOut(withDuration: 0.35),
                        .scale(to: 0.4, duration: 0.35)]),
                .removeFromParent(),
            ]))
        }
        if !quiet { SoundPlayer.play("sfx_tap") }
    }

    /// The bubble nearest a point within `radius`, for the creature's notice.
    func bubbleNear(_ p: CGPoint, within radius: CGFloat) -> SKSpriteNode? {
        bubbles.first { $0.parent != nil && $0.position.distance(to: p) < radius }
    }

    // MARK: - Ball

    private func spawnBall(in scene: SKScene) {
        let shadow = SKSpriteNode(texture: Self.ballShadowTexture)
        shadow.size = CGSize(width: ballRadius * 2.1, height: ballRadius * 0.7)
        shadow.alpha = 0.4
        root.addChild(shadow)
        ballShadow = shadow

        let b = SKSpriteNode(texture: Self.ballTexture)
        b.size = CGSize(width: ballRadius * 2, height: ballRadius * 2)
        ballDepth = 0.78
        ballDepthVel = 0
        ballHeight = 160
        let f = ballField(in: scene)
        b.position = CGPoint(x: scene.size.width * 0.24,
                             y: f.floorY + ballRadius * f.scale + ballHeight * f.scale)
        b.setScale(f.scale)
        root.addChild(b)
        ball = b
        ballVelocity = .zero
        ballShadowFollow()
        toyLog("ball spawn")
    }

    /// The stylised floor: the creature's home foot line.
    private func ballGroundY(in scene: SKScene) -> CGFloat {
        guard let s = scene as? CreatureScene else { return -scene.size.height * 0.28 }
        return s.toyGroundY + ballRadius
    }

    /// Sort the ball against the CREATURE by depth. The toy root sits at
    /// z 30 — above everything — which was fine while the ball could only go
    /// left and right, but now a ball rolling on ground further away than
    /// Aurie still drew in front of it, which reads as broken.
    ///
    /// A child's effective z is its own plus the root's, so the offset below
    /// is written to cross zero exactly when the ball passes the creature's
    /// depth. The +6 bias means a tie renders in FRONT: a ball at the
    /// creature's feet belongs on the near side of it.
    private func updateBallDepthOrder(in scene: SKScene) {
        guard let ball else { return }
        let creatureDepth = (scene as? CreatureScene)?.toyCreatureDepth ?? 0.7
        let effective = (ballDepth - creatureDepth) * 160 + 6
        ball.zPosition = effective - 30
        // The shadow always lies on the ground, just under whatever the ball
        // is sorted against.
        ballShadow?.zPosition = ball.zPosition - 2
    }

    private func ballField(in scene: SKScene)
        -> (floorY: CGFloat, scale: CGFloat, halfWidth: CGFloat) {
        guard let s = scene as? CreatureScene else {
            return (-scene.size.height * 0.28, 1, scene.size.width / 2 - 10)
        }
        return s.toyField(depth: ballDepth)
    }

    private func ballShadowFollow() {
        guard let ball, let ballShadow else { return }
        ballShadow.position = CGPoint(x: ball.position.x,
                                      y: ball.position.y - ballRadius + 4
                                        - max(0, ball.position.y - shadowRestY))
        // Shadow sits on the floor, and shrinks BOTH with the ball's height
        // and with its distance — otherwise a ball kicked away keeps a
        // full-size shadow and looks like it is floating toward the horizon.
        let h = max(0, ball.position.y - shadowRestY)
        ballShadow.position = CGPoint(x: ball.position.x,
                                      y: shadowRestY - ballRadius + 6)
        let f = max(0.45, 1 - h / 420)
        ballShadow.setScale(f * ball.xScale)
        ballShadow.alpha = 0.4 * f
    }

    private var shadowRestY: CGFloat = 0

    private func tickBall(dt: CGFloat, in scene: SKScene) {
        guard let ball, !ballGrabbed else {
            updateBallDepthOrder(in: scene)
            ballShadowFollow()
            return
        }

        // DEPTH first — the floor line, the render scale and the walls all
        // depend on it, so everything below has to be computed against the
        // depth the ball is at THIS tick.
        ballDepth += ballDepthVel * dt
        if ballDepth < Self.ballDepthFar {
            ballDepth = Self.ballDepthFar
            ballDepthVel = -ballDepthVel * 0.45      // bounces off the far edge
        } else if ballDepth > 1 {
            ballDepth = 1
            ballDepthVel = -ballDepthVel * 0.45
        }
        ballDepthVel *= pow(0.12, dt)                // rolls to a stop

        let field = ballField(in: scene)
        let scale = field.scale
        let floor = field.floorY + ballRadius * scale
        shadowRestY = floor
        let wall = field.halfWidth - ballRadius * scale

        var p = ball.position
        var v = ballVelocity
        // Height is in WORLD units and only scaled when drawn, so a bounce
        // keeps its shape wherever the ball is standing.
        v.dy += gravity * dt
        ballHeight += v.dy * dt
        p.x += v.dx * dt * scale

        if ballHeight <= 0 {
            ballHeight = 0
            if abs(v.dy) > 60 {
                v.dy = -v.dy * bounceKeep
                v.dx *= 0.92
                ballDepthVel *= 0.92
                SoundPlayer.play("sfx_drop")
            } else {
                v.dy = 0
            }
        }
        if p.x > wall { p.x = wall; v.dx = -abs(v.dx) * 0.7 }
        if p.x < -wall { p.x = -wall; v.dx = abs(v.dx) * 0.7 }
        if ballHeight <= 0.5 { v.dx *= rollFriction }

        // Roll: spin from travel, now including the depth component so a ball
        // kicked straight away still turns over.
        let travel = abs(v.dx) + abs(ballDepthVel) * 260
        if travel > 4 {
            ball.zRotation -= (v.dx * dt) / ballRadius
        }

        let wasResting = ballResting
        ballResting = ballHeight <= 0.5 && abs(v.dx) < 12 && abs(v.dy) < 1
            && abs(ballDepthVel) < 0.04
        if ballResting { v = .zero; ballDepthVel = 0 }
        if ballResting && !wasResting {
            toyLog(String(format: "ball rest (%.0f,%.0f) depth=%.2f",
                          p.x, p.y, ballDepth))
            onEvent?(.ballRested)
        }
        p.y = floor + ballHeight * scale
        ball.position = p
        ball.setScale(scale)
        ballVelocity = v
        updateBallDepthOrder(in: scene)
        ballShadowFollow()
    }

    var ballPosition: CGPoint? { ball?.position }
    /// 0 far … 1 near, so the scene can decide whether a kick should send the
    /// ball away or bring it back.
    var ballFieldDepth: CGFloat { ballDepth }
    var ballIsResting: Bool { ballResting }
    /// Slow enough to kick without waiting for the full stop: on the ground
    /// and barely rolling. The rally keeps moving instead of the creature
    /// watching the ball coast the last few seconds to a halt.
    var ballIsSlow: Bool {
        ball != nil && !ballGrabbed && ballHeight <= 0.5
            && abs(ballVelocity.dx) < 70 && abs(ballDepthVel) < 0.08
    }

    /// The creature kicked the ball. `depth` is the DEPTH impulse: negative
    /// sends it away from the viewer, positive brings it back. A sideways
    /// kick passes 0 and behaves exactly as before.
    func kickBall(direction: CGFloat, depth: CGFloat = 0) {
        guard ball != nil else { return }
        ballResting = false
        // A kick straight down the field puts less into the sideways throw,
        // otherwise a "forward" kick still sails off to one side.
        let sideways = direction * .random(in: 300...400) * (1 - min(abs(depth) / 0.5, 0.8))
        ballVelocity = CGVector(dx: sideways,
                                dy: .random(in: 200...300))
        ballDepthVel = depth
        SoundPlayer.play("sfx_tap")
        toyLog(String(format: "ball kicked dir=%@ depth=%+.2f",
                      direction > 0 ? "R" : "L", depth))
        onEvent?(.ballKicked(strong: depth < -0.15))   // sent down the field
    }

    /// The creature batted the ball mid-air with a hand: redirect it away at
    /// the moment of contact.
    func batBall(direction: CGFloat, up: Bool) {
        guard ball != nil else { return }
        ballResting = false
        ballVelocity = CGVector(dx: direction * .random(in: 260...360),
                                dy: up ? .random(in: -60...40)
                                       : .random(in: 180...260))
        SoundPlayer.play("sfx_tap")
        toyLog("ball batted dir=\(direction > 0 ? "R" : "L")\(up ? " high" : "")")
        onEvent?(.ballKicked(strong: false))
    }

    var ballMoving: Bool {
        ball != nil && !ballGrabbed && !ballResting
    }

    /// The bubble nearest a point, for reach targeting.
    func nearestBubble(to p: CGPoint) -> SKSpriteNode? {
        bubbles.filter { $0.parent != nil }
            .min { $0.position.distance(to: p) < $1.position.distance(to: p) }
    }

    // MARK: - Star

    private func spawnStar(in scene: SKScene) {
        let s = SKSpriteNode(texture: Self.starTexture)
        s.size = CGSize(width: starRadius * 2.6, height: starRadius * 2.6)
        s.position = CGPoint(x: -scene.size.width * 0.24,
                             y: scene.size.height * 0.16)
        root.addChild(s)
        star = s
        starIdleBob()
        toyLog("star spawn")
    }

    private func starIdleBob() {
        guard let star else { return }
        let bob = SKAction.repeatForever(.sequence([
            .moveBy(x: 0, y: 7, duration: 1.3),
            .moveBy(x: 0, y: -7, duration: 1.3),
        ]))
        bob.timingMode = .easeInEaseOut
        star.run(bob, withKey: "bob")
        star.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.85, duration: 1.1),
            .fadeAlpha(to: 1.0, duration: 1.1),
        ])), withKey: "shimmer")
    }

    var starPosition: CGPoint? { star?.position }

    /// A small answering pulse when the creature touches the star.
    func starPulse() {
        guard let star else { return }
        star.removeAction(forKey: "pulse")
        star.run(.sequence([.scale(to: 1.18, duration: 0.12),
                            .scale(to: 1.0, duration: 0.18)]), withKey: "pulse")
        for _ in 0 ..< 3 {
            let t = SKSpriteNode(texture: Self.trailSparkTexture)
            t.size = CGSize(width: 10, height: 10)
            t.position = CGPoint(x: star.position.x + .random(in: -14...14),
                                 y: star.position.y + .random(in: -12...14))
            root.addChild(t)
            t.run(.sequence([
                .group([.fadeOut(withDuration: 0.4),
                        .moveBy(x: 0, y: 10, duration: 0.4)]),
                .removeFromParent(),
            ]))
        }
    }

    /// The rare two-hand catch: a brief magical burst, then the star floats
    /// free again.
    func starBurst() {
        guard let star else { return }
        starPulse()
        for i in 0 ..< 8 {
            let t = SKSpriteNode(texture: Self.trailSparkTexture)
            t.size = CGSize(width: 12, height: 12)
            t.position = star.position
            root.addChild(t)
            let a = CGFloat(i) * .pi / 4
            t.run(.sequence([
                .group([.moveBy(x: cos(a) * 42, y: sin(a) * 42, duration: 0.5),
                        .fadeOut(withDuration: 0.5),
                        .scale(to: 0.3, duration: 0.5)]),
                .removeFromParent(),
            ]))
        }
        star.run(.moveBy(x: 0, y: 34, duration: 0.7), withKey: "release")
        SoundPlayer.play("sfx_appear")
        toyLog("star catch burst")
    }

    private func spawnStarTrail(at p: CGPoint, now: TimeInterval) {
        guard now - lastTrailAt > 0.09 else { return }
        lastTrailAt = now
        let t = SKSpriteNode(texture: Self.trailSparkTexture)
        t.size = CGSize(width: 10, height: 10)
        t.position = CGPoint(x: p.x + .random(in: -6...6),
                             y: p.y + .random(in: -6...6))
        t.alpha = 0.8
        t.zRotation = .random(in: 0 ..< .pi)
        root.addChild(t)
        t.run(.sequence([
            .group([.fadeOut(withDuration: 0.45),
                    .scale(to: 0.3, duration: 0.45),
                    .moveBy(x: 0, y: -6, duration: 0.45)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Butterfly

    private func spawnButterfly(in scene: SKScene) {
        let b = SKNode()
        let body = SKSpriteNode(texture: Self.butterflyBodyTexture)
        body.size = CGSize(width: 7, height: 22)
        body.zPosition = 0.2
        let wingL = SKSpriteNode(texture: Self.butterflyWingTexture)
        wingL.size = CGSize(width: 18, height: 24)
        wingL.anchorPoint = CGPoint(x: 1.0, y: 0.5)
        wingL.position = CGPoint(x: -1, y: 2)
        let wingR = SKSpriteNode(texture: Self.butterflyWingTexture)
        wingR.size = CGSize(width: 18, height: 24)
        wingR.anchorPoint = CGPoint(x: 1.0, y: 0.5)
        wingR.position = CGPoint(x: 1, y: 2)
        wingR.xScale = -1
        b.addChild(wingL); b.addChild(wingR); b.addChild(body)

        // Gentle continuous flap (scale about the body edge).
        let flapIn = SKAction.scaleX(to: 0.35, duration: 0.12)
        let flapOut = SKAction.scaleX(to: 1.0, duration: 0.14)
        flapIn.timingMode = .easeIn; flapOut.timingMode = .easeOut
        wingL.run(.repeatForever(.sequence([flapIn, flapOut])))
        let flapIn2 = SKAction.scaleX(to: -0.35, duration: 0.12)
        let flapOut2 = SKAction.scaleX(to: -1.0, duration: 0.14)
        flapIn2.timingMode = .easeIn; flapOut2.timingMode = .easeOut
        wingR.run(.repeatForever(.sequence([flapIn2, flapOut2])))

        b.position = CGPoint(x: scene.size.width * 0.2, y: scene.size.height * 0.2)
        b.setScale(1.35)
        root.addChild(b)
        butterfly = b
        butterflyPos = b.position
        wanderButterfly(in: scene)
        toyLog("butterfly spawn")
    }

    /// One curved wander segment at a time; occasional hover pauses.
    private func wanderButterfly(in scene: SKScene, fleeing: Bool = false) {
        guard let butterfly else { return }
        let halfW = scene.size.width / 2
        let halfH = scene.size.height / 2
        // Safe airspace: sides clear of the edges, upper-middle band so it
        // never crowds the ground line or the top chrome.
        let x = CGFloat.random(in: -halfW * 0.72 ... halfW * 0.72)
        let yLo = -halfH * 0.10, yHi = halfH * 0.42
        let y = fleeing ? CGFloat.random(in: halfH * 0.22 ... yHi)
                        : CGFloat.random(in: yLo ... yHi)
        let target = CGPoint(x: x, y: y)
        let from = butterfly.position
        let dist = from.distance(to: target)
        guard dist > 30 else { wanderButterfly(in: scene); return }
        let speed: CGFloat = fleeing ? 210 : .random(in: 55...95)
        // A curved path: control point offset sideways from the midpoint.
        let mid = CGPoint(x: (from.x + target.x) / 2, y: (from.y + target.y) / 2)
        let normal = CGVector(dx: -(target.y - from.y) / dist,
                              dy: (target.x - from.x) / dist)
        let bow = CGFloat.random(in: -0.35...0.35) * dist
        let control = CGPoint(x: mid.x + normal.dx * bow, y: mid.y + normal.dy * bow)
        let path = UIBezierPath()
        path.move(to: from)
        path.addQuadCurve(to: target, controlPoint: control)
        let fly = SKAction.follow(path.cgPath, asOffset: false,
                                  orientToPath: false, speed: speed)
        let hover: SKAction = Bool.random()
            ? .sequence([.moveBy(x: 0, y: 5, duration: 0.6),
                         .moveBy(x: 0, y: -5, duration: 0.6)])
            : .wait(forDuration: .random(in: 0.2...0.9))
        butterfly.run(.sequence([fly, hover, .run { [weak self, weak scene] in
            guard let self, let scene else { return }
            self.butterflyPos = self.butterfly?.position ?? .zero
            self.wanderButterfly(in: scene)
        }]), withKey: "wander")
        butterflyPos = target
    }

    /// The creature lunged: dart up and away, then resume wandering.
    func butterflyFlee(in scene: SKScene) {
        guard let butterfly else { return }
        butterfly.removeAction(forKey: "wander")
        wanderButterfly(in: scene, fleeing: true)
        toyLog("butterfly flee")
    }

    /// A quick sideways dart (chase beats): a short fast segment away from
    /// `from`, staying at catchable height, then normal wandering resumes.
    func butterflyDart(in scene: SKScene, awayFrom from: CGPoint) {
        guard let butterfly else { return }
        butterfly.removeAction(forKey: "wander")
        let halfW = scene.size.width / 2
        let dir: CGFloat = butterfly.position.x >= from.x ? 1 : -1
        let x = max(-halfW * 0.72, min(halfW * 0.72,
                    butterfly.position.x + dir * .random(in: 90...150)))
        let y = max(-scene.size.height * 0.10,
                    min(scene.size.height * 0.30,
                        butterfly.position.y + .random(in: -30...50)))
        let target = CGPoint(x: x, y: y)
        let move = SKAction.move(to: target, duration: 0.55)
        move.timingMode = .easeOut
        butterfly.run(.sequence([move, .run { [weak self, weak scene] in
            guard let self, let scene else { return }
            self.butterflyPos = target
            self.wanderButterfly(in: scene)
        }]), withKey: "wander")
        butterflyPos = target
        toyLog("butterfly dart")
    }

    var butterflyPosition: CGPoint? { butterfly?.position }

    // MARK: - Procedural textures

    static let bubbleTexture: SKTexture = {
        let size = CGSize(width: 128, height: 128)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
            // Soft translucent fill, barely-there.
            c.saveGState()
            c.addEllipse(in: rect); c.clip()
            let fill = CGGradient(colorsSpace: nil, colors: [
                UIColor(white: 1, alpha: 0.05).cgColor,
                UIColor(white: 1, alpha: 0.16).cgColor,
            ] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(fill, startCenter: CGPoint(x: 64, y: 64),
                                 startRadius: 8,
                                 endCenter: CGPoint(x: 64, y: 64),
                                 endRadius: 62, options: [])
            c.restoreGState()
            // Iridescent rim: hue-shifted arcs hugging the inside edge.
            let hues: [(CGFloat, CGFloat, CGFloat)] = [
                (0.55, 0.75, 1.6), (0.80, 2.2, 3.0), (0.12, 4.0, 4.9), (0.38, 5.4, 6.1),
            ]
            for (hue, a0, a1) in hues {
                c.setStrokeColor(UIColor(hue: hue, saturation: 0.55,
                                         brightness: 1, alpha: 0.5).cgColor)
                c.setLineWidth(5)
                c.addArc(center: CGPoint(x: 64, y: 64), radius: 55,
                         startAngle: a0, endAngle: a1, clockwise: false)
                c.strokePath()
            }
            // Thin bright rim + specular highlight.
            c.setStrokeColor(UIColor(white: 1, alpha: 0.75).cgColor)
            c.setLineWidth(2.5)
            c.strokeEllipse(in: rect)
            c.setFillColor(UIColor(white: 1, alpha: 0.9).cgColor)
            c.fillEllipse(in: CGRect(x: 34, y: 26, width: 22, height: 14))
            c.setFillColor(UIColor(white: 1, alpha: 0.5).cgColor)
            c.fillEllipse(in: CGRect(x: 58, y: 20, width: 8, height: 6))
        }
        return SKTexture(image: img)
    }()

    static let dropletTexture: SKTexture = {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
            ctx.cgContext.setFillColor(UIColor(white: 1, alpha: 0.9).cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: 3, y: 3, width: 10, height: 10))
        }
        return SKTexture(image: img)
    }()

    static let ballTexture: SKTexture = {
        let size = CGSize(width: 128, height: 128)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
            c.saveGState()
            c.addEllipse(in: rect); c.clip()
            // Plush two-tone: warm coral body with a soft cream band.
            let body = CGGradient(colorsSpace: nil, colors: [
                UIColor(red: 1.00, green: 0.62, blue: 0.47, alpha: 1).cgColor,
                UIColor(red: 0.85, green: 0.38, blue: 0.30, alpha: 1).cgColor,
            ] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(body, startCenter: CGPoint(x: 48, y: 44),
                                 startRadius: 6,
                                 endCenter: CGPoint(x: 64, y: 64),
                                 endRadius: 66, options: [])
            // Cream band across the middle (gently curved).
            c.setFillColor(UIColor(red: 1.0, green: 0.93, blue: 0.82, alpha: 1).cgColor)
            let band = UIBezierPath()
            band.move(to: CGPoint(x: 0, y: 46))
            band.addQuadCurve(to: CGPoint(x: 128, y: 46),
                              controlPoint: CGPoint(x: 64, y: 66))
            band.addLine(to: CGPoint(x: 128, y: 78))
            band.addQuadCurve(to: CGPoint(x: 0, y: 78),
                              controlPoint: CGPoint(x: 64, y: 98))
            band.close()
            c.addPath(band.cgPath); c.fillPath()
            // Soft top highlight + lower shade for plush depth.
            c.setFillColor(UIColor(white: 1, alpha: 0.35).cgColor)
            c.fillEllipse(in: CGRect(x: 26, y: 14, width: 40, height: 24))
            c.setFillColor(UIColor(red: 0.4, green: 0.12, blue: 0.10, alpha: 0.25).cgColor)
            c.fillEllipse(in: CGRect(x: 22, y: 92, width: 84, height: 30))
            c.restoreGState()
        }
        return SKTexture(image: img)
    }()

    static let ballShadowTexture: SKTexture = {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 32)).image { ctx in
            let g = CGGradient(colorsSpace: nil, colors: [
                UIColor(white: 0, alpha: 0.55).cgColor,
                UIColor(white: 0, alpha: 0).cgColor,
            ] as CFArray, locations: [0, 1])!
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 48, y: 16)
            ctx.cgContext.scaleBy(x: 1, y: 0.33)
            ctx.cgContext.drawRadialGradient(g, startCenter: .zero, startRadius: 0,
                                             endCenter: .zero, endRadius: 46, options: [])
            ctx.cgContext.restoreGState()
        }
        return SKTexture(image: img)
    }()

    static let starTexture: SKTexture = {
        let size = CGSize(width: 160, height: 160)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            // Soft magical glow.
            let glow = CGGradient(colorsSpace: nil, colors: [
                UIColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 0.55).cgColor,
                UIColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 0).cgColor,
            ] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(glow, startCenter: CGPoint(x: 80, y: 80),
                                 startRadius: 4,
                                 endCenter: CGPoint(x: 80, y: 80),
                                 endRadius: 78, options: [])
            // Rounded five-point star.
            let star = UIBezierPath()
            let cx: CGFloat = 80, cy: CGFloat = 80
            let rOuter: CGFloat = 42, rInner: CGFloat = 19
            for i in 0 ..< 10 {
                let r = i.isMultiple(of: 2) ? rOuter : rInner
                let a = CGFloat(i) * .pi / 5 - .pi / 2
                let pt = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
                if i == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
            }
            star.close()
            c.setShadow(offset: .zero, blur: 10,
                        color: UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 0.9).cgColor)
            c.setFillColor(UIColor(red: 1.0, green: 0.88, blue: 0.45, alpha: 1).cgColor)
            c.addPath(star.cgPath); c.fillPath()
            c.setShadow(offset: .zero, blur: 0, color: nil)
            // Inner warm core + tiny specular.
            c.setFillColor(UIColor(red: 1.0, green: 0.97, blue: 0.8, alpha: 0.9).cgColor)
            c.fillEllipse(in: CGRect(x: 66, y: 62, width: 26, height: 22))
            c.setFillColor(UIColor.white.cgColor)
            c.fillEllipse(in: CGRect(x: 70, y: 60, width: 9, height: 8))
        }
        return SKTexture(image: img)
    }()

    static let trailSparkTexture: SKTexture = {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { ctx in
            let c = ctx.cgContext
            let p = UIBezierPath()
            for i in 0 ..< 8 {
                let r: CGFloat = i.isMultiple(of: 2) ? 10 : 3.4
                let a = CGFloat(i) * .pi / 4
                let pt = CGPoint(x: 12 + cos(a) * r, y: 12 + sin(a) * r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.close()
            c.setFillColor(UIColor(red: 1, green: 0.94, blue: 0.7, alpha: 1).cgColor)
            c.addPath(p.cgPath); c.fillPath()
        }
        return SKTexture(image: img)
    }()

    static let butterflyWingTexture: SKTexture = {
        let size = CGSize(width: 40, height: 56)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            // Two soft lobes, lavender with a blush edge — Aurie-world colours.
            func lobe(_ rect: CGRect, _ color: UIColor) {
                c.setFillColor(color.cgColor)
                c.fillEllipse(in: rect)
            }
            lobe(CGRect(x: 2, y: 4, width: 34, height: 28),
                 UIColor(red: 0.72, green: 0.62, blue: 0.94, alpha: 0.95))
            lobe(CGRect(x: 6, y: 26, width: 28, height: 24),
                 UIColor(red: 0.86, green: 0.64, blue: 0.90, alpha: 0.95))
            lobe(CGRect(x: 8, y: 9, width: 18, height: 13),
                 UIColor(white: 1, alpha: 0.35))
            c.setStrokeColor(UIColor(red: 0.45, green: 0.35, blue: 0.65, alpha: 0.6).cgColor)
            c.setLineWidth(1.5)
            c.strokeEllipse(in: CGRect(x: 2, y: 4, width: 34, height: 28))
            c.strokeEllipse(in: CGRect(x: 6, y: 26, width: 28, height: 24))
        }
        return SKTexture(image: img)
    }()

    static let butterflyBodyTexture: SKTexture = {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 14, height: 44)).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(red: 0.35, green: 0.28, blue: 0.45, alpha: 1).cgColor)
            let body = UIBezierPath(roundedRect: CGRect(x: 4, y: 6, width: 6, height: 34),
                                    cornerRadius: 3)
            c.addPath(body.cgPath); c.fillPath()
            // Antennae dots.
            c.fillEllipse(in: CGRect(x: 1, y: 1, width: 3, height: 3))
            c.fillEllipse(in: CGRect(x: 10, y: 1, width: 3, height: 3))
        }
        return SKTexture(image: img)
    }()

    /// Shelf icon for a toy — the same art the scene shows, so the shelf
    /// promises exactly what the toy delivers.
    static func icon(for toy: PlayToy) -> UIImage {
        let tex: SKTexture
        switch toy {
        case .bubble: tex = bubbleTexture
        case .ball: tex = ballTexture
        case .star: tex = starTexture
        case .butterfly:
            // Composite a tiny butterfly: two wings + body.
            let img = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image { _ in
                let wing = butterflyWingTexture.cgImage()
                let body = butterflyBodyTexture.cgImage()
                let w = UIImage(cgImage: wing)
                let b = UIImage(cgImage: body)
                w.draw(in: CGRect(x: 8, y: 22, width: 34, height: 48))
                UIImage(cgImage: wing, scale: 1, orientation: .upMirrored)
                    .draw(in: CGRect(x: 54, y: 22, width: 34, height: 48))
                b.draw(in: CGRect(x: 42, y: 24, width: 12, height: 40))
            }
            return img
        }
        return UIImage(cgImage: tex.cgImage())
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }
}
