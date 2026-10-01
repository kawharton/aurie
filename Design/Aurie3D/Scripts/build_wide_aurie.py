"""Wide Aurie (Rig C) — v1 prototype Blender pipeline (headless).

Builds one Wide Aurie: a shorter, broader, squat-but-dimensional soft
mascot in the same visual family as frozen Round v6 and Tall v14 (same
material/lighting/camera architecture) with its OWN sculpted body and
Rig C anchors. Round V2's accidental wide read is the numerical starting
clue; Wide v1 is a deliberate redesign, not a stretched Round.

Face: the Tall v10/v11 surface-conforming architecture — eyes with
charcoal rim gradient + gray sheen + catchlights, ribbon mouth, blush —
all flush on the body surface (tiny anti-z-fighting epsilons only).

Limbs: Rig C / Tiny Stubby PROTOTYPE baseline (like Tall's) — enough to
judge the body, not the final Wide limb design.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender --background \
      --factory-startup --python-exit-code 1 \
      --python Design/Aurie3D/Scripts/build_wide_aurie.py -- \
      --outdir /abs/path/to/Design/Aurie3D

Canonical passes (shared fixed camera -> pixel-registered layers):
  Previews/preview_wide_full.png         everything + face
  Renders/body_02_wide.png               BODY ONLY
  Renders/tuft_00_wide.png               TUFT ONLY (design 00, Wide frame)
  Renders/limbs_c_00.png                 RIG C prototype ARMS + FEET ONLY
  Renders/body_02_wide_with_tuft.png     convenience reference
"""

import argparse
import math
import os
import sys
import traceback

import bmesh
import bpy
from mathutils import Vector

# ================= WIDE TUNING (Rig C — independent of Round/Tall) ========
# All distances are fractions of the body radius R. Floor is world z = 0;
# the camera looks straight down +Y at the -Y face of the character.
#
# The body is SCULPTED wide, not X-scaled: the same profile machinery
# proven on Tall — w(t) = WIDEN * pear(t) * (1 + SIDE_FILL*t^2(1-t^2)) —
# with Wide values: broad soft flanks (side-fill), gently full lower body
# (pear), moderate vertical squash, and only a SUBTLE bottom flatten
# (Round V2's 0.06 was half the pancake problem; Wide uses 0.03).

R = 1.0
WIDE_SQUASH = 0.925         # v2: a touch taller — v1's 0.89 read as a
                            # squashed oval; the dome gets breathing room
BODY_WIDEN = 1.12           # broad (v1 width approved, kept)
PEAR_AMOUNT = 0.10          # v2: lower body softly full, less floor-spread
SIDE_FILL = 0.25            # v2: slightly less uniform mid fullness — more
                            # distinct dome, curvier sides (still sculpted)
BOTTOM_FLATTEN = 0.02       # v2: rounder transition into the base
BOTTOM_FLAT_START = -0.5
BODY_LIFT = 0.917           # body center height (bottom sits at +0.010)
# Body ~1.83 tall x ~2.33 wide -> H/W ~ 0.79 (Round v6 ~ 0.96, Tall v14
# ~ 1.32): still clearly Wide, now a soft wide gumdrop, not a pillow.

# Tuft: same family design/scale as Round/Tall (NOT widened), on the dome.
TUFT_MID_SCALE = (0.15, 0.15, 0.20)
TUFT_SIDE_SCALE = (0.125, 0.125, 0.165)
TUFT_MID_Z = 1.87           # body top (1.842) + 0.03
TUFT_SIDE_X = 0.145
TUFT_SIDE_Z = (1.83, 1.81)
TUFT_TILT_DEG = (22, 30)

# Arms — Rig C / Tiny Stubby PROTOTYPE. Wide-sized (NOT copied from
# Tall): the broad body would swallow Tall-scale beans. Clearly below
# the face, side-mounted, down-and-out, never ear-like.
ARM_SCALE = (0.17, 0.14, 0.31)     # stubby bean for the squat body
ARM_X = 1.10                # derived for the v2 surface: same ~45-50%
                            # visible bean (arms sit at side*ARM_X)
ARM_Y = -0.10               # side-attached (negative = toward camera)
ARM_Z = 0.65                # derived: same normalized lower-flank position
ARM_TILT_DEG = -52          # mostly down, slightly out (never positive)

# Feet — Rig C / Tiny Stubby PROTOTYPE: broad soft pads emerging from
# under the wide belly near mid-depth (Tall lessons: centered depth,
# low-profile mass below the belly edge, wider stance on a broad base).
FOOT_SCALE = (0.26, 0.20, 0.135)
FOOT_X = 0.54               # 2026-08-16 foot correction pass: 0.46 ->
                            # 0.50 stance + FOOT_Y -0.05 -> -0.09 —
                            # the very broad lower body was swallowing
                            # the feet; wider stance + forward
                            # emergence keeps them readable. Framing
                            # unchanged (FOOT_Z - scale_z pinned);
                            # BODY untouched (prototype limbs only).
FOOT_Y = -0.17              # 2026-08-17: stronger forward emergence
                            # (still well behind the belly front at
                            # y ~ -0.60 — never front-mounted)
FOOT_Z = 0.102              # flattened sole rests on the floor (z ~ 0)
FOOT_FLAT_START = -0.5
FOOT_BOTTOM_FLATTEN = 0.24  # soft plush compression (same as Tall)

# Face — Wide-specific anchors; same conforming architecture and design
# language as Tall v14. Face sits slightly ABOVE the body center (~63%
# up) so it dominates the broad body; eyes spaced wider than Tall to
# match the Round-family relative spacing on the broad face.
EYE_RX = 0.112              # same eye size as Round/Tall (not shrunk)
EYE_RZ = 0.156
EYE_X = 0.31                # wider than Tall's 0.26 (broader face)
EYE_Z = 1.17                # derived +0.05 with the taller body — same
                            # normalized position (~63% up)
CATCH_RX, CATCH_RZ = 0.036, 0.047
CATCH_OFF = (-0.034, 0.050)
CATCH2_RX, CATCH2_RZ = 0.0145, 0.018
CATCH2_OFF = (0.024, -0.034)
EYE_EDGE_TONE = (0.075, 0.078, 0.095)  # charcoal rim (glossy-sphere cue)
EYE_EDGE_START = 0.55
EYE_EDGE_MIX = 0.30
EYESHEEN_RX, EYESHEEN_RZ = 0.032, 0.085
EYESHEEN_OFF = (0.055, -0.015)
EYESHEEN_CORE_ALPHA = 0.60
EYESHEEN_FALL_EXP = 1.3

MOUTH_HALF_W = 0.09
MOUTH_DROP = 0.045
MOUTH_Z = 0.89              # same 0.28 R eye->mouth gap as the family
MOUTH_BEVEL = 0.011

CHEEK_RX = 0.22             # broadest face of the family -> widest blush
CHEEK_RZ = 0.095
CHEEK_X = 0.58
CHEEK_Z = 0.90
CHEEK_SOFT = True
CHEEK_FALL_RADIUS = 0.95
CHEEK_FALL_EXP = 1.5
CHEEK_CORE_ALPHA = 0.45

# Surface-offset policy (same as Tall): z-fighting only, never lift.
FACE_SURF_EPS = 0.003
CATCH_EXTRA_EPS = 0.002

# Framing: Wide is WIDTH-limited (char ~2.76 R wide incl. arms vs ~2.02
# tall), so the frame is sized from the width, not the height.
FRAME_FILL_W = 0.78         # character width as a fraction of canvas width
SAMPLES = 128
VIEW_TRANSFORM = "Standard"
EXPOSURE = 0.0

COL_BODY_HEX = "97C9EF"
COL_CHEEK_HEX = "F5AFC0"
KEY_POWER, FILL_POWER, RIM_POWER = 300.0, 90.0, 150.0
# ==========================================================================


def wide_width(t):
    """Sculpted radial width factor at normalized height t (-1..1)."""
    pear = 1.0 + PEAR_AMOUNT * ((1.0 - t) * 0.5) ** 1.5
    side = 1.0 + SIDE_FILL * (t * t) * (1.0 - t * t)
    return BODY_WIDEN * pear * side


def body_surface_y(x, z_world):
    """World y of the deformed body's front (-Y) surface at (x, z_world)."""
    z_local = (z_world - BODY_LIFT * R) / WIDE_SQUASH
    t = max(-1.0, min(1.0, z_local / R))
    w = wide_width(t)
    inside = R * R - z_local * z_local - (x / w) ** 2
    if inside <= 0:
        return 0.0
    return -w * math.sqrt(inside)


def srgb_to_linear(hexstr):
    def chan(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hexstr[i:i + 2], 16) for i in (0, 2, 4))
    return (chan(r), chan(g), chan(b), 1.0)


def set_input(node, value, *candidates):
    for name in candidates:
        sock = node.inputs.get(name)
        if sock is not None:
            sock.default_value = value
            return name
    print(f"AURIE WARN: none of {candidates} on {node.name}")
    return None


def principled_material(name):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    return mat, bsdf


def make_sphere(name, collection, location, scale, material,
                segments=48, rings=24):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings,
                              radius=1.0)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    ob.location = location
    ob.scale = scale
    if material is not None:
        ob.data.materials.append(material)
    collection.objects.link(ob)
    return ob


def build(outdir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    root = scene.collection

    cols = {}
    for name in ("RIG", "STAGE", "BODY", "TUFT", "LIMBS", "FACE"):
        col = bpy.data.collections.new(name)
        root.children.link(col)
        cols[name] = col

    # ---- materials (identical family look) ------------------------------
    body_mat, b = principled_material("AurieBody")
    set_input(b, srgb_to_linear(COL_BODY_HEX), "Base Color")
    set_input(b, 0.80, "Roughness")
    set_input(b, 0.30, "Specular IOR Level", "Specular")
    set_input(b, 0.15, "Sheen Weight", "Sheen")
    set_input(b, 0.50, "Sheen Roughness")

    # Eye patch: controlled faux-gloss (Tall v11) — deep black + charcoal
    # rim gradient; sheen/catchlight patches supply the reflections.
    eye_mat, e = principled_material("AurieEye")
    set_input(e, (0.010, 0.010, 0.013, 1.0), "Base Color")
    set_input(e, 0.42, "Roughness")
    set_input(e, 0.10, "Specular IOR Level", "Specular")
    nt = eye_mat.node_tree
    ecoord = nt.nodes.new("ShaderNodeTexCoord")
    enorm = nt.nodes.new("ShaderNodeVectorMath")
    enorm.operation = "MULTIPLY"
    enorm.inputs[1].default_value = (1.0 / EYE_RX, 0.0, 1.0 / EYE_RZ)
    elen = nt.nodes.new("ShaderNodeVectorMath")
    elen.operation = "LENGTH"
    erim = nt.nodes.new("ShaderNodeMapRange")
    erim.inputs["From Min"].default_value = EYE_EDGE_START
    erim.inputs["From Max"].default_value = 1.0
    erim.inputs["To Min"].default_value = 0.0
    erim.inputs["To Max"].default_value = EYE_EDGE_MIX
    erim.clamp = True
    if hasattr(erim, "interpolation_type"):
        erim.interpolation_type = "SMOOTHERSTEP"
    etone = nt.nodes.new("ShaderNodeVectorMath")
    etone.operation = "SCALE"
    etone.inputs[0].default_value = EYE_EDGE_TONE
    ebase = nt.nodes.new("ShaderNodeVectorMath")
    ebase.operation = "ADD"
    ebase.inputs[1].default_value = (0.010, 0.010, 0.013)
    nt.links.new(ecoord.outputs["Object"], enorm.inputs[0])
    nt.links.new(enorm.outputs["Vector"], elen.inputs[0])
    nt.links.new(elen.outputs["Value"], erim.inputs["Value"])
    nt.links.new(erim.outputs["Result"], etone.inputs["Scale"])
    nt.links.new(etone.outputs["Vector"], ebase.inputs[0])
    nt.links.new(ebase.outputs["Vector"], e.inputs["Base Color"])

    sheen_mat, sh = principled_material("AurieEyeSheen")
    set_input(sh, (0.02, 0.02, 0.025, 1.0), "Base Color")
    set_input(sh, 0.50, "Roughness")
    set_input(sh, 0.05, "Specular IOR Level", "Specular")
    set_input(sh, (0.62, 0.65, 0.70, 1.0), "Emission Color", "Emission")
    set_input(sh, 0.90, "Emission Strength")
    nt = sheen_mat.node_tree
    scoord = nt.nodes.new("ShaderNodeTexCoord")
    snorm = nt.nodes.new("ShaderNodeVectorMath")
    snorm.operation = "MULTIPLY"
    snorm.inputs[1].default_value = (1.0 / EYESHEEN_RX, 0.0, 1.0 / EYESHEEN_RZ)
    slen = nt.nodes.new("ShaderNodeVectorMath")
    slen.operation = "LENGTH"

    def sheen_math(op, second=None, clamp=False):
        node = nt.nodes.new("ShaderNodeMath")
        node.operation = op
        node.use_clamp = clamp
        if second is not None:
            node.inputs[1].default_value = second
        return node

    sdiv = sheen_math("DIVIDE", 0.95)
    sinv = sheen_math("SUBTRACT", clamp=True)
    sinv.inputs[0].default_value = 1.0
    scurve = sheen_math("POWER", EYESHEEN_FALL_EXP)
    speak = sheen_math("MULTIPLY", EYESHEEN_CORE_ALPHA)
    nt.links.new(scoord.outputs["Object"], snorm.inputs[0])
    nt.links.new(snorm.outputs["Vector"], slen.inputs[0])
    nt.links.new(slen.outputs["Value"], sdiv.inputs[0])
    nt.links.new(sdiv.outputs["Value"], sinv.inputs[1])
    nt.links.new(sinv.outputs["Value"], scurve.inputs[0])
    nt.links.new(scurve.outputs["Value"], speak.inputs[0])
    nt.links.new(speak.outputs["Value"], sh.inputs["Alpha"])

    catch_mat, c = principled_material("AurieCatchlight")
    set_input(c, (0, 0, 0, 1), "Base Color")
    set_input(c, (1, 1, 1, 1), "Emission Color", "Emission")
    set_input(c, 1.5, "Emission Strength")

    cheek_mat, k = principled_material("AurieCheek")
    set_input(k, srgb_to_linear(COL_CHEEK_HEX), "Base Color")
    set_input(k, 0.90, "Roughness")
    set_input(k, 0.20, "Specular IOR Level", "Specular")
    if CHEEK_SOFT:
        nt = cheek_mat.node_tree
        coord = nt.nodes.new("ShaderNodeTexCoord")
        flatten = nt.nodes.new("ShaderNodeVectorMath")
        flatten.operation = "MULTIPLY"
        flatten.inputs[1].default_value = (1.0 / CHEEK_RX, 0.0, 1.0 / CHEEK_RZ)
        length = nt.nodes.new("ShaderNodeVectorMath")
        length.operation = "LENGTH"

        def cheek_math(op, second=None, clamp=False):
            node = nt.nodes.new("ShaderNodeMath")
            node.operation = op
            node.use_clamp = clamp
            if second is not None:
                node.inputs[1].default_value = second
            return node

        norm = cheek_math("DIVIDE", CHEEK_FALL_RADIUS)
        inv = cheek_math("SUBTRACT", clamp=True)
        inv.inputs[0].default_value = 1.0
        curve = cheek_math("POWER", CHEEK_FALL_EXP)
        peak = cheek_math("MULTIPLY", CHEEK_CORE_ALPHA)
        nt.links.new(coord.outputs["Object"], flatten.inputs[0])
        nt.links.new(flatten.outputs["Vector"], length.inputs[0])
        nt.links.new(length.outputs["Value"], norm.inputs[0])
        nt.links.new(norm.outputs["Value"], inv.inputs[1])
        nt.links.new(inv.outputs["Value"], curve.inputs[0])
        nt.links.new(curve.outputs["Value"], peak.inputs[0])
        nt.links.new(peak.outputs["Value"], k.inputs["Alpha"])

    mouth_mat, m = principled_material("AurieMouth")
    set_input(m, (0.05, 0.03, 0.03, 1.0), "Base Color")
    set_input(m, 0.60, "Roughness")

    # ---- body: sculpted wide profile ------------------------------------
    body = make_sphere("Body", cols["BODY"], (0, 0, 0), (R, R, R),
                       body_mat, segments=64, rings=32)
    me = body.data
    for v in me.vertices:
        t = max(-1.0, min(1.0, v.co.z / R))
        w = wide_width(t)
        v.co.x *= w
        v.co.y *= w
        z = v.co.z
        if t < BOTTOM_FLAT_START:
            u = (BOTTOM_FLAT_START - t) / (1.0 + BOTTOM_FLAT_START)
            z += BOTTOM_FLATTEN * u * u * R
        v.co.z = z * WIDE_SQUASH
    me.update()
    body.location = (0, 0, BODY_LIFT * R)

    # ---- tuft -----------------------------------------------------------
    make_sphere("TuftMid", cols["TUFT"], (0, 0, TUFT_MID_Z * R),
                TUFT_MID_SCALE, body_mat)
    for i, side in enumerate((-1, 1)):
        lobe = make_sphere(f"TuftSide{'L' if side < 0 else 'R'}",
                           cols["TUFT"],
                           (side * TUFT_SIDE_X * R, 0, TUFT_SIDE_Z[i] * R),
                           TUFT_SIDE_SCALE, body_mat)
        lobe.rotation_euler = (0, side * math.radians(TUFT_TILT_DEG[i]), 0)

    # ---- limbs (Rig C prototype): stubby beans + broad pads -------------
    atilt = math.radians(ARM_TILT_DEG)
    for side in (-1, 1):
        arm = make_sphere(f"Arm{'L' if side < 0 else 'R'}", cols["LIMBS"],
                          (side * ARM_X * R, ARM_Y * R, ARM_Z * R),
                          ARM_SCALE, body_mat)
        arm.rotation_euler = (0, side * atilt, 0)
        foot = make_sphere(f"Foot{'L' if side < 0 else 'R'}", cols["LIMBS"],
                           (side * FOOT_X * R, FOOT_Y * R, FOOT_Z * R),
                           FOOT_SCALE, body_mat)
        fm = foot.data
        for v in fm.vertices:
            if v.co.z < FOOT_FLAT_START:
                u = (FOOT_FLAT_START - v.co.z) / (1.0 + FOOT_FLAT_START)
                v.co.z += FOOT_BOTTOM_FLATTEN * u * u
        fm.update()

    # ---- face: every feature is a surface-conforming patch --------------
    body_center = Vector((0.0, 0.0, BODY_LIFT * R))

    def conform(gx, gz, eps):
        p = Vector((gx, body_surface_y(gx, gz), gz))
        return p + (p - body_center).normalized() * (eps * R)

    def make_surface_patch(name, cx, cz, rx, rz, material, eps,
                           rings=16, segs=48):
        def vert(rn, th):
            p = conform(cx + rx * rn * math.cos(th) * R,
                        cz + rz * rn * math.sin(th) * R, eps)
            return (p.x - cx, p.y, p.z - cz)

        verts = [vert(0.0, 0.0)]
        for i in range(1, rings + 1):
            for j in range(segs):
                verts.append(vert(i / rings, 2.0 * math.pi * j / segs))

        def vid(i, j):
            return 1 + (i - 1) * segs + (j % segs)

        faces = [(0, vid(1, j), vid(1, j + 1)) for j in range(segs)]
        for i in range(1, rings):
            faces += [(vid(i, j), vid(i + 1, j), vid(i + 1, j + 1),
                       vid(i, j + 1)) for j in range(segs)]
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(verts, [], faces)
        mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
        mesh.update()
        ob = bpy.data.objects.new(name, mesh)
        ob.location = (cx, 0.0, cz)
        ob.data.materials.append(material)
        ob.visible_shadow = False
        cols["FACE"].objects.link(ob)
        return ob

    for side in (-1, 1):
        sfx = "L" if side < 0 else "R"
        ex, ez = side * EYE_X * R, EYE_Z * R
        make_surface_patch(f"Eye{sfx}", ex, ez, EYE_RX, EYE_RZ,
                           eye_mat, FACE_SURF_EPS)
        gloss = make_surface_patch(f"EyeSheen{sfx}",
                                   ex + EYESHEEN_OFF[0] * R,
                                   ez + EYESHEEN_OFF[1] * R,
                                   EYESHEEN_RX, EYESHEEN_RZ, sheen_mat,
                                   FACE_SURF_EPS + 0.001, rings=8, segs=24)
        gloss.visible_diffuse = False
        for tag, crx, crz, off in (
                ("Catch", CATCH_RX, CATCH_RZ, CATCH_OFF),
                ("Catch2", CATCH2_RX, CATCH2_RZ, CATCH2_OFF)):
            dot = make_surface_patch(f"{tag}{sfx}",
                                     ex + off[0] * R, ez + off[1] * R,
                                     crx, crz, catch_mat,
                                     FACE_SURF_EPS + CATCH_EXTRA_EPS,
                                     rings=8, segs=24)
            dot.visible_diffuse = False

    msamples = 32
    mverts = []
    for i in range(msamples + 1):
        u = 2.0 * i / msamples - 1.0
        x = u * MOUTH_HALF_W * R
        zc = (MOUTH_Z - MOUTH_DROP * (1.0 - u * u)) * R
        tan = Vector((2.0 * MOUTH_HALF_W, 0.0, 4.0 * MOUTH_DROP * u))
        nrm = Vector((-tan.z, 0.0, tan.x)).normalized()
        ua = abs(u)
        h = MOUTH_BEVEL
        if ua > 0.88:
            h *= math.sqrt(max(0.0, 1.0 - ((ua - 0.88) / 0.12) ** 2))
        h = max(h, MOUTH_BEVEL * 0.03) * R
        for s in (1.0, -1.0):
            p = conform(x + nrm.x * h * s, zc + nrm.z * h * s, FACE_SURF_EPS)
            mverts.append((p.x, p.y, p.z))
    mfaces = [(2 * i + 1, 2 * i + 3, 2 * i + 2, 2 * i)
              for i in range(msamples)]
    mmesh = bpy.data.meshes.new("Mouth")
    mmesh.from_pydata(mverts, [], mfaces)
    mmesh.polygons.foreach_set("use_smooth", [True] * len(mmesh.polygons))
    mmesh.update()
    mouth = bpy.data.objects.new("Mouth", mmesh)
    mouth.data.materials.append(mouth_mat)
    mouth.visible_shadow = False
    cols["FACE"].objects.link(mouth)

    for side in (-1, 1):
        make_surface_patch(f"Cheek{'L' if side < 0 else 'R'}",
                           side * CHEEK_X * R, CHEEK_Z * R,
                           CHEEK_RX, CHEEK_RZ, cheek_mat, FACE_SURF_EPS)

    # ---- stage: shadow catcher (preview pass only) ----------------------
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=12.0)
    floor_mesh = bpy.data.meshes.new("Floor")
    bm.to_mesh(floor_mesh)
    bm.free()
    floor = bpy.data.objects.new("Floor", floor_mesh)
    floor.location = (0, 0, 0)
    floor.is_shadow_catcher = True
    cols["STAGE"].objects.link(floor)

    # ---- lights (same family rig, aimed at the wide body center) --------
    target = Vector((0, 0, BODY_LIFT * R))

    def area_light(name, loc, size, power, color):
        data = bpy.data.lights.new(name, "AREA")
        data.shape = "SQUARE"
        data.size = size
        data.energy = power
        data.color = color
        ob = bpy.data.objects.new(name, data)
        ob.location = loc
        direction = target - Vector(loc)
        ob.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        cols["RIG"].objects.link(ob)
        return ob

    area_light("Key", (-3.0, -3.0, 4.0), 3.0, KEY_POWER, (1.0, 0.97, 0.92))
    area_light("Fill", (3.5, -2.5, 1.2), 4.0, FILL_POWER, (0.90, 0.95, 1.0))
    area_light("Rim", (0.8, 3.5, 3.2), 2.0, RIM_POWER, (1.0, 1.0, 1.0))

    world = bpy.data.worlds.new("AurieWorld")
    if world.node_tree is None:
        world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.85, 0.90, 1.0, 1.0)
    bg.inputs["Strength"].default_value = 0.2
    scene.world = world

    # ---- camera: orthographic, WIDTH-limited framing --------------------
    z_top = (TUFT_MID_Z + TUFT_MID_SCALE[2]) * R
    z_bot = min(0.0, (FOOT_Z - FOOT_SCALE[2]) * R,
                (BODY_LIFT - WIDE_SQUASH * (1.0 - BOTTOM_FLATTEN)) * R)
    # widest point: arm tips (tilted-ellipsoid x-extent about ARM_X)
    ct, st = math.cos(atilt), math.sin(atilt)
    arm_half_x = math.sqrt((ARM_SCALE[0] * ct) ** 2 +
                           (ARM_SCALE[2] * st) ** 2)
    half_width = ARM_X * R + arm_half_x * R
    ortho = max((z_top - z_bot) / 0.90, 2.0 * half_width / FRAME_FILL_W)

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho
    cam_data.clip_start, cam_data.clip_end = 0.01, 100.0
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0.0, -10.0, (z_top + z_bot) / 2.0)
    cam.rotation_euler = (math.radians(90), 0.0, 0.0)
    cols["RIG"].objects.link(cam)
    scene.camera = cam

    # ---- render settings (identical family setup) -----------------------
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.use_denoising = True
    scene.cycles.denoiser = "OPENIMAGEDENOISE"
    scene.cycles.seed = 0
    scene.render.resolution_x = scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = VIEW_TRANSFORM
    scene.view_settings.look = "None"
    scene.view_settings.exposure = EXPOSURE
    scene.view_settings.gamma = 1.0

    return scene, cols


PASSES = (
    ("Previews/preview_wide_full.png", {"BODY", "TUFT", "LIMBS", "FACE", "STAGE"}),
    ("Renders/body_02_wide.png", {"BODY"}),
    ("Renders/tuft_00_wide.png", {"TUFT"}),
    ("Renders/limbs_c_00.png", {"LIMBS"}),
    ("Renders/body_02_wide_with_tuft.png", {"BODY", "TUFT"}),
)


def render_passes(scene, cols, outdir):
    part_cols = {n: c for n, c in cols.items() if n != "RIG"}
    for rel, visible in PASSES:
        for name, col in part_cols.items():
            col.hide_render = name not in visible
        path = os.path.join(outdir, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print(f"AURIE OK: {path}")
    for col in part_cols.values():
        col.hide_render = False


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", required=True)
    args = parser.parse_args(argv)
    outdir = os.path.abspath(args.outdir)

    scene, cols = build(outdir)
    render_passes(scene, cols, outdir)

    blend_path = os.path.join(outdir, "Source", "wide_aurie_master.blend")
    os.makedirs(os.path.dirname(blend_path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print(f"AURIE OK: {blend_path}")
    print("AURIE DONE")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("AURIE_FAIL:\n" + traceback.format_exc())
        raise
