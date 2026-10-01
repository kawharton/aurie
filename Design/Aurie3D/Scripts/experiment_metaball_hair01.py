"""EXPERIMENT: hair_01 Soft Mohawk candidate renders on Round
(2026-09-14) — the approval-gate process that cleared hair_00: the
candidate is built by the REAL aurie_hair_styles builder on the crown
the REAL export_app_layers.measure_body measured, then rendered from
every angle the reference sheet shows. No app integration here.

    blender --background --factory-startup \
        --python experiment_metaball_hair01.py -- --outdir <renders>

Reference: Design/Hair/soft_mohawk.png; measured targets in
aurie-review-evidence/hair01_softmohawk/reference_manifest.json.

Outputs on identical camera/lighting:
    hair01_{front,side,back,top}.png      full character, tuft hidden
    hair01_prod.png                       front at the export canvas
                                          framing (ortho * 1.08) — the
                                          clip check for production
    hair01_iso_{front,side,top}.png       hair only, clean silhouette
Saves Source/softmohawk_hair01_mesh_experiment.blend (the v1
metaball evidence blend softmohawk_hair01_experiment.blend is
preserved untouched).
"""

import argparse
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aurie_hair_styles as HAIR  # noqa: E402
import aurie_limb_styles as L  # noqa: E402
import build_round_aurie as ROUND  # noqa: E402
import export_app_layers as EXP  # noqa: E402

M = 0.85
LIFT = 0.22              # leg_01's lift — complete grounded character


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--samples", type=int, default=96)
    ap.add_argument("--style", default="hair_01",
                    help="hair style id from aurie_hair_styles.HAIR")
    ap.add_argument("--views", default="all",
                    help="CSV of views to render: front,side,back,"
                         "top,prod,iso_front,iso_side,iso_top")
    args = ap.parse_args(argv)
    tag = args.style.replace("_", "")
    want = (None if args.views == "all"
            else {v.strip() for v in args.views.split(",")})

    def wanted(v):
        return want is None or v in want
    out = os.path.abspath(args.outdir)
    os.makedirs(out, exist_ok=True)

    scene, cols = ROUND.build(os.path.join(HERE, "..", "Source"))
    scene.cycles.samples = args.samples
    body_mat = bpy.data.materials["AurieBody"]
    for ob in list(cols["LIMBS"].objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for side in (-1, 1):
        L.LEGS["leg_01"](cols["LIMBS"], body_mat, side,
                         ROUND.FOOT_X, ROUND.FOOT_Y, M)
    for cname in ("BODY", "TUFT", "FACE"):
        for ob in cols[cname].objects:
            ob.location.z += LIFT

    # the app shows either the tuft or one hair layer, never both
    for ob in cols["TUFT"].objects:
        ob.hide_render = True

    meas = EXP.measure_body(cols)
    print("CROWN top=%.4f halfw=%.4f head_x=%.4f" %
          (meas["top"], meas["halfw"], meas["head_x"]))

    hair_col = bpy.data.collections.new("HAIR")
    scene.collection.children.link(hair_col)
    HAIR.HAIR[args.style](hair_col, body_mat, meas, M)

    # production-canvas clip check: the export canvas spans base ortho
    # * 1.08 centred on the build's cam_z. matrix_world is lazy —
    # without the update it reads IDENTITY and reports local coords.
    bpy.context.view_layer.update()
    hz = max((ob.matrix_world @ v.co).z
             for ob in hair_col.objects if ob.type == "MESH"
             for v in ob.data.vertices)
    cam = scene.camera
    base_ortho = cam.data.ortho_scale
    canvas_top = cam.location.z + 0.5 * base_ortho * 1.08
    print("CLIPCHECK hair_top=%.4f canvas_top=%.4f margin=%.4f" %
          (hz, canvas_top, canvas_top - hz))

    orbit = bpy.data.objects.new("CamOrbit", None)
    orbit.location = (0.0, 0.0, 0.95)
    cols["RIG"].objects.link(orbit)
    keep = cam.matrix_world.copy()
    cam.parent = orbit
    cam.matrix_world = keep
    cam.data.ortho_scale = base_ortho * 1.30   # headroom for the crest
    mw = cam.matrix_world.copy()
    mw.translation.z += 0.05
    cam.matrix_world = mw

    top_data = bpy.data.cameras.new("TopCam")
    top_data.type = "ORTHO"
    top_data.ortho_scale = base_ortho * 1.30
    top_data.clip_start, top_data.clip_end = 0.01, 100.0
    top_cam = bpy.data.objects.new("TopCam", top_data)
    top_cam.location = (0.0, 0.0, 9.0)
    top_cam.rotation_euler = (0.0, 0.0, 0.0)
    cols["RIG"].objects.link(top_cam)

    def render(path):
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("AURIE OK:", os.path.basename(path))

    scene.render.resolution_x = scene.render.resolution_y = 1024

    # full character: front / side (face pointing frame-left, like the
    # reference sheet) / back / top (front at frame-bottom)
    for vname, ang in (("front", 0.0), ("side", math.radians(90.0)),
                       ("back", math.radians(180.0))):
        if wanted(vname):
            orbit.rotation_euler = (0.0, 0.0, ang)
            render(f"{out}/{tag}_{vname}.png")
    if wanted("top"):
        scene.camera = top_cam
        render(f"{out}/{tag}_top.png")
        scene.camera = cam

    # production framing (export canvas is base ortho * 1.08)
    if wanted("prod"):
        orbit.rotation_euler = (0.0, 0.0, 0.0)
        cam.data.ortho_scale = base_ortho * 1.08
        render(f"{out}/{tag}_prod.png")
        cam.data.ortho_scale = base_ortho * 1.30

    # hair only — clean silhouettes
    for cname, col in cols.items():
        if cname != "RIG":
            col.hide_render = True
    for vname, ang in (("front", 0.0), ("side", math.radians(90.0))):
        if wanted("iso_" + vname):
            orbit.rotation_euler = (0.0, 0.0, ang)
            render(f"{out}/{tag}_iso_{vname}.png")
    if wanted("iso_top"):
        scene.camera = top_cam
        render(f"{out}/{tag}_iso_top.png")
        scene.camera = cam
    for cname, col in cols.items():
        col.hide_render = False
    for ob in cols["TUFT"].objects:
        ob.hide_render = True

    orbit.rotation_euler = (0.0, 0.0, 0.0)
    # _mesh: the v1 metaball evidence blend (softmohawk_hair01_
    # experiment.blend) is preserved, never overwritten
    blend = os.path.abspath(os.path.join(
        HERE, "..", "Source", (args.style + "_candidate_experiment.blend") if args.style != "hair_01" else "softmohawk_hair01_mesh_experiment.blend"))
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print("SAVED", blend)
    print("EXPERIMENT DONE")


if __name__ == "__main__":
    main()
