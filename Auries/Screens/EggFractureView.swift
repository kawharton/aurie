import SwiftUI

/// Draws the recovered A4 fracture network over the current Blender shell.
///
/// The old branch's three-stage `CrackShape` placeholder cannot express this:
/// the approved progression is FOUR cumulative tap stages (main branches plus
/// thinner decorative spurs) followed by SEVEN short rim seams on tap five,
/// and it is that seam completion that divides the shell into the seven
/// pieces the burst then separates.
///
/// Each stage draws on with `.trim`, so a tap grows its branches rather than
/// snapping them in, and everything already drawn stays drawn.
struct EggFractureView: View {
    /// Draw-on progress for tap stages 1...4 (index 0 = tap 1).
    let stageProgress: [CGFloat]
    /// Draw-on progress for the seven tap-5 rim seams.
    let seamProgress: CGFloat

    /// Warm dark fracture line, matching the recovered treatment.
    private let ink = Color.black.opacity(0.62)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                ForEach(Array(EggFracture.tapStages.enumerated()), id: \.offset) { i, stage in
                    let p = i < stageProgress.count ? stageProgress[i] : 0
                    // Main branches carry the full weight…
                    polylines(stage.main, w: w, h: h)
                        .trim(from: 0, to: p)
                        .stroke(ink, style: StrokeStyle(lineWidth: 3.2,
                                                        lineCap: .round,
                                                        lineJoin: .round))
                    // …spurs are the same colour, thinner (recovered rule).
                    polylines(stage.spurs, w: w, h: h)
                        .trim(from: 0, to: p)
                        .stroke(ink, style: StrokeStyle(lineWidth: 2.0,
                                                        lineCap: .round,
                                                        lineJoin: .round))
                }
                // Tap 5: the seams that reach the rim and complete the seven
                // shell pieces. Until these land, the egg is cracked but not
                // yet divided.
                polylines(EggFracture.seams, w: w, h: h)
                    .trim(from: 0, to: seamProgress)
                    .stroke(ink, style: StrokeStyle(lineWidth: 3.2,
                                                    lineCap: .round,
                                                    lineJoin: .round))
            }
        }
    }

    private func polylines(_ lines: [[CGPoint]], w: CGFloat, h: CGFloat) -> Path {
        var path = Path()
        for line in lines where line.count > 1 {
            path.move(to: CGPoint(x: line[0].x * w, y: line[0].y * h))
            for p in line.dropFirst() {
                path.addLine(to: CGPoint(x: p.x * w, y: p.y * h))
            }
        }
        return path
    }
}
