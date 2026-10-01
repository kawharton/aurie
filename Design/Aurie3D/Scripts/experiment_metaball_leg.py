"""EXPERIMENT: one Aurie leg modeled with METABALLS (2026-09-13).

    blender --background --factory-startup \
        --python experiment_metaball_leg.py -- --outdir <renders>

A modeling-technique test, NOT a pipeline change: the existing limb
attachment/placement system (foot anchors FOOT_X/FOOT_Y on the ground
plane, body raised by a leg lift, limb root buried in the body, no
boolean union) is used exactly as-is. The experiment only swaps HOW the
leg's geometry is authored:

  metaball elements (upper leg / lower leg / ankle / foot / three toe
  masses) -> fused implicit surface -> duplicate -> convert the
  duplicate to a mesh -> inspect/clean -> shade smooth -> attach via
  the socket empties.

The editable metaball SOURCE survives in a render-excluded collection.
The reference is the user's chibi leg concept sheet: short chunky
slightly tapered legs, big soft paw feet with toe bulges; the
attachment end flares wider so it melts into the body.

Outputs (identical camera/lighting/framing per variant):
  metaleg_{front,q34l,side,q34r}.png      the metaball leg
  leg00_{front,q34l,side,q34r}.png        closest traditional leg
Saves the whole setup to Source/metaball_leg_experiment.blend — a NEW
file; nothing existing is overwritten.
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
LIFT = 0.17              # leg_00's body raise (its own LEG_BODY_LIFT)
LIFT_META = 0.26         # the longer metaball leg raises the body more
SIDE = -1                # the ONE modeled test leg (left); right mirrors it


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

    # The builder seeds LIMBS with its own preview limbs — clear, exactly
    # like the exporter does before each style pass.
    for ob in list(cols["LIMBS"].objects):
        bpy.data.objects.remove(ob, do_unlink=True)

    # Body group raised by the leg lift (existing placement system).
    def shift_body(dz):
        for cname in ("BODY", "TUFT", "FACE"):
            for ob in cols[cname].objects:
                ob.location.z += dz
    shift_body(LIFT_META)

    lx = SIDE * ROUND.FOOT_X
    fy = ROUND.FOOT_Y

    # ---- socket empties: the attachment points, made explicit ---------
    sockets = bpy.data.collections.new("SOCKETS")
    scene.collection.children.link(sockets)
    sock_z = 0.42            # leg root height — buried in the raised body
    for side, name in ((-1, "Socket_Leg_L"), (1, "Socket_Leg_R")):
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = "SPHERE"
        e.empty_display_size = 0.05
        e.location = (side * ROUND.FOOT_X, fy, sock_z)
        sockets.objects.link(e)

    # ---- metaball construction ----------------------------------------
    src_col = bpy.data.collections.new("MetaLegSource")
    scene.collection.children.link(src_col)
    mb = bpy.data.metaballs.new("MetaLeg")
    mb.resolution = 0.06
    mb.render_resolution = 0.03
    mb_obj = bpy.data.objects.new("MetaLeg", mb)
    src_col.objects.link(mb_obj)
    # Object origin AT the socket; every element is socket-relative.
    mb_obj.location = (lx, fy, sock_z)

    def el(co, r, stiffness=2.0):
        e = mb.elements.new()
        e.type = "BALL"
        e.co = co
        e.radius = r
        e.stiffness = stiffness
        return e

    # Socket-relative Z: 0 at the socket (buried), -sock_z at the ground.
    # BALL elements only (the ellipsoid path produced no usable field);
    # generous radii + strong overlaps so the union is one soft limb.
    # The iso-surface sits well inside element.radius (~0.7x at the
    # default threshold), so radii here are deliberately fatter than the
    # target silhouette — sized against leg_00's chunky column.
    g = -sock_z
    # LONGER, slightly slimmer leg column (the foot carries the mass).
    el((0.0, 0.0, 0.03), 0.330)          # root flare, buried in the body
    el((0.0, 0.0, -0.09), 0.290)         # upper leg
    el((0.004, -0.006, -0.18), 0.265)    # mid leg
    el((0.006, -0.010, -0.26), 0.245)    # lower leg
    el((0.006, -0.014, -0.325), 0.220)   # ankle — waist above the foot
    # THE FOOT (+13%): one continuous slab extending forward from the
    # ankle — heel under the column, DOMED instep rising where the foot
    # meets the leg (the reference's rounded top), broad forefoot.
    foot = [(0.000, -0.034, 0.125, 0.271),   # heel / instep
            (0.000, -0.100, 0.190, 0.210),   # instep DOME (rounded top)
            (-0.113, -0.113, 0.115, 0.226),  # mid-foot, left
            (0.113, -0.113, 0.115, 0.226),   # mid-foot, right
            (0.000, -0.136, 0.125, 0.260),   # mid-foot, centre
            (-0.130, -0.209, 0.110, 0.209),  # forefoot, left
            (0.130, -0.209, 0.110, 0.209),   # forefoot, right
            (0.000, -0.226, 0.115, 0.237)]   # forefoot, centre
    for dx, dy, dz, r in foot:
        el((dx + 0.008, dy, g + dz), r, 1.6)
    # TOES (+13%): three lobes of the SAME paw — tucked hard against the
    # forefoot so fusion leaves shallow scallop notches, never balls.
    for dx, dy, r in ((-0.200, -0.325, 0.200), (0.0, -0.365, 0.215),
                      (0.200, -0.325, 0.200)):
        el((0.008 + dx, dy, g + 0.075), r, 2.0)       # toe scallops (grounded)
    # convert() meshes at the VIEWPORT resolution — keep it fine
    mb.resolution = 0.015
    mb.render_resolution = 0.015

    # Force the depsgraph to realize the metaball surface.
    bpy.context.view_layer.update()

    # ---- duplicate -> convert to MESH (source stays editable) ---------
    for o in bpy.context.selected_objects:
        o.select_set(False)
    mb_obj.select_set(True)
    bpy.context.view_layer.objects.active = mb_obj
    bpy.ops.object.duplicate()
    dup = bpy.context.view_layer.objects.active
    dup.name = "MetaLegConv"
    bpy.ops.object.convert(target="MESH")
    leg = bpy.context.view_layer.objects.active
    leg.name = "Leg_Metaball_L"
    for c in list(leg.users_collection):
        c.objects.unlink(leg)
    cols["LIMBS"].objects.link(leg)
    leg.data.materials.append(body_mat)
    nverts, nfaces = len(leg.data.vertices), len(leg.data.polygons)
    print(f"METALEG topology: {nverts} verts / {nfaces} faces")
    bb = [leg.matrix_world @ Vector(c) for c in leg.bound_box]
    dims = (max(v.x for v in bb) - min(v.x for v in bb),
            max(v.y for v in bb) - min(v.y for v in bb),
            max(v.z for v in bb) - min(v.z for v in bb))
    print(f"METALEG bbox: {dims[0]:.3f} x {dims[1]:.3f} x {dims[2]:.3f}")
    if nverts < 200:
        raise RuntimeError("metaball conversion produced a stub mesh — "
                           "element field never reached threshold")
    # Clean density only if the implicit mesher went overboard.
    if nverts > 60000:
        dec = leg.modifiers.new("Clean", "DECIMATE")
        dec.ratio = 40000.0 / nverts
        bpy.ops.object.modifier_apply(modifier=dec.name)
        print(f"METALEG decimated to {len(leg.data.vertices)} verts")
    # Gentle smooth (applied), then a FLAT SOLE: every vertex below the
    # ground plane is clamped to it, so the fused paw/heel bellies become
    # one level surface the Aurie actually stands on.
    sm = leg.modifiers.new("Soften", "SMOOTH")
    sm.factor = 0.4
    sm.iterations = 4
    bpy.context.view_layer.objects.active = leg
    bpy.ops.object.modifier_apply(modifier=sm.name)
    sole = g  # local z of the ground (origin sits at the socket)
    flattened = 0
    for v in leg.data.vertices:
        if v.co.z < sole:
            v.co.z = sole
            flattened += 1
    print(f"METALEG sole: flattened {flattened} verts to the ground plane")
    leg.data.polygons.foreach_set(
        "use_smooth", [True] * len(leg.data.polygons))
    leg.data.update()

    # The metaball SOURCE stays for editing but never renders/exports.
    src_col.hide_render = True
    bpy.context.view_layer.layer_collection.children[
        "MetaLegSource"].exclude = True

    # Mirror the ONE modeled leg to the right socket (same asset).
    leg_r = leg.copy()
    leg_r.data = leg.data
    leg_r.name = "Leg_Metaball_R"
    leg_r.scale.x = -1
    leg_r.location = (abs(lx), fy, sock_z)
    cols["LIMBS"].objects.link(leg_r)

    # ---- the traditional comparison leg (leg_00, both sides) ----------
    trad = bpy.data.collections.new("LegTraditional")
    scene.collection.children.link(trad)
    for side in (-1, 1):
        L.LEGS["leg_00"](trad, body_mat, side, ROUND.FOOT_X, fy, M)

    # ---- identical-view render rig -------------------------------------
    orbit = bpy.data.objects.new("CamOrbit", None)
    orbit.location = (0.0, 0.0, 0.95)
    cols["RIG"].objects.link(orbit)
    cam = scene.camera
    keep = cam.matrix_world.copy()
    cam.parent = orbit
    cam.matrix_world = keep
    # The canonical camera frames the un-lifted body tightly; with the
    # body raised for legs, widen and drop the view so feet + ground are
    # always in frame.
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
        want = LIFT_META if meta_on else LIFT
        if abs(want - current_lift[0]) > 1e-6:
            shift_body(want - current_lift[0])
            current_lift[0] = want

    def render(path):
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("AURIE OK:", os.path.basename(path))

    scene.render.resolution_x = scene.render.resolution_y = 1024
    for tag, on in (("metaleg", True), ("leg00", False)):
        show_variant(on)
        for vname, ang in views:
            orbit.rotation_euler = (0.0, 0.0, ang)
            render(f"{out}/{tag}_{vname}.png")

    orbit.rotation_euler = (0.0, 0.0, 0.0)
    show_variant(True)

    # ---- save as a NEW experimental file --------------------------------
    blend = os.path.abspath(os.path.join(HERE, "..", "Source",
                                         "metaball_leg_experiment.blend"))
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print("SAVED", blend)
    print("EXPERIMENT DONE")


if __name__ == "__main__":
    main()
