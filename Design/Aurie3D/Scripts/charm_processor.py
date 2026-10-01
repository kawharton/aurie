"""Aurie Charm Processor V1 — source .blend in, Aurie charm master out.

    blender --background --factory-startup --python-exit-code 1 \
        --python charm_processor.py -- --pilot [--mode processed|source]
    blender ... --python charm_processor.py -- --ids charm_food_cupcake_01

The source models are a CC0 low-poly pack. They are recognisable and cheap,
but they are not ours: flat shading, a different material system per pack,
arbitrary scale and orientation, leftover armatures. This turns them into a
consistent charm set that can sit beside the Blender Aurie without anyone
modelling anything new.

THE SOURCES ARE READ-ONLY. Each file is opened, mutated in memory, and saved
somewhere else; `--mode source` skips only the Aurie-specific steps so the
contact sheet compares like with like. Every run re-hashes the source
afterwards and fails loudly if a single byte moved.

PER CHARM
    1  inspect      what is actually in the scene
    2  keep meshes  cameras, lights, empties and armatures are dropped
    3  bake         modifiers (armature pose, geometry nodes) become geometry
    4  join         one object, one transform
    5  centre       on real geometry bounds, not the origin the artist left
    6  orient       largest face to camera, then the profile's 3/4 offset
    7  normalize    oriented front view fits the canonical charm box
    8  soften       profile-driven bevel + angle-limited shading
    9  materials    rebuilt into the Aurie family, hues preserved
   10  anchor       logical attachment point recorded, NO hardware baked
   11  render       Aurie light rig, Aurie camera, transparent background
   12  save         _PROCESSED/<id>.blend + _THUMBNAILS/<id>.png + record
"""

import argparse
import colorsys
import json
import math
import os
import sys
import time

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aurie_body_common as common  # noqa: E402
import charm_library as lib  # noqa: E402
import charm_profiles as P  # noqa: E402

PROCESSOR_VERSION = "v1"
RENDER_PX = 512
# The camera sees CHARM_BOX plus a margin, so nothing ever touches the edge
# and both contact sheets share one scale.
ORTHO = P.CHARM_BOX * 1.30
# Stands in for a colour the source cannot supply. Deliberately a flat,
# obviously-unfinished grey so a missing atlas never passes review as art.
UNRESOLVED_COLOUR = (0.32, 0.32, 0.32, 1.0)
# Texture atlases live beside the models. The .blend files point at the
# original author's drive, so every image is relinked by FILENAME here.
TEXTURE_DIRS = [lib.SOURCE_DIR / "Textures"]


def image_ok(img):
    """Whether an image actually resolves to a file Blender can read.

    NOT `has_data`: that stays False until the pixel buffer is loaded, so a
    freshly relinked atlas reports as missing even though its header has
    been read and its size is known. Testing `size` is the honest check —
    getting this wrong silently kept the flowers grey after their texture
    had already been found.
    """
    return img.has_data or img.size[0] > 0


def find_texture(filepath):
    """Locate an image the .blend cannot reach, and say how it was found.

    Matches on FILENAME only — exact, then case-insensitive. Nothing looser:
    a singular/plural rule was tried so "Flower.png" could pick up the
    supplied "Flowers.png", and across the whole library it never once
    produced a correct result. It mapped the one genuinely broken flower
    onto an atlas its UVs do not fit, rendering it black with purple
    speckle. Guessing which picture an artist meant is worse than saying
    the texture is missing.
    """
    base = os.path.basename(filepath)
    if not base:
        return None, "no filename"
    for d in TEXTURE_DIRS:
        if not d.exists():
            continue
        for cand in d.iterdir():
            if cand.name == base:
                return cand, "exact"
            if cand.name.lower() == base.lower():
                return cand, "exact (case-insensitive)"
    return None, "not found"


# ---------------------------------------------------------------------------
# colour
# ---------------------------------------------------------------------------

def lin_to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def restyle(rgba, prof):
    """Move a source colour into the Aurie palette without recolouring it.

    Hue is never touched — a banana stays yellow. Saturation is pulled part
    of the way toward a shared target so the set reads as one product, and
    the value is clamped because a near-black or blown-white charm loses its
    form entirely at 60 points across.
    """
    r, g, b = (lin_to_srgb(max(0.0, min(1.0, c))) for c in rgba[:3])
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    # The pull is scaled by how chromatic the colour already is. A flat mix
    # tripled the saturation of near-neutrals — the Husky's warm grey came
    # out olive — because a grey has a hue but no business being pushed
    # toward one. Genuinely colourful sources still get the full pull.
    if s > 0.02:
        s += (prof["sat_target"] - s) * prof["sat_mix"] * min(1.0, s / 0.25)
    v = max(prof["val_floor"], min(prof["val_ceiling"], v))
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return (srgb_to_lin(r), srgb_to_lin(g), srgb_to_lin(b),
            rgba[3] if len(rgba) > 3 else 1.0)


# ---------------------------------------------------------------------------
# scene surgery
# ---------------------------------------------------------------------------

def normalize_context():
    """Put a downloaded file into a state operators can actually run in.

    These are working files, not deliverables: Crown.blend was saved while
    its mesh was in Edit mode, which makes every object-mode operator fail
    its poll, and any source could ship with a collection excluded from the
    view layer. Both are fixed here rather than special-cased per charm.
    """
    fixes = []
    def unexclude(lc):
        if lc.exclude:
            lc.exclude = False
            fixes.append(f"unexcluded:{lc.name}")
        lc.hide_viewport = False
        for child in lc.children:
            unexclude(child)
    unexclude(bpy.context.view_layer.layer_collection)

    for ob in bpy.context.view_layer.objects:
        if ob.mode != "OBJECT":
            bpy.context.view_layer.objects.active = ob
            bpy.ops.object.mode_set(mode="OBJECT")
            fixes.append(f"objectmode:{ob.name}")
    active = next((o for o in bpy.context.view_layer.objects
                   if o.type == "MESH"), None)
    if active is not None:
        bpy.context.view_layer.objects.active = active
    return fixes


def strip_scene():
    """Keep the model's meshes; drop everything that is not the model.

    Hidden meshes are only dropped when the file ALSO contains visible ones
    — that pattern means the author parked an alternate. Clownfish.blend
    ships with its single mesh flagged hide_render, and treating that as
    "not part of the model" deletes the entire charm.
    """
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    visible = [o for o in meshes if not o.hide_render]
    keep = set(o.name for o in (visible or meshes))

    dropped = {}
    for ob in list(bpy.data.objects):
        if ob.name in keep:
            continue
        key = "MESH_hidden" if ob.type == "MESH" else ob.type
        dropped[key] = dropped.get(key, 0) + 1
        bpy.data.objects.remove(ob, do_unlink=True)
    return dict(dropped, keptHiddenMeshes=not visible)


def bake_and_join():
    """Evaluate modifiers into real geometry, then make it one object.

    Armature and geometry-nodes modifiers are converted rather than deleted:
    the pose the artist left IS the shape we want, and simply removing the
    modifier would snap a posed animal back to its rest position.
    """
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("no mesh objects left after stripping")
    for ob in meshes:
        ob.hide_set(False)
        ob.hide_select = False
        # Clownfish.blend ships with hide_render set. Keeping the object but
        # not clearing the flag renders a perfectly empty transparent PNG.
        ob.hide_render = False
    bpy.ops.object.select_all(action="DESELECT")
    for ob in meshes:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if any(ob.modifiers for ob in meshes):
        bpy.ops.object.convert(target="MESH")
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def bounds(ob):
    co = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co),
                 min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co),
                 max(c.z for c in co)))
    return lo, hi, hi - lo


def orient(ob, prof, override, adj=None):
    """Turn the model's biggest face toward the camera, then add the tilt.

    The camera looks along +y with +z up, so a model authored lying flat in
    the xy plane (keys, pizza slices, snowflakes) would render as a sliver.
    The rule: if one axis is much thinner than the other two, that thin axis
    is the one the viewer should look down. Otherwise keep the model upright
    and just turn its longer horizontal axis across the screen.
    """
    if override:
        ob.rotation_euler = (override.get("pitch", 0.0),
                             override.get("roll", 0.0),
                             override.get("yaw", 0.0))
        bpy.ops.object.transform_apply(rotation=True)
        return dict(rule="override", **override)

    _, _, ext = bounds(ob)
    flat = ext.z < 0.45 * min(ext.x, ext.y)
    steps = []
    if flat:
        ob.rotation_euler = (math.radians(90), 0.0, 0.0)
        bpy.ops.object.transform_apply(rotation=True)
        steps.append("stand-up")
    else:
        _, _, e = bounds(ob)
        if e.y > e.x:
            ob.rotation_euler = (0.0, 0.0, math.radians(90))
            bpy.ops.object.transform_apply(rotation=True)
            steps.append("yaw-90")
    # A flat charm turned 3/4 goes edge-on, so it only gets the pitch.
    adj = adj or {}
    yaw = (0.0 if flat else prof["yaw"]) + adj.get("yaw", 0.0)
    pitch = prof["pitch"] + adj.get("pitch", 0.0)
    ob.rotation_euler = (pitch, 0.0, yaw)
    bpy.ops.object.transform_apply(rotation=True)
    steps.append(f"pitch{math.degrees(pitch):.0f}"
                 f"/yaw{math.degrees(yaw):.0f}")
    return dict(rule="auto", flat=flat, steps=steps)


def centre_and_scale(ob, rel=1.0):
    """Fit the ORIENTED front view to the canonical box, aspect preserved.

    `rel` sizes one charm against the others — a long thin animal fills its
    box but still reads small beside a round one, so it can be nudged up.
    """
    lo, hi, ext = bounds(ob)
    span = max(ext.x, ext.z)               # what the camera actually sees
    k = P.CHARM_BOX * rel / span
    ob.scale = (k, k, k)
    bpy.ops.object.transform_apply(scale=True)
    lo, hi, ext = bounds(ob)
    ob.location -= (lo + hi) / 2.0         # geometry centre, not the origin
    bpy.ops.object.transform_apply(location=True)
    return k, [round(v, 4) for v in ext]


def crease_by_angle(ob, angle):
    """Mark genuinely sharp edges so subdivision cannot melt them.

    Catmull-Clark rounds everything it touches, which is right for an apple
    and wrong for a cupcake wrapper. Creasing every edge above `angle`
    first means the subdivision smooths the body and leaves the rim, the
    stem junction and the base exactly where the artist put them.
    """
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    elay = (bm.edges.layers.float.get("crease_edge")
            or bm.edges.layers.float.new("crease_edge"))
    vlay = (bm.verts.layers.float.get("crease_vert")
            or bm.verts.layers.float.new("crease_vert"))
    sharp = set()
    for e in bm.edges:
        # A boundary edge has one face and so no dihedral at all; it is sharp
        # by definition, and leaving it uncreased pulls open rims inward.
        if len(e.link_faces) < 2 or e.calc_face_angle(0.0) >= angle:
            e[elay] = 1.0
            sharp.add(e.index)
    # Creased EDGES alone are not enough: Catmull-Clark still rounds the
    # CORNERS where creased edges turn, unless the vertex is creased too.
    # Three-way corners are the obvious case (a box), but the one that
    # actually bit was two-way: every vertex of the first aid kit's cross
    # has exactly two creased edges, so a ">= 3" rule creased none of them
    # and the Swiss cross subdivided into a blob. A vertex is a corner when
    # its creased edges TURN; along a straight creased run they do not.
    nv = 0
    for v in bm.verts:
        ce = [e for e in v.link_edges if e.index in sharp]
        corner = len(ce) >= 3
        if len(ce) == 2:
            d0 = (ce[0].other_vert(v).co - v.co).normalized()
            d1 = (ce[1].other_vert(v).co - v.co).normalized()
            corner = d0.dot(d1) > -0.87          # turns more than ~30 deg
        if corner:
            v[vlay] = 1.0
            nv += 1
    bm.to_mesh(me)
    bm.free()
    return len(sharp), nv


def soften(ob, prof):
    """Profile-driven softening. Subdivision is OPT-IN per profile.

    An angle threshold alone cannot separate "round" from "creased" on
    these meshes: the donut's neighbouring faces meet at a median of 51
    degrees, so any threshold low enough to keep a wrapper rim crisp also
    facets the torus. Objects that are supposed to be round therefore get
    real geometry — crease the sharp edges, then subdivide — rather than a
    shading trick that leaves a twelve-sided silhouette.
    """
    applied = []
    if prof.get("subsurf"):
        ce, cv = crease_by_angle(ob, prof["crease_angle"])
        mod = ob.modifiers.new("CharmSubsurf", "SUBSURF")
        mod.levels = mod.render_levels = prof["subsurf"]
        mod.use_creases = True
        # Open boundaries (a pizza slice's cut faces) must keep
        # their corners instead of being pulled into a lozenge.
        mod.boundary_smooth = 'PRESERVE_CORNERS'
        bpy.ops.object.modifier_apply(modifier=mod.name)
        applied.append(f"subsurf {prof['subsurf']} (creased {ce} edges >"
                       f"{math.degrees(prof['crease_angle']):.0f}deg, "
                       f"{cv} corner verts)")

    if prof["bevel_width"] > 0:
        mod = ob.modifiers.new("CharmBevel", "BEVEL")
        mod.width = prof["bevel_width"] * P.CHARM_BOX
        mod.segments = prof["bevel_segments"]
        mod.limit_method = "ANGLE"
        mod.angle_limit = prof["bevel_angle"]
        mod.miter_outer = "MITER_ARC"
        mod.use_clamp_overlap = True           # never let a bevel eat a thin arm
        bpy.ops.object.modifier_apply(modifier=mod.name)
        applied.append(f"bevel {prof['bevel_width']:.3f}x"
                       f"{prof['bevel_segments']}")

    me = ob.data
    if prof["smooth_angle"] is None:
        me.polygons.foreach_set("use_smooth", [False] * len(me.polygons))
        applied.append("faceted")
    else:
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
        # Edge split gives exactly the angle-limited shading the profile
        # asks for and behaves identically on every Blender version.
        mod = ob.modifiers.new("CharmSmooth", "EDGE_SPLIT")
        mod.split_angle = prof["smooth_angle"]
        mod.use_edge_angle = True
        mod.use_edge_sharp = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
        applied.append(f"smooth<{math.degrees(prof['smooth_angle']):.0f}deg")
    me.update()
    return applied


def upstream_image(sock):
    """The image feeding a colour socket, however indirectly.

    Foliage in this pack does not wire a texture straight into a shader: the
    leaf and petal materials run it through a Mix node that also drives an
    alpha cutout. Only accepting a DIRECT image link made those materials
    fall back to default white, which is why the trees and petals came out
    colourless.
    """
    stack = [l.from_node for l in sock.links]
    seen = set()
    while stack:
        node = stack.pop(0)
        if node.name in seen:
            continue
        seen.add(node.name)
        if node.type == "TEX_IMAGE":
            return node
        # Walk through colour plumbing only; never cross into another shader.
        if node.type.startswith("BSDF") or node.type in ("MIX_SHADER",
                                                         "ADD_SHADER"):
            continue
        for inp in node.inputs:
            stack += [l.from_node for l in inp.links]
    return None


def base_colour_of(mat):
    """The source colour, whatever shader system the pack happened to use.

    This WALKS BACK FROM THE MATERIAL OUTPUT instead of taking the first
    shader node it finds. The packs are full of disconnected leftovers —
    Cupcake's DarkBrown carries an orphan green Diffuse BSDF that node
    order happens to list first — and reading one of those turns a brown
    cupcake green. Only what is actually wired to the output is the model's
    real colour.
    """
    if not mat.use_nodes or mat.node_tree is None:
        return list(mat.diffuse_color), None, 0

    nt = mat.node_tree
    out = next((n for n in nt.nodes
                if n.type == "OUTPUT_MATERIAL" and n.is_active_output),
               next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"),
                    None))
    reached, stack = [], []
    if out is not None:
        sock = out.inputs.get("Surface")
        stack = [l.from_node for l in sock.links] if sock else []
    seen = set()
    while stack:
        node = stack.pop(0)
        if node.name in seen:
            continue
        seen.add(node.name)
        if node.type in ("BSDF_PRINCIPLED", "BSDF_DIFFUSE"):
            reached.append(node)
        for inp in node.inputs:
            stack += [l.from_node for l in inp.links]

    orphans = sum(1 for n in nt.nodes
                  if n.type in ("BSDF_PRINCIPLED", "BSDF_DIFFUSE")
                  and n.name not in seen)
    # Principled wins over Diffuse: it is the node the pack actually authors.
    reached.sort(key=lambda n: 0 if n.type == "BSDF_PRINCIPLED" else 1)
    for node in reached:
        sock = node.inputs.get("Base Color") or node.inputs.get("Color")
        if sock is None:
            continue
        if sock.is_linked:
            tex = upstream_image(sock)
            if tex is not None:
                return None, tex, orphans
            continue
        return list(sock.default_value), None, orphans
    return [0.8, 0.8, 0.8, 1.0], None, orphans


def restyle_materials(ob, prof, overrides=None):
    """Rebuild every slot in the Aurie material family.

    Source packs ship fresnel-emission rims, stray transparent mixes and
    per-pack metallic conventions. Those are what make an imported model
    look imported, so each material is rebuilt from ONE thing — its colour
    (or its palette texture) — onto the same plush Principled setup the
    Aurie body uses.
    """
    report = []
    for slot in ob.material_slots:
        mat = slot.material
        if mat is None:
            continue
        colour, tex, orphans = base_colour_of(mat)
        img = tex.image if tex else None

        mat.use_nodes = True
        nt = mat.node_tree
        for node in list(nt.nodes):
            nt.nodes.remove(node)
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out.location, bsdf.location = (300, 0), (0, 0)
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

        if img is not None and image_ok(img):
            # A palette atlas carries several colours through the UVs; the
            # only correct move is to keep it and restyle around it.
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = img
            t.interpolation = "Closest"
            t.location = (-320, 0)
            nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
            # Leaves and petals are flat quads whose SHAPE lives in the
            # texture's alpha. Dropping that link turned a maple canopy into
            # a bunch of solid white polygons and a ring of petals into a
            # faceted ball. Opaque textures carry alpha 1 and are unaffected.
            if "Alpha" in bsdf.inputs:
                nt.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
            source = "texture"
        elif img is not None:
            # The pack shipped the model but not its atlas, and the path
            # points at the original author's machine. Inventing a colour
            # here would hide a missing asset behind a plausible render, so
            # the charm goes out in flagged placeholder grey instead.
            common._set(bsdf, UNRESOLVED_COLOUR, "Base Color")
            source = "texture-missing"
        elif mat.name in (overrides or {}):
            # Hand-authored art direction for one slot. Used as given, with
            # no saturation or value shaping, because the whole point is
            # that a person chose this exact colour.
            common._set(bsdf, common._srgb(overrides[mat.name].lstrip("#")),
                        "Base Color")
            source = "override"
        else:
            common._set(bsdf, restyle(colour, prof), "Base Color")
            source = "colour"

        common._set(bsdf, prof["roughness"], "Roughness")
        common._set(bsdf, prof["specular"], "Specular IOR Level", "Specular")
        common._set(bsdf, prof["sheen"], "Sheen Weight", "Sheen")
        common._set(bsdf, 0.50, "Sheen Roughness")
        common._set(bsdf, 0.0, "Metallic")      # one metallic system: none
        report.append(dict(name=mat.name, source=source,
                           colour=([round(c, 4) for c in colour[:3]]
                                   if colour else None),
                           orphanShaderNodesIgnored=orphans))
    return report


def anchor_for(ob, slot):
    """Where a ring would go — recorded, never built.

    V1 bakes no hardware. It stores a point ON the surface (not on the
    bounding box, which would float in mid-air on anything curved) plus the
    direction that surface faces, so a later pass can attach whatever the
    charm type turns out to need.
    """
    rule = P.ANCHOR_RULES.get(slot, P.ANCHOR_RULES["HANGING"])
    axis, sign = rule["axis"][1], (1 if rule["axis"][0] == "+" else -1)
    idx = "xyz".index(axis)
    others = [i for i in range(3) if i != idx]

    co = [ob.matrix_world @ v.co for v in ob.data.vertices]
    _, _, ext = bounds(ob)
    # Only consider vertices near the charm's centre line, so the anchor
    # lands on the middle of the face rather than on a corner.
    tol = 0.18 * max(ext)
    near = [c for c in co
            if all(abs(c[i]) <= tol for i in others)] or co
    best = max(near, key=lambda c: sign * c[idx])
    return dict(type=slot,
                position=[round(best.x, 4), round(best.y, 4),
                          round(best.z, 4)],
                normal=list(rule["normal"]),
                space="charm_local_normalized",
                hardware="none")


# ---------------------------------------------------------------------------
# stage
# ---------------------------------------------------------------------------

def build_stage(scene, samples):
    """The approved Aurie rig, unchanged, so charms are lit in one studio."""
    def light(name, loc, size, power, colour):
        data = bpy.data.lights.new(name, "AREA")
        data.shape, data.size = "DISK", size
        data.energy, data.color = power, colour
        ob = bpy.data.objects.new(name, data)
        ob.location = loc
        ob.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)) \
            .to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(ob)

    light("Key", (-3.0, -3.0, 4.0), 3.0, common.KEY_POWER, (1.0, 0.97, 0.92))
    light("Fill", (3.5, -2.5, 1.2), 4.0, common.FILL_POWER, (0.90, 0.95, 1.0))
    light("Rim", (0.8, 3.5, 3.2), 2.0, common.RIM_POWER, (1.0, 1.0, 1.0))

    world = bpy.data.worlds.new("CharmWorld")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Strength"].default_value = 0.2
    scene.world = world

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ORTHO
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0.0, -10.0, 0.0)
    cam.rotation_euler = (math.radians(90), 0.0, 0.0)
    scene.collection.objects.link(cam)
    scene.camera = cam

    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = RENDER_PX
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"


# ---------------------------------------------------------------------------

def process(rec, mode, samples, out_png, out_blend):
    cfg = P.for_charm(rec["id"], rec["category"])
    prof_name, prof = cfg["profile"], cfg["prof"]
    slot, override, adj = cfg["attach"], cfg["orient"], cfg["adj"]
    src = lib.SOURCE_DIR / rec["sourceFilename"]
    t0 = time.time()

    bpy.ops.wm.open_mainfile(filepath=str(src))
    # Several sources still point at the original author's drive. Autopack
    # would abort the save on the first unreachable one, so images are
    # packed deliberately and whatever cannot be resolved is RECORDED.
    bpy.data.use_autopack = False
    context_fixes = normalize_context()
    missing_tex, relinked = [], []
    for img in bpy.data.images:
        if not img.users or img.name == "Render Result":
            continue
        if not image_ok(img):
            img.reload()
        if not image_ok(img):
            found, how = find_texture(img.filepath)
            if found is not None:
                relinked.append(dict(image=img.name,
                                     wanted=os.path.basename(img.filepath),
                                     resolved=found.name, match=how))
                img.filepath = str(found)
                img.reload()
        if image_ok(img):
            img.pack()
        else:
            missing_tex.append(dict(name=img.name, path=img.filepath))

    before = dict(objects=len(bpy.data.objects),
                  kinds={k: sum(1 for o in bpy.data.objects if o.type == k)
                         for k in {o.type for o in bpy.data.objects}})
    dropped = strip_scene()
    ob = bake_and_join()
    before["polys"] = len(ob.data.polygons)

    o = orient(ob, prof, override, adj)
    k, ext = centre_and_scale(ob, cfg["scale"])

    softened, materials = [], []
    if mode == "processed":
        softened = soften(ob, prof)
        materials = restyle_materials(ob, prof, cfg["colours"])
    anchor = anchor_for(ob, slot)

    ob.name = rec["id"]
    ob.data.name = rec["id"]
    scene = bpy.context.scene
    build_stage(scene, samples)
    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)

    if out_blend:
        # Re-running the processor should replace a master, not accumulate
        # .blend1 backups of it next to the real thing.
        bpy.context.preferences.filepaths.save_version = 0
        # Guard: the only writable destination is the library.
        assert str(lib.LIBRARY) in out_blend and "Charms" not in out_blend, \
            f"refusing to save outside the library: {out_blend}"
        bpy.ops.wm.save_as_mainfile(filepath=out_blend, compress=True,
                                    copy=True)

    unresolved = [m["name"] for m in materials
                  if m["source"] == "texture-missing"]
    # A missing image only MATTERS when a material was getting its colour
    # from it. Almost every source in this pack carries a dead reference to
    # the original author's drive that nothing reads; flagging those as
    # incomplete would bury the one charm that genuinely lost its palette.
    return dict(
        processorVersion=PROCESSOR_VERSION, mode=mode, profile=prof_name,
        seconds=round(time.time() - t0, 1),
        sourceComplete=not missing_tex,
        texturesRelinked=relinked,
        colourComplete=not unresolved,
        missingTextures=missing_tex,
        unresolvedMaterials=unresolved,
        source=dict(objects=before["objects"], kinds=before["kinds"],
                    polys=before["polys"], droppedObjects=dropped,
                    contextFixes=context_fixes),
        relativeScale=cfg["scale"],
        geometry=dict(polysAfter=len(ob.data.polygons), scaleApplied=round(k, 5),
                      extentsNormalized=ext, orientation=o, softening=softened),
        materials=materials, attachment=anchor)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", default="")
    ap.add_argument("--pilot", action="store_true")
    ap.add_argument("--batch", default="")
    ap.add_argument("--allow-cut", action="store_true",
                    help="process a charm that review already rejected")
    ap.add_argument("--mode", default="processed",
                    choices=["processed", "source"])
    ap.add_argument("--samples", type=int, default=128)
    ap.add_argument("--source-outdir", default="")
    args = ap.parse_args(argv)

    manifest = lib.load_manifest()
    by_id = {r["id"]: r for r in manifest["charms"]}
    ids = [i for i in args.ids.split(",") if i]
    if args.batch:
        ids += lib.BATCHES[args.batch]
    elif args.pilot:
        ids += lib.PILOT
    if not ids:
        sys.exit("nothing to do: pass --ids, --batch or --pilot")

    for cid in ids:
        rec = by_id[cid]
        if not rec["sourcePresent"]:
            print(f"SKIP {cid}: source missing")
            continue
        # The batch lists exclude cut charms, but --ids goes straight past
        # that and silently puts a rejected charm back in the library.
        if cid in lib.CUT and not args.allow_cut:
            print(f"SKIP {cid}: cut in review ({lib.CUT[cid]}) "
                  f"— pass --allow-cut to override")
            continue
        if args.mode == "source":
            outdir = args.source_outdir or "/tmp"
            os.makedirs(outdir, exist_ok=True)
            png, blend = os.path.join(outdir, f"{cid}_source.png"), ""
        else:
            png = str(lib.LIBRARY / f"_THUMBNAILS/{cid}.png")
            blend = str(lib.LIBRARY / f"_PROCESSED/{cid}.blend")

        result = process(rec, args.mode, args.samples, png, blend)

        # The sources are read-only; prove it every single time.
        src = lib.SOURCE_DIR / rec["sourceFilename"]
        digest = lib.sha256(src)
        if digest != rec["sourceSHA256"]:
            sys.exit(f"FATAL: source changed during processing: {src}")

        if args.mode == "processed":
            rec.update(processed=True,
                       processedFilename=f"_PROCESSED/{cid}.blend",
                       thumbnailFilename=f"_THUMBNAILS/{cid}.png",
                       processorVersion=PROCESSOR_VERSION,
                       processing=result, attachment=result["attachment"])
            path = lib.LIBRARY / rec["category"] / f"{cid}.json"
            path.write_text(json.dumps(
                dict(id=cid, displayName=rec["displayName"],
                     category=rec["category"],
                     sourceFilename=rec["sourceFilename"],
                     sourceSHA256=rec["sourceSHA256"],
                     **result), indent=2) + "\n")

        g = result["geometry"]
        flag = "" if result["colourComplete"] else \
            f"  <- COLOUR LOST, missing {result['missingTextures'][0]['name']}"
        print(f"CHARM OK {cid:32s} {result['profile']:10s} "
              f"{result['source']['polys']:5d}->{g['polysAfter']:5d}p  "
              f"ext {g['extentsNormalized']}  "
              f"{result['attachment']['type']:10s} {result['seconds']}s{flag}")

    if args.mode == "processed":
        manifest["charms"] = list(by_id.values())
        manifest["counts"]["processed"] = sum(1 for r in by_id.values()
                                              if r["processed"])
        lib.save_manifest(manifest)
        print(f"manifest updated: {manifest['counts']['processed']} processed")
    print("AURIE CHARMS DONE")


if __name__ == "__main__":
    main()
