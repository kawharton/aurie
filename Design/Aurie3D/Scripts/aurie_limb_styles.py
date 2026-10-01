"""Aurie launch limb library v3 — sculpted rebuild to MATCH
References/limbs_to_copy.png (the visual target, not inspiration).

Rebuilt from scratch after the v2 catalog was rejected (too thin,
too cylindrical, too small, insufficiently plush). Design priorities:
READABILITY at full-character size, strong silhouettes, cute plush
proportions, subdivision-quality curvature. Geometry: Catmull-Rom
spline sweeps (36 samples, 24-seg rings) with smooth thickness
variation and true hemispherical end caps — no capsules, no rods, no
faceted bends. Designed on ROUND first; per-body scale multiplier
adapts to Tall/Wide.

ACTIVE ARMS — ALL THREE FROZEN 2026-08-17 ("the arm/hand work is good
enough now"). Do not retune arm geometry, hand size, digit length or
the thumb without an explicit instruction. Two more concepts are still
to be designed — arm_03/arm_04 are free slots:
  arm_00 Rounded Flipper — broad flattened-teardrop plush flipper
                           (FROZEN — benchmark for clean simple arms)
  arm_01 Tiny Hands      — short soft forearm + plush hand: 3 extended
                           digits + an opposable tapered thumb (FROZEN)
  arm_02 Noodle Arms     — LONGEST: slim dangling J-curve noodle, same
                           hand anatomy as arm_01 (FROZEN)

HELD OUT (history only, never fill the free slots with these):
  _wave_held_out         — lifted waving arm, never user-reviewed
  _belly_paws_removed    — Belly Paws, removed by user direction

ACTIVE LEGS — 4 styles (a 5th is still to be designed; leg_04's id is
free but must NOT be a Tiny Boots revival). Only leg_01 is APPROVED;
the other three are still under review. LEG_BODY_LIFT tells the harness
how much the body rides up so that style's feet clear the underside:
  leg_00 Short Standing Legs — thick plush toddler columns + broad
                               rounded feet; body elevated
  leg_01 Bounce Feet         — oversized bulbous ball feet, forward-set
                               (APPROVED / FROZEN)
  leg_02 Chibi Stance        — thick short out-angled stubs at a WIDE
                               squat planted stance
  leg_03 Splayed Feet        — fat plush pods on an outward diagonal

REMOVED: leg_04 Tiny Boots (too redundant with Short Standing).
"""

import math

try:
    import bmesh
    import bpy
except ImportError:
    bmesh = bpy = None

# Per-style body elevation. Each value is the minimum that lets THAT
# foot geometry clear Round's underside: at 0.0 the big ball feet and
# the flat splayed pods were both swallowed by the body. Approved
# anchors (FOOT_X / FOOT_Y) are untouched - this is elevation only.
# leg_01 is APPROVED and must keep its value.
LEG_BODY_LIFT = {"leg_00": 0.17, "leg_01": 0.22, "leg_02": 0.09,
                 "leg_03": 0.17,
                 # 2026-09-13 metaball styles, user-approved (ids
                 # renumbered from the experiments per user instruction)
                 "leg_04": 0.26, "leg_05": 0.31}


def _sphere(col, name, loc, scale, mat, rot=None, segs=48, rings=24,
            flatten=0.0, flat_start=-0.5):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings,
                              radius=1.0)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    if flatten > 0.0:
        for v in mesh.vertices:
            if v.co.z < flat_start:
                u = (flat_start - v.co.z) / (1.0 + flat_start)
                v.co.z += flatten * u * u
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    ob.location = loc
    ob.scale = scale
    if rot:
        ob.rotation_euler = rot
    ob.data.materials.append(mat)
    col.objects.link(ob)
    return ob


def _cr(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return tuple(
        0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t
               + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
               + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3)
        for k in range(3))


def _resample(ctrl, radii_x, radii_y, n=36):
    """Catmull-Rom through ctrl points; radii interpolated smoothly."""
    pts = [ctrl[0]] + list(ctrl) + [ctrl[-1]]
    m = len(ctrl) - 1
    path, rxs, rys = [], [], []
    for i in range(n + 1):
        u = i / n * m
        seg = min(int(u), m - 1)
        t = u - seg
        path.append(_cr(pts[seg], pts[seg + 1], pts[seg + 2],
                        pts[seg + 3], t))
        fu = u / m * (len(radii_x) - 1)
        j = min(int(fu), len(radii_x) - 2)
        ft = fu - j
        rxs.append(radii_x[j] * (1 - ft) + radii_x[j + 1] * ft)
        rys.append(radii_y[j] * (1 - ft) + radii_y[j + 1] * ft)
    return path, rxs, rys


def _tube(col, name, mat, origin, ctrl, radii_x, radii_y=None, segs=24):
    """Plush sculpted tube: CR-spline path, smooth radii, true
    hemispherical rounded caps."""
    if radii_y is None:
        radii_y = radii_x
    path, rxs, rys = _resample(ctrl, radii_x, radii_y)

    def cap(p_end, p_prev, r_x, r_y, flip):
        d = [p_end[k] - p_prev[k] for k in range(3)]
        n = math.sqrt(sum(c * c for c in d)) or 1.0
        d = [c / n for c in d]
        out_p, out_rx, out_ry = [], [], []
        for f, rr in ((0.38, 0.925), (0.68, 0.735), (0.88, 0.475),
                      (0.985, 0.17)):
            out_p.append(tuple(p_end[k] + d[k] * r_x * f
                               for k in range(3)))
            out_rx.append(r_x * rr)
            out_ry.append(r_y * rr)
        return out_p, out_rx, out_ry

    hp, hrx, hry = cap(path[0], path[1], rxs[0], rys[0], True)
    tp, trx, try_ = cap(path[-1], path[-2], rxs[-1], rys[-1], False)
    path = hp[::-1] + path + tp
    rxs = hrx[::-1] + rxs + trx
    rys = hry[::-1] + rys + try_
    n = len(path)
    verts, faces = [], []
    for i in range(n):
        a = path[max(0, i - 1)]
        b = path[min(n - 1, i + 1)]
        t = [b[k] - a[k] for k in range(3)]
        tl = math.sqrt(sum(c * c for c in t)) or 1.0
        t = [c / tl for c in t]
        ref = (0.0, 1.0, 0.0) if abs(t[1]) < 0.92 else (1.0, 0.0, 0.0)
        n1 = [t[1] * ref[2] - t[2] * ref[1],
              t[2] * ref[0] - t[0] * ref[2],
              t[0] * ref[1] - t[1] * ref[0]]
        nl = math.sqrt(sum(c * c for c in n1)) or 1.0
        n1 = [c / nl for c in n1]
        n2 = [t[1] * n1[2] - t[2] * n1[1], t[2] * n1[0] - t[0] * n1[2],
              t[0] * n1[1] - t[1] * n1[0]]
        for j in range(segs):
            th = 2.0 * math.pi * j / segs
            verts.append(tuple(path[i][k]
                               + n1[k] * math.cos(th) * rxs[i]
                               + n2[k] * math.sin(th) * rys[i]
                               for k in range(3)))
    for i in range(n - 1):
        for j in range(segs):
            a2 = i * segs + j
            b2 = i * segs + (j + 1) % segs
            faces.append((a2, b2, b2 + segs, a2 + segs))
    # close both tips with apex fans (open rings showed pinholes)
    def apex(p_end, p_next, r_end):
        d = [p_end[k] - p_next[k] for k in range(3)]
        nl = math.sqrt(sum(c * c for c in d)) or 1.0
        return tuple(p_end[k] + d[k] / nl * r_end * 0.5 for k in range(3))
    ah = len(verts)
    verts.append(apex(path[0], path[1], rxs[0]))
    at = len(verts)
    verts.append(apex(path[-1], path[-2], rxs[-1]))
    for j in range(segs):
        faces.append((ah, (j + 1) % segs, j))
        base = (n - 1) * segs
        faces.append((at, base + j, base + (j + 1) % segs))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    ob.location = origin
    ob.data.materials.append(mat)
    col.objects.link(ob)
    return ob


def _thumb(col, name, mat, tip, m, side, out_dx, dz, r=0.062):
    """Single deeply-fused thumb bump on a palm bulb — the mitten
    suggestion. ~75% embedded so it reads sculpted, never glued."""
    _sphere(col, name, (tip[0] + side * out_dx * m, tip[1] - 0.035 * m,
                        tip[2] + dz * m),
            (r * m, r * 0.92 * m, r * 1.08 * m), mat)



# ---- continuous implicit hand/arm surfaces --------------------------------
# Gaussian blobby field F(p) = sum e*exp(-|p-c|^2/r^2), iso-surface at 1.0
# (so a lone element's surface radius is exactly r). Meshed with marching
# TETRAHEDRA -> ONE watertight continuous mesh: palm and finger bumps flow
# together with soft valleys, never glued primitives. Used by the
# hand-bearing arm styles; arm_00 keeps its swept form.

LAST_HAND = {}        # (name, side) -> palm centre, world coords
LAST_HAND_FRAME = {}  # (name, side) -> (palm centre, f, sx, rp)
#                       f = distal axis (fingers point along it),
#                       sx = in-plane fan axis. Render harnesses use
#                       this to aim close-up cameras at the digits.


def _n3(v):
    n = math.sqrt(sum(c * c for c in v)) or 1.0
    return tuple(c / n for c in v)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def _add(a, b, k=1.0):
    return tuple(a[i] + b[i] * k for i in range(3))


def _spine_elements(origin, ctrl, radii, n=16):
    """Chain of field elements along the arm path (absolute coords).
    Radii are trimmed for blend inflation."""
    path, rxs, _ = _resample(ctrl, radii, radii, n=n)
    return [(_add(origin, p), r * 0.92, 1.0) for p, r in zip(path, rxs)]


def _hand_elements(wrist, f, rp, inward, n_fingers=3, reach=1.0,
                   r_arm=None):
    """Palm + EXTENDED finger + thumb elements forming one plush hand.

    f: distal direction (fingers protrude along it); the finger fan is
    laid out in the x-z plane so the digits read from the front.

    Each digit is a 3-element chain (knuckle -> mid -> tip) rather than
    a single surface bump, so it projects clearly off the palm instead
    of dissolving into it, while staying stubby and plush (tip r 0.34
    rp). `reach` scales the projection per style.

    Readability rules learned from blind review — grooves that only
    shade do NOT survive at app scale, so the digit separations must
    cut the SILHOUETTE: the fan is wide (+-0.74 rp at the knuckles)
    and the tips splay further (0.40 rp) to open real notches between
    them. Chain elements use a steep falloff (hardness 3+) to keep
    those valleys deep; palm and wrist use a soft falloff so the whole
    thing is still ONE continuous surface.

    r_arm = radius of the incoming arm at the wrist. The bridge
    element never goes below it, otherwise the hand looks pinched onto
    the arm (measured 0.86x on the slimmed noodle = visible jump)."""
    f = _n3(f)
    sx = _n3(_cross(f, (0.0, 1.0, 0.0)))
    if sum(sx[i] * inward[i] for i in range(3)) < 0:
        sx = tuple(-c for c in sx)          # sx now points inward
    c = _add(wrist, f, 0.52 * rp)
    r_bridge = max(0.57 * rp, r_arm if r_arm else 0.0)
    els = [(wrist, r_bridge, 1.0),                        # wrist bridge
           (c, 0.66 * rp, 1.2),
           (_add(c, sx, 0.31 * rp), 0.60 * rp, 1.2),
           (_add(c, sx, -0.31 * rp), 0.60 * rp, 1.2)]
    spread = (-0.74, 0.0, 0.74) if n_fingers == 3 else (-0.46, 0.46)
    knuckle, length = 0.70 * rp, 0.66 * rp * reach
    for o in spread:
        base = _add(_add(c, f, knuckle), sx, o * rp)
        els.append((base, 0.43 * rp, 3.0))
        els.append((_add(_add(base, f, 0.50 * length), sx,
                         o * 0.16 * rp), 0.40 * rp, 3.4))
        els.append((_add(_add(base, f, length), sx, o * 0.33 * rp),
                    0.36 * rp, 3.6))
    # ---- thumb: an OPPOSABLE STUB OF THE PALM, not a fourth finger --
    # Everything here exists to keep it from reading as a digit in the
    # row: the root sits high on the palm's SIDE (proximal of the
    # finger knuckles, not on the digit edge), it is broad and carries
    # the palm's own soft falloff so it swells out of the palm instead
    # of necking down, it travels mostly SIDEWAYS with a slight
    # forward lean so it opposes the fingers rather than paralleling
    # them, and it hooks gently back toward them at the tip. The low
    # hardnesses keep the thumb web a shallow dish rather than a
    # finger-length cleft.
    nf = _n3(_cross(sx, f))                 # out of the digit plane
    if nf[1] > 0.0:
        nf = tuple(-v for v in nf)          # ...toward the viewer
    # Only a token forward lean: leaning it at the viewer foreshortens
    # the stub until it vanishes into the palm, so the thumb lives
    # mostly in the digit plane where it can hold a silhouette. It sits
    # on the OUTER flank (away from the torso), where it silhouettes
    # against open background in both front and 3/4 views - on the
    # inner flank it hid behind the palm and grazed the body.
    # Root sits mid-palm on the flank: still far proximal of the finger
    # knuckles (they are at 0.70 rp) so it is not a digit in the row,
    # but clear of the wrist-bridge blob - that blob is clamped to the
    # arm radius, so on a thick-armed style like the noodle it swallowed
    # a thumb rooted any higher.
    ux = tuple(-v for v in sx)              # outward, away from body
    tb = _add(_add(_add(c, ux, 0.64 * rp), f, 0.02 * rp), nf, 0.08 * rp)
    td = _n3(_add(_add(_add((0.0, 0.0, 0.0), ux, 0.90), f, 0.14),
                  nf, 0.30))
    # A DENSE chain of SOFT kernels, not 3 spaced steep ones. Steep
    # kernels decay so fast that the union waists between elements and
    # then closes into a ball at the tip - blind reviewers read exactly
    # that as "a bead stuck on a neck". Soft kernels (~1.0-1.2) at
    # ~0.18 rp spacing with monotonically falling radii fuse into one
    # smooth tapered cone instead, and the last element gets a small
    # f-offset for the gentle upturn toward the fingers.
    for d, r, h in ((0.00, 0.44, 1.20), (0.34, 0.39, 1.20),
                    (0.68, 0.34, 1.30), (1.04, 0.28, 1.30)):
        # hook factor raised with the length: the extra curl toward the
        # fingers is what keeps a longer thumb from reading as a fourth
        # digit spread sideways.
        p = _add(_add(tb, td, d * rp), f, 0.22 * d * rp)
        els.append((p, r * rp, h))
    return els, c, f, sx


def _blob(col, name, mat, elements, res, iso=1.0):
    import numpy as np
    E = math.e
    pad = max(r for _, r, _h in elements) * 1.35 + res * 2.0
    lo = [min(c[k] for c, _r, _h in elements) - pad for k in range(3)]
    hi = [max(c[k] for c, _r, _h in elements) + pad for k in range(3)]
    n = [int(math.ceil((hi[k] - lo[k]) / res)) + 1 for k in range(3)]
    axes = [lo[k] + res * np.arange(n[k]) for k in range(3)]
    F = np.zeros(tuple(n), dtype=np.float32)
    for c, r, hard in elements:
        sup = (2.5 if hard <= 1.0 else 1.75) * r
        b = []
        for k in range(3):
            i0 = max(0, int((c[k] - sup - lo[k]) / res))
            i1 = min(n[k] - 1, int((c[k] + sup - lo[k]) / res) + 1)
            b.append((i0, i1))
        if any(i1 <= i0 for i0, i1 in b):
            continue
        dx = (axes[0][b[0][0]:b[0][1] + 1] - c[0])[:, None, None]
        dy = (axes[1][b[1][0]:b[1][1] + 1] - c[1])[None, :, None]
        dz = (axes[2][b[2][0]:b[2][1] + 1] - c[2])[None, None, :]
        q = (dx * dx + dy * dy + dz * dz) / (r * r)
        if hard != 1.0:
            q = q ** hard
        F[b[0][0]:b[0][1] + 1, b[1][0]:b[1][1] + 1,
          b[2][0]:b[2][1] + 1] += (E * np.exp(-q)).astype(np.float32)
    S = F >= iso
    base = S[:-1, :-1, :-1]
    cand = np.zeros_like(base)
    for di in (0, 1):
        for dj in (0, 1):
            for dk in (0, 1):
                if di or dj or dk:
                    cand |= (S[di:n[0] - 1 + di, dj:n[1] - 1 + dj,
                               dk:n[2] - 1 + dk] != base)
    cubes = np.argwhere(cand)
    CO = ((0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),
          (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1))
    TETS = ((0, 1, 2, 6), (0, 2, 3, 6), (0, 3, 7, 6),
            (0, 7, 4, 6), (0, 4, 5, 6), (0, 5, 1, 6))
    verts, faces, vmap = [], [], {}

    def gradient(p):
        g = [0.0, 0.0, 0.0]
        for c, r, hard in elements:
            d2 = sum((p[k] - c[k]) ** 2 for k in range(3))
            if d2 > (2.7 * r) ** 2:
                continue
            q = d2 / (r * r)
            qh = q ** hard if hard != 1.0 else q
            dq = 1.0 if hard == 1.0 else hard * (q ** (hard - 1.0))
            w = E * math.exp(-qh) * (-dq) * (2.0 / (r * r))
            for k in range(3):
                g[k] += w * (p[k] - c[k])
        return g

    def edge_v(ga, gb, pa, pb, va, vb):
        key = (ga, gb) if ga < gb else (gb, ga)
        hit = vmap.get(key)
        if hit is not None:
            return hit
        t = 0.5 if abs(vb - va) < 1e-12 else (iso - va) / (vb - va)
        t = min(1.0, max(0.0, t))
        verts.append(tuple(pa[k] + (pb[k] - pa[k]) * t for k in range(3)))
        vmap[key] = len(verts) - 1
        return len(verts) - 1

    for ci, cj, ck in cubes:
        gp, pv, vv = [], [], []
        for dx_, dy_, dz_ in CO:
            i, j, k = ci + dx_, cj + dy_, ck + dz_
            gp.append((i * n[1] + j) * n[2] + k)
            pv.append((axes[0][i], axes[1][j], axes[2][k]))
            vv.append(float(F[i, j, k]))
        gc = tuple((pv[0][k] + pv[6][k]) * 0.5 for k in range(3))
        grad = gradient(gc)
        tris = []
        for tet in TETS:
            ins = [q for q in tet if vv[q] > iso]
            out = [q for q in tet if vv[q] <= iso]
            if not ins or not out:
                continue
            if len(ins) == 1 or len(out) == 1:
                a = ins[0] if len(ins) == 1 else out[0]
                rest = out if len(ins) == 1 else ins
                tris.append([edge_v(gp[a], gp[b], pv[a], pv[b], vv[a],
                                    vv[b]) for b in rest])
            else:
                a, b = ins
                c1, d1 = out
                q = [edge_v(gp[a], gp[c1], pv[a], pv[c1], vv[a], vv[c1]),
                     edge_v(gp[a], gp[d1], pv[a], pv[d1], vv[a], vv[d1]),
                     edge_v(gp[b], gp[d1], pv[b], pv[d1], vv[b], vv[d1]),
                     edge_v(gp[b], gp[c1], pv[b], pv[c1], vv[b], vv[c1])]
                tris.append([q[0], q[1], q[2]])
                tris.append([q[0], q[2], q[3]])
        for tri in tris:
            if len(set(tri)) < 3:
                continue
            p0, p1, p2 = (verts[i] for i in tri)
            e1 = [p1[k] - p0[k] for k in range(3)]
            e2 = [p2[k] - p0[k] for k in range(3)]
            nrm = _cross(e1, e2)
            if sum(nrm[k] * (-grad[k]) for k in range(3)) < 0:
                tri = [tri[0], tri[2], tri[1]]
            faces.append(tuple(tri))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    ob.data.materials.append(mat)
    col.objects.link(ob)
    sm = ob.modifiers.new("Plush", 'SMOOTH')   # clears marching terracing
    sm.factor = 0.55
    sm.iterations = 8
    return ob


def _blob_arm(col, mat, side, name, origin, ctrl, radii, rp, inward,
              m, hand_f=None, n_fingers=3, reach=1.0):
    els = _spine_elements(origin, ctrl, radii)
    wrist = _add(origin, ctrl[-1])
    prev = _add(origin, ctrl[-2])
    f = hand_f if hand_f else tuple(wrist[k] - prev[k] for k in range(3))
    hels, centre, hf, hsx = _hand_elements(wrist, f, rp, inward,
                                           n_fingers, reach,
                                           r_arm=radii[-1])
    LAST_HAND[(name, side)] = centre
    LAST_HAND_FRAME[(name, side)] = (centre, hf, hsx, rp)
    # res fine enough that a digit tip (r ~ 0.36 rp) spans ~11 cells,
    # so the extended fingers survive meshing + smoothing, and the
    # concave thumb web resolves without marching-tet shading ripples.
    _blob(col, f"{name}{side}", mat, els + hels,
          res=0.0066 * max(0.85, m))


# ---- ARM STYLES ----------------------------------------------------------
# signature: (col, mat, side, ax, ay, az, m, surf=None)

def arm_00(col, mat, side, ax, ay, az, m, surf=None):
    """Rounded Flipper — broad flattened-teardrop plush flipper.

    Scaled to 0.75 of the first sculpted size on user instruction
    (2026-08-17). K scales the path AND the radii together, so the
    flipper shrinks proportionally instead of just getting shorter;
    the root stays on the approved anchor and only the tip moves in."""
    s = side
    K = 0.75
    ctrl = [(0.0, 0.0, 0.06 * m * K),
            (s * 0.10 * m * K, -0.01 * m * K, -0.16 * m * K),
            (s * 0.17 * m * K, -0.02 * m * K, -0.36 * m * K),
            (s * 0.21 * m * K, -0.02 * m * K, -0.50 * m * K)]
    rx = [0.165 * m * K, 0.19 * m * K, 0.16 * m * K, 0.115 * m * K]
    ry = [0.095 * m * K, 0.105 * m * K, 0.09 * m * K, 0.068 * m * K]
    _tube(col, f"Arm{side}", mat, (s * ax, ay, az), ctrl, rx, ry)


def arm_01(col, mat, side, ax, ay, az, m, surf=None):
    """Tiny Hands — short soft forearm flowing into an OVERSIZED plush
    hand: rounded palm, 3 EXTENDED soft digits + inner thumb bump, all
    one continuous mesh. reach 1.10 = the longest digits of the set
    (this hand is the style's whole point). Palm rp 0.165 -> 0.190 m:
    blind review showed the digits were only countable when zoomed, and
    the fix is hand SIZE plus splayed tips, not longer fingers alone."""
    s = side
    origin = (s * ax, ay, az)
    ctrl = [(0.0, 0.0, 0.02 * m), (s * 0.075 * m, -0.03 * m, -0.09 * m),
            (s * 0.13 * m, -0.05 * m, -0.155 * m)]
    r = [0.10 * m, 0.092 * m, 0.088 * m]
    _blob_arm(col, mat, side, "Arm", origin, ctrl, r, 0.1425 * m,
              (-s, 0.0, 0.0), m, reach=1.10)


def arm_02(col, mat, side, ax, ay, az, m, surf=None):
    """Noodle Arms — longest: soft dangling J-curve flowing into a
    rounded hand with 3 EXTENDED soft digits (one mesh).

    Forearm slimmed ~8% from the first sculpted pass — a 13% cut read
    as spindly/fragile against the round body in blind review, so the
    slimness now comes mostly from the hand/arm contrast (hand rp
    0.132 -> 0.152 m) rather than from a thinner tube. The wrist keeps
    a fuller radius so the hand grows out of the noodle instead of
    ballooning off a stick."""
    s = side
    origin = (s * ax, ay, az)
    ctrl = [(0.0, 0.0, 0.06 * m), (s * 0.05 * m, -0.02 * m, -0.20 * m),
            (s * 0.02 * m, -0.035 * m, -0.42 * m),
            (s * 0.085 * m, -0.05 * m, -0.585 * m)]
    r = [0.086 * m, 0.078 * m, 0.075 * m, 0.075 * m]
    _blob_arm(col, mat, side, "Arm", origin, ctrl, r, 0.1275 * m,
              (-s, 0.0, 0.0), m, reach=1.05)


def _bud_nubs_removed(col, mat, side, ax, ay, az, m, surf=None):
    """Bud Nubs — REMOVED from the roster by user direction
    (2026-09-13; the shape read as phallic). Shipped to test devices
    as arm_03, so that id is BURNED: never reuse it for different art
    (a persisted arm_03 falls back to arm_00 at render time)."""
    s = side
    ctrl = [(0.0, 0.0, 0.055 * m),
            (s * 0.09 * m, -0.018 * m, -0.09 * m),
            (s * 0.14 * m, -0.03 * m, -0.21 * m)]
    r = [0.21 * m, 0.185 * m, 0.13 * m]
    _tube(col, f"Arm{side}", mat, (s * ax, ay, az), ctrl, r, r)


def _soft_mittens_removed(col, mat, side, ax, ay, az, m, surf=None):
    """Soft Mittens — REMOVED from the roster by user direction
    (2026-09-13). It shipped to test devices as arm_04, so that id is
    BURNED: never reuse it for different art (a persisted arm_04 falls
    back to arm_00 at render time). Held out, not deleted, per the
    same convention as the removed legs."""
    s = side
    ctrl = [(0.0, 0.0, 0.05 * m),
            (s * 0.10 * m, -0.02 * m, -0.14 * m),
            (s * 0.145 * m, -0.03 * m, -0.29 * m),
            (s * 0.15 * m, -0.035 * m, -0.41 * m)]
    r = [0.15 * m, 0.125 * m, 0.115 * m, 0.19 * m]
    _tube(col, f"Arm{side}", mat, (s * ax, ay, az), ctrl, r, r)
    tip = (s * (ax + 0.15 * m), ay - 0.035 * m, az - 0.41 * m)
    _thumb(col, f"Thumb{side}", mat, tip, m, -s, 0.13, 0.05, r=0.11)


def _wing_flaps_removed(col, mat, side, ax, ay, az, m, surf=None):
    """Wing Flaps — REMOVED from the roster by user direction
    (2026-09-13). Shipped to test devices as arm_05, so that id is
    BURNED: never reuse it for different art (a persisted arm_05
    falls back to arm_00 at render time). Original notes: broad flat
    plush flap held slightly OUT from the flank, penguin-proud. The
    silhouette signature is the open wedge of background between the
    flap and the body — nothing else in the set holds away from the
    flank. Broad at the root, blunt at the tip, flat in section (the
    second radius list is the half-thickness, exactly the flipper's
    flattening trick but angled outward instead of hanging)."""
    s = side
    ctrl = [(0.0, 0.0, 0.06 * m),
            (s * 0.17 * m, -0.015 * m, -0.11 * m),
            (s * 0.30 * m, -0.025 * m, -0.29 * m),
            (s * 0.345 * m, -0.03 * m, -0.41 * m)]
    rx = [0.20 * m, 0.195 * m, 0.15 * m, 0.09 * m]
    ry = [0.10 * m, 0.09 * m, 0.068 * m, 0.05 * m]
    _tube(col, f"Arm{side}", mat, (s * ax, ay, az), ctrl, rx, ry)


def _wave_held_out(col, mat, side, ax, ay, az, m, surf=None):
    """HELD OUT OF THE ACTIVE SET (never reviewed by the user; kept as
    history only, and its hand is still the old smooth end).

    Wave — soft open lifted arm: sweeps out-and-down then the tip
    rises to shoulder height in a gentle welcoming wave; integrated
    mitten bulb + thumb. Mass stays at flank height (never ears)."""
    s = side
    ctrl = [(0.0, 0.0, -0.02 * m), (s * 0.15 * m, -0.02 * m, -0.11 * m),
            (s * 0.25 * m, -0.03 * m, -0.02 * m),
            (s * 0.315 * m, -0.045 * m, 0.115 * m)]
    r = [0.125 * m, 0.112 * m, 0.104 * m, 0.138 * m]
    _tube(col, f"Arm{side}", mat, (s * ax, ay, az), ctrl, r, r)
    tip = (s * (ax + 0.315 * m), ay - 0.045 * m, az + 0.115 * m)
    _thumb(col, f"Thumb{side}", mat, tip, m, -s, 0.07, 0.045)


def _belly_paws_removed(col, mat, side, ax, ay, az, m, surf=None):
    """REMOVED FROM THE ACTIVE SET by user direction (2026-08-17): do
    not refine, do not include in arm comparison sheets, do not use to
    fill one of the two remaining arm slots. Kept as history only.

    Belly Paws — compact forward arms ending in broad plush paws on
    the belly, digit edge angled DOWN-AND-IN so the 3 finger bumps are
    visible from the front/3-4 (one continuous mesh)."""
    s = side

    def sy(x, z, lift):
        return (surf(x, z) + lift * m) if surf else ay - 0.26 * m

    origin = (s * ax, ay, az)
    m1 = (s * (ax - 0.07 * m), az - 0.12 * m)
    m2 = (s * (ax - 0.33 * m), az - 0.20 * m)
    ctrl = [(0.0, 0.0, 0.02 * m),
            (m1[0] - origin[0], min(0.0, sy(m1[0], m1[1], 0.05) - ay),
             m1[1] - az),
            (m2[0] - origin[0], sy(m2[0], m2[1], 0.05) - ay, m2[1] - az)]
    r = [0.12 * m, 0.114 * m, 0.108 * m]
    _blob_arm(col, mat, side, "Arm", origin, ctrl, r, 0.16 * m,
              (-s, 0.0, 0.0), m,
              hand_f=(-s * 0.72, -0.34, -1.0))


# ---- LEG STYLES ----------------------------------------------------------
# signature: (col, mat, side, fx, fy, m, fcx=0.0)

def leg_00(col, mat, side, fx, fy, m, fcx=0.0):
    """Short Standing Legs — THICK plush toddler leg columns + broad
    rounded feet. Rebuilt 2026-08-17: the old 0.125 m column under this
    body read as a bird leg. The column barely tapers now (0.185 ->
    0.175) and is nearly as wide as the foot, so leg and foot merge into
    one chunky soft form instead of a stem meeting a paddle."""
    lx = fcx + side * fx
    # The column STOPS INSIDE the foot mass (bottom ctrl at 0.20, well
    # above the sole) and the foot is wider than the column in every
    # direction. Otherwise the tube's rounded end cap pokes out below
    # the foot as a little pointed nub and a waist appears where the two
    # meet - blind reviewers read exactly that as a thin bird ankle.
    ctrl = [(0.0, 0.0, 0.35 * m), (0.0, 0.0, 0.26 * m),
            (side * 0.01 * m, -0.01 * m, 0.20 * m)]
    r = [0.185 * m, 0.180 * m, 0.172 * m]
    _tube(col, f"Leg{side}", mat, (lx, fy, 0.0), ctrl, r, r)
    _sphere(col, f"Foot{side}", (lx + side * 0.025 * m, fy - 0.05 * m,
                                 0.72 * 0.190 * m),
            (0.250 * m, 0.305 * m, 0.190 * m), mat, flatten=0.26)


def leg_01(col, mat, side, fx, fy, m, fcx=0.0):
    """Bounce Feet — OVERSIZED bulbous plush ball feet, set forward, no
    visible leg; the body rides low on them (LEG_BODY_LIFT 0.0). Volume
    is deliberately far beyond Short Standing's foot so the two never
    read as variants of one another, and the flatten is light so they
    stay balls rather than pads."""
    _sphere(col, f"Foot{side}", (fcx + side * fx * 0.98, fy - 0.14 * m,
                                 0.70 * 0.285 * m),
            (0.305 * m, 0.335 * m, 0.285 * m), mat, flatten=0.18)


def leg_02(col, mat, side, fx, fy, m, fcx=0.0, stance=1.62):
    """Chibi Stance — the SQUAT silhouette: stance pushed far out
    (1.62x the anchor), legs reduced to short THICK out-angled stubs
    (thicker than Short Standing's, so it never reads as a shortened
    copy of it), feet clearly outside the lower body silhouette, body
    riding low (LEG_BODY_LIFT 0.0). Reads as a wide planted toddler."""
    # `stance` is rig metadata, not a redesign: 1.62 is right on Round,
    # but on bodies whose approved foot anchor is already wide (wide,
    # squircle, star, beanbag) it throws the feet past the silhouette
    # edge and the character reads as crouching on all fours. Callers
    # clamp it so the stance stays inside the body.
    s = side
    bx = fcx + s * fx * stance
    # tall enough to actually reach the body at this wide stance: the
    # underside of a round body rises as |x| grows, so a wide stance
    # with short legs leaves the feet floating unless the stub reaches up
    # stronger A-frame than Short Standing (top tucked in, foot kicked
    # out) so this is not just that style spread wider, and - as with
    # leg_00 - the column ends INSIDE the foot so no cap nub shows
    ctrl = [(-s * 0.06 * m, 0.0, 0.375 * m), (s * 0.06 * m, 0.0, 0.26 * m),
            (s * 0.155 * m, -0.02 * m, 0.20 * m)]
    r = [0.205 * m, 0.200 * m, 0.188 * m]
    _tube(col, f"Leg{side}", mat, (bx, fy, 0.0), ctrl, r, r)
    # foot nearly as deep as it is wide and yaw cut from 24 to 11 deg:
    # an outward-pointing tapered foot was the strongest bird cue here
    _sphere(col, f"Foot{side}", (bx + s * 0.155 * m, fy - 0.05 * m,
                                 0.70 * 0.190 * m),
            (0.285 * m, 0.305 * m, 0.190 * m), mat,
            rot=(0, 0, s * math.radians(11)), flatten=0.26)


def leg_03(col, mat, side, fx, fy, m, fcx=0.0):
    """Splayed Feet — long FLAT plush pods running diagonally outward:
    swept (not an ellipsoid) so the pod TAPERS from a full inner heel
    to a slimmer outer toe, with a low vertical profile. Sweeping in the
    x-y plane means _tube's first radius list is the pod's half-HEIGHT
    and the second its half-WIDTH, which is what makes it flat. The
    inner-rear-to-outer-front diagonal is the whole silhouette idea:
    nothing else in the set points away from the body."""
    s = side
    # the outer end also rises slightly: in a straight-on front view a
    # purely horizontal splay foreshortens to a flat pad, and this tilt
    # is what puts the diagonal into the FRONT silhouette too
    # Rebuilt thick 2026-08-17: the flat tapered version read as a duck
    # foot / flipper. Vertical half-height is up ~45%, the outer end is
    # BLUNT (0.135 vs 0.155, no point) and the pod is shorter, so it is
    # a fat plush pod on a diagonal rather than a paddle.
    ctrl = [(-s * 0.13 * m, 0.10 * m, 0.185 * m),
            (s * 0.08 * m, -0.02 * m, 0.190 * m),
            (s * 0.28 * m, -0.20 * m, 0.200 * m)]
    r_up = [0.185 * m, 0.190 * m, 0.170 * m]       # half-height (thick)
    r_wide = [0.195 * m, 0.200 * m, 0.180 * m]     # half-width (blunt)
    _tube(col, f"Foot{side}", mat, (fcx + side * fx * 1.02, fy, 0.0),
          ctrl, r_up, r_wide)


def _tall_walkers_removed(col, mat, side, fx, fy, m, fcx=0.0):
    """REMOVED FROM THE ACTIVE SET 2026-09-13 (never user-approved).
    Tall Walkers — the LONG legs (2026-09-12 variety pass): plush
    columns clearly taller than Short Standing's, so the body rides
    high and the creature reads leggy-but-soft. This is also the rig's
    splits/extension workhorse: the column runs deep into the raised
    body (top 0.62 vs lift 0.34), so rotating it outward from a hip
    joint keeps the root buried at any dance angle. The column stays
    thick (0.150 — the bird-leg floor learned on leg_00 is respected
    by pairing the slimmer column with a full-size foot and almost no
    taper), and as always it ends INSIDE the foot mass."""
    lx = fcx + side * fx
    ctrl = [(0.0, 0.0, 0.70 * m), (0.0, 0.0, 0.44 * m),
            (side * 0.012 * m, -0.01 * m, 0.20 * m)]
    r = [0.165 * m, 0.158 * m, 0.150 * m]
    _tube(col, f"Leg{side}", mat, (lx, fy, 0.0), ctrl, r, r)
    _sphere(col, f"Foot{side}", (lx + side * 0.025 * m, fy - 0.05 * m,
                                 0.72 * 0.185 * m),
            (0.235 * m, 0.29 * m, 0.185 * m), mat, flatten=0.26)


def _haunch_hops_removed(col, mat, side, fx, fy, m, fcx=0.0):
    """REMOVED FROM THE ACTIVE SET 2026-09-13 (never user-approved).
    Haunch Hops — frog/bunny crouch (2026-09-12 variety pass): one
    big plush thigh bulge on each flank with a small foot pod peeking
    forward underneath. Nothing else in the set puts its mass on the
    SIDE of the silhouette — Chibi Stance is wide at the FEET, this is
    wide at the HIPS. The haunch is deliberately oversized (0.235 m)
    so it reads as a shape choice, not a swollen leg_02."""
    s = side
    bx = fcx + s * fx * 1.75
    _sphere(col, f"Leg{side}", (bx, fy + 0.02 * m, 0.17 * m),
            (0.30 * m, 0.25 * m, 0.225 * m), mat, flatten=0.12)
    _sphere(col, f"Foot{side}", (bx + s * 0.04 * m, fy - 0.22 * m,
                                 0.72 * 0.14 * m),
            (0.195 * m, 0.30 * m, 0.14 * m), mat,
            rot=(0, 0, s * math.radians(8)), flatten=0.22)


def _pigeon_steps_removed(col, mat, side, fx, fy, m, fcx=0.0):
    """REMOVED FROM THE ACTIVE SET 2026-09-13 (never user-approved).
    Pigeon Steps — the knock-kneed toddler (2026-09-12 variety
    pass): columns lean IN toward each other and the feet yaw INWARD,
    the exact mirror of Chibi Stance's out-angled sprawl. The inward
    toe angle is the whole silhouette idea; the column keeps leg_00's
    full thickness so shy never reads as spindly. Column ends inside
    the foot, as always."""
    s = side
    bx = fcx + s * fx * 1.02
    ctrl = [(s * 0.08 * m, 0.0, 0.37 * m), (-s * 0.02 * m, 0.0, 0.26 * m),
            (-s * 0.075 * m, -0.015 * m, 0.20 * m)]
    r = [0.175 * m, 0.170 * m, 0.162 * m]
    _tube(col, f"Leg{side}", mat, (bx, fy, 0.0), ctrl, r, r)
    _sphere(col, f"Foot{side}", (bx - s * 0.135 * m, fy - 0.05 * m,
                                 0.70 * 0.185 * m),
            (0.24 * m, 0.30 * m, 0.185 * m), mat,
            rot=(0, 0, -s * math.radians(28)), flatten=0.26)


def leg_04(col, mat, side, fx, fy, m, fcx=0.0):
    """Paw Steps (id leg_04 after the 2026-09-13 renumbering; built
    as leg_07 during the experiment) — the approved METABALL leg (see
    metaball_leg_experiment.blend): a longer, slightly slim column
    flowing into ONE fused paw — domed instep, broad forefoot ending in
    three shallow toe scallops, flat sole. Authored as a metaball field
    and realized to a mesh right here at export time, so column, instep
    and toes fuse with no seams (the technique's whole point). Values
    were approved on Round at m=0.85; k rescales per body."""
    import bpy
    k = m / 0.85
    lx = fcx + side * fx
    inward = -side          # the experiment's small forward-inward drifts
    name = f"Leg{side}"
    mb = bpy.data.metaballs.new(name)
    mb.resolution = 0.015
    mb.render_resolution = 0.015
    mb_obj = bpy.data.objects.new(name + "_meta", mb)
    col.objects.link(mb_obj)
    mb_obj.location = (lx, fy, 0.0)

    def el(dx, dy, z, r, st):
        e = mb.elements.new()
        e.type = "BALL"
        e.co = (dx * k, dy * k, z * k)
        e.radius = r * k
        e.stiffness = st
    # longer, slightly slim column (ground-relative z)
    el(0.0, 0.0, 0.45, 0.330, 2.0)
    el(0.0, 0.0, 0.33, 0.290, 2.0)
    el(inward * 0.004, -0.006, 0.24, 0.265, 2.0)
    el(inward * 0.006, -0.010, 0.16, 0.245, 2.0)
    el(inward * 0.006, -0.014, 0.095, 0.220, 2.0)
    # the foot: one fused slab with a domed instep
    for dx, dy, dz, r in ((0.000, -0.034, 0.125, 0.271),
                          (0.000, -0.100, 0.190, 0.210),
                          (-0.113, -0.113, 0.115, 0.226),
                          (0.113, -0.113, 0.115, 0.226),
                          (0.000, -0.136, 0.125, 0.260),
                          (-0.130, -0.209, 0.110, 0.209),
                          (0.130, -0.209, 0.110, 0.209),
                          (0.000, -0.226, 0.115, 0.237)):
        el(dx + inward * 0.008, dy, dz, r, 1.6)
    # toe scallops of the SAME paw — centres LOW so their bellies dip
    # below the ground and the sole clamp flattens them into the floor:
    # the toes are the ground contact, no sole edge shows under them
    for dx, dy, r in ((-0.200, -0.325, 0.200), (0.0, -0.365, 0.215),
                      (0.200, -0.325, 0.200)):
        el(dx + inward * 0.008, dy, 0.075, r, 2.0)
    # realize the field -> plain mesh; the metaball never ships
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(mb_obj.evaluated_get(deps))
    ob = bpy.data.objects.new(name, me)
    ob.location = mb_obj.location
    col.objects.link(ob)
    bpy.data.objects.remove(mb_obj, do_unlink=True)
    # flat sole (clamp below-ground bellies), then a gentle live smooth —
    # the sole interior stays planar because its neighbours are coplanar
    for v in me.vertices:
        if v.co.z < 0.0:
            v.co.z = 0.0
    sm = ob.modifiers.new("Soften", "SMOOTH")
    sm.factor = 0.4
    sm.iterations = 4
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.update()
    ob.data.materials.append(mat)


def leg_05(col, mat, side, fx, fy, m, fcx=0.0):
    """Bulb Boots (id leg_05; approved 2026-09-13 from the metaball
    leg-08 experiment, metaball_leg08_experiment.blend): thick, barely
    tapered columns with a long visible stretch of leg, flowing
    seamlessly into ONE smooth boot-like bulb per foot that swells
    forward — no toes, softly flattened ground contact. Same realize-
    to-mesh construction as Paw Steps."""
    import bpy
    k = m / 0.85
    lx = fcx + side * fx
    inward = -side
    name = f"Leg{side}"
    mb = bpy.data.metaballs.new(name)
    mb.resolution = 0.015
    mb.render_resolution = 0.015
    mb_obj = bpy.data.objects.new(name + "_meta", mb)
    col.objects.link(mb_obj)
    mb_obj.location = (lx, fy, 0.0)

    def el(dx, dy, z, r, st):
        e = mb.elements.new()
        e.type = "BALL"
        e.co = (dx * k, dy * k, z * k)
        e.radius = r * k
        e.stiffness = st
    # thick, barely-tapered column (ground-relative z)
    el(0.0, 0.0, 0.50, 0.345, 2.0)
    el(0.0, 0.0, 0.37, 0.305, 2.0)
    el(inward * 0.004, -0.004, 0.26, 0.285, 2.0)
    el(inward * 0.005, -0.006, 0.17, 0.272, 2.0)
    el(inward * 0.006, -0.008, 0.115, 0.262, 2.0)
    # the boot bulb: heel under the column, big main bulb, round front
    el(inward * 0.006, 0.02, 0.12, 0.275, 1.6)
    el(inward * 0.010, -0.10, 0.135, 0.325, 1.55)
    el(inward * 0.012, -0.225, 0.115, 0.27, 1.65)
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(mb_obj.evaluated_get(deps))
    ob = bpy.data.objects.new(name, me)
    ob.location = mb_obj.location
    col.objects.link(ob)
    bpy.data.objects.remove(mb_obj, do_unlink=True)
    for v in me.vertices:
        if v.co.z < 0.0:
            v.co.z = 0.0
    sm = ob.modifiers.new("Soften", "SMOOTH")
    sm.factor = 0.4
    sm.iterations = 4
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.update()
    ob.data.materials.append(mat)


def _tiny_boots_removed(col, mat, side, fx, fy, m, fcx=0.0):
    """REMOVED FROM THE ACTIVE SET by user direction (2026-08-17): too
    redundant with leg_00 Short Standing. Do not refine, do not include
    in sheets, do not use to fill the remaining leg slot. History only.

    Tiny Boots — CHUNKY plush boots. Rebuilt 2026-08-17: the old
    0.105 m ankle over a small boot was the most bird-like leg in the
    set. Now a thick short ankle (0.175, broad where it meets the body),
    a tall deep boot body and a big forward toe mass, so the boot has
    obvious volume beyond Short Standing's plain foot. Reads as the body
    forming into two rounded plush boots; no shoe detailing."""
    bx = fcx + side * fx
    # The ankle stays chunky but is clearly slimmer than the boot body,
    # so the silhouette has a boot CUFF step. That step is what tells
    # this style apart from Short Standing, whose column deliberately
    # flows straight into its foot with no flare.
    ctrl = [(0.0, 0.0, 0.345 * m), (0.0, 0.0, 0.255 * m),
            (0.0, -0.015 * m, 0.190 * m)]
    r = [0.160 * m, 0.155 * m, 0.150 * m]
    _tube(col, f"Ankle{side}", mat, (bx, fy, 0.0), ctrl, r, r)
    _sphere(col, f"Boot{side}", (bx, fy - 0.055 * m, 0.72 * 0.200 * m),
            (0.250 * m, 0.300 * m, 0.200 * m), mat, flatten=0.26)
    _sphere(col, f"Toe{side}", (bx, fy - 0.225 * m, 0.70 * 0.165 * m),
            (0.215 * m, 0.225 * m, 0.165 * m), mat, flatten=0.24)



# ACTIVE arm set = the three the user currently accepts. Slots arm_03
# and arm_04 are FREE for the two new concepts still needed to reach
# the launch five — they must NOT be filled by the two styles below.
# ---------------------------------------------------------------------------
# Tail
# ---------------------------------------------------------------------------

def tail(col, mat, side, rz, height, flank_of, m=1.0,
         root_r=0.240, tip_r=0.108, nub_r=0.118, clear=0.42, rise=0.10):
    """A short, raised, rounded tail on the lower back — a body feature.

    Shape language follows the reference: small, thick at the root, curving
    OUT and UP over a short run, ending blunt. The earlier version ran long
    and low toward the feet and read as a dangling addon; this one rises
    from the moment it leaves the body.

    Each control point is placed against the flank AT ITS OWN HEIGHT, so
    the tail hugs whatever silhouette it grows from instead of clipping
    into a wide body or floating off a narrow one.

    The root is pushed INTO the body and is the thickest section, which is
    what gives the same soft socket transition the arms and legs have —
    a tail that starts thin looks glued on.

    Returns the nub centre in world units: the anchor a charm hangs from.
    """
    H = height
    # Rise the whole way: out and up, never down.
    zs = [rz, rz + 0.20 * rise * H, rz + 0.62 * rise * H, rz + rise * H]
    outs = [-0.16, 0.38, 0.70, 0.80]
    ys = [0.30, 0.20, 0.08, -0.02]
    ctrl = [(side * (flank_of(z) + clear * o), y, z)
            for z, o, y in zip(zs, outs, ys)]

    origin = ctrl[0]
    rel = [tuple(cp[k] - origin[k] for k in range(3)) for cp in ctrl]
    # Fat root, fast taper: reads as part of the body rather than attached.
    radii = [root_r * m, root_r * 0.80 * m, tip_r * 1.24 * m, tip_r * m]
    _tube(col, f"Tail{'L' if side < 0 else 'R'}", mat, origin, rel, radii)

    d = [rel[-1][k] - rel[-2][k] for k in range(3)]
    n = math.sqrt(sum(v * v for v in d)) or 1.0
    nub = tuple(ctrl[-1][k] + d[k] / n * nub_r * 0.55 * m for k in range(3))
    _sphere(col, f"TailNub{'L' if side < 0 else 'R'}", nub,
            (nub_r * m, nub_r * m, nub_r * m), mat)
    return nub


# arm_03 Bud Nubs, arm_04 Soft Mittens and arm_05 Wing Flaps removed
# 2026-09-13 (user direction); all three ids burned. The roster is
# back to the original launch trio.
ARMS = {"arm_00": arm_00, "arm_01": arm_01, "arm_02": arm_02}
ARMS_HELD_OUT = {"wave": _wave_held_out,
                 "belly_paws": _belly_paws_removed,
                 "bud_nubs": _bud_nubs_removed,
                 "soft_mittens": _soft_mittens_removed,
                 "wing_flaps": _wing_flaps_removed}
# ACTIVE leg set = 7 styles. The old leg_04 Tiny Boots was REMOVED by
# user direction (too redundant with leg_00 Short Standing); the
# 2026-09-12 variety pass filled leg_04..06 with non-boot silhouettes.
LEGS = {"leg_00": leg_00, "leg_01": leg_01, "leg_02": leg_02,
        "leg_03": leg_03, "leg_04": leg_04, "leg_05": leg_05}
LEGS_HELD_OUT = {"tiny_boots": _tiny_boots_removed,
                 "tall_walkers": _tall_walkers_removed,
                 "haunch_hops": _haunch_hops_removed,
                 "pigeon_steps": _pigeon_steps_removed}

ARM_INFO = {
    "arm_00": ("Rounded Flipper", "broad flattened-teardrop flipper, "
               "thick root, rounded end", "waddly, seal-plush"),
    "arm_01": ("Tiny Hands", "short chunky forearm swelling into an "
               "oversized hand: 3 extended digits + a shorter "
               "projecting thumb", "dainty, expressive"),
    "arm_02": ("Noodle Arms", "longest: slim-but-plush dangling "
               "J-curve, same 3-digit-plus-thumb hand",
               "floppy, easygoing"),
}
LEG_INFO = {
    "leg_00": ("Short Standing Legs", "plush toddler leg columns + "
               "feet; body elevated", "standing proud"),
    "leg_01": ("Bounce Feet", "large bulbous ball feet",
               "springy, energetic"),
    "leg_02": ("Chibi Stance", "short out-angled legs, wide squat "
               "stance", "planted, wobbly-cute"),
    "leg_03": ("Splayed Feet", "long outward-angled plush pods",
               "duck-waddle"),
    "leg_04": ("Paw Steps", "longer slim legs into one fused paw: "
               "domed instep, flat sole, three toe scallops",
               "soft-pawed"),
    "leg_05": ("Bulb Boots", "thick barely-tapered legs into one "
               "smooth forward-swelling boot bulb, no toes",
               "marshmallow boots"),
}
