import SpriteKit
import UIKit

/// The universal 2.5D Home environment engine.
///
/// ONE engine for every family: a `FamilyEnvironment` configuration names the
/// artwork for each slot and the engine does everything else — aspect-fill
/// with bleed, restrained parallax off the Aurie's travel, the shallow
/// closer/farther depth illusion, foreground occlusion, and normalized event
/// zones for later family events. No family-specific code paths.
///
///     EnvironmentRoot (this node, behind everything)
///     ├── sky        z -100   barely moves
///     ├── mid        z  -90   moves a little
///     ├── ground     z  -80   the playfield surface Aurie stands on
///     │   [Aurie ~0, toys 30 — the existing scene graph, NOT children here]
///     ├── fore       z  +60   moves the most, can occlude Aurie/toys
///     └── glow       z  +62   optional additive atmosphere
///
/// Layers are plugged from imagesets named `<family>_env_<slot>` (see
/// `FamilyEnvironment.registry`). A missing required slot leaves the
/// environment inactive and Home keeps its current gradient — the engine
/// never invents stand-in art. The DEBUG grey-box (AURIE_ENV_GREYBOX=1)
/// exists purely to validate the mechanics before real art lands.
final class HomeEnvironment: SKNode {

    // MARK: - Configuration model

    struct FamilyEnvironment {
        let family: AuraFamily
        /// The shared walkable-ground geometry. Deliberately NOT tunable
        /// per family: one Home layout system, backgrounds as skins.
        let playfield: Playfield = .standard
        /// Draw ONLY the base painting (+ optional glow), ignoring any
        /// mid/ground/fore imagesets that still exist in the catalog. Most
        /// flat-master families simply have no slice assets; Moss keeps its
        /// superseded slices on disk, so it states the intent explicitly.
        var flatMaster: Bool = false

        /// Imageset base names. Only sky — the base painting — is required
        /// to activate; mid/ground/fore/glow are all optional. A painting
        /// with strong internal perspective (Stone) reads best as ONE flat
        /// master: any cutout layer re-composited over a flattened painting
        /// eventually reveals its mask boundary. The logical perspective
        /// playfield is independent of these visual layers, so depth
        /// movement, scaling, and the contact shadow work identically with
        /// or without the optional slices.
        var sky: String { "\(family.rawValue)_env_sky" }
        var mid: String { "\(family.rawValue)_env_mid" }
        var ground: String { "\(family.rawValue)_env_ground" }
        var fore: String { "\(family.rawValue)_env_fore" }
        var glow: String { "\(family.rawValue)_env_glow" }

        /// The families with registered environment slots. Art may not have
        /// landed yet; `missingAssets` reports exactly what is absent.
        static let registry: [AuraFamily: FamilyEnvironment] = [
            // ONE shared playfield for every family (Playfield.standard):
            // switching families must never change Aurie's size, position,
            // movement bounds, or the play-area dimensions. Backgrounds are
            // skins fitted into the same frame; art that composes poorly
            // against the shared horizon gets REPLACED, never special-cased.
            // Moss, Tide and Starlight keep superseded slice imagesets on
            // disk from their pre-template art; flatMaster states that the
            // 2026-09 recomposed masters are single flat paintings.
            .moss: FamilyEnvironment(family: .moss, flatMaster: true),
            .ember: FamilyEnvironment(family: .ember),
            .dusk: FamilyEnvironment(family: .dusk),
            .glow: FamilyEnvironment(family: .glow),
            .stone: FamilyEnvironment(family: .stone),
            .tide: FamilyEnvironment(family: .tide, flatMaster: true),
            .starlight: FamilyEnvironment(family: .starlight, flatMaster: true),
        ]

        var missingAssets: [String] {
            [sky].filter { UIImage(named: $0) == nil }
        }
        var isComplete: Bool { missingAssets.isEmpty }
    }

    // MARK: - Tuning

    /// Parallax travel per layer at full creature excursion, in POINTS.
    /// Restrained by design: depth, not a moving wallpaper. Art must carry at
    /// least this much bleed per side (plus crop margin) so edges never show.
    enum Parallax {
        static let sky: CGFloat = 4
        static let mid: CGFloat = 9
        static let ground: CGFloat = 16
        static let fore: CGFloat = 30
        /// Fraction of the offset applied per frame (smoothing).
        static let smoothing: CGFloat = 0.10
    }

    /// The PERSPECTIVE PLAYFIELD: the walkable ground is a trapezoid that
    /// recedes toward the horizon, exactly like the approved concepts (paths,
    /// clearings and stream beds narrowing into the distance). Everything
    /// spatial derives from one normalized depth coordinate:
    ///
    ///     depth = 0.0  -> far edge of the walkable ground (horizon end)
    ///     depth = 1.0  -> near foreground edge
    ///
    ///     farLeft ______ farRight        <- narrow, high, small, light shadow
    ///           /        \
    ///          /          \
    ///     nearLeft ________ nearRight    <- wide, low, large, strong shadow
    ///
    /// All values are FRACTIONS of the scene size (centre origin), so one
    /// playfield definition serves every device; families may later override
    /// the shape to match their art (a stream corridor vs a wide meadow).
    struct Playfield {
        // THE shared Home geometry (2026-08-29 unification): every family
        // uses these values — backgrounds are SKINS behind one playfield.
        // Never fork these per family; art must be composed to this frame.
        // farY 0.30 == sky 20%: the contract shared with the recomposed
        // masters (master_composition_template.png — sky in the top fifth,
        // walkable ground below). All seven families ship template art as
        // of 2026-09-12 (moss2/glow2/dusk2/tide2/starlight2/ember3/stone3).
        /// Foot line at the far/near edges, as fractions of scene HEIGHT.
        var farY: CGFloat = 0.30
        var nearY: CGFloat = -0.34
        /// Walkable half-width at the far/near edges, fractions of WIDTH.
        var farHalfW: CGFloat = 0.13
        var nearHalfW: CGFloat = 0.21
        /// Creature scale multiplier across the depth range.
        var farScale: CGFloat = 0.52
        var nearScale: CGFloat = 1.06
        /// Contact-shadow weight across the range (multiplies the rest pose).
        var farShadowAlpha: CGFloat = 1.00
        var nearShadowAlpha: CGFloat = 1.28
        var farShadowScale: CGFloat = 0.88
        var nearShadowScale: CGFloat = 1.32

        /// The ONE spec used everywhere. Family art differs; geometry never.
        static let standard = Playfield()

        private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
            a + (b - a) * max(0, min(1, t))
        }
        /// The FOOT line (scene y) at a depth.
        func footY(depth: CGFloat, sceneSize s: CGSize) -> CGFloat {
            lerp(farY, nearY, depth) * s.height
        }
        /// Walkable half-width (scene points) at a depth.
        func halfWidth(depth: CGFloat, sceneSize s: CGSize) -> CGFloat {
            lerp(farHalfW, nearHalfW, depth) * s.width
        }
        func scaleMultiplier(depth: CGFloat) -> CGFloat {
            lerp(farScale, nearScale, depth)
        }
        func shadowAlphaMultiplier(depth: CGFloat) -> CGFloat {
            lerp(farShadowAlpha, nearShadowAlpha, depth)
        }
        func shadowScaleMultiplier(depth: CGFloat) -> CGFloat {
            lerp(farShadowScale, nearShadowScale, depth)
        }
        /// Inverse of `footY`: which depth puts the feet at scene y (clamped).
        func depth(forFootY y: CGFloat, sceneSize s: CGSize) -> CGFloat {
            let far = farY * s.height, near = nearY * s.height
            guard abs(near - far) > 0.01 else { return 1 }
            return max(0, min(1, (y - far) / (near - far)))
        }
        /// The walkable polygon in scene coordinates (for overlays/containment).
        func polygon(sceneSize s: CGSize) -> [CGPoint] {
            [CGPoint(x: -halfWidth(depth: 0, sceneSize: s), y: footY(depth: 0, sceneSize: s)),
             CGPoint(x: halfWidth(depth: 0, sceneSize: s), y: footY(depth: 0, sceneSize: s)),
             CGPoint(x: halfWidth(depth: 1, sceneSize: s), y: footY(depth: 1, sceneSize: s)),
             CGPoint(x: -halfWidth(depth: 1, sceneSize: s), y: footY(depth: 1, sceneSize: s))]
        }
    }

    // MARK: - Event zones (normalized, family-agnostic)

    /// Reusable stage regions for later family events. Defined relative to
    /// the live scene size and the shared ground line, never to one body or
    /// family, so any event system can ask "where may a shooting star fly?"
    enum Zone: String, CaseIterable {
        case skyEvent, airEvent, groundEvent, foregroundPass, auriePlay
    }

    /// Rect zones for the airborne bands; the GROUND-related zones are
    /// polygon-aware and live on `Playfield` instead of fixed screen bands.
    static func zoneRect(_ zone: Zone, sceneSize s: CGSize,
                         playfield: Playfield) -> CGRect {
        let w = s.width, h = s.height
        switch zone {
        case .skyEvent:        // shooting stars, cloud shapes, drifting lights
            let top = playfield.footY(depth: 0, sceneSize: s) + h * 0.10
            return CGRect(x: -w * 0.42, y: top, width: w * 0.84,
                          height: h * 0.44 - (top - h * 0.02))
        case .airEvent:        // butterflies, moths, leaves, embers, fireflies
            let base = playfield.footY(depth: 0.5, sceneSize: s)
            return CGRect(x: -w * 0.40, y: base, width: w * 0.80, height: h * 0.26)
        case .foregroundPass:  // something crossing very close to the viewer
            let nearFoot = playfield.footY(depth: 1, sceneSize: s)
            return CGRect(x: -w * 0.55, y: nearFoot - h * 0.14,
                          width: w * 1.10, height: h * 0.13)
        case .groundEvent, .auriePlay:
            // Perspective zones: use `groundEventPoint` / `playRegion`.
            let far = playfield.footY(depth: 0, sceneSize: s)
            let near = playfield.footY(depth: 1, sceneSize: s)
            return CGRect(x: -playfield.halfWidth(depth: 1, sceneSize: s),
                          y: near, width: playfield.halfWidth(depth: 1, sceneSize: s) * 2,
                          height: far - near)
        }
    }

    /// A concrete spot ON the walkable ground: `depth` picks the row,
    /// `across` (-1…1) slides along that row's width. Found objects,
    /// mushrooms, shells and chase destinations land here.
    static func groundEventPoint(depth: CGFloat, across: CGFloat,
                                 sceneSize s: CGSize,
                                 playfield: Playfield) -> CGPoint {
        let t = max(-1, min(1, across))
        return CGPoint(x: t * playfield.halfWidth(depth: depth, sceneSize: s),
                       y: playfield.footY(depth: depth, sceneSize: s))
    }

    /// The reachable region around a creature standing at `depth`: the
    /// walkable row it is on, extended a little toward the rows in front and
    /// behind — where toys and interactions live.
    static func playRegion(aroundDepth depth: CGFloat, sceneSize s: CGSize,
                           playfield: Playfield) -> CGRect {
        let d0 = max(0, depth - 0.22), d1 = min(1, depth + 0.22)
        let yTop = playfield.footY(depth: d0, sceneSize: s)
        let yBot = playfield.footY(depth: d1, sceneSize: s)
        let half = max(playfield.halfWidth(depth: d0, sceneSize: s),
                       playfield.halfWidth(depth: d1, sceneSize: s))
        return CGRect(x: -half, y: yBot, width: half * 2,
                      height: max(yTop - yBot, 30) + 60)
    }

    // MARK: - State

    private var layers: [SKSpriteNode] = []

    /// The SKY layer's artwork and exactly where it sits on screen, for
    /// effects that DUPLICATE SLICES of the painting rather than draw their
    /// own marks (Tide's shoreline surf). Returning the scale and centre as
    /// well as the texture is what lets a caller map a scene-space band back
    /// to the normalized texture rect it came from.
    ///
    /// NOTE: the sky layer parallaxes (`Parallax.sky` = 4pt max) while a
    /// slice placed from this does not, so a slice can sit up to ~4pt off its
    /// source at full creature excursion. That is below the feather width and
    /// was judged not worth coupling the two nodes together for.
    /// Mean luminance of the backdrop, 0...1, sampled once from the sky
    /// artwork. The creature's aura is ADDITIVE, so the same glow reads
    /// completely differently depending on what it lands on — measured, it
    /// lifts Dusk by 40% of its background but Stone by only 15%, which is
    /// why Stone's aura looks absent. Whoever draws the aura needs this to
    /// compensate.
    private(set) var backdropLuminance: CGFloat = 0.5

    private func sampleBackdropLuminance(_ texture: SKTexture) -> CGFloat {
        let cg = texture.cgImage()
        let w = 24, h = 24
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0.5 }
        // Sample only the band the creature STANDS in, not the whole
        // painting. A family can have a bright sky over a dark floor (or the
        // reverse), and what matters is what the aura actually lands on —
        // sampling the full image made Dusk read as bright and pushed its
        // aura up instead of down.
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        let band = CGRect(x: iw * 0.28, y: ih * 0.52,
                          width: iw * 0.44, height: ih * 0.30)
        guard let crop = cg.cropping(to: band) else { return 0.5 }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        var total = 0.0
        for px in stride(from: 0, to: buf.count, by: 4) {
            total += (Double(buf[px]) + Double(buf[px + 1]) + Double(buf[px + 2])) / 3
        }
        return CGFloat(total / Double(w * h) / 255)
    }

    var skyLayer: (texture: SKTexture, scale: CGFloat, centerY: CGFloat)? {
        guard let sprite = layers.first, let texture = sprite.texture,
              isActive else { return nil }
        return (texture, sprite.xScale, sprite.position.y)
    }

    private var factors: [CGFloat] = []          // parallax points per layer
    private var currentOffset: CGFloat = 0       // smoothed -1…1
    private(set) var isActive = false

    /// Extra scale beyond aspect-fill so parallax travel can never expose an
    /// edge: the layer covers viewport + 2× its own maximum excursion.
    private func fillScale(for texture: SKTexture, in size: CGSize,
                           travel: CGFloat) -> CGFloat {
        let t = texture.size()
        return max((size.width + travel * 2 + 8) / t.width,
                   (size.height + travel * 2 + 8) / t.height)
    }

    // MARK: - Building

    /// Plug a family's artwork in. Returns false (and stays inactive) when a
    /// required slot has no art — the scene keeps its existing background.
    @discardableResult
    func activate(family: AuraFamily, in scene: SKScene) -> Bool {
        guard let config = FamilyEnvironment.registry[family],
              config.isComplete else { return false }
        var textures: [SKTexture] = []
        var zs: [CGFloat] = []
        var travels: [CGFloat] = []
        let slots: [(name: String, z: CGFloat, travel: CGFloat)] =
            config.flatMaster
            ? [(config.sky, -100, Parallax.sky)]
            : [(config.sky, -100, Parallax.sky),
               (config.mid, -90, Parallax.mid),
               (config.ground, -80, Parallax.ground),
               (config.fore, 60, Parallax.fore)]
        for slot in slots {
            guard let image = UIImage(named: slot.name) else { continue }
            textures.append(SKTexture(image: image))
            zs.append(slot.z)
            travels.append(slot.travel)
        }
        let glowImage = UIImage(named: config.glow)
        build(sceneSize: scene.size,
              textures: textures,
              glow: glowImage.map { SKTexture(image: $0) },
              zs: zs, travels: travels)
        return true
    }

    /// DEBUG grey-box: deliberately unpolished neutral layers that exist only
    /// to validate registration, cropping, parallax, occlusion, depth and
    /// zones before real art lands. The GROUND is drawn in scene space from
    /// the playfield itself, so the perspective plane always matches the
    /// walkable polygon exactly on every device.
    func activateGreyBox(in scene: SKScene,
                         playfield: Playfield = .standard) {
        build(sceneSize: scene.size,
              textures: [Self.greyTexture(.sky), Self.greyTexture(.mid),
                         Self.greyTexture(.fore)],
              glow: nil,
              zs: [-100, -90, 60],
              travels: [Parallax.sky, Parallax.mid, Parallax.fore])
        addChild(Self.greyGround(playfield: playfield, sceneSize: scene.size))
    }

    /// The perspective ground plane: horizon line, receding side rails, and
    /// depth shading — one glance says "this surface goes back into the
    /// scene", which is the entire point of the correction.
    private static func greyGround(playfield: Playfield,
                                   sceneSize s: CGSize) -> SKNode {
        let node = SKNode()
        node.zPosition = -80
        let farY = playfield.footY(depth: 0, sceneSize: s)
        let nearY = playfield.footY(depth: 1, sceneSize: s)
        let bottom = -s.height / 2
        // The visual plane extends past the walkable edges (art bleed) and
        // continues to the screen bottom in front of the near edge.
        func railX(_ depth: CGFloat, _ side: CGFloat) -> CGFloat {
            side * playfield.halfWidth(depth: depth, sceneSize: s) * 1.45
        }
        let plane = CGMutablePath()
        plane.move(to: CGPoint(x: railX(0, -1), y: farY))
        plane.addLine(to: CGPoint(x: railX(0, 1), y: farY))
        plane.addLine(to: CGPoint(x: railX(1, 1) * 1.25, y: bottom))
        plane.addLine(to: CGPoint(x: railX(1, -1) * 1.25, y: bottom))
        plane.closeSubpath()
        let fill = SKShapeNode(path: plane)
        fill.fillColor = UIColor(white: 0.36, alpha: 1)
        fill.strokeColor = .clear
        node.addChild(fill)
        // Horizon line across the full width.
        let horizon = SKShapeNode(path: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -s.width / 2, y: farY))
            p.addLine(to: CGPoint(x: s.width / 2, y: farY))
            return p
        }())
        horizon.strokeColor = UIColor(white: 0.55, alpha: 1)
        horizon.lineWidth = 2.5
        node.addChild(horizon)
        // Depth shading bands + converging guide rails.
        for d in stride(from: CGFloat(0), through: 1.0, by: 0.25) {
            let y = playfield.footY(depth: d, sceneSize: s)
            let row = SKShapeNode(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: railX(d, -1), y: y))
                p.addLine(to: CGPoint(x: railX(d, 1), y: y))
                return p
            }())
            row.strokeColor = UIColor(white: 0.46, alpha: 1)
            row.lineWidth = 1.5
            node.addChild(row)
        }
        for side in [CGFloat(-1), 1] {
            let rail = SKShapeNode(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: railX(0, side), y: farY))
                p.addLine(to: CGPoint(x: railX(1, side), y: nearY))
                p.addLine(to: CGPoint(x: railX(1, side) * 1.25, y: bottom))
                return p
            }())
            rail.strokeColor = UIColor(white: 0.5, alpha: 1)
            rail.lineWidth = 2
            node.addChild(rail)
        }
        let label = SKLabelNode(text: "GREYBOX PERSPECTIVE GROUND")
        label.fontSize = 15
        label.fontName = "Menlo-Bold"
        label.fontColor = UIColor(white: 0.6, alpha: 1)
        label.position = CGPoint(x: 0, y: bottom + 24)
        node.addChild(label)
        return node
    }

    /// Shared fitting rule for every layer of every family: aspect-fill
    /// with the artwork's HORIZON pinned to the playfield's far line. The
    /// masters are composed to the 20% template (sky in the top fifth —
    /// master_composition_template.png) and the shared playfield puts its
    /// far walk line at that same fraction, so any excess height crops 20%
    /// from the sky side and the rest from the decorative near-foreground
    /// band. A painting taller than the viewport (the 9:16 masters on an
    /// iPad scene) therefore keeps its horizon at the same on-screen height
    /// on every device, instead of the aspect ratio deciding whether the
    /// sky survives the crop.
    private func horizonAlignedY(scaledHeight: CGFloat,
                                 sceneHeight: CGFloat) -> CGFloat {
        let excess = max(0, scaledHeight - sceneHeight)
        let skyFraction = 0.5 - Playfield.standard.farY   // template contract
        return excess * (skyFraction - 0.5)
    }

    private func build(sceneSize: CGSize, textures: [SKTexture],
                       glow: SKTexture?,
                       zs: [CGFloat] = [-100, -90, -80, 60],
                       travels: [CGFloat] = [Parallax.sky, Parallax.mid,
                                             Parallax.ground, Parallax.fore]) {
        removeAllChildren()
        layers.removeAll(); factors.removeAll()
        for (i, tex) in textures.enumerated() {
            let sprite = SKSpriteNode(texture: tex)
            sprite.zPosition = zs[i]
            let scale = fillScale(for: tex, in: sceneSize, travel: travels[i])
            sprite.setScale(scale)
            sprite.position.y = horizonAlignedY(
                scaledHeight: tex.size().height * scale,
                sceneHeight: sceneSize.height)
            addChild(sprite)
            if i == 0 { backdropLuminance = sampleBackdropLuminance(tex) }
            layers.append(sprite)
            factors.append(travels[i])
        }
        if let glow {
            let g = SKSpriteNode(texture: glow)
            g.zPosition = 62
            g.blendMode = .add
            g.alpha = 0.85
            let scale = fillScale(for: glow, in: sceneSize, travel: Parallax.fore)
            g.setScale(scale)
            g.position.y = horizonAlignedY(
                scaledHeight: glow.size().height * scale,
                sceneHeight: sceneSize.height)
            addChild(g)
            layers.append(g)
            factors.append(Parallax.fore)
        }
        isActive = true
    }

    /// Re-fit on rotation / size change (idempotent).
    func layout(for size: CGSize) {
        guard isActive else { return }
        for (i, layer) in layers.enumerated() {
            guard let tex = layer.texture else { continue }
            let scale = fillScale(for: tex, in: size, travel: factors[i])
            layer.setScale(scale)
            layer.position.y = horizonAlignedY(
                scaledHeight: tex.size().height * scale,
                sceneHeight: size.height)
        }
    }

    /// Deactivate and RELEASE the artwork (the textures die with the nodes,
    /// so switching families never keeps two worlds resident).
    func deactivate() {
        removeAllChildren()
        layers.removeAll(); factors.removeAll()
        isActive = false
        currentOffset = 0
    }

    // MARK: - Parallax tick

    /// Drive from the creature's normalized travel (-1…1). Smoothed so hops
    /// ease the world rather than yank it; foreground leads, sky trails.
    func updateParallax(normalizedX: CGFloat) {
        guard isActive else { return }
        let target = max(-1, min(1, normalizedX))
        currentOffset += (target - currentOffset) * Parallax.smoothing
        for (i, layer) in layers.enumerated() {
            layer.position.x = -currentOffset * factors[i]
        }
    }

    // MARK: - Grey-box textures (mechanics only, deliberately plain)

    enum GreySlot { case sky, mid, ground, fore }

    static func greyTexture(_ slot: GreySlot) -> SKTexture {
        let size = CGSize(width: 800, height: 1100)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            func label(_ text: String, _ y: CGFloat) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 34),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.55),
                ]
                (text as NSString).draw(at: CGPoint(x: 24, y: y), withAttributes: attrs)
            }
            switch slot {
            case .sky:
                c.setFillColor(UIColor(white: 0.16, alpha: 1).cgColor)
                c.fill(CGRect(origin: .zero, size: size))
                // Distant blobs so sky parallax is measurable.
                c.setFillColor(UIColor(white: 0.22, alpha: 1).cgColor)
                c.fillEllipse(in: CGRect(x: 90, y: 120, width: 200, height: 90))
                c.fillEllipse(in: CGRect(x: 470, y: 220, width: 240, height: 100))
                c.setFillColor(UIColor(white: 0.30, alpha: 1).cgColor)
                c.fillEllipse(in: CGRect(x: 330, y: 90, width: 60, height: 60))
                label("GREYBOX SKY", 40)
            case .mid:
                c.clear(CGRect(origin: .zero, size: size))
                c.setFillColor(UIColor(white: 0.30, alpha: 1).cgColor)
                // Side structures framing the centre (centre stays open).
                for x in [CGFloat(30), 640] {
                    c.fill(CGRect(x: x, y: 330, width: 130, height: 460))
                }
                c.setFillColor(UIColor(white: 0.26, alpha: 1).cgColor)
                for x in [CGFloat(190), 560] {
                    c.fill(CGRect(x: x, y: 420, width: 60, height: 330))
                }
                label("GREYBOX MID", 350)
            case .ground:
                c.clear(CGRect(origin: .zero, size: size))
                // The playfield surface band with a measurable grid.
                c.setFillColor(UIColor(white: 0.38, alpha: 1).cgColor)
                c.fill(CGRect(x: 0, y: 700, width: 800, height: 400))
                c.setStrokeColor(UIColor(white: 0.48, alpha: 1).cgColor)
                c.setLineWidth(3)
                for gx in stride(from: 0, through: 800, by: 100) {
                    c.move(to: CGPoint(x: gx, y: 700))
                    c.addLine(to: CGPoint(x: gx, y: 1100))
                }
                c.strokePath()
                label("GREYBOX GROUND", 720)
            case .fore:
                c.clear(CGRect(origin: .zero, size: size))
                // One tall pillar + corner tufts: proves occlusion + max
                // parallax without crowding the safe centre.
                c.setFillColor(UIColor(white: 0.55, alpha: 1).cgColor)
                c.fill(CGRect(x: 40, y: 560, width: 90, height: 540))
                c.fillEllipse(in: CGRect(x: 620, y: 960, width: 220, height: 160))
                c.fillEllipse(in: CGRect(x: -60, y: 1000, width: 200, height: 140))
                label("GREYBOX FORE", 590)
            }
        }
        return SKTexture(image: img)
    }
}
