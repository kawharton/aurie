"""Charm layer exporter — true-3D charm renders on the production rig.

    blender --background --factory-startup --python-exit-code 1 \
        --python export_charm_layers.py -- \
        --body round --charm charm_object_backpack_01 \
        --outdir Design/Aurie3D/Export/masters_2026-09-14_hair01 \
        [--orientation front|back] [--preview] [--samples 128]

Renders ONE charm as an app layer for one body and one orientation:
`<body>_<charm_id>[_back].png`, on the exact production canvas (same
camera, lights, 1024px, ortho x1.08) so install_app_assets.py ingests
it like any other layer with zero installer changes.

PLACEMENT AUTHORITY lives here, never in Swift:
- The mount point on the AURIE is derived from measure_body() using the
  same formulas write_manifest() ships as `anchors`, with the missing
  third dimension (body depth) measured off the real mesh.
- The point/direction on the CHARM comes from the library manifest's
  true-3D `attachment` block (charm_local_normalized space).
- The charm parents to the same turntable as every creature part with
  matrix_parent_inverse = Identity — the BODY-LOCAL ATTACHMENT
  INVARIANT (2026-09-14): world = R(orientation) @ authored, so the
  charm turns WITH the Aurie and back placement is never special-cased.

OCCLUSION is baked into the pixels: the charm renders with BODY+TUFT as
Cycles holdouts, so the sprite is pre-carved wherever the body is in
front of it for THAT orientation. The app just draws the charm layer
above the body group (the reserved Z.charm seam) — no per-orientation
z rules in Swift. Limbs are deliberately NOT in the holdout (they
animate at runtime; a baked carve would be wrong the moment an arm
moves).
"""

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import export_app_layers as EXP  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
LIBRARY = os.path.join(REPO, "AurieCharmLibrary")

# Charm width as a fraction of the body's own width — the approved
# accessory_slots.py authoring ratios, applied in 3D.
SLOT_SCALE = {"BACK": 0.62, "HEAD": 0.40, "BODY_SIDE": 0.30,
              "BODY_FRONT": 0.30}
# A worn pack floats a hair off the surface so the shells never z-fight.
MOUNT_GAP = 0.02

# HEAD charms sit BESIDE the crown centreline. The approved hair owns
# the centre (hair_00's puff and hair_01's Soft Mohawk ridge both run
# down the midline) and hair is LOCKED, so the CHARM adapts: the
# offset is a fraction of THIS body's measured usable crown
# half-width, never a hand-tuned per-body constant.
# Measured on Round (2026-09-15): the crown half-width is 0.718, but
# hair_00's puff already reaches |x| 0.589 (82% of it) and hair_01's
# ridge owns the midline front-to-back — so a HEAD charm only clears
# BOTH locked styles out on the crown's shoulder. Placement is polar
# on the crown: a fraction of the measured crown half-width, swung
# FORWARD of lateral so the charm reads from the front and stays clear
# of the mohawk's rearward run.
HEAD_RADIUS_K = 0.86     # of the measured crown half-width
HEAD_AZIMUTH = 40.0      # degrees forward of lateral
# A stem is stiff: planting it on the surface NORMAL out here would
# lean it ~43 degrees and read as falling off the head. Real tucked
# flowers lean a fraction of the slope.
HEAD_TILT_DAMP = 0.42
HEAD_SINK = 0.030        # of body height: seat the stem base in

# SHOULDER STRAPS (BACK slot, 2026-09-14; reference-matched pass 3,
# 2026-09-15): a worn pack must READ as worn from every view, so each
# BACK charm grows two soft PADDED BANDS — flat ribbons hugging the
# measured body surface (mesh strips widthwise-tangent to the surface,
# solidified outward and subdivided, NOT bevelled curve tubes — the
# tube read was rejected against the reference) — that wrap as one
# continuous loop: pack top corner -> over the shoulder -> a gently
# outward-bowing chest descent (no elbows: azimuth accelerates
# smoothly outward as it falls) -> around the side -> a SAGGING
# return that dips toward the rear centreline just under the pack,
# where the mirrored straps meet as the reference's under-pack band
# (minutely staggered in lift so the overlap never z-fights).
# Path keys are (azimuth-from-front in degrees, height fraction),
# interpolated densely; the body-fit radius comes from the measured
# profile. Straps belong to the BODY (never the arms).
# STRUCTURAL ROUTE (2026-09-15): each strap is ONE continuous band
# with BOTH ends attached to the pack — no loose ends, no cross-body
# belt, the two sides never meet. Keys are (azimuth-from-front deg,
# height fraction, radial extra in half-widths): extra 0 rides the
# body surface; positive pushes off the surface INTO the pack volume,
# hiding the terminations "sewn" into the bag. Per side:
#   pack TOP corner (buried) -> emerges at the pack edge -> over the
#   shoulder -> down the front/outer torso -> passes UNDER the arm
#   (the arm sits outside the surface-hugging band by construction —
#   real depth does the layering) -> wraps the lower side -> rises
#   behind the body into the pack's BOTTOM corner (buried, hidden by
#   the pack from the back view).
# SURFACE section of the route (the two END keys are COMPUTED from
# the mounted pack's real bounding box at build time — see
# build_straps — so the strap geometry demonstrably leads into the
# bag's top and bottom corners rather than fading at rear azimuths).
# The under-arm pass crosses the arm's HANGING zone (f~0.26-0.30 at
# the side), squarely behind the flipper, not above its root.
# NOTE (rev 8): no surface keys adjacent to the pack anchors — the
# strap leaves the shoulder crest (and the under-arm wrap) and flies a
# SHORT free segment straight to the designer's root on the bag face,
# like a real strap leaving the shoulder for its buckle. Hugging the
# body all the way to the rear first made the approach float as a
# high beam behind the crown.
STRAP_KEYS = [(120.0, 0.875, 0.0), (90.0, 0.88, 0.0),
              (60.0, 0.855, 0.0), (40.0, 0.78, 0.0),
              (34.0, 0.68, 0.0), (36.0, 0.57, 0.0),
              (44.0, 0.47, 0.0), (62.0, 0.36, 0.0),
              (82.0, 0.28, 0.0), (102.0, 0.26, 0.0),
              (125.0, 0.29, 0.0)]
STRAP_HALFWIDTH_K = 0.095   # band half-width, of the body half-width
STRAP_THICK_K = 0.042       # padding thickness, of the body half-width
STRAP_LIFT = 0.012          # clearance off the surface


def catmull_rom(keys, samples):
    """Smooth 2D interpolation through every key (endpoint-clamped)."""
    pts = [keys[0]] + list(keys) + [keys[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for j in range(samples):
            t = j / samples
            out.append(tuple(
                0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t
                       + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t * t
                       + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t ** 3)
                for k in range(len(p1))))
    out.append(pts[-2])
    return out


def build_straps(ccol, meas, ring_radius_at, strap_mat, side_anchors):
    """Two soft padded bands conforming to THIS body, each terminating
    at the pack's ORIGINAL designer strap roots (side_anchors: world
    points {+1: (top, bottom), -1: (top, bottom)} harvested from the
    molded strap shells before their deletion and transformed through
    the pack's own matrix — they ride the bag's lean).

    Each band is a quad strip whose width direction is TANGENT to the
    body surface (t-hat cross n-hat), lifted slightly off it, then
    Solidify (outward, along the surface normal) + Subdivision make it
    a rounded padded ribbon. Deterministic — no interactive edits.
    """
    import bmesh
    bottom, height = meas["bottom"], meas["height"]
    halfw = meas["halfw_body"]
    bw = STRAP_HALFWIDTH_K * halfw
    th = STRAP_THICK_K * halfw
    zc = (meas["top"] + meas["bottom"]) / 2.0
    half_h = height / 2.0

    def anchor_key(pnt):
        """A world anchor expressed in the path's (psi, f, extra)
        coordinates (x folded positive; the generator mirrors)."""
        f = (pnt.z - bottom) / height
        psi = math.degrees(math.atan2(abs(pnt.x), -pnt.y))
        rho = math.hypot(pnt.x, pnt.y)
        extra = (rho - ring_radius_at(pnt.z) - STRAP_LIFT) / halfw
        return (psi, f, extra)

    made = []
    for side in (-1.0, 1.0):
        top_w, bot_w = side_anchors[side]
        bot_key = anchor_key(bot_w)
        top_key = anchor_key(top_w)
        # The tail BURIES past the lower root INTO the bag (same root,
        # extended along the approach) — terminating flush AT the root
        # left the padded end reading as a floating stop against the
        # curved shell, while the top end already penetrates and reads
        # attached. No new endpoint: the root still sets the entry.
        # Burial nudge is PACK-scale, not body-scale (2026-09-17): the
        # old +0.35 body-half-widths overshot the small pack sideways on
        # wide/tall bodies, leaving the tail tips floating in open air
        # beside the body ("wings"). A short push past the root reads
        # sewn-in on every body.
        # Pure RADIAL burial: straight off the body surface into the
        # bag's volume at the root's own azimuth/height — no lateral
        # drift (the old +5 deg swung the tip sideways past the small
        # pack on narrow bodies, leaving a visible hooked open end).
        burial = (bot_key[0], bot_key[1] + 0.01, bot_key[2] + 0.45)
        # ANCHORED APPROACHES (2026-09-17 fix): a Catmull-Rom through a
        # sparse free-flight segment OVERSHOOTS — on wide/tall bodies
        # the lower tails swept out past the pack as detached "wings"
        # and the upper approach left floating chips (Round's
        # proportions had masked it). One SURFACE key at each root's
        # own azimuth/height pins the spline: the band hugs the body to
        # the root's azimuth, then dives radially into the designer
        # root. Same roots, no new endpoints — only the approach path.
        top_surface = (top_key[0], top_key[1], 0.0)
        bot_surface = (bot_key[0], bot_key[1], 0.0)
        # TUCK (2026-09-17): the design intent has the lower entries
        # "buried, hidden by the pack from the back view" — but the
        # designer roots sit on the bag's curved SIDE faces, and on
        # non-Round bodies their back-projection lands OUTSIDE the pack
        # silhouette, so the tail ends floated in the open beside the
        # bag. Route the final approach through the pack's rear-central
        # shadow first: the band dips toward the rear centreline under
        # the bag (the approved under-pack meeting), THEN rises out to
        # its root — so everything from the tuck onward is occluded by
        # the pack itself in the back view, on every body.
        tuck = (min(bot_key[0] + 14.0, 176.0), bot_key[1] - 0.02,
                max(bot_key[2] * 0.5, 0.05))
        keys = ([top_key, top_surface] + STRAP_KEYS
                + [bot_surface, tuck, bot_key, burial])
        path = catmull_rom(keys, 24)
        lift = STRAP_LIFT
        centres, normals = [], []
        for psi_deg, f, extra in path:
            z = bottom + f * height
            r = ring_radius_at(z) + lift + extra * halfw
            psi = math.radians(psi_deg)
            u = Vector((side * math.sin(psi), -math.cos(psi), 0.0))
            pnt = u * r + Vector((0.0, 0.0, z))
            # Ellipse-profile outward normal at (ring, z).
            n = (u * (max(r, 1e-5) / (halfw * halfw))
                 + Vector((0.0, 0.0, (z - zc) / (half_h * half_h))))
            normals.append(n.normalized())
            centres.append(pnt)
        mesh = bpy.data.meshes.new(f"StrapBand_{int(side)}")
        bm = bmesh.new()
        rails = []
        for i, c in enumerate(centres):
            t = (centres[min(i + 1, len(centres) - 1)]
                 - centres[max(i - 1, 0)])
            w = t.cross(normals[i])
            if w.length < 1e-6:
                w = Vector((0.0, 0.0, 1.0))
            w = w.normalized() * bw
            rails.append((bm.verts.new(c - w), bm.verts.new(c + w)))
        for i, ((a1, b1), (a2, b2)) in enumerate(zip(rails, rails[1:])):
            # Winding chosen so each face's normal points OUTWARD along
            # ITS OWN surface normal (they swing ~180 deg around the
            # loop): Solidify then thickens away from the body.
            f4 = bm.faces.new((a1, b1, b2, a2))
            f4.normal_update()
            if f4.normal.dot(normals[i]) < 0:
                f4.normal_flip()
        bm.normal_update()
        bm.to_mesh(mesh)
        bm.free()
        ob = bpy.data.objects.new(f"Strap_{'l' if side < 0 else 'r'}",
                                  mesh)
        ob.data.materials.append(strap_mat)
        sol = ob.modifiers.new("pad", "SOLIDIFY")
        sol.thickness = th
        sol.offset = 1.0
        sub = ob.modifiers.new("soft", "SUBSURF")
        sub.levels = sub.render_levels = 2
        for poly in ob.data.polygons:
            poly.use_smooth = True
        ccol.objects.link(ob)
        made.append(ob)
    return made


def charm_record(charm_id):
    m = json.load(open(os.path.join(LIBRARY, "_MANIFESTS", "charms.json")))
    for c in m["charms"]:
        if c["id"] == charm_id:
            return c
    sys.exit(f"charm {charm_id} not in the library manifest")


def append_charm(charm_id):
    """Append every object from the processed master into a CHARM
    collection under one root empty (the placement handle)."""
    path = os.path.join(LIBRARY, "_PROCESSED", f"{charm_id}.blend")
    if not os.path.exists(path):
        sys.exit(f"no processed master at {path}")
    before = set(bpy.data.objects)
    with bpy.data.libraries.load(path) as (src, dst):
        dst.objects = list(src.objects)
    col = bpy.data.collections.new("CHARM")
    bpy.context.scene.collection.children.link(col)
    root = bpy.data.objects.new("CharmRoot", None)
    col.objects.link(root)
    for ob in set(bpy.data.objects) - before:
        if ob is root or ob.name in col.objects:
            continue
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        col.objects.link(ob)
        if ob.parent is None:
            ob.parent = root
            ob.matrix_parent_inverse = Matrix.Identity(4)
    return col, root


def find_molded_straps(ob):
    """Locate the pack's own molded shoulder-strap shells and their
    attachment ROOTS, in MESH-LOCAL coordinates.

    The processed pack is a kitbash of ~20 separate shells. The two
    shoulder straps are the tall, narrow, OFF-CENTRE shells that
    protrude deep on the mount side (+y): bbox y_max > 0.26,
    |x-centre| > 0.05, z-span > 0.5. Their roots — where the designer
    attached them to the bag — are their vertices in CONTACT with any
    OTHER shell (KD-tree distance, widening epsilon), clustered into a
    top and a bottom group per strap. Returns (anchors, strap_faces):
    anchors = list of (top_local, bottom_local) per strap shell,
    strap_faces = set of face indices to delete later.
    """
    import bmesh
    from mathutils import kdtree
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    comp = [-1] * len(bm.faces)
    ncomp = 0
    for f in bm.faces:
        if comp[f.index] != -1:
            continue
        stack = [f]
        while stack:
            g = stack.pop()
            if comp[g.index] != -1:
                continue
            comp[g.index] = ncomp
            for e in g.edges:
                for lf in e.link_faces:
                    if comp[lf.index] == -1:
                        stack.append(lf)
        ncomp += 1
    from collections import defaultdict
    faces_by = defaultdict(list)
    for f in bm.faces:
        faces_by[comp[f.index]].append(f)

    def bbox(fs):
        pts = [v.co for f in fs for v in f.verts]
        return (Vector((min(p.x for p in pts), min(p.y for p in pts),
                        min(p.z for p in pts))),
                Vector((max(p.x for p in pts), max(p.y for p in pts),
                        max(p.z for p in pts))))

    strap_cis = []
    for ci, fs in faces_by.items():
        lo, hi = bbox(fs)
        if (hi.y > 0.26 and abs((lo.x + hi.x) / 2) > 0.05
                and (hi.z - lo.z) > 0.5):
            strap_cis.append(ci)
    if len(strap_cis) != 2:
        sys.exit(f"expected 2 molded strap shells, found {len(strap_cis)}")

    # LOWER TAIL shells (2026-09-17, the floating-"wings" root cause):
    # the pack carries THREE molded strap structures per side — the
    # deep shoulder shells above (harvested for roots, deleted), the
    # side pockets (kept), and a pair of LONG LOWER TAILS that sweep
    # from near the bag's midline far outboard with curled ends. They
    # never matched the shoulder filter, were never deleted, and worn
    # on any body they splay into open air beside the creature — the
    # "harness not connected" read. Census signature (verified against
    # the full shell table): ONE-SIDED in x, long x-extent, reaching
    # far outboard — which the boxy pockets (extent ~0.25) and every
    # centred shell fail.
    tail_cis = []
    for ci, fs in faces_by.items():
        if ci in strap_cis:
            continue
        lo, hi = bbox(fs)
        if (lo.x * hi.x > 0                       # one side only
                and (hi.x - lo.x) > 0.30          # a long sweep
                and max(abs(lo.x), abs(hi.x)) > 0.42):   # far outboard
            tail_cis.append(ci)
    print(f"AURIE lower-tail shells removed: {len(tail_cis)}")
    strap_cis = strap_cis + tail_cis

    # KD-tree over every NON-strap shell (the bag proper).
    bag_verts = [v.co.copy() for ci, fs in faces_by.items()
                 if ci not in strap_cis
                 for f in fs for v in f.verts]
    kd = kdtree.KDTree(len(bag_verts))
    for i, co in enumerate(bag_verts):
        kd.insert(co, i)
    kd.balance()

    anchors = []
    strap_faces = set()
    for ci in strap_cis:
        verts = {v for f in faces_by[ci] for v in f.verts}
        strap_faces.update(f.index for f in faces_by[ci])
        contact = []
        for eps in (0.03, 0.05, 0.08, 0.12):
            contact = [v.co.copy() for v in verts
                       if kd.find(v.co)[2] < eps]
            if len(contact) >= 8:
                break
        zs = [p.z for p in contact]
        zmid = (min(zs) + max(zs)) / 2
        top = [p for p in contact if p.z >= zmid]
        bot = [p for p in contact if p.z < zmid]
        t = sum(top, Vector()) / len(top)
        b = sum(bot, Vector()) / len(bot)
        anchors.append((t, b))
        print(f"AURIE strap shell {ci}: {len(faces_by[ci])} faces, "
              f"top root local=({t.x:+.3f},{t.y:+.3f},{t.z:+.3f}) "
              f"bottom root local=({b.x:+.3f},{b.y:+.3f},{b.z:+.3f})")
    bm.free()
    return anchors, strap_faces


def delete_faces(ob, face_indices):
    """Remove the recorded faces (the molded strap shells) wholesale."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    doomed = [bm.faces[i] for i in sorted(face_indices)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    print(f"AURIE deleted {len(doomed)} molded strap faces")


def charm_bbox(col):
    pts = []
    for ob in col.objects:
        if ob.type != "MESH":
            continue
        pts += [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts),
                 min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts),
                 max(p.z for p in pts)))
    return lo, hi


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--body", required=True, choices=sorted(EXP.BODIES))
    ap.add_argument("--charm", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--orientation", default="front",
                    choices=["front", "back"])
    ap.add_argument("--samples", type=int, default=128)
    ap.add_argument("--roots-diag", action="store_true",
                    help="BACK-view diagnostic: render the PACK ALONE "
                         "(straps hidden, no holdouts) and print the "
                         "camera-space pixel positions of the designer "
                         "bottom roots vs the pack's rendered bbox — "
                         "the data needed to decide whether a root "
                         "projects outside the visible bag silhouette.")
    ap.add_argument("--preview", action="store_true",
                    help="also render an assembled body+tuft+charm view "
                         "for placement review (not an app asset)")
    ap.add_argument("--hair", default="none",
                    help="review-rig hair style (none|tuft|hair_00|"
                         "hair_01); previews/diagnostics only — the app "
                         "layer itself is hair-independent")
    ap.add_argument("--head-side", default="right",
                    choices=["left", "right"],
                    help="which side of the crown a HEAD charm sits on")
    ap.add_argument("--anchors-diag", action="store_true",
                    help="render before/after diagnostics of the pack's "
                         "original strap roots (markers) and their "
                         "removal — never app assets")
    ap.add_argument("--diag-yaw", type=float, default=None,
                    help="extra diagnostic render at this turntable yaw "
                         "in degrees (e.g. 135 for a 3/4 view of how "
                         "straps wrap) — never an app asset")
    args = ap.parse_args(argv)
    out = os.path.abspath(args.outdir)
    os.makedirs(out, exist_ok=True)

    rec = charm_record(args.charm)
    att = rec.get("attachment")
    if not att:
        sys.exit(f"{args.charm} has no attachment block")
    slot = att["type"]
    if slot == "HANGING":
        # HANGING mounts on the tail nub; launch Auries ship without a
        # tail, so this placement cannot look correct yet. Refuse loudly
        # rather than float a charm in mid-air.
        sys.exit("HANGING charms need the tail (not in launch scope)")
    if slot not in SLOT_SCALE:
        sys.exit(f"unsupported attachment type {slot}")

    (mod, scene, cols, R, centre, surf, pos, arm, foot,
     fixed_m) = EXP.build_body(args.body)
    meas = EXP.measure_body(cols)
    scene.cycles.samples = args.samples
    cols["STAGE"].hide_render = True
    # Match the production canvas exactly (export_app_layers.main).
    scene.camera.data.ortho_scale *= 1.08
    scene.render.resolution_x = scene.render.resolution_y = 1024

    # Raw body verts in world space — the same sampling measure_body uses.
    bpy.context.view_layer.update()
    pts = []
    for ob in cols["BODY"].objects:
        if ob.type == "MESH":
            pts += [ob.matrix_world @ v.co for v in ob.data.vertices]
    height = meas["height"]

    def rear_y_at(x, z, band=0.08):
        near = [p.y for p in pts
                if abs(p.x - x) <= band * height
                and abs(p.z - z) <= band * height]
        return max(near) if near else 0.0

    def flank_y_span(x_sign, z, band=0.08):
        fl = meas["flank_of"](z)
        near = [p.y for p in pts
                if abs(p.x - x_sign * fl) <= band * height
                and abs(p.z - z) <= band * height]
        return (max(near) if near else 0.0)

    def axis_x_at(z, band=0.06):
        near = [p.x for p in pts if abs(p.z - z) <= band * height]
        return (min(near) + max(near)) / 2.0 if near else 0.0

    # ---- mount point + outward direction on the AURIE ------------------
    # HEAD reuses the exact anchor formula write_manifest() ships. BACK
    # deliberately does NOT reuse the manifest's x offset: that
    # -0.34*mid_flank was the 2D compositing "one-shoulder peek" trick,
    # and in true 3D it reads as a satchel on the hip. A worn pack sits
    # CENTRED on the spine — the front view then hides it behind the
    # body, which is physically correct ("a backpack should primarily
    # read from behind").
    if slot == "BACK":
        mz = meas["bottom"] + 0.56 * height
        seat_band = 0.08
        if args.body != "round":     # Round's approved seat is FROZEN
            # Squat bodies (beanbag): at 56% height a straight box pack
            # can overrun the crown and stand off the fast-receding
            # dome. Cap the pack TOP at the body top (estimated from
            # the manifest extents + attach offset), and seat with a
            # TIGHT band — the 0.08 band-max overshoots depth on steep
            # profiles (the z_at trap, again).
            ext = rec["processing"]["geometry"]["extentsNormalized"]
            s_est = SLOT_SCALE[slot] * meas["width"] / max(ext[0], 1e-6)
            top_off = (ext[2] / 2.0 - att["position"][2]) * s_est
            mz = min(mz, meas["top"] - top_off)
            mz = max(mz, meas["bottom"] + 0.40 * height)
            seat_band = 0.03
        mx = axis_x_at(mz)
        mount = Vector((mx, rear_y_at(mx, mz, band=seat_band)
                        + MOUNT_GAP, mz))
        outward = Vector((0.0, 1.0, 0.0))
    elif slot == "HEAD":
        hside = -1.0 if args.head_side == "left" else 1.0
        az = math.radians(HEAD_AZIMUTH)

        def crown_xy(x, y, band=0.05):
            """True crown height at (x, y) — sampled off the real mesh,
            so it works on every silhouette (no band-MAX bias: the
            window is centred on the query point in BOTH axes)."""
            near = [p.z for p in pts
                    if abs(p.x - x) <= band * height
                    and abs(p.y - y) <= band * height]
            return max(near) if near else meas["top"]

        def crown_polar(r):
            return (meas["head_x"] + hside * r * math.cos(az),
                    -r * math.sin(az))
        r0 = HEAD_RADIUS_K * meas["halfw"]
        px, py = crown_polar(r0)
        z_here = crown_xy(px, py)
        dr = 0.12 * meas["halfw"]
        px2, py2 = crown_polar(r0 + dr)
        slope = (crown_xy(px2, py2) - z_here) / max(dr, 1e-6)
        tilt = HEAD_TILT_DAMP * math.atan(-slope)
        u = Vector((hside * math.cos(az), -math.sin(az), 0.0))
        outward = (Vector((0.0, 0.0, 1.0)) * math.cos(tilt)
                   + u * math.sin(tilt)).normalized()
        mount = Vector((px, py, z_here - HEAD_SINK * height))
    else:  # BODY_SIDE / BODY_FRONT hug the flank / front surface
        mz = meas["bottom"] + 0.46 * height
        if slot == "BODY_SIDE":
            fl = meas["flank_of"](mz)
            mount = Vector((fl + MOUNT_GAP, 0.0, mz))
            outward = Vector((1.0, 0.0, 0.0))
        else:
            front_y = -rear_y_at(0.0, mz)   # revolve: front depth = rear
            mount = Vector((0.0, front_y - MOUNT_GAP, mz))
            outward = Vector((0.0, -1.0, 0.0))

    # ---- bring the charm in, size it, aim it, seat it -------------------
    ccol, root = append_charm(args.charm)
    strap_anchors_local, strap_shell_faces = None, None
    if args.charm == "charm_object_backpack_01":
        # The molded straps carry the DESIGNER'S attachment points:
        # harvest their roots first (mesh-local), delete the shells
        # later — reference information, never visible geometry.
        mesh_ob = next(o for o in ccol.objects if o.type == "MESH")
        strap_anchors_local, strap_shell_faces = \
            find_molded_straps(mesh_ob)
    bpy.context.view_layer.update()
    lo, hi = charm_bbox(ccol)
    ext_x = max(hi.x - lo.x, 1e-6)
    if slot == "BACK":
        # FROZEN backpack rule: width fraction over the charm's own
        # x-extent (correct for wide, bag-shaped charms).
        s = SLOT_SCALE[slot] * meas["width"] / ext_x
    else:
        # Tall/thin charms (a flower is ~4x taller than wide) would be
        # enormous under the x-extent rule — 0.34 x width across a
        # 0.23 normalized x-extent is 1.5x the body's width in height.
        # Scale the charm's LONGEST axis instead.
        ext_max = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, 1e-6)
        s = SLOT_SCALE[slot] * meas["width"] / ext_max
    # Yaw so the charm's attachment normal points INTO the mount surface
    # (i.e. opposite the surface's outward direction). Vertical normals
    # (HEAD) need no yaw — the flower already stands on its stem base.
    n = Vector(att["normal"])
    yaw = 0.0
    if abs(n.z) < 0.5:
        want = -Vector((outward.x, outward.y, 0.0))
        have = Vector((n.x, n.y, 0.0))
        if have.length > 1e-6 and want.length > 1e-6:
            yaw = math.atan2(want.y, want.x) - math.atan2(have.y, have.x)
    rot = Matrix.Rotation(yaw, 4, "Z")
    if abs(n.z) > 0.5:
        # Vertical-normal charms (HEAD): align the charm's up axis with
        # the measured surface normal so it leans with the dome.
        rot = (Vector((0.0, 0.0, -1.0)) if n.z > 0 else
               Vector((0.0, 0.0, 1.0))).rotation_difference(
                   outward).to_matrix().to_4x4()
    attach_local = Vector(att["position"])
    root.matrix_world = (Matrix.Translation(
        mount - rot @ (attach_local * s)) @ rot
        @ Matrix.Scale(s, 4))
    bpy.context.view_layer.update()
    if slot == "BACK":
        # The attach point rides where it was authored (depth + height),
        # but a WORN pack centres across the spine: cancel the attach
        # point's sideways offset with the charm's own measured bbox.
        lo2, hi2 = charm_bbox(ccol)
        root.location.x += mount.x - (lo2.x + hi2.x) / 2.0
        bpy.context.view_layer.update()
        # TOP LEAN (2026-09-15): a worn pack rests AGAINST the back,
        # so the bag tips toward the body about its bottom-front
        # contact edge — the bottom stays put (general position
        # locked), only the top leans in to follow the receding rear
        # surface.
        lo3, hi3 = charm_bbox(ccol)
        pivot = Vector((0.0, lo3.y, lo3.z))
        lean = Matrix.Rotation(math.radians(12.0), 4, "X")
        root.matrix_world = (Matrix.Translation(pivot) @ lean
                             @ Matrix.Translation(-pivot)
                             @ root.matrix_world)
        bpy.context.view_layer.update()
    # THE DESIGNER'S ANCHORS, captured in the AUTHORED frame: the
    # pack-local roots transformed through the pack's final matrix
    # (mount + centring + lean) BEFORE the turntable exists — the same
    # frame the strap surface route is authored in, so front and back
    # runs build IDENTICAL geometry and the turn alone handles
    # orientation (the invariant). Capturing after turntable parenting
    # measured TURNED coordinates and mangled the back run's route.
    side_anchors = None
    if strap_anchors_local is not None:
        mesh_ob = next(o for o in ccol.objects if o.type == "MESH")
        mw = mesh_ob.matrix_world
        side_anchors = {}
        for t_loc, b_loc in strap_anchors_local:
            t_w, b_w = mw @ t_loc, mw @ b_loc
            sgn = 1.0 if (t_w.x + b_w.x) >= 0 else -1.0
            side_anchors[sgn] = (t_w, b_w)
        for sgn, (t_w, b_w) in sorted(side_anchors.items()):
            print(f"AURIE anchor side {sgn:+.0f}: "
                  f"top=({t_w.x:+.3f},{t_w.y:+.3f},{t_w.z:+.3f}) "
                  f"bottom=({b_w.x:+.3f},{b_w.y:+.3f},{b_w.z:+.3f})")
        if len(side_anchors) != 2:
            sys.exit("strap shells did not split into left/right")

    # ---- the turntable: identical invariant to the production exporter --
    sfx = "_back" if args.orientation == "back" else ""
    turn = bpy.data.objects.new("TurnPivot", None)
    scene.collection.objects.link(turn)
    if args.orientation == "back":
        turn.rotation_euler = (0.0, 0.0, math.pi)
    for group in ("BODY", "TUFT", "FACE"):
        for ob in cols[group].objects:
            if ob.parent is None:
                ob.parent = turn
                ob.matrix_parent_inverse = Matrix.Identity(4)
    for ob in ccol.objects:
        if ob.parent is None:
            ob.parent = turn
            ob.matrix_parent_inverse = Matrix.Identity(4)
    bpy.context.view_layer.update()

    def render(path):
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("AURIE OK:", os.path.basename(path))

    def show_only(names):
        for cname, col in cols.items():
            if cname != "RIG":
                col.hide_render = cname not in names
        ccol.hide_render = "CHARM" not in names

    def holdout(on):
        # LIMBS joined 2026-09-17: the baked REST arms/feet carve the
        # strap wherever a resting limb covers it. The app draws limbs
        # BEHIND the body plane (animation-safe joints), so no runtime
        # z-order can ever put an arm in front of the strap — the
        # under-arm pass must be carved into the pixels, exactly as the
        # approved 3D proofs showed it. A gesturing arm briefly exposes
        # the carved hole to the body behind it, which is mild and
        # matches the accessory reading as worn against the body.
        for cname in ("BODY", "TUFT", "LIMBS"):
            for ob in cols[cname].objects:
                ob.is_holdout = on

    if slot == "BACK" and side_anchors is not None:
        strap_mat = bpy.data.materials.get("DarkBrown")
        if strap_mat is None:
            strap_mat = bpy.data.materials.new("StrapBrown")
            strap_mat.use_nodes = True
            next(n for n in strap_mat.node_tree.nodes
                 if n.type == "BSDF_PRINCIPLED") \
                .inputs["Base Color"].default_value = \
                (0.099, 0.048, 0.030, 1.0)
        zc = (meas["top"] + meas["bottom"]) / 2.0
        half_h = height / 2.0
        half_w = meas["halfw_body"]

        if args.body == "round":
            # FROZEN (approved 2026-09-15): Round's analytic oblate-
            # ellipse fit ships exactly as reviewed — do not retouch.
            def ring_radius_at(z):
                u = max(-1.0, min(1.0, (z - zc) / half_h))
                return half_w * math.sqrt(max(0.0, 1.0 - u * u))
        else:
            # BODY-TRUE profile for the other nine silhouettes (pear,
            # teardrop, heart's lobes, beanbag's lean are not
            # ellipses): tight-band ring radii sampled off the real
            # mesh at 96 levels, then smoothed — raw band-max
            # stair-steps the padding (the z_at trap, radial flavour).
            n_lv = 96
            band = 0.03 * height
            levels = [meas["bottom"] + (i / (n_lv - 1)) * height
                      for i in range(n_lv)]
            raw = []
            for lz in levels:
                near = [abs(p.x) for p in pts if abs(p.z - lz) <= band]
                raw.append(max(near) if near else 0.0)
            smoothed = [
                sum(raw[max(0, i - 2):i + 3])
                / len(raw[max(0, i - 2):i + 3])
                for i in range(n_lv)]

            def ring_radius_at(z):
                t = (z - meas["bottom"]) / height * (n_lv - 1)
                i = max(0, min(n_lv - 2, int(t)))
                frac = max(0.0, min(1.0, t - i))
                return smoothed[i] * (1 - frac) + smoothed[i + 1] * frac

        mesh_ob = next(o for o in ccol.objects if o.type == "MESH")

        def diag_shot(tag):
            show_only(["BODY", "TUFT", "CHARM"])
            turn.rotation_euler = (0.0, 0.0, math.radians(135.0))
            bpy.context.view_layer.update()
            render(os.path.join(
                out, f"diag_anchors_{tag}_{args.body}.png"))
            turn.rotation_euler = (0.0, 0.0,
                                   math.pi if args.orientation == "back"
                                   else 0.0)
            bpy.context.view_layer.update()

        markers = []
        if args.anchors_diag:
            mmat = bpy.data.materials.new("AnchorMark")
            mmat.use_nodes = True
            bsdf_m = next(n for n in mmat.node_tree.nodes
                          if n.type == "BSDF_PRINCIPLED")
            bsdf_m.inputs["Emission Color"].default_value = (1, 0.1, 0.1, 1)
            bsdf_m.inputs["Emission Strength"].default_value = 8.0
            for t_w, b_w in side_anchors.values():
                for pnt in (t_w, b_w):
                    me = bpy.data.meshes.new("mark")
                    import bmesh as _bm
                    b2 = _bm.new()
                    _bm.ops.create_icosphere(b2, subdivisions=2,
                                             radius=0.055)
                    b2.to_mesh(me)
                    b2.free()
                    me.materials.append(mmat)
                    mo = bpy.data.objects.new("AnchorMark", me)
                    mo.location = pnt
                    ccol.objects.link(mo)
                    mo.parent = turn
                    mo.matrix_parent_inverse = Matrix.Identity(4)
                    markers.append(mo)
            diag_shot("before")
            for mo in markers:
                bpy.data.objects.remove(mo, do_unlink=True)

        # Reference captured — now the originals GO.
        delete_faces(mesh_ob, strap_shell_faces)
        bpy.context.view_layer.update()
        if args.anchors_diag:
            diag_shot("after")

        build_straps(ccol, meas, ring_radius_at, strap_mat,
                     side_anchors)
        for ob in ccol.objects:
            if ob.parent is None:
                ob.parent = turn
                ob.matrix_parent_inverse = Matrix.Identity(4)
        bpy.context.view_layer.update()

    if args.roots_diag:
        import bpy_extras
        for ob in ccol.objects:
            if ob.name.startswith("StrapBand"):
                ob.hide_render = True
        show_only(["CHARM"])
        diag = os.path.join(out, f"_diag_pack_{args.body}{sfx}.png")
        render(diag)
        cam = scene.camera
        res = scene.render.resolution_x
        for side in (-1.0, 1.0):
            top_w, bot_w = side_anchors[side]
            wp = turn.matrix_world @ bot_w
            uv = bpy_extras.object_utils.world_to_camera_view(
                scene, cam, wp)
            print(f"AURIE ROOTDIAG side {side:+.0f}: "
                  f"px=({uv.x * res:.0f},{(1 - uv.y) * res:.0f})")
        return

    # ---- the app layer: charm only, body+tuft carving it ----------------
    # Rendered FIRST, against the UNLIFTED body (registration identical
    # to the production body layer; the app applies leg lift at runtime).
    show_only(["BODY", "TUFT", "LIMBS", "CHARM"])
    holdout(True)
    render(os.path.join(out, f"{args.body}_{args.charm}{sfx}.png"))
    holdout(False)

    if args.preview or args.diag_yaw is not None:
        # REVIEW RIG: the approved rest limbs (arm_00/leg_00) join the
        # scene so the arm/strap depth relationship is inspectable —
        # the straps hug the body UNDER the arms, so real 3D depth must
        # show body -> strap -> arm, exactly what ships. Locations are
        # LOCAL under the turntable, so lifting after parenting is
        # sound (world = R @ local).
        import aurie_limb_styles as L  # noqa: E402
        body_mat = bpy.data.materials["AurieBody"]
        limbs = cols["LIMBS"]
        # build_body ships baked rest limbs (ArmL/ArmR/FootL/FootR);
        # the production exporter clears them before rendering limb
        # styles and so must this rig — leaving them in doubled every
        # preview's arms and feet (found 2026-09-15).
        for ob in list(limbs.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        arm_p = arm if hasattr(mod, "CFG") else dict(
            x=meas["shoulder_x"], y=arm["y"], z=meas["shoulder_z"])
        m = fixed_m or EXP.derived_m(meas)
        for lside in (-1, 1):
            L.ARMS["arm_00"](limbs, body_mat, lside, arm_p["x"],
                             arm_p["y"], arm_p["z"], m, surf=None)
            L.LEGS["leg_00"](limbs, body_mat, lside, foot["x"],
                             foot["y"], m, fcx=foot["cx"])
        for ob in limbs.objects:
            if ob.parent is None:
                ob.parent = turn
                ob.matrix_parent_inverse = Matrix.Identity(4)
        # HAIR for the review rig: the approved styles are LOCKED and
        # are built here UNTOUCHED, purely so charm/hair coexistence is
        # inspectable. The app-facing charm layer never renders hair
        # (it would need a sprite per style); the charm is placed to
        # avoid the crown centreline instead.
        hair_cols = []
        if args.hair != "tuft":
            for ob in cols["TUFT"].objects:
                ob.hide_render = True        # styled hair replaces it
        if args.hair not in ("none", "tuft"):
            import aurie_hair_styles as HAIR  # noqa: E402
            hcol = bpy.data.collections.new("VHAIR")
            scene.collection.children.link(hcol)
            cols["VHAIR"] = hcol
            HAIR.HAIR[args.hair](hcol, body_mat, meas, m)
            for ob in hcol.objects:
                if ob.parent is None:
                    ob.parent = turn
                    ob.matrix_parent_inverse = Matrix.Identity(4)
            hair_cols.append("VHAIR")

        lift = L.LEG_BODY_LIFT["leg_00"] * (m / 0.85)
        for group in ("BODY", "TUFT") + tuple(hair_cols):
            for ob in cols[group].objects:
                ob.location.z += lift
        for ob in ccol.objects:
            if ob.parent == turn:
                ob.location.z += lift      # charm rides the body group
        for ob in limbs.objects:
            if ob.name.startswith("Arm"):
                ob.location.z += lift
        bpy.context.view_layer.update()

    if args.preview:
        show_only(["BODY", "TUFT", "LIMBS", "CHARM"] + hair_cols)
        render(os.path.join(out,
                            f"preview_{args.body}_{args.charm}{sfx}.png"))
    if args.diag_yaw is not None:
        # 3/4 wrap diagnostic: everything visible, arbitrary yaw.
        show_only(["BODY", "TUFT", "LIMBS", "CHARM"] + hair_cols)
        turn.rotation_euler = (0.0, 0.0, math.radians(args.diag_yaw))
        bpy.context.view_layer.update()
        render(os.path.join(
            out, f"diag_{args.body}_{args.charm}"
                 f"_yaw{int(args.diag_yaw)}.png"))
    print(f"CHARM DONE {args.body} {args.charm} {args.orientation}")


if __name__ == "__main__":
    main()
