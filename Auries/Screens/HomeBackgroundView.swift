import SwiftUI

/// Layered, low-contrast family-background *placeholder* for Home (Stage A).
/// Replaces the flat single-tint with soft depth: a base family gradient, a
/// gentle central bloom behind the creature, a subtle vignette, and sparse
/// slow-drifting motes. Colour comes from the creature's aura, so it keeps the
/// family identity (Dusk reads as Dusk). This is deliberately still a
/// placeholder — real `background_<family>` art drops in later via AssetLoader
/// without changing this composition's role.
///
/// Deliberately appearance-independent: the atmosphere is a full-bleed coloured
/// scene, identical in light or dark, so it doesn't rely on forcing dark mode.
/// Home-only; Detail / Hatch / Collection / Calm backgrounds are untouched.
///
/// Motes are purely decorative: hidden from VoiceOver, static under Reduce
/// Motion, and paused whenever Home is off-screen or the app is inactive so no
/// display-link work happens on a hidden tab or in the background.
struct HomeBackgroundView: View {
    let aura: Rgb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = false

    private var animate: Bool { onScreen && scenePhase == .active && !reduceMotion }

    private var base: Color {
        let c = familyBackdropComponents(aura)
        return Color(red: c.r, green: c.g, blue: c.b)
    }
    /// A slightly lifted family colour for the bloom (never bright).
    private var bloom: Color { Color(aura, brightness: 0.42) }

    var body: some View {
        ZStack {
            // Base vertical gradient: a touch deeper at top and bottom.
            LinearGradient(
                colors: [base.opacity(0.65), base, base.opacity(0.8)],
                startPoint: .top, endPoint: .bottom
            )

            // Soft central bloom behind where the creature rests (lower-centre).
            RadialGradient(
                colors: [bloom.opacity(HomeTokens.bloomOpacity), .clear],
                center: UnitPoint(x: 0.5, y: 0.57), startRadius: 8, endRadius: 460
            )

            motes

            // Vignette: darken the outer edges to focus the centre.
            RadialGradient(
                colors: [.clear, .black.opacity(HomeTokens.vignetteOpacity)],
                center: .center, startRadius: 180, endRadius: 620
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)   // decorative; invisible to VoiceOver
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
    }

    /// Sparse, soft, slow atmospheric motes. Paused (static) when Home is
    /// hidden, the app is inactive, or Reduce Motion is on.
    private var motes: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animate)) { timeline in
            Canvas { ctx, size in
                let t = animate ? timeline.date.timeIntervalSinceReferenceDate : 0
                for i in 0..<HomeTokens.moteCount {
                    let seed = Double(i)
                    let x = (sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let baseY = (sin(seed * 78.233) * 12543.245).truncatingRemainder(dividingBy: 1)
                    let px = abs(x) * size.width
                    let drift = (abs(baseY) + t * 0.004 * (0.5 + abs(x))).truncatingRemainder(dividingBy: 1)
                    let py = drift * size.height
                    let r = 1.0 + abs(x) * 2.2
                    let twinkle = 0.10 + 0.10 * (0.5 + 0.5 * sin(t * 0.6 + seed))
                    let rect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                    ctx.fill(Circle().path(in: rect), with: .color(.white.opacity(twinkle)))
                }
            }
        }
    }
}
