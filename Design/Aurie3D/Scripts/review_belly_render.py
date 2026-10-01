"""REVIEW TOOLING — belly evidence passes. NOT production source.

This renders the passes a belly/sticker review sheet is built from. It
ships nothing: the approved production rules live in `aurie_belly.py`
and `aurie_belly_stickers.py`, and the belly zone itself is generated
by `build_pattern_masks.py --zone belly`. This script only reproduces
the EVIDENCE.

Per yaw (0 front, 45 3/4-front, 135 3/4-back, 180 back) it writes:
    body_yawNNN.png             NEUTRAL body beauty pass
    parts_yawNNN.png            hair/face/limbs, body held out
    belly_yawNNN.png            the belly zone falloff
    pattern_<name>_yawNNN.png   pattern masks, same scene

All passes share the production camera, framing and turntable, so they
are pixel-registered with each other.

REGISTRATION NOTE (a real bug this rig hit): `build_pattern_masks.py`
renders the body UNLIFTED, while this rig raises it by the leg lift so
the limbs assemble. Compositing a mask from there put every marking
48 px low. That is why the pattern masks are re-rendered HERE, in the
lifted scene. Production is immune — `install_app_assets.py` crops the
body layer and every mask to the same body bbox.

    blender --background --factory-startup --python-exit-code 1 \
        --python review_belly_render.py -- --body round --outdir <dir>
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_pattern_masks as BPM  # noqa: E402
import export_app_layers as E  # noqa: E402

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--body", default="round")
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--samples", type=int, default=96)
    ap.add_argument("--yaws", default="0,45,135,180",
                    help="comma-separated turntable yaws to render")
    args = ap.parse_args(argv)
    out = os.path.abspath(args.outdir)

    os.makedirs(out, exist_ok=True)
    name = args.body

    (mod, scene, cols, R, centre, surf, pos, arm, foot,
     fixed_m) = E.build_body(name)
    cols["STAGE"].hide_render = True
    scene.cycles.samples = args.samples
    cam = scene.camera
    cam.data.ortho_scale *= 1.08          # production framing
    for cname, col in cols.items():
        if cname != "RIG":
            col.hide_render = cname != "BODY"

    # Rest limbs, so the proof can be judged against the REAL margins to
    # arms/legs/face rather than on a bare ball. Built exactly like the
    # production rig: clear the baked rest limbs first, then lift the
    # body group by the leg style's lift.
    import aurie_limb_styles as L  # noqa: E402
    meas = E.measure_body(cols)
    limbs = cols["LIMBS"]
    for ob in list(limbs.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    arm_p = arm if hasattr(mod, "CFG") else dict(
        x=meas["shoulder_x"], y=arm["y"], z=meas["shoulder_z"])
    m = fixed_m or E.derived_m(meas)
    for side in (-1, 1):
        L.ARMS["arm_00"](limbs, body_mat_dummy := bpy.data.materials["AurieBody"],
                         side, arm_p["x"], arm_p["y"], arm_p["z"], m, surf=None)
        L.LEGS["leg_00"](limbs, body_mat_dummy, side, foot["x"], foot["y"], m,
                         fcx=foot["cx"])
    lift = L.LEG_BODY_LIFT["leg_00"] * (m / 0.85)
    for cname in ("BODY", "TUFT", "FACE"):
        for ob in cols[cname].objects:
            ob.location.z += lift
    for ob in limbs.objects:
        if ob.name.startswith("Arm"):
            ob.location.z += lift

    bodies = [ob for ob in cols["BODY"].objects if ob.type == "MESH"]
    original = [list(ob.data.materials) for ob in bodies]

    # NEUTRAL, exactly as the layer exporter sets it.
    body_mat = bpy.data.materials["AurieBody"]
    bsdf = next(n for n in body_mat.node_tree.nodes
                if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = E.srgb_to_linear(E.NEUTRAL)

    # The approved turntable: rotate the BODY, never the camera/lights.
    turn = bpy.data.objects.new("TurnPivot", None)
    scene.collection.objects.link(turn)
    for cname in ("BODY", "TUFT", "FACE", "LIMBS"):
        for ob in cols[cname].objects:
            if ob.parent is None:
                ob.parent = turn
                ob.matrix_parent_inverse = Matrix.Identity(4)
    bpy.context.view_layer.update()

    def only(names):
        for cname, col in cols.items():
            if cname != "RIG":
                col.hide_render = cname not in names

    def holdout(cnames, on):
        for cname in cnames:
            for ob in cols[cname].objects:
                ob.is_holdout = on

    lights = [ob for c in cols.values() for ob in c.objects
              if ob.type == "LIGHT"]
    world = scene.world
    # PRE-LIFT measurement: `meas` was taken before the body group was
    # raised by the leg lift, and pos["mouth_z"] is likewise an unlifted
    # anchor. Re-measuring here would mix a lifted bbox with an
    # unlifted mouth and push the zone far too low. Production
    # (build_pattern_masks) never lifts, so it is unaffected.
    zp = BPM.belly_params(meas, pos)
    print("AURIE ZONE params", zp)
    zone_mat = BPM.mask_material("Zone_belly_proof",
                                 lambda nt, c: BPM.z_belly(nt, c, zp))

    for yaw in [int(v) for v in args.yaws.split(",") if v]:
        turn.rotation_euler = (0.0, 0.0, math.radians(yaw))
        bpy.context.view_layer.update()

        # --- beauty pass: BODY alone (the layer the belly applies to) ---
        for ob, mats in zip(bodies, original):
            ob.data.materials.clear()
            for m in mats:
                ob.data.materials.append(m)
        for lg in lights:
            lg.hide_render = False
        scene.world = world
        only({"BODY"})
        scene.render.filepath = f"{out}/body_yaw{yaw:03d}.png"
        bpy.ops.render.render(write_still=True)
        print("AURIE OK:", os.path.basename(scene.render.filepath))

        # --- parts pass: everything the app draws OVER the body, with
        # the body as a holdout so it carves them exactly as the real
        # layer stack does. Composited on top of the belly-lit body.
        only({"BODY", "TUFT", "FACE", "LIMBS"})
        holdout(["BODY"], True)
        scene.render.filepath = f"{out}/parts_yaw{yaw:03d}.png"
        bpy.ops.render.render(write_still=True)
        holdout(["BODY"], False)
        print("AURIE OK:", os.path.basename(scene.render.filepath))

        # --- belly mask pass (flat emission, unlit, BODY alone) ---
        only({"BODY"})
        for ob in bodies:
            ob.data.materials.clear()
            ob.data.materials.append(zone_mat)
        for lg in lights:
            lg.hide_render = True
        scene.world = None
        scene.render.filepath = f"{out}/belly_yaw{yaw:03d}.png"
        bpy.ops.render.render(write_still=True)
        print("AURIE OK:", os.path.basename(scene.render.filepath))

        # --- pattern masks, rendered in THIS SAME lifted scene ---
        # build_pattern_masks.py renders the body UNLIFTED, so a mask
        # taken from it sits ~48 px low against this rig's lifted body
        # and the markings read as shifted down. Production is immune
        # (the installer crops body and mask to the same body bbox);
        # this rig has to render its own to stay registered.
        for pat, seed in (("stripes", 0), ("spots", 0)):
            pmat = BPM.mask_material(
                f"Mask_{pat}_{seed}_proof",
                lambda nt, c, p=pat, s=seed: BPM.BUILDERS[p](nt, c, s))
            for ob in bodies:
                ob.data.materials.clear()
                ob.data.materials.append(pmat)
            scene.render.filepath = f"{out}/pattern_{pat}_yaw{yaw:03d}.png"
            bpy.ops.render.render(write_still=True)
            print("AURIE OK:", os.path.basename(scene.render.filepath))

    print(f"BELLY PROOF RENDERS DONE {name}")


if __name__ == "__main__":
    main()
