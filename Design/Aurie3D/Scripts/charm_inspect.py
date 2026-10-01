"""Read-only survey of the charm sources — what is actually in each .blend.

    blender --background --factory-startup --python charm_inspect.py -- \
        --ids charm_animal_fox_01,... [--out report.json]

Opens each source, reports objects / meshes / materials / dimensions, and
QUITS. Nothing is saved, so the sources cannot be modified by this pass.
The output drives the processing profiles: guessing what a model contains
is how you end up bevelling a snowflake into a blob.
"""

import argparse
import json
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import charm_library as lib  # noqa: E402


def survey(path):
    bpy.ops.wm.open_mainfile(filepath=path)
    scene = bpy.context.scene
    kinds, meshes, mats = {}, [], {}
    for ob in scene.objects:
        kinds[ob.type] = kinds.get(ob.type, 0) + 1
        if ob.type != "MESH":
            continue
        me = ob.data
        dims = [round(d, 4) for d in ob.dimensions]
        meshes.append(dict(name=ob.name, verts=len(me.vertices),
                           polys=len(me.polygons), dims=dims,
                           parent=ob.parent.name if ob.parent else None,
                           modifiers=[m.type for m in ob.modifiers],
                           shade_smooth=any(p.use_smooth
                                            for p in me.polygons),
                           uv_layers=len(me.uv_layers),
                           slots=[s.material.name for s in ob.material_slots
                                  if s.material]))
    for m in bpy.data.materials:
        if not m.users:
            continue
        rec = dict(name=m.name, nodes=bool(m.use_nodes), image_textures=0)
        if m.use_nodes:
            b = next((n for n in m.node_tree.nodes
                      if n.type == "BSDF_PRINCIPLED"), None)
            rec["image_textures"] = sum(1 for n in m.node_tree.nodes
                                        if n.type.startswith("TEX_IMAGE"))
            rec["node_types"] = sorted({n.type for n in m.node_tree.nodes})
            if b:
                def val(name):
                    s = b.inputs.get(name)
                    if s is None:
                        return None
                    if s.is_linked:
                        return "LINKED"
                    v = s.default_value
                    try:
                        return [round(x, 3) for x in v]
                    except TypeError:
                        return round(v, 3)
                rec.update(base_color=val("Base Color"),
                           metallic=val("Metallic"),
                           roughness=val("Roughness"),
                           emission=val("Emission Strength"))
        mats[m.name] = rec

    # Whole-model bounds from evaluated geometry, ignoring non-mesh objects.
    dg = bpy.context.evaluated_depsgraph_get()
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for ob in scene.objects:
        if ob.type != "MESH":
            continue
        ev = ob.evaluated_get(dg)
        for corner in ev.bound_box:
            w = ev.matrix_world @ Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    size = [round(hi[i] - lo[i], 4) for i in range(3)] if hi[0] > -1e8 else None

    return dict(objects=sum(kinds.values()), kinds=kinds,
                meshes=meshes, materials=mats,
                total_verts=sum(m["verts"] for m in meshes),
                total_polys=sum(m["polys"] for m in meshes),
                world_size=size,
                images=[i.name for i in bpy.data.images if i.users
                        and i.name != "Render Result"],
                collections=[c.name for c in bpy.data.collections])


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", default=",".join(lib.PILOT))
    ap.add_argument("--out", default="")
    args = ap.parse_args(argv)

    manifest = lib.load_manifest()
    by_id = {r["id"]: r for r in manifest["charms"]}
    out = {}
    for cid in args.ids.split(","):
        rec = by_id[cid]
        src = lib.SOURCE_DIR / rec["sourceFilename"]
        if not src.exists():
            print(f"MISSING {cid}")
            continue
        out[cid] = survey(str(src))
        s = out[cid]
        print(f"\n=== {cid}  ({rec['sourceFilename']}) ===")
        print(f"    objects {s['objects']} {s['kinds']}  "
              f"verts {s['total_verts']}  polys {s['total_polys']}")
        print(f"    size    {s['world_size']}")
        print(f"    meshes  " + ", ".join(
            f"{m['name']}({m['polys']}p{'S' if m['shade_smooth'] else 'F'}"
            f"{'M' + str(len(m['modifiers'])) if m['modifiers'] else ''})"
            for m in s["meshes"][:8])
            + (f" +{len(s['meshes']) - 8} more" if len(s["meshes"]) > 8 else ""))
        for name, m in s["materials"].items():
            print(f"    mat     {name:22s} base={m.get('base_color')} "
                  f"metal={m.get('metallic')} rough={m.get('roughness')} "
                  f"tex={m['image_textures']}")
    if args.out:
        with open(args.out, "w") as fh:
            json.dump(out, fh, indent=2)
        print(f"\nwrote {args.out}")


if __name__ == "__main__":
    main()
