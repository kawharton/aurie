"""Worry Jar firefly — a tiny golden character, not a dark insect.

Rebuilt to the approved reference: the WHOLE creature is warm luminous gold,
the large veined wings are the star feature, and it has a face — dark glossy
eyes and a little smile — plus thin antennae and a segmented abdomen that
curls gently upward. Think tiny magical lantern-sprite, cute enough to sit
beside an Aurie.

Same public API as before (build_firefly + VARIANTS), so the review renderer
is unchanged. Pivots: root empty at the thorax; each wing's origin at its
hinge for later flutter renders.
"""

import math

import bmesh
import bpy
from mathutils import Euler, Vector

R_HEAD = 0.165          # big head for cuteness
R_THORAX = 0.150
SEGS = [                # abdomen segments: (radius, y, z-rise)
    (0.148, 0.09, 0.000),
    (0.130, 0.205, 0.012),
    (0.104, 0.310, 0.038),
    (0.064, 0.395, 0.078),   # upturned glowing tip
]


def _sphere(bm, radius, u=24, v=16):
    return bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v,
                                     radius=radius)


def _mesh_object(name, bm):
    me = bpy.data.meshes.new(name + "Mesh")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    return ob


# ------------------------------------------------------------------ materials

def gold_body_material(glow=1.0):
    """Luminous warm gold for head/thorax: saturated amber emission kept LOW
    so AgX preserves the hue instead of blowing it to white."""
    m = bpy.data.materials.new(f"FireflyGold_{glow:.2f}")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (1.0, 0.68, 0.24, 1)
    b.inputs["Roughness"].default_value = 0.45
    b.inputs["Subsurface Weight"].default_value = 0.4
    b.inputs["Subsurface Radius"].default_value = (0.3, 0.18, 0.06)
    b.inputs["Emission Color"].default_value = (1.0, 0.54, 0.15, 1)
    b.inputs["Emission Strength"].default_value = 0.75 * glow
    return m


def tail_material(glow=1.0):
    """Abdomen: same family, brighter toward the tail tip."""
    m = bpy.data.materials.new(f"FireflyTail_{glow:.2f}")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (1.0, 0.70, 0.26, 1)
    b.inputs["Roughness"].default_value = 0.5
    b.inputs["Subsurface Weight"].default_value = 0.35

    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Object"], sep.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["From Min"].default_value = 0.05
    ramp.inputs["From Max"].default_value = 0.42
    nt.links.new(sep.outputs["Y"], ramp.inputs["Value"])

    col = nt.nodes.new("ShaderNodeValToRGB")
    col.color_ramp.elements[0].color = (1.0, 0.52, 0.14, 1)
    col.color_ramp.elements[1].color = (1.0, 0.86, 0.55, 1)   # warm cream tip
    nt.links.new(ramp.outputs["Result"], col.inputs["Fac"])
    nt.links.new(col.outputs["Color"], b.inputs["Emission Color"])

    st = nt.nodes.new("ShaderNodeMapRange")
    st.inputs["To Min"].default_value = 0.9 * glow
    st.inputs["To Max"].default_value = 2.3 * glow
    nt.links.new(ramp.outputs["Result"], st.inputs["Value"])
    nt.links.new(st.outputs["Result"], b.inputs["Emission Strength"])
    return m


def wing_material(glow=1.0):
    """The star: large glowing translucent gold wings with radiating veins.

    Veins are a wave texture in the wing's mesh space; they modulate the
    emission strength, so they read as the brighter structural lines the
    reference paints rather than as painted-on stripes.
    """
    m = bpy.data.materials.new(f"FireflyWing_{glow:.2f}")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (1.0, 0.82, 0.46, 1)
    b.inputs["Roughness"].default_value = 0.35
    b.inputs["Alpha"].default_value = 0.55

    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Object"], sep.inputs["Vector"])

    # Root -> tip falloff along the wing's local Y.
    fall = nt.nodes.new("ShaderNodeMapRange")
    fall.inputs["From Min"].default_value = 0.05
    fall.inputs["From Max"].default_value = 0.88
    fall.inputs["To Min"].default_value = 1.0
    fall.inputs["To Max"].default_value = 0.25
    nt.links.new(sep.outputs["Y"], fall.inputs["Value"])

    # Radiating veins — soft structure, not zebra stripes.
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 22.0
    wave.inputs["Distortion"].default_value = 3.0
    wave.inputs["Detail"].default_value = 1.0
    nt.links.new(coord.outputs["Object"], wave.inputs["Vector"])
    vein = nt.nodes.new("ShaderNodeMapRange")
    vein.inputs["From Min"].default_value = 0.35
    vein.inputs["From Max"].default_value = 1.0
    vein.inputs["To Min"].default_value = 0.75
    vein.inputs["To Max"].default_value = 1.35
    nt.links.new(wave.outputs["Fac"], vein.inputs["Value"])

    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(fall.outputs["Result"], mul.inputs[0])
    nt.links.new(vein.outputs["Result"], mul.inputs[1])
    strength = nt.nodes.new("ShaderNodeMath")
    strength.operation = "MULTIPLY"
    strength.inputs[1].default_value = 1.5 * glow
    nt.links.new(mul.outputs[0], strength.inputs[0])
    nt.links.new(strength.outputs[0], b.inputs["Emission Strength"])

    ecol = nt.nodes.new("ShaderNodeValToRGB")
    ecol.color_ramp.elements[0].color = (1.0, 0.56, 0.16, 1)   # edges amber
    ecol.color_ramp.elements[1].color = (1.0, 0.90, 0.62, 1)   # root cream
    nt.links.new(fall.outputs["Result"], ecol.inputs["Fac"])
    nt.links.new(ecol.outputs["Color"], b.inputs["Emission Color"])
    return m


def dark_material():
    """Eyes, smile, antennae, legs: near-black glossy warm brown."""
    m = bpy.data.materials.get("FireflyDark")
    if m:
        return m
    m = bpy.data.materials.new("FireflyDark")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.045, 0.030, 0.022, 1)
    b.inputs["Roughness"].default_value = 0.18
    b.inputs["Coat Weight"].default_value = 0.5
    return m


# ------------------------------------------------------------------- geometry

def _build_head(scale, glow):
    """Head with two glossy eyes and a little smile — a character."""
    bm = bmesh.new()
    _sphere(bm, R_HEAD * scale)
    head = _mesh_object("FireflyHead", bm)
    head.location = (0, -0.30 * scale, 0.015 * scale)
    head.data.materials.append(gold_body_material(glow))

    parts = [head]
    for side in (-1, 1):
        bm = bmesh.new()
        _sphere(bm, 0.055 * scale, u=16, v=12)
        eye = _mesh_object("FireflyEye", bm)
        eye.location = (side * 0.082 * scale, -0.448 * scale, 0.045 * scale)
        eye.data.materials.append(dark_material())
        parts.append(eye)

    # Smile: a thin tube swept along a path ON the head sphere itself —
    # longitude sweeps ±42°, latitude dips in the middle, so from the front
    # it reads as a clean ∪ smile and from any other angle it simply hugs
    # the face. The earlier floating torus arcs could not do this: flat arcs
    # against a sphere bury one end and poke the other out as a hook.
    centre = Vector((0, -0.30 * scale, 0.015 * scale))
    R = R_HEAD * scale * 1.015
    path = []
    for i in range(15):
        lam = math.radians(-42 + 84 * i / 14)
        phi = math.radians(-16 - 15 * math.cos(lam * 1.9))
        d = Vector((math.cos(phi) * math.sin(lam),
                    -math.cos(phi) * math.cos(lam),
                    math.sin(phi)))
        path.append(centre + d * R)
    bm = bmesh.new()
    tube_r = 0.0085 * scale
    rings = []
    for i, pnt in enumerate(path):
        prev = path[max(0, i - 1)]
        nxt = path[min(len(path) - 1, i + 1)]
        t = (nxt - prev).normalized()
        n = (pnt - centre).normalized()          # radial, out of the face
        b = t.cross(n).normalized()
        ring = [bm.verts.new(pnt + (n * math.cos(a) + b * math.sin(a)) * tube_r)
                for a in [2 * math.pi * k / 6 for k in range(6)]]
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(6):
            bm.faces.new((r0[k], r0[(k + 1) % 6], r1[(k + 1) % 6], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    smile = _mesh_object("FireflySmile", bm)
    smile.data.materials.append(dark_material())
    parts.append(smile)

    # Antennae: thin rods with tip bulbs, swept up and forward.
    for side in (-1, 1):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=8,
                              radius1=0.008 * scale, radius2=0.005 * scale,
                              depth=0.26 * scale)
        ant = _mesh_object("FireflyAntenna", bm)
        ant.location = (side * 0.050 * scale, -0.400 * scale, 0.150 * scale)
        # Positive X pitch sends the +Z cone axis toward -Y: forward and up.
        ant.rotation_euler = Euler((math.radians(34),
                                    math.radians(10 * side), 0))
        ant.data.materials.append(dark_material())
        parts.append(ant)
        bm = bmesh.new()
        _sphere(bm, 0.020 * scale, u=12, v=8)
        tip = _mesh_object("FireflyAntennaTip", bm)
        v = Vector((0, 0, 0.14 * scale))
        v.rotate(ant.rotation_euler)
        tip.location = Vector(ant.location) + v
        tip.data.materials.append(dark_material())
        parts.append(tip)
    return parts


def _build_thorax_tail(scale, abd_len, glow):
    bm = bmesh.new()
    t = _sphere(bm, R_THORAX * scale)
    bmesh.ops.scale(bm, verts=t["verts"], vec=(1.0, 1.05, 0.95))
    thorax = _mesh_object("FireflyThorax", bm)
    thorax.data.materials.append(gold_body_material(glow))

    # Segmented tail: overlapping squashed spheres rising toward the tip.
    bm = bmesh.new()
    for r, y, zr in SEGS:
        s = _sphere(bm, r * scale, u=20, v=14)
        bmesh.ops.scale(bm, verts=s["verts"], vec=(1.0, 0.80, 1.0))
        bmesh.ops.translate(bm, verts=s["verts"],
                            vec=(0, y * abd_len * scale, zr * scale))
    tail = _mesh_object("FireflyTailSegs", bm)
    tail.data.materials.append(tail_material(glow))
    return [thorax, tail]


def _build_wing(name, side, scale, pitch_deg, spread_deg, glow):
    """One LARGE glowing petal wing. Origin at the hinge."""
    bm = bmesh.new()
    s = _sphere(bm, 0.5, u=24, v=14)
    bmesh.ops.scale(bm, verts=s["verts"], vec=(0.34, 1.0, 0.05))
    for v in bm.verts:
        t = (v.co.y + 0.5)          # 0 at root pole, 1 at tip pole
        v.co.x *= 0.55 + 0.85 * math.sin(min(1.0, max(0.0, t)) * math.pi) ** 0.8
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=(0, 0.48, 0))
    ob = _mesh_object(name, bm)
    ob.data.materials.append(wing_material(glow))
    ob.scale = (scale, scale, scale)
    # Upright V: X pitch raises the tip up-and-back, Y roll fans the pair
    # apart (this is what keeps the two wings readable as TWO), Z adds a
    # small sweep. The old pose yawed both wings nearly parallel backwards,
    # which merged them into one mass from any side view.
    ob.rotation_euler = Euler((math.radians(pitch_deg),
                               math.radians(side * (14 + spread_deg)),
                               math.radians(side * 9)))
    ob.location = (side * 0.05 * scale, -0.05 * scale, 0.11 * scale)
    return ob


def _build_legs(scale):
    """Three pairs of hair-thin dangling legs. Nearly invisible at app size;
    character up close."""
    parts = []
    for i, (y, ang) in enumerate([(-0.12, 16), (0.00, -6)]):
        for side in (-1, 1):
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, segments=6,
                                  radius1=0.007 * scale, radius2=0.004 * scale,
                                  depth=0.16 * scale)
            leg = _mesh_object(f"FireflyLeg{i}", bm)
            leg.location = (side * 0.075 * scale, y * scale, -0.115 * scale)
            leg.rotation_euler = Euler((math.radians(160 + ang * 0.4),
                                        math.radians(10 * side), 0))
            leg.data.materials.append(dark_material())
            parts.append(leg)
    return parts


def build_firefly(name="Firefly", scale=1.0, abd_len=1.0,
                  wing_pitch=58.0, wing_spread=6.0, glow=1.0):
    """One golden firefly character under a root empty at the thorax."""
    root = bpy.data.objects.new(name, None)
    root.empty_display_size = 0.1
    bpy.context.scene.collection.objects.link(root)

    parts = []
    parts += _build_head(scale, glow)
    parts += _build_thorax_tail(scale, abd_len, glow)
    parts.append(_build_wing(name + "_WingL", -1, scale, wing_pitch,
                             wing_spread, glow))
    parts.append(_build_wing(name + "_WingR", +1, scale, wing_pitch,
                             wing_spread, glow))
    parts += _build_legs(scale)
    for p in parts:
        p.parent = root
    return root


VARIANTS = {
    "V1_base":    dict(scale=1.00, abd_len=1.00, wing_pitch=58, wing_spread=6,  glow=1.00),
    "V2_round":   dict(scale=1.08, abd_len=0.88, wing_pitch=50, wing_spread=12, glow=0.88),
    "V3_slender": dict(scale=0.93, abd_len=1.14, wing_pitch=64, wing_spread=2,  glow=1.10),
    "V4_bright":  dict(scale=0.85, abd_len=0.95, wing_pitch=56, wing_spread=8,  glow=1.28),
}
