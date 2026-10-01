"""Rollout validation renders for the APPROVED hair_01 Soft Mohawk
(2026-09-14): one launch body per run, built through the AUTHORITATIVE
export path (export_app_layers.build_body + measure_body), tuft
swapped for hair_01, rendered front/side/back/top on the family
camera/lighting plus the production-canvas clip check.

    blender --background --factory-startup \
        --python experiment_hair01_rollout.py -- --body round \
        --outdir <renders>

Outputs: hair01_<body>_{front,side,back,top}.png
No app integration here — this is the per-body approval evidence,
the same gate the limb metaballs cleared.
"""

import argparse
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aurie_hair_styles as HAIR  # noqa: E402
import export_app_layers as EXP  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--body", required=True, choices=sorted(EXP.BODIES))
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--samples", type=int, default=64)
    args = ap.parse_args(argv)
    out = os.path.abspath(args.outdir)
    os.makedirs(out, exist_ok=True)

    (mod, scene, cols, R, centre, surf, pos, arm, foot,
     fixed_m) = EXP.build_body(args.body)
    meas = EXP.measure_body(cols)
    m = fixed_m or EXP.derived_m(meas)
    scene.cycles.samples = args.samples
    print("ROLLOUT %s: m=%.3f top=%.4f halfw=%.4f head_x=%.4f "
          "width=%.4f" % (args.body, m, meas["top"], meas["halfw"],
                          meas["head_x"], meas["width"]))

    # the app shows either the tuft or one hair layer, never both
    for ob in cols["TUFT"].objects:
        ob.hide_render = True

    hair_col = bpy.data.collections.new("HAIR")
    scene.collection.children.link(hair_col)
    HAIR.HAIR["hair_01"](hair_col, bpy.data.materials["AurieBody"],
                         meas, m)

    bpy.context.view_layer.update()
    hz = max((ob.matrix_world @ v.co).z
             for ob in hair_col.objects if ob.type == "MESH"
             for v in ob.data.vertices)
    lo = min((ob.matrix_world @ v.co).z
             for ob in hair_col.objects if ob.type == "MESH"
             for v in ob.data.vertices)
    cam = scene.camera
    base_ortho = cam.data.ortho_scale
    canvas_top = cam.location.z + 0.5 * base_ortho * 1.08
    print("CLIPCHECK %s hair_top=%.4f canvas_top=%.4f margin=%.4f "
          "hair_bottom=%.4f crown=%.4f" %
          (args.body, hz, canvas_top, canvas_top - hz, lo,
           meas["top"]))

    orbit = bpy.data.objects.new("CamOrbit", None)
    orbit.location = (0.0, 0.0, cam.location.z)
    cols["RIG"].objects.link(orbit)
    keep = cam.matrix_world.copy()
    cam.parent = orbit
    cam.matrix_world = keep
    cam.data.ortho_scale = base_ortho * 1.30   # headroom for the crest

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
    for vname, ang in (("front", 0.0), ("side", math.radians(90.0)),
                       ("back", math.radians(180.0))):
        orbit.rotation_euler = (0.0, 0.0, ang)
        render(f"{out}/hair01_{args.body}_{vname}.png")
    scene.camera = top_cam
    render(f"{out}/hair01_{args.body}_top.png")
    print(f"ROLLOUT DONE {args.body}")


if __name__ == "__main__":
    main()
