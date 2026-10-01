"""Fast Cycles PREVIEW of the Worry Jar — proportions and materials only.

    blender --background --factory-startup --python preview_worry_jar.py -- \
        --outdir <dir> [--samples 56]

Deliberately still Cycles, not EEVEE: the whole question at this stage is
whether the glass reads as glass, and EEVEE's screen-space approximation
would not be representative. Cost is cut by sample count, resolution and
bounce depth instead — transmission bounces stay high enough (12) that the
thick base and lip still resolve, since those are exactly the areas being
judged.

Writes ONLY the two files it names. It never deletes anything.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_worry_jar as jar          # noqa: E402
import render_worry_jar_review as rig  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--samples", type=int, default=56)
    args = ap.parse_args(argv)
    os.makedirs(args.outdir, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = True
    # Preview depth: plenty for glass, far cheaper than the review pass.
    scene.cycles.max_bounces = 8
    scene.cycles.transmission_bounces = 12
    scene.cycles.transparent_max_bounces = 8
    scene.cycles.diffuse_bounces = 2
    scene.cycles.glossy_bounces = 4
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Punchy"

    glass = jar.build_glass()
    cork = jar.build_cork()
    cork.location = (0.0, 0.0, jar.LIP_TOP)
    glass.data.materials.append(jar.glass_material())
    cork.data.materials.append(jar.cork_material())

    # Dark plum world, so the preview already shows the jar against something
    # close to the Calm background rather than a neutral studio.
    rig.setup_world(scene, dark=True)
    rig.setup_lights()

    # The jar is 1.18 tall plus ~0.08 of cork above the lip, so it needs a
    # taller frame and a higher aim point than the squat first version did.
    rig.make_camera(scene, (0.0, -3.4, 0.63), look_at=Vector((0, 0, 0.63)),
                    ortho=1.62)
    rig.render(scene, os.path.join(args.outdir, "worry_jar_preview_front.png"),
               700, 890, transparent=False)

    rig.make_camera(scene, (-2.05, -2.5, 1.62), look_at=Vector((0, 0, 0.60)),
                    ortho=1.72)
    rig.render(scene, os.path.join(args.outdir, "worry_jar_preview_3q.png"),
               760, 890, transparent=False)

    dg = bpy.context.evaluated_depsgraph_get()
    for ob in (glass, cork):
        me = ob.evaluated_get(dg).to_mesh()
        bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
        print(f"STAT {ob.name} tris={sum(len(p.vertices)-2 for p in me.polygons)} "
              f"verts={len(me.vertices)} "
              f"h={max(v.z for v in bb)-min(v.z for v in bb):.3f} "
              f"w={max(v.x for v in bb)-min(v.x for v in bb):.3f}")


if __name__ == "__main__":
    main()
