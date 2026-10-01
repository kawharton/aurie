"""Aurie hair library v5 — THE METABALL ERA (2026-09-13).

v2-v4 sculpted hairstyles never cleared review. Hair then went through
the same Blender-metaball process that produced the approved legs
(leg_04/leg_05): candidates modeled as metaball fields on the Round
body, iterated one style at a time against the user's reference
images, integrated only on explicit approval.

Launch decision (2026-09-13): the launch hair pool is the baked tuft
plus hair_00 Cloud Puff. Twin Poms (candidate C4 — the same puff at
80.5% scale riding each upper side of the head) is APPROVED BUT HELD
for a later release: its recipe lives in experiment_metaball_hair.py
and Source/metaball_hair_experiment.blend (it still needs per-body
placement work — the experiment placed it on Round's head sphere,
which other bodies don't have). 2026-09-14: the user assigned id
hair_01 to the Soft Mohawk (reference: Design/Hair/soft_mohawk.png);
Twin Poms takes the next free id if/when it is integrated. The retired sculpted styles that briefly used ids
hair_00..hair_04 never shipped in any build (their imagesets were
removed and the app fell back to the tuft), so hair_00 is safe to
carry the Cloud Puff; hair_02..hair_04 stay reserved-unused in
AurieLimbCatalog.

hair_00 Cloud Puff — one round lobed cloud puff pushed into the
scalp. The element recipe is EXACTLY the approved experiment build: a
fat core wrapped by left/right/front/back lobes plus two offset top
bumps (a lobed dome, never a cone), attached by PLAIN SINK — the puff
surface simply disappears into the crown. A meld collar and a tangent
flare were both explicitly rejected ("an extra layer below the hair").

Builder signature: (col, mat, crown, m). Front is -y.
"""


def _crown(crown):
    return (crown["head_x"], crown["top"], max(crown["halfw"], 0.18),
            crown["z_at"])


# The approved Cloud Puff, crown-relative on Round at m=0.85
# (experiment_metaball_hair.py c1_base): (co, radius, stiffness).
C1_BASE = [
    ((0.0, 0.02, -0.10), 0.44, 1.8),         # weld root
    ((0.0, 0.0, 0.18), 0.54, 2.1),           # fat core
    ((-0.14, -0.02, 0.375), 0.345, 2.35),    # top-left bump
    ((0.165, 0.03, 0.385), 0.36, 2.35),      # top-right bump
    ((-0.315, -0.03, 0.20), 0.415, 2.3),     # left lobe
    ((0.33, 0.02, 0.215), 0.43, 2.3),        # right lobe (asym)
    ((-0.02, -0.27, 0.16), 0.39, 2.3),       # front lobe (depth)
    ((0.03, 0.28, 0.15), 0.40, 2.3),         # back lobe (depth)
]
C1_SINK = 0.10          # approved burial below the local crown
# RC3 (2026-09-13): these are the APPROVED SCULPT'S own crown
# measurements — normalization datums describing the crown the recipe
# was authored on, not assumptions about the wearing body. Placement
# and fit read the WEARER'S measured crown (halfw, z_at) at build time;
# these two numbers only say what "fits like the original" means.
REF_CROWN_HALFW = 0.718  # crown half-width of the authoring body
REF_CROWN_DROP = 0.065   # its z_at fall-off at +/-0.42 (band-max
                         # sampling, same measure_body method)


def hair_00(col, mat, crown, m):
    """Cloud Puff — the approved metaball puff, realized to a mesh at
    export time (same technique as leg_04/leg_05). Scales with the
    body's limb scale and crown width; bodies whose crown falls away
    faster than Round's sink the puff a little deeper so its underside
    still lands inside the surface on both flanks."""
    import bpy
    hx, top, halfw, z_at = _crown(crown)
    # base size follows the body's limb scale; the width fit compares
    # the crown to what the puff needs AT that scale (so it is 1.0 by
    # definition on Round, keeping the approved sculpt exact there)
    k0 = m / 0.85
    fit = max(0.75, min(1.1, halfw / (REF_CROWN_HALFW * k0)))
    k = k0 * fit
    base_z = z_at(hx)
    side_drop = base_z - min(z_at(hx - 0.42 * k), z_at(hx + 0.42 * k))
    sink = C1_SINK * k + 0.35 * max(0.0, side_drop - REF_CROWN_DROP * k)
    print(f"hair_00: halfw={halfw:.3f} m={m:.2f} k={k:.3f} "
          f"sink={sink:.3f} side_drop={side_drop:.3f}")
    name = "Hair00"
    mb = bpy.data.metaballs.new(name)
    mb.resolution = 0.015
    mb.render_resolution = 0.015
    mb_obj = bpy.data.objects.new(name + "_meta", mb)
    col.objects.link(mb_obj)
    mb_obj.location = (hx, 0.0, base_z)
    for (x, y, z), r, st in C1_BASE:
        e = mb.elements.new()
        e.type = "BALL"
        e.co = (x * k, y * k, z * k - sink)
        e.radius = r * k
        e.stiffness = st
    # realize the field -> plain mesh; the metaball never ships
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(mb_obj.evaluated_get(deps))
    ob = bpy.data.objects.new(name, me)
    ob.location = mb_obj.location
    col.objects.link(ob)
    bpy.data.objects.remove(mb_obj, do_unlink=True)
    # same gentle soften the approved experiment renders used
    sm = ob.modifiers.new("Soften", "SMOOTH")
    sm.factor = 0.35
    sm.iterations = 3
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.update()
    ob.data.materials.append(mat)


# ---- hair_01 Soft Mohawk — APPROVED 2026-09-14 ----------------------
# The mesh_iter15 candidate cleared visual review; the recipe below
# is FROZEN. Do not retune the constants without a new approval round
# (evidence trail: aurie-review-evidence/hair01_softmohawk).
#
# Source of truth: Design/Hair/soft_mohawk.png; measured targets in
# aurie-review-evidence/hair01_softmohawk/reference_manifest.json
# (the approved design evolved past the sheet by user direction:
# six spikes, splayed tip leans).
# Six soft petal spikes on the SAGITTAL CENTERLINE (x = head_x,
# zero lateral offset — a true mohawk, never a crown). The row starts
# just forward of the crown apex and follows the skull curve down the
# back; the front petal towers, the rest shrink rearward.
#
# v2 (2026-09-14, after visual review of the metaball attempt): the
# five spikes are SEPARATE deformed-primitive meshes, not one fused
# metaball field — a fused field kept the valleys between petals
# shallow no matter the stiffness, and the crest read as one ridge.
# The measurement/placement architecture the review APPROVED is
# unchanged: the wearer's measured crown, the bias-corrected sagittal
# skull-circle fit, hair_00's k-normalization, centerline placement,
# and the front-to-back arc. Each petal is a UV sphere run through a
# deterministic taper (widest near lower-middle, soft rounded point),
# a base flatten where it enters the head, and a backward lean that
# grows along the row — five objects in the HAIR collection; the
# runtime asset is a rendered layer, so the hairstyle needs no single
# continuous mesh.
MOHAWK_RATIOS = (1.00, 1.22, 1.25, 1.15, 1.05, 1.00)  # petal heights
                         # spike 2 TALLER than spike 1 (user
                         # direction 2026-09-14, raised +15% from
                         # 1.06) — its tip is the crest's peak
                         # (+0.61 vs spike 1's +0.55); spike 3 only
                         # a little shorter than spike 2 (user
                         # direction, same day) so the front three
                         # form a full clustered crest before the
                         # rear nubs
MOHAWK_THETAS = (-6.0, 10.0, 26.0, 43.0, 60.0, 76.0)  # arc positions
                         # spike 6 (2026-09-14): continues the row
                         # down the back — at 76 deg + lean its axis
                         # is horizontal, a big petal pointing
                         # straight back low on the skull
                         # (mesh_iter1 tightened 18->16-17 deg: at 18
                         # the tapered rear petals didn't reach each
                         # other and the row read as separate beads)
MOHAWK_H1 = 0.72         # front petal total height (front-read
                         # pass: 0.68 read as a squat blob; taller +
                         # narrower makes the crest slender)
MOHAWK_W1_HALF = 0.315   # front petal half-width (front-read pass:
                         # 0.348 filled the whole front silhouette
                         # and hid every rear petal behind spike 1)
MOHAWK_WIDTHS = (1.00, 1.18, 1.18, 1.12, 1.05, 1.00)
                         # per-spike half-width ladder (x W1_HALF).
                         # ASCENDING over spikes 1-3 (user direction
                         # 2026-09-14): spike 2 a little wider than
                         # spike 1, spike 3 a little wider than
                         # spike 2, so each front layer peeks
                         # symmetrically around the one before it —
                         # a perfectly centered row can only read as
                         # layered from the front if the widths GROW
                         # rearward for the visible layers. Spikes
                         # 4-5 keep their small rear-nub widths.
MOHAWK_STAGGER = (0.0, -0.025, 0.025, -0.015, 0.015, -0.015)
                         # lateral offsets, fractions of the
                         # wearer's MEASURED body width (the +0.08
                         # spike-3 shift was reverted — the strip
                         # bulged right from the top; its point now
                         # comes from SIDE_LEAN instead)
MOHAWK_SIDE_LEAN = (6.0, -8.0, 18.0, 0.0, 0.0, 0.0)
                         # per-spike lateral tip lean, degrees,
                         # + = the Aurie's right: the spike's BASE
                         # stays on the strip while its point flicks
                         # sideways clear of spike 1's occlusion —
                         # spike 3's answer to spike 2's left point
                         # (user direction 2026-09-14)
MOHAWK_DEPTH = 0.90      # front-back half-depth as a fraction of
                         # half-width — thick, but width-dominant
MOHAWK_LEAN = 14.0       # extra backward lean off the skull normal
MOHAWK_BURY = 0.10       # per-spike root burial, fraction of height


def _mohawk_arc_r(top, z_at, hx, k, height):
    """Sagittal skull-circle radius from the measured crown: sample
    the lateral fall-off at +/-0.45k and circle-fit through it (the
    lateral profile stands in for the front-to-back one; identical on
    Round's spherical top).

    z_at is a BAND-MAX sampler (max z within +/-0.045*height of the
    query), so on a falling profile its reading at d is really the
    surface at d minus the band half-width; fit at that effective
    offset or the circle comes out ~45% too big and the rear spikes
    float behind the head (iter1, 2026-09-14)."""
    d = 0.45 * k
    x_eff = max(d - 0.045 * height, 0.12)
    drop = top - 0.5 * (z_at(hx - d) + z_at(hx + d))
    drop = max(drop, 0.02)
    return max(0.40, min(3.0, (x_eff * x_eff + drop * drop)
                         / (2.0 * drop)))


# -- v1 metaball attempt, SUPERSEDED 2026-09-14 -----------------------
# Kept verbatim as evidence (renders: aurie-review-evidence/
# hair01_softmohawk/iter1-4; scene: Source/
# softmohawk_hair01_experiment.blend). Review verdict: the fused
# field reads as one continuous ridge — stiffness is not a valley-
# sharpener (it fattens each surface as much as it sharpens falloff),
# and slim bases + protruding tips only got scallops, not petals.
# Not registered in HAIR; do not iterate on this — hair_01 below is
# the live implementation.
_V1_TIPS = (0.52, 0.25, -0.06, -0.33, -0.58)   # tip z over crown
_V1_SCALES = (1.00, 0.78, 0.56, 0.40, 0.28)    # petal size ladder
_V1_L1 = 0.50            # front petal visible length
_V1_SINK = 0.06          # plain sink — the approved attachment
_V1_STIFF = 3.0


def _hair_01_v1_metaball(col, mat, crown, m):
    """Soft Mohawk v1 — five metaball petal stacks in one fused
    field, realized to a mesh exactly like hair_00. SUPERSEDED."""
    import math

    import bpy
    hx, top, halfw, z_at = _crown(crown)
    k0 = m / 0.85
    fit = max(0.75, min(1.1, halfw / (REF_CROWN_HALFW * k0)))
    k = k0 * fit
    r = _mohawk_arc_r(top, z_at, hx, k, crown["height"])

    def tip_z(theta, length, tip_r):
        th = math.radians(theta)
        ax = math.radians(theta + MOHAWK_LEAN)
        return (r * (math.cos(th) - 1.0)
                + (length + 0.6 * tip_r) * math.cos(ax) - _V1_SINK)

    els = []
    solved = []
    for i, (tip_target, s) in enumerate(zip(_V1_TIPS, _V1_SCALES)):
        length = _V1_L1 * s
        # 0.60 = measured field-to-surface factor at this stiffness
        # (iter1 rendered the petal 15% narrower than the 0.70 guess)
        mid_r = (MOHAWK_W1_HALF / 0.60) * s
        # slim base, protruding tip (iter3): fat 1.12x base balls were
        # what bridged neighbouring petals into one smooth wave — the
        # petal silhouette lives in the mid+tip, the base only welds
        base_r, tip_r = 0.80 * mid_r, 0.38 * mid_r
        # tip_z falls monotonically with theta: bisect for the target
        lo, hi = -15.0, 80.0
        if tip_z(lo, length, tip_r) < tip_target:
            theta = lo
        elif tip_z(hi, length, tip_r) > tip_target:
            theta = hi
        else:
            for _ in range(40):
                mid = 0.5 * (lo + hi)
                if tip_z(mid, length, tip_r) > tip_target:
                    lo = mid
                else:
                    hi = mid
            theta = 0.5 * (lo + hi)
        th = math.radians(theta)
        ax = math.radians(theta + MOHAWK_LEAN)
        ry, rz = r * math.sin(th), r * (math.cos(th) - 1.0)
        solved.append((theta, tip_z(theta, length, tip_r)))
        for t, rr in ((0.05, base_r), (0.40, mid_r), (0.95, tip_r)):
            els.append(((0.0,
                         ry + t * length * math.sin(ax),
                         rz + t * length * math.cos(ax) - _V1_SINK),
                        rr, _V1_STIFF))
    print("hair_01v1: halfw=%.3f m=%.2f k=%.3f arc_r=%.3f" %
          (halfw, m, k, r))
    print("hair_01v1 VALIDATE spikes=%d thetas=%s tips=%s" % (
        len(_V1_TIPS),
        [round(t, 1) for t, _ in solved],
        [round(z, 3) for _, z in solved]))

    name = "Hair01"
    mb = bpy.data.metaballs.new(name)
    mb.resolution = 0.015
    mb.render_resolution = 0.015
    mb_obj = bpy.data.objects.new(name + "_meta", mb)
    col.objects.link(mb_obj)
    mb_obj.location = (hx, 0.0, top)
    for (x, y, z), rr, st in els:
        e = mb.elements.new()
        e.type = "BALL"
        e.co = (x * k, y * k, z * k)
        e.radius = rr * k
        e.stiffness = st
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(mb_obj.evaluated_get(deps))
    ob = bpy.data.objects.new(name, me)
    ob.location = mb_obj.location
    col.objects.link(ob)
    bpy.data.objects.remove(mb_obj, do_unlink=True)
    sm = ob.modifiers.new("Soften", "SMOOTH")
    sm.factor = 0.35
    sm.iterations = 3
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.update()
    ob.data.materials.append(mat)


def hair_01(col, mat, crown, m):
    """Soft Mohawk — SEPARATE soft petal meshes down the head's
    midline (v2; spike count = len(MOHAWK_RATIOS)). Deterministic
    bmesh construction: UV sphere -> petal taper (widest near
    lower-middle, soft rounded point) -> base flatten -> skull-normal
    lean growing along the row; every petal buries its own root in
    the measured crown. The runtime asset is a rendered layer, so
    overlapping objects in the HAIR collection are fine.
    APPROVED 2026-09-14 (mesh_iter15)."""
    import math

    import bmesh
    import bpy
    hx, top, halfw, z_at = _crown(crown)
    k0 = m / 0.85
    fit = max(0.75, min(1.1, halfw / (REF_CROWN_HALFW * k0)))
    k = k0 * fit
    r = _mohawk_arc_r(top, z_at, hx, k, crown["height"])
    print("hair_01: halfw=%.3f m=%.2f k=%.3f arc_r=%.3f" %
          (halfw, m, k, r))
    tips = []
    for i, (ratio, theta) in enumerate(zip(MOHAWK_RATIOS,
                                           MOHAWK_THETAS)):
        H = MOHAWK_H1 * ratio * k
        wx = MOHAWK_W1_HALF * MOHAWK_WIDTHS[i] * k
        wy = wx * MOHAWK_DEPTH
        th = math.radians(theta)
        ax = math.radians(theta + MOHAWK_LEAN)
        ay, az = math.sin(ax), math.cos(ax)     # petal axis, sagittal
        ry = r * math.sin(th)                   # root on the fitted
        rz = top + r * (math.cos(th) - 1.0)     # skull circle
        # the flattened base pole sits 0.376*H below the petal centre
        # (see the -0.55/0.45 squash below); centre placed so that
        # pole lands MOHAWK_BURY*H inside the head along the axis
        c_off = (0.376 - MOHAWK_BURY) * H
        cy, cz = ry + c_off * ay, rz + c_off * az
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=20,
                                  radius=1.0)
        for v in bm.verts:
            x, y, z = v.co
            if z > -0.3:
                # petal taper: widest stays near lower-middle, the
                # top closes to a soft rounded point (20%), no needle
                # (-0.3 / 1.35: mesh_iter1's -0.2 / 1.6 kept the bulb
                # low and the point abrupt — a droplet, not a leaf;
                # 0.80 depth: at 0.72 the tips stayed stubby and the
                # valleys read shallower than the reference's)
                t = (z + 0.3) / 1.3
                s = 1.0 - 0.80 * t ** 1.35
                x *= s
                y *= s
            if z < -0.55:
                # flatten the base where it enters the head
                z = -0.55 + (z + 0.55) * 0.45
            v.co = (x * wx, y * wy, z * 0.5 * H)
        name = "Hair01_S%d" % (i + 1)
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        mesh.polygons.foreach_set("use_smooth",
                                  [True] * len(mesh.polygons))
        mesh.update()
        ob = bpy.data.objects.new(name, mesh)
        ob.location = (hx + MOHAWK_STAGGER[i] * crown["width"],
                       cy, cz)
        # R_x(-ax) carries local +z onto (0, sin ax, cos ax): tips
        # lean toward +y, the BACK (front is -y). Euler XYZ applies
        # the y-rotation AFTER: a positive SIDE_LEAN then tips the
        # point toward +x, the Aurie's right, about the petal centre
        ob.rotation_euler = (-ax,
                             math.radians(MOHAWK_SIDE_LEAN[i]), 0.0)
        ob.data.materials.append(mat)
        col.objects.link(ob)
        tips.append(round(rz - top + (c_off + 0.5 * H) * az, 3))
    print("hair_01 VALIDATE spikes=%d thetas=%s tips=%s stagger_x=%s"
          % (len(MOHAWK_RATIOS), list(MOHAWK_THETAS), tips,
             [round(s * crown["width"], 3) for s in MOHAWK_STAGGER]))


HAIR = {"hair_00": hair_00, "hair_01": hair_01}

HAIR_INFO = {
    "hair_00": ("Cloud Puff", "one round lobed cloud puff sunk into "
                "the crown", "the approved metaball puff"),
    "hair_01": ("Soft Mohawk", "six separate soft petal meshes down "
                "the midline", "approved 2026-09-14"),
}
