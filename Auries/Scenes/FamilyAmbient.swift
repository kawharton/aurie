import SpriteKit
import UIKit

/// ONE configuration-driven ambient-life system for the family environments.
///
/// Why a config and not six implementations: the six (seven, with Stone)
/// environments want the SAME handful of behaviours at different densities
/// and speeds. So there are exactly five effect kinds below, and each family
/// is a list of them. Adding a family is data, not code.
///
/// Why it is not a particle engine: `ParticleField` already owns pooled
/// particle motion, and `FamilyParticleArt` already draws every motif this
/// needs (pollen, fireflies, cinders, shimmer, flares, star dots, comets).
/// This system only places and animates a small number of sprites using
/// those textures with SKActions.
///
/// ARCHITECTURAL NOTE (2026-09-21 audit): every family background is a
/// SINGLE FLAT PAINTING — `mid`/`ground`/`fore` slices are optional and
/// unused, so no painted feature (a fern, a crystal, the waterline, a
/// volcanic vent) is addressable as a node. Every effect here is therefore
/// placed by NORMALIZED ZONE, never attached to art.
///
/// The three primaries that were open scope are now implemented WITHOUT
/// overlay art or a shader (2026-09-22 visibility pass):
///   · Tide shoreline waves — wide crest bands slid shoreward from the
///     waterline. The waterline is not a node, so `fromY`/`toY` were MEASURED
///     off the painting (surf sits at scene_y +0.26...+0.33) and are stated
///     as constants in the config. If the Tide master is ever repainted,
///     re-measure them.
///   · Ember heat — tapered convection plumes that rise and waver.
///   · Moss vegetation — drifting leaves rather than a sway, since no painted
///     fern is addressable.
/// Each replaced an effect that failed the only test that matters: whether a
/// viewer can tell something is moving without being told to look.
enum FamilyAmbient {

    // MARK: - Zones

    /// Normalized scene rects (0…1, origin bottom-left) an effect may use.
    /// The CENTRE COLUMN is excluded everywhere so the environment frames
    /// Aurie instead of competing: prominent objects avoid the central ~44%
    /// of width and the creature's body band.
    enum Zone {
        /// Left and right thirds, full height above the very bottom.
        case sides
        /// Upper band, full width — safely above Aurie's face.
        case upper
        /// Upper corners only: the quietest, most distant placement.
        case upperSides
        /// A thin horizontal band for distant water shimmer.
        case waterBand
        /// Spread across nearly the whole frame, unlike `.sides` which packs
        /// everything into two narrow columns. A point landing in the
        /// creature's column is pushed ABOVE or BELOW the body band rather
        /// than dropped, so the distribution stays even without anything
        /// crowding Aurie's silhouette.
        case broad
        /// SKY ONLY. Measured off the Starlight master: open sky is just
        /// scene_y +0.35...+0.50, and reliably unbroken only above +0.43
        /// between x 0.20 and 0.86 — mountain peaks intrude either side
        /// below that. `.upper` reaches down to +0.10, which is why the old
        /// "stars" sat on the path and beside the creature (2026-09-22).
        case sky

        /// Deterministic point for index `i` of `total`, using a golden-ratio
        /// walk so placement is stable across launches but never a visible
        /// grid. `jitter` is derived from the index, not `random`, so a scene
        /// composes identically every time it is rebuilt.
        func point(index i: Int, of total: Int, in size: CGSize) -> CGPoint {
            let t = total > 1 ? CGFloat(i) / CGFloat(total - 1) : 0.5
            let phi = CGFloat((Double(i) * 0.6180339887).truncatingRemainder(dividingBy: 1))
            // Second walk, INDEPENDENT of phi — see the note in `.sky` about
            // why 0.3819660113 cannot be used here.
            let q = CGFloat((Double(i) * 0.7548776662).truncatingRemainder(dividingBy: 1))
            let w = size.width, h = size.height
            var nx: CGFloat, ny: CGFloat
            switch self {
            case .sides:
                // Alternate sides; keep clear of the centre column.
                let left = i % 2 == 0
                nx = left ? 0.06 + phi * 0.22 : 0.72 + phi * 0.22
                ny = 0.18 + t * 0.66
            case .upper:
                nx = 0.05 + phi * 0.90
                ny = 0.60 + (phi * 0.9 + t * 0.1).truncatingRemainder(dividingBy: 1) * 0.36
            case .upperSides:
                let left = i % 2 == 0
                nx = left ? 0.04 + phi * 0.24 : 0.72 + phi * 0.24
                ny = 0.62 + t * 0.32
            case .waterBand:
                nx = 0.06 + phi * 0.88
                ny = 0.54 + t * 0.10
            case .broad:
                nx = 0.04 + phi * 0.92
                ny = 0.10 + q * 0.82
                if nx > 0.34, nx < 0.66, ny > 0.30, ny < 0.64 {
                    let t = (ny - 0.30) / 0.34          // 0...1 in the band
                    ny = t < 0.5 ? 0.30 - t * 0.40
                                 : 0.64 + (t - 0.5) * 0.56
                }
            case .sky:
                // A SECOND irrational walk for height, so x and y are not
                // correlated and the points never line up along a diagonal.
                // Sky is ONLY what is above the mountain ridge, and the
                // ridge is not level: MEASURED per column it dips to +0.417
                // in the valley (x ~= .45) and rises to +0.461 at both edges.
                // An earlier blue-dominance test called the mountains sky —
                // they are blue-lit at night — and stars landed on the
                // hillside. Stars now fill the WEDGE between that line and
                // the top of frame, which spreads them in both axes instead
                // of along one strip.
                // x uses the FULL width; the wedge floor below already rises
                // per column, so an edge star simply sits higher. Coupling
                // the x-spread to q instead made the wide-and-high corner
                // vanishingly rare and pinned everything to the left half.
                nx = 0.08 + phi * 0.84
                let edge = min(1, abs(nx - 0.45) / 0.30)
                let ridge = 0.417 + 0.044 * edge
                let floorY = ridge + 0.012            // clear of the skyline
                ny = (0.5 + floorY) + q * (0.497 - floorY)
            }
            return CGPoint(x: (nx - 0.5) * w, y: (ny - 0.5) * h)
        }
    }

    // MARK: - Effects

    /// The five behaviours every family is composed from.
    enum Effect {
        /// Small drifting background particles (pollen, ash, dust, shimmer).
        /// Slow upward/diagonal travel, very low opacity.
        case motes(count: Int, motif: FamilyParticleArt.Motif, zone: Zone,
                   alpha: CGFloat, scale: CGFloat,
                   travel: ClosedRange<Double>, horizontal: Bool)
        /// Stationary points that pulse brightness (crystals, stars). Never
        /// blinks fully off, phases are staggered so only a minority peak.
        case twinkle(count: Int, motif: FamilyParticleArt.Motif, zone: Zone,
                     base: CGFloat, peak: CGFloat, scale: CGFloat,
                     period: ClosedRange<Double>, scalePulse: CGFloat)
        /// A brief soft sparkle somewhere in the zone, occasionally.
        case glint(every: ClosedRange<Double>, motif: FamilyParticleArt.Motif,
                   zone: Zone, alpha: CGFloat)
        /// Local wanderers that fade up and down while drifting inside a
        /// small radius (fireflies). `visible` caps how many glow at once.
        case wander(count: Int, visible: Int, motif: FamilyParticleArt.Motif,
                    zone: Zone, radius: CGFloat, alpha: CGFloat,
                    cycle: ClosedRange<Double>)
        /// A rare visitor that enters, crosses part of the zone and leaves.
        case visitor(kind: Visitor, every: ClosedRange<Double>,
                     duration: ClosedRange<Double>, zone: Zone)
        /// SHORELINE SURF, built from the PAINTING ITSELF. Narrow
        /// horizontal bands of the existing surf are duplicated straight out
        /// of the background texture, laid back exactly over their source and
        /// given a small drift. Nothing new is drawn, so the water can never
        /// look like a mark added on top of the art — the earlier
        /// hand-painted foam bands always did, however soft they got.
        /// `topY`/`bottomY` bound the shoreline zone (scene-height fractions
        /// from centre, MEASURED off the painting). Each band gets its own
        /// speed and phase so the surf never pulses in unison.
        /// `xRange` confines a group to a stretch of the shoreline, as
        /// fractions of scene width. Needed because the rocks are not evenly
        /// spread: the lower shoreline is open only between x 0.24 and 0.62
        /// (measured), so the wash there can be animated while the rocky
        /// stretches either side stay perfectly still.
        /// `frontBoost` adds travel to the NEAREST band only, on a cubic so
        /// the far and middle bands are left essentially untouched. Raising
        /// `lift` instead would scale the whole group and flatten the depth
        /// cue — the point is that the front foam edge runs further than the
        /// water behind it, not that everything moves more.
        /// `fade` is the horizontal feather width, as a fraction of scene
        /// width. It has to be per-group: the open water spans half the
        /// frame and can afford a wide dissolve, while the one rock-free
        /// stretch of shore is barely 0.13 wide and a 0.07 feather at each
        /// end would reach the rocks either side of it.
        /// `vFade` is the VERTICAL fade, as a fraction of the slice height
        /// at each end. 0.34 is the generous default that keeps a band from
        /// showing its edge; a thin band squeezed between rock above and
        /// below needs a tighter value or its tail spills onto them.
        case surfSlices(bands: Int, topY: CGFloat, bottomY: CGFloat,
                        xRange: ClosedRange<CGFloat>, fade: CGFloat,
                        vFade: CGFloat,
                        drift: CGFloat, lift: CGFloat, frontBoost: CGFloat,
                        period: ClosedRange<Double>, alpha: CGFloat)
        /// RISING HEAT. Tall tapered plumes that rise, waver horizontally and
        /// fade out — convection, not particles.
        case heat(count: Int, zone: Zone, alpha: CGFloat,
                  rise: ClosedRange<Double>, scale: CGFloat)
        /// FALLING. A one-way descent with sway and slow tumble, respawning
        /// at the top. `motes` oscillates over a short span, which at ambient
        /// speeds is ~6pt/sec and reads as stillness (measured: moss ambient
        /// contributed 0.49% of frame change, indistinguishable from none).
        /// A leaf that actually falls crosses the frame and reads instantly.
        case drift(count: Int, motif: FamilyParticleArt.Motif, zone: Zone,
                   alpha: CGFloat, scale: CGFloat,
                   fall: ClosedRange<Double>, sway: CGFloat, spin: Bool)
    }

    enum Visitor {
        /// Moss's decorative butterfly. Reuses the (now shelf-retired) toy
        /// art. DECORATIVE ONLY — never hit-testable, so we never teach the
        /// player to tap background butterflies.
        case butterfly
        /// Starlight's shooting star: a short streak across the upper sky.
        case shootingStar
    }

    // MARK: - Per-family configuration

    /// Counts and timings are the reviewed values; see the pass report.
    static func effects(for family: AuraFamily) -> [Effect] {
        switch family {

        // MOSS — drifting GREEN SPORES. The falling leaves that used to
        // lead this were removed 2026-09-25: at 10 large tumbling sprites
        // crossing the whole frame they were too much going on, which is the
        // opposite failure to the original too-subtle pass. Spores carry the
        // same "the forest is alive" read with far less event — they are
        // small, slow, and never cross the creature.
        case .moss:
            return [
                .motes(count: 10, motif: .mossSpore, zone: .sides,
                       alpha: 0.80, scale: 0.85, travel: 9...16, horizontal: false),
                // A little gold pollen still, for warmth in the light shafts.
                .motes(count: 3, motif: .mossPollen, zone: .sides,
                       alpha: 0.55, scale: 0.70, travel: 10...15, horizontal: false),
                // A butterfly now and then, which the creature notices and
                // follows with its eyes (see `onVisitorMove` -> CreatureScene).
                // Rare on purpose: it should feel like luck, not a loop.
                .visitor(kind: .butterfly, every: 150...300,
                         duration: 11...16, zone: .sides),
            ]

        // GLOW — twinkling crystal points, an occasional glint, few motes.
        case .glow:
            return [
                // Bigger, brighter, and they pulse in SIZE as well as
                // brightness — a crystal catching the light, not a dot
                // dimming. base 0.22->0.30 and peak 0.78->1.00 so the swing
                // is visible in motion rather than only in a still.
                .twinkle(count: 8, motif: .glowOrb, zone: .sides,
                         base: 0.30, peak: 1.00, scale: 1.05,
                         period: 1.6...3.4, scalePulse: 0.22),
                .glint(every: 2...5, motif: .glowFlare, zone: .sides,
                       alpha: 0.90),
                .motes(count: 5, motif: .glowFlare, zone: .upperSides,
                       alpha: 0.40, scale: 0.55, travel: 10...16, horizontal: false),
            ]

        // TIDE — surf rolling ashore. This REPLACES the old `tideShimmer`
        // crescents (2026-09-22), which were abstract white arcs placed by
        // the `.waterBand` zone at scene_y +0.04...+0.14 — measured against
        // the painting, the surf is actually at +0.26...+0.33, so every mark
        // landed on DRY SAND in the middle of the frame and read as random
        // squiggles. Bands now start at the painted waterline and travel
        // shoreward, which is the one motion that says "ocean".
        case .tide:
            return [
                // Bands sit in the OPEN WATER between the horizon (+0.347)
                // and the wet sand — ABOVE the shoreline rocks, which start
                // around +0.27 and ghost badly when duplicated. Drift is
                // small for the same reason: water tolerates a duplicate
                // offset from itself, hard edges do not.
                // Four groups, each fitted to the open span MEASURED at its
                // OWN height. Scanning row by row for "how far right is this
                // row clear" is what this needs — a single scan over a tall
                // slice averages the boulder tops into rows that are actually
                // open, which is how the right side kept coming out dead.
                //   y +.240..+.290  clear only to x ~.63 (boulder field)
                //   y +.295..+.315  clear to x ~.78
                //   y +.318..+.332  clear to x ~.95   <- carries the right
                //   y +.335..+.345  clear only to x ~.53 (distant rocks)
                //
                // NO FAR-WATER BAND. The horizon is at scene_y +0.352
                // (measured: R-B flips from -37 to +91 between .348 and
                // .352), and rows .335-.345 are blocked by distant rocks, so
                // a band up there covers rock and SKY rather than sea — it
                // was visibly animating the sky on the left (2026-09-25).
                // Nothing above +0.332 moves.
                //
                // MAIN WATER and RIGHT WATER share a period and phase so the
                // two halves of the bay move as ONE body of water. They are
                // separate groups only because the boulder cluster at
                // x .62-.70 forces a gap in x, and because the right side's
                // clear water starts a little higher.
                .surfSlices(bands: 2, topY: 0.330, bottomY: 0.296,
                            xRange: 0.24...0.56, fade: 0.065, vFade: 0.34,
                            drift: 8, lift: 5, frontBoost: 0,
                            period: 5.6...5.6, alpha: 0.66),
                .surfSlices(bands: 2, topY: 0.330, bottomY: 0.306,
                            xRange: 0.62...0.72, fade: 0.04, vFade: 0.34,
                            drift: 8, lift: 5, frontBoost: 0,
                            period: 5.6...5.6, alpha: 0.68),
                // FAR RIGHT — the y .320-.331 slot is the only place the
                // water runs clear to x .95. Small travel so its tail stays
                // inside the slot; same period, so it moves with the rest.
                .surfSlices(bands: 1, topY: 0.331, bottomY: 0.320,
                            xRange: 0.80...0.96, fade: 0.035, vFade: 0.20,
                            drift: 4, lift: 2, frontBoost: 0,
                            period: 5.6...5.6, alpha: 0.78),
                // SHORELINE — the shore is crowded: the only rock-free
                // stretch at this height is x .467-.600, so the window is
                // narrow and the feather tight.
                .surfSlices(bands: 2, topY: 0.292, bottomY: 0.252,
                            xRange: 0.50...0.565, fade: 0.04, vFade: 0.34,
                            drift: 6, lift: 8, frontBoost: 0,
                            period: 4.4...6.8, alpha: 0.70),
            ]

        // STARLIGHT — twinkling stars + a very rare shooting star.
        // STARLIGHT — the most restrained family. Rebuilt 2026-09-22: the
        // previous treatment was 16 `starDot`s at scale 0.80 with a 30% size
        // pulse in the `.upper` zone, which reads as drifting fireflies
        // scattered over the path and the creature, not as a night sky.
        // Everything here is deliberately minimal: a handful of fixed
        // pinpricks in the sky band, brightening and dimming slowly, plus one
        // occasional brighter twinkle. Nothing travels.
        case .starlight:
            return [
                // Visibility comes from the SWING, not from size or travel.
                // At base 0.26 -> peak 0.70 the measured change at a star was
                // only 4-8 luminance levels out of 255 (~2%), which against a
                // sky that already has painted stars in it is indistinguish-
                // able from nothing. Dropping the floor and raising the
                // ceiling nearly doubles the swing (0.44 -> 0.82) while
                // leaving each star DIMMER at rest than before. `scale` and
                // `scalePulse` are deliberately untouched.
                // base 0.18 -> 0.10: a lower floor widens the contrast from
                // the only end that still has room, and leaves the star
                // fainter at rest rather than brighter overall.
                .twinkle(count: 11, motif: .starPinprick, zone: .sky,
                         base: 0.10, peak: 1.00, scale: 0.55,
                         period: 3.4...6.2, scalePulse: 0.0),
                // The occasional brighter one. `glint` is stationary — it
                // fades up and down in place, it does not cross the sky.
                .glint(every: 9...17, motif: .starPinprick, zone: .sky,
                       alpha: 1.00),
            ]

        // EMBER — rising heat is the PRIMARY now (2026-09-22). Real optical
        // shimmer needs a displacement shader over the background; tapered
        // convection plumes rising and wavering communicate the same thing
        // with no shader and no risk to the painting underneath.
        case .ember:
            return [
                .heat(count: 4, zone: .sides, alpha: 0.42,
                      rise: 4.5...7.5, scale: 1.0),
                .motes(count: 7, motif: .emberFleck, zone: .sides,
                       alpha: 0.60, scale: 0.62, travel: 6...10, horizontal: false),
                .motes(count: 3, motif: .emberCinder, zone: .sides,
                       alpha: 0.90, scale: 0.72, travel: 5...9, horizontal: false),
            ]

        // DUSK — wandering evening fireflies.
        case .dusk:
            return [
                .wander(count: 8, visible: 4, motif: .duskFirefly,
                        zone: .sides, radius: 58, alpha: 1.00, cycle: 5...9),
            ]

        // STONE — deliberately the quietest: faint dust in still air.
        // No sparkle, no glow, no whimsy.
        case .stone:
            // Still the quietest family — but 0.22 alpha at 0.44 scale was
            // below the threshold of "is that moving?". Lifted just far
            // enough to be perceptible; deliberately NOT to parity with the
            // others, and still no sparkle, glow or whimsy.
            // `stoneDust` is warm CREAM, which is the same value as a sunlit
            // alpine meadow — an amplified frame diff showed the motes were
            // moving correctly and were simply invisible. `stoneSpeck` is
            // amber, so it carries contrast against the grass without
            // becoming a sparkle.
            return [
                .motes(count: 14, motif: .stoneMote, zone: .broad,
                       alpha: 0.80, scale: 1.25, travel: 11...17, horizontal: false),
            ]
        }
    }
}

/// The node that hosts one family's ambient life. Owns every action it
/// creates, so `teardown()` (or simply removing it with the scene) leaves
/// nothing running.
final class FamilyAmbientNode: SKNode {

    /// Reports a visitor's live position to the scene, and `nil` when it
    /// leaves. This is the ONLY channel between ambient life and the
    /// creature: the sprites themselves stay decorative and untouchable.
    var onVisitorMove: ((CGPoint?) -> Void)?

    private let sceneSize: CGSize
    /// The background painting and its placement, for `surfSlices`. Optional
    /// because the grey-box environment has no artwork to duplicate.
    private let skyLayer: (texture: SKTexture, scale: CGFloat, centerY: CGFloat)?
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// CAPTURE AID ONLY (DEBUG, `AURIE_AMBIENT_FAST=1`). Rare-by-design
    /// effects — the shooting star, the glint — are tuned to feel like luck,
    /// which means a 10-second recording usually contains none. This shortens
    /// only the WAITING, never a production default and never the effect's own
    /// motion, so a video shows the same animation the player eventually sees.
    private func captureInterval(_ r: ClosedRange<Double>) -> ClosedRange<Double> {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AURIE_AMBIENT_FAST"] == "1" {
            return 1.5...3.0
        }
        #endif
        return r
    }

    init(family: AuraFamily, sceneSize: CGSize,
         skyLayer: (texture: SKTexture, scale: CGFloat, centerY: CGFloat)? = nil) {
        self.sceneSize = sceneSize
        self.skyLayer = skyLayer
        super.init()
        // Behind the creature, above the background painting.
        zPosition = -40
        name = "familyAmbient"
        for effect in FamilyAmbient.effects(for: family) {
            build(effect, family: family)
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["AURIE_AMBIENT_LOG"] == "1" {
            NSLog("AURIE_AMBIENT family=%@ sceneSize=%.0fx%.0f children=%d reduceMotion=%@",
                  family.rawValue, sceneSize.width, sceneSize.height,
                  children.count, reduceMotion ? "YES" : "NO")
            // EVERY child, with its position as a fraction of scene height.
            // Pixel differencing cannot answer "is anything outside the sky?"
            // — Aurie's bob and the greeting bubble swamp it — but the scene
            // graph answers it exactly.
            for c in children {
                NSLog("AURIE_AMBIENT  child x=%.2f y=%+.3f alpha=%.2f %@",
                      c.position.x / sceneSize.width,
                      c.position.y / sceneSize.height,
                      c.alpha, String(describing: type(of: c)))
            }
        }
        #endif
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    /// A soft-edged duplicate of one horizontal strip of the background.
    ///
    /// The feather is baked into the IMAGE. It used to be an `SKCropNode`
    /// mask, which does not work: SpriteKit masks by ALPHA TEST, not by
    /// blending, so a gradient mask still yields a HARD edge. The band
    /// boundaries were therefore always straight lines — invisible only
    /// while the bands barely moved. Raising the front band's travel slid
    /// enough content across them to expose the rectangle, which reads as
    /// the headland rocks moving (2026-09-24).
    private static func featheredSlice(from texture: SKTexture,
                                       vLow: CGFloat, vHigh: CGFloat,
                                       xRange: ClosedRange<CGFloat>,
                                       fade: CGFloat,
                                       vFade: CGFloat) -> SKTexture? {
        let full = texture.cgImage()
        let pxW = CGFloat(full.width), pxH = CGFloat(full.height)
        // SKTexture coordinates are bottom-left origin; CGImage is top-left.
        let rect = CGRect(x: 0, y: (1 - vHigh) * pxH,
                          width: pxW, height: (vHigh - vLow) * pxH).integral
        guard rect.height >= 2, let cropped = full.cropping(to: rect) else { return nil }
        let size = CGSize(width: rect.width, height: rect.height)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: size))
            c.setBlendMode(.destinationIn)
            // Top and bottom dissolve into the untouched painting.
            // Per-group, NOT a fixed fraction: making this proportional for
            // every band at once sharpened them all, which widened their
            // full-strength area and woke rocks across the whole frame
            // (2026-09-25). Only the thin far-right band wants a tight fade.
            let edge = min(max(vFade, 0.05), 0.45)
            let vert = [UIColor(white: 1, alpha: 0).cgColor,
                        UIColor(white: 1, alpha: 1).cgColor,
                        UIColor(white: 1, alpha: 1).cgColor,
                        UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: vert,
                                  locations: [0, edge, 1 - edge, 1]) {
                c.drawLinearGradient(g, start: .zero,
                                     end: CGPoint(x: 0, y: size.height),
                                     options: [])
            }
            // Ends dissolve too, so a band never reaches a headland. Stops
            // span the FULL width: a gradient that stops short leaves the
            // rest of the image untouched, i.e. fully opaque.
            let a = max(0, xRange.lowerBound - fade)
            let b = min(xRange.lowerBound + fade, xRange.upperBound)
            let cc = max(xRange.upperBound - fade, b)
            let dd = min(1, xRange.upperBound + fade)
            let ends = [UIColor(white: 1, alpha: 0).cgColor,
                        UIColor(white: 1, alpha: 0).cgColor,
                        UIColor(white: 1, alpha: 1).cgColor,
                        UIColor(white: 1, alpha: 1).cgColor,
                        UIColor(white: 1, alpha: 0).cgColor,
                        UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: ends, locations: [0, a, b, cc, dd, 1]) {
                c.drawLinearGradient(g, start: .zero,
                                     end: CGPoint(x: size.width, y: 0),
                                     options: [])
            }
        }
        return SKTexture(image: image)
    }

    /// Stop and drop everything. Safe to call more than once.
    func teardown() {
        onVisitorMove?(nil)
        onVisitorMove = nil
        removeAllActions()
        for child in children { child.removeAllActions() }
        removeAllChildren()
        removeFromParent()
    }

    // MARK: - Builders

    private func build(_ effect: FamilyAmbient.Effect, family: AuraFamily) {
        switch effect {
        case let .motes(count, motif, zone, alpha, scale, travel, horizontal):
            // Reduce Motion: far fewer, and they hold still.
            let n = reduceMotion ? max(2, count / 4) : count
            for i in 0 ..< n {
                let s = sprite(motif, alpha: alpha, scale: scale)
                s.position = zone.point(index: i, of: n, in: sceneSize)
                addChild(s)
                guard !reduceMotion else { continue }
                let span = travel.lowerBound
                    + (travel.upperBound - travel.lowerBound)
                    * Double(i % 5) / 4.0
                let dx: CGFloat = horizontal ? 46 : 12
                let dy: CGFloat = horizontal ? 0 : 58
                let out = SKAction.moveBy(x: dx, y: dy, duration: span)
                out.timingMode = .easeInEaseOut
                let back = out.reversed()
                // Phase offset per mote so the field never resets together.
                s.run(.sequence([
                    .wait(forDuration: Double(i) * span / Double(max(n, 1))),
                    .repeatForever(.sequence([out, back])),
                ]))
            }

        case let .twinkle(count, motif, zone, base, peak, spriteScale,
                          period, scalePulse):
            let n = count
            for i in 0 ..< n {
                let s = sprite(motif, alpha: base, scale: spriteScale)
                s.position = zone.point(index: i, of: n, in: sceneSize)
                addChild(s)
                let dur = period.lowerBound
                    + (period.upperBound - period.lowerBound)
                    * Double(i % 7) / 6.0
                // Reduce Motion: a very slow, shallow brightness drift only.
                let up = SKAction.fadeAlpha(to: reduceMotion
                                            ? base + (peak - base) * 0.35 : peak,
                                            duration: reduceMotion ? dur * 2 : dur)
                up.timingMode = .easeInEaseOut
                let down = SKAction.fadeAlpha(to: base,
                                              duration: reduceMotion ? dur * 2 : dur)
                down.timingMode = .easeInEaseOut
                var pulse: [SKAction] = [up, down]
                if scalePulse > 0, !reduceMotion {
                    let grow = SKAction.scale(by: 1 + scalePulse, duration: dur)
                    grow.timingMode = .easeInEaseOut
                    pulse = [.group([up, grow]), .group([down, grow.reversed()])]
                }
                // Stagger so only a minority are near peak at any moment.
                s.run(.sequence([
                    .wait(forDuration: Double(i) * dur / Double(max(n, 1)) * 1.7),
                    .repeatForever(.sequence(pulse)),
                ]))
            }

        case let .glint(every, motif, zone, alpha):
            guard !reduceMotion else { return }   // no sudden sparkles
            var i = 0
            let tick = SKAction.run { [weak self] in
                guard let self else { return }
                let s = self.sprite(motif, alpha: 0, scale: 0.62)
                s.position = zone.point(index: i, of: 9, in: self.sceneSize)
                i = (i + 1) % 9
                self.addChild(s)
                s.run(.sequence([
                    .fadeAlpha(to: alpha, duration: 0.22),
                    .fadeAlpha(to: 0, duration: 0.42),
                    .removeFromParent(),
                ]))
            }
            let gEvery = captureInterval(every)
            run(.repeatForever(.sequence([
                .wait(forDuration: (gEvery.lowerBound + gEvery.upperBound) / 2,
                      withRange: gEvery.upperBound - gEvery.lowerBound),
                tick,
            ])), withKey: "glint")

        case let .wander(count, visible, motif, zone, radius, alpha, cycle):
            for i in 0 ..< count {
                let s = sprite(motif, alpha: 0, scale: 0.60)
                let home = zone.point(index: i, of: count, in: sceneSize)
                s.position = home
                addChild(s)
                let dur = cycle.lowerBound
                    + (cycle.upperBound - cycle.lowerBound)
                    * Double(i % 4) / 3.0
                // Only `visible` of them glow at a time: the rest sit dark
                // and take their turn as the staggered cycle comes round.
                let duty = Double(visible) / Double(max(count, 1))
                let glow = SKAction.sequence([
                    .fadeAlpha(to: alpha, duration: dur * 0.30),
                    .wait(forDuration: dur * duty),
                    .fadeAlpha(to: 0, duration: dur * 0.34),
                    .wait(forDuration: dur * (1 - duty)),
                ])
                s.run(.sequence([.wait(forDuration: Double(i) * dur / Double(count)),
                                 .repeatForever(glow)]))
                guard !reduceMotion else { continue }   // glow only, no travel
                // Local wander: a small closed loop, never a screen crossing.
                let r = radius
                let path = SKAction.sequence([
                    move(s, by: CGVector(dx: r, dy: r * 0.5), dur * 0.5),
                    move(s, by: CGVector(dx: -r * 0.6, dy: r * 0.4), dur * 0.5),
                    move(s, by: CGVector(dx: -r * 0.6, dy: -r * 0.5), dur * 0.5),
                    move(s, by: CGVector(dx: r * 0.2, dy: -r * 0.4), dur * 0.5),
                ])
                s.run(.repeatForever(path), withKey: "wander")
            }

        case let .surfSlices(bands, topY, bottomY, xRange, fade, vFade,
                             drift, lift, frontBoost, period, alpha):
            guard let sky = skyLayer else {
                #if DEBUG
                NSLog("AURIE_AMBIENT surfSlices SKIPPED — no sky layer")
                #endif
                return
            }
            let h = sceneSize.height
            let texH = sky.texture.size().height
            let texW = sky.texture.size().width
            let onScreenH = texH * sky.scale

            for i in 0 ..< bands {
                // Deterministic per-band jitter (same golden-ratio walk the
                // zones use): drives each band's phase, hold and gap so the
                // set never surges in unison, while still composing
                // identically on every launch.
                let d = (Double(i) * 0.6180339887).truncatingRemainder(dividingBy: 1)
                // Travel is needed up front: the slice has to be PADDED by it
                // (see below), so it cannot wait until the motion is built.
                let near = bands > 1
                    ? CGFloat(i) / CGFloat(bands - 1) : 1
                // Cubic, so the boost lands almost entirely on near = 1:
                // at near 0.5 it adds ~6%, at near 0 nothing at all.
                let dy = lift * (0.55 + 0.85 * near
                                 + frontBoost * near * near * near)
                let dx = drift * (0.70 + 0.30 * near)
                // Bands are stacked down the shoreline zone and overlap
                // slightly, so there is no gap of un-animated water between
                // one and the next.
                let f0 = CGFloat(i) / CGFloat(bands)
                let f1 = CGFloat(i + 1) / CGFloat(bands)
                // Overlap stays a fixed fraction of SCENE height. Making it
                // proportional to the band looked right but is not: `vFade`
                // is a fraction of the SLICE, so a thinner band pushes its
                // full-strength zone out into the travel padding and spills
                // onto whatever is above and below (2026-09-25).
                let yTop = h * (topY - (topY - bottomY) * f0) + h * 0.006
                let yBot = h * (topY - (topY - bottomY) * f1) - h * 0.006
                let midY = (yTop + yBot) / 2
                let bandH = yTop - yBot
                guard bandH > 1 else { continue }

                // Scene y -> normalized v in the sky texture. The sprite is
                // centre-anchored at `centerY` and uniformly scaled, so this
                // is the exact inverse of how the layer was laid down.
                func v(_ sceneY: CGFloat) -> CGFloat {
                    (sceneY - sky.centerY) / onScreenH + 0.5
                }
                // PAD THE SLICE BY ITS OWN TRAVEL. The sprite used to be
                // exactly as tall as its crop window, which is fine while it
                // barely moves — but once travel approaches the band height
                // the sprite slides clean out of the window, so the window
                // empties and refills every cycle and a hard edge sweeps
                // across the shore. (2026-09-24: raising the front band's
                // travel to 20.3pt against a 20.3pt band did exactly that,
                // and read as the rocks moving again.) Sampling extra
                // painting above and below means there is always material
                // under the mask, whatever the travel.
                let pad = dy + 3
                let v0 = v(yBot - pad), v1 = v(yTop + pad)
                guard v0 > 0, v1 < 1, v1 > v0 else { continue }

                guard let slice = Self.featheredSlice(from: sky.texture,
                                                      vLow: v0, vHigh: v1,
                                                      xRange: xRange,
                                                      fade: fade,
                                                      vFade: vFade) else { continue }
                let sprite = SKSpriteNode(texture: slice)
                sprite.size = CGSize(width: texW * sky.scale,
                                     height: bandH + pad * 2)
                sprite.alpha = alpha
                sprite.isUserInteractionEnabled = false
                sprite.position = CGPoint(x: 0, y: midY)
                addChild(sprite)

                guard !reduceMotion else { continue }

                // ONE SURF CYCLE per band: a quick run-up shoreward, a
                // brief hold, then a slower drain back out. The previous
                // version swayed symmetrically over the whole period, which
                // reads as shimmer — water is ASYMMETRIC, it arrives fast and
                // leaves slowly, and that asymmetry is most of what makes a
                // wash legible as a wash.
                let t = period.lowerBound
                    + (period.upperBound - period.lowerBound)
                    * Double(i) / Double(max(bands - 1, 1))

                // i = 0 is the FARTHEST band (highest on screen) and i grows
                // toward the viewer. Travel therefore has to grow WITH i:
                // the frontmost foam edge is the one that visibly runs up the
                // sand, and the distant bands barely shift. This was inverted
                // before — `lift * (1 - 0.25 * i)` gave the horizon the most
                // movement and the shoreline the least.
                let dir: CGFloat = i.isMultiple(of: 2) ? 1 : -1

                let tUp = t * 0.32
                let tDown = t * 0.54
                let runUp = SKAction.group([
                    .moveBy(x: dx * dir, y: -dy, duration: tUp),
                    .fadeAlpha(to: alpha, duration: tUp * 0.55),
                ])
                runUp.timingMode = .easeOut
                let drain = SKAction.group([
                    .moveBy(x: -dx * dir, y: dy, duration: tDown),
                    .sequence([.wait(forDuration: tDown * 0.30),
                               .fadeAlpha(to: alpha * 0.58,
                                          duration: tDown * 0.70)]),
                ])
                drain.timingMode = .easeInEaseOut

                // Every band gets its own phase AND its own hold/gap, derived
                // from the irrational walk, so they never surge as one unit.
                sprite.run(.sequence([
                    .wait(forDuration: (tUp + tDown)
                          * Double(i) / Double(bands) + d * 0.7),
                    .repeatForever(.sequence([
                        runUp,
                        .wait(forDuration: 0.10 + d * 0.26),
                        drain,
                        .wait(forDuration: 0.15 + d * 0.80),
                    ])),
                ]))
            }

        case let .drift(count, motif, zone, alpha, spriteScale, fall, sway, spin):
            let h = sceneSize.height
            for i in 0 ..< count {
                let s = sprite(motif, alpha: 0, scale: spriteScale)
                let home = zone.point(index: i, of: count, in: sceneSize)
                addChild(s)
                let dur = fall.lowerBound
                    + (fall.upperBound - fall.lowerBound)
                    * Double(i % 4) / 3.0
                guard !reduceMotion else {
                    // Reduce Motion: they simply rest where they fell.
                    s.position = home
                    s.alpha = alpha
                    continue
                }
                let top = h * 0.56, bottom = -h * 0.40
                let reset = SKAction.run {
                    s.position = CGPoint(x: home.x, y: top)
                    s.zRotation = CGFloat(i) * 0.7
                }
                let down = SKAction.moveTo(y: bottom, duration: dur)
                down.timingMode = .linear
                // Sway makes the descent read as a leaf rather than a dropped
                // object: two slow lateral passes over the fall.
                let right = SKAction.moveBy(x: sway, y: 0, duration: dur * 0.25)
                let left = SKAction.moveBy(x: -sway, y: 0, duration: dur * 0.25)
                right.timingMode = .easeInEaseOut
                left.timingMode = .easeInEaseOut
                var group: [SKAction] = [
                    down,
                    .sequence([right, left, left, right]),
                    .sequence([.fadeAlpha(to: alpha, duration: dur * 0.12),
                               .wait(forDuration: dur * 0.70),
                               .fadeAlpha(to: 0, duration: dur * 0.18)]),
                ]
                if spin {
                    group.append(.repeatForever(
                        .rotate(byAngle: i.isMultiple(of: 2) ? 1.8 : -1.8,
                                duration: dur * 0.5)))
                }
                s.run(.sequence([
                    .wait(forDuration: dur * Double(i) / Double(count)),
                    .repeatForever(.sequence([reset, .group(group)])),
                ]))
            }

        case let .heat(count, zone, alpha, rise, spriteScale):
            guard !reduceMotion else { return }   // shimmer IS motion
            let h = sceneSize.height
            for i in 0 ..< count {
                let s = SKSpriteNode(texture:
                    FamilyParticleArt.texture(.emberHeat))
                s.setScale(spriteScale)
                s.alpha = 0
                s.blendMode = .add
                s.isUserInteractionEnabled = false
                let home = zone.point(index: i, of: count, in: sceneSize)
                // Plumes belong low, where the ground is hot.
                s.position = CGPoint(x: home.x, y: -h * 0.24)
                s.anchorPoint = CGPoint(x: 0.5, y: 0)
                addChild(s)
                let dur = rise.lowerBound
                    + (rise.upperBound - rise.lowerBound)
                    * Double(i % 3) / 2.0
                let up = SKAction.moveBy(x: 0, y: h * 0.30, duration: dur)
                up.timingMode = .easeOut
                // The waver is what sells it: a slow horizontal sway while
                // rising, so the column bends the way hot air does.
                let swayR = SKAction.moveBy(x: 14, y: 0, duration: dur * 0.5)
                let swayL = SKAction.moveBy(x: -14, y: 0, duration: dur * 0.5)
                swayR.timingMode = .easeInEaseOut
                swayL.timingMode = .easeInEaseOut
                let cycle = SKAction.sequence([
                    .run { s.position = CGPoint(x: home.x, y: -h * 0.24) },
                    .group([up,
                            .sequence([swayR, swayL]),
                            .sequence([
                                .fadeAlpha(to: alpha, duration: dur * 0.30),
                                .fadeAlpha(to: 0, duration: dur * 0.70)])]),
                ])
                s.run(.sequence([
                    .wait(forDuration: dur * Double(i) / Double(count)),
                    .repeatForever(cycle),
                ]))
            }

        case let .visitor(kind, every, duration, zone):
            guard !reduceMotion else { return }   // no ambient travel
            let spawn = SKAction.run { [weak self] in
                self?.spawnVisitor(kind, duration: duration, zone: zone,
                                   family: family)
            }
            // First appearance is also delayed, so a session can open with
            // none at all — the visitor must feel like luck, not a loop.
            let vEvery = captureInterval(every)
            run(.repeatForever(.sequence([
                .wait(forDuration: (vEvery.lowerBound + vEvery.upperBound) / 2,
                      withRange: vEvery.upperBound - vEvery.lowerBound),
                spawn,
            ])), withKey: "visitor")
        }
    }

    private func move(_ node: SKNode, by v: CGVector,
                      _ duration: Double) -> SKAction {
        let a = SKAction.moveBy(x: v.dx, y: v.dy, duration: duration)
        a.timingMode = .easeInEaseOut
        return a
    }

    private func sprite(_ motif: FamilyParticleArt.Motif,
                        alpha: CGFloat, scale: CGFloat) -> SKSpriteNode {
        let s = SKSpriteNode(texture: FamilyParticleArt.texture(motif))
        s.alpha = alpha
        s.setScale(scale)
        // LIT MATTER vs LIGHT. Additive blending only reads against a darker
        // background: a leaf over a sunlit forest or dust over a bright alpine
        // meadow just saturates toward the background and vanishes (measured:
        // Stone's dust was invisible in a still and contributed ~1% of frame
        // change). Things that are merely *lit* composite normally; things
        // that *emit* stay additive.
        switch motif {
        case .mossLeaf, .mossSpore, .stoneDust, .stoneMote, .stoneSpeck,
             .stoneFleck, .mossPetal:
            s.blendMode = .alpha
        default:
            s.blendMode = .add
        }
        // Ambient life is scenery: it must never intercept a touch meant for
        // Aurie or the play area.
        s.isUserInteractionEnabled = false
        return s
    }

    // MARK: - Visitors

    private func spawnVisitor(_ kind: FamilyAmbient.Visitor,
                              duration: ClosedRange<Double>,
                              zone: FamilyAmbient.Zone,
                              family: AuraFamily) {
        // One at a time, always.
        guard childNode(withName: "visitor") == nil else { return }
        let dur = Double.random(in: duration)
        let w = sceneSize.width, h = sceneSize.height
        let fromLeft = Bool.random()

        switch kind {
        case .butterfly:
            let node = butterflyNode()
            node.name = "visitor"
            // IN FRONT of the creature. The ambient node sits at z -40 so its
            // spores stay behind Aurie, but a butterfly Aurie is watching and
            // reaching for cannot be behind its head — the eye tracking reads
            // as wrong (2026-09-25). +85 here = +45 in the scene: ahead of the
            // creature (~0-8) and still behind the foreground art (60+).
            node.zPosition = 85
            // Enter from a side, wander through the side/upper zone, leave.
            // Deliberately stays out of the centre column and the face band.
            let startX = fromLeft ? -w * 0.56 : w * 0.56
            // Enters nearer the creature's own height than it used to, so
            // the crossing is something Aurie can plausibly notice rather
            // than a shape near the canopy. Still above the face band, so it
            // never occludes the expression.
            let entryY = h * CGFloat.random(in: 0.04...0.15)
            node.position = CGPoint(x: startX, y: entryY)
            node.alpha = 0
            addChild(node)
            // APPROACH -> HOVER -> LEAVE, not one continuous crossing. A
            // single sweep put the butterfly near the creature for only a
            // moment in the middle, so Aurie spent the visit chasing
            // something already gone. The hover IS the interaction window:
            // it loiters near the centre long enough to be followed.
            //
            // Every segment flutters — two incommensurate sines for the bob,
            // and a warped `t` so ground speed is uneven (dawdle, then dart).
            let dir: CGFloat = fromLeft ? 1 : -1
            let hoverX = -dir * w * 0.06      // just past centre
            let hoverY = entryY - h * 0.05
            func bobPath(_ p0: CGPoint, _ p1: CGPoint, _ waves: CGFloat) -> CGPath {
                let path = CGMutablePath()
                path.move(to: p0)
                let steps = 40
                for i in 1 ... steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    let tx = t + sin(t * .pi * 3.0) * 0.03
                    let x = p0.x + (p1.x - p0.x) * tx
                    let base = p0.y + (p1.y - p0.y) * t
                    let bob = sin(t * .pi * waves) * h * 0.020
                        + sin(t * .pi * waves * 0.6 + 0.8) * h * 0.011
                    path.addLine(to: CGPoint(x: x, y: base + bob))
                }
                return path
            }
            // The loiter: two loose loops whose offsets vanish at both ends,
            // so it starts and finishes exactly on the hover point and the
            // three segments join without a jump.
            let hover = CGMutablePath()
            hover.move(to: CGPoint(x: hoverX, y: hoverY))
            for i in 1 ... 90 {
                let t = CGFloat(i) / 90
                let a = t * .pi * 4
                let env = sin(t * .pi)
                hover.addLine(to: CGPoint(
                    x: hoverX + sin(a) * w * 0.11 + sin(a * 2.3) * w * 0.03 * env,
                    y: hoverY + sin(a * 1.7 + 0.5) * h * 0.030 * env
                        + cos(a * 3.1) * h * 0.014 * env))
            }
            let fly = SKAction.sequence([
                .follow(bobPath(CGPoint(x: startX, y: entryY),
                                CGPoint(x: hoverX, y: hoverY), 9),
                        asOffset: false, orientToPath: false,
                        duration: dur * 0.30),
                .follow(hover, asOffset: false, orientToPath: false,
                        duration: dur * 0.42),
                .follow(bobPath(CGPoint(x: hoverX, y: hoverY),
                                CGPoint(x: dir * w * 0.62,
                                        y: entryY + h * 0.12), 7),
                        asOffset: false, orientToPath: false,
                        duration: dur * 0.28),
            ])
            node.run(.repeatForever(.sequence([
                .run { [weak self, weak node] in
                    guard let node else { return }
                    self?.onVisitorMove?(node.position)
                },
                .wait(forDuration: 0.1),
            ])), withKey: "report")
            node.run(.sequence([
                .fadeAlpha(to: 0.85, duration: 0.8),
                fly,
                // Short, and only once it is already outside the frame — the
                // fade is insurance against an odd aspect ratio, not the way
                // it leaves.
                .fadeAlpha(to: 0, duration: 0.25),
                .run { [weak self] in self?.onVisitorMove?(nil) },
                .removeFromParent(),
            ]))

        case .shootingStar:
            let s = sprite(.starComet, alpha: 0, scale: 0.52)
            s.name = "visitor"
            // A SHORT streak across part of the upper sky only.
            let y = h * CGFloat.random(in: 0.22...0.40)
            let startX = fromLeft ? -w * 0.34 : w * 0.34
            let span: CGFloat = w * 0.30
            s.position = CGPoint(x: startX, y: y)
            s.zRotation = fromLeft ? -0.5 : 0.5
            addChild(s)
            let travel = SKAction.moveBy(x: fromLeft ? span : -span,
                                         y: -h * 0.06, duration: dur)
            travel.timingMode = .easeOut
            s.run(.sequence([
                .group([travel,
                        .sequence([.fadeAlpha(to: 0.75, duration: dur * 0.25),
                                   .fadeAlpha(to: 0, duration: dur * 0.75)])]),
                .removeFromParent(),
            ]))
        }
    }

    /// Moss's decorative butterfly, built from the (shelf-retired) toy art so
    /// there is one butterfly look in the app. Wings flap; nothing is
    /// interactive.
    private func butterflyNode() -> SKNode {
        let node = SKNode()
        let body = SKSpriteNode(texture: ToyBox.butterflyBodyTexture)
        body.setScale(0.46)
        let wingL = SKSpriteNode(texture: ToyBox.butterflyWingTexture)
        wingL.setScale(0.46)
        wingL.anchorPoint = CGPoint(x: 1, y: 0.5)
        wingL.position = CGPoint(x: -1, y: 4)
        let wingR = SKSpriteNode(texture: ToyBox.butterflyWingTexture)
        wingR.setScale(0.46)
        wingR.anchorPoint = CGPoint(x: 1, y: 0.5)
        wingR.position = CGPoint(x: 1, y: 4)
        wingR.xScale = -0.46
        node.addChild(wingL); node.addChild(wingR); node.addChild(body)
        let flapIn = SKAction.scaleX(to: 0.16, duration: 0.22)
        let flapOut = SKAction.scaleX(to: 0.46, duration: 0.22)
        flapIn.timingMode = .easeInEaseOut
        flapOut.timingMode = .easeInEaseOut
        wingL.run(.repeatForever(.sequence([flapIn, flapOut])))
        wingR.run(.repeatForever(.sequence([
            .scaleX(to: -0.16, duration: 0.22),
            .scaleX(to: -0.46, duration: 0.22),
        ])))
        return node
    }
}
