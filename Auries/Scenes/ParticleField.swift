import SpriteKit
import UIKit

/// How particles MOVE, independent of what they look like. A caller composes a
/// family (the art, in `FamilyParticleArt`) with a motion preset, so no site
/// ever reinvents a family's magic.
enum ParticleMotion {
    /// Sparse, slow, barely-there. Home and environment.
    case ambient
    /// Very slow floating, long fades, nothing that flashes. Calm Mode.
    case calm
    /// Particles orbit the creature with pronounced front/back depth.
    /// `energy` drives the whole choreography.
    case swirl
    /// SNOW GLOBE: particles are flung out across the whole field, arc under
    /// gravity, settle toward the floor and fade away. Unlike `.swirl` this is
    /// free flight rather than an orbit — it fills the scene instead of
    /// ringing the creature, which is what makes a shake read as a shaken
    /// globe rather than a small decorative swirl.
    case globe
}

/// The moving half of the family particle system.
///
/// A `ParticleField` owns a FIXED POOL of sprites and recomputes their
/// positions each frame from a handful of per-particle parameters. Nodes are
/// never churned and no texture is ever built on a frame — the pool is
/// allocated once and reused for the lifetime of the scene.
///
/// Depth is real: in `.swirl` each particle rides an ellipse around the
/// creature, and its scale, alpha and z-order follow its position on that
/// ellipse, so particles genuinely pass BEHIND and IN FRONT rather than being
/// stickers on top. The near half of the orbit is the LOWER half, which keeps
/// the front layer crossing the belly instead of parking over the face.
/// Lifecycle of a `.globe` particle. The fade is owned by LANDING, never by
/// age, by the settle clock, or by the Wonder sequence's duration.
enum GlobePhase { case suspended, falling, landed, fading, inactive }

final class ParticleField: SKNode {

    private struct Particle {
        let sprite: SKSpriteNode
        var angle: CGFloat          // position on its orbit
        var speed: CGFloat          // angular speed
        /// Orbit半 radii as FRACTIONS of the body box — wide in x, shallow in
        /// y. Stored per particle so 2-3 bands can coexist.
        var bandRX: CGFloat
        var bandRY: CGFloat
        /// Small vertical offset of this particle's band from the torso
        /// centre, as a fraction of body height. Kept small: no band may sit
        /// over the head.
        var bandY: CGFloat
        var bobPhase: CGFloat
        var bobAmp: CGFloat
        var baseScale: CGFloat
        var baseAlpha: CGFloat
        var spin: CGFloat           // rotation per second (0 for non-tumbling motifs)
        var restPoint: CGPoint      // where it waits when the field is at rest
        var drift: CGVector         // ambient/calm travel
        /// How much energy must build before this one leaves the rest point.
        /// Staggered across the pool so the swirl fills from the bottom up
        /// instead of the whole ring appearing at once.
        var liftDelay: CGFloat
        /// Free-flight state, used only by `.globe`.
        var vel: CGVector = .zero
        var age: CGFloat = 0
        var lifespan: CGFloat = 1
        /// 0 = tiny fleck, 1 = hero motif. Drives fall speed, drag and how
        /// strongly the flow field pushes it around.
        var weight: CGFloat = 0.5
        var dragScale: CGFloat = 1
        var flutterPhase: CGFloat = 0
        /// +1 or -1, so flutter has no net direction across the pool.
        var flutterDir: CGFloat = 1
        /// Explicit lifecycle. A particle may ONLY begin its disappearance
        /// fade from `.landed` — nothing airborne is ever removed.
        var phase: GlobePhase = .inactive
        var settleAge: CGFloat = 0
        /// How long it rests on the ground before fading, and how long the
        /// fade takes. Varied so the floor does not clear all at once.
        var restTime: CGFloat = 0.5
        var fadeTime: CGFloat = 0.9
        /// This particle's own landing height — a narrow band, not one line.
        var floorY: CGFloat = 0
        /// Last Y, for the DEBUG one-way assertion.
        var lastY: CGFloat = 0
    }

    private let family: AuraFamily
    private let motion: ParticleMotion
    private var area: CGRect
    /// The creature's VISIBLE body box, in this node's coordinate space.
    ///
    /// The swirl used to assume the body sat at `area.midY` and size itself
    /// off the field span. That guess is what put the ring over Aurie's head:
    /// nothing in the maths referenced where the creature actually is. Callers
    /// pass the real box (`node.calculateAccumulatedFrame()`, inset past the
    /// aura) and the orbit is built around its centre.
    private var body: CGRect
    private var particles: [Particle] = []
    /// Seconds since the last `fling`, driving the globe's phase envelopes.
    private var globeTime: CGFloat = 0
    /// While true the current stays fully energised — the swirl lasts exactly
    /// as long as the player keeps shaking, not a fixed duration.
    private var globeEnergized = false
    /// Seconds since the shake stopped. Only this drives the decay.
    private var settleTime: CGFloat = 0
    /// 0…1 from the shake monitor; scales flow speed and turbulence.
    private var shakeEnergy: CGFloat = 1

    /// 0 = at rest, 1 = full intensity. Everything scales off this, so the
    /// whole field can be choreographed with one number.
    private(set) var energy: CGFloat = 0
    private var targetEnergy: CGFloat = 0
    private var energyRate: CGFloat = 1

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Reference field span, in points: an iPhone at the standard
    /// `footprint * 1.9` effect field. iPhone is the baseline look.
    private static let referenceSpan: CGFloat = 430

    /// Motif size follows the EFFECT FIELD rather than being a fixed number of
    /// points, so the particle-to-creature relationship survives a change of
    /// device. Previously an iPad kept iPhone-sized sprites on a canvas twice
    /// the width, which read as far too small against the creature.
    ///
    /// Damped with a 0.6 exponent — a linear mapping over-scales badly on iPad
    /// (~2.1x) — and clamped so an extreme layout cannot produce enormous
    /// motifs. An 11" iPad portrait lands around 1.5x.
    private var sizeScale: CGFloat {
        let span = min(area.width, area.height)
        guard span > 1 else { return 1 }
        return min(1.9, max(0.85, pow(span / Self.referenceSpan, 0.6)))
    }

    /// Rest energy per preset — never zero, so a field is always faintly alive.
    private var restEnergy: CGFloat {
        switch motion {
        case .ambient: return 0.30
        case .calm:    return 0.22
        case .swirl:   return 0.10
        case .globe:   return 0
        }
    }

    init(family: AuraFamily, area: CGRect,
         motion: ParticleMotion, count: Int? = nil, body: CGRect? = nil) {
        self.family = family
        self.motion = motion
        self.area = area
        // Fallback keeps old call sites working: the standard field is
        // `footprint * 1.9`, so the body is ~1/1.9 of the span, centred.
        let fallback = min(area.width, area.height) / 1.9
        self.body = body ?? CGRect(x: area.midX - fallback / 2,
                                   y: area.midY - fallback / 2,
                                   width: fallback, height: fallback)
        super.init()
        FamilyParticleArt.preload(family)
        build(count: count ?? Self.defaultCount(for: motion))
        energy = restEnergy
        targetEnergy = restEnergy
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// Beauty over quantity — enough for depth and richness, never noise.
    private static func defaultCount(for motion: ParticleMotion) -> Int {
        switch motion {
        case .ambient: return 14
        case .calm:    return 12
        case .swirl:   return 30
        case .globe:   return 420      // a globe should look FULL
        }
    }

    // MARK: Build

    private func build(count: Int) {
        let motifs = FamilyParticleArt.motifs(for: family)
        let intensity = FamilyParticleArt.intensity(for: family)
        let centre = CGPoint(x: area.midX, y: area.midY)
        let span = min(area.width, area.height)
        for i in 0 ..< count {
            // Accent motifs (the last two of each family) stay rare, so the
            // set reads as a coordinated mixture rather than a jumble.
            let motif = i % 5 < 3
                ? motifs[Int.random(in: 0 ..< min(3, motifs.count))]
                : motifs[Int.random(in: 0 ..< motifs.count)]
            let sprite = SKSpriteNode(texture: FamilyParticleArt.texture(motif))
            let bandSize: CGFloat = [0.78, 1.0, 1.18][i % 3]
            // A globe wants MOSTLY small flecks with a few hero motifs — a
            // uniform spread at this count reads as clutter, not snowfall.
            // THREE DEPTH TIERS. Most of the fill is cheap background motes;
            // the expensive-looking hero motifs stay rare. This is what makes
            // the globe read as full without 400 large sprites.
            //   0-7  background (8 of 12) · 8-10 midground · 11 foreground
            let tier = motion == .globe ? (i % 12) : 6
            let isHero = motion == .globe && tier == 11
            let sizeMix: CGFloat = motion == .globe
                ? (tier <= 7  ? .random(in: 0.20 ... 0.38)    // background
                 : tier <= 10 ? .random(in: 0.42 ... 0.66)    // midground
                              : .random(in: 0.92 ... 1.25))   // foreground hero
                : .random(in: 0.34 ... 0.78)
            let scale = sizeMix * (0.72 + 0.28 * intensity) * sizeScale * bandSize
            sprite.setScale(scale)
            sprite.alpha = 0
            sprite.blendMode = .add
            sprite.zRotation = .random(in: 0 ... (.pi * 2))
            addChild(sprite)

            let angle = CGFloat(i) / CGFloat(count) * .pi * 2 + .random(in: -0.3 ... 0.3)
            // Three bands, so the swirl reads as a VOLUME rather than one
            // perfect ring. All are centred on the torso; none sits over the
            // head. Wide in x, shallow in y — a horizontal orbit seen slightly
            // from above, not a halo.
            //   inner: tight and small · main: the strongest read · outer:
            //   wider, slower, carries the larger accent motifs.
            let band = i % 3
            let bandRX: CGFloat, bandRY: CGFloat, bandY: CGFloat
            switch band {
            case 0:  bandRX = .random(in: 0.56 ... 0.64)
                     bandRY = .random(in: 0.19 ... 0.23)
                     bandY  = -0.04
            case 1:  bandRX = .random(in: 0.68 ... 0.78)
                     bandRY = .random(in: 0.25 ... 0.30)
                     bandY  = 0.02
            default: bandRX = .random(in: 0.82 ... 0.90)
                     bandRY = .random(in: 0.30 ... 0.36)
                     bandY  = 0.07
            }
            particles.append(Particle(
                sprite: sprite,
                angle: angle,
                // Per-band angular rate, so the swirl never reads as one
                // rigid ring: the tight inner band runs fastest, the wide
                // outer accent band slowest, with jitter on top. All the same
                // direction — counter-rotation reads as chaos, not magic.
                speed: [1.22, 1.00, 0.82][band] * .random(in: 0.88 ... 1.12),
                bandRX: bandRX,
                bandRY: bandRY,
                bandY: bandY,
                bobPhase: .random(in: 0 ... (.pi * 2)),
                bobAmp: span * .random(in: 0.012 ... 0.045),
                baseScale: scale,
                baseAlpha: (motion == .globe
                            ? (tier <= 7 ? CGFloat.random(in: 0.34 ... 0.58)
                             : tier <= 10 ? CGFloat.random(in: 0.62 ... 0.86)
                                          : CGFloat.random(in: 0.90 ... 1.0))
                            : .random(in: 0.55 ... 1.0)) * intensity,
                spin: .random(in: -0.6 ... 0.6),
                restPoint: CGPoint(x: centre.x + .random(in: -span*0.34 ... span*0.34),
                                   y: area.minY + span * .random(in: 0.06 ... 0.30)),
                drift: CGVector(dx: .random(in: -6 ... 6), dy: .random(in: 8 ... 26)),
                // Particles destined for the top of the ring wait longest, so
                // the ring grows upward rather than switching on.
                liftDelay: (sin(angle) * 0.5 + 0.5) * 0.26 + .random(in: 0 ... 0.08),
                // Weight is fixed WITH the sprite size, so heavy particles are
                // always the visibly large ones. Deciding it at fling time
                // meant a "hero" could land on a tiny fleck.
                weight: isHero ? .random(in: 0.75 ... 1.0)
                       : tier <= 7 ? .random(in: 0.0 ... 0.22)
                                   : .random(in: 0.25 ... 0.5)))
        }
    }

    /// Re-fit after a layout change without rebuilding the pool.
    func setBounds(_ rect: CGRect) { area = rect }

    #if DEBUG
    /// Draws the geometry the swirl is actually using: body box, torso
    /// centre, the three orbit bands and the face-clear disc. Enabled with
    /// AURIE_ORBIT_DEBUG=1. Never shipped — the whole block is DEBUG-only and
    /// nothing calls it unless the variable is set.
    func showOrbitDebug() {
        guard ProcessInfo.processInfo.environment["AURIE_ORBIT_DEBUG"] == "1"
        else { return }
        childNode(withName: "orbitDebug")?.removeFromParent()
        let g = SKNode()
        g.name = "orbitDebug"
        g.zPosition = 40
        let torso = CGPoint(x: body.midX, y: body.midY)

        let box = SKShapeNode(rect: body)
        box.strokeColor = .systemGreen; box.lineWidth = 2; box.fillColor = .clear
        g.addChild(box)

        let dot = SKShapeNode(circleOfRadius: 5)
        dot.position = torso; dot.fillColor = .systemGreen
        dot.strokeColor = .clear
        g.addChild(dot)

        for (rx, ry, dy, c) in [(0.62, 0.21, -0.04, SKColor.systemTeal),
                                (0.75, 0.27,  0.02, SKColor.systemYellow),
                                (0.86, 0.33,  0.07, SKColor.systemOrange)] {
            let r = CGRect(x: torso.x - body.width * rx,
                           y: torso.y + body.height * dy - body.height * ry,
                           width: body.width * rx * 2,
                           height: body.height * ry * 2)
            let e = SKShapeNode(ellipseIn: r)
            e.strokeColor = c; e.lineWidth = 2; e.fillColor = .clear
            g.addChild(e)
        }

        let fr = min(body.width, body.height) * 0.19
        let f = SKShapeNode(circleOfRadius: fr)
        f.position = CGPoint(x: torso.x, y: body.maxY - body.height * 0.48)
        f.strokeColor = .systemRed; f.lineWidth = 2; f.fillColor = .clear
        g.addChild(f)
        addChild(g)
    }
    #endif

    /// Tell the field where the creature actually is. The swirl orbits this
    /// box's centre, so it must be the visible BODY, not the aura or the
    /// field. Safe to call after construction.
    func setBody(_ rect: CGRect) { body = rect }

    // MARK: Energy

    /// Ease the field toward a new intensity. This is the whole choreography
    /// API: wake, build, peak and settle are all just target energies.
    func setEnergy(_ target: CGFloat, duration: TimeInterval) {
        targetEnergy = max(0, min(1, target))
        energyRate = duration > 0
            ? abs(targetEnergy - energy) / CGFloat(duration)
            : .greatestFiniteMagnitude
    }

    /// Drain back to the preset's resting intensity.
    func settle(duration: TimeInterval = 2.2) {
        setEnergy(restEnergy, duration: duration)
    }

    // MARK: Per-frame

    func update(_ dt: TimeInterval) {
        let step = CGFloat(min(dt, 1.0 / 20))
        // Ease energy toward its target.
        if energy != targetEnergy {
            let delta = energyRate * step
            energy = energy < targetEnergy
                ? min(targetEnergy, energy + delta)
                : max(targetEnergy, energy - delta)
        }
        // Reduce Motion keeps the particles visible but calm: no fast orbit,
        // no big excursions — the policy HomeBackgroundView established.
        let e = reduceMotion ? min(energy, 0.45) : energy
        switch motion {
        case .swirl:            updateSwirl(step, energy: e)
        case .ambient, .calm:   updateDrift(step, energy: e)
        case .globe:            updateGlobe(step)
        }
    }

    private func updateSwirl(_ dt: CGFloat, energy e: CGFloat) {
        // EVERYTHING here is measured from the creature's real body box.
        let torso = CGPoint(x: body.midX, y: body.midY)
        let bw = body.width, bh = body.height
        // Face-clear protects the FACE ONLY — eyes, mouth and immediately
        // around them. It used to be a span-sized disc that swallowed the
        // whole upper body, and because the only escape was outward it helped
        // push the entire orbit over the head.
        let face = CGPoint(x: torso.x, y: body.maxY - bh * 0.48)
        let faceRadius = min(bw, bh) * 0.19
        let spinScale: CGFloat = reduceMotion ? 0.3 : 1

        for i in particles.indices {
            var p = particles[i]
            // Energy drives angular velocity, so the orbit accelerates
            // through the build and decelerates back through the settle
            // without ever switching between discrete speeds.
            //
            //   rest  (e≈0.10): ~0.5-1.0 rad/s  -> 6-12 s period, graceful
            //   peak  (e=1.0):  ~1.7-3.2 rad/s  -> 2.0-3.6 s period
            //
            // The old `0.25 + e * 1.25` topped out near 1.3 rad/s, which left
            // the peak at a 5-12 s period — too slow to read as circling.
            let omega = 0.55 + 1.85 * e
            p.angle += p.speed * omega * dt * spinScale
            p.bobPhase += dt * 1.1

            // A HORIZONTAL RING AROUND THE TORSO, projected.
            //
            //   x     = cos(phase) * (wide radius)
            //   depth = sin(phase)              +1 near · -1 far
            //   y     = torso + band offset - depth * (shallow radius)
            //
            // Depth comes from the SAME phase as x, so front/back is never
            // decided independently of position: the far half is genuinely
            // behind the creature and gets occluded, the near half genuinely
            // in front. `-depth` puts the near half LOW (belly, lower sides)
            // and the far half high (behind the shoulders) — a ring seen from
            // slightly above, which is what makes the loop read as 3D.
            let cosA = cos(p.angle)
            let depth = sin(p.angle)
            let frontness = (depth + 1) / 2
            // Near side reads further from centre, as a real ring does.
            let persp = 1 + 0.22 * depth
            let open = 0.55 + 0.45 * e           // energy opens the orbit

            let rx = bw * p.bandRX * persp * open
            let ry = bh * p.bandRY * open
            var pos = CGPoint(
                x: torso.x + cosA * rx,
                // NO cumulative vertical term. `bob` is a bounded sine, so a
                // particle loops the same orbit forever instead of drifting
                // upward the way `.ambient` is meant to.
                y: torso.y + p.bandY * bh - depth * ry
                   + sin(p.bobPhase) * p.bobAmp)

            // Energy lifts the particle from its rest point onto the orbit,
            // staggered so the ring fills in rather than switching on.
            // Lift completes by e≈0.55 rather than tracking energy all the
            // way to 1.0. Above that every particle is fully ON its orbit and
            // only alpha and angular speed vary with energy — so a settled
            // swirl is a slow ORBIT, not a huddle stranded partway between
            // the rest points and the ring.
            //
            // The hatch rise is unaffected in kind: it still runs from e=0 up
            // through this range, just completing earlier in the ramp. Peak is
            // bit-identical, since lift was already saturated at e=1.
            let eLift = min(1, e / 0.55)
            let span0 = max(0.05, 1 - p.liftDelay)
            let l = min(1, max(0, (eLift - p.liftDelay) / span0))
            let lift = l * l * (3 - 2 * l)          // smoothstep
            if lift < 1 {
                pos = CGPoint(x: p.restPoint.x + (pos.x - p.restPoint.x) * lift,
                              y: p.restPoint.y + (pos.y - p.restPoint.y) * lift)
            }

            // FRONT-HALF KEEP-OUT. The far half needs nothing — it draws at
            // z -3 behind an opaque body and is occluded for free, which is
            // exactly the disappear-and-reappear that sells the orbit. This
            // only bows the NEAR arc out around the belly perimeter, and it
            // resolves LATERALLY/DOWNWARD (never up over the head) because
            // the near arc already sits below the torso centre.
            if frontness > 0.5 && lift > 0.05 {
                let dx = pos.x - torso.x
                let dy = pos.y - torso.y
                let norm = hypot(dx / (bw * 0.52), dy / (bh * 0.46))
                if norm < 1 {
                    let push = 1 / max(norm, 0.12)
                    pos.x = torso.x + dx * push
                    pos.y = torso.y + dy * push
                }
            }
            p.sprite.position = pos

            // Depth ordering, size and brightness all from the same phase.
            p.sprite.zPosition = depth > 0 ? 3 : -3
            p.sprite.setScale(p.baseScale * (0.76 + 0.42 * frontness))
            var alpha = p.baseAlpha * (0.55 + 0.45 * frontness)
                      * (0.25 + 0.75 * e) * lift
            // Small, face-only backstop.
            if frontness > 0.5 {
                let d = hypot(pos.x - face.x, pos.y - face.y)
                if d < faceRadius { alpha *= 0.20 + 0.80 * (d / faceRadius) }
            }
            p.sprite.alpha = alpha
            p.sprite.zRotation += p.spin * dt * spinScale
            particles[i] = p
        }
    }

    private func updateDrift(_ dt: CGFloat, energy e: CGFloat) {
        let spinScale: CGFloat = reduceMotion ? 0.3 : 1
        for i in particles.indices {
            var p = particles[i]
            p.bobPhase += dt * 0.8
            var pos = p.sprite.position == .zero ? p.restPoint : p.sprite.position
            pos.x += (p.drift.dx + sin(p.bobPhase) * 6) * dt * (0.4 + e)
            pos.y += p.drift.dy * dt * (0.4 + e)
            // Wrap gently from the top back to the bottom of the field.
            if pos.y > area.maxY {
                pos.y = area.minY
                pos.x = area.midX + .random(in: -area.width*0.34 ... area.width*0.34)
            }
            if pos.x < area.minX { pos.x = area.maxX }
            if pos.x > area.maxX { pos.x = area.minX }
            p.sprite.position = pos
            // Fade in and out across the vertical travel so nothing pops.
            let travel = (pos.y - area.minY) / max(area.height, 1)
            let envelope = sin(max(0, min(1, travel)) * .pi)
            p.sprite.alpha = p.baseAlpha * envelope * (0.35 + 0.65 * e)
            p.sprite.zRotation += p.spin * dt * 0.5 * spinScale
            particles[i] = p
        }
    }

    // MARK: Snow globe

    /// Shake the globe.
    ///
    /// Phase 1 only: distribute particles throughout the WHOLE play area and
    /// give them a starting velocity aligned with the flow, so the scene is
    /// already full and already moving coherently within a few frames. The
    /// motion itself comes from `updateGlobe`'s flow field, not from this
    /// impulse — a burst of impulses is what read as a confetti cannon.
    func fling(from origin: CGPoint, power: CGFloat = 1) {
        globeTime = 0
        let span = min(area.width, area.height)
        for i in particles.indices {
            var p = particles[i]
            // STRATIFIED, not uniform-random. Plain `random` over the whole
            // rect clumps and leaves obvious bare regions (Poisson clumping);
            // seeding one particle per cell of a loose grid and jittering
            // inside the cell gives even coverage that still looks random.
            let cols = 7, rows = 9
            let cell = i % (cols * rows)
            let cx = CGFloat(cell % cols), cy = CGFloat(cell / cols)
            let jx = CGFloat.random(in: 0.05 ... 0.95)
            let jy = CGFloat.random(in: 0.05 ... 0.95)
            let pos = CGPoint(
                x: area.minX + area.width  * (cx + jx) / CGFloat(cols),
                y: area.minY + area.height * (cy + jy) / CGFloat(rows))
            p.sprite.position = pos
            // Start on the current, not against it.
            let v = flowVelocity(at: pos, time: 0)
            p.vel = CGVector(dx: v.dx * .random(in: 0.6 ... 1.2) * power,
                             dy: v.dy * .random(in: 0.6 ... 1.2) * power)
            p.dragScale = .random(in: 0.8 ... 1.25)
            p.flutterPhase = .random(in: 0 ... (.pi * 2))
            p.flutterDir = Bool.random() ? 1 : -1
            p.spin = .random(in: -0.9 ... 0.9)
            p.age = 0
            // Purely a leak guard. Long enough that under normal physics every
            // particle has landed and faded — never part of the choreography.
            p.lifespan = 45
            p.phase = .suspended
            p.settleAge = 0
            p.restTime = .random(in: 0.30 ... 0.80)
            p.fadeTime = .random(in: 0.60 ... 1.20)
            // A narrow, organic landing band rather than one flat line.
            p.floorY = area.minY + span * .random(in: 0.015 ... 0.075)
            p.sprite.zPosition = p.weight > 0.7 ? 3 : (Bool.random() ? 3 : -3)
            p.sprite.alpha = 0
            particles[i] = p
        }
    }

    /// ONE ENORMOUS, SLOW, IRREGULAR CURRENT across the whole field.
    ///
    /// A loose Rankine vortex about a drifting centre, plus two octaves of
    /// low-frequency sine "noise". Deliberately NOT `angle += omega` — that
    /// produces concentric rings, which is the orbit look this is meant to
    /// replace. Here every particle simply samples the field at its own
    /// position, so paths are long, curved and never repeat.
    private func flowVelocity(at pos: CGPoint, time t: CGFloat) -> CGVector {
        let span = min(area.width, area.height)
        // The centre wanders, so the current never reads as a spinner.
        let cx = area.midX + sin(t * 0.23) * area.width * 0.17
        let cy = area.midY + cos(t * 0.31) * area.height * 0.13
        let dx = pos.x - cx, dy = pos.y - cy
        let r = max(hypot(dx, dy), 1)
        // Tangential unit vector.
        let tx = -dy / r, ty = dx / r
        // Rankine profile: solid-body rotation in the core, gentle decay
        // outside, so the whole scene circulates rather than a tight middle.
        let rn = r / (span * 0.62)
        let profile = rn < 1 ? rn : 1 / max(rn, 0.001)
        let tang = span * 0.34 * profile * shakeEnergy

        // Low-frequency, smooth. High-frequency noise reads as jitter.
        let n1 = sin(pos.y / (span * 0.44) + t * 0.33)
               + 0.55 * sin(pos.y / (span * 0.21) - t * 0.21)
        let n2 = cos(pos.x / (span * 0.40) - t * 0.27)
               + 0.55 * cos(pos.x / (span * 0.18) + t * 0.18)
        let noise = span * 0.16
        return CGVector(dx: tx * tang + n1 * noise,
                        dy: ty * tang + n2 * noise)
    }

    /// Hold or release the current. Called from the shake state machine.
    func setGlobeEnergized(_ on: Bool, energy: CGFloat = 1) {
        shakeEnergy = max(0.45, min(1.35, energy))
        guard on != globeEnergized else { return }
        globeEnergized = on
        guard !on else { return }
        settleTime = 0                     // decay starts NOW, not at fling

        // SHAKE RELEASE IS A GLOBAL PHASE CHANGE.
        //
        // Every suspended particle leaves the upward-capable state on THIS
        // frame. Staggering the transition was the bug: while some particles
        // were visibly falling, others were still suspended and still taking
        // the full vortex, so the snowfall appeared to reverse. Variety comes
        // from fall SPEED, never from some particles still rising.
        #if DEBUG
        landBuckets = [Int](repeating: 0, count: 6)
        landLogged = false
        #endif
        var moved = 0
        for i in particles.indices where particles[i].phase == .suspended {
            particles[i].phase = .falling
            // Keep horizontal momentum; kill any upward momentum outright.
            particles[i].vel.dy = min(particles[i].vel.dy, 0)
            moved += 1
        }
        #if DEBUG
        NSLog("AURIE_GLOBE SHAKE RELEASE — %d particles -> falling", moved)
        upwardViolations = 0
        #endif
    }

    private func updateGlobe(_ dt: CGFloat) {
        globeTime += dt
        let t = globeTime
        if !globeEnergized { settleTime += dt }
        let span = min(area.width, area.height)
        let spinScale: CGFloat = reduceMotion ? 0.3 : 1

        let swirl: CGFloat = globeEnergized
            ? min(1, t / 0.4)
            : max(0, 1 - settleTime / 1.5)
        let gravity: CGFloat = globeEnergized
            ? 0
            : min(1, settleTime / 1.8)

        for i in particles.indices {
            var p = particles[i]
            if p.phase == .inactive { p.sprite.alpha = 0; particles[i] = p; continue }
            p.age += dt
            p.flutterPhase += dt * (1.1 + p.weight)

            // Leak guard ONLY. Under normal physics this never fires.
            if p.age > p.lifespan { p.phase = .inactive; p.sprite.alpha = 0
                                    particles[i] = p; continue }

            var pos = p.sprite.position
            var v = p.vel

            switch p.phase {
            case .suspended:
                // The vortex owns this particle. It may travel in ANY
                // direction, including upward.
                if swirl > 0 {
                    let f = flowVelocity(at: pos, time: t)
                    let follow = (1.9 - 0.8 * p.weight) * swirl * dt
                    v.dx += (f.dx - v.dx) * min(1, follow)
                    v.dy += (f.dy - v.dy) * min(1, follow)
                }
                v.dy -= span * 0.85 * (0.45 + p.weight) * gravity * dt
                let drag = (0.55 + 0.9 * gravity) * p.dragScale
                v.dx *= (1 - min(0.9, drag * dt))
                v.dy *= (1 - min(0.9, drag * dt))
                pos.x += v.dx * dt
                pos.y += v.dy * dt
                // Wrap only while suspended.
                if pos.x < area.minX { pos.x = area.maxX }
                if pos.x > area.maxX { pos.x = area.minX }
                if pos.y > area.maxY { pos.y = area.maxY; v.dy = min(v.dy, 0) }
                // NOTE: there is no per-particle commit here. The whole pool
                // leaves `.suspended` together, in `setGlobeEnergized(false)`.
                p.sprite.alpha = p.baseAlpha * min(1, p.age / 0.35)

            case .falling:
                // ONE-WAY, and NO vortex sampling.
                //
                // This used to keep steering `v.dx` toward the flow field's
                // horizontal component, which looked reasonable but carried a
                // systematic bias: the tangential x of a vortex is `-dy / r`,
                // so every particle BELOW the centre — which is all of them,
                // once they are falling — got pushed the same way. They swept
                // right together and piled in the lower-right corner.
                //
                // Instead each particle keeps the horizontal velocity it had
                // at release and lets it decay. Those velocities were varied
                // by position in the swirl, so sideways drift stays rich and
                // the landings spread across the whole floor.
                v.dy -= span * 0.85 * (0.45 + p.weight) * dt
                v.dx += sin(p.flutterPhase) * span * 0.30 * (0.3 + p.weight)
                      * p.flutterDir * dt
                v.dx *= (1 - min(0.9, 1.45 * p.dragScale * dt))
                if v.dy > 0 { v.dy = 0 }
                let terminal = -span * (0.13 + 0.20 * p.weight)
                if v.dy < terminal { v.dy = terminal }

                pos.x += v.dx * dt
                pos.y += v.dy * dt
                pos.x = min(max(pos.x, area.minX + 4), area.maxX - 4)

                if pos.y <= p.floorY {
                    // Rest where it actually arrived. Snapping UP to the
                    // nominal floor was a real (if small) upward move — a fast
                    // faller can overshoot ~10pt in a frame, and the assertion
                    // correctly flagged it.
                    p.floorY = pos.y
                    p.phase = .landed
                    #if DEBUG
                    recordLanding(x: pos.x)
                    #endif
                    p.settleAge = 0
                    v.dy = 0
                    v.dx *= 0.35
                }
                p.sprite.alpha = p.baseAlpha * min(1, p.age / 0.35)

            case .landed:
                // Rest on the ground, still fully visible, sliding to a stop.
                p.settleAge += dt
                v.dx *= (1 - min(0.9, 3.2 * dt))
                pos.x += v.dx * dt
                p.sprite.alpha = p.baseAlpha
                if p.settleAge >= p.restTime {
                    p.phase = .fading
                    p.settleAge = 0
                }

            case .fading:
                p.settleAge += dt
                v.dx *= (1 - min(0.9, 4.0 * dt))
                pos.x += v.dx * dt
                let k = min(1, p.settleAge / p.fadeTime)
                p.sprite.alpha = p.baseAlpha * (1 - k * k)
                if k >= 1 { p.phase = .inactive; p.sprite.alpha = 0 }

            case .inactive:
                break
            }

            #if DEBUG
            // One-way assertion. Sub-pixel tolerance only.
            if (p.phase == .falling || p.phase == .landed), pos.y > p.lastY + 0.5 {
                upwardViolations += 1
                worstRise = max(worstRise, pos.y - p.lastY)
                if upwardViolations % 60 == 1 {
                    NSLog("AURIE_GLOBE UPWARD VIOLATION #%d rise=%.1fpt",
                          upwardViolations, pos.y - p.lastY)
                }
            }
            p.lastY = pos.y
            #endif
            p.vel = v
            p.sprite.position = pos
            p.sprite.zRotation += p.spin * dt * spinScale
                                * (p.phase == .suspended || p.phase == .falling ? 1 : 0.1)
            particles[i] = p
        }
    }

    #if DEBUG
    /// Counts any frame where a falling/landed particle moved UP. Must stay
    /// zero after a release — this is the assertion behind the visual claim.
    private(set) var upwardViolations = 0
    private var worstRise: CGFloat = 0
    #endif

    #if DEBUG
    /// Landing x accumulated AT THE MOMENT each particle lands, in 6 buckets
    /// left-to-right. Sampling "currently landed" missed most of them, since
    /// a particle only rests then fades for a second or two.
    private var landBuckets = [Int](repeating: 0, count: 6)
    private var landLogged = false

    private func recordLanding(x: CGFloat) {
        let f = (x - area.minX) / max(area.width, 1)
        landBuckets[min(5, max(0, Int(f * 6)))] += 1
        let total = landBuckets.reduce(0, +)
        if !landLogged, total >= 300 {
            landLogged = true
            NSLog("AURIE_GLOBE LANDING SPREAD (L->R) %@  of %d",
                  landBuckets.map(String.init).joined(separator: " | "), total)
        }
    }
    #endif

    /// True once every globe particle has landed AND finished fading. The
    /// scene waits for this before tearing the field down, so no visible
    /// particle is ever removed mid-air by the sequence ending.
    var isGlobeFinished: Bool {
        motion == .globe && particles.allSatisfy { $0.phase == .inactive }
    }

    #if DEBUG
    /// Diagnostic for the settle poll: which phases are still holding the
    /// globe open. Gated by the caller on AURIE_GLOBE_SCALE_LOG.
    func logGlobePhases() {
        var counts: [String: Int] = [:]
        for p in particles { counts["\(p.phase)", default: 0] += 1 }
        let summary = counts.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        NSLog("AURIE_GLOBE poll motion=%@ finished=%@ %@",
              "\(motion)", isGlobeFinished ? "YES" : "no", summary)
    }
    #endif

    // MARK: One-shot bursts

    /// An energetic outward burst that dissipates gracefully — celebrations,
    /// reaction puffs, and Wonderglobe's reveal accent all use this.
    /// Spawn-and-remove rather than pooled: it is short-lived by nature.
    /// The shared CELEBRATION: three overlapping waves rather than one
    /// synchronous explosion. Richness comes from choreography — a main
    /// burst, a tighter secondary a beat later, and a few slower, larger
    /// accent motifs — which reads fuller than simply doubling the sprite
    /// count at a single instant.
    ///
    /// Every wave spawns on a RING at the body's perimeter, not at its
    /// centre, so the particles frame the creature instead of erupting
    /// through the face and belly.
    func celebrate(at point: CGPoint, spread: CGFloat) {
        burst(count: 18, at: point, spread: spread, fromRing: 0.55)
        run(.sequence([
            .wait(forDuration: 0.19),
            .run { [weak self] in
                self?.burst(count: 12, at: point, spread: spread * 0.80,
                            fromRing: 0.42)
            }]))
        // Accents: slower, larger, drawn from the rare end of the motif list.
        run(.sequence([
            .wait(forDuration: 0.08),
            .run { [weak self] in
                self?.burst(count: 6, at: point, spread: spread * 1.12,
                            fromRing: 0.68, sizeBias: 1.45, speedBias: 0.62,
                            preferAccents: true)
            }]))
    }

    /// - Parameters:
    ///   - fromRing: 0 spawns everything at `point`; 1 spawns on a ring of
    ///     radius `spread * 0.5`. Non-zero keeps a burst clear of the centre.
    ///   - sizeBias: multiplies motif size (accent waves run larger).
    ///   - speedBias: multiplies travel time (below 1 is slower, lingering).
    ///   - preferAccents: draw from the rare tail of the family's motif list.
    func burst(count: Int, at point: CGPoint, spread: CGFloat,
               rising: Bool = true, fromRing: CGFloat = 0,
               sizeBias: CGFloat = 1, speedBias: CGFloat = 1,
               preferAccents: Bool = false) {
        let motifs = FamilyParticleArt.motifs(for: family)
        let slow: CGFloat = reduceMotion ? 0.55 : 1
        for i in 0 ..< count {
            // Spread the draw across the whole set so a denser burst keeps its
            // variety instead of filling up with one texture.
            let motif: FamilyParticleArt.Motif
            if preferAccents, motifs.count >= 2 {
                motif = motifs[Int.random(in: (motifs.count - 2) ..< motifs.count)]
            } else {
                motif = motifs[(i + Int.random(in: 0 ..< motifs.count)) % motifs.count]
            }
            let sprite = SKSpriteNode(texture: FamilyParticleArt.texture(motif))
            sprite.setScale(.random(in: 0.32 ... 0.72) * sizeScale * sizeBias)
            let ringAngle = CGFloat(i) / CGFloat(max(count, 1)) * .pi * 2
                          + .random(in: -0.35 ... 0.35)
            let ringR = spread * 0.5 * fromRing
            sprite.position = CGPoint(x: point.x + cos(ringAngle) * ringR,
                                      y: point.y + sin(ringAngle) * ringR * 0.85)
            sprite.alpha = 0
            sprite.blendMode = .add
            sprite.zPosition = Bool.random() ? 3 : -3
            sprite.zRotation = .random(in: 0 ... (.pi * 2))
            addChild(sprite)

            let angle = ringR > 0
                ? ringAngle + .random(in: -0.25 ... 0.25)
                : CGFloat(i) / CGFloat(count) * .pi * 2 + .random(in: -0.4 ... 0.4)
            let distance = spread * .random(in: 0.45 ... 1.0) * slow
            let target = CGPoint(x: sprite.position.x + cos(angle) * distance,
                                 y: sprite.position.y + sin(angle) * distance * 0.7
                                    + (rising ? spread * 0.45 : 0))
            let travel = TimeInterval.random(in: 0.85 ... 1.5) / Double(speedBias)
            let move = SKAction.move(to: target, duration: travel)
            move.timingMode = .easeOut          // fast out, gentle arrival
            let fade = SKAction.sequence([
                .fadeAlpha(to: .random(in: 0.7 ... 1.0), duration: 0.16),
                .wait(forDuration: travel * 0.45),
                .fadeOut(withDuration: travel * 0.5)])
            let spin = SKAction.rotate(byAngle: .random(in: -1.6 ... 1.6),
                                       duration: travel)
            // Staggered, so a burst blooms rather than snapping into place.
            sprite.run(.sequence([
                .wait(forDuration: Double(i) * 0.022),
                .group([move, fade, spin]),
                .removeFromParent()]))
        }
    }

    /// The restrained family flourish used at Wonderglobe's reveal: a tight
    /// ring of that family's motifs blooming outward from the creature.
    func accentBeat(at point: CGPoint) {
        burst(count: reduceMotion ? 6 : 12,
              at: point,
              spread: min(area.width, area.height) * 0.34)
    }
}
