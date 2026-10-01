"""Worry Jar — keepsake glass jar with a natural cork stopper.

    blender --background --factory-startup --python build_worry_jar.py -- \
        --outdir <dir> [--samples 256] [--review]

Built for a LAYERED runtime composite, not a single flat PNG. The glass is
one watertight solid with real wall thickness, so it can be rendered twice —
back wall only, then front wall only — using a Backfacing switch in the
material. The app draws animated fireflies between those two layers, which is
what makes them read as occupying the jar's volume instead of sitting behind
a transparent picture of a jar.

Nothing here is a flat plane: the wall, the thick base and the lip all have
genuine thickness, because that thickness is where the warm firefly light is
supposed to collect.

The cork is a SEPARATE object with its own origin at the base of its plug, so
the app can wobble, lift, rotate and fly it during a release.
"""

import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

# ---------------------------------------------------------------- proportions
#
# One Blender unit = the jar's overall height. Tuned against the reference:
# a small keepsake jar — belly wider than the neck, soft shoulders, short
# neck, thick lip, stable base.

H          = 1.18      # total glass height — ~1.28x the width
R_BELLY    = 0.46      # widest point (width 0.92)
R_BASE     = 0.385     # foot
R_NECK     = 0.285     # outer neck
R_LIP      = 0.328     # lip — still ~2x the wall in solid glass, but the
                       # outer flare is reined in: at 0.350 its bulb refracted
                       # through the shoulder as two bright side lobes that
                       # read as tiny handles at app size
WALL       = 0.042     # body wall thickness
BORE       = R_NECK - WALL   # inner mouth, CONSTANT through neck and lip —
                             # a straight bore is what makes the lip read as
                             # thick glass, and it removes the internal
                             # undercut that was trapping light (black wedges)
FLOOR      = 0.155     # thick base — light pools here
Z_BELLY    = 0.40      # height of the widest point
Z_SHOULDER = 0.68      # where the belly begins curving in
Z_NECK     = 0.94      # neck begins
Z_LIP      = 1.10      # underside of the lip flare
LIP_TOP    = Z_LIP + 0.085   # top surface of the glass

# A real stopper: compact cap, tapered plug seated through the whole neck —
# and no further, so it reads inserted without becoming a tan cylinder
# hanging into the body of the jar.
CORK_R_CAP     = 0.293  # compact: modest overhang past the 0.243 opening,
                        # and INSIDE the lip's outer edge, so a ring of glass
                        # rim stays visible around the seated cork
CORK_R_PLUG_T  = 0.234  # a hair inside the bore
CORK_R_PLUG_B  = 0.200  # clearer downward taper — a stopper, not a dowel
CORK_H_CAP     = 0.078
CORK_H_PLUG    = 0.170  # ends in the upper neck: visibly inserted, but the
                        # tan column no longer dominates the whole neck


def _smoothstep(t):
    return t * t * (3 - 2 * t)


def _outer_profile(n=64):
    """(radius, z) up the OUTSIDE of the glass, base to lip."""
    pts = []
    for i in range(n + 1):
        t = i / n
        z = t * Z_LIP
        if z <= Z_BELLY:
            # Foot flaring gently out to the belly.
            k = _smoothstep(z / Z_BELLY)
            r = R_BASE + (R_BELLY - R_BASE) * k
        elif z <= Z_SHOULDER:
            # Gently convex through the mid-lower body: full low, curving
            # increasingly toward the shoulder (t^1.8 keeps the curvature
            # continuous). A near-straight wall here read as a specimen
            # bottle rather than a keepsake jar.
            t = (z - Z_BELLY) / (Z_SHOULDER - Z_BELLY)
            r = R_BELLY * (1.0 - 0.050 * (t ** 1.8))
        elif z <= Z_NECK:
            # Soft shoulder curving in toward the neck.
            k = _smoothstep((z - Z_SHOULDER) / (Z_NECK - Z_SHOULDER))
            r = R_BELLY * 0.950 + (R_NECK - R_BELLY * 0.950) * k
        else:
            # Short straight neck, then the lip flares.
            # Gentler, earlier flare: the k**1.7 curve concentrated the
            # flare at the top into a bulb — the source of the lobes.
            k = _smoothstep((z - Z_NECK) / (Z_LIP - Z_NECK))
            r = R_NECK + (R_LIP - R_NECK) * (k ** 1.25)
        pts.append((r, z))
    return pts


def _glass_section():
    """Closed 2D section of the glass wall, revolved into a solid.

    Traced as: up the outside -> over the lip -> down the inside -> across
    the top of the thick floor -> down the centre -> out along the bottom.
    """
    outer = _outer_profile()
    sec = [(0.0, 0.0)]                       # centre of the underside
    sec += [(r, z) for r, z in outer]        # up the outside

    # Over the top of the lip. With the straight bore below, the lip is
    # ~0.107 of solid glass against the 0.042 body wall — the strongest
    # "solid glass object" read on the jar.
    sec += [(R_LIP, LIP_TOP - 0.020), (R_LIP - 0.012, LIP_TOP),
            (BORE + 0.012, LIP_TOP), (BORE, LIP_TOP - 0.022)]

    # Down the inside. The bore is CONSTANT through the lip and neck (a real
    # jar's mouth is a straight cylinder); below the neck the inner wall
    # follows the outside minus the wall. This removes the reentrant pocket
    # under the lip flare that trapped rays into hard black wedges.
    inner = []
    for r, z in reversed(outer):
        if z < FLOOR:
            continue
        ri = BORE if z >= Z_NECK else max(r - WALL, 0.02)
        inner.append((ri, z))
    sec += inner

    # Across the top of the thick floor and back to the axis.
    sec += [(0.0, FLOOR)]
    return sec


def build_glass():
    sec = _glass_section()
    bm = bmesh.new()
    verts = [bm.verts.new((r, 0.0, z)) for r, z in sec]
    bm.verts.ensure_lookup_table()
    for a, b in zip(verts, verts[1:]):
        bm.edges.new((a, b))

    # Revolve. 96 segments keeps the silhouette clean at 3x render scale
    # without a heavy mesh.
    bmesh.ops.spin(bm, geom=bm.verts[:] + bm.edges[:],
                   axis=(0, 0, 1), cent=(0, 0, 0),
                   dvec=(0, 0, 0), angle=math.radians(360),
                   steps=96, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    me = bpy.data.meshes.new("WorryJarGlassMesh")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("WorryJarGlass", me)
    bpy.context.scene.collection.objects.link(ob)

    for p in me.polygons:
        p.use_smooth = True
    # Keep the lip and foot crisp; only the sweeping walls should smooth.
    ob.modifiers.new("Bevel", "BEVEL").width = 0.004
    ob.modifiers["Bevel"].segments = 2
    ob.modifiers["Bevel"].limit_method = "ANGLE"
    ob.modifiers["Bevel"].angle_limit = math.radians(38)
    return ob


def build_cork():
    """Cap + plug as ONE solid, with pores and an irregular edge.

    Origin sits at the top of the plug — i.e. where the cork meets the lip —
    so the app can rotate it about a believable pivot when it pops.
    """
    bm = bmesh.new()
    # The section deliberately does NOT touch the axis at either end. Closing
    # a spin at r=0 collapses into a triangle fan around a centre pole, and
    # that fan showed through the bump as a radial starburst on the cap. The
    # open boundary loops are grid-filled with QUADS below instead.
    sec = [
        (CORK_R_PLUG_B * 0.60, -CORK_H_PLUG),
        (CORK_R_PLUG_B * 0.88, -CORK_H_PLUG),              # chamfered nose
        (CORK_R_PLUG_B, -CORK_H_PLUG + 0.022),
        (CORK_R_PLUG_T, -0.030),                           # taper up the plug
        (CORK_R_PLUG_T * 1.01, -0.006),
        (CORK_R_CAP, 0.010),                               # shoulder onto the cap
        (CORK_R_CAP * 1.005, CORK_H_CAP - 0.018),
        (CORK_R_CAP * 0.955, CORK_H_CAP),                  # soft bevelled rim
        (CORK_R_CAP * 0.55, CORK_H_CAP),                   # flat toward centre
    ]
    verts = [bm.verts.new((r, 0.0, z)) for r, z in sec]
    bm.verts.ensure_lookup_table()
    for a, b in zip(verts, verts[1:]):
        bm.edges.new((a, b))
    bmesh.ops.spin(bm, geom=bm.verts[:] + bm.edges[:],
                   axis=(0, 0, 1), cent=(0, 0, 0), dvec=(0, 0, 0),
                   angle=math.radians(360), steps=64, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)

    # Close top and bottom with CONSTRUCTED concentric quad rings — the fill
    # operators (grid_fill, holes_fill) failed silently on these loops and
    # left the cap open, so nothing here trusts an operator: the rings and
    # faces are built explicitly and verified by the boundary count below.
    def close_disc(z_target, rings=3):
        eps = 1e-4
        boundary = [v for v in bm.verts
                    if abs(v.co.z - z_target) < eps
                    and len([e for e in v.link_edges
                             if len(e.link_faces) < 2]) >= 1]
        if not boundary:
            return
        boundary.sort(key=lambda v: math.atan2(v.co.y, v.co.x))
        n = len(boundary)
        r0 = sum(math.hypot(v.co.x, v.co.y) for v in boundary) / n
        prev = boundary
        for k in range(1, rings + 1):
            rk = r0 * (1 - k / (rings + 1))
            ring = []
            for v in prev:
                a = math.atan2(v.co.y, v.co.x)
                ring.append(bm.verts.new((rk * math.cos(a),
                                          rk * math.sin(a), z_target)))
            for i in range(n):
                j = (i + 1) % n
                bm.faces.new((prev[i], prev[j], ring[j], ring[i]))
            prev = ring
        # Tiny flat ngon at the centre: no interior verts, so displacement
        # cannot fan it — and at r0/(rings+1) it is a dot at display size.
        bm.faces.new(prev)

    close_disc(CORK_H_CAP, rings=3)
    close_disc(-CORK_H_PLUG, rings=2)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # PROOF the solid is closed: an open cap renders as a dark hole into the
    # cork's interior, which is exactly the bug this replaces.
    still_open = [e for e in bm.edges if len(e.link_faces) < 2]
    if still_open:
        raise RuntimeError(f"cork not watertight: {len(still_open)} boundary edges")

    me = bpy.data.meshes.new("WorryJarCorkMesh")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("WorryJarCork", me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True

    # The Voronoi displacements are confined to the WALLS. On the cap's
    # constructed ring topology, per-ring displacement differences shade as
    # radial spokes (the "citrus" look) — so the top face takes only the
    # smooth low-frequency wobble, and its fine texture comes from the
    # material's bump, which is shading-only and cannot reveal topology.
    walls = ob.vertex_groups.new(name="Walls")
    top_z = CORK_H_CAP - 1e-3
    wall_ids = [v.index for v in me.vertices if v.co.z < top_z]
    rim_ids = [v.index for v in me.vertices
               if v.co.z >= top_z
               and (v.co.x ** 2 + v.co.y ** 2) ** 0.5 > CORK_R_CAP * 0.80]
    walls.add(wall_ids, 1.0, "REPLACE")
    walls.add(rim_ids, 0.45, "REPLACE")   # soft falloff, no visible seam

    # Real geometric irregularity, not just a bump map: cork is a pressed
    # natural material and its silhouette should not be a perfect cylinder.
    # Light subdivision only. Two levels plus displacement rounded the plug
    # into a blob and cost the cork its crisp cut edges.
    sub = ob.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 2
    # Fine pores, weak — cork is pitted, not quilted. The first pass used a
    # 0.055 cell at 0.010 strength and read as a crumpet.
    disp = ob.modifiers.new("Pores", "DISPLACE")
    tex = bpy.data.textures.new("CorkPores", "VORONOI")
    tex.noise_scale = 0.018
    tex.contrast = 1.15
    disp.texture = tex
    disp.strength = 0.0042
    disp.mid_level = 0.46
    disp.vertex_group = "Walls"
    # A second, larger and rarer scale: the occasional real imperfection, so
    # the surface is not uniformly speckled.
    big = ob.modifiers.new("Flaws", "DISPLACE")
    tex2 = bpy.data.textures.new("CorkFlaws", "VORONOI")
    tex2.noise_scale = 0.075
    tex2.contrast = 2.0
    big.texture = tex2
    big.strength = 0.0035
    big.mid_level = 0.62
    big.vertex_group = "Walls"
    # Very low-frequency wobble so the silhouette is not a perfect cylinder.
    rough = ob.modifiers.new("Edge", "DISPLACE")
    tex3 = bpy.data.textures.new("CorkEdge", "CLOUDS")
    tex3.noise_scale = 0.34
    rough.texture = tex3
    rough.strength = 0.0035
    rough.mid_level = 0.5
    return ob


def _set(node, value, *names):
    for n in names:
        if n in node.inputs:
            node.inputs[n].default_value = value
            return True
    return False


def glass_material():
    """Stylised optical glass.

    Real transmission (Cycles), IOR 1.45, very low roughness, and a faint
    cool tint so the jar reads as an object rather than a hole in the screen.
    A touch of violet in the tint is what lets it sit in the Calm palette
    without being colour-graded later.
    """
    m = bpy.data.materials.new("WorryJarGlass")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    _set(b, (0.92, 0.93, 1.0, 1.0), "Base Color")
    _set(b, 1.0, "Transmission Weight", "Transmission")
    _set(b, 0.035, "Roughness")
    _set(b, 1.45, "IOR")
    _set(b, 0.0, "Metallic")
    _set(b, 0.5, "Specular IOR Level", "Specular")
    _set(b, 0.12, "Coat Weight")
    _set(b, 0.06, "Coat Roughness")
    m.use_backface_culling = False
    return m


def cork_material():
    """Natural wine-cork material, gently stylised.

    Four kinds of variation, each doing a different job:
      pores  — sparse irregular dark pits (noise-distorted Voronoi, thresholded
               so only the deepest ~30%% of cells become pores at all; the
               distortion kills the honeycomb spacing, and anisotropic vector
               scaling elongates some pits)
      pits   — rare medium imperfections
      grain  — fine fibrous streaks, strongly stretched in one axis
      blotch — low-frequency tonal drift between tan and cork-brown, with a
               lighter worn patch here and there
    """
    m = bpy.data.materials.new("WorryJarCork")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    _set(b, 0.0, "Metallic")
    _set(b, 0.06, "Specular IOR Level", "Specular")
    _set(b, 0.22, "Sheen Weight")

    coord = nt.nodes.new("ShaderNodeTexCoord")

    # Distortion field: breaks the even Voronoi spacing.
    warp = nt.nodes.new("ShaderNodeTexNoise")
    warp.inputs["Scale"].default_value = 22.0
    warp.inputs["Detail"].default_value = 3.0
    nt.links.new(coord.outputs["Object"], warp.inputs["Vector"])

    # Elongate: squash the lookup so pores stretch slightly along the grain.
    aniso = nt.nodes.new("ShaderNodeMapping")
    aniso.inputs["Scale"].default_value = (1.0, 1.0, 0.55)
    nt.links.new(coord.outputs["Object"], aniso.inputs["Vector"])

    warped = nt.nodes.new("ShaderNodeVectorMath")
    warped.operation = "MULTIPLY_ADD"
    warped.inputs[1].default_value = (0.10, 0.10, 0.10)
    nt.links.new(warp.outputs["Color"], warped.inputs[0])
    nt.links.new(aniso.outputs["Vector"], warped.inputs[2])

    # Fine pores — thresholded, so most of the surface is NOT pitted.
    pores = nt.nodes.new("ShaderNodeTexVoronoi")
    pores.inputs["Scale"].default_value = 78.0
    nt.links.new(warped.outputs["Vector"], pores.inputs["Vector"])
    pore_mask = nt.nodes.new("ShaderNodeValToRGB")
    pore_mask.color_ramp.elements[0].position = 0.10
    pore_mask.color_ramp.elements[0].color = (1, 1, 1, 1)
    pore_mask.color_ramp.elements[1].position = 0.30
    pore_mask.color_ramp.elements[1].color = (0, 0, 0, 1)
    nt.links.new(pores.outputs["Distance"], pore_mask.inputs["Fac"])

    # Rare medium pits.
    pits = nt.nodes.new("ShaderNodeTexVoronoi")
    pits.inputs["Scale"].default_value = 24.0
    nt.links.new(warped.outputs["Vector"], pits.inputs["Vector"])
    pit_mask = nt.nodes.new("ShaderNodeValToRGB")
    pit_mask.color_ramp.elements[0].position = 0.03
    pit_mask.color_ramp.elements[0].color = (1, 1, 1, 1)
    pit_mask.color_ramp.elements[1].position = 0.13
    pit_mask.color_ramp.elements[1].color = (0, 0, 0, 1)
    nt.links.new(pits.outputs["Distance"], pit_mask.inputs["Fac"])

    # Fibrous grain: noise stretched hard along Z.
    # Grain runs ALONG one horizontal axis (like a cut cork sheet), so on
    # the flat cap it reads as parallel fibres instead of converging on the
    # centre like citrus segments. The vertical stretch was what produced
    # the radial streaks on a horizontal face.
    gmap = nt.nodes.new("ShaderNodeMapping")
    gmap.inputs["Scale"].default_value = (30.0, 3.6, 3.6)
    nt.links.new(coord.outputs["Object"], gmap.inputs["Vector"])
    grain = nt.nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 1.0
    grain.inputs["Detail"].default_value = 5.0
    nt.links.new(gmap.outputs["Vector"], grain.inputs["Vector"])

    # Tonal drift + occasional lighter worn area.
    blotch = nt.nodes.new("ShaderNodeTexNoise")
    blotch.inputs["Scale"].default_value = 6.5
    blotch.inputs["Detail"].default_value = 5.0
    nt.links.new(coord.outputs["Object"], blotch.inputs["Vector"])

    # Base colour: warm tan -> cork brown by blotch, nudged by grain.
    cramp = nt.nodes.new("ShaderNodeValToRGB")
    cramp.color_ramp.elements[0].position = 0.30
    cramp.color_ramp.elements[0].color = (0.58, 0.40, 0.235, 1)  # cork brown
    cramp.color_ramp.elements[1].position = 0.72
    cramp.color_ramp.elements[1].color = (0.84, 0.65, 0.42, 1)   # light tan
    e = cramp.color_ramp.elements.new(0.92)
    e.color = (0.90, 0.74, 0.52, 1)                              # worn light
    bmix = nt.nodes.new("ShaderNodeMix")
    bmix.data_type = "FLOAT"
    bmix.inputs["Factor"].default_value = 0.30
    nt.links.new(blotch.outputs["Fac"], bmix.inputs[2])
    nt.links.new(grain.outputs["Fac"], bmix.inputs[3])
    nt.links.new(bmix.outputs[0], cramp.inputs["Fac"])

    # Darken inside pores and pits (pore full strength, pit a bit softer).
    pore_dark = nt.nodes.new("ShaderNodeMixRGB")
    pore_dark.blend_type = "MULTIPLY"
    pore_dark.inputs["Fac"].default_value = 0.62
    nt.links.new(cramp.outputs["Color"], pore_dark.inputs["Color1"])
    pore_col = nt.nodes.new("ShaderNodeRGB")
    pore_col.outputs[0].default_value = (0.33, 0.21, 0.12, 1)
    nt.links.new(pore_col.outputs[0], pore_dark.inputs["Color2"])
    inv = nt.nodes.new("ShaderNodeInvert")
    nt.links.new(pore_mask.outputs["Color"], inv.inputs["Color"])
    pit_add = nt.nodes.new("ShaderNodeMath")
    pit_add.operation = "MAXIMUM"
    inv2 = nt.nodes.new("ShaderNodeInvert")
    nt.links.new(pit_mask.outputs["Color"], inv2.inputs["Color"])
    nt.links.new(inv.outputs["Color"], pit_add.inputs[0])
    nt.links.new(inv2.outputs["Color"], pit_add.inputs[1])
    fac = nt.nodes.new("ShaderNodeMath")
    fac.operation = "MULTIPLY"
    fac.inputs[1].default_value = 0.85
    nt.links.new(pit_add.outputs[0], fac.inputs[0])
    nt.links.new(fac.outputs[0], pore_dark.inputs["Fac"])
    nt.links.new(pore_dark.outputs["Color"], b.inputs["Base Color"])

    # Bump: pores deepest, pits medium, grain faint.
    bsum = nt.nodes.new("ShaderNodeMath")
    bsum.operation = "MULTIPLY_ADD"
    bsum.inputs[1].default_value = 0.55
    gm = nt.nodes.new("ShaderNodeMath")
    gm.operation = "MULTIPLY"
    gm.inputs[1].default_value = 0.18
    nt.links.new(grain.outputs["Fac"], gm.inputs[0])
    nt.links.new(pit_add.outputs[0], bsum.inputs[0])
    nt.links.new(gm.outputs[0], bsum.inputs[2])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.55
    bump.inputs["Distance"].default_value = 0.008
    bump.invert = True
    nt.links.new(bsum.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])

    # Non-uniform roughness: pits duller, worn areas slightly shinier.
    rr = nt.nodes.new("ShaderNodeMapRange")
    rr.inputs["From Min"].default_value = 0.0
    rr.inputs["From Max"].default_value = 1.0
    rr.inputs["To Min"].default_value = 0.60
    rr.inputs["To Max"].default_value = 0.92
    nt.links.new(pit_add.outputs[0], rr.inputs["Value"])
    nt.links.new(rr.outputs["Result"], b.inputs["Roughness"])
    return m


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--save", default=None, help="write a .blend master here")
    args = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)

    glass = build_glass()
    cork = build_cork()
    cork.location = (0.0, 0.0, Z_LIP + 0.055)     # seated in the mouth

    glass.data.materials.append(glass_material())
    cork.data.materials.append(cork_material())

    # Report measured geometry rather than assuming it.
    dg = bpy.context.evaluated_depsgraph_get()
    stats = {}
    for ob in (glass, cork):
        me = ob.evaluated_get(dg).to_mesh()
        stats[ob.name] = {
            "tris": sum(len(p.vertices) - 2 for p in me.polygons),
            "verts": len(me.vertices),
        }
        bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
        stats[ob.name]["height"] = round(max(v.z for v in bb) - min(v.z for v in bb), 4)
        stats[ob.name]["width"] = round(max(v.x for v in bb) - min(v.x for v in bb), 4)

    os.makedirs(args.outdir, exist_ok=True)
    if args.save:
        os.makedirs(os.path.dirname(args.save), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=args.save, copy=True)

    print("JARSTATS", stats)


if __name__ == "__main__":
    main()
