"""ROUND-ONLY PROOF: Aurie back orientation (2026-09-14).

    blender --background --factory-startup \
        --python experiment_back_view_round.py -- --outdir <dir>

TURNTABLE RIG: the CREATURE rotates 180 deg about its vertical body
axis under the FIXED production camera and light rig (a pivot empty
at the origin parents body/tuft/face/limbs/hair). Camera, projection,
framing, ground line, floor and lights are untouched, so front and
back are pixel-registered on the same canvas and lit like the same
studio subject turned around — the back is genuinely rendered from
the 3D geometry, never a flipped sprite.

Outputs (family-blue material for review readability; the production
rollout re-renders with the NEUTRAL export albedo):
  assembled rows, front|back pairs, grounded on leg_00/arm_00:
    row_plain_{front,back}.png     tuft crown, face only on front
    row_hair00_{front,back}.png
    row_hair01_{front,back}.png
    row_limbs_{front,back}.png     arm_02 + leg_05 (longest limbs)
  layer renders at production framing/lift conventions (lift 0 for
  the body group, body raised for leg passes, holdouts as in
  export_app_layers; face layers deliberately NOT rendered for back):
    round_body_front.png, round_body_back.png
    round_hair_00_back.png, round_hair_01_back.png
    round_arm_00_l_back.png, round_arm_00_r_back.png
    round_leg_00_l_back.png, round_leg_00_r_back.png
  diagnostics:
    diag_back_top.png              hair_01 back, top camera

Naming convention (documented decision): the orientation key is a
SUFFIX on the layer name — round_body_back -> asset
aurie_round_body_back; existing suffix-less names stay implicit
FRONT. Future: _left, _right, _3q_left, _3q_right.
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


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--samples", type=int, default=96)
    args = ap.parse_args(argv)
    out = os.path.abspath(args.outdir)
    os.makedirs(out, exist_ok=True)

    (mod, scene, cols, R, centre, surf, pos, arm, foot,
     fixed_m) = EXP.build_body("round")
    meas0 = EXP.measure_body(cols)
    m = fixed_m or EXP.derived_m(meas0)
    scene.cycles.samples = args.samples
    body_mat = bpy.data.materials["AurieBody"]
    arm = dict(x=meas0["shoulder_x"], y=arm["y"], z=meas0["shoulder_z"])

    limbs = cols["LIMBS"]
    for ob in list(limbs.objects):
        bpy.data.objects.remove(ob, do_unlink=True)

    def add_limbs(arm_style, leg_style):
        for ob in list(limbs.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        for side in (-1, 1):
            L.ARMS[arm_style](limbs, body_mat, side, arm["x"], arm["y"],
                              arm["z"], m, surf=None)
            kw = dict(fcx=foot["cx"])
            L.LEGS[leg_style](limbs, body_mat, side, foot["x"],
                              foot["y"], m, **kw)

    def shift(cnames, dz):
        for cname in cnames:
            for ob in cols[cname].objects:
                ob.location.z += dz

    def shift_arms(dz):
        # ARMS RIDE THE BODY GROUP: the export renders them at lift 0
        # and the app raises body+tuft+face+ARMS together by the leg
        # lift — an assembled preview must do the same or long arms
        # hang low and drag the floor.
        for ob in limbs.objects:
            if ob.name.startswith("Arm"):
                ob.location.z += dz

    add_limbs("arm_00", "leg_00")
    lift = L.LEG_BODY_LIFT["leg_00"] * (m / 0.85)
    shift(("BODY", "TUFT", "FACE"), lift)
    shift_arms(lift)

    # hair on the LIFTED crown (runtime configuration)
    meas = EXP.measure_body(cols)
    h0 = bpy.data.collections.new("H0")
    h1 = bpy.data.collections.new("H1")
    scene.collection.children.link(h0)
    scene.collection.children.link(h1)
    HAIR.HAIR["hair_00"](h0, body_mat, meas, m)
    HAIR.HAIR["hair_01"](h1, body_mat, meas, m)

    # ---- the turntable pivot ------------------------------------------
    piv = bpy.data.objects.new("TurnPivot", None)
    scene.collection.objects.link(piv)
    creature_cols = [cols["BODY"], cols["TUFT"], cols["FACE"], limbs,
                     h0, h1]
    from mathutils import Matrix
    for col in creature_cols:
        for ob in col.objects:
            ob.parent = piv
            ob.matrix_parent_inverse = Matrix.Identity(4)

    def orient(back):
        piv.rotation_euler = (0.0, 0.0, math.pi if back else 0.0)
        bpy.context.view_layer.update()

    cam = scene.camera
    cam.data.ortho_scale *= 1.08          # the production canvas

    def only(colset):
        for cname, col in cols.items():
            if cname != "RIG":
                col.hide_render = col not in colset and cname != "STAGE"
        cols["STAGE"].hide_render = cols["STAGE"] not in colset
        h0.hide_render = h0 not in colset
        h1.hide_render = h1 not in colset

    def render(path):
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("AURIE OK:", os.path.basename(path))

    scene.render.resolution_x = scene.render.resolution_y = 1024
    B, T, F, S = cols["BODY"], cols["TUFT"], cols["FACE"], cols["STAGE"]

    # ---- assembled comparison rows ------------------------------------
    rows = (("row_plain", {B, T, limbs, S}, None),
            ("row_hair00", {B, limbs, S, h0}, None),
            ("row_hair01", {B, limbs, S, h1}, None),
            ("row_limbs", {B, T, limbs, S}, ("arm_02", "leg_05")))
    for tag, visible, limbcfg in rows:
        if limbcfg:
            shift(("BODY", "TUFT", "FACE"), -lift)
            for col in (h0, h1):
                for ob in col.objects:
                    ob.location.z -= lift
            add_limbs(*limbcfg)
            lift2 = L.LEG_BODY_LIFT[limbcfg[1]] * (m / 0.85)
            shift(("BODY", "TUFT", "FACE"), lift2)
            shift_arms(lift2)
            for col in (h0, h1):
                for ob in col.objects:
                    ob.location.z += lift2
            for ob in limbs.objects:
                ob.parent = piv
                ob.matrix_parent_inverse = Matrix.Identity(4)
        for back in (False, True):
            orient(back)
            vis = set(visible)
            if not back:
                vis.add(F)
            only(vis)
            render(f"{out}/{tag}_{'back' if back else 'front'}.png")

    # restore default limbs/lift for the layer passes
    shift(("BODY", "TUFT", "FACE"), -(L.LEG_BODY_LIFT["leg_05"]
                                      * (m / 0.85)))
    for col in (h0, h1):
        for ob in col.objects:
            ob.location.z -= L.LEG_BODY_LIFT["leg_05"] * (m / 0.85)
    add_limbs("arm_00", "leg_00")
    for ob in limbs.objects:
        ob.parent = piv
        ob.matrix_parent_inverse = Matrix.Identity(4)

    # ---- layer renders (production conventions, lift 0) ---------------
    def holdout(colset, on):
        for col in colset:
            for ob in col.objects:
                ob.is_holdout = on

    def show_limb(pred):
        for ob in limbs.objects:
            ob.hide_render = not pred(ob.name)

    def is_side(n, left):
        return n.endswith("-1") if left else (n.endswith("1")
                                              and not n.endswith("-1"))

    # body layer, both orientations
    for back in (False, True):
        orient(back)
        only({B})
        render(f"{out}/round_body_{'back' if back else 'front'}.png")

    orient(True)
    # hair layers (body holdout, tuft hidden)
    holdout([B], True)
    for tag, col in (("hair_00", h0), ("hair_01", h1)):
        only({B, col})
        render(f"{out}/round_{tag}_back.png")
    holdout([B], False)
    # arm layers (body+tuft holdout, lift 0)
    holdout([B, T], True)
    only({B, T, limbs})
    show_limb(lambda n: n.startswith("Arm"))
    for tag, left in (("l", True), ("r", False)):
        show_limb(lambda n, lf=left: n.startswith("Arm")
                  and is_side(n, lf))
        render(f"{out}/round_arm_00_{tag}_back.png")
    # leg layers (body raised by the style lift, as in export)
    shift(("BODY", "TUFT", "FACE"), lift)
    for tag, left in (("l", True), ("r", False)):
        show_limb(lambda n, lf=left: not n.startswith("Arm")
                  and is_side(n, lf))
        render(f"{out}/round_leg_00_{tag}_back.png")
    shift(("BODY", "TUFT", "FACE"), -lift)
    holdout([B, T], False)
    show_limb(lambda n: True)

    # ---- diagnostics: back top view with hair_01 ----------------------
    top_data = bpy.data.cameras.new("TopCam")
    top_data.type = "ORTHO"
    top_data.ortho_scale = cam.data.ortho_scale
    top_data.clip_start, top_data.clip_end = 0.01, 100.0
    top_cam = bpy.data.objects.new("TopCam", top_data)
    top_cam.location = (0.0, 0.0, 9.0)
    cols["RIG"].objects.link(top_cam)
    scene.camera = top_cam
    only({B, limbs, h1})
    render(f"{out}/diag_back_top.png")
    scene.camera = cam

    print("BACKPROOF DONE round m=%.3f lift=%.4f" % (m, lift))


if __name__ == "__main__":
    main()
