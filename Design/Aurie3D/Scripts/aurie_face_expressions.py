"""Aurie launch expression library — 10 expressions + blink.

Built ON TOP of the family surface-conforming face system, not beside
it: every patch is projected onto the body's own front surface with the
same epsilon policy as `aurie_body_common` (0.003 body, +0.001 sheen,
+0.002 catchlights), so a face sits correctly on any silhouette without
per-body geometry work. Bodies, materials and lighting are untouched.

WHAT AN EXPRESSION CAN CHANGE (per the launch spec):
  eye size, eye tilt, eyelid coverage, gaze offset (via the whole eye
  patch plus its catchlights), mouth shape, blush strength.
It must NOT introduce eyebrows, teeth, or anything that stops reading
as the same species — so every expression here is a re-shaping of the
same three parts: charcoal eye patch, ribbon/filled mouth, blush patch.

BLINK is one parameter, not a second pipeline: `blink` in 0..1 raises
each eye's lid toward closed, and at >=0.86 the patch is replaced by a
thin lash ribbon on the same conformed path. Any expression whose eyes
are already arcs (delighted) ignores blink, which is the sensible
handling the spec asks for rather than forcing a standard blink.

The eye material's rim gradient is normalised against the patch radii,
so `set_eye_norm` retunes it whenever an expression rescales the eye.
"""

import math

try:
    import bpy
    from mathutils import Vector
except ImportError:                       # importable without Blender
    bpy = None
    Vector = None

import aurie_body_common as common

EYE_RX, EYE_RZ = common.EYE_RX, common.EYE_RZ
EPS = common.FACE_SURF_EPS
EPS_SHEEN = EPS + 0.001
EPS_CATCH = EPS + common.CATCH_EXTRA_EPS
MOUTH_BEVEL = common.MOUTH_BEVEL
LASH_AT = 0.86            # blink fraction where the eye becomes a line


# ---- expression table ----------------------------------------------------
# eye:   sx/sz eye patch scale, lid (0 open .. 1 shut), tilt deg (outer
#        corner up = positive), dx/dz gaze offset of eye+catchlights,
#        kind "patch" | "arc" (already-closed happy eyes)
# mouth: kind + width/depth multipliers; "open"/"o" are filled shapes
# blush: cheek patch scale multiplier
EXPRESSIONS = {
    "happy": dict(
        label="Classic Happy",
        eye=dict(sx=1.00, sz=1.00, lid=0.00, tilt=0.0),
        mouth=dict(kind="smile", w=1.00, drop=1.00),
        blush=1.00,
        note="the baseline; every other expression is read against it"),
    "excited": dict(
        label="Excited",
        eye=dict(sx=1.08, sz=1.12, lid=0.00, tilt=0.0, catch=1.15),
        mouth=dict(kind="open", w=1.15, drop=1.35),
        blush=1.30,
        note="biggest eyes plus an open mouth; blush pushed up"),
    "sleepy": dict(
        label="Sleepy",
        eye=dict(sx=1.00, sz=1.02, lid=0.62, tilt=-4.0, dz=-0.012,
                 catch=0.70),
        mouth=dict(kind="tiny", w=0.55, drop=0.55),
        blush=0.85,
        note="heavy lids and a small soft mouth; catchlights dimmed"),
    "shy": dict(
        label="Shy",
        eye=dict(sx=0.96, sz=0.94, lid=0.30, tilt=-6.0, dx=0.014,
                 dz=-0.014),
        mouth=dict(kind="tiny", w=0.62, drop=0.85),
        blush=1.75,
        note="gaze off-axis and down, lids lowered, blush is the tell"),
    "curious": dict(
        label="Curious",
        eye=dict(sx=1.04, sz=1.06, lid=0.00, tilt=0.0, dz=0.012,
                 lid_r=0.22, catch=1.05),
        mouth=dict(kind="o", w=0.72, drop=0.72),
        blush=1.00,
        note="asymmetric lid (one eye half) + small round mouth = quizzical"),
    "surprised": dict(
        label="Surprised",
        eye=dict(sx=1.14, sz=1.18, lid=0.00, tilt=0.0, catch=1.10),
        mouth=dict(kind="o", w=1.00, drop=1.00),
        blush=0.75,
        note="widest eyes, full round mouth, blush pulled back"),
    "mischievous": dict(
        label="Mischievous",
        eye=dict(sx=1.02, sz=0.90, lid=0.34, tilt=9.0),
        mouth=dict(kind="smirk", w=1.05, drop=1.05),
        blush=1.05,
        note="flat-topped tilted eyes + one-sided smirk; playful, not mean"),
    "worried": dict(
        label="Worried",
        eye=dict(sx=0.98, sz=1.04, lid=0.12, tilt=-11.0),
        mouth=dict(kind="wavy", w=0.85, drop=0.70),
        blush=0.85,
        note="eyes tilted down-and-in (no brows) + wavering mouth"),
    "pouty": dict(
        label="Pouty",
        eye=dict(sx=1.00, sz=0.96, lid=0.22, tilt=-5.0, dz=-0.008),
        mouth=dict(kind="frown", w=0.80, drop=0.85),
        blush=1.20,
        note="squint plus an inverted mouth arc; sulky rather than sad"),
    "delighted": dict(
        label="Big Happy / Delighted",
        eye=dict(kind="arc", sx=1.06, sz=1.00, arc=0.55),
        mouth=dict(kind="open", w=1.30, drop=1.55),
        blush=1.45,
        note="closed happy arcs + widest open smile; ignores blink"),
}
ORDER = ["happy", "excited", "sleepy", "shy", "curious", "surprised",
         "mischievous", "worried", "pouty", "delighted"]

# ---- reaction faces ------------------------------------------------------
# TEMPORARY overrides only. These are never assigned as an Aurie's saved
# base expression - they exist so a reaction can borrow the face for a
# moment and hand it back. Reactions that need an existing look (startled
# -> surprised, bounce -> happy, hop -> delighted) simply reuse the ten.
REACTION_FACES = {
    "dizzy": dict(
        label="Dizzy",
        eye=dict(sx=1.04, sz=0.96, lid=0.08, dx_in=0.075, catch=1.45,
                 catch_swirl=True, tilt_abs=9.0),
        mouth=dict(kind="wavy", w=1.05, drop=0.22),
        blush=1.35,
        note="unfocused crossed gaze + offset sparkles reading as swirl; "
             "wobbly mouth. Cute-dazed, never distressed"),
    "yawn": dict(
        label="Yawn",
        eye=dict(sx=1.00, sz=1.02, lid=0.78, tilt=-4.0),
        mouth=dict(kind="o", w=0.62, drop=1.55),
        blush=1.05,
        note="lids nearly shut over a tall soft oval mouth; no big maw"),
    "calm": dict(
        label="Calm",
        eye=dict(sx=0.99, sz=0.97, lid=0.46, tilt=-3.0),
        mouth=dict(kind="tiny", w=0.70, drop=0.80),
        blush=1.15,
        note="softened lids and a small settled smile for Calm Settle"),
}
ALL_FACES = dict(EXPRESSIONS)
ALL_FACES.update(REACTION_FACES)


def set_eye_norm(mat, rx, rz):
    """Retune the eye rim gradient for a rescaled patch."""
    for node in mat.node_tree.nodes:
        if node.type == "VECT_MATH" and node.operation == "MULTIPLY":
            node.inputs[1].default_value = (1.0 / rx, 0.0, 1.0 / rz)
            return


def tune_eye_material(mat):
    """Force the family CONFORMING eye spec (roughness 0.42, specular
    0.10, no metallic).

    Round's legacy build script still ships an eye material tuned for
    proud ellipsoid eyes, where curvature keeps the reflection to a
    small highlight. On a flat conforming patch that same material
    mirrors the light rig as a hard-edged wedge across the whole eye —
    the "never mirror-glossy" rule the face system was built on."""
    for node in mat.node_tree.nodes:
        if node.type != "BSDF_PRINCIPLED":
            continue
        for names, value in ((("Roughness",), 0.42),
                             (("Specular IOR Level", "Specular"), 0.10),
                             (("Metallic",), 0.0),
                             (("Coat Weight", "Clearcoat"), 0.0)):
            for nm in names:
                sock = node.inputs.get(nm)
                if sock is not None:
                    sock.default_value = value
                    break


def _clear(col):
    for ob in list(col.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def _patch(col, name, mat, conform, cx, cz, rx, rz, eps, R,
           lid=0.0, tilt=0.0, rings=16, segs=48):
    """Conforming elliptical patch, optionally tilted and lid-clipped.

    The lid clip happens in the ellipse's own parameter space before
    conforming, so a closing eye keeps sitting on the body surface
    instead of shearing off it. The lid edge carries a shallow arc
    (0.16 rz) so it reads as an eyelid rather than a cut."""
    ct, st = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
    v_lid = rz * (1.0 - 2.0 * lid)

    def vert(rn, th):
        u = rx * rn * math.cos(th)
        v = rz * rn * math.sin(th)
        if lid > 0.0:
            edge = v_lid - 0.16 * rz * (u / rx) ** 2 if rx else v_lid
            v = min(v, edge)
        du, dv = u * ct - v * st, u * st + v * ct
        p = conform(cx + du * R, cz + dv * R, eps)
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
    col.objects.link(ob)
    return ob


def _ribbon(col, name, mat, conform, x0, z0, half_w, drop, R,
            thick=None, samples=32, tilt_end=0.0, wave=0.0):
    """Conforming ribbon along a parabola: mouths, lash lines and the
    closed 'arc' eyes all use this one primitive.

    drop > 0 curves the centre DOWN (a smile read as seen from the
    front); drop < 0 curves it up (frown). `tilt_end` lifts one end for
    a smirk, `wave` adds a single gentle S for the worried mouth."""
    thick = MOUTH_BEVEL if thick is None else thick
    verts = []
    for i in range(samples + 1):
        u = 2.0 * i / samples - 1.0
        x = x0 + u * half_w * R
        z = z0 - drop * (1.0 - u * u) * R
        z += tilt_end * u * R
        if wave:
            z += wave * math.sin(math.pi * u) * R
        tan = Vector((2.0 * half_w, 0.0, 4.0 * drop * u + tilt_end))
        nrm = Vector((-tan.z, 0.0, tan.x)).normalized()
        ua = abs(u)
        hgt = thick
        if ua > 0.88:                       # taper the tips to a point
            hgt *= math.sqrt(max(0.0, 1.0 - ((ua - 0.88) / 0.12) ** 2))
        hgt = max(hgt, thick * 0.03) * R
        for s in (1.0, -1.0):
            p = conform(x + nrm.x * hgt * s, z + nrm.z * hgt * s, EPS)
            verts.append((p.x, p.y, p.z))
    faces = [(2 * i + 1, 2 * i + 3, 2 * i + 2, 2 * i)
             for i in range(samples)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    ob.data.materials.append(mat)
    ob.visible_shadow = False
    col.objects.link(ob)
    return ob


def _mouth(col, mats, conform, pos, R, spec):
    """One of six mouth treatments, all on the conformed surface."""
    kind = spec.get("kind", "smile")
    w = common.MOUTH_HALF_W * spec.get("w", 1.0)
    drop = common.MOUTH_DROP * spec.get("drop", 1.0)
    x0, z0 = pos["mouth_x"], pos["mouth_z"] * R
    mat = mats["mouth"]
    if kind in ("smile", "tiny"):
        _ribbon(col, "Mouth", mat, conform, x0, z0, w, drop, R)
    elif kind == "frown":
        # inverted arc, dropped a little so it does not touch the nose
        # line; a mirrored smile alone reads as a grimace
        _ribbon(col, "Mouth", mat, conform, x0, z0 - 0.035 * R, w,
                -drop * 0.85, R)
    elif kind == "wavy":
        _ribbon(col, "Mouth", mat, conform, x0, z0 - 0.012 * R, w,
                drop * 0.45, R, wave=0.016)
    elif kind == "smirk":
        _ribbon(col, "Mouth", mat, conform, x0, z0, w, drop * 0.8, R,
                tilt_end=0.045)
    elif kind == "o":
        _patch(col, "Mouth", mat, conform, x0, z0 - 0.02 * R,
               w * 0.62, drop * 1.30, EPS, R, rings=10, segs=32)
    elif kind == "open":
        # filled half-ellipse: flat top (the lip line), curved bottom
        _patch(col, "Mouth", mat, conform, x0, z0 - 0.01 * R,
               w * 0.95, drop * 1.55, EPS, R, lid=0.42, rings=12,
               segs=36)
    else:
        raise ValueError(f"unknown mouth kind {kind!r}")


def build(cols, mats, conform, R, pos, expr_id, blink=0.0):
    """Replace the FACE collection with `expr_id` at blink phase `blink`.

    `mats` maps eye/sheen/catch/cheek/mouth -> materials already created
    by the body script; `pos` carries that body's own approved face
    anchors (eye_x/eye_z/mouth_x/mouth_z/cheek_x/cheek_z/face_x).
    """
    expr = ALL_FACES[expr_id]
    eye = dict(expr["eye"])
    col = cols["FACE"]
    _clear(col)

    rx, rz = EYE_RX * eye.get("sx", 1.0), EYE_RZ * eye.get("sz", 1.0)
    set_eye_norm(mats["eye"], rx, rz)
    tune_eye_material(mats["eye"])
    arc_eyes = eye.get("kind") == "arc"
    catch_s = eye.get("catch", 1.0)

    for side in (-1, 1):
        sfx = "L" if side < 0 else "R"
        ex = pos["face_x"] + side * pos["eye_x"] * R
        ez = pos["eye_z"] * R
        # gaze: dx shifts both eyes the same way (looking left/right);
        # dx_in pulls each eye toward the other, which is the crossed
        # unfocused look Dizzy needs and cannot be built from dx alone
        ex += eye.get("dx", 0.0) * R - side * eye.get("dx_in", 0.0) * R
        ez += eye.get("dz", 0.0) * R
        if arc_eyes:
            _ribbon(col, f"Eye{sfx}", mats["mouth"], conform, ex, ez,
                    rx * 1.35, -eye.get("arc", 0.55) * rz, R,
                    thick=MOUTH_BEVEL * 1.5)
            continue
        # per-eye lid: base lid, one-eye override, then blink on top
        lid = eye.get("lid", 0.0)
        if side > 0 and "lid_r" in eye:
            lid = eye["lid_r"]
        lid = max(lid, blink)
        # `tilt` mirrors (outer corners up/down, a symmetric mood);
        # `tilt_abs` rotates BOTH eyes the same way, which is what makes
        # a face read as knocked off-kilter rather than merely sad
        tilt = eye.get("tilt", 0.0) * side + eye.get("tilt_abs", 0.0)
        if lid >= LASH_AT:
            # fully shut: a thin lash line on the same conformed path,
            # curving with the lid rather than a flat dash
            _ribbon(col, f"Eye{sfx}", mats["mouth"], conform, ex,
                    ez - rz * 0.10 * R, rx * 1.15, -0.16 * rz, R,
                    thick=MOUTH_BEVEL * 1.35)
            continue
        _patch(col, f"Eye{sfx}", mats["eye"], conform, ex, ez, rx, rz,
               EPS, R, lid=lid, tilt=tilt)
        # Round's legacy build script never creates the sheen material;
        # substituting the opaque catchlight material there painted a
        # white blob over the eye, so the sheen is simply skipped when
        # the body does not provide it.
        if mats.get("sheen") is not None:
            gl = _patch(col, f"EyeSheen{sfx}", mats["sheen"], conform,
                        ex + common.EYESHEEN_OFF[0] * R,
                        ez + common.EYESHEEN_OFF[1] * R,
                        common.EYESHEEN_RX, common.EYESHEEN_RZ, EPS_SHEEN,
                        R, rings=8, segs=24)
            gl.visible_diffuse = False
        if lid > 0.72:            # a nearly-shut eye shows no sparkle
            continue
        # A catchlight sitting above the lid edge would float on the
        # skin above a half-closed eye, so drop the ones the lid covers.
        v_lid = rz * (1.0 - 2.0 * lid)
        for tag, crx, crz, off in (
                ("Catch", common.CATCH_RX, common.CATCH_RZ,
                 common.CATCH_OFF),
                ("Catch2", common.CATCH2_RX, common.CATCH2_RZ,
                 common.CATCH2_OFF)):
            if lid > 0.0 and off[1] + crz * catch_s * 0.35 > v_lid:
                continue
            ox, oz = off[0], off[1]
            csx = catch_s
            if eye.get("catch_swirl"):
                # Two sparkles placed on OPPOSITE sides of the eye read
                # as an unfocused swirl at app scale, with no spiral
                # geometry. Derived offsets put them on top of each
                # other and merged into one white blob, so they are set
                # explicitly here, and the small one is enlarged so both
                # are legible.
                if tag == "Catch":
                    ox, oz = side * 0.026, 0.034
                else:
                    ox, oz, csx = -side * 0.030, -0.030, catch_s * 1.7
            dot = _patch(col, f"{tag}{sfx}", mats["catch"], conform,
                         ex + ox * R, ez + oz * R,
                         crx * csx, crz * csx, EPS_CATCH, R,
                         rings=8, segs=24)
            dot.visible_diffuse = False

    _mouth(col, mats, conform, pos, R, expr["mouth"])

    bl = expr.get("blush", 1.0)
    for side in (-1, 1):
        _patch(col, f"Cheek{'L' if side < 0 else 'R'}", mats["cheek"],
               conform, pos["face_x"] + side * pos["cheek_x"] * R,
               pos["cheek_z"] * R, pos["cheek_rx"] * bl,
               pos["cheek_rz"] * bl, EPS, R)
