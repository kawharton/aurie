"""Stage-C review renders for the Worry Jar firefly.

    blender --background --factory-startup --python render_firefly_review.py -- \
        --outdir <dir> [--samples 240]

    hero        one firefly, large, on the plum world
    lineup      the four variants side by side
    injar       6 fireflies INSIDE the frozen jar at real 3D depths, with
                their emission genuinely lighting the glass (perspective
                camera, so depth reads as scale and softness)

Bloom is applied afterwards in PIL (the bash step), not here — Cycles renders
the sharp cores and the real light bounce; the soft halo is the same additive
treatment the app will composite at runtime.

The jar and cork are the FROZEN Stage-B builders, untouched.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_firefly as ff             # noqa: E402
import build_worry_jar as jar          # noqa: E402
import render_worry_jar_review as rig  # noqa: E402


def scene_setup(samples):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 24
    scene.cycles.transmission_bounces = 20
    scene.cycles.transparent_max_bounces = 20
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Punchy"
    return scene


def persp_camera(scene, loc, look_at, lens=85):
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    cam = bpy.data.objects.new("Cam", cd)
    cam.location = loc
    bpy.context.scene.collection.objects.link(cam)
    d = Vector(look_at) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    return cam


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--samples", type=int, default=240)
    args = ap.parse_args(argv)
    os.makedirs(args.outdir, exist_ok=True)

    # ---------------------------------------------------------------- hero
    scene = scene_setup(args.samples)
    rig.setup_world(scene, dark=True)
    # Violet rim so the translucent wings catch coloured edges; a dim warm
    # key so the dark body has a readable highlight.
    rig.area_light("Rim", (1.6, 2.0, 1.4),
                   (math.radians(-55), 0, math.radians(28)),
                   size=2.0, energy=140, color=(0.66, 0.58, 1.0))
    rig.area_light("Key", (-1.8, -1.6, 1.8),
                   (math.radians(52), 0, math.radians(-40)),
                   size=2.4, energy=70, color=(1.0, 0.88, 0.72))
    hero = ff.build_firefly("Hero", **ff.VARIANTS["V1_base"])
    hero.rotation_euler = Euler((0, 0, math.radians(22)))
    persp_camera(scene, (-2.75, -3.05, 1.30), (0, 0.02, 0.00), lens=88)
    rig.render(scene, os.path.join(args.outdir, "firefly_hero.png"),
               1300, 1000, transparent=False)
    # Same pose with a transparent film: the alpha source the production
    # sprites will use (emissive solids keep correct alpha, unlike glass).
    rig.render(scene, os.path.join(args.outdir, "firefly_sprite_src.png"),
               1300, 1000, transparent=True)

    # -------------------------------------------------------------- lineup
    scene = scene_setup(args.samples)
    rig.setup_world(scene, dark=True)
    rig.area_light("Rim", (1.6, 2.2, 1.6),
                   (math.radians(-55), 0, math.radians(24)),
                   size=2.6, energy=150, color=(0.66, 0.58, 1.0))
    rig.area_light("Key", (-2.0, -1.8, 2.0),
                   (math.radians(52), 0, math.radians(-40)),
                   size=3.0, energy=80, color=(1.0, 0.88, 0.72))
    xs = (-2.45, -0.82, 0.82, 2.45)
    for x, (vname, kw) in zip(xs, ff.VARIANTS.items()):
        root = ff.build_firefly(vname, **kw)
        root.location = (x, 0, 0)
        # Side profile, tiny per-variant tilt so they read as individuals.
        root.rotation_euler = Euler((0, 0, math.radians(-95 - 6 * xs.index(x))))
    persp_camera(scene, (0, -9.2, 0.90), (0, 0, 0.02), lens=50)
    rig.render(scene, os.path.join(args.outdir, "firefly_lineup.png"),
               2000, 640, transparent=False)

    # -------------------------------------------------------------- in-jar
    scene = scene_setup(args.samples)
    rig.setup_world(scene, dark=True)
    rig.setup_lights()
    glass = jar.build_glass()
    cork = jar.build_cork()
    cork.location = (0.0, 0.0, jar.LIP_TOP)
    glass.data.materials.append(jar.glass_material())
    cork.data.materials.append(jar.cork_material())

    # Six fireflies occupying the interior VOLUME: varied height, depth
    # (camera is at -Y, so negative y is nearer), scale, glow and heading.
    placements = [
        # (x,      y,      z,    scale,  yaw°, variant)
        (-0.150,  0.110, 0.700, 0.085,   38, "V1_base"),
        ( 0.175, -0.120, 0.520, 0.100,  -24, "V2_round"),
        ( 0.010,  0.180, 0.380, 0.072,  152, "V3_slender"),
        (-0.195, -0.060, 0.330, 0.095,   -8, "V4_bright"),
        ( 0.105,  0.040, 0.260, 0.088,   74, "V1_base"),
        (-0.040, -0.150, 0.840, 0.078,  -52, "V2_round"),
    ]
    for i, (x, y, z, s, yaw, vname) in enumerate(placements):
        kw = dict(ff.VARIANTS[vname])
        # Emission is per-area: at 0.08x scale a firefly sheds ~0.6% of its
        # full-size light. x6 keeps the gold visibly pooling in the glass
        # base and walls without turning the jar into a lantern.
        kw["glow"] = kw["glow"] * 7.5
        root = ff.build_firefly(f"Jar{i}", **kw)
        root.location = (x, y, z)
        root.scale = (s, s, s)
        root.rotation_euler = Euler((0, 0, math.radians(yaw)))

    persp_camera(scene, (0.0, -3.6, 0.66), (0, 0, 0.60), lens=85)
    rig.render(scene, os.path.join(args.outdir, "firefly_injar.png"),
               1100, 1400, transparent=False)

    # Master (copy) for the pipeline.
    src = os.path.join(os.path.dirname(HERE), "Source", "firefly_master.blend")
    bpy.ops.wm.save_as_mainfile(filepath=src, copy=True)
    print("MASTER saved:", src)

    dg = bpy.context.evaluated_depsgraph_get()
    total = 0
    for ob in bpy.data.objects:
        if ob.type == "MESH" and ob.name.startswith(("Firefly", "Jar0")):
            me = ob.evaluated_get(dg).to_mesh()
            total += sum(len(p.vertices) - 2 for p in me.polygons)
    print(f"STAT one-firefly tris ≈ {total // max(1, len(placements))}")


if __name__ == "__main__":
    main()
