"""Tall Aurie (Rig B) — v1 prototype Blender pipeline (headless).

Builds one Tall Aurie: a soft, upright, chubby elongated mascot in the
same visual family as frozen Round v6 (matte vinyl-clay kawaii look, same
material/lighting/camera architecture) but with its OWN sculpted body and
its OWN Rig B anchors — NOT a vertically stretched Round.

Visual references: Design/Aurie3D/References/*.png (TALL body, Tiny
Stubby limbs, Oval eyes) and the frozen Round v6 renders for the shared
family look.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender --background \
      --factory-startup --python-exit-code 1 \
      --python Design/Aurie3D/Scripts/build_tall_aurie.py -- \
      --outdir /abs/path/to/Design/Aurie3D

Canonical passes (shared fixed camera -> pixel-registered layers):
  Previews/preview_tall_full.png         everything + temporary face
  Renders/body_01_tall.png               BODY ONLY
  Renders/tuft_00_tall.png               TUFT ONLY (tuft design 00 on the
                                         Tall frame; separate so charms
                                         can replace it later)
  Renders/limbs_b_00.png                 RIG B ARMS + FEET ONLY
  Renders/body_01_tall_with_tuft.png     convenience reference
"""

import argparse
import math
import os
import sys
import traceback

import bmesh
import bpy
from mathutils import Vector

# ================= TALL TUNING (Rig B — independent of Round) =============
# All distances are fractions of the body radius R. Floor is world z = 0;
# the camera looks straight down +Y at the -Y face of the character.
#
# The body is NOT a squashed/stretched sphere: the silhouette comes from a
# sculpted width profile w(t) = WIDEN * pear(t) * (1 + SIDE_FILL*t^2(1-t^2)).
# pear keeps the lower half fuller; SIDE_FILL widens the shoulder/hip
# latitudes so the sides run straighter and softer than sphere curvature
# (this is what prevents the "long egg / stretched Round" read). Rounded
# dome top, no waist, gentle floor contact.

R = 1.0
TALL_STRETCH = 1.18         # v5: clearly taller (v4 was 1.135); profile
                            # shape constants below deliberately unchanged
BODY_WIDEN = 0.85           # v13: MAJOR narrowing — the reference Tall is
                            # a slim soft gumdrop; v12's 0.90 still read
                            # as a broad blob that dwarfed the limbs
PEAR_AMOUNT = 0.105         # v13: lower body softly fuller, no balloon
SIDE_FILL = 0.27            # v13: keeps soft shoulder/side structure so
                            # the narrower body stays plush, not capsule
BOTTOM_FLATTEN = 0.02       # subtle grounding; silhouette stays rounded
BOTTOM_FLAT_START = -0.5    # normalized height where the flatten eases in
BODY_LIFT = 1.166           # body center height in R (bottom sits at +0.010)
# Resulting body-only H/W ~= 2.34 / 1.77 ~= 1.32 (Round v6 ~= 0.96; v12
# was 1.24): clearly taller-and-slimmer, closing on the reference Tall.

# Tuft: same small integrated asymmetric design language as Round v6 —
# deliberately NOT enlarged for the taller body; repositioned to the dome.
TUFT_MID_SCALE = (0.15, 0.15, 0.20)
TUFT_SIDE_SCALE = (0.125, 0.125, 0.165)
TUFT_MID_Z = 2.38           # body top (2.346) + 0.03, as on Round
TUFT_SIDE_X = 0.145         # deep overlap: one soft crown
TUFT_SIDE_Z = (2.34, 2.32)  # left / right: slight asymmetry
TUFT_TILT_DEG = (22, 30)    # left / right tilt asymmetry

# Arms — Rig B anchors. Same successful language (bean/pill, down-and-out,
# embedded, lower flank) sized to the Tiny Stubby reference. v4: the v3
# arms read as tiny dots — the arm itself is now larger (not just pushed
# out): +~50% volume, visible protrusion ~0.12 R (v3 was 0.10).
# v13: MAJOR limb rebalance to the Tiny Stubby reference — the arm is a
# substantial soft bean that participates in the silhouette, not a
# decorative tip. Placement lessons kept: side-mounted (Y slightly
# toward camera so the 3D volume reads), low flank, mostly-down
# direction, never ear-like.
ARM_SCALE = (0.17, 0.14, 0.325)    # v14: trimmed ~10% (long axis most) —
                            # short fat bean, not a flipper; still far
                            # bigger than the pre-v13 decorative tips
ARM_X = 0.83                # embed recomputed: ~47% of the bean form
                            # visible (v13's 55% read winglike)
                            # (arms sit at side*ARM_X; larger = outward)
ARM_Y = -0.10               # side-attached depth (kept from v9)
ARM_Z = 0.82                # low flank (kept)
ARM_TILT_DEG = -55          # v14: a touch less steep so the shorter arm
                            # doesn't read pointed (never positive)

# Feet — Rig B. v4: wide soft bean pads per the Tiny Stubby reference
# (v3's small spheres read as beads). Main growth is horizontal; stance
# widened and the rear tucked deeper under the belly so they read
# attached, not pasted on the front edge.
FOOT_SCALE = (0.24, 0.19, 0.132)   # v14: trimmed width/depth + a touch
                            # more vertical fullness — small rounded
                            # plush pad, not a paddle/shoe; still far
                            # bigger than the pre-v13 slivers
FOOT_X = 0.34               # stance kept: two close distinct pads, outer
                            # halves clear of the body's lower silhouette
FOOT_Y = -0.05              # v12: essentially centered in depth with the
                            # small allowed forward offset — the pad's
                            # front face sits just ahead of the body's
                            # thin near-edge shell, so the foot emerges
                            # around the underside edge instead of being
                            # knife-cut by it. NOWHERE near v9's -0.41.
FOOT_Z = 0.100              # derived for the plusher pad: flattened bottom
                            # rests exactly on the floor (z ~ 0)
FOOT_FLAT_START = -0.5      # normalized foot height where the flatten
                            # eases in (soft plush compression, no hard cut)
FOOT_BOTTOM_FLATTEN = 0.24  # unit-sphere bottom lift -> flattens ~12% of
                            # the foot height; top stays fully rounded

# Face — Tall-specific placement (~65% up the body, spacing pulled in
# for the narrower body; same design language as Round v6).
#
# v10 GLOBAL FACE RULE: ALL face artwork (black eyes, catchlights,
# mouth, blush) is built as SURFACE-CONFORMING patches on the analytic
# body surface (body_surface_y). Nothing floats, nothing stands proud,
# nothing adds silhouette at any viewing angle — features foreshorten
# and get occluded naturally as the Aurie turns. The ortho camera
# projects along Y, so every patch keeps the exact approved front-view
# footprint of the old proud geometry it replaces.
EYE_RX = 0.112              # black oval half-width (same front footprint
EYE_RZ = 0.156              # as the old proud eye sphere)
EYE_X = 0.26                # closer than Round's 0.28 (body is ~7% narrower)
EYE_Z = 1.53                # ~65% up the body
CATCH_RX, CATCH_RZ = 0.036, 0.047      # main catchlight footprint
CATCH_OFF = (-0.034, 0.050)            # x/z offset from the eye center
CATCH2_RX, CATCH2_RZ = 0.0145, 0.018   # tiny secondary sparkle
CATCH2_OFF = (0.024, -0.034)

# v11 glossy-eye restoration — all CONTROLLED and surface-conforming
# (no proud geometry, no mirror materials): deep black center with a
# subtle charcoal rim gradient in the eye shader (glossy-sphere cue),
# plus a soft gray reflection band as a conforming alpha-feathered
# patch on each eye's right side (where the v9 Fill-light sheen sat).
EYE_EDGE_TONE = (0.075, 0.078, 0.095)  # charcoal rim color (linear)
EYE_EDGE_START = 0.55       # normalized radius where the rim lift begins
EYE_EDGE_MIX = 0.30         # max blend toward charcoal at the rim
EYESHEEN_RX, EYESHEEN_RZ = 0.032, 0.085  # gray sheen band footprint
EYESHEEN_OFF = (0.055, -0.015)  # right side of BOTH eyes (light logic,
                                # not mirrored — matches v9's real sheen)
EYESHEEN_CORE_ALPHA = 0.60  # softer/dimmer than the white catchlights
EYESHEEN_FALL_EXP = 1.3

MOUTH_HALF_W = 0.09
MOUTH_DROP = 0.045
MOUTH_Z = 1.25              # same world-space eye->mouth gap as Round (0.28)
MOUTH_BEVEL = 0.011         # ribbon half-thickness (same visual weight as
                            # the old proud bevel curve, which is replaced)

# Cheeks — approved diffuse-blush falloff, now ROTATION-SAFE (v9): each
# cheek is a subdivided elliptical patch whose vertices sit ON the
# analytic body surface (body_surface_y) plus a tiny epsilon — it hugs
# the curvature, contributes zero silhouette, and is naturally occluded
# at side angles. Replaces the old CHEEK_PROUD camera-float trick, which
# visibly detached in 3/4 views. Front-view appearance is unchanged: the
# ortho camera projects along Y, so an on-surface patch has exactly the
# same (x, z) footprint and falloff as the old floating disc.
CHEEK_RX = 0.20             # blush half-width (world units of R)
CHEEK_RZ = 0.09             # blush half-height
CHEEK_X = 0.48
CHEEK_Z = 1.26
CHEEK_SOFT = True

# Surface-offset policy (v10): epsilons exist ONLY to prevent
# z-fighting; they must never create visible dimensional separation.
# body surface -> eye/mouth/cheek patches: FACE_SURF_EPS (~0.8 px).
# catchlights layer on TOP of the eye patch: +CATCH_EXTRA_EPS.
FACE_SURF_EPS = 0.003
CATCH_EXTRA_EPS = 0.002
CHEEK_FALL_RADIUS = 0.95
CHEEK_FALL_EXP = 1.5        # alpha = core * (1 - r/RADIUS)^EXP
CHEEK_CORE_ALPHA = 0.45

FRAME_FILL = 0.66           # Tall-specific fill (same value as Round for now)
SAMPLES = 128
VIEW_TRANSFORM = "Standard"
EXPOSURE = 0.0

COL_BODY_HEX = "97C9EF"     # same prototype pastel blue as Round
COL_CHEEK_HEX = "F5AFC0"
KEY_POWER, FILL_POWER, RIM_POWER = 300.0, 90.0, 150.0
# ==========================================================================


def tall_width(t):
    """Sculpted radial width factor at normalized height t (-1..1).

    pear(t) fills the lower half; the SIDE_FILL bump (peaked at |t|=0.707,
    zero at poles and equator) widens shoulder/hip latitudes so the sides
    read straighter/softer than raw sphere curvature.
    """
    pear = 1.0 + PEAR_AMOUNT * ((1.0 - t) * 0.5) ** 1.5
    side = 1.0 + SIDE_FILL * (t * t) * (1.0 - t * t)
    return BODY_WIDEN * pear * side


def body_surface_y(x, z_world):
    """World y of the deformed body's front (-Y) surface at (x, z_world).

    The body is a unit sphere whose x/y were scaled by tall_width(t) and z
    by TALL_STRETCH, lifted to BODY_LIFT. Face parts anchor to this so they
    always sit on the real surface regardless of proportion tuning. (The
    bottom flatten only affects the lowest region, below any face part.)
    """
    z_local = (z_world - BODY_LIFT * R) / TALL_STRETCH
    t = max(-1.0, min(1.0, z_local / R))
    w = tall_width(t)
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

    # ---- materials (identical look to frozen Round v6) ------------------
    body_mat, b = principled_material("AurieBody")
    set_input(b, srgb_to_linear(COL_BODY_HEX), "Base Color")
    set_input(b, 0.80, "Roughness")
    set_input(b, 0.30, "Specular IOR Level", "Specular")
    set_input(b, 0.15, "Sheen Weight", "Sheen")
    set_input(b, 0.50, "Sheen Roughness")

    # Eye patch material (v11): controlled faux-gloss. A mirror material
    # on a flat-ish conforming patch reflects the big area lights as one
    # silver blob (the v10.0 regression), so the gloss is art-directed:
    # deep black center -> subtle charcoal rim gradient (glossy-sphere
    # cue), mild real specular, and the emissive sheen/catchlight
    # patches supply the reflections.
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
        erim.interpolation_type = "SMOOTHERSTEP"   # flat deep-black center
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

    # Soft gray reflection band (v11): emissive alpha-feathered patch —
    # dimmer than the white catchlights, reads as a glossy sheen.
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
        # Approved Round v6 blush: alpha fades with RADIAL distance in the
        # cheek's local x/z disc plane. Falloff = core*(1 - r/RADIUS)^EXP —
        # fades from the very center (no plateau core), smooth 0 at rim.
        nt = cheek_mat.node_tree
        coord = nt.nodes.new("ShaderNodeTexCoord")
        flatten = nt.nodes.new("ShaderNodeVectorMath")
        flatten.operation = "MULTIPLY"
        # Patch-local x/z are in world units; normalize by the ellipse
        # semi-axes so r=1 at the blush rim (same profile as before).
        flatten.inputs[1].default_value = (1.0 / CHEEK_RX, 0.0, 1.0 / CHEEK_RZ)
        length = nt.nodes.new("ShaderNodeVectorMath")
        length.operation = "LENGTH"

        def math_node(op, second=None, clamp=False):
            node = nt.nodes.new("ShaderNodeMath")
            node.operation = op
            node.use_clamp = clamp
            if second is not None:
                node.inputs[1].default_value = second
            return node

        norm = math_node("DIVIDE", CHEEK_FALL_RADIUS)
        inv = math_node("SUBTRACT", clamp=True)
        inv.inputs[0].default_value = 1.0
        curve = math_node("POWER", CHEEK_FALL_EXP)
        peak = math_node("MULTIPLY", CHEEK_CORE_ALPHA)
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

    # ---- body: sculpted tall profile (width profile + stretch) ----------
    body = make_sphere("Body", cols["BODY"], (0, 0, 0), (R, R, R),
                       body_mat, segments=64, rings=32)
    me = body.data
    for v in me.vertices:
        t = max(-1.0, min(1.0, v.co.z / R))          # -1 bottom .. 1 top
        w = tall_width(t)
        v.co.x *= w
        v.co.y *= w
        z = v.co.z
        if t < BOTTOM_FLAT_START:
            # Soft quadratic lift of the lowest region: gently grounded
            # silhouette that still reads rounded, never a hard flat.
            u = (BOTTOM_FLAT_START - t) / (1.0 + BOTTOM_FLAT_START)
            z += BOTTOM_FLATTEN * u * u * R
        v.co.z = z * TALL_STRETCH
    me.update()
    body.location = (0, 0, BODY_LIFT * R)

    # ---- tuft: three soft lobes, deep overlap, slight asymmetry ---------
    make_sphere("TuftMid", cols["TUFT"], (0, 0, TUFT_MID_Z * R),
                TUFT_MID_SCALE, body_mat)
    for i, side in enumerate((-1, 1)):
        lobe = make_sphere(f"TuftSide{'L' if side < 0 else 'R'}",
                           cols["TUFT"],
                           (side * TUFT_SIDE_X * R, 0, TUFT_SIDE_Z[i] * R),
                           TUFT_SIDE_SCALE, body_mat)
        lobe.rotation_euler = (0, side * math.radians(TUFT_TILT_DEG[i]), 0)

    # ---- limbs (Rig B): down-and-out arm stubs + tiny feet --------------
    atilt = math.radians(ARM_TILT_DEG)
    for side in (-1, 1):
        arm = make_sphere(f"Arm{'L' if side < 0 else 'R'}", cols["LIMBS"],
                          (side * ARM_X * R, ARM_Y * R, ARM_Z * R),
                          ARM_SCALE, body_mat)
        arm.rotation_euler = (0, side * atilt, 0)
        foot = make_sphere(f"Foot{'L' if side < 0 else 'R'}", cols["LIMBS"],
                           (side * FOOT_X * R, FOOT_Y * R, FOOT_Z * R),
                           FOOT_SCALE, body_mat)
        # Soft plush compression against the floor: progressively lift the
        # lowest region (same quadratic ease as the body grounding) so the
        # pad rests flat-ish while the upper foot stays fully rounded.
        fm = foot.data
        for v in fm.vertices:
            if v.co.z < FOOT_FLAT_START:
                u = (FOOT_FLAT_START - v.co.z) / (1.0 + FOOT_FLAT_START)
                v.co.z += FOOT_BOTTOM_FLATTEN * u * u
        fm.update()

    # ---- face (preview only): EVERY feature is a surface-conforming -----
    # patch on the analytic body surface. Nothing floats; nothing adds
    # silhouette at any angle; features occlude naturally as the body turns.
    body_center = Vector((0.0, 0.0, BODY_LIFT * R))

    def conform(gx, gz, eps):
        """World point on the body surface at (gx, gz) + tiny outward eps."""
        p = Vector((gx, body_surface_y(gx, gz), gz))
        return p + (p - body_center).normalized() * (eps * R)

    def make_surface_patch(name, cx, cz, rx, rz, material, eps,
                           rings=16, segs=48):
        """Elliptical disc conformed to the body surface.

        Vertex x/z are stored relative to (cx, cz) so Object-space
        radial-falloff materials (the blush) keep working unchanged.
        """
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

    # Eyes + catchlights: same front-view footprint as the old proud
    # spheres (ortho projects along Y), now hugging the face curvature.
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

    # Mouth: conforming ribbon along the smile parabola — same width,
    # drop, thickness, and color as the old proud bevel curve; tips taper
    # softly over the last ~12% so the ends stay rounded.
    msamples = 32
    mverts = []
    for i in range(msamples + 1):
        u = 2.0 * i / msamples - 1.0                 # -1 .. 1 along the smile
        x = u * MOUTH_HALF_W * R
        zc = (MOUTH_Z - MOUTH_DROP * (1.0 - u * u)) * R
        tan = Vector((2.0 * MOUTH_HALF_W, 0.0, 4.0 * MOUTH_DROP * u))
        nrm = Vector((-tan.z, 0.0, tan.x)).normalized()
        ua = abs(u)
        h = MOUTH_BEVEL
        if ua > 0.88:
            h *= math.sqrt(max(0.0, 1.0 - ((ua - 0.88) / 0.12) ** 2))
        h = max(h, MOUTH_BEVEL * 0.03) * R
        for s in (1.0, -1.0):                        # top row, bottom row
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

    # Cheeks: the approved v9 conforming blush, via the shared helper.
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

    # ---- lights (same rig as Round, aimed at the tall body center) ------
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

    # ---- camera: orthographic, straight-on, framed from constants -------
    z_top = (TUFT_MID_Z + TUFT_MID_SCALE[2]) * R
    z_bot = min(0.0, (FOOT_Z - FOOT_SCALE[2]) * R,
                (BODY_LIFT - TALL_STRETCH * (1.0 - BOTTOM_FLATTEN)) * R)
    height = z_top - z_bot

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = height / FRAME_FILL
    cam_data.clip_start, cam_data.clip_end = 0.01, 100.0
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0.0, -10.0, (z_top + z_bot) / 2.0)
    cam.rotation_euler = (math.radians(90), 0.0, 0.0)
    cols["RIG"].objects.link(cam)
    scene.camera = cam

    # ---- render settings (identical to Round) ---------------------------
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
    ("Previews/preview_tall_full.png", {"BODY", "TUFT", "LIMBS", "FACE", "STAGE"}),
    ("Renders/body_01_tall.png", {"BODY"}),
    ("Renders/tuft_00_tall.png", {"TUFT"}),
    ("Renders/limbs_b_00.png", {"LIMBS"}),
    ("Renders/body_01_tall_with_tuft.png", {"BODY", "TUFT"}),
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

    blend_path = os.path.join(outdir, "Source", "tall_aurie_master.blend")
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
