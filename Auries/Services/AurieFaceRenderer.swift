import UIKit

/// Draws the expression catalogue as real geometry.
///
/// WHY THIS EXISTS. The creature's face used to be two baked bitmaps: one
/// texture with BOTH eyes drawn into it, and one mouth picked at hatch and
/// never touched again. An expression could therefore only scale or rotate
/// that eye pair — it could not narrow one eye, cross them, close them into
/// crescents, or change the mouth at all. Every "expression" rendered as the
/// same face. This renderer replaces the pair of bitmaps per expression, so
/// the geometry actually changes.
///
/// It follows the approved 3D catalogue's language rather than inventing a
/// second one: charcoal eye shapes with two catchlights, an eyelid that cuts
/// the eye from the top, gaze offsets, and a small set of mouth treatments
/// (smile / open / round / wavy / frown / smirk).
///
/// TODO(art): when per-expression sprites exist (ART_GUIDE naming, e.g.
/// `eyes_03_happy`), prefer `UIImage(named:)` here and keep this as the
/// fallback — callers never change.
enum AurieFaceRenderer {

    // Canvas is generous so tilted, crossed and crescent eyes have room; the
    // sprites are centre-anchored, so the transparent margin costs nothing.
    private static let eyeCanvas = CGSize(width: 190, height: 130)
    private static let mouthCanvas = CGSize(width: 130, height: 90)
    private static let ink = UIColor(white: 0.11, alpha: 1)

    private struct EyeSpec {
        var rx: CGFloat = 20          // half-width
        var ry: CGFloat = 25          // half-height
        var lid: CGFloat = 0          // 0 open .. 1 shut, cuts from the top
        var tilt: CGFloat = 0         // degrees, mirrored (outer corner up)
        var tiltAbs: CGFloat = 0      // degrees, same way on both eyes
        var dx: CGFloat = 0           // gaze, both eyes together
        var dxIn: CGFloat = 0         // each eye toward the other (crossed)
        var dy: CGFloat = 0
        var closed = false            // draw as a happy crescent instead
        var catchScale: CGFloat = 1
    }

    private enum MouthKind { case smile, tiny, open, round, wavy, frown, smirk }

    private struct MouthSpec {
        var kind: MouthKind = .smile
        var width: CGFloat = 1
        var depth: CGFloat = 1
    }

    private static func spec(_ faceId: String) -> (EyeSpec, MouthSpec) {
        switch faceId {
        case "excited":
            return (EyeSpec(rx: 22, ry: 28, catchScale: 1.15),
                    MouthSpec(kind: .open, width: 1.15, depth: 1.35))
        case "sleepy":
            return (EyeSpec(ry: 26, lid: 0.62, tilt: -4),
                    MouthSpec(kind: .tiny, width: 0.55, depth: 0.55))
        case "shy":
            return (EyeSpec(rx: 19, ry: 23, lid: 0.30, tilt: -6, dx: 6, dy: 4),
                    MouthSpec(kind: .tiny, width: 0.62, depth: 0.85))
        case "curious":
            return (EyeSpec(rx: 21, ry: 26, dy: -3, catchScale: 1.05),
                    MouthSpec(kind: .round, width: 0.72, depth: 0.72))
        case "surprised":
            return (EyeSpec(rx: 23, ry: 30, catchScale: 1.1),
                    MouthSpec(kind: .round, width: 1.0, depth: 1.0))
        case "mischievous":
            return (EyeSpec(rx: 22, ry: 24, lid: 0.50, tilt: 17),
                    MouthSpec(kind: .smirk, width: 1.12, depth: 1.15))
        case "worried":
            return (EyeSpec(rx: 20, ry: 26, lid: 0.12, tilt: -14),
                    MouthSpec(kind: .wavy, width: 0.85, depth: 0.7))
        case "pouty":
            return (EyeSpec(ry: 24, lid: 0.24, tilt: -6),
                    MouthSpec(kind: .frown, width: 0.8, depth: 0.85))
        case "delighted":
            return (EyeSpec(rx: 22, ry: 25, closed: true),
                    MouthSpec(kind: .open, width: 1.3, depth: 1.5))
        case "dizzy":
            // Woozy, not alien. This used `swirl: true` with an oversized
            // catchlight, which read as spiral alien eyes. Squeezed-shut arcs
            // with a slight outward tilt say "the world is spinning" and stay
            // cute. `swirl` is now referenced by NO face, so the spiral eye
            // can no longer appear anywhere in the app.
            return (EyeSpec(rx: 22, ry: 25, tiltAbs: 9, closed: true),
                    MouthSpec(kind: .wavy, width: 1.05, depth: 0.45))
        case "yawn":
            return (EyeSpec(ry: 26, lid: 0.78, tilt: -4),
                    MouthSpec(kind: .round, width: 0.62, depth: 1.55))
        case "calm":
            return (EyeSpec(ry: 25, lid: 0.46, tilt: -3),
                    MouthSpec(kind: .tiny, width: 0.70, depth: 0.80))
        default:      // happy
            return (EyeSpec(), MouthSpec(kind: .smile))
        }
    }

    // MARK: - Public

    static func eyes(_ faceId: String) -> UIImage {
        if let cached = eyeCache[faceId] { return cached }
        let image = drawEyes(spec(faceId).0)
        eyeCache[faceId] = image
        return image
    }

    static func mouth(_ faceId: String) -> UIImage {
        if let cached = mouthCache[faceId] { return cached }
        let image = drawMouth(spec(faceId).1)
        mouthCache[faceId] = image
        return image
    }

    private static var eyeCache: [String: UIImage] = [:]
    private static var mouthCache: [String: UIImage] = [:]

    // MARK: - Drawing

    private static func drawEyes(_ s: EyeSpec) -> UIImage {
        UIGraphicsImageRenderer(size: eyeCanvas).image { ctx in
            let c = ctx.cgContext
            let midY = eyeCanvas.height / 2
            let spread: CGFloat = 37
            for side in [CGFloat(-1), 1] {
                let cx = eyeCanvas.width / 2 + side * spread + s.dx - side * s.dxIn
                let cy = midY + s.dy
                c.saveGState()
                c.translateBy(x: cx, y: cy)
                c.rotate(by: (side * s.tilt + s.tiltAbs) * .pi / 180)
                if s.closed {
                    // Happy crescent: a stroked arc bowing upward.
                    ink.setStroke()
                    c.setLineWidth(7)
                    c.setLineCap(.round)
                    c.addArc(center: CGPoint(x: 0, y: 6), radius: s.rx,
                             startAngle: .pi, endAngle: 0, clockwise: true)
                    c.strokePath()
                    c.restoreGState()
                    continue
                }
                // Eye body, clipped by the lid so it can close from the top.
                c.saveGState()
                if s.lid > 0 {
                    let top = -s.ry + 2 * s.ry * s.lid
                    c.clip(to: CGRect(x: -s.rx - 4, y: top,
                                      width: s.rx * 2 + 8,
                                      height: s.ry - top + 4))
                }
                ink.setFill()
                c.fillEllipse(in: CGRect(x: -s.rx, y: -s.ry,
                                         width: s.rx * 2, height: s.ry * 2))
                c.restoreGState()

                // Catchlights. Hidden once the lid covers where they sit —
                // otherwise they float on the skin above a half-closed eye.
                if s.lid < 0.55 {
                    UIColor.white.setFill()
                    let big = 8.5 * s.catchScale
                    let small = 4.5 * s.catchScale
                    c.fillEllipse(in: CGRect(x: -s.rx * 0.55, y: -s.ry * 0.62,
                                             width: big * 2, height: big * 2))
                    c.fillEllipse(in: CGRect(x: s.rx * 0.10, y: s.ry * 0.10,
                                             width: small * 2, height: small * 2))
                }
                c.restoreGState()
            }
        }
    }

    private static func drawMouth(_ m: MouthSpec) -> UIImage {
        UIGraphicsImageRenderer(size: mouthCanvas).image { ctx in
            let c = ctx.cgContext
            let cx = mouthCanvas.width / 2
            let cy = mouthCanvas.height / 2
            let w = 26 * m.width
            let d = 14 * m.depth
            ink.setStroke()
            ink.setFill()
            c.setLineWidth(6)
            c.setLineCap(.round)
            switch m.kind {
            case .smile, .tiny:
                c.move(to: CGPoint(x: cx - w, y: cy - d * 0.35))
                c.addQuadCurve(to: CGPoint(x: cx + w, y: cy - d * 0.35),
                               control: CGPoint(x: cx, y: cy + d * 1.4))
                c.strokePath()
            case .frown:
                c.move(to: CGPoint(x: cx - w, y: cy + d * 0.5))
                c.addQuadCurve(to: CGPoint(x: cx + w, y: cy + d * 0.5),
                               control: CGPoint(x: cx, y: cy - d * 1.2))
                c.strokePath()
            case .smirk:
                c.move(to: CGPoint(x: cx - w, y: cy + d * 0.25))
                c.addQuadCurve(to: CGPoint(x: cx + w * 0.95, y: cy - d * 1.25),
                               control: CGPoint(x: cx, y: cy + d * 1.2))
                c.strokePath()
            case .wavy:
                c.move(to: CGPoint(x: cx - w, y: cy))
                c.addCurve(to: CGPoint(x: cx + w, y: cy),
                           control1: CGPoint(x: cx - w * 0.3, y: cy + d * 1.5),
                           control2: CGPoint(x: cx + w * 0.3, y: cy - d * 1.5))
                c.strokePath()
            case .round:
                c.fillEllipse(in: CGRect(x: cx - w * 0.55, y: cy - d * 0.9,
                                         width: w * 1.1, height: d * 1.8))
            case .open:
                // Filled half-ellipse: flat lip line on top, curved below.
                let rect = CGRect(x: cx - w * 0.85, y: cy - d * 0.9,
                                  width: w * 1.7, height: d * 2.4)
                c.saveGState()
                c.clip(to: CGRect(x: rect.minX, y: cy - d * 0.2,
                                  width: rect.width, height: rect.height))
                c.fillEllipse(in: rect)
                c.restoreGState()
            }
        }
    }
}
