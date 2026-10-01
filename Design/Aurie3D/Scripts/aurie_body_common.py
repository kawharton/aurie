"""Shared Aurie body-candidate pipeline (rapid body-library phase).

Centralizes the frozen family architecture VERBATIM (identical to the
frozen Round/Tall/Wide/Small/Egg/Pear implementations): #97C9EF matte
vinyl material, controlled glossy conforming eyes (charcoal rim + gray
sheen + catchlights), conforming ribbon mouth and diffuse blush with
the family epsilon policy, family tuft, rig-neutral Tiny Stubby
prototype limbs, family lights/camera/render settings, and the
registered canonical passes. Frozen bodies keep their own frozen
scripts — this module serves NEW candidate bodies only.

A body script provides a CFG dict (see DEFAULTS) with its TUNING and a
width function; family-standard anchors (face/tuft/limbs/framing) are
AUTO-DERIVED from the profile at the same normalized positions the
frozen bodies use, with per-body overrides where a concept needs them.

Optional shape hooks beyond the radial profile:
  x_shift_w(z)   world-x axis bow per height (Bean)
  s_phi(phi)     frontal radial modulation about (0, LIFT) applied to
                 x/z AND y (Star lobes, Pebble/Beanbag irregularity);
                 phi = atan2(z - LIFT, x)
  z_dent(x, z)   downward crown displacement (Heart) — must stay above
                 the face zone so the analytic surface stays exact

Import is bpy-OPTIONAL so verifiers/composers can import body CFGs and
recompute framing/anchors without Blender.
"""

import math
import os

try:
    import bmesh
    import bpy
    from mathutils import Vector
except ImportError:      # analysis mode (verifier / composer)
    bmesh = bpy = Vector = None

R = 1.0
COL_BODY_HEX = "97C9EF"
COL_CHEEK_HEX = "F5AFC0"
KEY_POWER, FILL_POWER, RIM_POWER = 300.0, 90.0, 150.0

EYE_RX, EYE_RZ = 0.112, 0.156
CATCH_RX, CATCH_RZ = 0.036, 0.047
CATCH_OFF = (-0.034, 0.050)
CATCH2_RX, CATCH2_RZ = 0.0145, 0.018
CATCH2_OFF = (0.024, -0.034)
EYE_EDGE_TONE = (0.075, 0.078, 0.095)
EYE_EDGE_START, EYE_EDGE_MIX = 0.55, 0.30
EYESHEEN_RX, EYESHEEN_RZ = 0.032, 0.085
EYESHEEN_OFF = (0.055, -0.015)
EYESHEEN_CORE_ALPHA, EYESHEEN_FALL_EXP = 0.60, 1.3
MOUTH_HALF_W, MOUTH_DROP, MOUTH_BEVEL = 0.09, 0.045, 0.011
CHEEK_FALL_RADIUS, CHEEK_FALL_EXP, CHEEK_CORE_ALPHA = 0.95, 1.5, 0.45
FACE_SURF_EPS, CATCH_EXTRA_EPS = 0.003, 0.002
TUFT_MID_SCALE = (0.15, 0.15, 0.20)
TUFT_SIDE_SCALE = (0.125, 0.125, 0.165)
TUFT_SIDE_X, TUFT_TILT_DEG = 0.145, (22, 30)
SAMPLES, VIEW_TRANSFORM, EXPOSURE = 128, "Standard", 0.0

DEFAULTS = dict(
    flatten=0.02, flat_start=-0.5, lift=None,          # lift auto
    x_shift_w=None, s_phi=None, z_dent=None,
    x_warp=None, x_warp_inv=None,  # lateral cross-section asymmetry
                                   # (fuller/tucked sides); inv must
                                   # invert warp for the face surface
    post_xy=1.0,                   # uniform horizontal (x AND y)
                                   # scale applied AFTER all other
                                   # deformations — narrows the whole
                                   # body incl. bow/dent, height kept
    sphi_y=1.0,                # y-coupling of s_phi (lower = flatter
                               # lobes in depth, smoother front face)
    fade_rho=0.45,             # frontal radius where s_phi reaches
                               # full strength (higher = fuller,
                               # more pillowy center)
    mesh_res=(64, 32),
    eye_frac=0.63, eye_rel=0.28, mouth_gap=0.28,
    face_dx=0.0,               # face-group x offset off the body axis
                               # (asymmetric bodies: seat the face on
                               # the visible front mass)
    cheek_dx=0.20, cheek_rx=0.19, cheek_rz=0.085,
    tuft_dz=0.027,                                     # over body top
    tuft_z=None,                                       # explicit override
    arm_scale=(0.16, 0.13, 0.30), arm_frac=0.36, arm_embed=0.09,
    arm_y=-0.10, arm_tilt=-53,
    arm_lr=None,               # ((xL, zL), (xR, zR)) world anchors for
                               # asymmetric bodies (Bean's cave side);
                               # arm_x still sets the framing width
    foot_scale=(0.24, 0.19, 0.13), foot_x=None,        # auto from base
    # Tail. Sits BELOW the arms and beside the legs, rooted on the lower
    # back flank. Every value is a fraction of the body's own height or
    # flank, never an absolute coordinate — ten silhouettes do not share
    # one position, which is exactly what the brief warns about.
    tail_frac=0.24, tail_embed=0.30, tail_back=0.34,
    tail_len=0.58, tail_root_r=0.115, tail_tip_r=0.058, tail_nub_r=0.082,
    foot_cx=None,              # stance center override (world x) for
                               # asymmetric bodies; default = the bowed
                               # axis at floor height
    foot_y=-0.05, foot_flatten=0.24,
    frame_fill=0.66, frame_fill_w=0.80,
)


def resolve(cfg):
    c = dict(DEFAULTS)
    c.update(cfg)
    if c["lift"] is None:
        c["lift"] = (1.0 - c["flatten"]) * c["stretch"] + 0.010
    return c


# ---- analytic geometry (works without bpy) -------------------------------

def body_top(c):
    s_top = c["s_phi"](math.pi / 2) if c["s_phi"] else 1.0
    return c["lift"] + c["stretch"] * s_top


def body_bottom(c):
    if c["s_phi"] is None:
        return c["lift"] - (1.0 - c["flatten"]) * c["stretch"]
    lo = 1e9
    for i in range(-140, -40):
        phi = math.radians(i)
        s = c["s_phi"](phi)
        rr = 1.0 / math.sqrt(math.cos(phi) ** 2 / c["width_fn"](0.0) ** 2
                             + math.sin(phi) ** 2 / c["stretch"] ** 2)
        lo = min(lo, rr * s * math.sin(phi))
    return c["lift"] + lo


def axis_x(c, z):
    return c["x_shift_w"](z) if c["x_shift_w"] else 0.0


def _fade(rho, fade_rho):
    """Smoothstep fade of the s_phi modulation near the frontal pole.

    atan2 is singular where the frontal radius -> 0 (the body-center
    front/back), which puckered the middle of s_phi bodies; fading the
    modulation in smoothly leaves silhouette lobes (large rho) intact
    while the center stays a clean sphere."""
    u = max(0.0, min(1.0, rho / fade_rho))
    return u * u * (3.0 - 2.0 * u)


def _s_at(c, phi, rho):
    return 1.0 + (c["s_phi"](phi) - 1.0) * _fade(rho, c["fade_rho"])


def flank(c, z):
    """Approximate silhouette half-width at world height z."""
    t = max(-1.0, min(1.0, (z - c["lift"]) / c["stretch"]))
    h = math.sqrt(max(0.0, 1.0 - t * t)) * c["width_fn"](t)
    if c["s_phi"]:
        dz = z - c["lift"]
        phi = math.atan2(dz, max(h, 1e-4))
        h *= _s_at(c, phi, math.hypot(h, dz))
    return h * c["post_xy"]


def _circle_y(c, x0, z_world):
    """Front y of the pure profile body (no warp/shift/s_phi/post)."""
    z_local = (z_world - c["lift"] * R) / c["stretch"]
    t = max(-1.0, min(1.0, z_local / R))
    w = c["width_fn"](t)
    inside = R * R - z_local * z_local - (x0 / w) ** 2
    if inside <= 0:
        return 0.0
    return -w * math.sqrt(inside)


def body_surface_y(c, x, z_world):
    """Inverts the vertex pipeline in exact reverse order —
    post_xy -> x_shift -> x_warp -> s_phi -> profile circle — then
    re-applies the y transforms (sphi_y coupling, post_xy). The vertex
    pipeline applies s_phi BEFORE warp/shift, so the inversion must
    strip warp/shift BEFORE dividing out s (the earlier ordering
    mismatch buried face patches on bodies combining all hooks)."""
    xr = x / c["post_xy"]
    xr -= axis_x(c, z_world)
    if c["x_warp_inv"]:
        xr = c["x_warp_inv"](xr)
    dz = z_world - c["lift"]
    if c["s_phi"]:
        phi = math.atan2(dz, xr)
        rho = math.hypot(xr, dz)
        s = _s_at(c, phi, rho)
        s = _s_at(c, phi, rho / s)      # refine fade at source radius
        y = _circle_y(c, xr / s, c["lift"] + dz / s)
        y *= 1.0 + (s - 1.0) * c["sphi_y"]
    else:
        y = _circle_y(c, xr, z_world)
    return y * c["post_xy"]


def base_surface_y(c, x, z_world):
    return body_surface_y(c, x, z_world)


def anchors(c):
    """Family-standard derived anchors (same normalized layout as the
    frozen bodies); overridable per body via cfg."""
    top, bot = body_top(c), body_bottom(c)
    height = top - bot
    a = {}
    a["eye_z"] = c.get("eye_z") or bot + c["eye_frac"] * height
    a["eye_x"] = c.get("eye_x") or round(
        c["eye_rel"] * flank(c, a["eye_z"]), 3)
    a["mouth_z"] = a["eye_z"] - c["mouth_gap"]
    a["cheek_z"] = a["mouth_z"] + 0.02
    a["cheek_x"] = a["eye_x"] + c["cheek_dx"]
    a["tuft_z"] = c["tuft_z"] or top + c["tuft_dz"]
    a["arm_z"] = c.get("arm_z") or bot + c["arm_frac"] * height
    a["arm_x"] = c.get("arm_x") or round(
        flank(c, a["arm_z"]) - c["arm_embed"], 3)
    a["foot_x"] = c["foot_x"] or round(
        min(0.50, max(0.28, 0.75 * flank(c, 0.10))), 3)
    a["foot_z"] = 0.76 * c["foot_scale"][2]

    # Tail root: on the lower flank, pushed INTO the body by tail_embed so
    # it grows out of the silhouette instead of being stuck onto it.
    a["tail_z"] = c.get("tail_z") or bot + c["tail_frac"] * height
    fl = flank(c, a["tail_z"])
    a["tail_x"] = c.get("tail_x") or round(fl * (1.0 - c["tail_embed"]), 3)
    a["tail_flank"] = round(fl, 3)
    return a


def framing(c):
    a = anchors(c)
    z_top = a["tuft_z"] + TUFT_MID_SCALE[2]
    z_bot = min(0.0, a["foot_z"] - c["foot_scale"][2], body_bottom(c))
    atilt = math.radians(c["arm_tilt"])
    arm_half = math.sqrt((c["arm_scale"][0] * math.cos(atilt)) ** 2
                         + (c["arm_scale"][2] * math.sin(atilt)) ** 2)
    half_w = a["arm_x"] + arm_half
    h_ortho = (z_top - z_bot) / c["frame_fill"]
    w_ortho = 2.0 * half_w / c["frame_fill_w"]
    ortho = max(h_ortho, w_ortho)
    return dict(ortho=ortho, cam_z=(z_top + z_bot) / 2.0,
                limited="w" if w_ortho > h_ortho else "h",
                z_top=z_top, z_bot=z_bot, half_w=half_w)


# ---- Blender build -------------------------------------------------------

def _srgb(hexstr):
    def chan(v):
        v /= 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hexstr[i:i + 2], 16) for i in (0, 2, 4))
    return (chan(r), chan(g), chan(b), 1.0)


def _set(node, value, *names):
    for name in names:
        sock = node.inputs.get(name)
        if sock is not None:
            sock.default_value = value
            return
    print(f"AURIE WARN: none of {names} on {node.name}")


def _principled(name):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    b = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    return mat, b


def _sphere(name, col, loc, scale, mat, segments=48, rings=24):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings,
                              radius=1.0)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    ob.location = loc
    ob.scale = scale
    if mat is not None:
        ob.data.materials.append(mat)
    col.objects.link(ob)
    return ob


def build(cfg):
    c = resolve(cfg)
    a = anchors(c)
    fr = framing(c)
    print(f"AURIE FRAME {c['name']}: ortho={fr['ortho']:.5f} "
          f"cam_z={fr['cam_z']:.5f} limited={fr['limited']}")
    print(f"AURIE ANCHORS {c['name']}: " + " ".join(
        f"{k}={v:.3f}" for k, v in sorted(a.items())))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    cols = {}
    for name in ("RIG", "STAGE", "BODY", "TUFT", "LIMBS", "TAIL", "FACE"):
        col = bpy.data.collections.new(name)
        scene.collection.children.link(col)
        cols[name] = col

    body_mat, b = _principled("AurieBody")
    _set(b, _srgb(COL_BODY_HEX), "Base Color")
    _set(b, 0.80, "Roughness")
    _set(b, 0.30, "Specular IOR Level", "Specular")
    _set(b, 0.15, "Sheen Weight", "Sheen")
    _set(b, 0.50, "Sheen Roughness")

    eye_mat, e = _principled("AurieEye")
    _set(e, (0.010, 0.010, 0.013, 1.0), "Base Color")
    _set(e, 0.42, "Roughness")
    _set(e, 0.10, "Specular IOR Level", "Specular")
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

    sheen_mat, sh = _principled("AurieEyeSheen")
    _set(sh, (0.02, 0.02, 0.025, 1.0), "Base Color")
    _set(sh, 0.50, "Roughness")
    _set(sh, 0.05, "Specular IOR Level", "Specular")
    _set(sh, (0.62, 0.65, 0.70, 1.0), "Emission Color", "Emission")
    _set(sh, 0.90, "Emission Strength")
    nt = sheen_mat.node_tree
    scoord = nt.nodes.new("ShaderNodeTexCoord")
    snorm = nt.nodes.new("ShaderNodeVectorMath")
    snorm.operation = "MULTIPLY"
    snorm.inputs[1].default_value = (1.0 / EYESHEEN_RX, 0.0,
                                    1.0 / EYESHEEN_RZ)
    slen = nt.nodes.new("ShaderNodeVectorMath")
    slen.operation = "LENGTH"

    def nmath(tree, op, second=None, clamp=False):
        node = tree.nodes.new("ShaderNodeMath")
        node.operation = op
        node.use_clamp = clamp
        if second is not None:
            node.inputs[1].default_value = second
        return node

    sdiv = nmath(nt, "DIVIDE", 0.95)
    sinv = nmath(nt, "SUBTRACT", clamp=True)
    sinv.inputs[0].default_value = 1.0
    scurve = nmath(nt, "POWER", EYESHEEN_FALL_EXP)
    speak = nmath(nt, "MULTIPLY", EYESHEEN_CORE_ALPHA)
    nt.links.new(scoord.outputs["Object"], snorm.inputs[0])
    nt.links.new(snorm.outputs["Vector"], slen.inputs[0])
    nt.links.new(slen.outputs["Value"], sdiv.inputs[0])
    nt.links.new(sdiv.outputs["Value"], sinv.inputs[1])
    nt.links.new(sinv.outputs["Value"], scurve.inputs[0])
    nt.links.new(scurve.outputs["Value"], speak.inputs[0])
    nt.links.new(speak.outputs["Value"], sh.inputs["Alpha"])

    catch_mat, cch = _principled("AurieCatchlight")
    _set(cch, (0, 0, 0, 1), "Base Color")
    _set(cch, (1, 1, 1, 1), "Emission Color", "Emission")
    _set(cch, 1.5, "Emission Strength")

    cheek_mat, k = _principled("AurieCheek")
    _set(k, _srgb(COL_CHEEK_HEX), "Base Color")
    _set(k, 0.90, "Roughness")
    _set(k, 0.20, "Specular IOR Level", "Specular")
    nt = cheek_mat.node_tree
    ccoord = nt.nodes.new("ShaderNodeTexCoord")
    cflat = nt.nodes.new("ShaderNodeVectorMath")
    cflat.operation = "MULTIPLY"
    cflat.inputs[1].default_value = (1.0 / c["cheek_rx"], 0.0,
                                    1.0 / c["cheek_rz"])
    clen = nt.nodes.new("ShaderNodeVectorMath")
    clen.operation = "LENGTH"
    cnorm = nmath(nt, "DIVIDE", CHEEK_FALL_RADIUS)
    cinv = nmath(nt, "SUBTRACT", clamp=True)
    cinv.inputs[0].default_value = 1.0
    ccurve = nmath(nt, "POWER", CHEEK_FALL_EXP)
    cpeak = nmath(nt, "MULTIPLY", CHEEK_CORE_ALPHA)
    nt.links.new(ccoord.outputs["Object"], cflat.inputs[0])
    nt.links.new(cflat.outputs["Vector"], clen.inputs[0])
    nt.links.new(clen.outputs["Value"], cnorm.inputs[0])
    nt.links.new(cnorm.outputs["Value"], cinv.inputs[1])
    nt.links.new(cinv.outputs["Value"], ccurve.inputs[0])
    nt.links.new(ccurve.outputs["Value"], cpeak.inputs[0])
    nt.links.new(cpeak.outputs["Value"], k.inputs["Alpha"])

    mouth_mat, mm = _principled("AurieMouth")
    _set(mm, (0.05, 0.03, 0.03, 1.0), "Base Color")
    _set(mm, 0.60, "Roughness")

    # ---- body -----------------------------------------------------------
    body = _sphere("Body", cols["BODY"], (0, 0, 0), (R, R, R), body_mat,
                   segments=c["mesh_res"][0], rings=c["mesh_res"][1])
    me = body.data
    for v in me.vertices:
        t = max(-1.0, min(1.0, v.co.z / R))
        w = c["width_fn"](t)
        v.co.x *= w
        v.co.y *= w
        z = v.co.z
        if t < c["flat_start"]:
            u = (c["flat_start"] - t) / (1.0 + c["flat_start"])
            z += c["flatten"] * u * u * R
        z *= c["stretch"]
        x, y = v.co.x, v.co.y
        if c["s_phi"]:
            phi = math.atan2(z, x)
            s = _s_at(c, phi, math.hypot(x, z))
            x, z = x * s, z * s
            y *= 1.0 + (s - 1.0) * c["sphi_y"]
        if c["x_warp"]:
            x = c["x_warp"](x)
        if c["x_shift_w"]:
            x += c["x_shift_w"](z + c["lift"] * R)
        if c["post_xy"] != 1.0:
            x *= c["post_xy"]
            y *= c["post_xy"]
        if c["z_dent"]:
            z -= c["z_dent"](x, z + c["lift"] * R)
        v.co = (x, y, z)
    me.update()
    body.location = (0, 0, c["lift"] * R)

    # ---- tuft -----------------------------------------------------------
    tx = axis_x(c, a["tuft_z"])
    _sphere("TuftMid", cols["TUFT"], (tx, 0, a["tuft_z"] * R),
            TUFT_MID_SCALE, body_mat)
    for i, side in enumerate((-1, 1)):
        lobe = _sphere(f"TuftSide{'L' if side < 0 else 'R'}", cols["TUFT"],
                       (tx + side * TUFT_SIDE_X * R, 0,
                        (a["tuft_z"] - (0.04, 0.06)[i]) * R),
                       TUFT_SIDE_SCALE, body_mat)
        lobe.rotation_euler = (0, side * math.radians(TUFT_TILT_DEG[i]), 0)

    # ---- limbs (rig-neutral prototype) ----------------------------------
    atilt = math.radians(c["arm_tilt"])
    ax_arm = axis_x(c, a["arm_z"])
    if c["arm_lr"]:
        arm_places = [(-1,) + tuple(c["arm_lr"][0]),
                      (1,) + tuple(c["arm_lr"][1])]
    else:
        arm_places = [(side, ax_arm + side * a["arm_x"], a["arm_z"])
                      for side in (-1, 1)]
    for side, arm_px, arm_pz in arm_places:
        arm = _sphere(f"Arm{'L' if side < 0 else 'R'}", cols["LIMBS"],
                      (arm_px * R, c["arm_y"] * R, arm_pz * R),
                      c["arm_scale"], body_mat)
        arm.rotation_euler = (0, side * atilt, 0)
        foot = _sphere(f"Foot{'L' if side < 0 else 'R'}", cols["LIMBS"],
                       ((c["foot_cx"] if c["foot_cx"] is not None
                         else axis_x(c, 0.1)) + side * a["foot_x"] * R,
                        c["foot_y"] * R, a["foot_z"] * R),
                       c["foot_scale"], body_mat)
        fm = foot.data
        for v in fm.vertices:
            if v.co.z < -0.5:
                u = (-0.5 - v.co.z) / 0.5
                v.co.z += c["foot_flatten"] * u * u
        fm.update()

    # ---- face (surface-conforming) --------------------------------------
    center = Vector((0.0, 0.0, c["lift"] * R))

    def conform(gx, gz, eps):
        p = Vector((gx, body_surface_y(c, gx, gz), gz))
        return p + (p - center).normalized() * (eps * R)

    def patch(name, cx, cz, rx, rz, mat, eps, rings=16, segs=48):
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
        ob.data.materials.append(mat)
        ob.visible_shadow = False
        cols["FACE"].objects.link(ob)
        return ob

    fx = axis_x(c, a["eye_z"]) + c["face_dx"]
    for side in (-1, 1):
        sfx = "L" if side < 0 else "R"
        ex, ez = fx + side * a["eye_x"] * R, a["eye_z"] * R
        patch(f"Eye{sfx}", ex, ez, EYE_RX, EYE_RZ, eye_mat, FACE_SURF_EPS)
        gl = patch(f"EyeSheen{sfx}", ex + EYESHEEN_OFF[0] * R,
                   ez + EYESHEEN_OFF[1] * R, EYESHEEN_RX, EYESHEEN_RZ,
                   sheen_mat, FACE_SURF_EPS + 0.001, rings=8, segs=24)
        gl.visible_diffuse = False
        for tag, crx, crz, off in (("Catch", CATCH_RX, CATCH_RZ, CATCH_OFF),
                                   ("Catch2", CATCH2_RX, CATCH2_RZ,
                                    CATCH2_OFF)):
            dot = patch(f"{tag}{sfx}", ex + off[0] * R, ez + off[1] * R,
                        crx, crz, catch_mat,
                        FACE_SURF_EPS + CATCH_EXTRA_EPS, rings=8, segs=24)
            dot.visible_diffuse = False

    msamples = 32
    mx0 = axis_x(c, a["mouth_z"]) + c["face_dx"]
    mverts = []
    for i in range(msamples + 1):
        u = 2.0 * i / msamples - 1.0
        x = mx0 + u * MOUTH_HALF_W * R
        zc = (a["mouth_z"] - MOUTH_DROP * (1.0 - u * u)) * R
        tan = Vector((2.0 * MOUTH_HALF_W, 0.0, 4.0 * MOUTH_DROP * u))
        nrm = Vector((-tan.z, 0.0, tan.x)).normalized()
        ua = abs(u)
        hgt = MOUTH_BEVEL
        if ua > 0.88:
            hgt *= math.sqrt(max(0.0, 1.0 - ((ua - 0.88) / 0.12) ** 2))
        hgt = max(hgt, MOUTH_BEVEL * 0.03) * R
        for s in (1.0, -1.0):
            p = conform(x + nrm.x * hgt * s, zc + nrm.z * hgt * s,
                        FACE_SURF_EPS)
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
        patch(f"Cheek{'L' if side < 0 else 'R'}",
              fx + side * a["cheek_x"] * R, a["cheek_z"] * R,
              c["cheek_rx"], c["cheek_rz"], cheek_mat, FACE_SURF_EPS)

    # ---- stage / lights / world / camera / render -----------------------
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=12.0)
    fmesh = bpy.data.meshes.new("Floor")
    bm.to_mesh(fmesh)
    bm.free()
    floor = bpy.data.objects.new("Floor", fmesh)
    floor.is_shadow_catcher = True
    cols["STAGE"].objects.link(floor)

    target = Vector((0, 0, c["lift"] * R))

    def light(name, loc, size, power, color):
        data = bpy.data.lights.new(name, "AREA")
        data.shape = "SQUARE"
        data.size = size
        data.energy = power
        data.color = color
        ob = bpy.data.objects.new(name, data)
        ob.location = loc
        ob.rotation_euler = (target - Vector(loc)).to_track_quat(
            "-Z", "Y").to_euler()
        cols["RIG"].objects.link(ob)

    light("Key", (-3.0, -3.0, 4.0), 3.0, KEY_POWER, (1.0, 0.97, 0.92))
    light("Fill", (3.5, -2.5, 1.2), 4.0, FILL_POWER, (0.90, 0.95, 1.0))
    light("Rim", (0.8, 3.5, 3.2), 2.0, RIM_POWER, (1.0, 1.0, 1.0))

    world = bpy.data.worlds.new("AurieWorld")
    if world.node_tree is None:
        world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.85, 0.90, 1.0, 1.0)
    bg.inputs["Strength"].default_value = 0.2
    scene.world = world

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = fr["ortho"]
    cam_data.clip_start, cam_data.clip_end = 0.01, 100.0
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0.0, -10.0, fr["cam_z"])
    cam.rotation_euler = (math.radians(90), 0.0, 0.0)
    cols["RIG"].objects.link(cam)
    scene.camera = cam

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


def passes_for(name):
    return (
        (f"Previews/preview_{name}_full.png",
         {"BODY", "TUFT", "LIMBS", "FACE", "STAGE"}),
        (f"Renders/body_{name}_candidate.png", {"BODY"}),
        (f"Renders/tuft_00_{name}.png", {"TUFT"}),
        (f"Renders/limbs_{name}_proto_00.png", {"LIMBS"}),
        (f"Renders/body_{name}_candidate_with_tuft.png", {"BODY", "TUFT"}),
    )


def render_all(cfg, outdir, diagnostic=True):
    name = cfg["name"]
    scene, cols = build(cfg)
    part = {n: c for n, c in cols.items() if n != "RIG"}
    for rel, visible in passes_for(name):
        for cname, col in part.items():
            col.hide_render = cname not in visible
        path = os.path.join(outdir, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print(f"AURIE OK: {path}")
    for col in part.values():
        col.hide_render = False
    blend = os.path.join(outdir, "Source", f"{name}_aurie_master.blend")
    os.makedirs(os.path.dirname(blend), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print(f"AURIE OK: {blend}")
    if diagnostic:
        for cname, col in part.items():
            col.hide_render = cname == "STAGE"
        cam = scene.camera
        theta = math.radians(35)
        cam.location = (-10.0 * math.sin(theta), -10.0 * math.cos(theta),
                        cam.location.z)
        cam.rotation_euler = (math.radians(90), 0.0, -theta)
        path = os.path.join(outdir,
                            f"Previews/preview_{name}_v1_diagnostic_34.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print(f"AURIE OK: {path}")
    print(f"AURIE DONE {name}")
