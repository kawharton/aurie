// RECOVERED from the frozen A4 fracture design (hatch-sequence-polish,
// commit 860ec09) — DO NOT EDIT BY HAND.
//
// The original coordinates were normalised to the 1570x2048 egg CANVAS.
// They are re-normalised here to the egg's own bounding box, which is the
// frame the current Blender shell is drawn in, so the network lands on the
// approved silhouette. Geometry is otherwise untouched: same branches, same
// spurs, same seven tap-5 rim seams.

import CoreGraphics

/// The A4 crack network: per-tap main branches + decorative spurs
/// (same warm dark treatment, thinner stroke), and the seven short
/// tap-5 rim seams. All geometry is frozen.
enum EggFracture {
    struct Stage {
        let main: [[CGPoint]]
        let spurs: [[CGPoint]]
    }

    /// Cumulative additions for accepted taps 1-4.
    static let tapStages: [Stage] = [
        Stage(main: [
            [CGPoint(x: 0.48008, y: 0.21080), CGPoint(x: 0.46475, y: 0.25034), CGPoint(x: 0.46436, y: 0.29248), CGPoint(x: 0.44022, y: 0.33046)],
        ], spurs: [
        ]),
        Stage(main: [
            [CGPoint(x: 0.44022, y: 0.33046), CGPoint(x: 0.48540, y: 0.37137), CGPoint(x: 0.50890, y: 0.42363), CGPoint(x: 0.57404, y: 0.45405), CGPoint(x: 0.60960, y: 0.50000)],
        ], spurs: [
            [CGPoint(x: 0.46461, y: 0.26553), CGPoint(x: 0.44709, y: 0.27817), CGPoint(x: 0.42163, y: 0.28342), CGPoint(x: 0.40654, y: 0.29832)],
            [CGPoint(x: 0.51478, y: 0.42637), CGPoint(x: 0.49467, y: 0.44534), CGPoint(x: 0.46197, y: 0.45232), CGPoint(x: 0.43879, y: 0.46835)],
        ]),
        Stage(main: [
            [CGPoint(x: 0.60960, y: 0.50000), CGPoint(x: 0.56330, y: 0.54220), CGPoint(x: 0.48962, y: 0.56644), CGPoint(x: 0.46391, y: 0.62213), CGPoint(x: 0.41034, y: 0.65956)],
            [CGPoint(x: 0.44022, y: 0.33046), CGPoint(x: 0.38273, y: 0.32847), CGPoint(x: 0.33550, y: 0.29820), CGPoint(x: 0.27830, y: 0.29538), CGPoint(x: 0.22185, y: 0.29053), CGPoint(x: 0.17012, y: 0.27262), CGPoint(x: 0.15510, y: 0.27370)],
            [CGPoint(x: 0.44022, y: 0.33046), CGPoint(x: 0.49959, y: 0.29903), CGPoint(x: 0.54691, y: 0.25833), CGPoint(x: 0.57960, y: 0.20639), CGPoint(x: 0.66061, y: 0.19158), CGPoint(x: 0.70619, y: 0.14955), CGPoint(x: 0.74064, y: 0.12656)],
            [CGPoint(x: 0.60960, y: 0.50000), CGPoint(x: 0.67147, y: 0.49395), CGPoint(x: 0.73075, y: 0.47664), CGPoint(x: 0.80113, y: 0.50744), CGPoint(x: 0.86277, y: 0.50038), CGPoint(x: 0.91649, y: 0.45894), CGPoint(x: 0.94353, y: 0.45818)],
        ], spurs: [
        ]),
        Stage(main: [
            [CGPoint(x: 0.60960, y: 0.50000), CGPoint(x: 0.66921, y: 0.54429), CGPoint(x: 0.72783, y: 0.58925), CGPoint(x: 0.78253, y: 0.63684), CGPoint(x: 0.85878, y: 0.66999), CGPoint(x: 0.88753, y: 0.73496), CGPoint(x: 0.93514, y: 0.76507)],
            [CGPoint(x: 0.41034, y: 0.65956), CGPoint(x: 0.44962, y: 0.71146), CGPoint(x: 0.45591, y: 0.77339), CGPoint(x: 0.50657, y: 0.82182), CGPoint(x: 0.53133, y: 0.87814), CGPoint(x: 0.56444, y: 0.93192), CGPoint(x: 0.59384, y: 0.96283)],
            [CGPoint(x: 0.41034, y: 0.65956), CGPoint(x: 0.35765, y: 0.69343), CGPoint(x: 0.32907, y: 0.74156), CGPoint(x: 0.29594, y: 0.78700), CGPoint(x: 0.22337, y: 0.80911), CGPoint(x: 0.19391, y: 0.85672), CGPoint(x: 0.17037, y: 0.87255)],
            [CGPoint(x: 0.41034, y: 0.65956), CGPoint(x: 0.34472, y: 0.63969), CGPoint(x: 0.27625, y: 0.62461), CGPoint(x: 0.22640, y: 0.57840), CGPoint(x: 0.14861, y: 0.57886), CGPoint(x: 0.07795, y: 0.56743), CGPoint(x: 0.04600, y: 0.54909)],
        ], spurs: [
            [CGPoint(x: 0.60960, y: 0.50000), CGPoint(x: 0.62923, y: 0.53086), CGPoint(x: 0.65339, y: 0.56052), CGPoint(x: 0.65771, y: 0.59542)],
            [CGPoint(x: 0.41034, y: 0.65956), CGPoint(x: 0.38319, y: 0.66930), CGPoint(x: 0.35277, y: 0.67168), CGPoint(x: 0.32473, y: 0.67942)],
        ]),
    ]

    /// Tap 5: the seven seams that complete each branch to the rim.
    static let seams: [[CGPoint]] = [
        [CGPoint(x: 0.15510, y: 0.27370), CGPoint(x: 0.11487, y: 0.27657)],
        [CGPoint(x: 0.74064, y: 0.12656), CGPoint(x: 0.75987, y: 0.11373), CGPoint(x: 0.77023, y: 0.10634)],
        [CGPoint(x: 0.94353, y: 0.45818), CGPoint(x: 0.97755, y: 0.45722)],
        [CGPoint(x: 0.93514, y: 0.76507), CGPoint(x: 0.95219, y: 0.77586), CGPoint(x: 0.96630, y: 0.78528)],
        [CGPoint(x: 0.59384, y: 0.96283), CGPoint(x: 0.61154, y: 0.98143), CGPoint(x: 0.61567, y: 0.99401)],
        [CGPoint(x: 0.17037, y: 0.87255), CGPoint(x: 0.14246, y: 0.89133), CGPoint(x: 0.13946, y: 0.89447)],
        [CGPoint(x: 0.04600, y: 0.54909), CGPoint(x: 0.02027, y: 0.53433), CGPoint(x: 0.01469, y: 0.53279)],
    ]
}
