import SwiftUI

// MARK: - The layered Blender jar
//
// The jar is a COMPOSITE of Blender-rendered layers, stacked back to front:
//
//   worry_jar_back       faint form veil (the glass body's presence)
//   (live fireflies)     sprite creatures drawn in a single Canvas
//   (cork)               separate, so it can wobble/pop during a release
//   worry_jar_glass_add  the APPROVED Stage-B transmissive glass rendered
//                        over black, screened on top: rims, speculars,
//                        window reflections, refractive base rings
//
// All layers share one Blender camera, so they align as full-frame overlays.
// The fireflies therefore genuinely sit INSIDE the glass volume.
//
// Geometry constants below are measured from that shared camera frame
// (ortho 1.62 over a 1100x1400 canvas; see export_worry_jar_assets.py).

private enum JarFrame {
    /// The glass interior, as a unit-rect region of the full image.
    static let interior = CGRect(x: 0.21, y: 0.33, width: 0.58, height: 0.44)
    /// The cork's hinge: where the cap's left edge meets the lip.
    static let corkAnchor = UnitPoint(x: 0.27, y: 0.155)
    static let aspect: CGFloat = 1100.0 / 1400.0
}

// MARK: - Firefly swarm

/// One resident firefly. Deterministic per index — `TimelineView` re-evaluates
/// constantly, so anything random would jitter between frames.
private struct JarFly {
    let id: Int
    let sprite: String
    let depth: CGFloat          // 0 back … 1 front — drives scale and alpha
    let cx: CGFloat, cy: CGFloat
    let rx: CGFloat, ry: CGFloat
    let speed: CGFloat, phase: CGFloat
    let size: CGFloat           // height, as a fraction of the jar height
    let pulse: CGFloat
    let mirrored: Bool

    /// Twelve residents — the approved 10-12 count at full fill. Variants and
    /// poses interleave so neighbours never match.
    static let swarm: [JarFly] = {
        let sprites = [
            "worry_firefly_V1_base_threeq", "worry_firefly_V2_round_side",
            "worry_firefly_V3_slender_up", "worry_firefly_V4_bright_threeq",
            "worry_firefly_V2_round_threeq", "worry_firefly_V1_base_side",
            "worry_firefly_V4_bright_up", "worry_firefly_V3_slender_side",
            "worry_firefly_V1_base_up", "worry_firefly_V3_slender_threeq",
            "worry_firefly_V2_round_up", "worry_firefly_V4_bright_side",
        ]
        var flies: [JarFly] = []
        for i in 0 ..< 12 {
            let fi = CGFloat(i)
            let depth: CGFloat = CGFloat((i * 5) % 12) / 11.0
            let cx: CGFloat = 0.20 + CGFloat((i * 37) % 61) / 100.0
            let cy: CGFloat = 0.18 + CGFloat((i * 53) % 64) / 100.0
            let rx: CGFloat = 0.10 + CGFloat((i * 29) % 14) / 100.0
            let ry: CGFloat = 0.08 + CGFloat((i * 17) % 15) / 100.0
            let speed: CGFloat = 0.16 + CGFloat((i * 13) % 22) / 130.0
            let size: CGFloat = 0.075 + CGFloat((i * 23) % 40) / 1000.0
            let pulse: CGFloat = 0.6 + CGFloat((i * 31) % 70) / 100.0
            flies.append(JarFly(id: i, sprite: sprites[i], depth: depth,
                                cx: cx, cy: cy, rx: rx, ry: ry,
                                speed: speed, phase: fi * 1.37,
                                size: size, pulse: pulse,
                                mirrored: i % 3 == 1))
        }
        return flies
    }()
}

// MARK: - Release kinematics (light-to-firefly)

/// The stored worry is a LIGHT. On release it rises to the mouth and
/// transforms: at the rim it births the approved fireflies one by one —
/// each is created at its final flight size and keeps it. This is a pure
/// function of (fly, time-since-release), shared by the light (which dims a
/// step per birth) and the escape overlay (which draws the born flies).
///
/// Coordinates are jar-INTERIOR units: u 0..1 across, v 0..1 down the
/// interior; v < 0 is above the rim, rising to about -6 at full height.
private enum FlyKinematics {
    static let releaseCount = 6

    struct State {
        var u: CGFloat
        var v: CGFloat
        var alpha: CGFloat      // lifecycle fade (multiplies the base look)
        var scale: CGFloat      // ~1; small breathing only
        var glow: CGFloat
    }

    /// Birth times (seconds after the release tap), by birth rank. The light
    /// reaches the mouth at ~1.25s; births stagger 0.18-0.35s apart.
    static func birthTimes(count: Int) -> [Double] {
        var times = [Double](repeating: 0, count: max(1, count))
        var t = 1.25
        for rank in 0..<max(1, count) {
            times[rank] = t
            t += 0.18 + Double((rank * 37) % 18) / 100.0
        }
        return times
    }

    /// Rank of a fly in the birth order (deterministic shuffle; 5 is coprime
    /// with 6, so every fly gets a distinct slot).
    static func rank(of id: Int, count: Int) -> Int {
        count <= 1 ? 0 : (id * 5) % count
    }

    /// How much of the light remains at time t (1 -> 0 as flies are born).
    static func lightRemaining(_ t: Double, count: Int) -> Double {
        let births = birthTimes(count: count)
        var level = 1.0
        let step = 1.0 / Double(count)
        for b in births {
            // each birth takes a smooth bite out of the light
            let k = min(max((t - b) / 0.25, 0), 1)
            level -= step * k * k * (3 - 2 * k)
        }
        return max(0, level)
    }

    private static func ease(_ x: CGFloat) -> CGFloat {
        let c = min(max(x, 0), 1); return c * c * (3 - 2 * c)
    }

    /// - Returns: nil while the fly is still part of the light, and nil
    ///   again once it has fully left the night.
    static func state(_ f: JarFly, count: Int, now: CGFloat, t0: CGFloat,
                      reduceMotion: Bool) -> State? {
        let t = now - t0
        let r = rank(of: f.id, count: count)
        let birth = CGFloat(birthTimes(count: count)[r])
        if t < birth { return nil }

        let tau = t - birth
        let jit = (CGFloat((f.id * 13) % 9) - 4) / 40      // ±0.10 at mouth
        let dir: CGFloat = f.id % 2 == 0 ? 1 : -1

        // -------------------------------------- birth at the rim (pop-in)
        let hover: CGFloat = 0.25
        if tau < hover {
            let hp = tau / hover
            let sway = reduceMotion ? 0 : 0.030 * sin(now * 2.6 + CGFloat(f.id))
            return State(u: 0.5 + jit + sway,
                         v: -0.10 - 0.10 * ease(hp),
                         alpha: min(1, tau / 0.12),
                         scale: 0.85 + 0.15 * ease(min(1, tau / 0.15)),
                         glow: 1.10)
        }

        // ------------------------------------------------ flight
        let flightDur: CGFloat = 3.0 + CGFloat((f.id * 29) % 12) / 10
        let p = (tau - hover) / flightDur
        if p >= 1 { return nil }
        let bAmp = 2.0 + CGFloat((f.id * 23) % 7) / 10           // 2.0-2.6
        let aAmp = 0.4 + CGFloat((f.id * 31) % 8) / 10           // 0.4-1.1
        let sAmp = 0.10 + CGFloat((f.id * 17) % 6) / 30          // gentle wave
        let om = 1.2 + CGFloat((f.id * 11) % 13) / 10            // 1.2-2.4
        let v = -0.20 - 6.2 * pow(p, 1.15)
        // Lateral spread front-loads and keeps widening with rise —
        // dispersal, never a clump or a column. Through the face band the
        // magnitude is FLOORED so no fly can cross the eyes or mouth.
        var lat = bAmp * pow(p, 0.55) + aAmp * pow(p, 1.3)
        let band = min(max((-v - 0.8) / 1.3, 0), 1)
        lat = max(lat, 1.05 * sin(.pi * band))
        let u = 0.5 + jit + dir * lat
              + (reduceMotion ? 0 : sAmp * sin(p * om * .pi + CGFloat(f.id)) * p)
        let fade: CGFloat = p < 0.55 ? 1 : max(0, 1 - (p - 0.55) / 0.45)
        let scale = 1 + 0.06 * sin(min(1, p) * .pi)
        return State(u: u, v: v, alpha: fade, scale: scale, glow: 1.0)
    }
}

// MARK: - The worry-light

/// The held worry inside the glass: ONE small beautiful warm light — a
/// near-white heart inside an amber glow, breathing slowly, with a few tiny
/// drifting motes. Nothing insect-shaped: "Only a little light remains in
/// the jar." On release it brightens, rises to the mouth, and dims a step
/// as each firefly is born from it.
struct JarLightView: View {
    /// 0 = no light, 1 = holding a worry.
    var fill: Double
    /// Set at the release tap (timeIntervalSinceReferenceDate).
    var releaseT0: TimeInterval?
    var reduceMotion: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                let t = CGFloat(tl.date.timeIntervalSinceReferenceDate)
                var v: CGFloat = 0.58
                var level = CGFloat(fill)
                var boost: CGFloat = 1
                if let t0 = releaseT0 {
                    let rt = t - CGFloat(t0)
                    let b = min(max(rt / 0.5, 0), 1)
                    boost = 1 + 0.35 * b * b * (3 - 2 * b)     // brighten first
                    let riseK = min(max((rt - 0.5) / 0.75, 0), 1)
                    v = 0.58 - 0.50 * riseK * riseK * (3 - 2 * riseK)
                    level = CGFloat(FlyKinematics.lightRemaining(
                        Double(rt), count: FlyKinematics.releaseCount))
                }
                guard level > 0.015 else { return }
                let breathe = reduceMotion
                    ? 1.0 : 0.92 + 0.08 * sin(t * 1.1)
                let cx = 0.5 * size.width
                let cy = v * size.height
                let presence = pow(level, 0.65) * breathe * boost

                func blob(_ radius: CGFloat, _ colors: [Color], _ alpha: CGFloat) {
                    var g = ctx
                    g.blendMode = .plusLighter
                    g.opacity = alpha
                    g.fill(
                        Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius,
                                               width: radius * 2,
                                               height: radius * 2)),
                        with: .radialGradient(
                            Gradient(colors: colors),
                            center: CGPoint(x: cx, y: cy),
                            startRadius: 0, endRadius: radius))
                }
                // amber outer glow -> gold body -> near-white heart
                blob(size.width * 0.40 * presence,
                     [Color(red: 1.0, green: 0.62, blue: 0.16).opacity(0.55),
                      Color(red: 1.0, green: 0.55, blue: 0.12).opacity(0)],
                     0.85 * level)
                blob(size.width * 0.20 * presence,
                     [Color(red: 1.0, green: 0.78, blue: 0.30),
                      Color(red: 1.0, green: 0.62, blue: 0.16).opacity(0)],
                     min(1, 0.95 * level + 0.05))
                blob(size.width * 0.085 * presence,
                     [Color(red: 1.0, green: 0.97, blue: 0.86),
                      Color(red: 1.0, green: 0.80, blue: 0.34).opacity(0)],
                     min(1, level + 0.1))

                // a few tiny drifting motes — light dust, never insects
                if reduceMotion == false {
                    for i in 0..<3 {
                        let fi = CGFloat(i)
                        let ang = t * (0.35 + fi * 0.11) + fi * 2.4
                        let rad = size.width * (0.13 + fi * 0.055)
                              * (0.8 + 0.2 * sin(t * 0.7 + fi))
                        let mx = cx + cos(ang) * rad
                        let my = cy + sin(ang * 0.83) * rad * 0.7
                        let ms: CGFloat = 1.4 + fi * 0.4
                        var g = ctx
                        g.blendMode = .plusLighter
                        g.opacity = (0.35 + 0.25 * sin(t * 1.9 + fi * 2))
                                    * level
                        g.fill(
                            Path(ellipseIn: CGRect(x: mx - ms, y: my - ms,
                                                   width: ms * 2, height: ms * 2)),
                            with: .color(Color(red: 1.0, green: 0.85,
                                               blue: 0.45)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - The jar

/// Clear Blender glass, cork stopper, fireflies inside.
struct WorryJarView: View {
    /// 0 = empty jar, 1 = holding the full swarm (11 fireflies).
    var fill: Double
    /// Cork lifts and tilts during a release.
    var lidOpen: Double = 0
    /// Set at the release tap: the residents leave one by one (identity-
    /// preserving choreography); `fill` then only drains the warm light.
    var releaseStart: Date? = nil
    var reduceMotion: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let inner = CGRect(x: JarFrame.interior.minX * w,
                               y: JarFrame.interior.minY * h,
                               width: JarFrame.interior.width * w,
                               height: JarFrame.interior.height * h)
            ZStack {
                // A faint form veil so the glass body exists between the
                // night and the lights; the REAL glass look rides on the
                // transmissive add layer at the top of the stack.
                Image("worry_jar_back")
                    .resizable()
                    .opacity(0.15)

                // Collective warmth low in the belly, from the swarm.
                RadialGradient(
                    colors: [Color(red: 1.0, green: 0.72, blue: 0.30)
                                .opacity(0.40 * fill),
                             .clear],
                    center: UnitPoint(x: 0.5, y: 0.60),
                    startRadius: 1, endRadius: inner.width * 0.62)
                    .frame(width: inner.width, height: inner.height)
                    .position(x: inner.midX, y: inner.midY)

                // The swarm's warmth caught by the glass floor.
                Ellipse()
                    .fill(Color(red: 1.0, green: 0.70, blue: 0.28)
                            .opacity(0.22 * fill))
                    .frame(width: inner.width * 0.66,
                           height: inner.height * 0.10)
                    .position(x: inner.midX,
                              y: inner.maxY - inner.height * 0.06)
                    .blur(radius: 6)

                if releaseStart != nil || fill > 0.02 {
                    JarLightView(
                        fill: fill,
                        releaseT0: releaseStart?.timeIntervalSinceReferenceDate,
                        reduceMotion: reduceMotion)
                        .frame(width: inner.width, height: inner.height)
                        .position(x: inner.midX, y: inner.midY)
                }

                Image("worry_jar_cork")
                    .resizable()
                    // Warm bounce on the cork underside when the jar is full.
                    .overlay {
                        Image("worry_jar_cork")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundStyle(
                                Color(red: 1.0, green: 0.72, blue: 0.30))
                            .opacity(0.22 * fill)
                    }
                    .rotationEffect(.degrees(-17 * lidOpen),
                                    anchor: JarFrame.corkAnchor)
                    .offset(y: -h * 0.045 * lidOpen)

                // The APPROVED Stage-B transmissive glass, rendered over
                // black and screened on: rims, speculars, window
                // reflections and the refractive base rings land over the
                // night, the fireflies and the cork — real glass, live
                // contents.
                Image("worry_jar_glass_add")
                    .resizable()
                    .blendMode(.screen)
            }
            .overlay(alignment: .bottom) {
                // The sky above the jar: the SAME residents, once past the
                // rim. Bottom-aligned so the two canvases share one space.
                if let releaseStart {
                    FireflyEscapeView(
                        releaseT0: releaseStart.timeIntervalSinceReferenceDate,
                        count: FlyKinematics.releaseCount,
                        jarSize: CGSize(width: w, height: h),
                        reduceMotion: reduceMotion)
                        .frame(width: w * 3.6, height: h * 4.3)
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(JarFrame.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Release escape overlay

/// The residents once past the rim: SAME art, SAME sizes, SAME identities as
/// inside the glass — this canvas just covers the sky above the jar. It maps
/// the shared interior-unit space into its own frame; a fly is drawn either
/// here or in `JarFirefliesView`, never both.
struct FireflyEscapeView: View {
    /// timeIntervalSinceReferenceDate at the release tap.
    var releaseT0: TimeInterval
    var count: Int = 6
    /// The jar's rendered size (the overlay is bottom-aligned to it).
    var jarSize: CGSize
    var reduceMotion: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                let t = CGFloat(tl.date.timeIntervalSinceReferenceDate)
                let rt = t - CGFloat(releaseT0)
                // The jar sits centred at the bottom of this canvas; the
                // interior rect in canvas points:
                let jarX = (size.width - jarSize.width) / 2
                let jarY = size.height - jarSize.height
                let ix = jarX + JarFrame.interior.minX * jarSize.width
                let iy = jarY + JarFrame.interior.minY * jarSize.height
                let iw = JarFrame.interior.width * jarSize.width
                let ih = JarFrame.interior.height * jarSize.height
                let n = max(0, min(JarFly.swarm.count, count))

                // Tiny warm-gold sparkle dust at each birth — the light
                // visibly becoming a firefly. Much smaller than the flies,
                // short-lived, subtle. Nothing else.
                let births = FlyKinematics.birthTimes(count: n)
                for (k, b) in births.enumerated() {
                    let age = rt - CGFloat(b)
                    guard age > 0, age < 0.55 else { continue }
                    let life = age / 0.55
                    let mouthX = ix + 0.5 * iw
                    let mouthY = iy - 0.12 * ih
                    let m = k == 0 ? 12 : 7
                    for j in 0..<m {
                        let ang = CGFloat(j) * (2 * .pi / CGFloat(m))
                                + CGFloat(k) * 0.9
                        let dist = (3 + 15 * life) * (0.7 + 0.3
                                * CGFloat((j * 13) % 7) / 7)
                        let px = mouthX + cos(ang) * dist
                        let py = mouthY + sin(ang) * dist * 0.8 - 6 * life
                        let ps = (2.0 - 1.2 * life)
                                * (0.7 + 0.3 * CGFloat((j * 7) % 5) / 5)
                        var g = ctx
                        g.blendMode = .plusLighter
                        g.opacity = (1 - life) * 0.8
                        g.fill(
                            Path(ellipseIn: CGRect(x: px - ps, y: py - ps,
                                                   width: ps * 2,
                                                   height: ps * 2)),
                            with: .color(j % 3 == 0
                                ? Color(red: 1.0, green: 0.95, blue: 0.78)
                                : Color(red: 1.0, green: 0.80, blue: 0.34)))
                    }
                }

                for f in JarFly.swarm.prefix(n) {
                    guard let st = FlyKinematics.state(
                        f, count: n, now: t, t0: CGFloat(releaseT0),
                        reduceMotion: reduceMotion)
                    else { continue }
                    let img = ctx.resolve(Image(f.sprite))
                    // ONE consistent runtime size from emergence to exit —
                    // only ±12% individual variation, no depth shrinking.
                    // 2.0x: real presence at phone size — a small elegant
                    // glowing firefly, never giant.
                    let h = ih * f.size * (0.88 + 0.24 * f.depth) * 2.0
                              * st.scale
                    let w = h * img.size.width / img.size.height
                    let x = ix + st.u * iw
                    let y = iy + st.v * ih
                    guard y > -h, x > -w, x < size.width + w else { continue }
                    let pulse = 0.82 + 0.18 * sin(t * f.pulse + f.phase)
                    let a = (0.64 + 0.36 * f.depth) * pulse
                              * st.alpha * min(1.25, st.glow)
                    // Wings stay a CONSTANT subtle detail (no fade-with-rise:
                    // that read as the fly shrinking). The luminous presence
                    // comes from the abdomen: a near-white-hot centre inside
                    // rich amber inside a soft controlled orb, sized so the
                    // fly keeps the same apparent footprint it had inside.
                    let wingFade: CGFloat = 0.78

                    var inner = ctx
                    inner.opacity = a * wingFade
                    inner.translateBy(x: x, y: y)
                    if f.mirrored { inner.scaleBy(x: -1, y: 1) }
                    inner.rotate(by: .degrees(Double(sin(t * 0.5 + f.phase)) * 7))
                    var glow = inner
                    glow.blendMode = .plusLighter
                    glow.opacity = a * 0.9
                    let orb = h * 1.15
                    glow.fill(
                        Path(ellipseIn: CGRect(x: -orb / 2, y: h * 0.06 - orb / 2,
                                               width: orb, height: orb)),
                        with: .radialGradient(
                            Gradient(colors: [
                                Color(red: 1.0, green: 0.72, blue: 0.26)
                                    .opacity(0.55),
                                Color(red: 1.0, green: 0.58, blue: 0.14)
                                    .opacity(0),
                            ]),
                            center: CGPoint(x: 0, y: h * 0.06),
                            startRadius: 0, endRadius: orb * 0.58))
                    glow.opacity = a * 0.30 * wingFade
                    glow.draw(img, in: CGRect(x: -w * 0.85, y: -h * 0.85,
                                              width: w * 1.7, height: h * 1.7))
                    // Amber body glow...
                    let core = h * 0.62
                    glow.opacity = min(1, a * 1.35)
                    glow.fill(
                        Path(ellipseIn: CGRect(x: -core / 2,
                                               y: h * 0.06 - core / 2,
                                               width: core, height: core)),
                        with: .radialGradient(
                            Gradient(colors: [
                                Color(red: 1.0, green: 0.80, blue: 0.32),
                                Color(red: 1.0, green: 0.60, blue: 0.16)
                                    .opacity(0),
                            ]),
                            center: CGPoint(x: 0, y: h * 0.06),
                            startRadius: 0, endRadius: core * 0.85))
                    // ...with a near-white-hot heart.
                    let hot = h * 0.30
                    glow.opacity = min(1, a * 1.4)
                    glow.fill(
                        Path(ellipseIn: CGRect(x: -hot / 2,
                                               y: h * 0.06 - hot / 2,
                                               width: hot, height: hot)),
                        with: .radialGradient(
                            Gradient(colors: [
                                Color(red: 1.0, green: 0.96, blue: 0.80),
                                Color(red: 1.0, green: 0.78, blue: 0.30)
                                    .opacity(0),
                            ]),
                            center: CGPoint(x: 0, y: h * 0.06),
                            startRadius: 0, endRadius: hot * 0.9))
                    inner.draw(img, in: CGRect(x: -w / 2, y: -h / 2,
                                               width: w, height: h))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
