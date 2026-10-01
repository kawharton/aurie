import SwiftUI

/// Home-only visual tokens (Stage A of the Home refactor). One source of truth
/// so layout literals aren't scattered across the Home views. Layout values
/// are proportional where they depend on device size, so the same composition
/// scales across iPhone and iPad portrait rather than floating a phone-width
/// column in an empty iPad canvas.
enum HomeTokens {

    // MARK: Layout
    /// Readable-chrome cap: header + Daily Lift stay within this width and
    /// centre on iPad rather than stretching edge to edge.
    static let contentMaxWidth: CGFloat = 640
    /// The creature PLAY SPACE gets its own, much wider budget so it uses
    /// nearly the full iPad width (minus margins) — decoupled from the chrome.
    static let playAreaMaxWidth: CGFloat = 900
    /// Side margin as a fraction of width, with a sensible floor.
    static func horizontalMargin(width: CGFloat) -> CGFloat { max(width * 0.055, 20) }
    /// A small reserved band under the header so the creature sits lower-centre
    /// with room for the speech bubble, without a huge empty upper half.
    static let bubbleReserveFraction: CGFloat = 0.06
    /// Readable cap for the speech bubble on any device; narrower play views
    /// cap it tighter (view width minus edge padding).
    static let bubbleMaxWidth: CGFloat = 320

    // MARK: Chrome (one consistent system)
    static let cardCornerRadius: CGFloat = 20
    static let controlMinSize: CGFloat = 44
    static let chromeShadow = Color.black.opacity(0.25)

    // MARK: Background depth
    static let bloomOpacity: Double = 0.55
    static let vignetteOpacity: Double = 0.5
    static let moteCount = 16
}
