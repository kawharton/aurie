"""All-10 back-rollout validation pairs (2026-09-14).

    blender --background --factory-startup \
        --python experiment_back_validation.py -- --body round \
        --outdir <dir>

Per body, four assembled renders on the fixed production camera and
the approved turntable (face on front only, STAGE visible for the
ground line):
    val_<body>_default_{front,back}.png   arm_00/leg_00 + hair_00
    val_<body>_long_{front,back}.png      arm_02/leg_05 + hair_01
                                          (hair_00 where hair_01 is
                                          catalog-excluded: heart)
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
import export_app_layers as EXP  # noqa: E402

HAIR01_EXCLUDED = {"heart"}          # mirrors AurieLimbCatalog


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--body", required=True, choices=sorted(EXP.BODIES))
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--samples", type=int, default=64)
    args = ap.parse_args(argv)
    out = os.path.abspath(args.outdir)
    os.makedirs(out, exist_ok=True)
    name = args.body

    (mod, scene, cols, R, centre, surf, pos, arm, foot,
     fixed_m) = EXP.build_body(name)
    meas0 = EXP.measure_body(cols)
    m = fixed_m or EXP.derived_m(meas0)
    scene.cycles.samples = args.samples
    body_mat = bpy.data.materials["AurieBody"]
    if not hasattr(mod, "CFG"):
        arm = dict(x=meas0["shoulder_x"], y=arm["y"],
                   z=meas0["shoulder_z"])
    limbs = cols["LIMBS"]

    piv = bpy.data.objects.new("TurnPivot", None)
    scene.collection.objects.link(piv)

    def adopt(objs):
        # identity inverse — the body-local attachment invariant (see
        # export_app_layers.orient_new): adopting mid-run with the
        # pivot's current inverse froze late-created hair in world
        # space (the reversed-mohawk bug)
        from mathutils import Matrix
        for ob in objs:
            if ob.parent is None:
                ob.parent = piv
                ob.matrix_parent_inverse = Matrix.Identity(4)

    for cname in ("BODY", "TUFT", "FACE"):
        adopt(cols[cname].objects)

    def orient(back):
        piv.rotation_euler = (0.0, 0.0, math.pi if back else 0.0)
        bpy.context.view_layer.update()

    cam = scene.camera
    cam.data.ortho_scale *= 1.08
    scene.render.resolution_x = scene.render.resolution_y = 1024

    def render(path):
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("AURIE OK:", os.path.basename(path))

    group_dz = [0.0]          # current body-group lift (arms ride it)

    def set_rig(arm_style, leg_style, hair_style):
        # AUTHORING FRAME: measure + build at identity orientation —
        # a rotated pivot would flip measured asymmetries (head_x)
        orient(False)
        # tear down limbs + hair, rebuild at lift 0, then lift the
        # body group (incl. ARMS — the runtime contract) by the leg's
        # lift and grow the hair on the LIFTED crown
        for ob in list(limbs.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        for coll in list(scene.collection.children):
            if coll.name.startswith("VHAIR"):
                for ob in list(coll.objects):
                    bpy.data.objects.remove(ob, do_unlink=True)
                scene.collection.children.unlink(coll)
        dz = -group_dz[0]
        for cname in ("BODY", "TUFT", "FACE"):
            for ob in cols[cname].objects:
                ob.location.z += dz
        group_dz[0] = 0.0
        for side in (-1, 1):
            L.ARMS[arm_style](limbs, body_mat, side, arm["x"], arm["y"],
                              arm["z"], m, surf=None)
            kw = dict(fcx=foot["cx"])
            if leg_style == "leg_02":
                kw["stance"] = round(
                    min(1.62, 0.62 * meas0["halfw_body"] / foot["x"]), 3)
            L.LEGS[leg_style](limbs, body_mat, side, foot["x"],
                              foot["y"], m, **kw)
        lift = L.LEG_BODY_LIFT[leg_style] * (m / 0.85)
        for cname in ("BODY", "TUFT", "FACE"):
            for ob in cols[cname].objects:
                ob.location.z += lift
        for ob in limbs.objects:
            if ob.name.startswith("Arm"):
                ob.location.z += lift
        group_dz[0] = lift
        meas = EXP.measure_body(cols)
        hcol = bpy.data.collections.new("VHAIR")
        scene.collection.children.link(hcol)
        HAIR.HAIR[hair_style](hcol, body_mat, meas, m)
        adopt(limbs.objects)
        adopt(hcol.objects)
        for ob in cols["TUFT"].objects:
            ob.hide_render = True
        return hcol

    def show(hcol, back):
        for cname, col in cols.items():
            if cname != "RIG":
                col.hide_render = cname not in ("BODY", "LIMBS", "STAGE")
        cols["FACE"].hide_render = back
        hcol.hide_render = False

    long_hair = "hair_00" if name in HAIR01_EXCLUDED else "hair_01"
    for tag, cfg in (("default", ("arm_00", "leg_00", "hair_00")),
                     ("long", ("arm_02", "leg_05", long_hair))):
        hcol = set_rig(*cfg)
        for back in (False, True):
            orient(back)
            show(hcol, back)
            render(f"{out}/val_{name}_{tag}_"
                   f"{'back' if back else 'front'}.png")
    print(f"BACKVAL DONE {name}")


if __name__ == "__main__":
    main()
