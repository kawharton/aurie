"""Pear Aurie — v2 APPROVED body Blender pipeline (headless).

v2 is the canonical approved Pear BODY: the localized smooth
hip-bulge architecture. v1's monotonic lower fullness produced a width
plateau (straight sidewalls); v2's cos^2 hip window produces one soft
width peak with continuously curved sides. Later v3/v4 explorations
(crown-concentrated taper; explicit PCHIP width profile) were REJECTED
— they did not improve on v2 enough to justify continuing — and v2 was
restored deterministically as the frozen Pear body.

Builds one Pear Aurie candidate: a soft plush mascot interpretation of
a pear — small rounded crown, relatively narrow upper body, smooth
outward expansion into a broad lower-middle / hip region, and a
rounded full base. UNMISTAKABLY more bottom-heavy than the frozen Egg
v1 (the approved MODERATE bottom-heavy body): Pear's max width sits at
t ~ -0.33 (~0.36 R below center) vs Egg's -0.18, its upper third is
visibly smaller (upper/lower ratio ~0.80 vs Egg's ~0.89), and its base
stays fuller. NOT a literal fruit: no stem, no leaf, no indentation,
no texture, no point — the tuft remains the Aurie tuft. No waist or
neck pinch (Gourd is reserved), no pointed end (Teardrop is reserved).

Pear is NOT in the persisted BodyType enum, so all assets use
CANDIDATE naming with no numeric body index (same policy as Egg). RIG
ASSIGNMENT IS OPEN — anchors here are temporary Pear-specific values
for the rig assessment.

Face: the Tall v10/v11 surface-conforming architecture — eyes with
charcoal rim gradient + gray sheen + catchlights, ribbon mouth, blush —
all flush on the body surface (tiny anti-z-fighting epsilons only).

Limbs: rig-neutral Tiny Stubby PROTOTYPE — enough to judge the body
and attachment zones, not a final limb set (rig is open).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender --background \
      --factory-startup --python-exit-code 1 \
      --python Design/Aurie3D/Scripts/build_pear_aurie.py -- \
      --outdir /abs/path/to/Design/Aurie3D

Canonical passes (shared fixed camera -> pixel-registered layers):
  Previews/preview_pear_full.png              everything + face
  Renders/body_pear_candidate.png             BODY ONLY (candidate, no index)
  Renders/tuft_00_pear.png                    TUFT ONLY (design 00, Pear frame)
  Renders/limbs_pear_proto_00.png             RIG-NEUTRAL prototype arms+feet
  Renders/body_pear_candidate_with_tuft.png   convenience reference
"""

import argparse
import math
import os
import sys
import traceback

import bmesh
import bpy
from mathutils import Vector

# ================ PEAR TUNING (rig OPEN — temporary anchors) ==============
# All distances are fractions of the family radius R. Floor is world
# z = 0; the camera looks straight down +Y at the -Y face.
#
# Pear's silhouette comes from four multiplied profile terms:
#   HIP (localized)     cos^2-window lower-middle bulge — a width
#                       PEAK, not a plateau; C1-smooth, no seam
#   UPPER_TAPER         visibly reduced upper body (rounded cap)
#   BASE_FULL           keeps the lowest region full for a rounded
#                       resting bottom
#   SIDE_FILL           whisper of flank fill; heavy-bottom comes from
#                       the PROFILE, never from bottom flattening

R = 1.0
PEAR_STRETCH = 1.06         # shape distribution carries the identity,
                            # not height (H/W lands ~1.11)
BODY_WIDEN = 0.90
HIP_FULL = 0.18             # LOCALIZED lower-middle hip bulge — a
                            # width PEAK, not v1's width plateau
HIP_CENTER = -0.40          # bump center; measured max lands ~ -0.30
                            # (sphere factor pulls the argmax upward)
HIP_SPREAD = 0.72           # cos^2 window half-width — C1-smooth, no
                            # seam, no waist; the wide window blends
                            # the swell into continuously convex sides
UPPER_TAPER = 0.30          # upper third clearly narrower than Egg's
TAPER_EASE = 1.5
BASE_FULL = 0.04            # base reads full while the sides turn
                            # inward visibly between hip and floor
BASE_START = 0.55           # u_bot threshold for the base term
SIDE_FILL = 0.03
BOTTOM_FLATTEN = 0.02       # subtle grounding only — the heavy bottom
                            # is profile mass, not floor flattening
BOTTOM_FLAT_START = -0.5
BODY_LIFT = 1.049           # body center height (bottom sits at +0.010)
# Body ~2.099 tall x ~1.895 wide -> H/W ~ 1.107 (Egg 1.13, Round
# 0.96). Max width ~65% down the body (t ~ -0.30; Egg: -0.18). One
# soft width maximum: 2%-of-max span t -0.41..-0.17 (v1 plateau was
# -0.49..-0.14); flank at t -0.7 falls to ~76% of max (v1 held 87%).
# Normal family world scale, Round/Egg mass class.

# Tuft: family design at family scale, centered on the small crown.
TUFT_MID_SCALE = (0.15, 0.15, 0.20)
TUFT_SIDE_SCALE = (0.125, 0.125, 0.165)
TUFT_MID_Z = 2.14           # body top (2.109) + ~0.03
TUFT_SIDE_X = 0.145
TUFT_SIDE_Z = (2.10, 2.08)
TUFT_TILT_DEG = (22, 30)

# Arms — RIG-NEUTRAL Tiny Stubby PROTOTYPE (diagnostic only; rig OPEN).
ARM_SCALE = (0.16, 0.13, 0.30)     # family-size stubby bean
ARM_X = 0.86                # flank at ARM_Z is 0.946 -> ~0.09 embed,
                            # same ~45-50% visible bean as the family
ARM_Y = -0.10               # side-attached (negative = toward camera)
ARM_Z = 0.76                # lower flank, ~36% up, clearly below face
ARM_TILT_DEG = -53          # mostly down, slightly out (never positive)

# Feet — RIG-NEUTRAL Tiny Stubby PROTOTYPE: emerge underneath the
# fuller base at centered depth — never front-mounted. Stance a touch
# wider than Egg's (0.33) under the broader base.
FOOT_SCALE = (0.24, 0.19, 0.13)
FOOT_X = 0.34               # 2026-08-16 foot/leg placement pass:
                            # 0.32 -> 0.34 stance, and FOOT_Y -0.05 ->
                            # -0.08 — Pear's full base was partially
                            # occluding the feet from the front (noted
                            # at the V2 checkpoint as a placement
                            # concern); slightly wider stance + more
                            # forward emergence grounds it. BODY and
                            # framing untouched (FOOT_Z - scale_z
                            # unchanged).
FOOT_Y = -0.08              # centered depth + forward emergence bias
FOOT_Z = 0.099              # flattened sole rests on the floor (z ~ 0)
FOOT_FLAT_START = -0.5
FOOT_BOTTOM_FLATTEN = 0.24  # soft plush compression (same as family)

# Face — Pear-specific anchors; same conforming architecture as
# Tall/Wide/Small/Egg. The face sits comfortably in the UPPER half
# (eyes ~64.5% up — slightly higher relative than Egg's ~63%) so it
# never slides down into the large belly. Family eye size and the
# family 0.28 R eye->mouth gap are kept; eye spacing tightened to the
# narrower upper body (local flank half-width 0.776 at eye height).
EYE_RX = 0.112              # FAMILY eye size (not enlarged)
EYE_RZ = 0.156
EYE_X = 0.21                # tighter than Egg's 0.24 (narrow upper
                            # body); ~0.29 of the local half-width
                            # (0.728 at eye height), the family
                            # relative spacing
EYE_Z = 1.36                # ~64.5% up; geometric center is 1.060
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
MOUTH_Z = 1.08              # family 0.28 R eye->mouth gap
MOUTH_BEVEL = 0.011

CHEEK_RX = 0.19             # trimmed to the narrower mid face (flank
CHEEK_RZ = 0.085            # half-width 0.879 at cheek height)
CHEEK_X = 0.40
CHEEK_Z = 1.10
CHEEK_SOFT = True
CHEEK_FALL_RADIUS = 0.95
CHEEK_FALL_EXP = 1.5
CHEEK_CORE_ALPHA = 0.45

# Surface-offset policy (family standard): z-fighting only, never lift.
FACE_SURF_EPS = 0.003
CATCH_EXTRA_EPS = 0.002

# Framing: Pear is height-limited (upright pear). Same family fill;
# the width guard is not binding (arm tips 2.24 R).
FRAME_FILL = 0.66           # character height as a fraction of canvas
FRAME_FILL_W = 0.80         # width guard (not binding for Pear v1)
SAMPLES = 128
VIEW_TRANSFORM = "Standard"
EXPOSURE = 0.0

COL_BODY_HEX = "97C9EF"
COL_CHEEK_HEX = "F5AFC0"
KEY_POWER, FILL_POWER, RIM_POWER = 300.0, 90.0, 150.0
# ==========================================================================


def pear_width(t):
    """Sculpted radial width factor at normalized height t (-1..1).

    hips is a LOCALIZED cos^2-window bulge: it turns on gradually,
    peaks around the lower-middle, and fades toward the base — one
    soft width maximum with continuously curved sides above and below
    it. The window is C1-smooth (zero slope at center and edges): no
    breakpoint, no seam, no waist. taper visibly reduces the upper
    body while the cap stays rounded; base keeps the lowest region
    full enough for a rounded resting bottom; side keeps a whisper of
    flank fill."""
    u_bot = (1.0 - t) * 0.5
    u_top = (1.0 + t) * 0.5
    d = min(1.0, abs(t - HIP_CENTER) / HIP_SPREAD)
    hips = 1.0 + HIP_FULL * math.cos(math.pi * 0.5 * d) ** 2
    taper = 1.0 - UPPER_TAPER * u_top ** TAPER_EASE
    base = 1.0 + BASE_FULL * max(0.0, (u_bot - BASE_START) /
                                 (1.0 - BASE_START)) ** 2
    side = 1.0 + SIDE_FILL * (t * t) * (1.0 - t * t)
    return BODY_WIDEN * hips * taper * base * side


def body_surface_y(x, z_world):
    """World y of the deformed body's front (-Y) surface at (x, z_world)."""
    z_local = (z_world - BODY_LIFT * R) / PEAR_STRETCH
    t = max(-1.0, min(1.0, z_local / R))
    w = pear_width(t)
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

    # ---- body: sculpted pear profile ------------------------------------
    body = make_sphere("Body", cols["BODY"], (0, 0, 0), (R, R, R),
                       body_mat, segments=64, rings=32)
    me = body.data
    for v in me.vertices:
        t = max(-1.0, min(1.0, v.co.z / R))
        w = pear_width(t)
        v.co.x *= w
        v.co.y *= w
        z = v.co.z
        if t < BOTTOM_FLAT_START:
            u = (BOTTOM_FLAT_START - t) / (1.0 + BOTTOM_FLAT_START)
            z += BOTTOM_FLATTEN * u * u * R
        v.co.z = z * PEAR_STRETCH
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

    # ---- limbs (rig-neutral prototype): stubby beans + pads -------------
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

    # ---- lights (same family rig, aimed at the pear body center) --------
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

    # ---- camera: orthographic, HEIGHT-limited framing (width guard) -----
    z_top = (TUFT_MID_Z + TUFT_MID_SCALE[2]) * R
    z_bot = min(0.0, (FOOT_Z - FOOT_SCALE[2]) * R,
                (BODY_LIFT - PEAR_STRETCH * (1.0 - BOTTOM_FLATTEN)) * R)
    # widest point: arm tips (tilted-ellipsoid x-extent about ARM_X)
    ct, st = math.cos(atilt), math.sin(atilt)
    arm_half_x = math.sqrt((ARM_SCALE[0] * ct) ** 2 +
                           (ARM_SCALE[2] * st) ** 2)
    half_width = ARM_X * R + arm_half_x * R
    ortho = max((z_top - z_bot) / FRAME_FILL,
                2.0 * half_width / FRAME_FILL_W)

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
    ("Previews/preview_pear_full.png", {"BODY", "TUFT", "LIMBS", "FACE", "STAGE"}),
    ("Renders/body_pear_candidate.png", {"BODY"}),
    ("Renders/tuft_00_pear.png", {"TUFT"}),
    ("Renders/limbs_pear_proto_00.png", {"LIMBS"}),
    ("Renders/body_pear_candidate_with_tuft.png", {"BODY", "TUFT"}),
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

    blend_path = os.path.join(outdir, "Source", "pear_aurie_master.blend")
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
