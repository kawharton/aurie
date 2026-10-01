"""Production asset export for the Worry Jar layered composite.

    blender --background --factory-startup --python export_worry_jar_assets.py -- \
        --outdir <dir> [--samples 220]

Outputs (all transparent-film PNG, one shared camera so the jar layers align
pixel-perfectly when stacked as full-frame images):

    worry_jar_back.png    glass BACK wall only (faces pointing away)
    worry_jar_front.png   glass FRONT wall only (faces toward camera)
    worry_jar_cork.png    the cork alone, same frame
    worry_firefly_<variant>_<pose>.png   4 variants x 3 poses, tight frame

The layer split is done in the MATERIAL: a Backfacing mix collapses the
unwanted hemisphere to fully transparent. The glass here is deliberately
NON-transmissive (stylised alpha glass): the runtime draws live fireflies
between the two layers, so the glass must composite over arbitrary content —
the Stage-B lesson was that true transmission over a transparent film renders
black, and it would also bake the studio into the refraction.

The APPROVED Stage-B Cycles look (transmissive) remains the review target;
this export reproduces its highlights and rim with lights + Fresnel alpha.
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


def glass_layer_material(front: bool):
    """Stylised alpha glass showing only one hemisphere of the solid."""
    m = bpy.data.materials.new("GlassLayerF" if front else "GlassLayerB")
    m.use_nodes = True
    nt = m.node_tree
    out = nt.nodes["Material Output"]
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.88, 0.90, 1.0, 1)
    b.inputs["Roughness"].default_value = 0.04
    b.inputs["Metallic"].default_value = 0.0
    b.inputs["Specular IOR Level"].default_value = 0.8
    b.inputs["Coat Weight"].default_value = 0.3

    # Fresnel-driven alpha: near-clear face-on, stronger at grazing angles —
    # the same cue real glass gives, without transmission.
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.62
    ar = nt.nodes.new("ShaderNodeMapRange")
    ar.inputs["From Min"].default_value = 0.0
    ar.inputs["From Max"].default_value = 1.0
    # Presence range tuned for DARK underlays (the Calm night): face-on
    # glass must still read as material, and grazing edges must carry the
    # approved Stage-B rim. The original 0.055-0.62 vanished over black.
    ar.inputs["To Min"].default_value = 0.10
    ar.inputs["To Max"].default_value = 0.80
    nt.links.new(lw.outputs["Facing"], ar.inputs["Value"])
    nt.links.new(ar.outputs["Result"], b.inputs["Alpha"])

    # Hemisphere gate: unwanted side -> fully transparent.
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    trans = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(geo.outputs["Backfacing"], mix.inputs["Fac"])
    if front:
        nt.links.new(b.outputs["BSDF"], mix.inputs[1])       # frontfacing kept
        nt.links.new(trans.outputs["BSDF"], mix.inputs[2])
    else:
        nt.links.new(trans.outputs["BSDF"], mix.inputs[1])
        nt.links.new(b.outputs["BSDF"], mix.inputs[2])       # backfacing kept
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return m


def scene_setup(samples):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 12
    scene.cycles.transparent_max_bounces = 24
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Punchy"
    return scene


def jar_camera(scene):
    """The approved app-facing front framing (Stage B)."""
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.ortho_scale = 1.62
    cam = bpy.data.objects.new("Cam", cd)
    cam.location = (0.0, -3.4, 0.63)
    bpy.context.scene.collection.objects.link(cam)
    d = Vector((0, 0, 0.63)) - Vector(cam.location)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam


def render(scene, path, w, h):
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--samples", type=int, default=220)
    args = ap.parse_args(argv)
    os.makedirs(args.outdir, exist_ok=True)

    # ------------------------------------------------------ jar glass layers
    for front in (False, True):
        scene = scene_setup(args.samples)
        rig.setup_lights()
        # Dim neutral world so Fresnel alpha has something to reflect.
        w = bpy.data.worlds.new("W")
        scene.world = w
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.28
        glass = jar.build_glass()
        glass.data.materials.append(glass_layer_material(front))
        jar_camera(scene)
        name = "worry_jar_front.png" if front else "worry_jar_back.png"
        render(scene, os.path.join(args.outdir, name), 1100, 1400)

    # ---------------------------------------------------------------- cork
    scene = scene_setup(args.samples)
    rig.setup_lights()
    w = bpy.data.worlds.new("W2")
    scene.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.30
    cork = jar.build_cork()
    cork.location = (0.0, 0.0, jar.LIP_TOP)
    cork.data.materials.append(jar.cork_material())
    jar_camera(scene)
    render(scene, os.path.join(args.outdir, "worry_jar_cork.png"), 1100, 1400)

    # ------------------------------------------------------ firefly sprites
    # Three poses per variant. The side pose opens the wing V wider so the
    # pair still reads as TWO wings in profile.
    poses = {
        "threeq": dict(yaw=24, pitch=0, spread_boost=0),
        "side":   dict(yaw=86, pitch=0, spread_boost=14),
        "up":     dict(yaw=55, pitch=-18, spread_boost=6),
    }
    for vname, kw in ff.VARIANTS.items():
        for pname, p in poses.items():
            scene = scene_setup(max(140, args.samples - 60))
            rig.setup_world(scene, dark=True)
            rig.area_light("Rim", (1.6, 2.0, 1.4),
                           (math.radians(-55), 0, math.radians(28)),
                           size=2.0, energy=130, color=(0.66, 0.58, 1.0))
            rig.area_light("Key", (-1.8, -1.6, 1.8),
                           (math.radians(52), 0, math.radians(-40)),
                           size=2.4, energy=60, color=(1.0, 0.88, 0.72))
            k = dict(kw)
            k["wing_spread"] = k["wing_spread"] + p["spread_boost"]
            root = ff.build_firefly("Sprite", **k)
            root.rotation_euler = Euler((math.radians(p["pitch"]), 0,
                                         math.radians(p["yaw"])))
            cd = bpy.data.cameras.new("Cam")
            cd.type = "ORTHO"
            cd.ortho_scale = 1.7
            cam = bpy.data.objects.new("Cam", cd)
            cam.location = (0, -3.0, 0.05)
            scene.collection.objects.link(cam)
            d = Vector((0, 0, 0.05)) - Vector(cam.location)
            cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
            scene.camera = cam
            render(scene,
                   os.path.join(args.outdir, f"worry_firefly_{vname}_{pname}.png"),
                   680, 680)

    print("EXPORT complete")


if __name__ == "__main__":
    main()
