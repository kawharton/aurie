import SpriteKit
import UIKit

/// The drawn half of the family particle system: 3–5 coordinated MOTIFS per
/// family, each built as a real little illustration rather than a flat dot.
///
/// Every motif follows the same construction so the whole set reads as one
/// visual language:
///
///     1. a defined silhouette (leaf, shard, bubble, star…)
///     2. a brighter internal core or highlight
///     3. a soft outer bloom
///
/// Textures are drawn ONCE into a cache keyed by motif and never regenerated —
/// nothing here may run on a frame. Canvases are drawn large (44–72 pt) and
/// scaled down at use, so a particle stays crisp at any size the motion layer
/// asks for.
///
/// Motion lives in `ParticleField`; this file knows nothing about how a
/// particle travels. That split is what lets a caller say "ember + swirl" or
/// "moss + celebration" without any per-site art.
enum FamilyParticleArt {

    /// Every motif in the system. The raw value doubles as the texture cache key.
    enum Motif: String, CaseIterable {
        // Moss — enchanted forest: sunlight through leaves.
        case mossLeaf, mossPetal, mossPollen, mossFirefly, mossSeed
        /// A GREEN spore. `mossPollen` is gold and `mossSeed` is cream, so
        /// neither reads as the green drifting spores a forest floor throws.
        case mossSpore
        // Ember — glowing fragments, not orange dots.
        case emberFragment, emberSpark, emberCinder, emberStreak, emberFleck
        // Tide — luminous and underwater.
        case tideBubble, tideDroplet, tideFleck, tideShimmer, tideBiolum
        // Shoreline motion (2026-09-22). These are WIDE BANDS, not points:
        // stretched across most of the scene and slid shoreward, so the surf
        // reads as water arriving rather than as decorative marks.
        case tideWaveCrest, tideFoamWash
        // Ember heat: a soft vertical plume that rises and wavers.
        case emberHeat
        // Glow — crystalline, the most luminous family.
        case glowShard, glowDiamond, glowOrb, glowPrism, glowFlare
        // Dusk — dreamy and nocturnal.
        case duskFirefly, duskFleck, duskStarburst, duskPetal, duskComet
        // Stone — sunlight catching minerals, never dirt.
        case stoneFleck, stoneQuartz, stoneDust, stoneSpeck, stoneShard
        /// Ambient dust for the Stone meadow. Separate from `stoneDust`
        /// (which the emitter also uses) because it needs a shadow edge that
        /// would look wrong on a celebration burst.
        case stoneMote
        // Starlight — celestial, never generic glitter.
        case starRadiant, starSparkle, starComet, starDot, starCluster
        /// A star as an actual POINT of light. `starDot` carries a halo at
        /// 0.6 alpha across half its canvas, which at ambient sizes reads as
        /// a glowing blob rather than a star (2026-09-22).
        case starPinprick
    }

    /// The motifs belonging to each family, in the order they were designed.
    static func motifs(for family: AuraFamily) -> [Motif] {
        // ORDER MATTERS: the emitter draws its common particles from the first
        // three and treats the last two as rare accents. So the quieter,
        // structural motifs lead and the showy ones stay occasional — that is
        // what stops Starlight and Glow from washing the creature out.
        switch family {
        case .moss:      return [.mossLeaf, .mossPollen, .mossPetal, .mossFirefly, .mossSeed]
        case .ember:     return [.emberCinder, .emberFragment, .emberFleck, .emberSpark, .emberStreak]
        case .tide:      return [.tideBubble, .tideFleck, .tideDroplet, .tideShimmer, .tideBiolum]
        case .glow:      return [.glowDiamond, .glowShard, .glowOrb, .glowPrism, .glowFlare]
        case .dusk:      return [.duskFleck, .duskFirefly, .duskPetal, .duskStarburst, .duskComet]
        case .stone:     return [.stoneDust, .stoneFleck, .stoneQuartz, .stoneSpeck, .stoneShard]
        case .starlight: return [.starDot, .starCluster, .starSparkle, .starRadiant, .starComet]
        }
    }

    /// Per-family restraint. The luminous families stack additively and will
    /// swamp the creature's silhouette at full strength, so they are pulled
    /// back; the quieter ones are nudged up to hold their own.
    static func intensity(for family: AuraFamily) -> CGFloat {
        switch family {
        case .starlight: return 0.58
        case .glow:      return 0.74
        case .dusk:      return 0.86
        case .tide:      return 0.92
        case .ember:     return 0.92
        case .moss:      return 1.08
        case .stone:     return 1.02
        }
    }

    /// Cached texture for a motif. Drawn on first use, then reused forever.
    static func texture(_ motif: Motif) -> SKTexture {
        if let cached = cache[motif] { return cached }
        let texture = SKTexture(image: draw(motif))
        texture.filteringMode = .linear
        cache[motif] = texture
        return texture
    }

    /// Warm every texture up front (the DEBUG gallery and Wonderglobe both
    /// want the first frame to be as smooth as the hundredth).
    static func preload(_ family: AuraFamily) {
        for motif in motifs(for: family) { _ = texture(motif) }
    }

    private static var cache: [Motif: SKTexture] = [:]

    // MARK: - Palettes

    private enum P {
        // Moss
        static let leafGreen  = UIColor(red: 0.42, green: 0.68, blue: 0.34, alpha: 1)
        static let leafLight  = UIColor(red: 0.70, green: 0.86, blue: 0.48, alpha: 1)
        static let pollenGold = UIColor(red: 0.94, green: 0.86, blue: 0.44, alpha: 1)
        static let cream      = UIColor(red: 1.00, green: 0.98, blue: 0.90, alpha: 1)
        // Ember
        static let emberRed   = UIColor(red: 0.86, green: 0.20, blue: 0.16, alpha: 1)
        static let emberOrange = UIColor(red: 1.00, green: 0.48, blue: 0.18, alpha: 1)
        static let emberGold  = UIColor(red: 1.00, green: 0.78, blue: 0.34, alpha: 1)
        static let emberPale  = UIColor(red: 1.00, green: 0.95, blue: 0.76, alpha: 1)
        static let emberCoral = UIColor(red: 1.00, green: 0.52, blue: 0.55, alpha: 1)
        // Tide
        static let aqua       = UIColor(red: 0.42, green: 0.86, blue: 0.94, alpha: 1)
        static let paleBlue   = UIColor(red: 0.72, green: 0.92, blue: 1.00, alpha: 1)
        static let turquoise  = UIColor(red: 0.26, green: 0.74, blue: 0.78, alpha: 1)
        static let pearl      = UIColor(red: 0.96, green: 0.99, blue: 1.00, alpha: 1)
        // Glow
        static let glowYellow = UIColor(red: 1.00, green: 0.86, blue: 0.42, alpha: 1)
        static let glowCyan   = UIColor(red: 0.60, green: 0.94, blue: 1.00, alpha: 1)
        static let glowViolet = UIColor(red: 0.80, green: 0.70, blue: 1.00, alpha: 1)
        static let hot        = UIColor(white: 1, alpha: 1)
        // Dusk
        static let violet     = UIColor(red: 0.62, green: 0.46, blue: 0.92, alpha: 1)
        static let magenta    = UIColor(red: 0.92, green: 0.46, blue: 0.80, alpha: 1)
        static let dustyPink  = UIColor(red: 0.96, green: 0.70, blue: 0.80, alpha: 1)
        static let lavender   = UIColor(red: 0.80, green: 0.76, blue: 1.00, alpha: 1)
        static let mutedGold  = UIColor(red: 0.92, green: 0.82, blue: 0.56, alpha: 1)
        // Stone
        static let warmCream  = UIColor(red: 0.98, green: 0.94, blue: 0.86, alpha: 1)
        static let quartz     = UIColor(red: 0.90, green: 0.90, blue: 0.86, alpha: 1)
        static let taupe      = UIColor(red: 0.74, green: 0.68, blue: 0.60, alpha: 1)
        static let amber      = UIColor(red: 0.92, green: 0.74, blue: 0.40, alpha: 1)
        // Starlight
        static let starWhite  = UIColor(white: 1, alpha: 1)
        static let starBlue   = UIColor(red: 0.76, green: 0.86, blue: 1.00, alpha: 1)
        static let starGold   = UIColor(red: 1.00, green: 0.92, blue: 0.72, alpha: 1)
    }

    // MARK: - Drawing helpers

    private static func render(_ side: CGFloat,
                               _ body: (CGContext, CGFloat) -> Void) -> UIImage {
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            body(ctx.cgContext, side)
        }
    }

    /// Non-square canvas, for motifs that are BANDS rather than points
    /// (shoreline surf, heat plumes). Same cache, same one-time cost.
    private static func renderRect(_ w: CGFloat, _ h: CGFloat,
                                   _ body: (CGContext, CGFloat, CGFloat) -> Void) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
            body(ctx.cgContext, w, h)
        }
    }

    /// A run of overlapping soft blooms along a gently undulating line — the
    /// building block for surf. Alpha tapers to nothing at both ends (so the
    /// band dissolves instead of stopping), the centre line waves so it never
    /// looks ruled, and the radius varies so the foam is uneven like water.
    private static func foamLine(_ c: CGContext, w: CGFloat, n: Int,
                                 cy: CGFloat, wobble: CGFloat, waves: CGFloat,
                                 radius: CGFloat, jitter: CGFloat,
                                 _ outer: UIColor, _ inner: UIColor,
                                 _ outerAlpha: CGFloat, _ innerAlpha: CGFloat) {
        for i in 0 ..< n {
            let t = CGFloat(i) / CGFloat(max(n - 1, 1))
            // sin(pi*t) is 0 at both ends and 1 in the middle: the taper.
            let taper = pow(sin(t * .pi), 0.8)
            guard taper > 0.01 else { continue }
            let y = cy + sin(t * .pi * waves) * wobble
            let r = radius + sin(t * .pi * (waves * 2.7)) * jitter
            let p = CGPoint(x: t * w, y: y)
            bloom(c, center: p, radius: r * 2.3, outer, outerAlpha * taper)
            bloom(c, center: p, radius: r, inner, innerAlpha * taper)
        }
    }

    /// Soft radial falloff — the outer bloom every motif sits inside.
    private static func bloom(_ c: CGContext, center: CGPoint, radius: CGFloat,
                              _ color: UIColor, _ alpha: CGFloat = 0.5) {
        let colors = [color.withAlphaComponent(alpha).cgColor,
                      color.withAlphaComponent(alpha * 0.35).cgColor,
                      color.withAlphaComponent(0).cgColor] as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors, locations: [0, 0.45, 1]) else { return }
        c.drawRadialGradient(g, startCenter: center, startRadius: 0,
                             endCenter: center, endRadius: radius, options: [])
    }

    private static func poly(_ c: CGContext, _ points: [CGPoint], _ color: UIColor) {
        guard let first = points.first else { return }
        c.setFillColor(color.cgColor)
        c.move(to: first)
        for p in points.dropFirst() { c.addLine(to: p) }
        c.closePath()
        c.fillPath()
    }

    /// A pointed star of `points` arms — used for sparkles and flares.
    private static func star(_ c: CGContext, center: CGPoint, outer: CGFloat,
                             inner: CGFloat, points: Int, _ color: UIColor) {
        var pts: [CGPoint] = []
        for i in 0 ..< points * 2 {
            let r = i.isMultiple(of: 2) ? outer : inner
            let a = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            pts.append(CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r))
        }
        poly(c, pts, color)
    }

    /// A leaf/petal silhouette: two mirrored quadratic curves meeting at the tips.
    private static func leaf(_ c: CGContext, rect: CGRect, bend: CGFloat,
                             _ color: UIColor) {
        let path = UIBezierPath()
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        path.move(to: top)
        path.addQuadCurve(to: bottom,
                          controlPoint: CGPoint(x: rect.maxX + bend, y: rect.midY))
        path.addQuadCurve(to: top,
                          controlPoint: CGPoint(x: rect.minX + bend, y: rect.midY))
        c.setFillColor(color.cgColor)
        c.addPath(path.cgPath)
        c.fillPath()
    }

    // MARK: - Painters

    private static func draw(_ motif: Motif) -> UIImage {
        switch motif {

        // ---------- MOSS ----------
        case .mossLeaf:
            return render(52) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.46, P.leafGreen, 0.22)
                c.saveGState(); c.translateBy(x: s/2, y: s/2); c.rotate(by: 0.5)
                c.translateBy(x: -s/2, y: -s/2)
                leaf(c, rect: CGRect(x: s*0.30, y: s*0.12, width: s*0.40, height: s*0.76),
                     bend: s*0.05, P.leafGreen)
                // Lit edge + centre vein.
                leaf(c, rect: CGRect(x: s*0.36, y: s*0.18, width: s*0.24, height: s*0.60),
                     bend: s*0.03, P.leafLight.withAlphaComponent(0.75))
                c.setStrokeColor(P.cream.withAlphaComponent(0.5).cgColor)
                c.setLineWidth(s*0.022)
                c.move(to: CGPoint(x: s*0.5, y: s*0.16))
                c.addLine(to: CGPoint(x: s*0.5, y: s*0.84))
                c.strokePath()
                c.restoreGState()
            }
        case .mossPetal:
            return render(46) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.44, P.cream, 0.26)
                c.saveGState(); c.translateBy(x: s/2, y: s/2); c.rotate(by: -0.35)
                c.translateBy(x: -s/2, y: -s/2)
                leaf(c, rect: CGRect(x: s*0.28, y: s*0.20, width: s*0.44, height: s*0.60),
                     bend: s*0.02, P.cream)
                leaf(c, rect: CGRect(x: s*0.36, y: s*0.30, width: s*0.28, height: s*0.38),
                     bend: 0, P.pollenGold.withAlphaComponent(0.45))
                c.restoreGState()
            }
        case .mossPollen:
            return render(40) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.pollenGold, 0.55)
                c.setFillColor(P.pollenGold.cgColor)
                c.fillEllipse(in: CGRect(x: s*0.38, y: s*0.38, width: s*0.24, height: s*0.24))
                c.setFillColor(P.cream.cgColor)
                c.fillEllipse(in: CGRect(x: s*0.44, y: s*0.42, width: s*0.11, height: s*0.11))
            }
        case .mossSpore:
            return render(34) { c, s in
                // NOT a disc. A spore is a scrap of matter, so the silhouette
                // is built from overlapping lobes at different radii, and the
                // edge is two translucent passes rather than one clean fill —
                // the offset between them leaves a ragged, gradual boundary.
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.46,
                      P.leafGreen, 0.26)
                let lobes: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.500, 0.500, 0.150),
                    (0.575, 0.540, 0.100),
                    (0.440, 0.560, 0.092),
                    (0.525, 0.430, 0.082),
                    (0.425, 0.465, 0.068),
                ]
                for (fx, fy, r) in lobes {
                    c.setFillColor(P.leafGreen.withAlphaComponent(0.26).cgColor)
                    c.fillEllipse(in: CGRect(x: s*(fx - r*1.6), y: s*(fy - r*1.6),
                                             width: s*r*3.2, height: s*r*3.2))
                }
                for (fx, fy, r) in lobes {
                    c.setFillColor(P.leafLight.withAlphaComponent(0.50).cgColor)
                    c.fillEllipse(in: CGRect(x: s*(fx - r), y: s*(fy - r),
                                             width: s*r*2, height: s*r*2))
                }
                c.setFillColor(P.cream.withAlphaComponent(0.40).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.468, y: s*0.478,
                                         width: s*0.072, height: s*0.072))
            }
        case .mossFirefly:
            return render(56) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.pollenGold, 0.62)
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.26, P.cream, 0.85)
                c.setFillColor(P.cream.cgColor)
                c.fillEllipse(in: CGRect(x: s*0.43, y: s*0.43, width: s*0.14, height: s*0.14))
            }
        case .mossSeed:
            return render(44) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s*0.4), radius: s*0.34, P.cream, 0.3)
                // Little tufted seed: a soft head with a fine tail.
                c.setStrokeColor(P.cream.withAlphaComponent(0.75).cgColor)
                c.setLineWidth(s*0.03); c.setLineCap(.round)
                for a in stride(from: -0.9, through: 0.9, by: 0.45) {
                    c.move(to: CGPoint(x: s*0.5, y: s*0.42))
                    c.addLine(to: CGPoint(x: s*0.5 + sin(a)*s*0.26, y: s*0.42 - cos(a)*s*0.30))
                }
                c.strokePath()
                c.setFillColor(P.leafLight.cgColor)
                c.fillEllipse(in: CGRect(x: s*0.44, y: s*0.44, width: s*0.12, height: s*0.16))
            }

        // ---------- EMBER ----------
        case .emberFragment:
            return render(52) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.emberOrange, 0.55)
                poly(c, [CGPoint(x: s*0.50, y: s*0.16), CGPoint(x: s*0.72, y: s*0.42),
                         CGPoint(x: s*0.58, y: s*0.82), CGPoint(x: s*0.32, y: s*0.62),
                         CGPoint(x: s*0.30, y: s*0.32)], P.emberRed)
                poly(c, [CGPoint(x: s*0.50, y: s*0.28), CGPoint(x: s*0.64, y: s*0.46),
                         CGPoint(x: s*0.54, y: s*0.70), CGPoint(x: s*0.40, y: s*0.52)],
                     P.emberOrange)
                c.setFillColor(P.emberPale.cgColor)
                c.fillEllipse(in: CGRect(x: s*0.44, y: s*0.44, width: s*0.14, height: s*0.16))
            }
        case .emberSpark:
            return render(52) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s*0.6), radius: s*0.4, P.emberGold, 0.5)
                // Tapered: hot head, thin tail.
                poly(c, [CGPoint(x: s*0.5, y: s*0.14), CGPoint(x: s*0.60, y: s*0.56),
                         CGPoint(x: s*0.5, y: s*0.90), CGPoint(x: s*0.40, y: s*0.56)],
                     P.emberOrange)
                poly(c, [CGPoint(x: s*0.5, y: s*0.22), CGPoint(x: s*0.55, y: s*0.54),
                         CGPoint(x: s*0.5, y: s*0.74), CGPoint(x: s*0.45, y: s*0.54)],
                     P.emberPale)
            }
        case .emberCinder:
            return render(44) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.42, P.emberRed, 0.35)
                c.setFillColor(UIColor(red: 0.45, green: 0.13, blue: 0.10, alpha: 1).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.32, y: s*0.34, width: s*0.36, height: s*0.32))
                c.setFillColor(P.emberOrange.withAlphaComponent(0.85).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.40, y: s*0.40, width: s*0.17, height: s*0.15))
            }
        case .emberStreak:
            return render(60) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.44, P.emberOrange, 0.36)
                // A curved flame-like ribbon.
                let path = UIBezierPath()
                path.move(to: CGPoint(x: s*0.30, y: s*0.84))
                path.addQuadCurve(to: CGPoint(x: s*0.66, y: s*0.18),
                                  controlPoint: CGPoint(x: s*0.86, y: s*0.60))
                path.addQuadCurve(to: CGPoint(x: s*0.38, y: s*0.84),
                                  controlPoint: CGPoint(x: s*0.52, y: s*0.52))
                c.setFillColor(P.emberOrange.cgColor)
                c.addPath(path.cgPath); c.fillPath()
                c.setStrokeColor(P.emberPale.withAlphaComponent(0.7).cgColor)
                c.setLineWidth(s*0.022); c.setLineCap(.round)
                c.move(to: CGPoint(x: s*0.38, y: s*0.76))
                c.addQuadCurve(to: CGPoint(x: s*0.62, y: s*0.26),
                               control: CGPoint(x: s*0.72, y: s*0.56))
                c.strokePath()
            }
        case .emberFleck:
            return render(38) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.emberCoral, 0.6)
                c.setFillColor(P.emberCoral.cgColor)
                c.fillEllipse(in: CGRect(x: s*0.39, y: s*0.39, width: s*0.22, height: s*0.22))
                c.setFillColor(UIColor(white: 1, alpha: 0.9).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.45, y: s*0.44, width: s*0.09, height: s*0.09))
            }

        // ---------- TIDE ----------
        case .tideBubble:
            return render(56) { c, s in
                let r = CGRect(x: s*0.16, y: s*0.16, width: s*0.68, height: s*0.68)
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.48, P.aqua, 0.20)
                // Transparent body with a faint interior wash.
                c.setFillColor(P.paleBlue.withAlphaComponent(0.13).cgColor)
                c.fillEllipse(in: r)
                // Bright rim, brighter at the top-left where the light is.
                c.setStrokeColor(P.paleBlue.withAlphaComponent(0.85).cgColor)
                c.setLineWidth(s*0.035); c.strokeEllipse(in: r)
                c.setStrokeColor(P.turquoise.withAlphaComponent(0.55).cgColor)
                c.setLineWidth(s*0.02)
                c.addArc(center: CGPoint(x: s/2, y: s/2), radius: s*0.34,
                         startAngle: 0.35, endAngle: 2.1, clockwise: false)
                c.strokePath()
                // Specular highlight.
                c.setFillColor(UIColor(white: 1, alpha: 0.92).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.30, y: s*0.26, width: s*0.13, height: s*0.10))
            }
        case .tideDroplet:
            return render(46) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s*0.55), radius: s*0.40, P.pearl, 0.35)
                poly(c, [CGPoint(x: s*0.5, y: s*0.16), CGPoint(x: s*0.70, y: s*0.58),
                         CGPoint(x: s*0.5, y: s*0.84), CGPoint(x: s*0.30, y: s*0.58)],
                     P.pearl.withAlphaComponent(0.72))
                c.setFillColor(UIColor(white: 1, alpha: 0.95).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.42, y: s*0.50, width: s*0.10, height: s*0.13))
            }
        case .tideFleck:
            return render(38) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.aqua, 0.6)
                c.setFillColor(P.aqua.cgColor)
                c.fillEllipse(in: CGRect(x: s*0.40, y: s*0.40, width: s*0.20, height: s*0.20))
                c.setFillColor(P.pearl.cgColor)
                c.fillEllipse(in: CGRect(x: s*0.45, y: s*0.44, width: s*0.09, height: s*0.09))
            }
        case .tideShimmer:
            return render(56) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.42, P.paleBlue, 0.28)
                // Curved crescent of light.
                c.setStrokeColor(P.paleBlue.withAlphaComponent(0.9).cgColor)
                c.setLineWidth(s*0.06); c.setLineCap(.round)
                c.addArc(center: CGPoint(x: s/2, y: s/2), radius: s*0.30,
                         startAngle: 0.6, endAngle: 2.4, clockwise: false)
                c.strokePath()
                c.setStrokeColor(UIColor(white: 1, alpha: 0.8).cgColor)
                c.setLineWidth(s*0.022)
                c.addArc(center: CGPoint(x: s/2, y: s/2), radius: s*0.30,
                         startAngle: 0.9, endAngle: 1.9, clockwise: false)
                c.strokePath()
            }
        case .tideBiolum:
            return render(52) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.turquoise, 0.7)
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.24, P.pearl, 0.9)
                c.setFillColor(UIColor(white: 1, alpha: 1).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.45, y: s*0.45, width: s*0.10, height: s*0.10))
            }

        // A WAVE CREST seen in perspective: a long, shallow band, brightest
        // along its top lip where the water is breaking, feathered to nothing
        // at both ends so it never shows a hard edge against the painting.
        case .tideWaveCrest:
            return renderRect(512, 76) { c, w, h in
                // Built from overlapping soft blooms along an undulating
                // centre line, NOT a clipped rectangle: a clipped band shows
                // its cut ends at full alpha and reads as a scanline across
                // the painting (first attempt, 2026-09-22). Blooms are soft
                // in every direction, so the crest has no edge anywhere.
                foamLine(c, w: w, n: 58, cy: h * 0.40, wobble: h * 0.11,
                         waves: 3.0, radius: h * 0.30, jitter: h * 0.10,
                         P.pearl, UIColor.white, 0.08, 0.18)
                // The water colour dragged along under the foam.
                foamLine(c, w: w, n: 40, cy: h * 0.70, wobble: h * 0.09,
                         waves: 3.0, radius: h * 0.26, jitter: h * 0.06,
                         P.aqua, P.turquoise, 0.07, 0.06)
            }

        // The WASH that runs up the sand: wider, softer, no lip at all. A
        // sheet of water, not a line.
        case .tideFoamWash:
            return renderRect(512, 96) { c, w, h in
                foamLine(c, w: w, n: 34, cy: h * 0.52, wobble: h * 0.07,
                         waves: 2.0, radius: h * 0.46, jitter: h * 0.10,
                         P.pearl, UIColor.white, 0.06, 0.07)
            }

        // ---------- EMBER HEAT ----------
        // A rising plume. Tall, narrow, brightest low down where the air is
        // hottest, fading out entirely at the top.
        case .emberHeat:
            return renderRect(64, 180) { c, w, h in
                let colors = [P.emberGold.withAlphaComponent(0.00).cgColor,
                              P.emberGold.withAlphaComponent(0.30).cgColor,
                              P.emberOrange.withAlphaComponent(0.16).cgColor,
                              P.emberOrange.withAlphaComponent(0.00).cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors, locations: [0, 0.22, 0.62, 1]) {
                    c.saveGState()
                    // Taper: wide at the base, pinched at the top.
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: w * 0.06, y: h))
                    path.addQuadCurve(to: CGPoint(x: w * 0.34, y: 0),
                                      controlPoint: CGPoint(x: w * 0.02, y: h * 0.42))
                    path.addLine(to: CGPoint(x: w * 0.66, y: 0))
                    path.addQuadCurve(to: CGPoint(x: w * 0.94, y: h),
                                      controlPoint: CGPoint(x: w * 0.98, y: h * 0.42))
                    path.close()
                    c.addPath(path.cgPath); c.clip()
                    c.drawLinearGradient(g, start: CGPoint(x: 0, y: h),
                                         end: CGPoint(x: 0, y: 0), options: [])
                    c.restoreGState()
                }
            }

        // ---------- GLOW ----------
        case .glowShard:
            return render(54) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.48, P.glowYellow, 0.5)
                poly(c, [CGPoint(x: s*0.50, y: s*0.12), CGPoint(x: s*0.70, y: s*0.40),
                         CGPoint(x: s*0.62, y: s*0.84), CGPoint(x: s*0.38, y: s*0.84),
                         CGPoint(x: s*0.30, y: s*0.40)], P.glowYellow.withAlphaComponent(0.85))
                // Directional facet highlight down one side.
                poly(c, [CGPoint(x: s*0.50, y: s*0.14), CGPoint(x: s*0.66, y: s*0.42),
                         CGPoint(x: s*0.58, y: s*0.80), CGPoint(x: s*0.50, y: s*0.80)],
                     P.hot.withAlphaComponent(0.6))
                c.setStrokeColor(P.glowCyan.withAlphaComponent(0.6).cgColor)
                c.setLineWidth(s*0.02)
                c.move(to: CGPoint(x: s*0.50, y: s*0.14))
                c.addLine(to: CGPoint(x: s*0.50, y: s*0.82))
                c.strokePath()
            }
        case .glowDiamond:
            return render(46) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.46, P.glowCyan, 0.5)
                poly(c, [CGPoint(x: s*0.5, y: s*0.16), CGPoint(x: s*0.74, y: s*0.5),
                         CGPoint(x: s*0.5, y: s*0.84), CGPoint(x: s*0.26, y: s*0.5)],
                     P.glowCyan.withAlphaComponent(0.85))
                poly(c, [CGPoint(x: s*0.5, y: s*0.28), CGPoint(x: s*0.62, y: s*0.5),
                         CGPoint(x: s*0.5, y: s*0.72), CGPoint(x: s*0.38, y: s*0.5)],
                     P.hot.withAlphaComponent(0.75))
            }
        case .glowOrb:
            return render(52) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.glowYellow, 0.65)
                bloom(c, center: CGPoint(x: s*0.46, y: s*0.46), radius: s*0.22, P.hot, 0.9)
                c.setFillColor(UIColor(white: 1, alpha: 1).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.44, y: s*0.44, width: s*0.12, height: s*0.12))
            }
        case .glowPrism:
            return render(60) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.40, P.glowViolet, 0.34)
                c.saveGState(); c.translateBy(x: s/2, y: s/2); c.rotate(by: -0.6)
                // Thin streak with a faint colour split either side.
                c.setFillColor(P.glowCyan.withAlphaComponent(0.55).cgColor)
                c.fill(CGRect(x: -s*0.045, y: -s*0.44, width: s*0.05, height: s*0.88))
                c.setFillColor(P.glowViolet.withAlphaComponent(0.55).cgColor)
                c.fill(CGRect(x: s*0.005, y: -s*0.44, width: s*0.05, height: s*0.88))
                c.setFillColor(P.hot.withAlphaComponent(0.95).cgColor)
                c.fill(CGRect(x: -s*0.014, y: -s*0.40, width: s*0.028, height: s*0.80))
                c.restoreGState()
            }
        case .glowFlare:
            return render(64) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.glowYellow, 0.6)
                star(c, center: CGPoint(x: s/2, y: s/2), outer: s*0.46, inner: s*0.055,
                     points: 4, P.hot.withAlphaComponent(0.9))
                star(c, center: CGPoint(x: s/2, y: s/2), outer: s*0.26, inner: s*0.07,
                     points: 4, P.glowCyan.withAlphaComponent(0.8))
                c.setFillColor(UIColor(white: 1, alpha: 1).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.455, y: s*0.455, width: s*0.09, height: s*0.09))
            }

        // ---------- DUSK ----------
        case .duskFirefly:
            return render(54) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.violet, 0.6)
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.24, P.mutedGold, 0.8)
                c.setFillColor(UIColor(white: 1, alpha: 0.95).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.45, y: s*0.45, width: s*0.10, height: s*0.10))
            }
        case .duskFleck:
            return render(38) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.magenta, 0.6)
                c.setFillColor(P.magenta.cgColor)
                c.fillEllipse(in: CGRect(x: s*0.40, y: s*0.40, width: s*0.20, height: s*0.20))
                c.setFillColor(P.dustyPink.cgColor)
                c.fillEllipse(in: CGRect(x: s*0.45, y: s*0.44, width: s*0.09, height: s*0.09))
            }
        case .duskStarburst:
            return render(56) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.46, P.lavender, 0.5)
                star(c, center: CGPoint(x: s/2, y: s/2), outer: s*0.42, inner: s*0.10,
                     points: 5, P.lavender)
                star(c, center: CGPoint(x: s/2, y: s/2), outer: s*0.20, inner: s*0.06,
                     points: 5, UIColor(white: 1, alpha: 0.9))
            }
        case .duskPetal:
            return render(48) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.42, P.dustyPink, 0.28)
                c.saveGState(); c.translateBy(x: s/2, y: s/2); c.rotate(by: 0.7)
                c.translateBy(x: -s/2, y: -s/2)
                leaf(c, rect: CGRect(x: s*0.28, y: s*0.18, width: s*0.44, height: s*0.64),
                     bend: s*0.04, P.dustyPink.withAlphaComponent(0.8))
                leaf(c, rect: CGRect(x: s*0.36, y: s*0.28, width: s*0.28, height: s*0.42),
                     bend: 0, P.magenta.withAlphaComponent(0.4))
                c.restoreGState()
            }
        case .duskComet:
            return render(64) { c, s in
                bloom(c, center: CGPoint(x: s*0.68, y: s*0.34), radius: s*0.34, P.violet, 0.45)
                // Short fading tail behind a bright head.
                let path = UIBezierPath()
                path.move(to: CGPoint(x: s*0.72, y: s*0.28))
                path.addQuadCurve(to: CGPoint(x: s*0.18, y: s*0.80),
                                  controlPoint: CGPoint(x: s*0.36, y: s*0.42))
                path.addQuadCurve(to: CGPoint(x: s*0.78, y: s*0.36),
                                  controlPoint: CGPoint(x: s*0.46, y: s*0.62))
                c.setFillColor(P.lavender.withAlphaComponent(0.5).cgColor)
                c.addPath(path.cgPath); c.fillPath()
                bloom(c, center: CGPoint(x: s*0.72, y: s*0.30), radius: s*0.16,
                      UIColor(white: 1, alpha: 1), 0.95)
            }

        // ---------- STONE ----------
        case .stoneFleck:
            return render(42) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.46, P.amber, 0.45)
                poly(c, [CGPoint(x: s*0.50, y: s*0.26), CGPoint(x: s*0.68, y: s*0.46),
                         CGPoint(x: s*0.54, y: s*0.72), CGPoint(x: s*0.34, y: s*0.54)],
                     P.amber)
                c.setFillColor(P.warmCream.cgColor)
                c.fillEllipse(in: CGRect(x: s*0.45, y: s*0.42, width: s*0.11, height: s*0.11))
            }
        case .stoneQuartz:
            return render(52) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.44, P.warmCream, 0.4)
                poly(c, [CGPoint(x: s*0.48, y: s*0.14), CGPoint(x: s*0.70, y: s*0.44),
                         CGPoint(x: s*0.58, y: s*0.84), CGPoint(x: s*0.34, y: s*0.66),
                         CGPoint(x: s*0.32, y: s*0.34)], P.quartz.withAlphaComponent(0.72))
                poly(c, [CGPoint(x: s*0.48, y: s*0.18), CGPoint(x: s*0.64, y: s*0.46),
                         CGPoint(x: s*0.52, y: s*0.60)], UIColor(white: 1, alpha: 0.7))
            }
        case .stoneDust:
            return render(44) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.warmCream, 0.55)
                c.setFillColor(P.warmCream.withAlphaComponent(0.9).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.42, y: s*0.42, width: s*0.16, height: s*0.16))
            }
        case .stoneMote:
            return render(38) { c, s in
                // A mote has to separate from a SUNLIT meadow, where a pale
                // blob is the same VALUE as the ground — which is why the
                // cream `stoneDust` was invisible there. A faint cool shadow
                // just outside the body gives it an edge. No sparkle, no
                // glow, no core highlight: Stone stays the quietest family.
                //
                // Built from offset lobes rather than concentric circles, so
                // the silhouette is irregular and the edge fades unevenly —
                // clean rings read as UI dots, not dust.
                let lobes: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.500, 0.500, 0.145),
                    (0.575, 0.535, 0.098),
                    (0.437, 0.552, 0.090),
                    (0.530, 0.435, 0.080),
                    (0.432, 0.462, 0.066),
                ]
                for (fx, fy, r) in lobes {
                    bloom(c, center: CGPoint(x: s*fx, y: s*fy),
                          radius: s*r*2.6, P.taupe, 0.16)
                }
                for (fx, fy, r) in lobes {
                    bloom(c, center: CGPoint(x: s*fx, y: s*fy),
                          radius: s*r*1.5, P.warmCream, 0.26)
                }
                for (fx, fy, r) in lobes {
                    c.setFillColor(P.warmCream.withAlphaComponent(0.34).cgColor)
                    c.fillEllipse(in: CGRect(x: s*(fx-r*0.62), y: s*(fy-r*0.62),
                                             width: s*r*1.24, height: s*r*1.24))
                }
            }
        case .stoneSpeck:
            return render(36) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.amber, 0.65)
                c.setFillColor(P.amber.cgColor)
                c.fillEllipse(in: CGRect(x: s*0.41, y: s*0.41, width: s*0.18, height: s*0.18))
                c.setFillColor(UIColor(white: 1, alpha: 0.95).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.46, y: s*0.45, width: s*0.08, height: s*0.08))
            }
        case .stoneShard:
            return render(48) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.42, P.taupe, 0.30)
                poly(c, [CGPoint(x: s*0.52, y: s*0.20), CGPoint(x: s*0.72, y: s*0.52),
                         CGPoint(x: s*0.46, y: s*0.78), CGPoint(x: s*0.30, y: s*0.44)],
                     P.taupe.withAlphaComponent(0.85))
                poly(c, [CGPoint(x: s*0.52, y: s*0.24), CGPoint(x: s*0.66, y: s*0.52),
                         CGPoint(x: s*0.50, y: s*0.56)], P.warmCream.withAlphaComponent(0.85))
            }

        // ---------- STARLIGHT ----------
        case .starRadiant:
            return render(60) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.starBlue, 0.55)
                star(c, center: CGPoint(x: s/2, y: s/2), outer: s*0.46, inner: s*0.075,
                     points: 4, P.starWhite)
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.14, P.starWhite, 0.95)
            }
        case .starSparkle:
            return render(52) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.44, P.starGold, 0.45)
                star(c, center: CGPoint(x: s/2, y: s/2), outer: s*0.40, inner: s*0.11,
                     points: 6, P.starWhite.withAlphaComponent(0.92))
                c.setFillColor(P.starGold.cgColor)
                c.fillEllipse(in: CGRect(x: s*0.455, y: s*0.455, width: s*0.09, height: s*0.09))
            }
        case .starComet:
            return render(68) { c, s in
                // Tail first, so the head sits on top of it.
                let path = UIBezierPath()
                path.move(to: CGPoint(x: s*0.74, y: s*0.26))
                path.addQuadCurve(to: CGPoint(x: s*0.16, y: s*0.78),
                                  controlPoint: CGPoint(x: s*0.34, y: s*0.40))
                path.addQuadCurve(to: CGPoint(x: s*0.80, y: s*0.34),
                                  controlPoint: CGPoint(x: s*0.46, y: s*0.60))
                c.setFillColor(P.starBlue.withAlphaComponent(0.45).cgColor)
                c.addPath(path.cgPath); c.fillPath()
                bloom(c, center: CGPoint(x: s*0.74, y: s*0.28), radius: s*0.22, P.starWhite, 0.85)
                star(c, center: CGPoint(x: s*0.74, y: s*0.28), outer: s*0.17, inner: s*0.04,
                     points: 4, P.starWhite)
            }
        case .starDot:
            return render(38) { c, s in
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.5, P.starBlue, 0.6)
                c.setFillColor(UIColor(white: 1, alpha: 1).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.43, y: s*0.43, width: s*0.14, height: s*0.14))
            }
        case .starPinprick:
            return render(24) { c, s in
                // Almost no bloom: just enough to keep the point from
                // aliasing, and a hard white core barely a pixel across at
                // ambient scale. Everything that made the old star read as a
                // firefly lived in its halo.
                // BRIGHTNESS, NOT FOOTPRINT (2026-09-23). Node alpha was
                // already maxed at peak 1.00, so further contrast had to come
                // from the texture emitting more light. The halo RADIUS is
                // deliberately unchanged at 0.30 and the core stays 0.12 wide
                // — only their intensity goes up, so the star cannot grow
                // back into the blob this replaced.
                bloom(c, center: CGPoint(x: s/2, y: s/2), radius: s*0.30,
                      P.starBlue, 0.52)
                c.setFillColor(UIColor(white: 1, alpha: 1.0).cgColor)
                c.fillEllipse(in: CGRect(x: s*0.44, y: s*0.44,
                                         width: s*0.12, height: s*0.12))
            }
        case .starCluster:
            return render(64) { c, s in
                // 2–4 tiny lights joined by extremely faint lines.
                let pts = [CGPoint(x: s*0.22, y: s*0.68), CGPoint(x: s*0.46, y: s*0.30),
                           CGPoint(x: s*0.74, y: s*0.52), CGPoint(x: s*0.58, y: s*0.80)]
                c.setStrokeColor(P.starBlue.withAlphaComponent(0.30).cgColor)
                c.setLineWidth(s*0.014)
                c.move(to: pts[0])
                for p in pts.dropFirst() { c.addLine(to: p) }
                c.strokePath()
                for (i, p) in pts.enumerated() {
                    let r = s * (i == 1 ? 0.055 : 0.036)
                    bloom(c, center: p, radius: r * 3.2, P.starWhite, 0.6)
                    c.setFillColor(UIColor(white: 1, alpha: 1).cgColor)
                    c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2))
                }
            }
        }
    }
}
