import SpriteKit
import UIKit

/// Resolves creature-part art by the ART_GUIDE naming convention
/// (`body_00_round`, `eyes_03`, `limbs_01`, `bellypattern_02`,
/// `background_moss`, ...). Returns the real sprite when that file exists in
/// the bundle, else a generated placeholder shape — so the whole app runs
/// before any art is drawn (§13). Real PNGs drop in later with no code change
/// here beyond bumping the part counts in AurieGenerator.
///
/// Placeholders follow the art rules in ART_GUIDE §3: tintable parts (body,
/// limbs, pattern, aura) are drawn white so tinting works; features (eyes,
/// mouth) are drawn in final colors.
enum AssetLoader {

    private static var imageCache: [String: UIImage] = [:]
    private static var textureCache: [String: SKTexture] = [:]
    private static var portraitCache: [String: UIImage] = [:]

    // MARK: - Live part set for AurieNode

    /// The texture dictionary AurieNode expects, resolved for one creature.
    static func textures(for aurie: Aurie) -> [String: SKTexture] {
        var t: [String: SKTexture] = [
            "aura":  texture(named: "aura_00") { placeholderAura() },
            "limbs": texture(named: name("limbs", aurie.parts.limbsId)) { placeholderLimbs(aurie.parts.limbsId) },
            "body":  texture(named: bodyName(aurie.body)) { placeholderBody(aurie.body) },
            "eyes":  texture(named: name("eyes", aurie.parts.eyesId)) { placeholderEyes(aurie.parts.eyesId) },
            "mouth": texture(named: name("mouth", aurie.parts.mouthId)) { placeholderMouth(aurie.parts.mouthId) },
        ]
        // The belly pattern is the one detail slot AurieNode already renders.
        // TODO: charms / texture / cheek marks when AurieNode grows those layers.
        if let p = aurie.slots.bellyPatternId {
            t["pattern"] = texture(named: name("bellypattern", p)) { placeholderPattern(p) }
        }
        return t
    }

    /// Family background — the real art if present, else nil, meaning "use the
    /// family-color tint fallback" (§9). TODO(step 7): consume on Home + full-screen.
    static func background(for family: AuraFamily) -> SKTexture? {
        UIImage(named: "background_\(family.rawValue)").map { SKTexture(image: $0) }
    }

    // MARK: - Still portrait (collection tiles now; widget + "born from" cards later)

    /// A composed still image of the creature: same part stack, z-order,
    /// offsets, and tinting as AurieNode, drawn once and cached by id.
    /// TODO(art): when real full-frame 1024 canvases arrive, parts already sit
    /// in place on the canvas — drop the eye/mouth offsets then (they mirror
    /// AurieNode, which needs the same change).
    static func portrait(for aurie: Aurie) -> UIImage {
        // Keyed on id AND equipment: the cache used to key on id alone, so
        // once a tile had been drawn bare it stayed bare forever — equipping
        // a charm never refreshed the grid (2026-09-21).
        let key = "\(aurie.id)#\(AurieEquipmentRender.equipmentSignature(for: aurie))"
        if let cached = portraitCache[key] { return cached }
        // Bodies with real (Blender) artwork are SNAPSHOT FROM THE LIVE RIG, so
        // a collection tile is the same creature Home shows — same layer order,
        // same tint shader, same face — instead of a second, drifting 2D
        // assembly of the old placeholder parts. Anything without that artwork
        // still composites the placeholder stack below.
        let portrait = blenderPortrait(for: aurie, canvas: CGSize(width: 340, height: 340))
            ?? composite(for: aurie, canvas: CGSize(width: 340, height: 340))
        portraitCache[key] = portrait
        return portrait
    }

    /// Render the real `AurieNode` offscreen and return it as an image.
    /// Returns nil when the body has no Blender skin, or if the snapshot
    /// fails for any reason, so the caller can fall back.
    private static func blenderPortrait(for aurie: Aurie,
                                        canvas: CGSize) -> UIImage? {
        guard AurieBlenderSkin.isAvailable(aurie.body) else { return nil }
        let node = AurieNode(
            textures: textures(for: aurie),
            baseColor: UIColor(aurie.baseColor),
            auraColor: UIColor(aurie.auraColor),
            body: aurie.body,
            armStyle: aurie.resolvedArmStyle,
            legStyle: aurie.resolvedLegStyle,
            hairStyle: aurie.resolvedHairStyle,
            patternLayer: aurie.patternMaskLayer,
            // A portrait wears what the creature wears. These come from the
            // SAME resolvers Home uses (AurieEquipmentRender), so the grid,
            // the widget and the Settings thumbnail can never drift from the
            // live scene. Belly + back draw directly; the aura cluster is
            // captured in its deterministic rest layout, which is the
            // approved static representation. Floating stays paused.
            charmLayers: AurieEquipmentRender.charmLayerKeys(for: aurie),
            bellyStickerCharmID: AurieEquipmentRender.bellyStickerID(for: aurie),
            auraCharmID: AurieEquipmentRender.auraCharmID(for: aurie),
            floatingCharmID: AurieEquipmentRender.floatingCharmID(for: aurie))
        // A portrait is a STILL: the creature wears its saved expression and
        // nothing animates. `startIdle()` is deliberately never called, so
        // there is no breathing, blinking or sway to catch mid-frame.
        node.adoptBaseExpression(aurie.resolvedBaseExpression)
        node.hideContactShadow()

        // Fit the rig's own footprint into the tile with a little margin.
        let extent = max(collisionHalfWidth,
                         max(collisionHalfHeightUp, collisionHalfHeightDown))
        node.setScale(canvas.width * 0.42 / max(extent, 1))
        node.position = CGPoint(x: canvas.width / 2, y: canvas.height / 2)

        let scene = SKScene(size: canvas)
        scene.scaleMode = .aspectFit
        scene.backgroundColor = .clear
        scene.addChild(node)
        let view = SKView(frame: CGRect(origin: .zero, size: canvas))
        view.allowsTransparency = true
        guard let texture = view.texture(from: scene) else { return nil }
        // `SKView.texture(from:)` already hands back a display-oriented
        // bitmap, so no flip is applied here — adding one turns the portrait
        // upside down.
        return UIImage(cgImage: texture.cgImage())
    }

    /// The widget's featured-creature still (Phase 8B): the same creature the
    /// app shows, at a fixed 512 PHYSICAL pixels — sharp on a Retina
    /// systemSmall without being huge — with a transparent background.
    ///
    /// This is exported by the APP (see `WidgetExporter`), never inside the
    /// widget extension, so it can snapshot the live rig exactly like a
    /// collection tile. Bodies without Blender artwork fall back to the
    /// placeholder composite.
    static func widgetStill(for aurie: Aurie) -> UIImage {
        let canvas = CGSize(width: 512, height: 512)
        if let live = blenderPortrait(for: aurie, canvas: canvas) { return live }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return composite(for: aurie, canvas: canvas, format: format)
    }

    /// One complete creature drawn into a square canvas: aura, limbs, body,
    /// pattern, face — same z-order, offsets, and tinting as AurieNode, with
    /// the geometry scaled from the 340pt reference tile.
    private static func composite(for aurie: Aurie, canvas: CGSize,
                                  format: UIGraphicsImageRendererFormat = .init()) -> UIImage {
        let base = UIColor(aurie.baseColor)
        let pattern = aurie.slots.bellyPatternId

        // Fit the (larger, shared-canvas) assembly comfortably inside the tile.
        let fit: CGFloat = 0.78 * canvas.width / 340
        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            func place(_ img: UIImage, offset: CGPoint = .zero, alpha: CGFloat = 1) {
                let w = img.size.width * fit, h = img.size.height * fit
                img.draw(in: CGRect(x: (canvas.width - w) / 2 + offset.x * fit,
                                    y: (canvas.height - h) / 2 + offset.y * fit,
                                    width: w, height: h),
                         blendMode: .normal, alpha: alpha)
            }
            place(tinted(image(named: "aura_00") { placeholderAura() },
                         UIColor(aurie.auraColor)), alpha: 0.55)
            place(tinted(image(named: name("limbs", aurie.parts.limbsId)) { placeholderLimbs(aurie.parts.limbsId) }, base))
            place(tinted(image(named: bodyName(aurie.body)) { placeholderBody(aurie.body) }, base))
            if let p = pattern {
                place(tinted(image(named: name("bellypattern", p)) { placeholderPattern(p) },
                             darkened(base, by: 0.25)))
            }
            // SpriteKit offsets are y-up; UIKit draws y-down, hence the flip.
            place(image(named: name("eyes", aurie.parts.eyesId)) { placeholderEyes(aurie.parts.eyesId) },
                  offset: CGPoint(x: 0, y: -30))
            place(image(named: name("mouth", aurie.parts.mouthId)) { placeholderMouth(aurie.parts.mouthId) },
                  offset: CGPoint(x: 0, y: 35))
        }
    }

    // MARK: - Naming (must match ART_GUIDE §6 exactly)

    static func bodyName(_ body: BodyType) -> String {
        let index = BodyType.allCases.firstIndex(of: body)!
        return String(format: "body_%02d_%@", index, body.rawValue)
    }

    static func name(_ part: String, _ id: Int) -> String {
        String(format: "%@_%02d", part, id)
    }

    // MARK: - Resolution + caches

    private static func image(named assetName: String, placeholder: () -> UIImage) -> UIImage {
        if let cached = imageCache[assetName] { return cached }
        let resolved = UIImage(named: assetName) ?? placeholder()
        imageCache[assetName] = resolved
        return resolved
    }

    private static func texture(named assetName: String, placeholder: () -> UIImage) -> SKTexture {
        if let cached = textureCache[assetName] { return cached }
        let texture = SKTexture(image: image(named: assetName, placeholder: placeholder))
        textureCache[assetName] = texture
        return texture
    }

    // MARK: - Tinting (multiply, like AurieNode's colorBlendFactor)

    /// Multiply-tint that preserves shading on real art; on flat white
    /// placeholders it's a plain fill.
    private static func tinted(_ image: UIImage, _ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: image.size).image { ctx in
            image.draw(at: .zero)
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size), blendMode: .multiply)
            image.draw(at: .zero, blendMode: .destinationIn, alpha: 1)   // restore alpha
        }
    }

    private static func darkened(_ c: UIColor, by f: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * (1 - f), green: g * (1 - f), blue: b * (1 - f), alpha: a)
    }

    // MARK: - Presentation placeholder (Stage B)
    //
    // Coordinated, dimensional, body-type-distinct shapes with small SEPARATE
    // limbs (no fused elephant/flower silhouette), a baked upper-left highlight,
    // lower-right soft shadow, a subtle outline, and cheeks. Parts share one
    // canvas + anchor scheme (ART_GUIDE) so they align, and the whole assembly
    // scales as one (AurieNode). Drawn near-white so the family tint reads as
    // colour while the baked light/shadow keep it three-dimensional. Real PNGs
    // still resolve first by name — this is only the fallback.

    /// Canonical body-footprint width (the round body's diameter). Other bodies
    /// vary around it, preserving body-type size differences.
    static let placeholderReferenceWidth: CGFloat = 300

    /// The creature's PHYSICAL interaction footprint at scale 1, in native part
    /// coordinates: the widest body (the 348-wide "wide" type ≈ ±175) plus the
    /// arms (±138 + radius) and feet (±58, extending ~190 below). Used both to
    /// choose the creature's scale and to clamp its movement.
    ///
    /// This deliberately EXCLUDES the aura, contact shadow, family particles,
    /// hearts/stars, reaction effects, and speech bubbles — only parts that
    /// physically extend the silhouette count.
    static let collisionHalfWidth: CGFloat = 175
    static let collisionHalfHeightUp: CGFloat = 172     // head top (tall body)
    static let collisionHalfHeightDown: CGFloat = 190   // feet bottom

    private static let pcanvas = CGSize(width: 400, height: 420)
    private static let pcenter = CGPoint(x: 200, y: 210)

    private static func draw(_ size: CGSize, _ body: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2   // crisp when the whole creature is scaled up on iPad
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            body(ctx.cgContext)
        }
    }

    /// Dark backing (a clean outer outline, even for compound lumpy shapes) +
    /// an inset shaded fill with a per-part upper-left highlight and lower-right
    /// shadow (one consistent light direction). `cheeks` adds two soft blushes.
    private static func shade(_ c: CGContext, path: CGPath, midtone: CGFloat = 0.95, cheeks: Bool) {
        let b = path.boundingBoxOfPath
        // 1) dark backing = outer outline; fills merge so no internal seams.
        c.saveGState()
        c.addPath(path); UIColor(white: 0.28, alpha: 0.55).setFill(); c.fillPath()
        c.restoreGState()
        // 2) shaded fill, inset a hair so the backing shows as a thin rim.
        c.saveGState()
        c.addPath(insetPath(path, scale: 0.955)); c.clip()
        UIColor(white: midtone, alpha: 1).setFill(); c.fill(b.insetBy(dx: -20, dy: -20))
        let r = max(b.width, b.height) * 0.72
        softRadial(c, UIColor(white: 1.0, alpha: 0.8),
                   at: CGPoint(x: b.midX - b.width * 0.24, y: b.midY - b.height * 0.24), radius: r)
        softRadial(c, UIColor(white: 0.30, alpha: 0.5),
                   at: CGPoint(x: b.midX + b.width * 0.26, y: b.midY + b.height * 0.26), radius: r)
        if cheeks {
            UIColor(red: 1, green: 0.5, blue: 0.55, alpha: 0.5).setFill()
            for dx in [CGFloat(-80), 80] {
                c.fillEllipse(in: CGRect(x: pcenter.x + dx - 27, y: pcenter.y - 6, width: 54, height: 44))
            }
        }
        c.restoreGState()
    }

    /// Scale a path about its own centre (to inset a silhouette uniformly).
    private static func insetPath(_ path: CGPath, scale: CGFloat) -> CGPath {
        let b = path.boundingBoxOfPath
        var t = CGAffineTransform.identity
            .translatedBy(x: b.midX, y: b.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -b.midX, y: -b.midY)
        return path.copy(using: &t) ?? path
    }

    private static func softRadial(_ c: CGContext, _ color: UIColor, at p: CGPoint, radius: CGFloat) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                                 locations: [0, 1]) else { return }
        c.drawRadialGradient(g, startCenter: p, startRadius: 6, endCenter: p, endRadius: radius, options: [])
    }

    /// Distinct silhouette per BodyType, centred in the shared canvas.
    private static func bodyPath(_ body: BodyType) -> CGPath {
        let c = pcenter
        func ellipse(_ w: CGFloat, _ h: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: c.x - w/2, y: c.y - h/2, width: w, height: h), transform: nil)
        }
        switch body {
        case .round: return ellipse(300, 300)
        case .tall:  return ellipse(250, 344)
        case .wide:  return ellipse(348, 250)
        case .small: return ellipse(232, 232)
        case .lumpy:
            let p = CGMutablePath()
            p.addEllipse(in: CGRect(x: c.x - 152, y: c.y - 50, width: 150, height: 150))
            p.addEllipse(in: CGRect(x: c.x - 40, y: c.y - 150, width: 200, height: 210))
            p.addEllipse(in: CGRect(x: c.x + 2, y: c.y - 20, width: 150, height: 170))
            return p
        // Bodies added for the launch pool. These only ever render through the
        // PLACEHOLDER path (missing Blender assets / older builds), so rough
        // silhouettes are enough — the real art is the Blender export.
        case .egg:      return ellipse(262, 320)
        case .pear:     return ellipse(268, 300)
        case .dumpling: return ellipse(310, 272)
        case .teardrop: return ellipse(252, 322)
        case .beanbag:  return ellipse(330, 262)
        case .oval:     return ellipse(268, 318)
        case .heart:    return ellipse(304, 286)
        }
    }

    private static func placeholderBody(_ body: BodyType) -> UIImage {
        draw(pcanvas) { c in
            shade(c, path: bodyPath(body), cheeks: true)
        }
    }

    /// One arms+legs set: two small arm stubs at the lower sides and two small
    /// feet at the base — sized to peek from behind the body, never oversized.
    private static func placeholderLimbs(_ id: Int) -> UIImage {
        let c = pcenter
        let armR: CGFloat = 30 + CGFloat(id % 3) * 3
        let legR: CGFloat = 33 + CGFloat(id % 2) * 3
        return draw(pcanvas) { ctx in
            func limb(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
                let rect = CGRect(x: x - r, y: y - r * 0.92, width: r * 2, height: r * 1.84)
                shade(ctx, path: CGPath(ellipseIn: rect, transform: nil), cheeks: false)
            }
            limb(c.x - 138, c.y + 44, armR)   // left arm
            limb(c.x + 138, c.y + 44, armR)   // right arm
            limb(c.x - 58, c.y + 156, legR)   // left leg
            limb(c.x + 58, c.y + 156, legR)   // right leg
        }
    }

    /// Two rounded eyes with a bright catchlight; size/spacing vary by id.
    private static func placeholderEyes(_ id: Int) -> UIImage {
        let radius: CGFloat = 15 + CGFloat(id / 4) * 5      // ids 0-3 small, 4-7 large
        let gap: CGFloat = 34 + CGFloat(id % 4) * 9
        let size = CGSize(width: radius * 4 + gap, height: radius * 2.2)
        return draw(size) { c in
            for x in [CGFloat(0), radius * 2 + gap] {
                UIColor(white: 0.12, alpha: 1).setFill()
                c.fillEllipse(in: CGRect(x: x, y: radius * 0.1, width: radius * 2, height: radius * 2))
                UIColor.white.setFill()
                c.fillEllipse(in: CGRect(x: x + radius * 0.52, y: radius * 0.42,
                                         width: radius * 0.66, height: radius * 0.66))
            }
        }
    }

    /// Simple dark mouth; three flavours cycled by id (smile arc / oval / line).
    private static func placeholderMouth(_ id: Int) -> UIImage {
        let size = CGSize(width: 66, height: 36)
        return draw(size) { c in
            let dark = UIColor(white: 0.15, alpha: 1)
            switch id % 3 {
            case 0:   // smile arc
                dark.setStroke()
                c.setLineWidth(7)
                c.setLineCap(.round)
                c.addArc(center: CGPoint(x: 33, y: 8), radius: 22,
                         startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
                c.strokePath()
            case 1:   // little "oh" oval
                dark.setFill()
                c.fillEllipse(in: CGRect(x: 21, y: 5, width: 24, height: 27))
            default:  // soft flat line
                dark.setFill()
                let r = CGRect(x: 12, y: 15, width: 42, height: 8)
                c.addPath(CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil))
                c.fillPath()
            }
        }
    }

    /// Belly speckles, white so they tint to the darker base shade.
    private static func placeholderPattern(_ id: Int) -> UIImage {
        let c = pcenter
        let spots: [(CGFloat, CGFloat, CGFloat)] = [
            (-40, 30, 15), (30, 10, 12), (68, 44, 16), (-14, 66, 13), (44, 80, 11),
        ]
        return draw(pcanvas) { ctx in
            UIColor(white: 0.82, alpha: 0.9).setFill()
            for (i, s) in spots.enumerated() where i <= (id % 2 == 0 ? 4 : 2) {
                ctx.fillEllipse(in: CGRect(x: c.x + s.0 - s.2, y: c.y + s.1 - s.2, width: s.2 * 2, height: s.2 * 2))
            }
        }
    }

    /// Soft radial white glow (a halo a little larger than the body); tinted
    /// with auraColor wherever it's drawn.
    private static func placeholderAura() -> UIImage {
        let size = CGSize(width: 400, height: 400)
        return draw(size) { c in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray, locations: [0, 1])!
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            c.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                 endCenter: center, endRadius: size.width / 2, options: [])
        }
    }
}
