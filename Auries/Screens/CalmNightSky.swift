import SwiftUI

// MARK: - The Calm night

/// The shared Calm/Worry Jar environment: ONE painted night — near-black sky
/// into deep midnight blue, a real star field with Milky-Way detail, misty
/// moonlit ridges, and a rocky clearing whose open centre is where Aurie and
/// the jar stand. It is a static image asset (approved reference artwork with
/// the subjects removed), NOT a procedural gradient/star build, and it is
/// deliberately family-neutral: every family sees this same night, and all
/// family colour comes from Aurie and the aura in front of it.
struct CalmNightSkyView: View {
    /// Kept for call-site stability; a static image has nothing to calm.
    var reduceMotion: Bool = false

    var body: some View {
        GeometryReader { geo in
            Image("calm_night_bg")
                .resizable()
                .scaledToFill()
                // Bottom-anchored: if a wider screen (iPad) forces a vertical
                // crop, rows leave the SKY — the clearing must never be lost,
                // it's the ground the creature and jar stand on.
                .frame(width: geo.size.width, height: geo.size.height,
                       alignment: .bottom)
                .clipped()
        }
        .ignoresSafeArea()
    }
}
