import SwiftUI

// Bridges from the model's plain Rgb (validated files, don't touch) to UI
// colors. `brightness` scales toward black — the mockup sits family colors on
// a deep night backdrop, so tiles and tints usually want a dimmed shade.

extension Color {
    init(_ rgb: Rgb, brightness: Double = 1) {
        self.init(red: Double(rgb.r) / 255 * brightness,
                  green: Double(rgb.g) / 255 * brightness,
                  blue: Double(rgb.b) / 255 * brightness)
    }

    /// The family-colour backdrop fallback (§9): deep night base leaning
    /// toward the aura colour. Single source of truth — CreatureScene uses the
    /// same components so SwiftUI chrome around a SpriteView matches exactly.
    static func familyBackdrop(_ aura: Rgb) -> Color {
        let c = familyBackdropComponents(aura)
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}

/// Shared night-magic tint math for SwiftUI and SpriteKit backdrops.
func familyBackdropComponents(_ aura: Rgb) -> (r: Double, g: Double, b: Double) {
    (0.06 + Double(aura.r) / 255 * 0.16,
     0.07 + Double(aura.g) / 255 * 0.16,
     0.10 + Double(aura.b) / 255 * 0.16)
}

/// Calm Mode's softened variant: the same family tint, desaturated toward its
/// own gray and slightly dimmed — Ember still feels like Ember, just quieter.
func calmBackdropComponents(_ aura: Rgb) -> (r: Double, g: Double, b: Double) {
    let base = familyBackdropComponents(aura)
    let gray = (base.r + base.g + base.b) / 3
    func soften(_ v: Double) -> Double { (v + (gray - v) * 0.45) * 0.9 }
    return (soften(base.r), soften(base.g), soften(base.b))
}

extension UIColor {
    convenience init(_ rgb: Rgb) {
        self.init(red: CGFloat(rgb.r) / 255,
                  green: CGFloat(rgb.g) / 255,
                  blue: CGFloat(rgb.b) / 255,
                  alpha: 1)
    }
}
