"""EXPERIMENT: five hair candidates modeled with METABALLS
(2026-09-13) — the exact process that produced the approved metaball
legs, pointed at the user's five hair reference images:

    C1 Cloud Puff   — one soft round cloud puff sunk into the crown
                      (APPROVED 2026-09-13)
    C2 Curl Pile    — REMOVED (user: too difficult)
    C3 Sprout Crown — ON HOLD (kept as-is, not iterated)
    C4 Twin Poms    — the approved C1 puff at 80.5% scale, one per
                      upper side of the head (APPROVED 2026-09-13)
    C5 Wave Quiff   — REMOVED (user, 2026-09-13)

    blender --background --factory-startup \
        --python experiment_metaball_hair.py -- --outdir <renders>

Each candidate: metaball elements -> fused implicit surface ->
duplicate -> convert to mesh -> gentle smooth -> shown on the round
body IN PLACE OF the baked tuft. Metaball sources survive in a
render-excluded collection. The baked tuft renders as the control.
No app integration here — approval gate first.

Outputs: {tuft,c1,c3,c4}_{front,q34}.png on identical camera/lighting.
Saves to Source/metaball_hair_experiment.blend — a NEW file.
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

M = 0.85
LIFT = 0.22              # leg_01's lift — complete grounded character


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--samples", type=int, default=96)
    ap.add_argument("--only", default=None,
                    help="CSV subset of tags to render, e.g. tuft,c1")
    args = ap.parse_args(argv)
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

    # Measure the crown of the LIFTED body from its real vertices.
    bpy.context.view_layer.update()
    pts = []
    for ob in cols["BODY"].objects:
        if ob.type == "MESH":
            mw = ob.matrix_world
            pts += [mw @ v.co for v in ob.data.vertices]
    top = max(p.z for p in pts)
    print(f"CROWN top z = {top:.3f}")

    src_col = bpy.data.collections.new("MetaHairSource")
    scene.collection.children.link(src_col)
    mesh_col = bpy.data.collections.new("HairCandidates")
    scene.collection.children.link(mesh_col)

    def build_candidate(name, elements, meld=None):
        """One metaball family -> converted mesh, hidden by default.

        meld=(R, skin, z_hi, z_lo): metaballs only ADD convex bulges,
        so a concave fillet against the (separate) head mesh cannot
        come from the field. Instead, after conversion, base vertices
        are pulled radially toward the head sphere (radius R + skin,
        centre R below the crown) with a smoothstep falloff from z_hi
        (no pull) to z_lo (fully on the sphere) — the base lands
        tangent on the scalp like the baked tuft does.
        """
        mb = bpy.data.metaballs.new(name)
        mb.resolution = 0.015
        mb.render_resolution = 0.015
        mb_obj = bpy.data.objects.new(name, mb)
        src_col.objects.link(mb_obj)
        mb_obj.location = (0.0, 0.0, top)      # origin at the crown peak
        for co, r, st in elements:
            e = mb.elements.new()
            e.type = "BALL"
            e.co = co
            e.radius = r
            e.stiffness = st
        bpy.context.view_layer.update()
        deps = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(mb_obj.evaluated_get(deps))
        if meld:
            R, skin, z_hi, z_lo = meld
            centre = Vector((0.0, 0.0, -R))
            for v in me.vertices:
                t = (z_hi - v.co.z) / (z_hi - z_lo)
                t = max(0.0, min(1.0, t))
                t = t * t * (3.0 - 2.0 * t)          # smoothstep
                if t <= 0.0:
                    continue
                u = v.co - centre
                dist = u.length
                # skin tapers with the pull so the flare's terminating
                # edge lands nearly flush on the scalp (no visible step)
                tgt = R + skin * (1.0 - t) + 0.004
                if dist > tgt:
                    v.co = centre + u * (
                        (dist + (tgt - dist) * t) / dist)
        ob = bpy.data.objects.new(name + "_mesh", me)
        ob.location = mb_obj.location
        mesh_col.objects.link(ob)
        sm = ob.modifiers.new("Soften", "SMOOTH")
        sm.factor = 0.35
        sm.iterations = 3
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
        me.update()
        ob.data.materials.append(body_mat)
        ob.hide_render = True
        print(f"{name}: {len(me.vertices)} verts")
        return ob

    # All element coords are CROWN-relative (z=0 at the crown peak);
    # negative z sinks the weld roots into the body.
    # Cloud Puff — a full round puffball, not a low cap: lobes wrap a
    # fat core in EVERY direction (front/back depth included) so it
    # reads round from the front and the 3/4 alike. Attachment is a
    # plain sink: the whole puff is lowered so its underside is buried
    # in the head and the visible junction is the puff surface
    # disappearing into the scalp — no collar/flare material (both
    # were rejected as "an extra layer below the hair").
    C1_SINK = 0.10
    c1_base = [
        ((0.0, 0.02, -0.10), 0.44, 1.8),         # weld root
        ((0.0, 0.0, 0.18), 0.54, 2.1),           # fat core
        ((-0.14, -0.02, 0.375), 0.345, 2.35),    # top-left bump
        ((0.165, 0.03, 0.385), 0.36, 2.35),      # top-right bump
        ((-0.315, -0.03, 0.20), 0.415, 2.3),     # left lobe
        ((0.33, 0.02, 0.215), 0.43, 2.3),        # right lobe (asym)
        ((-0.02, -0.27, 0.16), 0.39, 2.3),       # front lobe (depth)
        ((0.03, 0.28, 0.15), 0.40, 2.3),         # back lobe (depth)
    ]
    c1_els = [((x, y, z - C1_SINK), r, st)
              for (x, y, z), r, st in c1_base]
    c1 = build_candidate("MetaHairC1", c1_els)

    def bud(cx, cy, h, lean, w):
        els = []
        for i, t in enumerate((0.0, 0.5, 1.0)):
            els.append(((cx + lean * t * h, cy,
                         -0.05 + t * h),
                        (0.30 - 0.075 * t) * w, 2.3))
        return els
    c3_els = [((0.0, 0.0, -0.10), 0.36, 1.8)]     # weld root
    c3_els += bud(0.0, -0.04, 0.30, 0.08, 1.15)   # dominant front
    c3_els += bud(-0.21, 0.03, 0.20, -0.30, 0.88)
    c3_els += bud(0.21, 0.04, 0.235, 0.28, 0.98)
    c3 = build_candidate("MetaHairC3", c3_els)

    # C4 Twin Cloud Poms — the approved C1 puff at 70% scale, one per
    # upper side of the head (reference: twin cloud poms), attached the
    # same way C1 is: plainly sunk, no collar/flare material.
    HEAD_R = 0.97                    # crown z 2.155 minus body centre

    def side_puff(sign, theta_deg, scale, sink, xsq, zst):
        """Scale the C1 puff, aim its local +z along the head-sphere
        normal at polar angle theta in the frontal plane, land it on
        the scalp there (negative sink = origin proud of the scalp,
        only the root buried). xsq compresses the wide axis and zst
        stretches the outward axis so the small pom protrudes as a
        round ball, not a shallow ear."""
        th = math.radians(theta_deg) * sign
        ct, st_ = math.cos(th), math.sin(th)
        px = (HEAD_R - sink) * st_
        pz = (HEAD_R - sink) * ct - HEAD_R
        out = []
        for (x, y, z), r, stf in c1_base:
            x, y, z = x * scale * xsq, y * scale, z * scale * zst
            out.append(((px + x * ct + z * st_, y,
                         pz - x * st_ + z * ct), r * scale, stf))
        return out

    c4_els = (side_puff(-1, 40.0, 0.805, 0.01, 0.80, 1.3)
              + side_puff(1, 40.0, 0.805, 0.01, 0.80, 1.3))
    c4 = build_candidate("MetaHairC4", c4_els)

    candidates = {"c1": c1, "c3": c3, "c4": c4}
    src_col.hide_render = True
    bpy.context.view_layer.layer_collection.children[
        "MetaHairSource"].exclude = True

    orbit = bpy.data.objects.new("CamOrbit", None)
    orbit.location = (0.0, 0.0, 0.95)
    cols["RIG"].objects.link(orbit)
    cam = scene.camera
    keep = cam.matrix_world.copy()
    cam.parent = orbit
    cam.matrix_world = keep
    cam.data.ortho_scale *= 1.30       # headroom for the taller styles
    mw = cam.matrix_world.copy()
    mw.translation.z += 0.05
    cam.matrix_world = mw

    tuft_obs = list(cols["TUFT"].objects)

    def show(tag):
        for ob in tuft_obs:
            ob.hide_render = tag != "tuft"
        for t, ob in candidates.items():
            ob.hide_render = t != tag

    def render(path):
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("AURIE OK:", os.path.basename(path))

    scene.render.resolution_x = scene.render.resolution_y = 1024
    tags = ["tuft", "c1", "c3", "c4"]
    if args.only:
        want = {t.strip() for t in args.only.split(",")}
        tags = [t for t in tags if t in want]
    for tag in tags:
        show(tag)
        for vname, ang in (("front", 0.0), ("q34", math.radians(-38.0))):
            orbit.rotation_euler = (0.0, 0.0, ang)
            render(f"{out}/{tag}_{vname}.png")

    orbit.rotation_euler = (0.0, 0.0, 0.0)
    blend = os.path.abspath(os.path.join(HERE, "..", "Source",
                                         "metaball_hair_experiment.blend"))
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print("SAVED", blend)
    print("EXPERIMENT DONE")


if __name__ == "__main__":
    main()
