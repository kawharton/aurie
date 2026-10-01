import UIKit
import SpriteKit

// MARK: - AurieNode
//
// Assembles one creature from separate part sprites (so it can be tinted AND
// rigged), then animates it procedurally from a single front-facing art set:
// it breathes, blinks, squashes, hops to move, and mirror-flips to face
// left/right.
//
// Transform layers (Stage D). Each layer owns ONE kind of motion so actions
// compose instead of fighting over the same property:
//   self (AurieNode)  -> logical scene position (hop arc, carry) and the
//                        PERMANENT responsive scale the scene sets. Collision
//                        and the speech-bubble anchor read only these, so no
//                        transient motion below can disturb them.
//   shadowNode        -> contact shadow, a direct child of self: it follows
//                        the creature but is never squashed/tilted with the
//                        body, and stays grounded while the body arcs.
//   root              -> facing flip (xScale sign) + transient TILT (pet lean,
//                        tickle wiggle, carry tilt, tumble) + seated offsets.
//   squashNode        -> transient interaction squash/stretch only. All
//                        interaction squashes share one action key
//                        ("motionSquash") and end at exactly 1.0, so the
//                        newest always cleanly replaces the old.
//   breatheNode       -> idle/calm breathing scale only, composing with the
//                        squash above it rather than competing for it.

final class AurieNode: SKNode {

    private enum Z: CGFloat { case aura = 0, limbs = 1, body = 2, pattern = 3,
                                    charm = 4, eyes = 5, mouth = 6 }

    private enum Z2: CGFloat { case shadow = -1 }

    private let root = SKNode()
    private let squashNode = SKNode()
    private let breatheNode = SKNode()
    private let shadowNode = SKSpriteNode()
    private let bodyNode = SKSpriteNode()
    private let limbsNode = SKSpriteNode()
    private let patternNode = SKSpriteNode()
    private let eyesNode = SKSpriteNode()
    private let mouthNode = SKSpriteNode()
    private let auraNode = SKSpriteNode()

    private var facing: CGFloat = 1

    /// When false, `hop` is a hard no-op: the creature never changes its
    /// position. Calm mode sets this false so the Aurie stays planted; play
    /// mode leaves it true so a deliberate tap on empty space still hops.
    var hopsEnabled = true

    /// Re-weight the aura for the backdrop it is landing on. The glow is
    /// ADDITIVE: on a dark environment a modest alpha reads as a strong halo,
    /// while the SAME alpha on a bright one barely shifts the pixels. Left
    /// uncompensated the aura is a 40% lift on Dusk and 15% on Stone, which
    /// is the difference between obvious and invisible. Scaling alpha AND
    /// size with backdrop brightness converges them from both directions.
    func applyAuraStrength(backdropLuminance l: CGFloat) {
        let t = min(max((l - 0.22) / 0.42, 0), 1)     // 0 dark … 1 bright
        // Alpha caps at 1, and equal ABSOLUTE lift is not equal perceived
        // glow: measured on the same creature, the aura lifts a 42/255 Dusk
        // backdrop by 58% but a 104/255 Stone backdrop by only 24%. Size is
        // the remaining lever — a broader halo reads on bright ground even
        // when it cannot be made brighter.
        auraNode.alpha = 0.60 + t * 0.40              // 0.60 … 1.00
        auraNode.setScale(Self.auraScale * (1 + t * 0.55))
    }

    /// How much larger the aura glow is than its native texture footprint.
    /// 1.5x: a broader glow than the original tight halo, while still fading
    /// out well inside the play area so its edge never reaches the app frame.
    static let auraScale: CGFloat = 1.4

    /// Master switch for input-driven eye tracking — the eyes/sparkles easing
    /// toward a finger or a tapped point. Gates the two input primitives,
    /// `glanceToward` (play-mode finger-notice) and `lookToward` (calm-mode
    /// drag/tap). Autonomous liveliness — `lookAround`, `noticeOffscreen` — is
    /// independent of this.
    static let eyesFollowInput = true

    /// Finger-notice = only the SPARKLES (catchlights) follow the finger; the
    /// dark eye stays put. The sparkles are their own exported layer drawn on
    /// `catchNode`, a CHILD of `eyesNode` (so it inherits every eye transform —
    /// blink squash, sitDip, per-expression reposition). `catchRest` is the
    /// sparkle's neutral position RELATIVE to the eye; `eyeLookOffset` is the
    /// live offset toward the finger, re-applied on every face swap so a blink
    /// mid-track keeps the glance. The clamp keeps the sparkle inside the eye.
    private static let eyeTrackX: CGFloat = 7
    private static let eyeTrackY: CGFloat = 5
    private let catchNode = SKSpriteNode()
    private var catchRest: CGPoint = .zero
    private var eyeLookOffset: CGPoint = .zero

    /// Hide the contact shadow. A still portrait floats on a tile — there is
    /// no ground beneath it for a shadow to fall on.
    func hideContactShadow() { shadowNode.isHidden = true }

    /// Perspective-depth shadow weight: near = larger/denser, far =
    /// smaller/lighter. Multipliers come from the playfield definition.
    /// `duration` > 0 eases there (hops); 0 sets directly (per-frame drags).
    func applyDepthShadow(alpha: CGFloat, scale: CGFloat,
                          duration: TimeInterval = 0) {
        let a = min(1, max(0.2, Self.shadowRestAlpha * alpha))
        let sc = max(0.4, scale)
        shadowNode.removeAction(forKey: "shadowDepth")
        if duration > 0 {
            shadowNode.run(.group([.fadeAlpha(to: a, duration: duration),
                                   .scale(to: sc, duration: duration)]),
                           withKey: "shadowDepth")
        } else {
            shadowNode.alpha = a
            shadowNode.setScale(sc)
        }
    }

    /// Contact-shadow rest pose — every shadow animation returns exactly here.
    private static let shadowRestPosition = CGPoint(x: 0, y: -185)
    private static let shadowRestAlpha: CGFloat = 0.85

    /// Flatten motion when the system asks for it; checked per action so a
    /// mid-session settings change is respected.
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Extra sprites used only by the Blender skin (the placeholder path
    /// packs both arms into one `limbsNode` and has no separate tuft/cheeks).
    private var blenderLayers: [String: SKSpriteNode] = [:]
    private var blenderBody: BodyType = .round
    private var blenderArmStyle = "arm_00"
    private var blenderLegStyle = "leg_01"
    private var blenderHairStyle = "tuft"
    /// The pattern mask layer to composite onto the body (e.g.
    /// `pattern_spots_v1`), or nil for a plain Aurie. Set once at build.
    private var blenderPatternLayer: String?
    /// The family base colour the skin was built with — a runtime
    /// orientation swap rebuilds the layer stack with the same tint.
    private var blenderBaseColor: SKColor = .white
    /// Layer keys of the charms this creature wears (layer key ==
    /// charm id, e.g. `charm_object_backpack_01`). Set at build, reused
    /// verbatim by every orientation rebuild.
    private var blenderCharmLayers: [String] = []
    /// The equipped BELLY-placement charm, if any — drawn as a flat
    /// sticker on the belly patch (frozen presentation 2026-09-17).
    private var blenderBellyStickerID: String?
    private var blenderAuraCharmID: String?
    private var blenderFloatingCharmID: String?
    /// Body group (body, tuft, face, arms) rises by the leg style's lift —
    /// the legs were exported with the body already raised.
    private var blenderLift: CGFloat = 0
    private let cheeksNode = SKSpriteNode()
    private(set) var usesBlenderSkin = false

    /// Runtime-only facing of THIS node. Set at build time; never read
    /// from or written to the saved Aurie. `.back` renders the real
    /// 3D-exported back layers (never a flipped/hidden-face front) and
    /// omits the face group. If back art is unavailable for the body,
    /// the node silently builds front — the documented fallback.
    private(set) var orientation: AurieOrientation = .front

    init(textures: [String: SKTexture],
         baseColor: SKColor,
         auraColor: SKColor,
         body: BodyType? = nil,
         armStyle: String? = nil,
         legStyle: String? = nil,
         hairStyle: String? = nil,
         patternLayer: String? = nil,
         charmLayers: [String] = [],
         bellyStickerCharmID: String? = nil,
         auraCharmID: String? = nil,
         floatingCharmID: String? = nil,
         orientation: AurieOrientation = .front) {
        self.orientation = orientation
        blenderCharmLayers = charmLayers
        blenderBellyStickerID = bellyStickerCharmID
        blenderAuraCharmID = auraCharmID
        blenderFloatingCharmID = floatingCharmID
        super.init()

        addChild(root)
        root.addChild(squashNode)
        squashNode.addChild(breatheNode)

        // Soft contact shadow on the "ground" beneath the feet. A child of
        // self (not the squash stack): it scales with the permanent creature
        // scale and follows its position, but body squash/tilt never distort
        // it — its weight cues are driven explicitly by the hop/carry code.
        shadowNode.texture = Self.contactShadowTexture
        shadowNode.size = Self.contactShadowTexture.size()
        shadowNode.zPosition = Z2.shadow.rawValue
        shadowNode.position = Self.shadowRestPosition
        shadowNode.alpha = Self.shadowRestAlpha
        addChild(shadowNode)

        configure(auraNode, texture: textures["aura"], z: .aura)
        auraNode.color = auraColor
        auraNode.colorBlendFactor = 1
        auraNode.alpha = 0.78
        auraNode.blendMode = .add
        #if DEBUG
        // MEASUREMENT AID (AURIE_AURA_OFF=1): hides the glow so a capture
        // with and without can be differenced. "Is the aura visible?" cannot
        // be answered from one frame — the glow is broad and low-contrast, so
        // it hides inside the background's own variation.
        if ProcessInfo.processInfo.environment["AURIE_AURA_OFF"] == "1" {
            auraNode.isHidden = true
        }
        #endif
        // A broad, expansive glow rather than a tight halo hugging the body.
        // The aura texture is a radial gradient that fades to zero at its own
        // edge, so scaling the SPRITE keeps that soft falloff — only larger.
        // Aura only; the contact shadow (shadowNode) is a separate child of
        // self and is deliberately left at its own size.
        auraNode.setScale(Self.auraScale)
        // Lifted so the glow hugs the body and its falloff ends above the
        // contact shadow — the shadow owns the ground plane, the aura the air.
        auraNode.position = CGPoint(x: 0, y: 46)

        if let body, AurieBlenderSkin.isAvailable(body) {
            blenderBody = body
            blenderArmStyle = armStyle ?? "arm_00"
            blenderLegStyle = legStyle ?? "leg_01"
            blenderHairStyle = hairStyle ?? "tuft"
            blenderPatternLayer = patternLayer
            buildBlenderSkin(baseColor: baseColor)
            return
        }

        // Body/limbs use a partial blend so the baked highlight/shadow survive
        // the family tint and read as a soft, dimensional form (rather than a
        // flat solid colour).
        configure(limbsNode, texture: textures["limbs"], z: .limbs)
        tint(limbsNode, baseColor, blend: 0.82)

        configure(bodyNode, texture: textures["body"], z: .body)
        tint(bodyNode, baseColor, blend: 0.82)

        configure(patternNode, texture: textures["pattern"], z: .pattern)
        tint(patternNode, darken(baseColor, by: 0.25))

        // Eyes and mouth sit a little up/down from centre so they read as a face.
        configure(eyesNode, texture: textures["eyes"], z: .eyes)
        eyesNode.position = CGPoint(x: 0, y: 30)

        configure(mouthNode, texture: textures["mouth"], z: .mouth)
        mouthNode.position = CGPoint(x: 0, y: -35)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// Assemble the canonical Blender layers. Order was verified against the
    /// full 3D render; only the neutral layers get the family tint.
    private func buildBlenderSkin(baseColor: SKColor) {
        usesBlenderSkin = true
        blenderBaseColor = baseColor   // kept for runtime orientation rebuilds
        let body = blenderBody
        // Fallback: an orientation with no art for this body builds
        // front instead of crashing or faking (Round-only PoC today).
        if orientation != .front,
           AurieBlenderSkin.orientedLayer(body, "body",
                                          orientation) == nil {
            orientation = .front
        }
        let tint = AurieBlenderSkin.tintShader(for: baseColor)
        // A persisted leg style outside the launch pool (a removed style)
        // or one with no art for this body falls back to leg_00 — the
        // same always-whole rule the hair layer uses.
        if !AurieLimbCatalog.launchLegs.contains(blenderLegStyle)
            || AurieBlenderSkin.layerSet(body)?
                .layers["\(blenderLegStyle)_l"] == nil {
            blenderLegStyle = "leg_00"
        }
        // Same rule for arms (arm_04 Soft Mittens was removed 2026-09-13
        // after living on test devices — its id is burned, its saves must
        // still render whole).
        if !AurieLimbCatalog.arms.contains(blenderArmStyle)
            || AurieBlenderSkin.layerSet(body)?
                .layers["\(blenderArmStyle)_l"] == nil {
            blenderArmStyle = "arm_00"
        }
        blenderLift = AurieBlenderSkin.legLift(body, blenderLegStyle)

        // The pattern is a per-pixel choice between the body colour and a
        // darker family-adjacent pattern colour, applied ONLY to the body layer
        // (the mask was rendered on the body surface and is registered to the
        // body crop). Everything else — tuft, arms, legs — keeps the plain
        // family tint. Falls back to the plain tint if the Aurie is plain or
        // this body has no mask for the pattern, so nothing can break.
        var bodyIsPatterned = false
        let bodyShader: SKShader = {
            // Patterns continue around the creature (product rule
            // 2026-09-14): each orientation looks up its own mask,
            // registered to that orientation's body crop. Missing
            // masks (stars/hearts backs until the lost tile sources
            // are restored) degrade to the plain tint.
            if let layer = blenderPatternLayer,
               let mask = AurieBlenderSkin.patternMask(
                   body, layer, orientation: orientation) {
                bodyIsPatterned = true
                return AurieBlenderSkin.patternTintShader(
                    body: baseColor, pattern: darken(baseColor, by: 0.34),
                    mask: mask)
            }
            return tint
        }()

        // Order verified against the 3D reference: body → tuft → arms →
        // legs → cheeks → mouth → eyes.
        var z = Z.body.rawValue
        func add(_ layer: String, lifted: Bool, shader: SKShader? = nil) {
            guard let sprite = AurieBlenderSkin.sprite(
                body, layer, orientation: orientation,
                tinted: shader ?? tint)
            else { return }
            z += 0.01
            sprite.zPosition = z
            if lifted { sprite.position.y += blenderLift }
            breatheNode.addChild(sprite)
            blenderLayers[layer] = sprite
        }
        // ANIMATION-SAFE ARMS. When the arm art keeps its shoulder root, the
        // arm is drawn BEHIND the body on a shoulder JOINT: the body conceals
        // the root at rest (so the resting look is unchanged) and the arm
        // rotates about the joint, so no gap can open at the shoulder. Arms
        // added FIRST here, so they sit behind body + tuft.
        // Back limbs are jointed exactly like the front, through the
        // same exported pivot metadata — the guard only asks whether
        // THIS orientation shipped pivots (a body without back
        // masters degrades to static/absent limbs, never crashes).
        let animSafe = AurieBlenderSkin.animSafeArms(body)
            && AurieBlenderSkin.armPivot(
                body, "\(blenderArmStyle)_l", orientation) != nil
        armRotationSafe = animSafe        // arms may rotate only when jointed
        if animSafe {
            for side in ["l", "r"] { addArmJoint(side, tint: tint) }
        }
        // ANIMATION-SAFE LEGS: the same rule one storey down. When the leg
        // art keeps its hip root, each leg hangs from a hip joint behind the
        // body; splits/kicks rotate the joint and no gap can open.
        let animSafeL = AurieBlenderSkin.animSafeLegs(body)
            && AurieBlenderSkin.legPivot(
                body, "\(blenderLegStyle)_l", orientation) != nil
        legRotationSafe = animSafeL
        if animSafeL {
            for side in ["l", "r"] { addLegJoint(side, tint: tint) }
        }
        add("body", lifted: true, shader: bodyShader)
        // Crown: the baked tuft or one hair-style layer, never both. Only
        // styles in the LAUNCH pool render — a persisted id outside it
        // (or a style whose layer is missing) falls back to the tuft, so
        // restricting the pool also restyles any test creature that rolled
        // a since-rejected style. Styled hair is tinted a subtle step
        // darker than the body; the tuft keeps the plain tint every
        // existing creature has always worn.
        if blenderHairStyle != "tuft",
           AurieLimbCatalog.launchHair.contains(blenderHairStyle),
           AurieBlenderSkin.layerSet(blenderBody)?
               .layers[blenderHairStyle] != nil {
            add(blenderHairStyle, lifted: true,
                shader: AurieBlenderSkin.tintShader(
                    for: darken(baseColor, by: 0.10)))
        } else {
            add("tuft", lifted: true)
        }
        if !animSafe {
            for side in ["l", "r"] {
                add("\(blenderArmStyle)_\(side)", lifted: true)
            }
        }
        if !animSafeL {
            for side in ["l", "r"] {
                add("\(blenderLegStyle)_\(side)", lifted: false)
            }
        }
        // BELLY PATCH (frozen 2026-09-17): a FRONT-ONLY body-presentation
        // layer — the body's own neutral render cut to the generated patch
        // zone, installed per body by install_app_assets.py. Tinted a PALER
        // family colour through the standard tint shader (nothing multiplies
        // luminance, so nothing can glow). On a patterned body it draws
        // fully opaque and slightly darker, so markings stop at the patch
        // boundary instead of ghosting through. Lookup is orientation-
        // STRICT like the charms: no back asset exists, so the back simply
        // has no belly — never a borrowed front sprite.
        let bellySpec = orientation == .front
            ? AurieBlenderSkin.layerSet(body)?.layers["belly"] : nil
        if let spec = bellySpec, let image = UIImage(named: spec.asset) {
            let paleness: CGFloat = bodyIsPatterned ? 0.38 : 0.52
            let sprite = SKSpriteNode(texture: SKTexture(image: image))
            sprite.size = spec.size
            sprite.position = spec.position
            sprite.position.y += blenderLift
            sprite.shader = AurieBlenderSkin.tintShader(
                for: pale(baseColor, by: paleness))
            sprite.alpha = bodyIsPatterned ? 1.0 : 0.85
            sprite.zPosition = Z.body.rawValue + 0.012
            breatheNode.addChild(sprite)
            blenderLayers["belly"] = sprite

            // BELLY STICKER: the equipped belly charm as ONE flat processed
            // PNG (grade baked at install), scaled to THIS body's generated
            // bellyCore by the frozen two-axis fit — no per-body art, no
            // hand coordinates. Missing/unknown assets simply do not draw.
            if let charmID = blenderBellyStickerID,
               let core = AurieBlenderSkin.bellyCore(body),
               let stickerImage = UIImage(
                   named: "belly_sticker_\(charmID)") {
                let tex = SKTexture(image: stickerImage)
                let t = tex.size()
                // Frozen fit (aurie_belly_stickers.py): two-axis 0.62/0.88
                // of the core, x the approved 0.72 global size.
                let scale = min(0.62 * core.size.width / t.width,
                                0.88 * core.size.height / t.height) * 0.72
                let sticker = SKSpriteNode(texture: tex)
                sticker.size = CGSize(width: t.width * scale,
                                      height: t.height * scale)
                sticker.position = core.center
                sticker.position.y += blenderLift
                sticker.zPosition = Z.body.rawValue + 0.014
                breatheNode.addChild(sticker)
                blenderLayers["bellySticker"] = sticker
            }
        }
        // CHARMS (2026-09-14): true-3D layers rendered per orientation by
        // export_charm_layers.py with the body carved out as a Cycles
        // holdout — so drawing them at the reserved Z.charm seam (above
        // the body group, below the face) is depth-correct for BOTH
        // facings with no per-slot z rules: a worn backpack's front
        // sprite arrives fully carved (hidden behind the body, which is
        // the physically-correct picture) while its back sprite shows
        // the whole pack. Untinted — charms keep their own colours.
        // Orientation-STRICT lookup, unlike body layers: a charm whose
        // art is missing for this body/orientation simply does not draw
        // (the creature must render whole either way), and it must never
        // borrow the front sprite for a back view.
        // WEAR ORDER (corrected 2026-09-18): orientation-specific.
        // FRONT: charms sit ABOVE the body (and the belly/sticker skin
        // art) but BELOW styled hair and the static limbs — an arm
        // crossing a strap occludes the strap (the under-arm pass is
        // additionally carved into the layer at export for the
        // animation-safe bodies whose arms draw behind the body).
        // BACK: a worn pack sits proud of the back, OVER hair falling
        // against it — so back charms draw ABOVE the hair/tuft crown
        // (2.02) while staying BELOW the static-limb fallback (2.03+).
        // Z.charm stays reserved for future FLOATING/aura accessories
        // that genuinely belong in front of the whole creature.
        var charmZ = Z.body.rawValue
            + (orientation == .front ? 0.016 : 0.026)
        for key in blenderCharmLayers {
            let set = AurieBlenderSkin.layerSet(body)
            guard let spec = orientation == .front
                    ? set?.layers[key] : set?.backLayers[key],
                  let image = UIImage(named: spec.asset) else { continue }
            let sprite = SKSpriteNode(texture: SKTexture(image: image))
            sprite.size = spec.size
            sprite.position = spec.position
            sprite.position.y += blenderLift   // charms ride the body
            charmZ += 0.001
            sprite.zPosition = charmZ
            breatheNode.addChild(sprite)
            blenderLayers[key] = sprite
        }
        // FLOATING charm — PAUSED (2026-09-19 product decision):
        // reserved for a later personality-trait system. The model,
        // slot string and plumbing stay dormant for save compatibility;
        // flip `floatingPlacementActive` to resume rendering. While
        // paused, nothing draws even if a record exists.
        if Self.floatingPlacementActive,
           let id = blenderFloatingCharmID,
           let image = UIImage(named: "charm_catalog_\(id)") {
            let tex = SKTexture(image: image)
            let w = AssetLoader.collisionHalfWidth * 2 * 0.34
            let sprite = SKSpriteNode(texture: tex)
            sprite.size = CGSize(
                width: w, height: w * tex.size().height / tex.size().width)
            sprite.position = CGPoint(
                x: AssetLoader.collisionHalfWidth * 1.22,
                y: AssetLoader.collisionHalfHeightUp * 0.74 + blenderLift)
            sprite.zPosition = Z.charm.rawValue
            breatheNode.addChild(sprite)
            blenderLayers["floatingCharm"] = sprite
            if !reduceMotion {
                sprite.run(.repeatForever(.sequence([
                    ease(.moveBy(x: 0, y: 8, duration: 2.1)),
                    ease(.moveBy(x: 0, y: -8, duration: 2.1))])),
                    withKey: "floatBob")
                let motion = Self.floatMotion[id] ?? (tilt: 0.08, spin: false)
                if motion.spin {
                    sprite.run(.repeatForever(
                        .rotate(byAngle: -2 * .pi, duration: 14)),
                        withKey: "floatSpin")
                } else if motion.tilt > 0 {
                    sprite.run(.repeatForever(.sequence([
                        ease(.rotate(toAngle: motion.tilt, duration: 2.7)),
                        ease(.rotate(toAngle: -motion.tilt, duration: 2.7))])),
                        withKey: "floatTilt")
                }
            }
        }
        // AURA charm: a light cluster of SMALL copies living in the aura
        // space. Instances sit on a fixed ellipse OUTSIDE the body
        // silhouette (so eyes/mouth/belly can never be covered) and draw
        // BEHIND the body with the aura glow, which guarantees the same.
        // Layout is deterministic — a rebuild (orientation swap, equip
        // refresh) reproduces the identical cluster.
        if let id = blenderAuraCharmID,
           let image = UIImage(named: "charm_catalog_\(id)") {
            let tex = SKTexture(image: image)
            let halfW = AssetLoader.collisionHalfWidth
            let upH = AssetLoader.collisionHalfHeightUp
            let downH = AssetLoader.collisionHalfHeightDown
            // RETUNE 2 (approved direction): TINY particles, scattered
            // like matter in the gas phase — no ring, no uniform
            // spacing. Angles are irregular AND radial reach varies
            // widely, so the cloud reads as random drift while staying
            // deterministic (identical on every rebuild). angle°,
            // radial reach, size scale, bob period.
            let specs: [(CGFloat, CGFloat, CGFloat, Double)] = [
                (12, 1.62, 0.55, 3.1), (38, 1.18, 0.85, 2.7),
                (57, 1.45, 0.45, 3.6), (83, 1.60, 0.70, 2.9),
                (104, 1.22, 0.50, 3.3), (131, 1.52, 0.90, 2.6),
                (149, 1.12, 0.60, 3.8), (176, 1.38, 0.48, 3.0),
                (204, 1.58, 0.78, 3.4), (223, 1.15, 0.55, 2.8),
                (247, 1.42, 0.95, 3.2), (271, 1.65, 0.50, 2.5),
                (295, 1.25, 0.72, 3.7), (318, 1.50, 0.58, 2.9),
                (343, 1.30, 0.82, 3.5), (70, 1.70, 0.62, 4.0),
                // 2026-09-26: six further scatter positions so a charm may
                // ask for a DENSER cloud than the original sixteen. Only
                // charms whose `auraCount` exceeds 16 reach these, so the
                // approved Crystal (16) and Blossom (11) clusters are
                // untouched. Same irregular character: angles fall in the
                // gaps of the list above, reach and size stay varied.
                (25, 1.35, 0.68, 3.0), (95, 1.55, 0.52, 3.6),
                (162, 1.68, 0.88, 2.7), (190, 1.20, 0.58, 3.9),
                (260, 1.48, 0.75, 2.6), (330, 1.62, 0.46, 3.3),
            ]
            let count = Self.auraCount[id] ?? 13
            for (i, s) in specs.prefix(count).enumerated() {
                let a = s.0 * .pi / 180
                let base = halfW * 2 * 0.052 * s.2
                let inst = SKSpriteNode(texture: tex)
                inst.size = CGSize(
                    width: base,
                    height: base * tex.size().height / tex.size().width)
                inst.position = CGPoint(
                    x: cos(a) * halfW * s.1,
                    y: sin(a) * (sin(a) >= 0 ? upH : downH) * s.1
                        + blenderLift * 0.5)
                inst.zPosition = Z.aura.rawValue + 0.3
                breatheNode.addChild(inst)
                blenderLayers["auraCharm_\(i)"] = inst
                if !reduceMotion {
                    inst.run(.sequence([
                        .wait(forDuration: Double(i) * 0.35),
                        .repeatForever(.sequence([
                            ease(.moveBy(x: 0, y: 5, duration: s.3)),
                            ease(.moveBy(x: 0, y: -5, duration: s.3))]))]),
                        withKey: "auraBob")
                    inst.run(.sequence([
                        .wait(forDuration: Double(i) * 0.2),
                        .repeatForever(.sequence([
                            ease(.rotate(toAngle: 0.12, duration: s.3 * 1.3)),
                            ease(.rotate(toAngle: -0.12, duration: s.3 * 1.3))]))]),
                        withKey: "auraSway")
                }
            }
        }
        // The face group exists only on the front: a back view shows
        // no eyes/mouth/cheeks by DESIGN (never a hidden-face front
        // sprite). The nodes stay unparented so the expression state
        // machine remains harmless if poked.
        guard orientation == .front else { return }
        for (name, node) in [("cheeks", cheeksNode), ("mouth", mouthNode),
                             ("eyes", eyesNode)] {
            node.zPosition = Z.eyes.rawValue + (name == "eyes" ? 0.3
                                                : name == "mouth" ? 0.2 : 0.1)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            breatheNode.addChild(node)
        }
        // Sparkles sit ON the eye as a child, so gaze can move them alone while
        // they still ride the eye's own blink/squash. On an orientation
        // rebuild they are already parented from the first build.
        catchNode.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        catchNode.zPosition = 0.1
        if catchNode.parent == nil { eyesNode.addChild(catchNode) }
        AurieFaceCatalog.validateAndLog(body: AurieBlenderSkin.key(body))
        applyBlenderFace(BaseExpression.happy.rawValue, blink: false)
    }

    /// LIVE equipment refresh (equip/remove/replace from the Charms
    /// page, 2026-09-17). Same targeted mechanism as the facing swap:
    /// rebuild ONLY the Blender layer stack in place — position, scale,
    /// contact shadow, orientation and every in-flight action survive,
    /// because they live on self/squashNode/breatheNode/root, which are
    /// never torn down. No-op when nothing changed, and a no-op for
    /// placeholder skins (their charms ship with the Blender path).
    /// Store/Aurie remain the single source of truth — this only tells
    /// the node what that truth now is.
    func setEquipment(charmLayers: [String],
                      bellyStickerCharmID: String?,
                      auraCharmID: String? = nil,
                      floatingCharmID: String? = nil) {
        guard usesBlenderSkin else { return }
        guard charmLayers != blenderCharmLayers
                || bellyStickerCharmID != blenderBellyStickerID
                || auraCharmID != blenderAuraCharmID
                || floatingCharmID != blenderFloatingCharmID else { return }
        blenderCharmLayers = charmLayers
        blenderBellyStickerID = bellyStickerCharmID
        blenderAuraCharmID = auraCharmID
        blenderFloatingCharmID = floatingCharmID
        rebuildBlenderSkin()
    }

    /// Runtime facing swap (Home movement, 2026-09-14). Rebuilds ONLY the
    /// Blender layer stack, in place: the node's position, scale, contact
    /// shadow and every in-flight hop/squash/breath action survive — they
    /// run on self/squashNode/breatheNode/root, which are never torn down.
    /// No-op for placeholder skins, a same-orientation request, or a body
    /// with no art for the wanted orientation (the missing-asset rule:
    /// never crash, never disappear — the Aurie simply keeps its facing).
    func setOrientation(_ wanted: AurieOrientation) {
        guard usesBlenderSkin, wanted != orientation else { return }
        if wanted != .front,
           AurieBlenderSkin.orientedLayer(blenderBody, "body",
                                          wanted) == nil { return }
        orientation = wanted
        rebuildBlenderSkin()
    }

    /// Tear down every orientation-dependent sprite/joint and rebuild for
    /// the current `orientation`. Gesture actions running on removed joints
    /// die with them; the persistent face nodes are unparented (back) or
    /// re-adopted (front) by `buildBlenderSkin` itself.
    private func rebuildBlenderSkin() {
        for sprite in blenderLayers.values { sprite.removeFromParent() }
        blenderLayers.removeAll()
        for joint in armJoints.values { joint.removeFromParent() }
        armJoints.removeAll()
        for joint in legJoints.values { joint.removeFromParent() }
        legJoints.removeAll()
        for node in [cheeksNode, mouthNode, eyesNode] { node.removeFromParent() }
        buildBlenderSkin(baseColor: blenderBaseColor)
        // The rest-pose caches are keyed to the torn-down nodes: recapture
        // them so gestures ease home to THIS build's rest, not a stale one.
        armJointRest = armJoints.mapValues(\.position)
        armJointHomeZ = armJoints.mapValues(\.zPosition)
        var rest: [ObjectIdentifier: (pos: CGPoint, rot: CGFloat)] = [:]
        for n in [armL, armR, legL, legR].compactMap({ $0 }) {
            rest[ObjectIdentifier(n)] = (n.position, n.zRotation)
        }
        limbRest = rest
        // Back to the SAVED face (the build seeds a generic happy): a turn
        // must never reset the creature's resting personality.
        if orientation == .front { applyFace(baseExpression.rawValue) }
    }

    /// Swap the three Blender face layers. Same seam the placeholder path
    /// uses, so the expression/reaction state machine is unchanged.
    private func applyBlenderFace(_ faceId: String, blink: Bool) {
        guard let ids = AurieBlenderSkin.faceLayers(blenderBody, faceId,
                                                   blink: blink) else {
            #if DEBUG
            NSLog("AURIE_FACE_MISSING %@ - keeping the current face", faceId)
            assertionFailure("No Blender artwork for face '\(faceId)'")
            #endif
            return          // keep whatever is showing rather than lie
        }
        #if DEBUG
        let t0 = CACurrentMediaTime()
        defer {
            NSLog("AURIE_FACESWAP %@ blink=%d %.2fms", faceId, blink ? 1 : 0,
                  (CACurrentMediaTime() - t0) * 1000)
        }
        #endif
        var eyeSpecPos: CGPoint?
        for (layer, node) in [(ids.cheeks, cheeksNode), (ids.mouth, mouthNode),
                              (ids.eyes, eyesNode)] {
            guard let spec = AurieBlenderSkin.layerSet(blenderBody)?
                    .layers[layer],
                  let image = UIImage(named: spec.asset) else {
                node.isHidden = true
                continue
            }
            let texture = SKTexture(image: image)
            node.texture = texture
            // Setting `size` while a scale action holds the node squashed
            // (calm stroke eyesSoft 0.25, slowBlink 0.12, yawn's mouth)
            // makes SpriteKit rebase the sprite: the later "restore to 1.0"
            // then renders the layer at size/scale — the stretched-eye bug.
            // Assign size at scale 1 and put the live scale back.
            let liveX = node.xScale, liveY = node.yScale
            node.setScale(1)
            node.size = spec.size
            node.xScale = liveX
            node.yScale = liveY
            node.position = spec.position
            node.position.y += blenderLift    // face rides with the body
            node.isHidden = false
            if node === eyesNode { eyeSpecPos = spec.position }
        }

        // Sparkles: a child of the eye, so its position is EYE-RELATIVE
        // (spec − eye spec; the lift cancels). Carries the live gaze offset;
        // the dark eye no longer moves for gaze. Hidden when the expression
        // has no sparkle or the lid is shut (blink → ids.catch is nil).
        if let catchLayer = ids.sparkles, let eyeSpecPos,
           let spec = AurieBlenderSkin.layerSet(blenderBody)?.layers[catchLayer],
           let image = UIImage(named: spec.asset) {
            catchNode.texture = SKTexture(image: image)
            catchNode.size = spec.size
            catchRest = CGPoint(x: spec.position.x - eyeSpecPos.x,
                                y: spec.position.y - eyeSpecPos.y)
            catchNode.position = CGPoint(x: catchRest.x + eyeLookOffset.x,
                                         y: catchRest.y + eyeLookOffset.y)
            catchNode.isHidden = false
        } else {
            catchNode.isHidden = true
        }
    }

    private func configure(_ node: SKSpriteNode, texture: SKTexture?, z: Z) {
        node.texture = texture
        node.size = texture?.size() ?? .zero
        node.isHidden = (texture == nil)
        node.zPosition = z.rawValue
        breatheNode.addChild(node)
    }
    private func tint(_ node: SKSpriteNode, _ color: SKColor, blend: CGFloat = 1) {
        node.color = color; node.colorBlendFactor = blend
    }

    /// Generated soft, flat contact-shadow blob (no art file needed).
    private static let contactShadowTexture: SKTexture = {
        let size = CGSize(width: 300, height: 96)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            c.addEllipse(in: CGRect(origin: .zero, size: size))
            c.clip()
            let colors = [UIColor(white: 0, alpha: 0.62).cgColor,
                          UIColor(white: 0, alpha: 0).cgColor]
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: colors as CFArray, locations: [0, 1])!
            let ctr = CGPoint(x: size.width / 2, y: size.height / 2)
            c.drawRadialGradient(g, startCenter: ctr, startRadius: 0,
                                 endCenter: ctr, endRadius: size.width / 2, options: [])
        }
        return SKTexture(image: image)
    }()
    /// The belly's albedo: the family colour blended toward white —
    /// matches aurie_belly.pale (the approved reference maths).
    private func pale(_ c: SKColor, by f: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(red: r + (1 - r) * f, green: g + (1 - g) * f,
                       blue: b + (1 - b) * f, alpha: a)
    }
    private func darken(_ c: SKColor, by f: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(red: r*(1-f), green: g*(1-f), blue: b*(1-f), alpha: a)
    }

    // MARK: Idle life

    /// The grounded idle (Stage D): soft irregular breathing, occasional
    /// blinks, and a rare micro weight-shift. No continuous vertical bob —
    /// the feet stay planted over the shadow.
    func startIdle() {
        breatheNode.removeAction(forKey: "breathe")
        scheduleBreath()
        scheduleSway()
        scheduleArmMicro()

        // Aura pulse. Kept well clear of zero at the bottom of the swing so
        // the glow stays continuously readable against bright environments.
        let up = SKAction.fadeAlpha(to: 0.94, duration: 1.4)
        let down = SKAction.fadeAlpha(to: 0.64, duration: 1.4)
        auraNode.run(.repeatForever(.sequence([up, down])), withKey: "auraPulse")

        scheduleBlink()
    }

    /// A rare arm drift, on its own irregular clock — skipped while an arm is
    /// mid-gesture or the creature is carried, and entirely under Reduce
    /// Motion. Understated by design: the idle should read alive, not busy.
    private func scheduleArmMicro() {
        // Only when the arms are on shoulder joints (anim-safe) — a cropped
        // arm rotated about its centre detaches, so unrigged arms never move.
        guard armRotationSafe, !reduceMotion else { return }
        run(.sequence([.wait(forDuration: 9, withRange: 6), .run { [weak self] in
            guard let self else { return }
            if self.currentReaction == nil, !self.isCarried, !self.isDancing,
               self.armJointL?.action(forKey: "armGesture") == nil,
               self.armJointR?.action(forKey: "armGesture") == nil {
                self.armMicroMotion()
            }
            self.scheduleArmMicro()
        }]), withKey: "armMicroLoop")
    }

    /// One breath at a time, each with slightly random length, so idle never
    /// reads as a perfect metronome. Runs on its own layer, composing with any
    /// interaction squash instead of fighting it.
    ///
    /// Note the API: `SKAction.scaleX(to:y:)` animates a plain SKNode's scale
    /// factors. (`scale(to: CGSize)` is SKSpriteNode-only and silently does
    /// nothing on wrapper nodes — the original "invisible breathing" bug.)
    private func scheduleBreath() {
        // Visible at normal speed, soft and calm: inhale 1.4–1.7 s to ~2.8%
        // taller, exhale 1.8–2.1 s to ~1.2% wider, brief natural pause —
        // one cycle ≈ 3.4–4.3 s. Reduce Motion keeps a gentler breath
        // (~1% vertical, no horizontal, same grounded feet).
        let inhaleX: CGFloat = reduceMotion ? 1.0 : 0.996
        let inhaleY: CGFloat = reduceMotion ? 1.010 : 1.028
        let exhaleX: CGFloat = reduceMotion ? 1.0 : 1.012
        let exhaleY: CGFloat = reduceMotion ? 0.998 : 0.990
        breatheNode.run(.sequence([
            breathPose(x: inhaleX, y: inhaleY, duration: .random(in: 1.4...1.7)),
            breathPose(x: exhaleX, y: exhaleY, duration: .random(in: 1.8...2.1)),
            .wait(forDuration: .random(in: 0.2...0.45)),
            .run { [weak self] in self?.scheduleBreath() },
        ]), withKey: "breathe")
    }

    /// Ease to a breath pose with the FEET kept planted: scaling around the
    /// node centre would sink/raise the body bottom, so the node rises by
    /// exactly what the feet would sink — the bottom stays on the ground line
    /// while the head does the travelling. Logical position, collision, and
    /// the bubble anchor are untouched (this is all inside breatheNode).
    private func breathPose(x: CGFloat, y: CGFloat, duration: TimeInterval) -> SKAction {
        let scale = SKAction.scaleX(to: x, y: y, duration: duration)
        let ground = SKAction.moveTo(y: AssetLoader.collisionHalfHeightDown * (y - 1),
                                     duration: duration)
        scale.timingMode = .easeInEaseOut
        ground.timingMode = .easeInEaseOut
        return .group([scale, ground])
    }

    /// A rare, tiny weight shift — skipped while any interaction tilt owns the
    /// root, and entirely under Reduce Motion.
    private func scheduleSway() {
        guard !reduceMotion else { return }
        run(.sequence([.wait(forDuration: 6, withRange: 5), .run { [weak self] in
            guard let self else { return }
            if self.root.action(forKey: "motionTilt") == nil,
               self.root.action(forKey: "glance") == nil,
               !self.isDancing, !self.isCarried {
                let angle = CGFloat.random(in: 0.015...0.03) * (Bool.random() ? 1 : -1)
                let lean = SKAction.rotate(toAngle: angle, duration: 0.9)
                let back = SKAction.rotate(toAngle: 0, duration: 1.1)
                lean.timingMode = .easeInEaseOut
                back.timingMode = .easeInEaseOut
                self.root.run(.sequence([lean, back]), withKey: "idleSway")
            }
            self.scheduleSway()
        }]), withKey: "swayLoop")
    }

    private func scheduleBlink() {
        let wait = SKAction.wait(forDuration: 2.5, withRange: 3.0)
        let blink = SKAction.run { [weak self] in
            guard let self = self, self.eyesNode.texture != nil,
                  self.eyesNode.action(forKey: "expr") == nil else { return }
            // Blink is the lowest-priority reaction: it must not fire over
            // one that is playing, and it has to reopen to the Aurie's OWN
            // resting eye scale. Reopening to 1.0 (as it used to) would
            // quietly erase a sleepy or delighted base expression after the
            // first blink.
            guard self.currentReaction == nil, !self.eyesAreClosed else { return }
            if self.usesBlenderSkin {
                // Swap to the exported blink-closed eyes: the Blender eye
                // art is a drawn shape, so squashing it would deform the
                // catchlights rather than read as a lid coming down.
                self.blenderBlink()
                return
            }
            let close = SKAction.scaleY(to: 0.1, duration: 0.06)
            let open  = SKAction.scaleY(to: self.restEyeScaleY, duration: 0.09)
            self.eyesNode.run(.sequence([close, open]))
        }
        run(.repeatForever(.sequence([wait, blink])), withKey: "blinkLoop")
    }

    // MARK: Reactions

    /// Tap: a small compressed bounce — attentive, no relocation, clean return.
    func reactBounce() {
        if reduceMotion {
            runSquash([.scaleX(to: 1.03, y: 0.98, duration: 0.10),
                       .scaleX(to: 1.0, y: 1.0, duration: 0.16)])
            return
        }
        let squash  = SKAction.scaleX(to: 1.09, y: 0.91, duration: 0.08)
        let stretch = SKAction.scaleX(to: 0.96, y: 1.07, duration: 0.10)
        let settle  = SKAction.scaleX(to: 1.0, y: 1.0, duration: 0.16)
        settle.timingMode = .easeOut
        runSquash([squash, stretch, settle])
    }

    /// Head tap: an unmistakable startled acknowledgement — quick squash, a
    /// small upward whole-body pop, and settle. Bigger than `reactBounce`'s
    /// subtle squish (which read as nothing at Home size), still a hop-in-place
    /// rather than a jump. All targets are ABSOLUTE (scale 1, root y 0), so
    /// mid-animation retaps can never accumulate drift — the settle even heals
    /// a root the idle sit-dip left displaced.
    func headBoop() {
        if reduceMotion {
            runSquash([.scaleX(to: 1.05, y: 0.95, duration: 0.10),
                       .scaleX(to: 1.0, y: 1.0, duration: 0.16)])
            return
        }
        runSquash([.scaleX(to: 1.12, y: 0.86, duration: 0.09),
                   .scaleX(to: 0.93, y: 1.09, duration: 0.11),
                   .scaleX(to: 1.02, y: 0.98, duration: 0.10),
                   .scaleX(to: 1.0, y: 1.0, duration: 0.12)])
        let popY: CGFloat = 12
        let up = SKAction.moveTo(y: popY, duration: 0.12)
        up.timingMode = .easeOut
        let down = SKAction.moveTo(y: 0, duration: 0.18)
        down.timingMode = .easeInEaseOut
        root.removeAction(forKey: "sit")   // sole writer of root.y during the pop
        root.run(.sequence([.wait(forDuration: 0.08), up, down]),
                 withKey: "headPop")
        shadowNode.run(.sequence([
            .group([.scale(to: 0.94, duration: 0.12),
                    .fadeAlpha(to: Self.shadowRestAlpha - 0.15, duration: 0.12)]),
            .group([.scale(to: 1.0, duration: 0.18),
                    .fadeAlpha(to: Self.shadowRestAlpha, duration: 0.18)]),
        ]), withKey: "shadowPhase")
    }

    /// All interaction squashes go through one key: the newest replaces the
    /// old, and every sequence ends at exactly 1.0, so squash can never stack
    /// or leave the creature deformed.
    private func runSquash(_ actions: [SKAction]) {
        squashNode.run(.sequence(actions), withKey: "motionSquash")
    }

    // MARK: Movement (hop, not walk)

    /// Orientation is PINNED — Aurie no longer mirror-flips to "face" a
    /// direction. With the real (Blender) art the body is lit from one side, so
    /// a mirror flip swapped the baked form-shadow to the opposite side, which
    /// read as the creature (and its shadow) jarringly switching sides. Kept as
    /// a no-op chokepoint so `hop`/`noticeOffscreen` still call it and this is a
    /// two-line revert. `facing` stays +1, keeping it consistent with the
    /// (now always positive) `root.xScale` that pupil-tracking depends on.
    func face(_ direction: CGFloat) {
        _ = direction
        facing = 1
        root.xScale = abs(root.xScale)
    }

    /// Hop to a scene point with physical weight (Stage D): crouch, launch,
    /// arc, soft landing, one small rebound — always ending exactly at the
    /// clamped destination with every transform back at rest. Arc height and
    /// travel time respond modestly to distance (short hops stay low and
    /// quick) unless the caller overrides them (the shake-flail's fast wild
    /// hops pass their own). Keyed, so a new hop cleanly replaces an
    /// in-flight one instead of stacking position writers.
    func hop(to point: CGPoint, hopHeight: CGFloat? = nil, duration: TimeInterval? = nil) {
        guard hopsEnabled else { return }   // planted (e.g. calm mode): never hop
        face(point.x >= position.x ? 1 : -1)

        let start = position   // self.position, in scene coordinates
        let distance = hypot(point.x - start.x, point.y - start.y)
        let travel = duration ?? (0.32 + 0.20 * min(distance / 420, 1))   // 0.32–0.52 s
        let height = hopHeight ?? (22 + 58 * min(distance / 400, 1))      // 22–80 pt

        removeAction(forKey: "hopArc")
        shadowNode.removeAction(forKey: "shadowPhase")

        if reduceMotion {
            // Restrained fallback: same destination, gentle ease, no arc or
            // squash theatrics — feedback stays with expression/particles.
            let move = SKAction.move(to: point, duration: min(travel, 0.30))
            move.timingMode = .easeInEaseOut
            run(.sequence([move, .run { [weak self] in self?.restShadow() }]),
                withKey: "hopArc")
            runSquash([.scaleX(to: 1.02, y: 0.99, duration: 0.12),
                       .scaleX(to: 1.0, y: 1.0, duration: 0.14)])
            return
        }

        let anticipation = min(0.13, travel * 0.35)   // chained fast hops crouch briefly

        // The arc: linear travel plus a parabolic lift, while the shadow stays
        // on the ground line, shrinking and lightening with altitude.
        let arc = SKAction.customAction(withDuration: travel) { [weak self] _, t in
            guard let self else { return }
            let p = CGFloat(t) / CGFloat(travel)
            let lift = 4 * height * (p - p * p)   // peak at p = 0.5
            self.position = CGPoint(x: start.x + (point.x - start.x) * p,
                                    y: start.y + (point.y - start.y) * p + lift)
            self.groundShadow(lift: lift, of: height)
        }

        run(.sequence([
            .wait(forDuration: anticipation),
            arc,
            .run { [weak self] in self?.landShadow() },
        ]), withKey: "hopArc")

        // Body: crouch -> launch stretch -> relax in flight -> land -> settle.
        // Cumulative time of the landing squash matches the arc's touchdown.
        let crouch  = SKAction.scaleX(to: 1.09, y: 0.91, duration: anticipation)
        crouch.timingMode = .easeOut
        let launch  = SKAction.scaleX(to: 0.93, y: 1.09, duration: 0.10)
        launch.timingMode = .easeOut
        let flight  = SKAction.scaleX(to: 1.0, y: 1.02,
                                      duration: max(travel - 0.10, 0.05))
        let land    = SKAction.scaleX(to: 1.12, y: 0.88, duration: 0.09)
        land.timingMode = .easeOut
        let rebound = SKAction.scaleX(to: 0.97, y: 1.04, duration: 0.08)
        let settle  = SKAction.scaleX(to: 1.0, y: 1.0, duration: 0.12)
        settle.timingMode = .easeOut
        runSquash([crouch, launch, flight, land, rebound, settle])

        // Shadow: a touch wider and darker while the body coils for the jump.
        shadowNode.run(.group([
            .scale(to: 1.10, duration: anticipation),
            .fadeAlpha(to: min(Self.shadowRestAlpha + 0.1, 1), duration: anticipation),
        ]), withKey: "shadowPhase")
    }

    /// Keep the shadow on the ground line while the body arcs above it:
    /// compensate the node's lift (converted into self's local space) and
    /// shrink/lighten it with altitude. At lift 0 this IS the rest pose.
    private func groundShadow(lift: CGFloat, of height: CGFloat) {
        let f = min(lift / max(height, 1), 1)
        let localLift = lift / max(abs(xScale), 0.0001)
        shadowNode.position = CGPoint(x: Self.shadowRestPosition.x,
                                      y: Self.shadowRestPosition.y - localLift)
        shadowNode.setScale(1 - 0.28 * f)
        shadowNode.alpha = Self.shadowRestAlpha - 0.30 * f
    }

    /// Touchdown: one brief broaden/darken pulse, then exactly the rest pose.
    private func landShadow() {
        shadowNode.removeAction(forKey: "shadowPhase")
        let pulse = SKAction.group([
            .scale(to: 1.14, duration: 0.08),
            .fadeAlpha(to: min(Self.shadowRestAlpha + 0.12, 1), duration: 0.08),
        ])
        let rest = SKAction.group([
            .scale(to: 1.0, duration: 0.15),
            .fadeAlpha(to: Self.shadowRestAlpha, duration: 0.15),
            .move(to: Self.shadowRestPosition, duration: 0.15),
        ])
        rest.timingMode = .easeOut
        shadowNode.run(.sequence([pulse, rest]), withKey: "shadowPhase")
    }

    /// Snap the shadow straight back to rest (Reduce Motion path, cancels).
    private func restShadow() {
        shadowNode.removeAction(forKey: "shadowPhase")
        shadowNode.position = Self.shadowRestPosition
        shadowNode.setScale(1)
        shadowNode.alpha = Self.shadowRestAlpha
    }

    // MARK: - Play reactions (phase 4, §7 — procedural extensions per §3)

    /// Pet: a gentle lean toward the stroking hand, a softened body, hearts.
    func reactPet(toward direction: CGFloat = 1) {
        let magnitude: CGFloat = reduceMotion ? 0.03 : 0.09
        let angle: CGFloat = direction >= 0 ? -magnitude : magnitude
        let lean = SKAction.rotate(toAngle: angle, duration: 0.22)
        lean.timingMode = .easeOut
        let back = SKAction.rotate(toAngle: 0, duration: 0.30)
        back.timingMode = .easeInEaseOut
        root.run(.sequence([lean, .wait(forDuration: 0.18), back]), withKey: "motionTilt")
        runSquash([.scaleX(to: 1.04, y: 0.97, duration: 0.20),
                   .scaleX(to: 1.0, y: 1.0, duration: 0.28)])
        emitHearts()
    }

    /// Tickle: a quick asymmetric wiggle — playful, brief, distinct from the
    /// shake tumble, and safe to retrigger (keyed absolute rotations).
    func reactGiggle() {
        if reduceMotion {
            root.run(.sequence([.rotate(toAngle: 0.03, duration: 0.10),
                                .rotate(toAngle: -0.02, duration: 0.10),
                                .rotate(toAngle: 0, duration: 0.12)]), withKey: "motionTilt")
            return
        }
        let wiggle = SKAction.sequence([
            .rotate(toAngle: 0.07, duration: 0.05),
            .rotate(toAngle: -0.09, duration: 0.06),
            .rotate(toAngle: 0.05, duration: 0.045),
            .rotate(toAngle: -0.06, duration: 0.055),
            .rotate(toAngle: 0.03, duration: 0.04),
            .rotate(toAngle: 0, duration: 0.08),
        ])
        root.run(wiggle, withKey: "motionTilt")
        runSquash([.scaleX(to: 1.05, y: 0.96, duration: 0.08),
                   .scaleX(to: 0.97, y: 1.04, duration: 0.08),
                   .scaleX(to: 1.0, y: 1.0, duration: 0.10)])
    }

    /// Wonder: tumble for as long as the player keeps shaking.
    ///
    /// Unlike `playWonderTumble` (a fixed 2.5-rotation sequence) this spins
    /// indefinitely, because the effect's length is now decided by the shake
    /// state machine, not a timer.
    func beginWonderTumble() {
        guard AurieReaction.startled.canInterrupt(currentReaction) else { return }
        currentReaction = .dizzy
        applyFace("surprised")
        guard !reduceMotion else {
            root.run(.repeatForever(.sequence([
                .rotate(toAngle: 0.09, duration: 0.24),
                .rotate(toAngle: -0.07, duration: 0.26)])), withKey: "motionTilt")
            run(.sequence([.wait(forDuration: 0.3), .run { [weak self] in
                self?.applyFace(BaseExpression.delighted.rawValue)
            }]), withKey: "wonderFace")
            return
        }
        let dir: CGFloat = facing >= 0 ? -1 : 1
        root.run(.repeatForever(
            .rotate(byAngle: dir * 2 * .pi, duration: 0.85)), withKey: "motionTilt")
        run(.sequence([.wait(forDuration: 0.3), .run { [weak self] in
            self?.applyFace(BaseExpression.delighted.rawValue)
        }]), withKey: "wonderFace")
    }

    /// Shaking stopped: ease the spin out, but stay woozy until it lands.
    func endWonderTumble() {
        root.removeAction(forKey: "motionTilt")
        let dir: CGFloat = facing >= 0 ? -1 : 1
        // One last slowing rotation rather than a hard stop.
        let wind = SKAction.rotate(byAngle: dir * 2 * .pi * 0.75, duration: 1.25)
        wind.timingMode = .easeOut
        let settle = SKAction.run { [weak self] in self?.root.zRotation = 0 }
        root.run(.sequence([wind, settle]), withKey: "motionTilt")
    }

    /// Feet touch down at the end of the Wonder fall.
    func landingSquash() {
        removeAction(forKey: "wonderFace")
        applyFace("calm")
        runSquash([.scaleX(to: 1.18, y: 0.82, duration: 0.10),
                   .scaleX(to: 0.95, y: 1.05, duration: 0.13),
                   .scaleX(to: 1, y: 1, duration: 0.18)])
        run(.sequence([.wait(forDuration: 0.75), .run { [weak self] in
            self?.restoreBaseFace()
        }]), withKey: "reaction")
    }

    /// Wonder: a MUCH bigger tumble than the ordinary shake reaction — the
    /// creature has genuinely been shaken inside a globe. Two and a half
    /// rotations with a wobbling recovery, then it settles back to exactly
    /// neutral. Still cute: eased throughout, no violent snapping.
    func playWonderTumble() {
        guard AurieReaction.startled.canInterrupt(currentReaction) else { return }
        let token = reactionGeneration
        currentReaction = .dizzy
        applyFace("surprised")

        if reduceMotion {
            // Reduce Motion keeps the meaning without the spin.
            root.run(.sequence([.rotate(toAngle: 0.10, duration: 0.18),
                                .rotate(toAngle: -0.08, duration: 0.20),
                                .rotate(toAngle: 0.05, duration: 0.20),
                                .rotate(toAngle: 0, duration: 0.22)]),
                     withKey: "motionTilt")
        } else {
            let dir: CGFloat = facing >= 0 ? -1 : 1
            let big = SKAction.rotate(byAngle: dir * 2 * .pi * 2.5, duration: 1.55)
            big.timingMode = .easeOut                 // fast out, gentle arrival
            // Overshoot and settle, so it stops like a real spinning object.
            let over = SKAction.rotate(byAngle: dir * 0.22, duration: 0.16)
            let back = SKAction.rotate(byAngle: -dir * 0.22, duration: 0.26)
            back.timingMode = .easeOut
            let reset = SKAction.run { [weak self] in self?.root.zRotation = 0 }
            root.run(.sequence([big, over, back, reset]), withKey: "motionTilt")
            runSquash([.wait(forDuration: 1.55),
                       .scaleX(to: 1.16, y: 0.84, duration: 0.10),
                       .scaleX(to: 0.94, y: 1.06, duration: 0.12),
                       .scaleX(to: 1, y: 1, duration: 0.16)])
        }

        let guarded: (TimeInterval, @escaping () -> Void) -> Void = { [weak self] delay, work in
            self?.run(.sequence([.wait(forDuration: delay), .run { [weak self] in
                guard let self, self.reactionGeneration == token else { return }
                work()
            }]), withKey: "wonderStep\(Int(delay * 100))")
        }
        // Squeezed-shut arcs through the fast spin…
        guarded(0.30) { [weak self] in
            self?.applyFace(BaseExpression.delighted.rawValue)
        }
        guarded(2.30) { [weak self] in self?.applyFace("calm") }
        run(.sequence([.wait(forDuration: 2.85), .run { [weak self] in
            guard let self, self.reactionGeneration == token else { return }
            self.restoreBaseFace()
        }]), withKey: "reaction")
    }

    /// Shake: one full dizzy tumble, then settle back to exactly neutral.
    func reactTumble() {
        guard root.action(forKey: "motionTilt") == nil else { return }
        if reduceMotion {
            // No spin — a small self-steadying wobble carries the meaning.
            root.run(.sequence([.rotate(toAngle: 0.05, duration: 0.15),
                                .rotate(toAngle: -0.04, duration: 0.18),
                                .rotate(toAngle: 0, duration: 0.20)]), withKey: "motionTilt")
            return
        }
        // Full 360, all skins. `root` is the single visual root: body, tuft,
        // arms, legs and face all hang off it (via squashNode/breatheNode),
        // so this rotates the creature as ONE object. An earlier build looked
        // like the limbs detached mid-spin; that was not the rotation but a
        // real gap under the body from a mis-converted leg lift, which the
        // spin simply made obvious. Fixing the lift fixed the spin.
        let spinDuration: TimeInterval = 0.75
        let spin = SKAction.rotate(byAngle: facing >= 0 ? -2 * .pi : 2 * .pi, duration: spinDuration)
        spin.timingMode = .easeInEaseOut
        let reset = SKAction.run { [weak self] in self?.root.zRotation = 0 }
        root.run(.sequence([spin, reset]), withKey: "motionTilt")
        runSquash([.wait(forDuration: spinDuration),
                   .scaleX(to: 1.12, y: 0.88, duration: 0.10),
                   .scaleX(to: 1.0, y: 1.0, duration: 0.18)])
    }

    // Pick up / drop (press-and-hold, then drag).

    private(set) var isCarried = false

    /// `lifted` false = a ground drag (perspective field): the creature keeps
    /// its feet on the plane, so no lift squash and no shadow soften — the
    /// field renderer owns the shadow weight continuously.
    func beginCarry(lifted: Bool = true) {
        isCarried = true
        guard lifted else { return }
        runSquash([.scaleX(to: 0.95, y: 1.07, duration: 0.12)])
        // Lifted off the ground: the shadow softens and pulls in a little.
        shadowNode.removeAction(forKey: "shadowPhase")
        shadowNode.run(.group([
            .scale(to: 0.82, duration: 0.18),
            .fadeAlpha(to: 0.55, duration: 0.18),
        ]), withKey: "shadowPhase")
    }

    /// Follow the drag directly (no lag on the position itself); a light
    /// smoothed tilt into the movement direction adds the dangling feel.
    func carryMove(to point: CGPoint) {
        let dx = point.x - position.x
        position = point
        carryTilt(dx: dx)
    }

    /// The dangle/lean HALF of a carry move, for drags whose position is
    /// owned elsewhere (the perspective field): tilt only, no position write.
    func carryTilt(dx: CGFloat) {
        guard !reduceMotion else { return }
        let target = max(-0.14, min(0.14, -dx * 0.02))
        root.zRotation = root.zRotation * 0.8 + target * 0.2
    }

    func endCarry() {
        isCarried = false
        let back = SKAction.rotate(toAngle: 0, duration: 0.14)
        back.timingMode = .easeOut
        root.run(back, withKey: "motionTilt")
        if reduceMotion {
            runSquash([.scaleX(to: 1.02, y: 0.99, duration: 0.10),
                       .scaleX(to: 1.0, y: 1.0, duration: 0.14)])
        } else {
            runSquash([.scaleX(to: 1.12, y: 0.88, duration: 0.08),
                       .scaleX(to: 0.98, y: 1.03, duration: 0.08),
                       .scaleX(to: 1.0, y: 1.0, duration: 0.13)])
        }
        landShadow()
    }

    /// A few hearts drifting up from the creature.
    private func emitHearts() {
        for i in 0..<4 {
            let heart = SKSpriteNode(texture: Self.heartTexture)
            heart.position = CGPoint(x: CGFloat.random(in: -50...50),
                                     y: CGFloat.random(in: 20...60))
            heart.setScale(CGFloat.random(in: 0.6...1.0))
            heart.alpha = 0
            heart.zPosition = 10
            addChild(heart)
            let rise = SKAction.moveBy(x: CGFloat.random(in: -14...14),
                                       y: CGFloat.random(in: 60...95), duration: 0.9)
            rise.timingMode = .easeOut
            heart.run(.sequence([
                .wait(forDuration: Double(i) * 0.07),
                .group([.fadeIn(withDuration: 0.15), rise]),
                .fadeOut(withDuration: 0.25),
                .removeFromParent(),
            ]))
        }
    }

    private static let heartTexture: SKTexture = {
        let s: CGFloat = 30
        let image = UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            let c = ctx.cgContext
            UIColor(red: 1, green: 0.45, blue: 0.6, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 0, y: s * 0.10, width: s * 0.52, height: s * 0.52))
            c.fillEllipse(in: CGRect(x: s * 0.48, y: s * 0.10, width: s * 0.52, height: s * 0.52))
            c.move(to: CGPoint(x: s * 0.04, y: s * 0.44))
            c.addLine(to: CGPoint(x: s * 0.96, y: s * 0.44))
            c.addLine(to: CGPoint(x: s * 0.5, y: s * 0.97))
            c.closePath()
            c.fillPath()
        }
        return SKTexture(image: image)
    }()

    // MARK: - Calm Mode behaviors (quiet, settled — never compete with play)

    private(set) var isCalmSettled = false

    /// Settle into calm: everything slows — shallow bob, long breaths, sleepy
    /// blinks, a small sit-down dip. Safe to call again (e.g. after a
    /// breathing session) — the dip only happens once.
    func enterCalm() {
        removeAction(forKey: "blinkLoop")
        removeAction(forKey: "swayLoop")
        root.removeAction(forKey: "idleSway")
        root.removeAction(forKey: "bob")
        breatheNode.removeAction(forKey: "breathe")

        // Calm grounding: the creature stands on real painted ground, so
        // the contact shadow works harder — wider and denser than the play
        // scenes, hugging the body's base.
        shadowNode.removeAction(forKey: "shadowDepth")
        shadowNode.run(.group([
            .fadeAlpha(to: min(1.0, Self.shadowRestAlpha * 1.4), duration: 0.8),
            .scaleX(to: 1.28, duration: 0.8),
        ]))

        // Calm aura = a tight cinematic rim, not a haze: pull the halo close
        // to the silhouette and quiet it. (Home keeps the fuller aura — this
        // scene instance is Calm's own.)
        auraNode.removeAction(forKey: "auraPulse")
        auraNode.setScale(Self.auraScale * 0.67)
        let auraUp = SKAction.fadeAlpha(to: 0.58, duration: 3.2)
        let auraDown = SKAction.fadeAlpha(to: 0.42, duration: 3.2)
        auraUp.timingMode = .easeInEaseOut
        auraDown.timingMode = .easeInEaseOut
        auraNode.alpha = 0.50
        auraNode.run(.repeatForever(.sequence([auraUp, auraDown])),
                     withKey: "auraPulse")

        // Environmental integration: a whisper of cool moon rim just beyond
        // the silhouette, strongest over the head and shoulders — the night
        // touching the creature, not a second aura.
        if childNode(withName: "calmMoonRim") == nil {
            let rim = SKSpriteNode(texture: auraNode.texture)
            rim.name = "calmMoonRim"
            rim.size = auraNode.size
            rim.color = SKColor(red: 0.70, green: 0.80, blue: 1.0, alpha: 1)
            rim.colorBlendFactor = 1
            rim.blendMode = .add
            rim.alpha = 0.15
            rim.setScale(Self.auraScale * 0.76)
            rim.zPosition = auraNode.zPosition + 0.1
            rim.position = CGPoint(x: auraNode.position.x,
                                   y: auraNode.position.y + 12)
            addChild(rim)
        }

        if !isCalmSettled {
            isCalmSettled = true
            root.run(.moveBy(x: 0, y: -12, duration: 0.8), withKey: "settle")
        }

        let bobUp = SKAction.moveBy(x: 0, y: 4, duration: 2.6)
        let bobDown = SKAction.moveBy(x: 0, y: -4, duration: 2.6)
        bobUp.timingMode = .easeInEaseOut
        bobDown.timingMode = .easeInEaseOut
        root.run(.repeatForever(.sequence([bobUp, bobDown])), withKey: "bob")

        // Same working scaleX(to:y:) + grounded-feet pose as the play idle,
        // at calm's slower, softer settings.
        let inhale = breathPose(x: 1.0, y: 1.022, duration: 2.8)
        let exhale = breathPose(x: 1.014, y: 0.992, duration: 2.8)
        breatheNode.run(.repeatForever(.sequence([inhale, exhale])), withKey: "breathe")

        let wait = SKAction.wait(forDuration: 4.5, withRange: 3.0)
        let blink = SKAction.run { [weak self] in self?.slowBlink() }
        run(.repeatForever(.sequence([wait, blink])), withKey: "blinkLoop")
    }

    /// Back to the normal lively idle.
    func exitCalm() {
        removeAction(forKey: "blinkLoop")
        root.removeAction(forKey: "bob")
        breatheNode.removeAction(forKey: "breathe")
        endCalmLean()
        lookForward()
        if isCalmSettled {
            isCalmSettled = false
            root.run(.moveBy(x: 0, y: 12, duration: 0.5), withKey: "settle")
        }
        startIdle()
    }

    func slowBlink() {
        guard eyesNode.texture != nil else { return }
        let close = SKAction.scaleY(to: 0.12, duration: 0.18)
        let open  = SKAction.scaleY(to: 1.0, duration: 0.30)
        eyesNode.run(.sequence([close, open]))
    }

    /// Calm tap: a tiny acknowledging nod and a sleepy blink.
    func calmNod() {
        slowBlink()
        let dip = SKAction.scaleX(to: 1.03, y: 0.97, duration: 0.25)
        let rise = SKAction.scaleX(to: 1.0, y: 1.0, duration: 0.35)
        dip.timingMode = .easeInEaseOut
        rise.timingMode = .easeOut
        runSquash([dip, rise])
    }

    /// Calm stroke/hold: lean gently toward the touch, eyes nearly closed.
    func calmLean(toward direction: CGFloat) {
        let angle: CGFloat = direction >= 0 ? -0.06 : 0.06
        squashNode.run(.rotate(toAngle: angle, duration: 0.6), withKey: "lean")
        eyesNode.run(.scaleY(to: 0.25, duration: 0.5), withKey: "eyesSoft")
    }

    func endCalmLean() {
        squashNode.run(.rotate(toAngle: 0, duration: 0.6), withKey: "lean")
        eyesNode.run(.scaleY(to: 1.0, duration: 0.5), withKey: "eyesSoft")
    }

    /// Eyes drift gently toward a scene point (sparkles, a distant tap). On the
    /// Blender skin the dark eye is fixed art that must NEVER slide — so only the
    /// sparkle tracks, via `glanceToward` (this is what makes calm mode behave
    /// like Home). The placeholder art, which has no separate sparkle, slides its
    /// whole eye as before.
    func lookToward(_ scenePoint: CGPoint) {
        guard Self.eyesFollowInput else { return }
        if usesBlenderSkin { glanceToward(scenePoint); return }
        let dx = scenePoint.x - position.x
        let dy = scenePoint.y - position.y
        let mag = max(hypot(dx, dy), 1)
        let target = CGPoint(x: dx / mag * 7, y: 30 + dy / mag * 4)
        let move = SKAction.move(to: target, duration: 0.5)
        move.timingMode = .easeOut
        eyesNode.run(move, withKey: "look")
    }

    func lookForward() {
        if usesBlenderSkin { endGlance(); return }   // ease the sparkle home
        let move = SKAction.move(to: CGPoint(x: 0, y: 30), duration: 0.6)
        move.timingMode = .easeInEaseOut
        eyesNode.run(move, withKey: "look")
    }

    /// Rare calm-shake response: the tiniest wobble, then settling exhale.
    func calmWobble() {
        let l = SKAction.rotate(toAngle: 0.03, duration: 0.15)
        let r = SKAction.rotate(toAngle: -0.03, duration: 0.25)
        let settle = SKAction.rotate(toAngle: 0, duration: 0.3)
        root.run(.sequence([l, r, settle]), withKey: "motionTilt")
        let exhale = SKAction.scaleX(to: 1.04, y: 0.97, duration: 0.5)
        let recover = SKAction.scaleX(to: 1.0, y: 1.0, duration: 0.7)
        exhale.timingMode = .easeInEaseOut
        recover.timingMode = .easeOut
        runSquash([exhale, recover])
    }

    // MARK: Breathe Together (Calm Mode)

    /// Big slow synchronized breathing: rise + expand on the inhale, settle on
    /// the exhale. `cycle` is one full in+out.
    /// `root`'s Y before "Breathe Together" displaces it. `startBreathing`
    /// runs a repeating `moveBy(y: ±16)` on `root`, so simply removing that
    /// action leaves whatever partial offset the cycle had reached — which
    /// used to persist for the rest of the Calm session (fixed 2026-09-21).
    /// Captured only on the FIRST start, so repeated start/stop can never
    /// bake an offset into the baseline.
    private var breatheBaselineY: CGFloat?

    func startBreathing(cycle: TimeInterval = 8) {
        breatheNode.removeAction(forKey: "breathe")
        root.removeAction(forKey: "bob")
        if breatheBaselineY == nil { breatheBaselineY = root.position.y }
        let half = cycle / 2
        let inhaleScale = SKAction.scaleX(to: 1.08, y: 1.12, duration: half)
        let exhaleScale = SKAction.scaleX(to: 1.0, y: 1.0, duration: half)
        inhaleScale.timingMode = .easeInEaseOut
        exhaleScale.timingMode = .easeInEaseOut
        breatheNode.run(.repeatForever(.sequence([inhaleScale, exhaleScale])), withKey: "breatheTogether")
        let up = SKAction.moveBy(x: 0, y: 16, duration: half)
        let down = SKAction.moveBy(x: 0, y: -16, duration: half)
        up.timingMode = .easeInEaseOut
        down.timingMode = .easeInEaseOut
        root.run(.repeatForever(.sequence([up, down])), withKey: "breatheRise")
    }

    /// Back to the quiet calm idle.
    func stopBreathing() {
        breatheNode.removeAction(forKey: "breatheTogether")
        root.removeAction(forKey: "breatheRise")
        breatheNode.run(breathPose(x: 1.0, y: 1.0, duration: 0.8))
        guard let baseline = breatheBaselineY else {
            enterCalm()
            return
        }
        breatheBaselineY = nil
        #if DEBUG
        // Position-restore proof: `settled` must equal `baseline` no matter
        // where in the cycle we stopped. AURIE_BREATHE_LOG=1
        if ProcessInfo.processInfo.environment["AURIE_BREATHE_LOG"] == "1" {
            NSLog("AURIE_BREATHE stop baseline=%.2f displaced=%.2f",
                  baseline, root.position.y)
            root.run(.sequence([.wait(forDuration: 1.2),
                                .run { [weak self] in
                NSLog("AURIE_BREATHE settled y=%.2f",
                      self?.root.position.y ?? -999)
            }]), withKey: "breatheLog")
        }
        #endif
        // Ease back to the pre-breathing baseline, THEN hand back to the
        // calm idle. Runs on the "bob" key — the same key the calm bob uses
        // and which `startBreathing` cleared — so the settle and the bob can
        // never fight over `root.position`. `enterCalm()` is documented as
        // safe to call again and reinstalls the bob around the correct Y.
        let settle = SKAction.moveTo(y: baseline, duration: 0.8)
        settle.timingMode = .easeInEaseOut
        root.run(.sequence([settle,
                            .run { [weak self] in self?.enterCalm() }]),
                 withKey: "bob")
    }

    // MARK: - Birth reaction + idle moments (phase 5, §8.3-8.4)

    /// One short "I'm alive!" beat at the reveal.
    func playBirthReaction() {
        switch Int.random(in: 0..<4) {
        case 0:   // blink and look around
            slowBlink()
            lookAround()
        case 1:   // topple over and pop back up
            let tip = SKAction.rotate(toAngle: 0.35, duration: 0.25)
            tip.timingMode = .easeIn
            let pop = SKAction.rotate(toAngle: -0.06, duration: 0.18)
            let settle = SKAction.rotate(toAngle: 0, duration: 0.2)
            settle.timingMode = .easeOut
            squashNode.run(.sequence([tip, .wait(forDuration: 0.35), pop, settle]), withKey: "birth")
            run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in self?.reactBounce() }]))
        case 2:   // big stretch
            stretchTall()
        default:  // happy bounce-wiggle
            reactBounce()
            run(.sequence([.wait(forDuration: 0.3), .run { [weak self] in self?.reactPet() }]))
        }
    }

    /// Eyes wander left, right, then home. On the Blender skin the dark eye is
    /// fixed art and must not slide (same rule as `inspectFoot`), so this idle
    /// glance is a no-op there — only the placeholder eye wanders.
    func lookAround() {
        guard !usesBlenderSkin else { return }
        let left  = SKAction.move(to: CGPoint(x: -7, y: 30), duration: 0.5)
        let right = SKAction.move(to: CGPoint(x: 7, y: 32), duration: 0.7)
        let home  = SKAction.move(to: CGPoint(x: 0, y: 30), duration: 0.5)
        [left, right, home].forEach { $0.timingMode = .easeInEaseOut }
        eyesNode.run(.sequence([left, .wait(forDuration: 0.4), right, .wait(forDuration: 0.4), home]),
                     withKey: "look")
    }

    // MARK: - Autonomous behaviour primitives

    /// Autonomous pupil glance: slides ONLY the catch sparkles (the dark eye
    /// is fixed art) by a clamped offset, holds, then eases home — the same
    /// clamp the finger-tracking uses, so a sparkle can never leave the eye.
    /// The placeholder body slides its whole drawn eye like the old idle
    /// glance. A no-op while finger-tracking owns the sparkles or a blink /
    /// arc-eye expression has them hidden.
    func sparkleGlance(dx: CGFloat, dy: CGFloat, hold: TimeInterval,
                       out: TimeInterval = 0.35, back: TimeInterval = 0.4) {
        guard eyeLookOffset == .zero else { return }
        let cdx = max(-Self.eyeTrackX, min(Self.eyeTrackX, dx))
        let cdy = max(-Self.eyeTrackY, min(Self.eyeTrackY, dy))
        let node = usesBlenderSkin ? catchNode : eyesNode
        if usesBlenderSkin, catchNode.isHidden || catchNode.texture == nil {
            return
        }
        let rest = usesBlenderSkin ? catchRest : CGPoint(x: 0, y: 30)
        let to = SKAction.move(to: CGPoint(x: rest.x + cdx, y: rest.y + cdy),
                               duration: out)
        let home = SKAction.move(to: rest, duration: back)
        to.timingMode = .easeInEaseOut
        home.timingMode = .easeInEaseOut
        node.run(.sequence([to, .wait(forDuration: hold), home]), withKey: "look")
    }

    /// Autonomous: something offscreen? The pupils dart to one side with a
    /// small body lean; sometimes it checks the other side too, then settles.
    func curiousLook() {
        guard root.action(forKey: "motionTilt") == nil else { return }
        let side: CGFloat = Bool.random() ? 1 : -1
        let both = Bool.random()
        sparkleGlance(dx: side * Self.eyeTrackX, dy: 1,
                      hold: both ? 0.7 : 1.1)
        let lean = SKAction.rotate(toAngle: side * 0.035, duration: 0.4)
        lean.timingMode = .easeInEaseOut
        let level = SKAction.rotate(toAngle: 0, duration: 0.45)
        level.timingMode = .easeInEaseOut
        if both {
            let leanB = SKAction.rotate(toAngle: -side * 0.028, duration: 0.5)
            leanB.timingMode = .easeInEaseOut
            root.run(.sequence([lean, .wait(forDuration: 0.55), leanB,
                                .wait(forDuration: 0.5), level]),
                     withKey: "motionTilt")
            run(.sequence([.wait(forDuration: 1.5), .run { [weak self] in
                guard let self else { return }
                self.sparkleGlance(dx: -side * Self.eyeTrackX, dy: 1, hold: 0.5)
            }]), withKey: "autoStage")
        } else {
            root.run(.sequence([lean, .wait(forDuration: 1.1), level]),
                     withKey: "motionTilt")
        }
    }

    /// Autonomous: a short sleepy beat — eyes soften into the yawn, a small
    /// slump, then perk back up. Root targets are ABSOLUTE so an interrupt
    /// can never leave the body sunk.
    func sleepyMoment() {
        yawn()
        let down = SKAction.moveTo(y: -7, duration: 0.5)
        down.timingMode = .easeOut
        let up = SKAction.moveTo(y: 0, duration: 0.5)
        up.timingMode = .easeInEaseOut
        root.run(.sequence([.wait(forDuration: 0.3), down,
                            .wait(forDuration: 1.0), up]), withKey: "sit")
        runSquash([.scaleX(to: 1.04, y: 0.96, duration: 0.6),
                   .wait(forDuration: 0.9),
                   .scaleX(to: 1.0, y: 1.0, duration: 0.5)])
    }

    /// Autonomous: a soft plush stretch — small compress, an easy rise, arms
    /// drifting slightly outward, then back to exact proportions.
    func stretchSoft() {
        runSquash([.scaleX(to: 1.05, y: 0.95, duration: 0.35),
                   .scaleX(to: 0.94, y: 1.10, duration: 0.55),
                   .wait(forDuration: 0.55),
                   .scaleX(to: 1.0, y: 1.0, duration: 0.45)])
        guard armRotationSafe else { return }
        for (joint, dir) in [(armJointR, CGFloat(1)), (armJointL, CGFloat(-1))] {
            guard let joint else { continue }
            let out = SKAction.rotate(toAngle: dir * 0.5, duration: 0.6)
            out.timingMode = .easeInEaseOut
            let home = SKAction.rotate(toAngle: 0, duration: 0.5)
            home.timingMode = .easeInEaseOut
            joint.run(.sequence([.wait(forDuration: 0.3), out,
                                 .wait(forDuration: 0.45), home]),
                      withKey: "armGesture")
        }
    }

    // MARK: - Object-interaction gestures (reusable arm vocabulary)

    /// The shoulder joint on `side` (>= 0 right), if the body is jointed.
    private func armJoint(side: CGFloat) -> SKNode? {
        side >= 0 ? armJointR : armJointL
    }

    /// Reach one arm toward a scene point: the nearest arm rotates about its
    /// shoulder joint toward the target's height — side-level for things
    /// beside the body, up to the approved wave apex for things overhead —
    /// with a small lean. Holds, then returns EXACTLY to rest. Returns the
    /// side used (nil when unjointed / carried). The rotation never exceeds
    /// the wave's proven 1.45 rad, so the shoulder stays attached and the
    /// arm never stretches.
    @discardableResult
    func armReach(toward scenePoint: CGPoint, hold: TimeInterval = 0.5,
                  lean: Bool = true) -> CGFloat? {
        guard armRotationSafe, !isCarried else { return nil }
        let dx = scenePoint.x - position.x
        let side: CGFloat = dx >= 0 ? 1 : -1
        guard let joint = armJoint(side: side) else { return nil }
        // Elevation from the target's height relative to the body: shoulder
        // height ~0 → 0.85 rad (side reach); overhead → 1.45 (wave apex).
        let s = max(abs(xScale), 0.0001)
        let dyNorm = (scenePoint.y - position.y) / (AssetLoader.collisionHalfHeightUp * s)
        let angle = (0.85 + max(-0.25, min(0.6, dyNorm * 0.6))) * side
        let raise = SKAction.rotate(toAngle: angle, duration: 0.22)
        raise.timingMode = .easeOut
        let lower = SKAction.rotate(toAngle: 0, duration: 0.26)
        lower.timingMode = .easeInEaseOut
        joint.run(.sequence([raise, .wait(forDuration: hold), lower]),
                  withKey: "armGesture")
        if lean, root.action(forKey: "motionTilt") == nil {
            let tilt = SKAction.rotate(toAngle: side * 0.03, duration: 0.22)
            tilt.timingMode = .easeOut
            let level = SKAction.rotate(toAngle: 0, duration: 0.26)
            level.timingMode = .easeInEaseOut
            root.run(.sequence([tilt, .wait(forDuration: hold), level]),
                     withKey: "motionTilt")
        }
        return side
    }

    /// A quick bat/swat with one arm — snappy enough that an object nudged at
    /// its apex reads as HIT. `up` bats overhead height. ~0.35 s total; apex
    /// at ~0.14 s. Returns exactly to rest.
    func armBat(side: CGFloat, up: Bool = false) {
        guard armRotationSafe, !isCarried,
              let joint = armJoint(side: side) else { return }
        let angle = (up ? 1.35 : 0.95) * (side >= 0 ? 1 : -1)
        let swing = SKAction.rotate(toAngle: angle, duration: 0.14)
        swing.timingMode = .easeOut
        let back = SKAction.rotate(toAngle: 0, duration: 0.22)
        back.timingMode = .easeInEaseOut
        joint.run(.sequence([swing, back]), withKey: "armGesture")
    }

    /// Both arms curl gently inward toward something held at the chest —
    /// the rare "catch" moment. Small angles only, so both shoulders stay
    /// visibly attached; holds, then returns exactly.
    func twoHandReach(hold: TimeInterval = 0.7) {
        guard armRotationSafe, !isCarried,
              let l = armJointL, let r = armJointR else { return }
        for (joint, angle) in [(r, CGFloat(0.55)), (l, CGFloat(-0.55))] {
            let curl = SKAction.rotate(toAngle: angle, duration: 0.26)
            curl.timingMode = .easeInEaseOut
            let open = SKAction.rotate(toAngle: 0, duration: 0.3)
            open.timingMode = .easeInEaseOut
            joint.run(.sequence([curl, .wait(forDuration: hold), open]),
                      withKey: "armGesture")
        }
    }

    /// Autonomous: "Oh! You're here!" — pupils dip toward the viewer, a
    /// bright little pop, one small arm lift.
    func greetUser() {
        sparkleGlance(dx: 0, dy: -2.5, hold: 0.9, out: 0.25)
        reactBounce()
        if armRotationSafe {
            run(.sequence([.wait(forDuration: 0.25), .run { [weak self] in
                self?.littleWave(big: false, side: Bool.random() ? 1 : -1)
            }]), withKey: "autoStage")
        }
    }

    /// Reach up tall, hold, settle.
    func stretchTall() {
        let up = SKAction.scaleX(to: 0.92, y: 1.14, duration: 0.5)
        let settle = SKAction.scaleX(to: 1.0, y: 1.0, duration: 0.4)
        up.timingMode = .easeInEaseOut
        settle.timingMode = .easeOut
        runSquash([up, .wait(forDuration: 0.5), settle])
    }

    /// Brief cozy sit.
    func sitDip() {
        let down = SKAction.moveBy(x: 0, y: -10, duration: 0.4)
        let upAgain = SKAction.moveBy(x: 0, y: 10, duration: 0.5)
        down.timingMode = .easeOut
        upAgain.timingMode = .easeInEaseOut
        root.run(.sequence([down, .wait(forDuration: 1.6), upAgain]), withKey: "sit")
        eyesNode.run(.sequence([.scaleY(to: 0.5, duration: 0.4), .wait(forDuration: 1.6),
                                .scaleY(to: 1.0, duration: 0.4)]), withKey: "eyesSoft")
    }

    /// Mouth-open yawn approximation.
    func yawn() {
        guard mouthNode.texture != nil else { return }
        let open = SKAction.scale(to: 1.6, duration: 0.5)
        let close = SKAction.scale(to: 1.0, duration: 0.4)
        open.timingMode = .easeInEaseOut
        mouthNode.run(.sequence([open, .wait(forDuration: 0.5), close]), withKey: "yawn")
        eyesNode.run(.sequence([.scaleY(to: 0.3, duration: 0.5), .wait(forDuration: 0.5),
                                .scaleY(to: 1.0, duration: 0.4)]), withKey: "eyesSoft")
    }

    /// Wind-up... choo! (particles supplied by the scene).
    func sneeze() {
        let windup = SKAction.scaleX(to: 0.94, y: 1.08, duration: 0.35)
        let choo = SKAction.scaleX(to: 1.14, y: 0.88, duration: 0.08)
        let recover = SKAction.scaleX(to: 1.0, y: 1.0, duration: 0.25)
        windup.timingMode = .easeIn
        recover.timingMode = .easeOut
        runSquash([windup, choo, recover])
    }

    /// Something offscreen? Peer at it. On the Blender skin the dark eye is
    /// fixed art and must not slide (same rule as `inspectFoot`/`lookAround`),
    /// so only the placeholder eye peers; the pinned `face()` never mirrors.
    func noticeOffscreen() {
        guard !usesBlenderSkin else { return }
        let direction: CGFloat = Bool.random() ? 1 : -1
        face(direction)
        eyesNode.run(.sequence([
            .move(to: CGPoint(x: direction * 8, y: 33), duration: 0.4),
            .wait(forDuration: 1.2),
            .move(to: CGPoint(x: 0, y: 30), duration: 0.5),
        ]), withKey: "look")
    }

    // MARK: - Expression seam (phase 5, §8.6)

    enum Expression { case neutral, happy, surprised, dizzy, sleepy, laughing }

    /// Fleeting facial state. TODO(art): when expression sprite variants
    /// exist (e.g. `eyes_03_happy`, `mouth_02_laughing` per ART_GUIDE naming),
    /// swap textures here via AssetLoader; until then these are procedural
    /// approximations on the neutral art, and .neutral restores rest state.
    func setExpression(_ expression: Expression, for duration: TimeInterval = 1.1) {
        guard eyesNode.texture != nil else { return }
        eyesNode.removeAction(forKey: "expr")
        if usesBlenderSkin {
            // The Blender eye layer is DRAWN artwork, so the legacy
            // scale-based approximations distort it (a celebration caught
            // mid-animation stretched the delighted crescents across the
            // whole face). Swap the real catalog face instead.
            blenderSetExpression(expression, for: duration)
            return
        }
        // Every branch now ENDS by restoring the Aurie's saved base face
        // instead of springing back to scale 1.0. Returning to 1.0 quietly
        // erased the personality expression: one pet or tickle and a Sleepy
        // creature had wide-open eyes for the rest of the session.
        let restore = SKAction.run { [weak self] in
            guard let self, self.currentReaction == nil else { return }
            self.applyFace(self.baseExpression.rawValue)
        }
        switch expression {
        case .neutral:
            eyesNode.run(restore, withKey: "expr")
        case .happy:
            eyesNode.run(.sequence([.scaleY(to: 0.65, duration: 0.15),
                                    .wait(forDuration: duration),
                                    restore]), withKey: "expr")
        case .surprised:
            // No eye enlargement — a dramatic scale-up read as comically huge
            // eyes. Surprise is carried by a blink-pop + the body recoil the
            // caller pairs with it.
            eyesNode.run(.sequence([.scaleY(to: 0.2, duration: 0.06),
                                    .scaleY(to: 1.0, duration: 0.10),
                                    .wait(forDuration: duration),
                                    restore]), withKey: "expr")
        case .dizzy:
            let wob = SKAction.sequence([.rotate(toAngle: 0.3, duration: 0.12),
                                         .rotate(toAngle: -0.3, duration: 0.12)])
            eyesNode.run(.sequence([.repeat(wob, count: 4),
                                    .rotate(toAngle: 0, duration: 0.15),
                                    restore]), withKey: "expr")
        case .sleepy:
            eyesNode.run(.sequence([.scaleY(to: 0.35, duration: 0.4),
                                    .wait(forDuration: duration),
                                    restore]), withKey: "expr")
        case .laughing:
            let squeeze = SKAction.sequence([.scaleY(to: 0.4, duration: 0.1),
                                             .scaleY(to: 0.7, duration: 0.1)])
            eyesNode.run(.sequence([.repeat(squeeze, count: 4),
                                    restore]), withKey: "expr")
        }
    }

    // MARK: - Reaction system
    //
    // The runtime half of the approved design. It adds NO new animation
    // machinery: every pose below is built from the squash / tilt / hop /
    // eye actions above, and faces go through the same expression seam.
    // What is new is the bookkeeping the design asked for — one saved base
    // expression applied as a RESTING face, one temporary override at a
    // time resolved by priority, and hard cancellation so a reaction can
    // never outlive the scene, a backgrounding, or a change of creature.
    //
    // Art note: the 3D expression catalogue is not in the app as sprites
    // yet, so each face maps to the closest procedural treatment of the
    // single art set (the TODO(art) above still stands). Swapping in real
    // per-expression textures later is a change to `applyFace` alone.

    /// The creature's saved personality face. A reaction never writes this.
    private(set) var baseExpression: BaseExpression = .happy

    /// The temporary override currently playing, if any.
    private(set) var currentReaction: AurieReaction?

    /// Bumped by every cancellation. Anything a reaction scheduled checks
    /// this before touching the face, so work belonging to a cancelled
    /// reaction cannot resurrect a stale expression after the fact.
    private var reactionGeneration = 0

    /// Resting eye scale for the current base face, so a blink returns to
    /// the Aurie's own expression instead of flattening it back to 1.0.
    private var restEyeScaleY: CGFloat = 1.0

    /// Adopt an Aurie's saved face. Cancels anything in flight first, so
    /// switching the active creature can never leave the previous
    /// creature's reaction running on the new one.
    func adoptBaseExpression(_ expression: BaseExpression) {
        cancelReactions()
        baseExpression = expression
        applyFace(expression.rawValue)
    }

    /// Stop any reaction immediately and return to the saved face.
    func cancelReactions() {
        reactionGeneration &+= 1
        currentReaction = nil
        removeAction(forKey: "reaction")
        eyesNode.removeAction(forKey: "expr")
        applyFace(baseExpression.rawValue)
    }

    /// Play a reaction if priority allows; returns false when it was
    /// dropped, so callers can tell "ignored" from "played".
    @discardableResult
    func play(_ reaction: AurieReaction) -> Bool {
        guard reaction.canInterrupt(currentReaction) else { return false }
        let token = reactionGeneration
        currentReaction = reaction
        applyFace(reaction.overrideFace ?? baseExpression.rawValue)
        performReactionBody(reaction)
        // ONE keyed timer owns the return-to-base for every reaction, so a
        // higher-priority reaction replaces it rather than stacking a
        // second restore that would fire in the middle of the new one.
        run(.sequence([.wait(forDuration: reaction.duration),
                       .run { [weak self] in
                           guard let self, self.reactionGeneration == token,
                                 self.currentReaction == reaction else { return }
                           self.restoreBaseFace()
                       }]), withKey: "reaction")
        return true
    }

    /// Startled -> dizzy -> recovery squint -> saved face. Exposed as one
    /// call so the Wonderglobe sequence can reuse exactly what a manual
    /// shake does instead of scripting its own character animation.
    func playShakeSequence() {
        guard AurieReaction.startled.canInterrupt(currentReaction) else { return }
        let token = reactionGeneration
        currentReaction = .dizzy        // holds the high slot for the whole flow
        applyFace("surprised")
        performReactionBody(.startled)
        let guarded: (TimeInterval, @escaping () -> Void) -> Void = { [weak self] delay, work in
            self?.run(.sequence([.wait(forDuration: delay), .run { [weak self] in
                guard let self, self.reactionGeneration == token else { return }
                work()
            }]), withKey: "reactionStep\(Int(delay * 100))")
        }
        guarded(0.45) { [weak self] in
            guard let self else { return }
            self.applyFace(BaseExpression.delighted.rawValue)
            self.performReactionBody(.dizzy)
        }
        guarded(1.75) { [weak self] in self?.applyFace("calm") }
        run(.sequence([.wait(forDuration: 2.15), .run { [weak self] in
            guard let self, self.reactionGeneration == token else { return }
            self.restoreBaseFace()
        }]), withKey: "reaction")
    }

    private func restoreBaseFace() {
        currentReaction = nil
        applyFace(baseExpression.rawValue)
    }

    /// Resting face. Unlike `setExpression` (a fleeting state that springs
    /// back), this is where the face LIVES until something changes it.
    ///
    /// This swaps the eye AND mouth GEOMETRY, which is the whole point: the
    /// face used to be two baked bitmaps, so scaling them could never show a
    /// narrowed eye, a crossed eye, a crescent or a different mouth — every
    /// expression rendered identically. `AurieFaceRenderer` draws each one.
    /// The face currently on screen. A blink re-applies this rather than the
    /// persisted base expression, so a temporary face (a reaction, or an
    /// autonomous mood like Stone's annoyance at the radio) survives blinking
    /// instead of being reset every couple of seconds.
    private(set) var shownFaceId: String = BaseExpression.happy.rawValue

    private func applyFace(_ faceId: String) {
        shownFaceId = faceId
        if usesBlenderSkin {
            applyBlenderFace(faceId, blink: false)
            eyesAreClosed = (faceId == "delighted")
            restEyeScaleY = 1.0
            eyesNode.setScale(1)
            return
        }
        guard eyesNode.texture != nil else { return }
        eyesNode.removeAction(forKey: "expr")
        let eyeTexture = SKTexture(image: AurieFaceRenderer.eyes(faceId))
        eyesNode.texture = eyeTexture
        eyesNode.size = eyeTexture.size()
        let mouthTexture = SKTexture(image: AurieFaceRenderer.mouth(faceId))
        mouthNode.texture = mouthTexture
        mouthNode.size = mouthTexture.size()
        mouthNode.isHidden = false
        // The expression now lives in the drawn geometry, so the node's own
        // transform goes back to rest; blink still squashes from here.
        eyesNode.setScale(1)
        eyesNode.zRotation = 0
        restEyeScaleY = 1.0
        // Faces whose eyes are already closed have nothing to blink.
        eyesAreClosed = (faceId == "delighted")
    }

    /// Legacy fleeting-expression API mapped onto real catalog faces.
    /// Falls back to leaving the face alone when the mapped art is absent,
    /// so it can never distort or blank the creature.
    private func blenderSetExpression(_ expression: Expression,
                                      for duration: TimeInterval) {
        let id: String?
        switch expression {
        case .neutral:   id = nil
        case .happy:     id = BaseExpression.happy.rawValue
        case .surprised: id = BaseExpression.surprised.rawValue
        case .sleepy:    id = BaseExpression.sleepy.rawValue
        case .laughing:  id = BaseExpression.delighted.rawValue
        // NOT "dizzy": that baked face carries two oversized catchlights
        // per eye, which renders as a multi-pupil alien stare. Delighted's
        // squeezed-shut arcs are the readable, cute way to say "spinning".
        case .dizzy:     id = BaseExpression.delighted.rawValue
        }
        guard currentReaction == nil else { return }   // never fight a reaction
        guard let id, AurieFaceCatalog.face(
                id, body: AurieBlenderSkin.key(blenderBody)) != nil else {
            applyBlenderFace(baseExpression.rawValue, blink: false)
            return
        }
        applyBlenderFace(id, blink: false)
        run(.sequence([.wait(forDuration: duration), .run { [weak self] in
            guard let self, self.currentReaction == nil else { return }
            self.applyBlenderFace(self.baseExpression.rawValue, blink: false)
        }]), withKey: "exprFace")
    }

    /// True when the current face draws its eyes shut, so the blink loop
    /// skips instead of squashing an already-closed crescent.
    private var eyesAreClosed = false

    /// Blink in the Blender skin: hold the closed-eye layer briefly, then
    /// restore whatever face is currently showing. Mouth and cheeks are
    /// untouched, so the expression survives the blink.
    private func blenderBlink(hold: TimeInterval = 0.13) {
        let face = currentReaction?.overrideFace ?? shownFaceId
        applyBlenderFace(face, blink: true)
        run(.sequence([.wait(forDuration: hold), .run { [weak self] in
            guard let self else { return }
            let now = self.currentReaction?.overrideFace ?? self.shownFaceId
            self.applyBlenderFace(now, blink: false)
        }]), withKey: "blenderBlink")
    }

    #if DEBUG
    /// Show any catalog face directly — parade/inspection only, bypassing
    /// the reaction machinery so the face holds still for a screenshot.
    func debugShowFace(_ faceId: String) {
        guard usesBlenderSkin else { return }
        removeAction(forKey: "reaction")
        currentReaction = nil
        applyBlenderFace(faceId, blink: false)
    }

    /// Hold the blink-closed eyes so a screenshot can catch them.
    func debugHoldBlink(_ seconds: TimeInterval) {
        guard usesBlenderSkin else { return }
        removeAction(forKey: "blinkLoop")
        blenderBlink(hold: seconds)
    }

    /// Hold one arm at a fixed wave angle so a screenshot can inspect the
    /// shoulder attachment. Logs the rig state.
    func debugHoldWave(_ angle: CGFloat) {
        NSLog("AURIE_WAVE_HOLD safe=%d jointR=%d jointL=%d",
              armRotationSafe ? 1 : 0, armJointR != nil ? 1 : 0,
              armJointL != nil ? 1 : 0)
        guard let joint = armJointR ?? armJointL else { return }
        joint.removeAction(forKey: "armGesture")
        joint.run(.rotate(toAngle: angle, duration: 0.4), withKey: "armGesture")
    }

    /// Everything that must be back at rest once motion settles, for the
    /// drift check. A clean creature reads all-zero rotation, unit squash,
    /// and every limb within a pixel of its captured home.
    func debugTransformReport() -> String {
        func limb(_ n: SKSpriteNode?, _ tag: String) -> String {
            guard let n, let r = limbRest[ObjectIdentifier(n)] else { return "" }
            let dp = hypot(n.position.x - r.pos.x, n.position.y - r.pos.y)
            let dr = abs(n.zRotation - r.rot)
            return String(format: " %@Δ=%.2fpx/%.3frad", tag, dp, dr)
        }
        return String(format:
            "rootRot=%.4f rootPos=(%.2f,%.2f) squash=(%.4f,%.4f) breathe=(%.4f,%.4f)%@%@%@%@",
            root.zRotation, root.position.x, root.position.y,
            squashNode.xScale, squashNode.yScale,
            breatheNode.xScale, breatheNode.yScale,
            limb(armL, "aL"), limb(armR, "aR"),
            limb(legL, "lL"), limb(legR, "lR"))
    }
    #endif

    private func performReactionBody(_ reaction: AurieReaction) {
        switch reaction {
        case .blink:        break                  // face-only by design
        case .happyBounce:  reactBounce()
        case .startled:     reactStartledPop()
        case .dizzy:        reactTumble()
        case .curiousLook:  reactCuriousLean()
        case .sleepyYawn:   reactYawnStretch()
        case .calmSettle:   reactCalmBreath()
        case .excitedHop:   reactCelebrationHop()
        }
    }

    /// Startled: a quick pop upward and a wide squash landing.
    private func reactStartledPop() {
        guard !reduceMotion else {
            runSquash([.scaleX(to: 0.98, y: 1.03, duration: 0.08),
                       .scaleX(to: 1.0, y: 1.0, duration: 0.14)])
            return
        }
        runSquash([.scaleX(to: 0.92, y: 1.10, duration: 0.07),
                   .scaleX(to: 1.06, y: 0.95, duration: 0.10),
                   .scaleX(to: 1.0, y: 1.0, duration: 0.16)])
        shadowNode.removeAction(forKey: "shadowPhase")
        shadowNode.run(.sequence([.scale(to: 0.88, duration: 0.07),
                                  .scale(to: 1.0, duration: 0.18)]),
                       withKey: "shadowPhase")
    }

    /// Curious: a slow lean, held, then released — the whole body stands in
    /// for a head turn, since the creature has no neck.
    private func reactCuriousLean() {
        guard root.action(forKey: "motionTilt") == nil else { return }
        let angle: CGFloat = reduceMotion ? 0.03 : 0.075
        let lean = SKAction.rotate(toAngle: facing >= 0 ? angle : -angle,
                                   duration: 0.35)
        let back = SKAction.rotate(toAngle: 0, duration: 0.45)
        lean.timingMode = .easeOut
        back.timingMode = .easeInEaseOut
        root.run(.sequence([lean, .wait(forDuration: 0.5), back]),
                 withKey: "motionTilt")
    }

    /// Yawn: settle down into the yawn, then one small stretch upward.
    private func reactYawnStretch() {
        runSquash([.scaleX(to: 1.04, y: 0.95, duration: 0.35),
                   .wait(forDuration: 0.55),
                   .scaleX(to: 0.96, y: 1.06, duration: 0.30),
                   .scaleX(to: 1.0, y: 1.0, duration: 0.30)])
    }

    /// Calm: one slow breath. Deliberately the gentlest reaction.
    private func reactCalmBreath() {
        runSquash([.scaleX(to: 1.03, y: 0.97, duration: 0.7),
                   .scaleX(to: 0.99, y: 1.02, duration: 0.8),
                   .scaleX(to: 1.0, y: 1.0, duration: 0.6)])
    }

    /// Celebration: a real hop in place — crouch, launch, soft landing,
    /// small rebound. Clearly bigger than `reactBounce`.
    private func reactCelebrationHop() {
        guard !reduceMotion else {
            runSquash([.scaleX(to: 1.04, y: 0.97, duration: 0.12),
                       .scaleX(to: 1.0, y: 1.0, duration: 0.18)])
            return
        }
        // Compact stages cap the excursion (CreatureScene sets the cap
        // from real headroom) so the crown never leaves the stage; the
        // squash-and-stretch below still sells the jump when short.
        let lift: CGFloat = min(78, celebrationLiftCap)
        root.run(.sequence([.wait(forDuration: 0.12),
                            .moveBy(x: 0, y: lift, duration: 0.20),
                            .moveBy(x: 0, y: -lift, duration: 0.22),
                            .moveBy(x: 0, y: lift * 0.28, duration: 0.12),
                            .moveBy(x: 0, y: -lift * 0.28, duration: 0.14)]),
                 withKey: "celebrationHop")
        runSquash([.scaleX(to: 1.10, y: 0.90, duration: 0.12),
                   .scaleX(to: 0.92, y: 1.11, duration: 0.16),
                   .scaleX(to: 1.0, y: 1.0, duration: 0.20),
                   .scaleX(to: 1.10, y: 0.89, duration: 0.10),
                   .scaleX(to: 1.0, y: 1.0, duration: 0.18)])
        liftShadow()
    }

    /// Shadow dip for the celebration hop, mirroring the hop's timing.
    private func liftShadow() {
        shadowNode.removeAction(forKey: "shadowPhase")
        shadowNode.run(.sequence([
            .group([.scale(to: 0.80, duration: 0.20),
                    .fadeAlpha(to: 0.5, duration: 0.20)]),
            .group([.scale(to: 1.0, duration: 0.24),
                    .fadeAlpha(to: Self.shadowRestAlpha, duration: 0.24)]),
        ]), withKey: "shadowPhase")
    }

    // MARK: - Limb gestures + Home interaction (Home animation gate)
    //
    // The Blender skin exposes each arm and leg as its OWN sprite (they were
    // rendered as separate holdout passes), so the gestures below move one
    // limb at a time. The placeholder skin packs both arms into a single node
    // and has no separate legs, so every limb method degrades to a whole-body
    // approximation through the shared squash — callers never branch on skin.
    //
    // These add NO new transform owners: limbs animate their own sprite
    // transforms (keys "armGesture"/"legKick"), body poses reuse squashNode
    // ("motionSquash") and root ("motionTilt"), faces go through the same
    // applyFace seam. Rest transforms are captured ONCE so every gesture
    // returns each limb to exactly home — no drift after repeated play.

    /// Flipped true once the shoulder-joint rig + animation-safe arm art are
    /// in place. Until then NOTHING rotates an arm — a cropped arm rotated
    /// about its centre detaches at the shoulder, which is the bug under
    /// review. Wave, idle arm-drift and arm-hug all check this.
    private var armRotationSafe = false

    /// Shoulder-joint nodes (anim-safe arms only). The arm sprite is a child
    /// offset from the joint, so rotating the joint pivots the arm about the
    /// shoulder — the whole point of the joint rig. Rest rotation is 0.
    private var armJoints: [String: SKNode] = [:]
    private var armJointL: SKNode? { armJoints["l"] }
    private var armJointR: SKNode? { armJoints["r"] }

    /// Hip-joint mirror of the arm rig (anim-safe legs only, 2026-09-12):
    /// splits and kicks rotate the JOINT so the leg swings about its buried
    /// hip root instead of sliding a cropped sprite off the body — the fix
    /// for the old "legs may part from the body" splits concession.
    private var legRotationSafe = false
    private var legJoints: [String: SKNode] = [:]

    private func legJoint(side: CGFloat) -> SKNode? {
        side >= 0 ? legJoints["r"] : legJoints["l"]
    }

    /// Build one leg on a hip joint, BEHIND the body. Legs are ground-
    /// anchored (the BODY rises by `legLift`, never the legs), so unlike the
    /// arm joint this one is not lifted.
    private func addLegJoint(_ side: String, tint: SKShader) {
        let layer = "\(blenderLegStyle)_\(side)"
        guard let spec = AurieBlenderSkin.orientedLayer(blenderBody, layer,
                                                        orientation),
              let pivot = AurieBlenderSkin.legPivot(blenderBody, layer,
                                                    orientation),
              let image = UIImage(named: spec.asset) else { return }
        let joint = SKNode()
        joint.position = pivot
        joint.zPosition = Z.limbs.rawValue + (side == "l" ? 0.03 : 0.04)
        let sprite = SKSpriteNode(texture: SKTexture(image: image))
        sprite.size = spec.size
        sprite.shader = tint
        sprite.position = CGPoint(x: spec.position.x - pivot.x,
                                  y: spec.position.y - pivot.y)
        joint.addChild(sprite)
        breatheNode.addChild(joint)
        legJoints[side] = joint
        blenderLayers[layer] = sprite
    }

    /// Build one arm on a shoulder joint, BEHIND the body. The joint sits at
    /// the shoulder pivot; the arm sprite hangs off it at (spritePos − pivot)
    /// so its resting placement is identical to the in-front version, only
    /// now the body conceals the root.
    private func addArmJoint(_ side: String, tint: SKShader) {
        let layer = "\(blenderArmStyle)_\(side)"
        guard let spec = AurieBlenderSkin.orientedLayer(blenderBody, layer,
                                                        orientation),
              let pivot = AurieBlenderSkin.armPivot(blenderBody, layer,
                                                    orientation),
              let image = UIImage(named: spec.asset) else { return }
        let joint = SKNode()
        joint.position = CGPoint(x: pivot.x, y: pivot.y + blenderLift)
        joint.zPosition = Z.limbs.rawValue + (side == "l" ? 0.01 : 0.02)
        let sprite = SKSpriteNode(texture: SKTexture(image: image))
        sprite.size = spec.size
        sprite.shader = tint
        sprite.position = CGPoint(x: spec.position.x - pivot.x,
                                  y: spec.position.y - pivot.y)
        joint.addChild(sprite)
        breatheNode.addChild(joint)
        armJoints[side] = joint
        blenderLayers[layer] = sprite
    }

    /// Home position of each shoulder JOINT, captured once. The clap is the
    /// only gesture that moves a joint (rather than just rotating it), so it
    /// needs an absolute home to return to.
    lazy var armJointRest: [String: CGPoint] = {
        var m: [String: CGPoint] = [:]
        for (side, joint) in armJoints { m[side] = joint.position }
        return m
    }()

    /// Home z of each shoulder joint. The clap draws the arms in FRONT of the
    /// body for its beat, and this puts them back behind it afterwards.
    lazy var armJointHomeZ: [String: CGFloat] = {
        var m: [String: CGFloat] = [:]
        for (side, joint) in armJoints { m[side] = joint.zPosition }
        return m
    }()

    private var armL: SKSpriteNode? { blenderLayers["\(blenderArmStyle)_l"] }
    private var armR: SKSpriteNode? { blenderLayers["\(blenderArmStyle)_r"] }
    private var legL: SKSpriteNode? { blenderLayers["\(blenderLegStyle)_l"] }
    private var legR: SKSpriteNode? { blenderLayers["\(blenderLegStyle)_r"] }

    /// Home position + rotation of every limb sprite, captured the first time
    /// it is asked for (after the skin is fully built). Every gesture eases
    /// back to exactly these, so twenty waves leave the limbs where they
    /// started.
    private lazy var limbRest: [ObjectIdentifier: (pos: CGPoint, rot: CGFloat)] = {
        var m: [ObjectIdentifier: (pos: CGPoint, rot: CGFloat)] = [:]
        for n in [armL, armR, legL, legR].compactMap({ $0 }) {
            m[ObjectIdentifier(n)] = (n.position, n.zRotation)
        }
        return m
    }()

    private func restRot(_ n: SKSpriteNode) -> CGFloat {
        limbRest[ObjectIdentifier(n)]?.rot ?? 0
    }
    private func restPos(_ n: SKSpriteNode) -> CGPoint {
        limbRest[ObjectIdentifier(n)]?.pos ?? n.position
    }

    /// True on the ten launch bodies (separate limb sprites). Home uses these
    /// exclusively; the guard keeps the placeholder path honest.
    var hasArticulatedLimbs: Bool { armR != nil || legR != nil }

    // MARK: - Touch regions (from the real rendered sprites)

    /// Which part of the Aurie a scene point lands on, or nil for empty space.
    enum Region: String { case armLeft, armRight, footLeft, footRight, head, belly }

    /// Region resolution priority: a visible ARM, then a visible FOOT, then
    /// the head band, then the rest of the body. Each test uses the LIVE
    /// sprite's frame — the exact rectangle the player sees — so the zones
    /// track every body silhouette and limb style with no generic rectangle.
    /// The limb sprites are holdout-cropped to their VISIBLE part (except the
    /// anim-safe arms, whose concealed shoulder root adds only a small sliver
    /// inside the body edge), so "tap the foot you can see" is literally the
    /// test being run. A small pad forgives fat fingers without creating
    /// zones that extend far past the creature.
    /// Per-charm aura density: crystals tolerate more, blossoms breathe
    /// with fewer; everything else takes the default 13.
    private static let auraCount: [String: Int] = [
        "charm_magic_crystal_02": 16,
        "charm_nature_flower_03": 11,
        // 2026-09-26: the Star cluster read too faintly. Raised to 13 -> 16
        // -> 22, which is why the spec list above gained six more scatter
        // positions. Density is the per-charm knob; the GLOBAL particle
        // size (the 0.052 factor above) is the approved "TINY particles"
        // direction and is deliberately untouched.
        "charm_magic_star_01": 22,
    ]

    /// Floating placement master switch — PAUSED for launch (held for a
    /// later personality-trait system). Rendering only; the data model
    /// stays alive underneath.
    static let floatingPlacementActive = false

    /// Floating-charm motion personality (presentation-only): the book
    /// must stay readable (tiny tilt), the coin may visibly spin, the
    /// key gently rocks. Unlisted charms get the default gentle tilt.
    private static let floatMotion: [String: (tilt: CGFloat, spin: Bool)] = [
        "charm_object_book_01": (tilt: 0.05, spin: false),
        "charm_object_key_01": (tilt: 0.14, spin: false),
        "charm_magic_star_coin_01": (tilt: 0, spin: true),
    ]

    /// Ease-in-out wrapper for the ambient charm motion.
    private func ease(_ action: SKAction) -> SKAction {
        action.timingMode = .easeInEaseOut
        return action
    }

    /// Celebration-hop excursion cap in NODE units, set by the scene on
    /// height-constrained stages from real headroom (default: no cap).
    /// The resting size always has priority over the hop distance.
    var celebrationLiftCap: CGFloat = .greatestFiniteMagnitude

    /// Rise from the FOOT LINE to the highest crown pixel (body plus the
    /// worn tuft/hair layer), in unscaled node units, for stage-fit
    /// sizing: unlike the static collision footprint this includes
    /// however far the current hair style overshoots it, so a compact
    /// stage can size the creature by what will actually be drawn.
    /// Never less than the physical footprint; placeholder skins have
    /// nothing above it to add.
    func crownRiseAboveFeet() -> CGFloat {
        let physical = AssetLoader.collisionHalfHeightUp
            + AssetLoader.collisionHalfHeightDown
        guard usesBlenderSkin, let body = blenderLayers["body"]
        else { return physical }
        var f = body.frame
        for key in ["tuft", blenderHairStyle] {
            if let layer = blenderLayers[key] { f = f.union(layer.frame) }
        }
        return max(physical,
                   f.maxY + AssetLoader.collisionHalfHeightDown)
    }

    func hitRegion(_ scenePoint: CGPoint) -> Region? {
        guard let scene else { return nil }
        guard usesBlenderSkin else { return rectRegion(scenePoint) }
        let pad: CGFloat = 10
        func hits(_ node: SKSpriteNode?) -> Bool {
            guard let node, node.texture != nil, let parent = node.parent
            else { return false }
            let p = parent.convert(scenePoint, from: scene)
            return node.frame.insetBy(dx: -pad, dy: -pad).contains(p)
        }
        if hits(armL) { return .armLeft }
        if hits(armR) { return .armRight }
        if hits(legL) { return .footLeft }
        if hits(legR) { return .footRight }
        if let body = blenderLayers["body"], let parent = body.parent {
            let p = parent.convert(scenePoint, from: scene)
            var f = body.frame
            if let tuft = blenderLayers["tuft"] { f = f.union(tuft.frame) }
            if f.insetBy(dx: -4, dy: -4).contains(p) {
                // Head = the crown band above the face (top ~30% of the body).
                return p.y >= f.minY + f.height * 0.70 ? .head : .belly
            }
        }
        return nil
    }

    /// The placeholder path keeps the old footprint-fraction rectangle (its
    /// art is one undivided blob, so sprite bounds have nothing to add).
    private func rectRegion(_ p: CGPoint) -> Region? {
        let s = abs(xScale)
        let halfW = AssetLoader.collisionHalfWidth * s
        let up = AssetLoader.collisionHalfHeightUp * s
        let down = AssetLoader.collisionHalfHeightDown * s
        guard p.x >= position.x - halfW, p.x <= position.x + halfW,
              p.y >= position.y - down, p.y <= position.y + up else { return nil }
        let ry = p.y - position.y
        if ry > up * 0.32 { return .head }
        if ry < -down * 0.40 { return p.x < position.x ? .footLeft : .footRight }
        return .belly
    }

    /// DEBUG: every region rectangle in SCENE coordinates, for the alignment
    /// audit overlays (`AURIE_REGION_AUDIT=1`).
    func debugRegionFrames() -> [(String, CGRect)] {
        guard let scene else { return [] }
        var out: [(String, CGRect)] = []
        func rect(_ name: String, _ node: SKSpriteNode?) {
            guard let node, let parent = node.parent else { return }
            let f = node.frame
            let bl = scene.convert(CGPoint(x: f.minX, y: f.minY), from: parent)
            let tr = scene.convert(CGPoint(x: f.maxX, y: f.maxY), from: parent)
            out.append((name, CGRect(x: bl.x, y: bl.y,
                                     width: tr.x - bl.x, height: tr.y - bl.y)))
        }
        rect("armL", armL); rect("armR", armR)
        rect("legL", legL); rect("legR", legR)
        rect("body", blenderLayers["body"])
        return out
    }

    /// Idle: one arm drifts a hair and eases back. Rare and understated — the
    /// whole point is that the creature is never quite still, not that it
    /// fidgets. Skipped under Reduce Motion.
    func armMicroMotion() {
        guard armRotationSafe, !reduceMotion,
              let joint = (Bool.random() ? armJointR : armJointL) else { return }
        let dir: CGFloat = (joint === armJointR) ? -1 : 1   // small raise/drift
        let out = SKAction.rotate(toAngle: dir * .random(in: 0.05...0.09),
                                  duration: 0.55)
        let back = SKAction.rotate(toAngle: 0, duration: 0.8)
        out.timingMode = .easeInEaseOut
        back.timingMode = .easeInEaseOut
        joint.run(.sequence([out, back]), withKey: "armGesture")
    }

    /// A little wave: raise one arm, wiggle, lower. `big` false is the tiny
    /// arm flick a head-tap answers with. `side` picks the arm (>= 0 right),
    /// so tapping an arm waves THAT arm; falls back to whichever is jointed.
    func littleWave(big: Bool = true, side: CGFloat = 1) {
        let wanted = side >= 0 ? armJointR : armJointL
        guard armRotationSafe, let joint = (wanted ?? armJointR ?? armJointL) else {
            return                                     // no wave until attached
        }
        // The arm rests BEHIND the body (so the shoulder root is concealed and
        // no gap opens). A raise about the shoulder alone would swing the hand
        // out to the side and then straight INTO the body silhouette, where it
        // vanishes behind the body — which is why the old small lift only
        // waved at the side. So for the wave the arm is brought IN FRONT of the
        // body (below the face) and rotated up until the hand is beside the
        // head, then eased down and tucked back behind at rest.
        let dir: CGFloat = (joint === armJointR) ? 1 : -1
        // ~1.45 rad lifts the hand UP beside the body at cheek height. Higher
        // (1.65+) pushed the hand in toward the head where the body silhouette
        // starts to swallow it (the arm draws BEHIND the body); this keeps the
        // whole hand clearly outside the outline through the entire wave. The
        // arm keeps its resting z, so it never overlaps the body. Smaller
        // flick / Reduce Motion stop lower. Signed by the arm's side.
        let lift = (reduceMotion ? 1.2 : (big ? 1.45 : 1.1)) * dir
        let raise = SKAction.rotate(toAngle: lift, duration: 0.22)
        raise.timingMode = .easeOut
        // Wiggle bobs the hand DOWN from the peak only (never past `lift`), so
        // no swing rotates it in toward the head.
        let wiggle = SKAction.sequence([
            .rotate(toAngle: lift - 0.14 * dir, duration: 0.13),
            .rotate(toAngle: lift - 0.03 * dir, duration: 0.13),
            .rotate(toAngle: lift - 0.11 * dir, duration: 0.12),
        ])
        let lower = SKAction.rotate(toAngle: 0, duration: 0.26)
        lower.timingMode = .easeInEaseOut
        let seq: [SKAction] = reduceMotion ? [raise, lower]
                                           : [raise, wiggle, lower]
        joint.run(.sequence(seq), withKey: "armGesture")
    }

    /// A small inward hug of both arms — the body language for shy.
    private func armHug() {
        guard armRotationSafe else { return }
        if let a = armJointR {
            a.run(.sequence([.rotate(toAngle: 0.16, duration: 0.22),
                             .rotate(toAngle: 0, duration: 0.4)]),
                  withKey: "armGesture")
        }
        if let b = armJointL {
            b.run(.sequence([.rotate(toAngle: -0.16, duration: 0.22),
                             .rotate(toAngle: 0, duration: 0.4)]),
                  withKey: "armGesture")
        }
    }

    /// A clear little kick of one foot: the tapped foot lifts and swings
    /// OUTWARD far enough to read at Home size, holds a beat, and eases back
    /// to its exact captured rest. A slight opposite body tilt sells the
    /// weight shift while the body stays grounded. `side` >= 0 is the right
    /// foot.
    func kickFoot(_ side: CGFloat) {
        let leg = side >= 0 ? legR : legL
        guard let leg else {
            runSquash([.scaleX(to: 1.04, y: 0.97, duration: 0.09),
                       .scaleX(to: 1.0, y: 1.0, duration: 0.14)])
            return
        }
        let dir: CGFloat = side >= 0 ? 1 : -1
        let mag: CGFloat = reduceMotion ? 0.16 : 0.36
        let liftX: CGFloat = reduceMotion ? 3 : 7
        let liftY: CGFloat = reduceMotion ? 7 : 15
        if let joint = legJoint(side: side) {
            // Jointed rig: the swing pivots at the hip (root stays buried
            // behind the body), the little lift stays on the sprite.
            let swing = SKAction.sequence([
                .rotate(toAngle: dir * mag, duration: 0.10),
                .wait(forDuration: 0.10),
                .rotate(toAngle: 0, duration: 0.20)])
            swing.timingMode = .easeOut
            joint.run(swing, withKey: "legSwing")
            let hop = SKAction.sequence([
                .moveBy(x: dir * liftX, y: liftY, duration: 0.10),
                .wait(forDuration: 0.10),
                .move(to: restPos(leg), duration: 0.20)])
            hop.timingMode = .easeOut
            leg.run(hop, withKey: "legKick")
        } else {
            let kick = SKAction.sequence([
                .group([.rotate(toAngle: restRot(leg) + dir * mag, duration: 0.10),
                        .moveBy(x: dir * liftX, y: liftY, duration: 0.10)]),
                .wait(forDuration: 0.10),          // readable beat at the top
                .group([.rotate(toAngle: restRot(leg), duration: 0.20),
                        .move(to: restPos(leg), duration: 0.20)]),
            ])
            kick.timingMode = .easeOut
            leg.run(kick, withKey: "legKick")
        }
        // Tiny counter-lean away from the kicking foot; absolute angles, so it
        // always lands back at zero.
        if root.action(forKey: "motionTilt") == nil {
            let lean = SKAction.rotate(toAngle: -dir * 0.035, duration: 0.12)
            lean.timingMode = .easeOut
            let back = SKAction.rotate(toAngle: 0, duration: 0.22)
            back.timingMode = .easeInEaseOut
            root.run(.sequence([lean, .wait(forDuration: 0.08), back]),
                     withKey: "motionTilt")
        }
        runSquash([.scaleX(to: 1.03, y: 0.98, duration: 0.08),
                   .scaleX(to: 1.0, y: 1.0, duration: 0.14)])
    }

    /// Belly answer: a quick side-to-side rock on the tilt owner.
    func rockSideToSide() {
        guard root.action(forKey: "motionTilt") == nil else { return }
        let amp: CGFloat = reduceMotion ? 0.03 : 0.06
        root.run(.sequence([
            .rotate(toAngle: amp, duration: 0.12),
            .rotate(toAngle: -amp, duration: 0.16),
            .rotate(toAngle: amp * 0.6, duration: 0.12),
            .rotate(toAngle: 0, duration: 0.12),
        ]), withKey: "motionTilt")
    }

    /// Autonomous: peer down at one foot and lift it a touch, then restore.
    func inspectFoot() {
        let side: CGFloat = Bool.random() ? 1 : -1
        guard root.action(forKey: "motionTilt") == nil else { return }
        let lean = SKAction.rotate(toAngle: side * 0.05, duration: 0.4)
        lean.timingMode = .easeOut
        root.run(.sequence([lean, .wait(forDuration: 1.0),
                            .rotate(toAngle: 0, duration: 0.4)]), withKey: "motionTilt")
        if let leg = (side >= 0 ? legR : legL) {
            leg.run(.sequence([.moveBy(x: 0, y: 8, duration: 0.4),
                               .wait(forDuration: 0.8),
                               .move(to: restPos(leg), duration: 0.4)]),
                    withKey: "legKick")
        }
        // Pupils peer down at the lifted foot (sparkles only on Blender).
        sparkleGlance(dx: side * 3, dy: -Self.eyeTrackY, hold: 1.0)
    }

    /// Autonomous: a small bashful wiggle + arm hug.
    func shyWiggle() {
        guard root.action(forKey: "motionTilt") == nil else { return }
        root.run(.sequence([
            .rotate(toAngle: 0.04, duration: 0.18),
            .rotate(toAngle: -0.035, duration: 0.20),
            .rotate(toAngle: 0.02, duration: 0.16),
            .rotate(toAngle: 0, duration: 0.20),
        ]), withKey: "motionTilt")
        runSquash([.scaleX(to: 1.03, y: 0.97, duration: 0.20),
                   .scaleX(to: 1.0, y: 1.0, duration: 0.30)])
        armHug()
    }

    /// Attend to a nearby finger: the EYES follow it, nothing else. The body
    /// never leans — moving the whole creature read as "being dragged". The
    /// pupils are baked into the eye artwork, so "eyes follow" is a small
    /// slide of the eye LAYER toward the finger, offset from its captured
    /// neutral spot and re-issued as the finger moves. Returns whether it
    /// applied (for input tracing).
    @discardableResult
    func glanceToward(_ scenePoint: CGPoint) -> Bool {
        guard Self.eyesFollowInput else { return false }
        guard currentReaction == nil, !isCarried else { return false }
        // Nothing to track when the expression's sparkles are hidden (arc/
        // shut eyes) — the dark eye deliberately does not move.
        if usesBlenderSkin, catchNode.isHidden || catchNode.texture == nil {
            return false
        }
        let dx = scenePoint.x - position.x
        let dy = scenePoint.y - position.y
        let mag = max(hypot(dx, dy), 1)
        // `dx` is measured in SCENE space, but the offset is applied to a node
        // under `root`, whose xScale carries the facing sign — so when the
        // creature faces left (facing = -1) the subtree is mirrored and a raw
        // +x offset would slide the sparkle the WRONG way on screen. Multiply
        // by `facing` to cancel the mirror: the sparkle always tracks toward the
        // finger's real screen-side, whichever way the creature is turned.
        eyeLookOffset = CGPoint(
            x: facing * max(-Self.eyeTrackX, min(Self.eyeTrackX, dx / mag * Self.eyeTrackX)),
            y: max(-Self.eyeTrackY, min(Self.eyeTrackY, dy / mag * Self.eyeTrackY)))
        // Blender: move only the sparkle child; placeholder: its whole eye.
        let node = usesBlenderSkin ? catchNode : eyesNode
        let rest = usesBlenderSkin ? catchRest : CGPoint(x: 0, y: 30)
        let look = SKAction.move(to: CGPoint(x: rest.x + eyeLookOffset.x,
                                             y: rest.y + eyeLookOffset.y),
                                 duration: 0.16)
        look.timingMode = .easeOut
        node.run(look, withKey: "look")
        return true
    }

    /// Ease the sparkles back to centre (finger lifted / left the area). Also
    /// clears any leftover body lean from an earlier build so nothing drifts.
    func endGlance() {
        if abs(root.position.x) > 0.01 || root.action(forKey: "glance") != nil {
            let r = SKAction.group([.moveTo(x: 0, duration: 0.3),
                                    .rotate(toAngle: 0, duration: 0.3)])
            r.timingMode = .easeInEaseOut
            root.run(r, withKey: "glance")
        }
        guard eyeLookOffset != .zero else { return }
        eyeLookOffset = .zero
        let node = usesBlenderSkin ? catchNode : eyesNode
        let rest = usesBlenderSkin ? catchRest : CGPoint(x: 0, y: 30)
        let back = SKAction.move(to: rest, duration: 0.22)
        back.timingMode = .easeInEaseOut
        node.run(back, withKey: "look")
    }

    /// A user touch owns the highest priority: show a face NOW, cancelling any
    /// reaction/autonomous face in flight, and restore the saved face after
    /// `duration` unless something newer took over.
    func flashFace(_ faceId: String, for duration: TimeInterval) {
        reactionGeneration &+= 1
        let token = reactionGeneration
        currentReaction = nil
        removeAction(forKey: "autonomousFace")
        applyFace(faceId)
        run(.sequence([.wait(forDuration: duration), .run { [weak self] in
            guard let self, self.reactionGeneration == token,
                  self.currentReaction == nil else { return }
            self.applyFace(self.baseExpression.rawValue)
        }]), withKey: "reaction")
    }

    /// A face for an autonomous behaviour — LOWER priority: it never overrides
    /// a reaction and yields immediately if one starts.
    func autonomousExpression(_ faceId: String, for duration: TimeInterval) {
        guard currentReaction == nil else { return }
        reactionGeneration &+= 1
        let token = reactionGeneration
        applyFace(faceId)
        run(.sequence([.wait(forDuration: duration), .run { [weak self] in
            guard let self, self.reactionGeneration == token,
                  self.currentReaction == nil else { return }
            self.applyFace(self.baseExpression.rawValue)
        }]), withKey: "autonomousFace")
    }

    /// Stop any autonomous behaviour cleanly and ease EVERY touched transform
    /// home, so a user touch never lands on a half-raised arm, a mid-yawn, a
    /// slumped body or a wandering sparkle. All heal targets are absolute rest
    /// values, so interrupting can never strand a transform. Reactions (which
    /// the user is usually triggering) are intentionally left alone.
    func interruptIdleBehavior() {
        removeAction(forKey: "autoStage")        // pending staged beats (wave…)
        removeAction(forKey: "autonomousFace")

        // Pupils/sparkles home (autonomous glances run under "look").
        eyesNode.removeAction(forKey: "look")
        eyesNode.removeAction(forKey: "eyesSoft")
        eyesNode.yScale = 1                       // heal a half-softened lid
        if !usesBlenderSkin { eyesNode.position = CGPoint(x: 0, y: 30) }
        if usesBlenderSkin, !catchNode.isHidden, catchNode.texture != nil {
            catchNode.removeAction(forKey: "look")
            let home = SKAction.move(to: catchRest, duration: 0.15)
            home.timingMode = .easeOut
            catchNode.run(home, withKey: "look")
        }
        endGlance()          // a direct touch supersedes a finger-notice lean

        // Face rig: a mid-yawn mouth eases back to its natural scale.
        mouthNode.removeAction(forKey: "yawn")
        if abs(mouthNode.xScale - 1) > 0.01 {
            let m = SKAction.scale(to: 1.0, duration: 0.14)
            m.timingMode = .easeOut
            mouthNode.run(m, withKey: "yawn")
        }

        // Body: slump and lean home (absolute targets).
        root.removeAction(forKey: "sit")
        if abs(root.position.y) > 0.01 {
            let up = SKAction.moveTo(y: 0, duration: 0.15)
            up.timingMode = .easeOut
            root.run(up, withKey: "sit")
        }
        root.removeAction(forKey: "motionTilt")
        if abs(root.zRotation) > 0.005 {
            let level = SKAction.rotate(toAngle: 0, duration: 0.15)
            level.timingMode = .easeOut
            root.run(level, withKey: "motionTilt")
        }

        for joint in [armJointL, armJointR].compactMap({ $0 }) {
            if joint.action(forKey: "armGesture") != nil {
                let home = SKAction.rotate(toAngle: 0, duration: 0.16)
                home.timingMode = .easeOut
                joint.run(home, withKey: "armGesture")
            }
        }
        for limb in [legL, legR].compactMap({ $0 }) {
            if limb.action(forKey: "legKick") != nil {
                let home = SKAction.group([.rotate(toAngle: restRot(limb), duration: 0.16),
                                           .move(to: restPos(limb), duration: 0.16)])
                home.timingMode = .easeOut
                limb.run(home, withKey: "legKick")
            }
        }
        for joint in legJoints.values where joint.action(forKey: "legSwing") != nil {
            let home = SKAction.rotate(toAngle: 0, duration: 0.16)
            home.timingMode = .easeOut
            joint.run(home, withKey: "legSwing")
        }
        stopDancing()
    }

    // MARK: - Dance library (radio / music)

    /// ONE reusable library for every body. Each move is assembled from the
    /// SAME rig the interaction gestures use — the two shoulder JOINTS, the
    /// leg sprites, the root's tilt/lift, and the squash node — so there is no
    /// per-body implementation and no Blender animation sequence anywhere.
    ///
    /// BEAT-LOCKED: every move is handed the music's beat interval and lays
    /// its keyframes on it, so claps, jumps, floss reversals, disco points and
    /// foot taps all land with the loop instead of drifting on their own clock.
    ///
    /// EXACT REST: every keyframe is an ABSOLUTE target (`rotate(toAngle:)`,
    /// `move(to:)`, `scale(to:)`) referred to the captured `limbRest`, and the
    /// moves reuse the interaction action keys ("armGesture", "legKick",
    /// "motionTilt", "sit", "motionSquash"). A dance therefore cannot
    /// accumulate drift, and `interruptIdleBehavior()` heals a half-finished
    /// dance exactly the way it heals a half-finished wave.
    ///
    /// GROUNDING: dances never touch `position` (the perspective field
    /// coordinate). Jumps lift `root.position.y` and return it to 0, so the
    /// creature's footing in the environment is untouched.
    enum DanceMove: String, CaseIterable {
        case breakdance, disco, floss, jumpShake, split, sprinkler
        /// Stone only — the "I am definitely not dancing" foot tap.
        case footTap
    }

    /// True while a dance is running (the scene gates idle beats on this).
    var isDancing: Bool { action(forKey: "dance") != nil }

    /// Dance for `measures` bars of 4 beats. Returns the wall-clock duration
    /// so the director can schedule the next beat without guessing.
    @discardableResult
    func dance(_ move: DanceMove, beat: TimeInterval,
               measures: Int = 2) -> TimeInterval {
        guard !isCarried else { return 0 }
        stopDancing()
        let b = max(0.18, beat)
        let bars = max(1, measures)
        let steps: [SKAction]
        switch move {
        case .breakdance: steps = breakdanceSteps(b, bars)
        case .disco:      steps = discoSteps(b, bars)
        case .floss:      steps = flossSteps(b, bars)
        case .jumpShake:  steps = jumpShakeSteps(b, bars)
        case .split:      steps = splitSteps(b, bars)
        case .sprinkler:  steps = sprinklerSteps(b, bars)
        case .footTap:    steps = footTapSteps(b, bars)
        }
        let total = steps.reduce(0) { $0 + $1.duration }
        run(.sequence(steps + [.run { [weak self] in self?.settleFromDance() }]),
            withKey: "dance")
        return total
    }

    /// Stop mid-dance and ease every touched transform back to EXACT rest.
    func stopDancing() {
        guard action(forKey: "dance") != nil || danceTouched else { return }
        removeAction(forKey: "dance")
        settleFromDance()
    }

    /// Set the moment any dance keyframe runs, so a stop that lands between
    /// dances still heals the rig.
    private static var danceTouchedKey: UInt8 = 0
    private var danceTouched: Bool {
        get { (objc_getAssociatedObject(self, &Self.danceTouchedKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &Self.danceTouchedKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    /// Absolute return to the captured rest pose — the single exit path every
    /// dance uses, whether it finished or was interrupted.
    private func settleFromDance() {
        danceTouched = false
        let d: TimeInterval = 0.18
        root.removeAction(forKey: "idleSway")     // never leave an idle lean behind
        func ease(_ a: SKAction) -> SKAction { a.timingMode = .easeOut; return a }
        for (side, joint) in armJoints {
            let home = armJointRest[side] ?? joint.position
            joint.zPosition = armJointHomeZ[side] ?? joint.zPosition
            joint.run(.group([ease(.rotate(toAngle: 0, duration: d)),
                              ease(.move(to: home, duration: d)),
                              ease(.scale(to: 1.0, duration: d))]),
                      withKey: "armGesture")
        }
        for limb in [legL, legR].compactMap({ $0 }) {
            limb.run(.group([ease(.rotate(toAngle: restRot(limb), duration: d)),
                             ease(.move(to: restPos(limb), duration: d)),
                             ease(.scaleX(to: 1, y: 1, duration: d))]),
                     withKey: "legKick")
        }
        for joint in legJoints.values {
            joint.run(ease(.rotate(toAngle: 0, duration: d)),
                      withKey: "legSwing")
        }
        root.run(ease(.rotate(toAngle: 0, duration: d)), withKey: "motionTilt")
        root.run(.group([ease(.moveTo(y: 0, duration: d)),
                         ease(.moveTo(x: 0, duration: d))]), withKey: "sit")
        squashNode.run(ease(.scaleX(to: 1, y: 1, duration: d)), withKey: "motionSquash")
    }

    /// Mark the rig as posed, so an interruption always runs the heal.
    private func mark() -> SKAction { .run { [weak self] in self?.danceTouched = true } }

    // MARK: Move builders — all keyframes are absolute, all timing is beats

    /// Rotating a shoulder joint: right arm raises POSITIVE, left NEGATIVE,
    /// and 1.45 rad is the approved apex that keeps the shoulder attached.
    private func armPose(_ side: CGFloat, _ angle: CGFloat,
                         _ dur: TimeInterval) -> SKAction {
        guard let joint = armJoint(side: side) else { return .wait(forDuration: dur) }
        let a = SKAction.rotate(toAngle: max(-1.45, min(1.45, angle)), duration: dur)
        a.timingMode = .easeInEaseOut
        return .run { joint.run(a, withKey: "armGesture") }
    }

    private func legPose(_ side: CGFloat, angle: CGFloat, dx: CGFloat, dy: CGFloat,
                         _ dur: TimeInterval) -> SKAction {
        let leg = side >= 0 ? legR : legL
        guard let leg else { return .wait(forDuration: dur) }
        let rest = restPos(leg)
        let move = SKAction.move(to: CGPoint(x: rest.x + dx, y: rest.y + dy),
                                 duration: dur)
        move.timingMode = .easeInEaseOut
        // Jointed rig: the ANGLE swings the whole leg about its buried hip
        // root (same clamp discipline as the shoulder), translation stays on
        // the sprite. Legacy cropped legs keep the old sprite-local motion.
        if let joint = legJoint(side: side) {
            let spin = SKAction.rotate(toAngle: max(-1.45, min(1.45, angle)),
                                       duration: dur)
            spin.timingMode = .easeInEaseOut
            return .run { joint.run(spin, withKey: "legSwing")
                          leg.run(move, withKey: "legKick") }
        }
        let group = SKAction.group([
            .rotate(toAngle: restRot(leg) + angle, duration: dur), move])
        group.timingMode = .easeInEaseOut
        return .run { leg.run(group, withKey: "legKick") }
    }

    private func tilt(_ angle: CGFloat, _ dur: TimeInterval) -> SKAction {
        let a = SKAction.rotate(toAngle: angle, duration: dur)
        a.timingMode = .easeInEaseOut
        return .run { [weak self] in self?.root.run(a, withKey: "motionTilt") }
    }

    private func lift(_ y: CGFloat, x: CGFloat = 0, _ dur: TimeInterval,
                      ease: SKActionTimingMode = .easeInEaseOut) -> SKAction {
        let a = SKAction.group([.moveTo(y: y, duration: dur),
                                .moveTo(x: x, duration: dur)])
        a.timingMode = ease
        return .run { [weak self] in self?.root.run(a, withKey: "sit") }
    }

    private func squash(_ x: CGFloat, _ y: CGFloat, _ dur: TimeInterval) -> SKAction {
        let a = SKAction.scaleX(to: x, y: y, duration: dur)
        a.timingMode = .easeInEaseOut
        return .run { [weak self] in self?.squashNode.run(a, withKey: "motionSquash") }
    }

    private func faceFor(_ ids: [String], _ hold: TimeInterval) -> SKAction {
        let id = ids.randomElement() ?? BaseExpression.happy.rawValue
        return .run { [weak self] in self?.autonomousExpression(id, for: hold) }
    }

    /// 1. BREAKDANCE — prep bounce, drop to one side with a planted arm, legs
    /// kick out, a fast spin of the whole body (so every limb stays attached),
    /// a freeze, then pop upright.
    private func breakdanceSteps(_ b: TimeInterval, _ bars: Int) -> [SKAction] {
        let side: CGFloat = Bool.random() ? 1 : -1
        var s: [SKAction] = [mark(),
            faceFor(["excited", "mischievous", "delighted"], Double(bars) * 4 * b)]
        for _ in 0 ..< bars {
            // Beat 1 — prep bounce.
            s += [squash(1.08, 0.90, b * 0.3), .wait(forDuration: b * 0.3),
                  squash(1.0, 1.0, b * 0.2), .wait(forDuration: b * 0.5)]
            // Beat 2 — drop to the side, plant one arm down, legs kick out.
            s += [tilt(side * 0.30, b * 0.5),
                  lift(-14, x: side * 6, b * 0.5),
                  armPose(side, side * -0.75, b * 0.5),     // plant toward the floor
                  armPose(-side, -side * 1.0, b * 0.5),     // other arm up for balance
                  legPose(side, angle: side * 0.5, dx: side * 10, dy: -2, b * 0.5),
                  legPose(-side, angle: -side * 0.35, dx: -side * 8, dy: 4, b * 0.5),
                  .wait(forDuration: b)]
            // Beat 3 — the spin: the WHOLE body turns, so nothing detaches.
            let spin = SKAction.rotate(byAngle: side * .pi * 2, duration: b)
            spin.timingMode = .easeInEaseOut
            s += [.run { [weak self] in self?.root.run(spin, withKey: "motionTilt") },
                  .wait(forDuration: b)]
            // Beat 4 — freeze, then pop upright.
            s += [tilt(side * 0.22, b * 0.2), .wait(forDuration: b * 0.55),
                  tilt(0, b * 0.25), lift(0, b * 0.25),
                  armPose(side, 0, b * 0.25), armPose(-side, 0, b * 0.25),
                  legPose(side, angle: 0, dx: 0, dy: 0, b * 0.25),
                  legPose(-side, angle: 0, dx: 0, dy: 0, b * 0.25),
                  squash(1.05, 0.95, b * 0.12), .wait(forDuration: b * 0.25),
                  squash(1.0, 1.0, b * 0.2), .wait(forDuration: b * 0.2)]
        }
        return s
    }

    /// 2. DISCO — one arm points high diagonally, the other drops, the body
    /// leans and takes a small step; sides alternate on the beat.
    private func discoSteps(_ b: TimeInterval, _ bars: Int) -> [SKAction] {
        var s: [SKAction] = [mark(),
            faceFor(["happy", "delighted"], Double(bars) * 4 * b)]
        for bar in 0 ..< bars {
            for beatIdx in 0 ..< 4 {
                let side: CGFloat = (bar + beatIdx) % 2 == 0 ? 1 : -1
                s += [armPose(side, side * 1.30, b * 0.45),      // point up-out
                      armPose(-side, -side * 0.30, b * 0.45),    // opposite arm low
                      tilt(-side * 0.10, b * 0.45),
                      lift(0, x: side * 7, b * 0.45),
                      squash(0.98, 1.02, b * 0.45),
                      .wait(forDuration: b * 0.5),
                      squash(1.0, 1.0, b * 0.3),
                      .wait(forDuration: b * 0.5)]
            }
        }
        return s
    }

    /// 3. FLOSS — both arms swing together to one side while the body rocks
    /// the OPPOSITE way, then reverse. The arm that crosses the body passes in
    /// front of the belly, which is what makes the move readable.
    private func flossSteps(_ b: TimeInterval, _ bars: Int) -> [SKAction] {
        var s: [SKAction] = [mark(),
            faceFor(["happy", "mischievous"], Double(bars) * 4 * b)]
        for bar in 0 ..< bars {
            for beatIdx in 0 ..< 4 {
                let side: CGFloat = (bar * 4 + beatIdx) % 2 == 0 ? 1 : -1
                // A floss reads from the arms CROSSING THE TORSO in opposite
                // senses: one sweeps across the FRONT of the body while the
                // other passes BEHIND it and emerges on the far side. Both
                // hands therefore travel over the body rather than one waving
                // out in clear air, and the pair trades front/back each beat.
                // BOTH arms travel the same way — left together, then right
                // together. Whichever ends up crossing the torso is drawn in
                // FRONT of the body while its partner stays BEHIND it, and the
                // two trade depth each time the swing reverses.
                s += [armDepth(frontSide: -side),
                      armPose(1, side * 0.88, b * 0.4),
                      armPose(-1, side * 0.88, b * 0.4),
                      tilt(side * 0.13, b * 0.4),          // hips rock opposite
                      lift(0, x: -side * 9, b * 0.4),
                      .wait(forDuration: b * 0.5),
                      squash(1.03, 0.98, b * 0.2),
                      .wait(forDuration: b * 0.2),
                      squash(1.0, 1.0, b * 0.2),
                      .wait(forDuration: b * 0.3)]
            }
        }
        s.append(armDepth(frontSide: nil))
        return s
    }

    /// 4. JUMP + SHAKE — the happiest one. The jump lifts the ROOT (never the
    /// field position) and both arms shake up and down on the beat. The arms
    /// stay on their shoulders behind the body throughout: no reach across the
    /// front, no stretch, nothing to restore but the rotation.
    private func jumpShakeSteps(_ b: TimeInterval, _ bars: Int) -> [SKAction] {
        var s: [SKAction] = [mark(),
            faceFor(["excited", "delighted"], Double(bars) * 4 * b)]
        for _ in 0 ..< bars {
            for _ in 0 ..< 2 {
                s += [squash(1.10, 0.88, b * 0.3),
                      armPose(1, 0.20, b * 0.3), armPose(-1, -0.20, b * 0.3),
                      .wait(forDuration: b * 0.35)]
                s += [lift(34, b * 0.35, ease: .easeOut),
                      squash(0.94, 1.10, b * 0.25),
                      armPose(1, 1.30, b * 0.18), armPose(-1, -1.30, b * 0.18),
                      .wait(forDuration: b * 0.3)]
                for _ in 0 ..< 2 {              // quick shakes at the top
                    s += [armPose(1, 0.70, b * 0.12), armPose(-1, -0.70, b * 0.12),
                          .wait(forDuration: b * 0.14),
                          armPose(1, 1.30, b * 0.12), armPose(-1, -1.30, b * 0.12),
                          .wait(forDuration: b * 0.14)]
                }
                s += [lift(0, b * 0.3, ease: .easeIn),
                      squash(1.08, 0.92, b * 0.2),
                      armPose(1, 0, b * 0.28), armPose(-1, 0, b * 0.28),
                      .wait(forDuration: b * 0.35),
                      squash(1.0, 1.0, b * 0.2),
                      .wait(forDuration: b * 0.5)]
            }
        }
        return s
    }

    /// z for an arm drawn in FRONT of the body (still under the face layers).
    /// The floss uses this to put one arm ahead of the torso.
    private static let armFrontZ: CGFloat = Z.pattern.rawValue + 0.4

    /// Draw the arm on `frontSide` IN FRONT of the body and the other one
    /// behind it — the depth split that makes the floss read. Passing nil puts
    /// both back to their captured home depth.
    private func armDepth(frontSide: CGFloat?) -> SKAction {
        .run { [weak self] in
            guard let self else { return }
            for (side, joint) in self.armJoints {
                let home = self.armJointHomeZ[side] ?? joint.zPosition
                guard let frontSide else { joint.zPosition = home; continue }
                let isFront = (side == "r") == (frontSide >= 0)
                joint.zPosition = isFront ? Self.armFrontZ : home
            }
        }
    }

    /// 5. SPLIT — prep bounce, legs slide strongly out, body drops into a
    /// clear split, surprise → delight, then springs back.
    private func splitSteps(_ b: TimeInterval, _ bars: Int) -> [SKAction] {
        var s: [SKAction] = [mark()]
        for _ in 0 ..< bars {
            // Prep.
            s += [faceFor(["curious", "excited"], b * 1.2),
                  squash(1.10, 0.88, b * 0.3), .wait(forDuration: b * 0.35),
                  squash(0.96, 1.06, b * 0.2), .wait(forDuration: b * 0.4)]
            // Out and down into the split. On the jointed rig the legs SWING
            // about their buried hip roots — the extension is rotation, so
            // nothing can detach at any angle, and only a small slide sells
            // the stretch. (The old cropped-sprite rig had to slide 34pt and
            // accepted the legs "parting a little"; that concession is
            // retired with the 2026-09-12 anim-safe leg export.)
            s += [legPose(1, angle: legRotationSafe ? 1.30 : 1.15,
                          dx: legRotationSafe ? 10 : 34,
                          dy: legRotationSafe ? -4 : -12, b * 0.45),
                  legPose(-1, angle: legRotationSafe ? -1.30 : -1.15,
                          dx: legRotationSafe ? -10 : -34,
                          dy: legRotationSafe ? -4 : -12, b * 0.45),
                  lift(-30, b * 0.45),
                  squash(1.16, 0.82, b * 0.45),
                  armPose(1, 0.75, b * 0.45), armPose(-1, -0.75, b * 0.45),
                  .run { [weak self] in
                      self?.autonomousExpression(BaseExpression.surprised.rawValue,
                                                 for: b * 1.1) },
                  .wait(forDuration: b * 1.1)]
            // Hold the pose, then look pleased with itself.
            s += [faceFor(["delighted", "excited"], b * 1.6),
                  .wait(forDuration: b * 0.7)]
            // Spring back up.
            s += [legPose(1, angle: 0, dx: 0, dy: 0, b * 0.4),
                  legPose(-1, angle: 0, dx: 0, dy: 0, b * 0.4),
                  lift(0, b * 0.4), squash(0.94, 1.08, b * 0.3),
                  armPose(1, 0, b * 0.4), armPose(-1, 0, b * 0.4),
                  .wait(forDuration: b * 0.5),
                  squash(1.0, 1.0, b * 0.25), .wait(forDuration: b * 0.5)]
        }
        return s
    }

    /// 6. SPRINKLER — one arm bent up by the head, the other held out straight
    /// while the body rocks round in steps, carrying the extended arm with it.
    private func sprinklerSteps(_ b: TimeInterval, _ bars: Int) -> [SKAction] {
        let out: CGFloat = Bool.random() ? 1 : -1        // the extended side
        var s: [SKAction] = [mark(),
            faceFor(["happy", "mischievous"], Double(bars) * 4 * b)]
        // Set the pose: bent arm by the head, straight arm out level.
        s += [armPose(-out, -out * 1.32, b * 0.5),        // bent, up by the head
              armPose(out, out * 0.88, b * 0.5),          // extended, level
              .wait(forDuration: b * 0.6)]
        for _ in 0 ..< bars {
            // Sweep: the body turns through four incremental steps, so the
            // straight arm travels round with the shoulder still attached.
            for step in 0 ..< 4 {
                let t = CGFloat(step) / 3.0                // 0 → 1
                s += [tilt(out * (-0.16 + 0.32 * t), b * 0.32),
                      armPose(out, out * (0.88 - 0.30 * t), b * 0.32),
                      lift(0, x: out * (-6 + 12 * t), b * 0.32),
                      .wait(forDuration: b * 0.9)]
            }
            // Reset back to the start of the sweep.
            s += [tilt(out * -0.16, b * 0.35),
                  armPose(out, out * 0.88, b * 0.35),
                  lift(0, x: out * -6, b * 0.35),
                  .wait(forDuration: b * 0.4)]
        }
        s += [armPose(out, 0, b * 0.4), armPose(-out, 0, b * 0.4),
              tilt(0, b * 0.4), lift(0, b * 0.4), .wait(forDuration: b * 0.4)]
        return s
    }

    /// 7. RELUCTANT FOOT TAP (Stone) — one foot keeps the beat for a while.
    /// Everything else stays still: this has to read as an Aurie trying NOT to
    /// dance, so there is no body bounce, no arms, no tilt — just the one foot
    /// lifting and coming down ON the beat, with the occasional missed beat so
    /// it never looks committed.
    private func footTapSteps(_ b: TimeInterval, _ bars: Int) -> [SKAction] {
        let side: CGFloat = Bool.random() ? 1 : -1
        var s: [SKAction] = [mark()]
        for bar in 0 ..< bars {
            for beatIdx in 0 ..< 4 {
                // Skip a beat now and then — reluctant, not metronomic.
                if bar > 0, beatIdx == 3, Int.random(in: 0 ..< 100) < 35 {
                    s.append(.wait(forDuration: b))
                    continue
                }
                s += [legPose(side, angle: side * 0.10, dx: 0, dy: 7, b * 0.20),
                      .wait(forDuration: b * 0.22),
                      legPose(side, angle: 0, dx: 0, dy: 0, b * 0.18),
                      .wait(forDuration: b * 0.78)]
            }
        }
        return s
    }
}

// MARK: - Demo scene (runs with placeholder shapes -- no art files needed)

final class AurieDemoScene: SKScene {

    private var aurie: AurieNode!

    override func didMove(to view: SKView) {
        // Soft lavender so it's obvious the scene is showing (not white).
        backgroundColor = SKColor(red: 0.93, green: 0.91, blue: 0.98, alpha: 1)

        let textures: [String: SKTexture] = [
            "aura":  circleTexture(radius: 150, color: .white),
            "limbs": circleTexture(radius: 130, color: .white),
            "body":  circleTexture(radius: 110, color: .white),
            "eyes":  circleTexture(radius: 18,  color: .black),
            "mouth": circleTexture(radius: 10,  color: .darkGray),
        ]

        aurie = AurieNode(
            textures: textures,
            baseColor: SKColor(red: 0.45, green: 0.60, blue: 0.85, alpha: 1),
            auraColor: SKColor(red: 0.71, green: 0.78, blue: 1.0,  alpha: 1)
        )
        aurie.position = CGPoint(x: frame.midX, y: frame.midY)
        addChild(aurie)
        aurie.startIdle()
    }

    // Reliable placeholder: draw a filled circle into an image, then a texture.
    private func circleTexture(radius: CGFloat, color: UIColor) -> SKTexture {
        let size = CGSize(width: radius * 2, height: radius * 2)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: image)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if aurie.contains(p) {
            aurie.reactBounce()   // tapped the creature -> bounce
        } else {
            aurie.hop(to: p)      // tapped elsewhere -> hop there
        }
    }
}
