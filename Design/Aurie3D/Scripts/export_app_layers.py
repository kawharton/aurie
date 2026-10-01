"""Export one body's modular app layers from the canonical Blender scenes.

    blender --background --factory-startup --python export_app_layers.py -- \
        --body round --outdir <dir> [--faces all] [--skip-parts]

Everything is rendered from ONE build with a single camera and canvas, so the
layers are pixel-registered and the app stacks them with no offsets.

WHAT COMES OUT
  <body>_body / _tuft / _arm_l / _arm_r / _leg_l / _leg_r
      Neutral #C0C0C0 so the app can multiply-tint per family. White clips a
      third of the shading, which is why the neutral is not white.
      Limb and tuft passes render with the body as a HOLDOUT: the limb roots
      are embedded in the body, so without it no 2D stacking order is right.
  <body>_face_<expr>_{cheeks,mouth,eyes}
      Cheeks live in the FACE layer, never the body, so blush is not tinted
      with the family colour.
  <body>_face_<expr>_blink_eyes
      Eyes only — blink drives the eye layer and keeps the expression's own
      mouth and blush underneath.

Bodies are declared in BODIES below; Stage 3 runs the same script per body.
"""

import argparse
import importlib
import json
import math
import os
import shutil
import sys

import bpy
try:
    from PIL import Image
except ImportError:
    Image = None
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aurie_body_common as common  # noqa: E402
import aurie_face_expressions as FX  # noqa: E402
import aurie_hair_styles as HAIR  # noqa: E402
import aurie_limb_styles as L  # noqa: E402

NEUTRAL = "C0C0C0"          # brightest neutral albedo with zero clipping
# arm_03 Bud Nubs, arm_04 Soft Mittens and arm_05 Wing Flaps removed
# 2026-09-13; all three ids burned (they lived on test devices).
ARM_STYLES = ["arm_00", "arm_01", "arm_02"]
# 2026-09-13 renumbering: 04 = metaball Paw Steps, 05 = Bulb Boots
LEG_STYLES = ["leg_00", "leg_01", "leg_02", "leg_03", "leg_04", "leg_05"]
# hair_00 = metaball Cloud Puff (approved 2026-09-13). hair_01 =
# mesh Soft Mohawk (approved 2026-09-14). Twin Poms (approved-but-
# held, recipe in experiment_metaball_hair.py) takes the next free
# id when integrated; hair_02..04 are retired, never shipped.
HAIR_STYLES = ["hair_00", "hair_01"]

# LIFT SCHEME. Each leg style raises the body by LEG_BODY_LIFT so its feet
# show. Rather than re-render the body/face once per lift, everything that
# belongs to the BODY GROUP (body, tuft, face, arms) is exported at lift 0
# and the app translates that whole group up by the chosen leg's lift. Only
# the LEG passes are rendered with the body actually raised, because their
# holdout matte depends on how much body is in front of them.

# The active launch pool. `m` is the approved per-body limb scale where one
# was set by hand; None derives it from the body's MEASURED height (RC3,
# 2026-09-13 — see derived_m; before that, every None silently used 0.85).
BODIES = {
    "round": ("build_round_aurie", 0.85),
    "tall": ("build_tall_aurie", 1.00),
    "small": ("build_small_aurie", None),
    "egg": ("build_egg_aurie", None),
    "pear": ("build_pear_aurie", None),
    "dumpling": ("build_dumpling_aurie", None),
    "teardrop": ("build_teardrop_aurie", None),
    "beanbag": ("build_beanbag_aurie", None),
    "oval": ("build_oval_aurie", None),
    "heart": ("build_heart_aurie", None),
}

# Faces the app needs. The ten base expressions plus only those reaction
# faces with unique artwork — reactions that borrow a base expression
# (bounce->happy, startled->surprised, curious look->curious, hop->
# delighted) deliberately export nothing extra.
BASE_FACES = list(FX.ORDER)
REACTION_FACES = ["dizzy", "yawn", "calm"]
# Delighted's eyes are already closed arcs, so a blink would be meaningless.
NO_BLINK = {"delighted"}


# RC3 (2026-09-13): body-aware default part scale. The one datum is
# Round's own measured height — the body every approved limb sculpt was
# authored against at m=0.85. HEIGHT is the measure that reproduces the
# only other hand-approved value (Tall was tuned to 1.00; height
# predicts 1.03, width predicts 0.72), so bodies without an approved
# override scale their parts by their real stature.
ROUND_REF_HEIGHT = 1.9254


def derived_m(meas):
    return round(min(1.15, max(0.65,
                               0.85 * meas["height"] / ROUND_REF_HEIGHT)), 3)


def srgb_to_linear(hexstr):
    def chan(v):
        v /= 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hexstr[i:i + 2], 16) for i in (0, 2, 4))
    return (chan(r), chan(g), chan(b), 1.0)


def build_body(name):
    """Build the body and return everything the passes need, for either
    script flavour (module constants vs the shared CFG pipeline)."""
    modname, fixed_m = BODIES[name]
    mod = importlib.import_module(modname)
    if hasattr(mod, "CFG"):
        c = common.resolve(mod.CFG)
        a = common.anchors(c)
        scene, cols = common.build(mod.CFG)
        R = common.R
        centre = Vector((0.0, 0.0, c["lift"] * R))

        def surf(x, z):
            return common.body_surface_y(c, x, z)
        pos = dict(eye_x=a["eye_x"], eye_z=a["eye_z"], mouth_z=a["mouth_z"],
                   cheek_x=a["cheek_x"], cheek_z=a["cheek_z"],
                   cheek_rx=c["cheek_rx"], cheek_rz=c["cheek_rz"],
                   face_x=common.axis_x(c, a["eye_z"]) + c["face_dx"],
                   mouth_x=common.axis_x(c, a["mouth_z"]) + c["face_dx"])
        arm = dict(x=a["arm_x"], y=c["arm_y"], z=a["arm_z"])
        foot = dict(x=a["foot_x"], y=c["foot_y"],
                    cx=c.get("foot_cx") or 0.0)
    else:
        scene, cols = mod.build(os.path.join(HERE, "..", "Source"))
        R = getattr(mod, "R", 1.0)
        centre = Vector((0.0, 0.0, mod.BODY_LIFT * R))

        def surf(x, z):
            return mod.body_surface_y(x, z)
        pos = dict(eye_x=mod.EYE_X, eye_z=mod.EYE_Z, mouth_z=mod.MOUTH_Z,
                   cheek_x=mod.CHEEK_X, cheek_z=mod.CHEEK_Z,
                   cheek_rx=mod.CHEEK_RX, cheek_rz=mod.CHEEK_RZ,
                   face_x=0.0, mouth_x=0.0)
        arm = dict(x=mod.ARM_X, y=mod.ARM_Y, z=mod.ARM_Z)
        foot = dict(x=mod.FOOT_X, y=mod.FOOT_Y, cx=0.0)
    return mod, scene, cols, R, centre, surf, pos, arm, foot, fixed_m




def measure_body(cols):
    """Silhouette measurements taken from the real body mesh.

    Everything the accessory system needs — where the crown is, how wide
    the lower flank runs, where the back sits — read off the geometry that
    was actually built. Parameters would have meant two code paths and ten
    hand-tuned guesses.
    """
    # Object matrices are computed lazily. Reading matrix_world straight
    # after a build returns the IDENTITY, which silently measured the body
    # in local space and dropped the tail a whole unit below the creature.
    bpy.context.view_layer.update()
    pts = []
    for ob in cols["BODY"].objects:
        if ob.type != "MESH":
            continue
        mw = ob.matrix_world
        pts += [mw @ v.co for v in ob.data.vertices]
    if not pts:
        raise RuntimeError("no body geometry to measure")
    top = max(p.z for p in pts)
    bottom = min(p.z for p in pts)
    height = top - bottom

    def flank_at(z, band=0.06):
        near = [abs(p.x) for p in pts if abs(p.z - z) <= band * height]
        return max(near) if near else 0.0

    def axis_at(z, band=0.06):
        near = [p.x for p in pts if abs(p.z - z) <= band * height]
        return (min(near) + max(near)) / 2.0 if near else 0.0

    # High enough that the tail leaves the body through its visible SIDE
    # rather than under the bottom curve, where the holdout would clip it
    # into a floating comma.
    # Measured against the arm layer: the hands hang across the mid-lower
    # flank, and a tail rooted any higher than this loses 15-30% of itself
    # behind them. At 0.14 the tail sits in the clear band between the hand
    # and the feet on all ten bodies.
    # Raised onto the lower back rather than down by the feet. Measured
    # against the arm layer: below this the hands cover a third of it.
    tail_z = bottom + 0.34 * height

    def crown_at(x, band=0.045):
        """The LOCAL crown height at lateral offset x — the surface a hair
        root must sit on. Sampling the real mesh is what lets one style
        definition hug a flat beanbag, a pointed teardrop and the dip
        between heart's lobes without per-body hand tuning."""
        near = [p.z for p in pts if abs(p.x - x) <= band * height]
        return max(near) if near else top

    fl = flank_at(tail_z)

    # RC3 (2026-09-13): the AUTHORITATIVE per-body measurement set. Every
    # part decision (scale, shoulders, hips, crown fit) reads THESE
    # numbers, taken from the mesh that was actually built — never from
    # constants duplicated in the limb/hair scripts. The shoulder/hip
    # rules are the family-standard ones aurie_body_common.anchors()
    # applies analytically to CFG bodies (arm_z = bottom + 0.36*height,
    # embed 0.09; hip = 0.75 * low flank clamped to [0.28, 0.50]), so a
    # standalone builder and a CFG builder measure identically.
    xs = [p.x for p in pts]
    width = max(xs) - min(xs)
    shoulder_z = bottom + 0.36 * height
    shoulder_x = flank_at(shoulder_z) - 0.09
    hip_x = min(0.50, max(0.28, 0.75 * flank_at(0.10)))

    return dict(x=round(fl * 0.88, 4), y=0.30, z=round(tail_z, 4),
                height=round(height, 4), flank_of=flank_at,
                flank=round(fl, 4), top=round(top, 4),
                bottom=round(bottom, 4),
                head_x=round(axis_at(top - 0.02 * height), 4),
                mid_flank=round(flank_at(bottom + 0.56 * height), 4),
                # usable crown half-width, for the crown-adaptive hair
                halfw=round(flank_at(top - 0.10 * height), 4),
                z_at=crown_at,
                # RC3 additions
                width=round(width, 4),
                halfw_body=round(width / 2.0, 4),
                center_z=round(bottom + height / 2.0, 4),
                shoulder_z=round(shoulder_z, 4),
                shoulder_x=round(shoulder_x, 4),
                hip_x=round(hip_x, 4))


def write_manifest(out, name, m, scene, tail_nub, pos_tail, extra=None):
    """The manifest carries ANCHORS as well as art.

    Accessories attach at points the app cannot derive from a PNG, and the
    three slots differ per silhouette, so each anchor is measured off the
    built geometry here and shipped in scene units next to the `ortho` that
    converts them to points.
    """
    path = os.path.join(out, f"{name}_manifest.json")
    meta = {}
    if os.path.exists(path):
        with open(path) as fh:
            meta = json.load(fh)
    meta.update({
        "body": name, "limb_scale": m,
        "ortho": scene.camera.data.ortho_scale,
        "anchors": {
            # where a tail charm hangs from — the nub at the tail tip
            # (kept from the previous manifest when the tail pass was
            # skipped in a selective re-export)
            "tail": ([round(v, 4) for v in tail_nub] if tail_nub
                     else meta.get("anchors", {}).get("tail", [0, 0, 0])),
            # crown of the body, for head accessories
            "head": [round(pos_tail.get("head_x", 0.0), 4), 0.0,
                     round(pos_tail["top"], 4)],
            # behind and above centre, for back accessories
            "back": [round(-pos_tail["mid_flank"] * 0.34, 4), 0.0,
                     round(pos_tail["bottom"]
                           + 0.56 * (pos_tail["top"] - pos_tail["bottom"]), 4)],
        },
        "bodyTop": round(pos_tail["top"], 4),
        "bodyBottom": round(pos_tail["bottom"], 4),
        "bodyFlank": round(pos_tail["flank"], 4),
    })
    meta.update(extra or {})
    with open(path, "w") as fh:
        json.dump(meta, fh, indent=2)
    return meta


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--body", required=True, choices=sorted(BODIES))
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--faces", default="all")
    ap.add_argument("--skip-parts", action="store_true")
    ap.add_argument("--tail-only", action="store_true",
                    help="render just the tail pass and refresh the manifest")
    ap.add_argument("--samples", type=int, default=128)
    ap.add_argument("--anim-safe-arms", action="store_true",
                    help="render arms without the body holdout (keeps the "
                         "shoulder root), so the app can draw them behind the "
                         "body and rotate about the joint without a gap")
    ap.add_argument("--anim-safe-legs", action="store_true",
                    help="same rule for legs: rendered alone with the hip "
                         "root kept, so splits/kicks rotate about a hip "
                         "joint without detaching")
    ap.add_argument("--skip-tail", action="store_true")
    ap.add_argument("--skip-faces", action="store_true")
    ap.add_argument("--skip-body", action="store_true",
                    help="skip the body/tuft passes (selective limb/hair "
                         "re-exports on top of an existing export dir)")
    ap.add_argument("--arm-styles", default="all",
                    help="CSV of arm styles to render, 'all' or 'none'")
    ap.add_argument("--leg-styles", default="all",
                    help="CSV of leg styles to render, 'all' or 'none'")
    ap.add_argument("--hair-styles", default="all",
                    help="CSV of hair styles to render, 'all' or 'none'")
    ap.add_argument("--orientation", default="front",
                    choices=["front", "back"],
                    help="back = the 180-degree TURNTABLE: the creature "
                         "rotates about its vertical axis under the "
                         "UNTOUCHED camera/lights (approved on the Round "
                         "PoC 2026-09-14) so front/back stay registered "
                         "and lit as the same character turned around. "
                         "Layer files gain a _back suffix; run with "
                         "--skip-tail --skip-faces (face layers are "
                         "front-only by design).")
    args = ap.parse_args(argv)

    def pick(flag, full):
        if flag == "all":
            return list(full)
        if flag == "none":
            return []
        return [s for s in flag.split(",") if s]

    def cap_roots(col):
        """Close each limb's open ROOT mouth (2026-09-17 black-wedge fix).

        The builders leave the root end OPEN — it plugs into the body,
        so a cap was never needed for the assembled look. But the limb
        LAYER renders the limb alone, and an open mouth shows the
        mesh's unlit interior: a solid BLACK region baked into every
        limb sprite, hidden at rest behind the body and exposed the
        moment a gesture rotates the limb (dance arm raises, splits,
        kicks). Filling the boundary loop caps the mouth with the same
        body material, so the root renders as lit surface. Silhouette
        and bbox are unchanged — the cap sits inside the mouth ring.
        """
        import bmesh
        for ob in col.objects:
            if ob.type != "MESH":
                continue
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            if any(e.is_boundary for e in bm.edges):
                bmesh.ops.holes_fill(bm, edges=bm.edges[:], sides=0)
                bm.normal_update()
            bm.to_mesh(ob.data)
            bm.free()

    arm_run = pick(args.arm_styles, ARM_STYLES)
    leg_run = pick(args.leg_styles, LEG_STYLES)
    hair_run = pick(args.hair_styles, HAIR_STYLES)

    name = args.body
    out = os.path.abspath(args.outdir)
    os.makedirs(out, exist_ok=True)
    (mod, scene, cols, R, centre, surf, pos, arm, foot,
     fixed_m) = build_body(name)
    # Half the launch bodies predate the shared config, and all ten have
    # different silhouettes, so anchors are MEASURED off the built mesh
    # rather than derived from parameters some bodies do not have.
    if "TAIL" not in cols:
        col = bpy.data.collections.new("TAIL")
        scene.collection.children.link(col)
        cols["TAIL"] = col
    pos_tail = measure_body(cols)
    # Orientation: parent every creature object to a pivot on the body
    # axis and rotate the PIVOT — camera, lights, floor and framing are
    # never touched. Objects created later (limbs, hair) call
    # orient_new() so they join the same turn.
    sfx = "_back" if args.orientation == "back" else ""
    turn = bpy.data.objects.new("TurnPivot", None)
    scene.collection.objects.link(turn)
    if args.orientation == "back":
        turn.rotation_euler = (0.0, 0.0, math.pi)

    def orient_new(objs):
        # BODY-LOCAL ATTACHMENT INVARIANT (2026-09-14 bug fix): the
        # creature is AUTHORED at identity orientation (world ==
        # body-local: front -y, right +x), so every creature object
        # parents to the turntable with matrix_parent_inverse =
        # IDENTITY — never the pivot's current inverse. Reading
        # turn.matrix_world here is the bug that reversed hair_01:
        # Blender computes matrices LAZILY, so parts parented at
        # setup saw a stale identity (and turned) while parts created
        # mid-flow saw the real rotation (keep-transform: they did
        # NOT turn). With the identity inverse, child_world =
        # R(orientation) @ authored for every part regardless of when
        # it is created — hair, limbs and future charms/tails all
        # turn WITH the body.
        from mathutils import Matrix
        for ob in objs:
            if ob.parent is None:
                ob.parent = turn
                ob.matrix_parent_inverse = Matrix.Identity(4)
    for cname in ("BODY", "TUFT", "FACE", "TAIL"):
        if cname in cols:
            orient_new(cols[cname].objects)
    bpy.context.view_layer.update()
    cols["STAGE"].hide_render = True
    scene.cycles.samples = args.samples

    body_mat = bpy.data.materials["AurieBody"]
    bsdf = next(n for n in body_mat.node_tree.nodes
                if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = srgb_to_linear(NEUTRAL)

    limbs = cols["LIMBS"]

    def clear_limbs():
        for ob in list(limbs.objects):
            bpy.data.objects.remove(ob, do_unlink=True)

    def shift_body(dz):
        for cname in ("BODY", "TUFT", "FACE"):
            for ob in cols[cname].objects:
                ob.location.z += dz

    # RC3: standalone builders (round/tall) hardcoded their shoulder
    # anchors; both now come from the measured mesh through the same
    # family-standard rule the CFG bodies apply analytically (Round's
    # measured shoulder lands within 1% of its approved hand-tuned one).
    # Foot stances are NOT derived: every body already ships an approved
    # per-body stance, and the body's own depth constant (arm y) stays.
    if not hasattr(mod, "CFG"):
        arm = dict(x=pos_tail["shoulder_x"], y=arm["y"],
                   z=pos_tail["shoulder_z"])

    m = fixed_m or derived_m(pos_tail)
    print(f"AURIE SCALE {name}: m={m} (fixed={fixed_m}) "
          f"h={pos_tail['height']} w={pos_tail['width']}")

    def conform(gx, gz, eps):
        p = Vector((gx, surf(gx, gz), gz))
        return p + (p - centre).normalized() * (eps * R)

    fpos = dict(pos)
    mats = {"eye": bpy.data.materials["AurieEye"],
            "catch": bpy.data.materials["AurieCatchlight"],
            "cheek": bpy.data.materials["AurieCheek"],
            "mouth": bpy.data.materials["AurieMouth"],
            "sheen": bpy.data.materials.get("AurieEyeSheen")}
    cam = scene.camera
    cam.data.ortho_scale *= 1.08

    def render(path):
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("AURIE OK:", os.path.basename(path))

    def render_limb(path):
        """Limb render with the ROOT DE-BLACKED (2026-09-17).

        The body/tuft stay in the scene casting shadows so the limb's
        VISIBLE surface keeps its calibrated lighting (RC1 parity —
        rendered alone, limbs came out 13-29% too bright). But the
        buried root sits INSIDE the body volume where that shadow is
        total, baking a solid-black zone into every sprite — invisible
        at rest, exposed as black wedges the moment a gesture rotates
        the limb (dance raises, splits, kicks). Render twice: the
        normal shadowed pass, plus a pass with body/tuft shadows off;
        only pixels the full occlusion drove to near-black are replaced
        from the unshadowed pass, so visible-surface lighting is
        untouched to the last pixel and the root becomes plausible lit
        limb surface. Deterministic, style- and body-agnostic.
        """
        import numpy as np
        render(path)
        shadowers = [ob for cname in ("BODY", "TUFT")
                     for ob in cols[cname].objects if ob.type == "MESH"]
        for ob in shadowers:
            ob.visible_shadow = False
        unshadowed = path + ".unshadowed.png"
        render(unshadowed)
        for ob in shadowers:
            ob.visible_shadow = True
        ia = bpy.data.images.load(path)
        ib = bpy.data.images.load(unshadowed)
        a = np.array(ia.pixels[:], dtype=np.float32).reshape(-1, 4)
        b = np.array(ib.pixels[:], dtype=np.float32).reshape(-1, 4)
        dark = (a[:, :3].max(axis=1) < 55 / 255) & (a[:, 3] > 40 / 255)
        a[dark] = b[dark]
        ia.pixels = a.ravel().tolist()
        ia.filepath_raw = path
        ia.file_format = "PNG"
        ia.save()
        bpy.data.images.remove(ia)
        bpy.data.images.remove(ib)
        os.remove(unshadowed)

    def only(names):
        for cname, col in cols.items():
            if cname != "RIG":
                col.hide_render = cname not in names

    def show(col, predicate):
        for ob in col.objects:
            ob.hide_render = not predicate(ob.name)

    def holdout(cnames, on):
        for cname in cnames:
            for ob in cols[cname].objects:
                ob.is_holdout = on

    def camera_visible(cnames, on):
        # Cycles per-ray visibility: with visible_camera off the object
        # stays a FULL light participant (shadows, occlusion, GI bounce)
        # but camera rays pass straight through it — unlike a holdout,
        # which mattes away everything behind it (killing the buried limb
        # roots the anim-safe sprites need).
        for cname in cnames:
            for ob in cols[cname].objects:
                ob.visible_camera = on

    # ---- tail ---------------------------------------------------------
    # Rendered with BODY and TUFT as holdouts, exactly like the limbs: the
    # tail root is embedded in the body, so without the holdout no 2D
    # stacking order can be right.
    tail_nub = None
    if not args.skip_tail:
        holdout(["BODY", "TUFT"], True)
        only({"TAIL", "BODY", "TUFT"})
        for ob in list(cols["TAIL"].objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        # Clearance scales with the body's own flank so a wide silhouette
        # gets a proportionally wider sweep instead of a buried stub.
        tail_nub = L.tail(cols["TAIL"], body_mat, 1, pos_tail["z"],
                          pos_tail["height"], pos_tail["flank_of"], m,
                          clear=0.42 * pos_tail["flank"])
        orient_new(cols["TAIL"].objects)
        render(f"{out}/{name}_tail.png")
        holdout(["BODY", "TUFT"], False)
        if args.tail_only:
            write_manifest(out, name, m, scene, tail_nub, pos_tail)
            print(f"AURIE TAIL DONE {name}")
            return

    if not args.skip_parts:
        if not args.skip_body:
            only({"BODY"})
            render(f"{out}/{name}_body{sfx}.png")
            holdout(["BODY"], True)
            only({"TUFT", "BODY"})
            render(f"{out}/{name}_tuft{sfx}.png")
            holdout(["BODY"], False)

        def is_side(n, left):
            # "Arm-1" also ends with "1"; a plain endswith("1") silently
            # puts BOTH limbs in the right-side pass.
            return n.endswith("-1") if left else (n.endswith("1")
                                                  and not n.endswith("-1"))

        # ANIMATION-SAFE ARMS. The default holdout crops each arm exactly to
        # the body silhouette, so it has no root behind the body — rotating
        # it opens a gap at the shoulder. With --anim-safe-arms the sprite
        # keeps the mitten root that normally hides behind the body; the app
        # draws the arm BEHIND the body and rotates it about the shoulder.
        # RC1 (2026-09-13): the root is kept by making body+tuft invisible
        # to CAMERA RAYS ONLY (visible_camera=False) instead of removing
        # them from the scene — they still shadow, occlude and bounce light
        # onto the arm, so the limb is lit exactly like the ground-truth
        # composite. (Rendered alone, arms came out 8-11% too bright and
        # read as a different material — see aurie-review-evidence/
        # diagnosis/DIAGNOSIS.md RC1.)
        if not args.anim_safe_arms:
            holdout(["BODY", "TUFT"], True)
            only({"LIMBS", "BODY", "TUFT"})
        else:
            only({"LIMBS", "BODY", "TUFT"})
            camera_visible(["BODY", "TUFT"], False)
        for style in arm_run:
            clear_limbs()
            for side in (-1, 1):
                L.ARMS[style](limbs, body_mat, side, arm["x"], arm["y"],
                              arm["z"], m, surf=None)
            cap_roots(limbs)
            orient_new(limbs.objects)
            for tag, left in (("l", True), ("r", False)):
                show(limbs, lambda n, lf=left: is_side(n, lf))
                render_limb(f"{out}/{name}_{style}_{tag}{sfx}.png")
        if args.anim_safe_arms:
            camera_visible(["BODY", "TUFT"], True)
        # ANIMATION-SAFE LEGS mirror the arm rule: the sprite keeps the hip
        # root that normally hides behind the body, letting the app rotate
        # the leg about a hip joint (splits, kicks) without a gap at the
        # hip. RC1 (2026-09-13): body+tuft stay in the scene camera-
        # invisible so the legs receive the body's shadow and occlusion
        # (rendered alone they came out 13-29% too bright — DIAGNOSIS.md
        # RC1), and the body is RAISED by each style's lift on every path
        # so its shadow falls on the legs exactly where it does at runtime.
        if args.anim_safe_legs:
            only({"LIMBS", "BODY", "TUFT"})
            holdout(["BODY", "TUFT"], False)
            camera_visible(["BODY", "TUFT"], False)
        else:
            holdout(["BODY", "TUFT"], True)
            only({"LIMBS", "BODY", "TUFT"})
        for style in leg_run:
            clear_limbs()
            # RC3: the per-style lifts were calibrated on Round at
            # m=0.85, and the foot geometry scales with this body's m —
            # so the lift scales with it too, or a big-footed body sinks
            # (and a small-footed one floats) relative to its own feet.
            lift = L.LEG_BODY_LIFT[style] * (m / 0.85)
            shift_body(lift)              # body at its true in-app height
            kw = dict(fcx=foot["cx"])
            if style == "leg_02":
                # Chibi's wide splay was tuned on Round (stance 1.62);
                # the measured clamp keeps the feet inside THIS body's
                # flank. Round keeps exactly 1.62 by construction.
                kw["stance"] = round(
                    min(1.62, 0.62 * pos_tail["halfw_body"] / foot["x"]), 3)
            for side in (-1, 1):
                L.LEGS[style](limbs, body_mat, side, foot["x"], foot["y"], m,
                              **kw)
            cap_roots(limbs)
            orient_new(limbs.objects)
            for tag, left in (("l", True), ("r", False)):
                show(limbs, lambda n, lf=left: is_side(n, lf))
                render_limb(f"{out}/{name}_{style}_{tag}{sfx}.png")
            shift_body(-lift)
        if args.anim_safe_legs:
            camera_visible(["BODY", "TUFT"], True)
        clear_limbs()

        # ---- hair: crown alternatives to the baked tuft ----------------
        # Rendered with the BODY as holdout (tuft hidden entirely — the app
        # shows either the tuft or one hair layer, never both), at lift 0
        # like every body-group layer.
        if hair_run:
            if "HAIR" not in cols:
                hcol = bpy.data.collections.new("HAIR")
                scene.collection.children.link(hcol)
                cols["HAIR"] = hcol
            holdout(["BODY"], True)
            only({"HAIR", "BODY"})
            for style in hair_run:
                for ob in list(cols["HAIR"].objects):
                    bpy.data.objects.remove(ob, do_unlink=True)
                HAIR.HAIR[style](cols["HAIR"], body_mat, pos_tail, m)
                orient_new(cols["HAIR"].objects)
                render(f"{out}/{name}_{style}{sfx}.png")
            for ob in list(cols["HAIR"].objects):
                bpy.data.objects.remove(ob, do_unlink=True)
            holdout(["BODY"], False)
        holdout(["BODY", "TUFT"], False)

    faces = ([] if args.skip_faces
             else BASE_FACES + REACTION_FACES if args.faces == "all"
             else args.faces.split(","))
    face_col = cols["FACE"]
    only({"FACE"})
    # The dark eye oval + gloss are the FIXED eye; the catchlight sparkles are
    # exported as their OWN layer so the app can slide only the sparkles toward
    # a finger while the eye stays put (the user's "glints follow" gaze). At
    # rest, eyes + catch composite back to exactly the original eye. Arc/shut
    # eyes carry no sparkle, so their catch layer renders empty and the
    # installer skips it.
    def is_eyes(n):
        return n.startswith("Eye")           # Eye + EyeSheen, NOT Catch
    groups = (("cheeks", lambda n: n.startswith("Cheek")),
              ("mouth", lambda n: n.startswith("Mouth")),
              ("eyes", is_eyes),
              ("catch", lambda n: n.startswith("Catch")))
    for expr in faces:
        FX.build(cols, mats, conform, R, fpos, expr)
        for gname, pred in groups:
            show(face_col, pred)
            render(f"{out}/{name}_face_{expr}_{gname}.png")
        if expr not in NO_BLINK:
            FX.build(cols, mats, conform, R, fpos, expr, blink=1.0)
            show(face_col, is_eyes)          # eyes/lash only; closed = no sparkle
            render(f"{out}/{name}_face_{expr}_blink_eyes.png")
        show(face_col, lambda n: True)

    # full-character reference for A/B checks
    if not args.skip_faces:
        FX.build(cols, mats, conform, R, fpos, "happy")
        only({"BODY", "TUFT", "LIMBS", "FACE"})
        render(f"{out}/{name}_reference_neutral.png")

    # The canvas spans `ortho` SCENE UNITS. Without this the app cannot
    # convert a scene-unit leg lift into points; assuming a fixed span put
    # the body 1.8x too high above its feet.
    write_manifest(out, name, m, scene, tail_nub, pos_tail, extra={
        # RC3: lifts ship m-scaled, matching the m-scaled foot art above.
        "leg_lift": {k: round(L.LEG_BODY_LIFT[k] * m / 0.85, 4)
                     for k in LEG_STYLES},
        "arm_styles": ARM_STYLES, "leg_styles": LEG_STYLES,
        "hair_styles": HAIR_STYLES,
        "anim_safe_arms": bool(args.anim_safe_arms),
        "anim_safe_legs": bool(args.anim_safe_legs),
        "faces": faces, "no_blink": sorted(NO_BLINK)})
    shutil.rmtree(os.path.join(HERE, "__pycache__"), ignore_errors=True)
    print(f"AURIE EXPORT DONE {name} ({len(faces)} faces)")


if __name__ == "__main__":
    main()
