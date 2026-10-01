"""Stage-B review renders for the Worry Jar.

    blender --background --factory-startup --python render_worry_jar_review.py -- \
        --outdir <dir> [--samples 300]

Produces the set needed to judge the ASSET, not the integration:

    front        straight app-facing view, transparent
    threequarter 3/4 beauty view, transparent
    cork_apart   cork lifted beside the jar, for geometry/material inspection
    closeup      crop on lip, wall thickness, cork pores
    calm         the jar on a dark indigo/plum Calm-Mode-like set
    phonesize    the front render downsampled to real device size

Lighting is a warm-key / cool-violet-fill rig, which is the combination the
Calm scene actually uses: gold fireflies against purple night. Glass needs
something bright to refract, so a soft area light doubles as a visible
"studio" reflection in the wall.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_worry_jar as jar  # noqa: E402


def area_light(name, loc, rot, size, energy, color):
    d = bpy.data.lights.new(name, "AREA")
    d.size = size
    d.energy = energy
    d.color = color
    ob = bpy.data.objects.new(name, d)
    ob.location = loc
    ob.rotation_euler = Euler(rot)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def setup_world(scene, dark=False):
    w = bpy.data.worlds.new("W")
    scene.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    if dark:
        # Calm Mode: deep indigo/plum, dim.
        bg.inputs["Color"].default_value = (0.055, 0.040, 0.105, 1.0)
        bg.inputs["Strength"].default_value = 1.0
    else:
        bg.inputs["Color"].default_value = (0.05, 0.05, 0.06, 1.0)
        bg.inputs["Strength"].default_value = 0.35
    return w


def setup_lights():
    # Larger, farther, dimmer sources than the preview rig: reflection size
    # scales with source size, so big soft sources give the glass long
    # elegant wraps instead of hard blocky cards.
    key = area_light("Key", (-2.6, -2.0, 2.9),
                     (math.radians(50), 0, math.radians(-40)),
                     size=4.2, energy=240, color=(1.0, 0.87, 0.68))
    key.data.spread = math.radians(140)
    fill = area_light("Fill", (2.8, -1.4, 1.3),
                      (math.radians(72), 0, math.radians(60)),
                      size=4.6, energy=110, color=(0.62, 0.55, 1.0))
    fill.data.spread = math.radians(150)
    # Rim stays tighter — it is what draws the bright glass edges.
    rim = area_light("Rim", (0.7, 2.6, 2.0),
                     (math.radians(-56), 0, math.radians(14)),
                     size=1.7, energy=260, color=(0.90, 0.86, 1.0))
    # A tall narrow softbox for the classic vertical window reflection.
    card = area_light("Card", (-0.3, -3.4, 1.0), (math.radians(90), 0, 0),
                      size=2.2, energy=60, color=(1.0, 0.95, 0.92))
    card.data.size_y = 6.0
    return card


def make_camera(scene, loc, look_at=Vector((0, 0, 0.48)), ortho=None):
    cd = bpy.data.cameras.new("Cam")
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    else:
        cd.lens = 85
    cam = bpy.data.objects.new("Cam", cd)
    cam.location = loc
    bpy.context.scene.collection.objects.link(cam)
    d = look_at - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    return cam


def render(scene, path, w, h, transparent=True):
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.film_transparent = transparent
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--samples", type=int, default=300)
    args = ap.parse_args(argv)
    os.makedirs(args.outdir, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    try:
        scene.cycles.device = "GPU"
    except Exception:
        pass
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = True
    # Glass needs refractive bounces or it goes black in the thick areas.
    scene.cycles.max_bounces = 32
    scene.cycles.transmission_bounces = 24
    scene.cycles.transparent_max_bounces = 24
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Punchy"

    glass = jar.build_glass()
    cork = jar.build_cork()
    cork.location = (0.0, 0.0, jar.LIP_TOP)
    glass.data.materials.append(jar.glass_material())
    cork.data.materials.append(jar.cork_material())

    # Plum world for ALL review views: transmissive glass over a transparent
    # film transmits nothing and reads as a black jar — misleading for a
    # beauty review. Production layer exports handle alpha separately.
    setup_world(scene, dark=True)
    setup_lights()

    out = args.outdir
    # 1. straight front, app-facing (framing proven in the preview passes)
    make_camera(scene, (0.0, -3.4, 0.63), look_at=Vector((0, 0, 0.63)),
                ortho=1.62)
    render(scene, os.path.join(out, "front.png"), 1100, 1400, transparent=False)

    # 2. three-quarter beauty
    make_camera(scene, (-2.05, -2.5, 1.62), look_at=Vector((0, 0, 0.60)),
                ortho=1.72)
    render(scene, os.path.join(out, "threequarter.png"), 1200, 1400, transparent=False)

    # 3. close-up: mouth, lip thickness, cork seating, wall, reflections
    make_camera(scene, (-1.05, -1.65, 1.60), look_at=Vector((0, 0, 1.06)),
                ortho=0.66)
    render(scene, os.path.join(out, "closeup.png"), 1300, 1100, transparent=False)

    # 4. cork lifted aside for independent inspection
    cork.location = (0.74, -0.05, 0.80)
    cork.rotation_euler = Euler((math.radians(22), math.radians(-14), 0))
    make_camera(scene, (-1.5, -2.9, 1.35), look_at=Vector((0.28, 0, 0.66)),
                ortho=1.95)
    render(scene, os.path.join(out, "cork_apart.png"), 1400, 1200, transparent=False)
    cork.location = (0.0, 0.0, jar.LIP_TOP)
    cork.rotation_euler = Euler((0, 0, 0))

    # 5. against a Calm-Mode-like dark plum set
    make_camera(scene, (-0.55, -3.3, 0.68), look_at=Vector((0, 0, 0.64)),
                ortho=1.66)
    render(scene, os.path.join(out, "calm.png"), 1100, 1400, transparent=False)

    # Master .blend for the pipeline (copy — never overwrites a working file).
    src = os.path.join(os.path.dirname(HERE), "Source", "worry_jar_master.blend")
    os.makedirs(os.path.dirname(src), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=src, copy=True)
    print("MASTER saved:", src)

    dg = bpy.context.evaluated_depsgraph_get()
    for ob in (glass, cork):
        me = ob.evaluated_get(dg).to_mesh()
        print(f"STAT {ob.name} tris={sum(len(p.vertices)-2 for p in me.polygons)} "
              f"verts={len(me.vertices)}")


if __name__ == "__main__":
    main()
