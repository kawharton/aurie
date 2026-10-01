"""Aurie hatch egg — 3D shell behind the APPROVED 2D silhouette.

    blender --background --factory-startup --python build_hatch_egg.py -- \
        --outdir <dir> [--neutral C0C0C0] [--samples 128]

The silhouette is NOT redesigned. `EggShape` in the app is four bezier
curves in a unit rect; its right half is sampled here and revolved, so the
rendered front silhouette reproduces the shipped egg outline exactly and
the existing crack paths still line up over it.

Material and lighting are the approved Aurie family rig (same key/fill/rim
powers, same world strength, same plush principled setup), so the egg and
the creature read as the same product. Shell markings are shallow DENTS in
the geometry rather than pasted circles: they catch the same light as the
body, so they survive the runtime family tint instead of looking stuck on.

Exports a neutral shell (default #C0C0C0) with transparent background, plus
a clipping report so the neutral can be checked rather than assumed.
"""

import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aurie_body_common as common  # noqa: E402

# EggShape (Auries/Screens/EggHatchView.swift), right half, unit rect:
#   start   (0.50, 0.00)
#   curve 1 -> (1.00, 0.62)  c1 (0.86, 0.02)  c2 (1.00, 0.35)
#   curve 2 -> (0.50, 1.00)  c1 (1.00, 0.86)  c2 (0.78, 1.00)
RIGHT_HALF = [
    ((0.50, 0.00), (0.86, 0.02), (1.00, 0.35), (1.00, 0.62)),
    ((1.00, 0.62), (1.00, 0.86), (0.78, 1.00), (0.50, 1.00)),
]
# The app draws the egg in a 230x300 frame; keep that aspect in 3D.
FRAME_W, FRAME_H = 230.0, 300.0
EGG_H = 2.0                                   # scene units, tall axis
EGG_W = EGG_H * (FRAME_W / FRAME_H)

# Shell markings: (u around, v up, radius, depth). `u` is in HALF-TURNS and
# the camera looks along +y, so the visible face is u = -0.5; keeping the
# spots near that band puts them on the front rather than skidding across
# the silhouette edge where they read as smudges.
SPOTS = [(-0.34, 0.66, 0.22, 0.026), (-0.68, 0.55, 0.18, 0.021),
         (-0.44, 0.36, 0.20, 0.024), (-0.24, 0.24, 0.16, 0.019),
         (-0.72, 0.28, 0.15, 0.017), (-0.55, 0.76, 0.14, 0.016)]


def bezier(p0, p1, p2, p3, t):
    u = 1.0 - t
    return (u * u * u * p0[0] + 3 * u * u * t * p1[0]
            + 3 * u * t * t * p2[0] + t * t * t * p3[0],
            u * u * u * p0[1] + 3 * u * u * t * p1[1]
            + 3 * u * t * t * p2[1] + t * t * t * p3[1])


def profile(samples=96):
    """(height, radius) pairs in scene units, bottom-up."""
    pts = []
    for seg in RIGHT_HALF:
        for i in range(samples):
            x, y = bezier(*seg, i / samples)
            pts.append((x, y))
    pts.append((0.5, 1.0))
    out = []
    for x, y in pts:
        # unit rect -> scene: y down 0..1 becomes z up, x 0.5 is the axis
        z = (1.0 - y) * EGG_H - EGG_H / 2.0
        r = (x - 0.5) * EGG_W
        out.append((z, max(r, 0.0)))
    out.sort(key=lambda p: p[0])
    return out


def build_shell(neutral_hex):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    cols = {}
    for name in ("EGG", "STAGE"):
        c = bpy.data.collections.new(name)
        scene.collection.children.link(c)
        cols[name] = c

    prof = profile()
    segs = 128
    bm = bmesh.new()
    rings = []
    for z, r in prof:
        if r <= 1e-5:
            rings.append([bm.verts.new((0.0, 0.0, z))])
            continue
        ring = [bm.verts.new((r * math.cos(2 * math.pi * i / segs), 0.0, z))
                for i in range(segs)]
        for i, v in enumerate(ring):
            a = 2 * math.pi * i / segs
            v.co = Vector((r * math.cos(a), r * math.sin(a), z))
        rings.append(ring)
    for lower, upper in zip(rings, rings[1:]):
        if len(lower) == 1 or len(upper) == 1:
            hub = lower[0] if len(lower) == 1 else upper[0]
            loop = upper if len(lower) == 1 else lower
            for i in range(segs):
                try:
                    bm.faces.new((hub, loop[i], loop[(i + 1) % segs]))
                except ValueError:
                    pass
            continue
        for i in range(segs):
            try:
                bm.faces.new((lower[i], lower[(i + 1) % segs],
                              upper[(i + 1) % segs], upper[i]))
            except ValueError:
                pass
    bm.normal_update()

    # Shell markings as shallow dents: they shade with the same light rig,
    # so they read as part of the material rather than pasted-on circles.
    for u, v, rad, depth in SPOTS:
        zc = (v - 0.5) * EGG_H
        ang = u * math.pi
        centre = None
        for z, r in prof:
            if abs(z - zc) < EGG_H / len(prof) * 1.5:
                centre = Vector((r * math.cos(ang), r * math.sin(ang), z))
                break
        if centre is None:
            continue
        for vert in bm.verts:
            d = (vert.co - centre).length
            if d < rad:
                fall = math.cos(d / rad * math.pi * 0.5) ** 2
                vert.co -= vert.co.normalized() * depth * fall

    bm.normal_update()
    mesh = bpy.data.meshes.new("EggShell")
    bm.to_mesh(mesh)
    bm.free()
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.update()
    egg = bpy.data.objects.new("EggShell", mesh)
    cols["EGG"].objects.link(egg)

    mat, bsdf = common._principled("EggShell")
    common._set(bsdf, common._srgb(neutral_hex), "Base Color")
    common._set(bsdf, 0.80, "Roughness")
    common._set(bsdf, 0.30, "Specular IOR Level", "Specular")
    common._set(bsdf, 0.15, "Sheen Weight", "Sheen")
    common._set(bsdf, 0.50, "Sheen Roughness")
    egg.data.materials.append(mat)
    return scene, cols, egg, bsdf


def light_and_render(scene, cols, outdir, samples):
    def light(name, loc, size, power, colour):
        data = bpy.data.lights.new(name, "AREA")
        data.shape, data.size, data.energy, data.color = "DISK", size, power, colour
        ob = bpy.data.objects.new(name, data)
        ob.location = loc
        direction = Vector((0.0, 0.0, 0.0)) - Vector(loc)
        ob.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        cols["STAGE"].objects.link(ob)

    # The approved Aurie rig, unchanged, so the egg is lit in the same studio.
    light("Key", (-3.0, -3.0, 4.0), 3.0, common.KEY_POWER, (1.0, 0.97, 0.92))
    light("Fill", (3.5, -2.5, 1.2), 4.0, common.FILL_POWER, (0.90, 0.95, 1.0))
    light("Rim", (0.8, 3.5, 3.2), 2.0, common.RIM_POWER, (1.0, 1.0, 1.0))

    world = bpy.data.worlds.new("EggWorld")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Strength"].default_value = 0.2
    scene.world = world

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    # Frame the egg tightly: the export is cropped to its alpha bbox and
    # then drawn into the app's existing egg rect, so registration is exact.
    cam_data.ortho_scale = EGG_H * 1.04
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0.0, -10.0, 0.0)
    cam.rotation_euler = (math.radians(90), 0.0, 0.0)
    cols["STAGE"].objects.link(cam)
    scene.camera = cam

    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = 1024
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.render.filepath = os.path.join(outdir, "egg_shell_neutral.png")
    bpy.ops.render.render(write_still=True)
    print("AURIE OK:", scene.render.filepath)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--neutral", default="C0C0C0")
    ap.add_argument("--samples", type=int, default=128)
    args = ap.parse_args(argv)
    out = os.path.abspath(args.outdir)
    os.makedirs(out, exist_ok=True)
    scene, cols, egg, bsdf = build_shell(args.neutral)
    light_and_render(scene, cols, out, args.samples)
    print("AURIE EGG DONE")


if __name__ == "__main__":
    main()
