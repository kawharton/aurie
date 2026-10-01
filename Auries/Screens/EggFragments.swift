import SwiftUI

// MARK: - Seven-piece egg fragment burst
//
// RECOVERED from `hatch-sequence-polish` (b8639be, "Add animated egg
// fragment burst"), which was never merged into this branch. The motion
// model below — measured centroids, angles, travel, arc, rotation, scale,
// stagger, z-order, device-aware travel capping — is that work VERBATIM.
//
// What changed is only what the pieces are cut from. The old branch masked
// three snapshot bitmaps of its Illustrator material; here the pieces mask
// the CURRENT Blender shell view directly, so each fragment carries that
// shell's dimensional shading, highlight, markings and family tint by
// construction rather than by re-rendering.
//
// The piece masks were re-partitioned against the Blender shell's own alpha
// (see Scripts/adapt_egg_piece_masks.py): the frozen masks were mapped into
// the current silhouette and every shell pixel assigned to exactly one
// piece, verified union == shell alpha, 0 overlap, 0 gaps. So progress 0
// reassembles the intact egg exactly.

/// Per-piece burst choreography, measured from the frozen A4 piece masks.
/// `centroid` is normalised to the egg frame, so it survived the mask
/// remap unchanged. `radius` was measured at the old aspect and is ~6%
/// generous in x here; it only feeds off-screen travel capping.
struct EggFragmentSpec {
    let piece: Int          // 1-based; matches aurie_egg_piece_0N
    let centroid: UnitPoint // in the shared egg frame; rotation/scale anchor
    let angle: Double       // outward direction, degrees, y-down screen space
    let travel: CGFloat     // nominal displacement, in egg-widths (see cap)
    let arc: CGFloat        // signed perpendicular drift, in egg-widths
    let rotation: Double    // total local tumble, degrees, about `centroid`
    let scale: CGFloat      // end scale (depth cue; >1 nears the viewer)
    let duration: Double    // drift duration
    let delay: Double       // drift stagger
    let z: Double           // draw order in flight (nearer pieces above)
    let radius: CGFloat     // max centroid->edge extent, egg-widths (measured)

    /// Multiplies every piece's nominal travel. This is a BURST — the pieces
    /// need to be clear of the body fast, not drift.
    static let travelBoost: CGFloat = 1.35

    /// The Aurie appears here; also the radial origin of every trajectory.
    static let revealCenter = UnitPoint(x: 0.506, y: 0.527)

    static let all: [EggFragmentSpec] = [
        EggFragmentSpec(piece: 1, centroid: UnitPoint(x: 0.693, y: 0.352),
                        angle: -50.7, travel: 1.05, arc: 0.06, rotation: 14,
                        scale: 1.04, duration: 0.62, delay: 0.02, z: 4, radius: 0.274),
        EggFragmentSpec(piece: 2, centroid: UnitPoint(x: 0.813, y: 0.580),
                        angle: 12.7, travel: 0.95, arc: -0.05, rotation: -19,
                        scale: 0.94, duration: 0.55, delay: 0.00, z: 1, radius: 0.247),
        EggFragmentSpec(piece: 3, centroid: UnitPoint(x: 0.650, y: 0.735),
                        angle: 62.0, travel: 1.50, arc: 0.04, rotation: 9,
                        scale: 1.10, duration: 0.85, delay: 0.05, z: 7, radius: 0.312),
        EggFragmentSpec(piece: 4, centroid: UnitPoint(x: 0.400, y: 0.833),
                        angle: 104.9, travel: 1.25, arc: -0.06, rotation: -12,
                        scale: 1.06, duration: 0.78, delay: 0.04, z: 5, radius: 0.248),
        EggFragmentSpec(piece: 5, centroid: UnitPoint(x: 0.212, y: 0.684),
                        angle: 145.1, travel: 1.35, arc: 0.05, rotation: 17,
                        scale: 1.08, duration: 0.80, delay: 0.03, z: 6, radius: 0.238),
        EggFragmentSpec(piece: 6, centroid: UnitPoint(x: 0.323, y: 0.466),
                        angle: -156.2, travel: 1.15, arc: -0.04, rotation: -8,
                        scale: 0.96, duration: 0.70, delay: 0.06, z: 2, radius: 0.274),
        EggFragmentSpec(piece: 7, centroid: UnitPoint(x: 0.449, y: 0.192),
                        angle: -97.4, travel: 1.05, arc: 0.08, rotation: 6,
                        scale: 0.98, duration: 0.66, delay: 0.00, z: 3, radius: 0.311),
    ]

    /// Device-aware final travel (C2A2 rule 1): the approved direction and
    /// relative hierarchy are preserved, but each endpoint is capped by the
    /// distance from this piece's rest centroid to the stage (screen) edge
    /// along its own trajectory, expanded by the piece's radius — so on a
    /// small screen a fragment stays readable through the middle of the
    /// flight and fully exits only near the end, while a large screen keeps
    /// the nominal travel. `rest` and `stage` share one coordinate space.
    func finalTravel(rest: CGPoint, stage: CGRect, eggWidth w: CGFloat) -> CGFloat {
        let a = angle * .pi / 180
        let dir = CGVector(dx: cos(a), dy: sin(a))
        let expanded = stage.insetBy(dx: -radius * w, dy: -radius * w)
        var exit = CGFloat.greatestFiniteMagnitude
        if dir.dx > 0.0001 { exit = min(exit, (expanded.maxX - rest.x) / dir.dx) }
        if dir.dx < -0.0001 { exit = min(exit, (expanded.minX - rest.x) / dir.dx) }
        if dir.dy > 0.0001 { exit = min(exit, (expanded.maxY - rest.y) / dir.dy) }
        if dir.dy < -0.0001 { exit = min(exit, (expanded.minY - rest.y) / dir.dy) }
        // Displacement boost: the approved per-piece hierarchy and direction
        // are preserved, but every endpoint is pushed further out so the
        // character's silhouette is clear of shell early in the flight
        // rather than at the end of it.
        return min(travel * Self.travelBoost * w, max(exit, 0) + w * 0.03)
    }

    /// Pose at progress f in 0...1 along a trajectory of `finalTravel`
    /// points. Linear in f — the C2A2 two-phase animation (quick release,
    /// slow magical drift) shapes f over time, so offset, rotation, and
    /// scale stay in lockstep.
    func pose(at f: CGFloat, eggWidth w: CGFloat,
              finalTravel: CGFloat? = nil) -> EggFragmentPose {
        let a = angle * .pi / 180
        let dir = CGVector(dx: cos(a), dy: sin(a))
        let perp = CGVector(dx: -dir.dy, dy: dir.dx)
        let t = finalTravel ?? travel * w
        let dx = (dir.dx * t + perp.dx * arc * w) * f
        let dy = (dir.dy * t + perp.dy * arc * w) * f
        return EggFragmentPose(offset: CGSize(width: dx, height: dy),
                               rotation: .degrees(rotation * f),
                               scale: 1 + (scale - 1) * f)
    }
}


/// One fragment's transform at an instant. Identity = seamless assembly.
struct EggFragmentPose {
    var offset: CGSize = .zero
    var rotation: Angle = .zero
    var scale: CGFloat = 1
}

// MARK: - Rendering

/// The seven shell fragments, each one the SAME shell view seen through its
/// own piece mask and transformed about its OWN centroid (pieces tumble
/// locally, they never orbit the egg centre).
///
/// At `t = 0` this is pixel-identical to the intact egg: the masks partition
/// the shell alpha exactly, so nothing moves, appears or disappears at the
/// moment of separation.
struct EggBurstFragmentsView: View {
    /// ONE precomposited bitmap of the intact egg — Blender shell, family
    /// tint and the completed fracture network already baked in. Every piece
    /// is a mask of THIS image, so no fragment re-runs tint or effects.
    let shell: UIImage
    /// 0 = assembled, 1 = fully burst. Per-piece stagger is derived.
    let t: Double
    /// Stage size, for the device-aware travel cap.
    let stageSize: CGSize

    /// Longest piece timeline, used to normalise the shared driver.
    private static var span: Double {
        EggFragmentSpec.all.map { $0.delay + $0.duration }.max() ?? 1
    }

    private func progress(_ spec: EggFragmentSpec) -> Double {
        let start = spec.delay / Self.span
        let end = (spec.delay + spec.duration) / Self.span
        guard end > start else { return t }
        return min(max((t - start) / (end - start), 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let frame = geo.frame(in: .global)
            let stage = CGRect(x: -frame.minX, y: -frame.minY,
                               width: stageSize.width, height: stageSize.height)
            ZStack {
                ForEach(EggFragmentSpec.all, id: \.piece) { spec in
                    let f = progress(spec)
                    let rest = CGPoint(x: spec.centroid.x * w, y: spec.centroid.y * h)
                    let capped = spec.finalTravel(rest: rest, stage: stage, eggWidth: w)
                    let pose = spec.pose(at: f, eggWidth: w, finalTravel: capped)
                    Image(uiImage: shell)
                        .resizable()
                        .mask {
                            // Hard-partition mask: no dilation, so adjacent
                            // pieces cannot double-composite the antialiased
                            // edge and thin the crack strokes crossing it.
                            Image("aurie_egg_piece_0\(spec.piece)")
                                .resizable()
                        }
                        .scaleEffect(pose.scale, anchor: spec.centroid)
                        .rotationEffect(pose.rotation, anchor: spec.centroid)
                        .offset(pose.offset)
                        // Opaque through the OPENING — the first third of the
                        // piece's flight — so the physical shell reveal stays
                        // readable, then a progressive fade that is complete
                        // by 75%. At 66% (the original) giant chunks orbited
                        // Aurie for most of a second; at 25% they vanished
                        // before the reveal could be enjoyed.
                        .opacity(f < 0.35
                                 ? 1 : max(0, 1 - (f - 0.35) / 0.65))
                        .zIndex(spec.z)
                }
            }
        }
    }
}
