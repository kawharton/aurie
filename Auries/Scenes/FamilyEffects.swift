import SpriteKit
import UIKit

/// Shared family-effect helpers.
///
/// The particle ART now lives in `FamilyParticleArt` (motifs per family) and
/// the MOTION in `ParticleField` (ambient / calm / swirl / bursts). What
/// remains here is the soft radial glow, which is a glow rather than a
/// particle, plus one accessor for the two effects that spawn a single sprite
/// with their own bespoke motion.
enum FamilyEffects {

    /// One motif from a family's set, for the few effects that spawn a single
    /// sprite with their own already-tuned motion (the Calm sparkle trail and
    /// the Worry Jar release). Everything else should compose a `ParticleField`
    /// with a `ParticleMotion` instead.
    static func trailMotif(for family: AuraFamily) -> SKTexture {
        let motifs = FamilyParticleArt.motifs(for: family)
        return FamilyParticleArt.texture(motifs[Int.random(in: 0 ..< motifs.count)])
    }

    /// Soft radial white glow (tint at the call site).
    static let radialGlow: SKTexture = {
        let size = CGSize(width: 420, height: 420)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray, locations: [0, 1])!
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                             endCenter: center, endRadius: size.width / 2, options: [])
        }
        return SKTexture(image: image)
    }()

}
