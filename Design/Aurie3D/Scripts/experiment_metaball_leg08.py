"""EXPERIMENT: leg candidate 08 from the user's bulb-foot reference
(2026-09-13), modeled with METABALLS — the same steps as the approved
leg_07 experiment.

    blender --background --factory-startup \
        --python experiment_metaball_leg08.py -- --outdir <renders>

Reference read: thick smooth leg columns, barely tapered, flowing
seamlessly into BIG rounded feet that swell forward like soft boots —
one continuous bulb each, NO toes, soft flattened ground contact, the
body riding low. The attachment/placement system is used exactly as-is
(foot anchors, body lift, buried root, no boolean).

Outputs (identical camera/lighting/framing per variant):
  metaleg8_{front,q34l,side,q34r}.png     the candidate
  leg01_{front,q34l,side,q34r}.png        leg_01 Bounce Feet (closest)
Saves to Source/metaball_leg08_experiment.blend — a NEW file.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aurie_limb_styles as L  # noqa: E402
import build_round_aurie as ROUND  # noqa: E402

M = 0.85                 # round's approved limb scale
LIFT_TRAD = 0.22         # leg_01 Bounce Feet's own body raise
LIFT_META = 0.31         # the candidate's raise (long visible column)
SIDE = -1                # the ONE modeled test leg (left); right mirrors


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--samples", type=int, default=96)
    args = ap.parse_args(argv)
    out = os.path.abspath(args.outdir)
    os.makedirs(out, exist_ok=True)

    scene, cols = ROUND.build(os.path.join(HERE, "..", "Source"))
    scene.cycles.samples = args.samples
    body_mat = bpy.data.materials["AurieBody"]
    for ob in list(cols["LIMBS"].objects):
        bpy.data.objects.remove(ob, do_unlink=True)

    def shift_body(dz):
        for cname in ("BODY", "TUFT", "FACE"):
            for ob in cols[cname].objects:
                ob.location.z += dz
    shift_body(LIFT_META)

    lx = SIDE * ROUND.FOOT_X
    fy = ROUND.FOOT_Y

    sockets = bpy.data.collections.new("SOCKETS")
    scene.collection.children.link(sockets)
    sock_z = 0.47
    for side, name in ((-1, "Socket_Leg_L"), (1, "Socket_Leg_R")):
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = "SPHERE"
        e.empty_display_size = 0.05
        e.location = (side * ROUND.FOOT_X, fy, sock_z)
        sockets.objects.link(e)

    src_col = bpy.data.collections.new("MetaLegSource")
    scene.collection.children.link(src_col)
    mb = bpy.data.metaballs.new("MetaLeg8")
    mb.resolution = 0.015
    mb.render_resolution = 0.015
    mb_obj = bpy.data.objects.new("MetaLeg8", mb)
    src_col.objects.link(mb_obj)
    mb_obj.location = (lx, fy, sock_z)

    def el(co, r, stiffness=2.0):
        e = mb.elements.new()
        e.type = "BALL"
        e.co = co
        e.radius = r
        e.stiffness = stiffness
        return e

    # Socket-relative Z: 0 buried, -sock_z at the ground.
    g = -sock_z
    # thick, barely-tapered column (the reference legs stay chunky),
    # LONGER so a clear stretch of leg shows between body and foot
    el((0.0, 0.0, 0.03), 0.345)          # root flare, buried
    el((0.0, 0.0, -0.10), 0.305)         # upper leg
    el((0.004, -0.004, -0.21), 0.285)    # mid leg
    el((0.005, -0.006, -0.30), 0.272)    # lower leg
    el((0.006, -0.008, -0.355), 0.262)   # above the foot — hardly a waist
    # THE FOOT: one smooth bulb swelling forward, boot-like, NO toes —
    # heel tucked under the column, BIG main bulb, round front lobe,
    # all soft-fused into a single continuous mass
    el((0.006, 0.02, g + 0.12), 0.275, 1.6)       # heel
    el((0.010, -0.10, g + 0.135), 0.325, 1.55)    # main bulb
    el((0.012, -0.225, g + 0.115), 0.27, 1.65)    # rounded front
    bpy.context.view_layer.update()

    for o in bpy.context.selected_objects:
        o.select_set(False)
    mb_obj.select_set(True)
    bpy.context.view_layer.objects.active = mb_obj
    bpy.ops.object.duplicate()
    dup = bpy.context.view_layer.objects.active
    dup.name = "MetaLeg8Conv"
    bpy.ops.object.convert(target="MESH")
    leg = bpy.context.view_layer.objects.active
    leg.name = "Leg_Metaball8_L"
    for c in list(leg.users_collection):
        c.objects.unlink(leg)
    cols["LIMBS"].objects.link(leg)
    leg.data.materials.append(body_mat)
    nverts = len(leg.data.vertices)
    print(f"METALEG8 topology: {nverts} verts / {len(leg.data.polygons)} faces")
    bb = [leg.matrix_world @ Vector(c) for c in leg.bound_box]
    print("METALEG8 bbox: "
          f"{max(v.x for v in bb) - min(v.x for v in bb):.3f} x "
          f"{max(v.y for v in bb) - min(v.y for v in bb):.3f} x "
          f"{max(v.z for v in bb) - min(v.z for v in bb):.3f}")
    if nverts < 200:
        raise RuntimeError("stub mesh — field never reached threshold")
    sm = leg.modifiers.new("Soften", "SMOOTH")
    sm.factor = 0.4
    sm.iterations = 4
    bpy.context.view_layer.objects.active = leg
    bpy.ops.object.modifier_apply(modifier=sm.name)
    flattened = 0
    for v in leg.data.vertices:
        if v.co.z < g:
            v.co.z = g
            flattened += 1
    print(f"METALEG8 sole: flattened {flattened} verts")
    leg.data.polygons.foreach_set(
        "use_smooth", [True] * len(leg.data.polygons))
    leg.data.update()

    src_col.hide_render = True
    bpy.context.view_layer.layer_collection.children[
        "MetaLegSource"].exclude = True

    leg_r = leg.copy()
    leg_r.data = leg.data
    leg_r.name = "Leg_Metaball8_R"
    leg_r.scale.x = -1
    leg_r.location = (abs(lx), fy, sock_z)
    cols["LIMBS"].objects.link(leg_r)

    trad = bpy.data.collections.new("LegTraditional")
    scene.collection.children.link(trad)
    for side in (-1, 1):
        L.LEGS["leg_01"](trad, body_mat, side, ROUND.FOOT_X, fy, M)

    orbit = bpy.data.objects.new("CamOrbit", None)
    orbit.location = (0.0, 0.0, 0.95)
    cols["RIG"].objects.link(orbit)
    cam = scene.camera
    keep = cam.matrix_world.copy()
    cam.parent = orbit
    cam.matrix_world = keep
    cam.data.ortho_scale *= 1.22
    mw = cam.matrix_world.copy()
    mw.translation.z -= 0.10
    cam.matrix_world = mw

    views = [("front", 0.0), ("q34l", math.radians(-40.0)),
             ("side", math.radians(-90.0)), ("q34r", math.radians(40.0))]
    current_lift = [LIFT_META]

    def show_variant(meta_on):
        for ob in (leg, leg_r):
            ob.hide_render = not meta_on
        for ob in trad.objects:
            ob.hide_render = meta_on
        want = LIFT_META if meta_on else LIFT_TRAD
        if abs(want - current_lift[0]) > 1e-6:
            shift_body(want - current_lift[0])
            current_lift[0] = want

    def render(path):
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("AURIE OK:", os.path.basename(path))

    scene.render.resolution_x = scene.render.resolution_y = 1024
    for tag, on in (("metaleg8", True), ("leg01", False)):
        show_variant(on)
        for vname, ang in views:
            orbit.rotation_euler = (0.0, 0.0, ang)
            render(f"{out}/{tag}_{vname}.png")

    orbit.rotation_euler = (0.0, 0.0, 0.0)
    show_variant(True)
    blend = os.path.abspath(os.path.join(HERE, "..", "Source",
                                         "metaball_leg08_experiment.blend"))
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print("SAVED", blend)
    print("EXPERIMENT DONE")


if __name__ == "__main__":
    main()
