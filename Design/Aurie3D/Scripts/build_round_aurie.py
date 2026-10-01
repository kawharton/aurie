"""Round Aurie — proof-of-concept Blender pipeline (headless).

Builds one cute Round Aurie (matte vinyl-clay kawaii mascot) entirely from
Python, renders registered transparent 1024x1024 passes, and saves the
.blend source. Visual source of truth: Design/Aurie3D/References/*.png
(ROUND body, Tiny Stubby limbs, Oval eyes).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender --background \
      --factory-startup --python-exit-code 1 \
      --python Design/Aurie3D/Scripts/build_round_aurie.py -- \
      --outdir /abs/path/to/Design/Aurie3D

Canonical passes (shared fixed camera -> pixel-registered layers):
  Previews/preview_round_full.png        everything + face + soft ground shadow
  Renders/body_00_round.png              BODY ONLY
  Renders/tuft_00.png                    TUFT ONLY
  Renders/limbs_a_00.png                 ARMS + FEET ONLY
  Renders/body_00_round_with_tuft.png    convenience reference
The ground shadow (Cycles shadow catcher) appears ONLY in the preview pass.
"""

import argparse
import math
import os
import sys
import traceback

import bmesh
import bpy
from mathutils import Vector

# ===================== TUNING (visual source of truth: the references) =====
# All distances are fractions of the body radius R. Floor is world z = 0;
# the camera looks straight down +Y at the -Y face of the character.

R = 1.0
BODY_WIDEN = 1.01           # v4: upright buoyant Round (v3's 1.02 still broad)
BODY_SQUASH = 0.97          # v4: taller lower half; reads Round immediately
PEAR_AMOUNT = 0.10          # lower-half fullness
BOTTOM_FLATTEN = 0.015      # barest grounding; silhouette stays rounded
BOTTOM_FLAT_START = -0.5    # normalized height where the flatten eases in
BODY_LIFT = 0.965           # body center height in R (bottom sits at +0.010)

TUFT_MID_SCALE = (0.15, 0.15, 0.20)
TUFT_SIDE_SCALE = (0.125, 0.125, 0.165)
TUFT_MID_Z = 1.965          # in R, world z of middle lobe center
TUFT_SIDE_X = 0.145         # deep overlap: one soft crown, not three eggs
TUFT_SIDE_Z = (1.925, 1.905)  # left / right: slight asymmetry
TUFT_TILT_DEG = (22, 30)    # left / right tilt asymmetry

ARM_SCALE = (0.095, 0.085, 0.185)  # slim pill: stub, not circle (v5)
ARM_X = 0.955               # deeply embedded; only a small stub shows
ARM_Y = -0.08               # 2026-08-16 foot/leg placement pass: 0.05
                            # -> -0.08 (family toward-camera bias so
                            # the stub shows real 3D volume, not a
                            # flat tab — the documented deferred fix)
ARM_Z = 0.72                # world z (clearly on the lower half)
ARM_TILT_DEG = -35          # NEGATIVE: stub points down-and-out (flipper);
                            # positive tilts the tip up, which reads as an ear

# 2026-08-16 foot/leg placement pass: Round was the last body on the
# pre-architecture front-mounted feet (tiny pads at y -0.42 stuck to
# the belly front). Modernized to the family standard: plusher pads
# UNDER the body at centered depth with the soft bottom flatten.
# FOOT_Z - scale_z stays pinned at -0.030 so the frozen V6 framing
# (ortho 3.32576) is unchanged. BODY untouched.
FOOT_SCALE = (0.21, 0.17, 0.115)
FOOT_X = 0.36
FOOT_Y = -0.05              # centered depth + small emergence bias
FOOT_Z = 0.085
FOOT_FLAT_START = -0.5
FOOT_BOTTOM_FLATTEN = 0.24  # soft plush sole compression

# Face parts are placed ON the computed body surface (body_surface_y);
# the Y values below are relative depths, not absolute positions.
EYE_SCALE = (0.112, 0.066, 0.156)  # +12%
EYE_X = 0.28                # a touch closer together
EYE_Z = 1.16                # slightly above the body's visual center
EYE_EMBED = 0.60            # fraction of the eye's depth buried in the body
CATCH_SCALE = (0.036, 0.018, 0.047)
CATCH_OFFSET = (-0.034, -0.052, 0.050)   # upper-left, proud of the cornea
CATCH2_SCALE = (0.0145, 0.010, 0.018)
CATCH2_OFFSET = (0.024, -0.050, -0.034)  # tiny lower-right secondary

MOUTH_HALF_W = 0.09
MOUTH_DROP = 0.045
MOUTH_Z = 0.88
MOUTH_PROUD = 0.015         # lift off the surface toward the camera
MOUTH_BEVEL = 0.011

# 2026-08-16 correction pass: the v6 proud ellipsoid cheeks (PROUD
# 0.10 float) visibly poked past the silhouette at 3/4 — the last
# proud face geometry in the family. Ported to the family SURFACE-
# CONFORMING patch (same footprint, same airbrushed falloff, same
# front-view look); eyes/mouth untouched.
CHEEK_RX = 0.22             # wide soft horizontal oval haze (v6 size)
CHEEK_RZ = 0.095
CHEEK_X = 0.52              # slightly outward
CHEEK_Z = 0.89              # slightly lower
CHEEK_SURF_EPS = 0.003      # anti-z-fighting only, never a lift
                            # occludes the wide flat disc's inner region and
                            # cuts a hard edge. Invisible from the straight-on
                            # ortho camera (no parallax); preview-only part.
CHEEK_SOFT = True           # soft alpha-falloff edge (airbrushed blush)
CHEEK_FALL_RADIUS = 0.95    # normalized disc radius where alpha reaches 0
CHEEK_FALL_EXP = 1.5        # alpha = core * (1 - r/RADIUS)^EXP: fades from
                            # r=0 immediately (no plateau/core), smooth 0 at rim
CHEEK_CORE_ALPHA = 0.45     # peak alpha: rosy haze, never an opaque mark

FRAME_FILL = 0.66           # character height as a fraction of canvas height
SAMPLES = 128
VIEW_TRANSFORM = "Standard"
EXPOSURE = 0.0

COL_BODY_HEX = "97C9EF"     # pastel blue
COL_CHEEK_HEX = "F5AFC0"    # soft pink
KEY_POWER, FILL_POWER, RIM_POWER = 300.0, 90.0, 150.0
# ==========================================================================


def pear_widen(t):
    """Radial widen factor for the body at normalized height t (-1..1)."""
    return 1.0 + PEAR_AMOUNT * ((1.0 - t) * 0.5) ** 1.5


def body_surface_y(x, z_world):
    """World y of the deformed body's front (-Y) surface at (x, z_world).

    The body is a unit sphere whose x/y were scaled by pear_widen(z/R) *
    BODY_WIDEN and z by BODY_SQUASH, lifted to BODY_LIFT. Face parts anchor
    to this so they always sit on the real surface regardless of proportion
    tuning. (The bottom flatten only affects the lowest region, well below
    any face part.)
    """
    z_local = (z_world - BODY_LIFT * R) / BODY_SQUASH
    t = max(-1.0, min(1.0, z_local / R))
    w = pear_widen(t) * BODY_WIDEN
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

    # ---- materials ------------------------------------------------------
    body_mat, b = principled_material("AurieBody")
    set_input(b, srgb_to_linear(COL_BODY_HEX), "Base Color")
    set_input(b, 0.80, "Roughness")
    set_input(b, 0.30, "Specular IOR Level", "Specular")
    set_input(b, 0.15, "Sheen Weight", "Sheen")
    set_input(b, 0.50, "Sheen Roughness")

    eye_mat, e = principled_material("AurieEye")
    set_input(e, (0.010, 0.010, 0.013, 1.0), "Base Color")
    set_input(e, 0.08, "Roughness")
    set_input(e, 0.60, "Specular IOR Level", "Specular")
    set_input(e, 0.40, "Coat Weight")
    set_input(e, 0.05, "Coat Roughness")

    catch_mat, c = principled_material("AurieCatchlight")
    set_input(c, (0, 0, 0, 1), "Base Color")
    set_input(c, (1, 1, 1, 1), "Emission Color", "Emission")
    set_input(c, 1.5, "Emission Strength")

    cheek_mat, k = principled_material("AurieCheek")
    set_input(k, srgb_to_linear(COL_CHEEK_HEX), "Base Color")
    set_input(k, 0.90, "Roughness")
    set_input(k, 0.20, "Specular IOR Level", "Specular")
    if CHEEK_SOFT:
        # Airbrushed blush: alpha fades with RADIAL distance in the cheek's
        # disc plane (local x/z), not 3D distance — every surface point of a
        # sphere is at 3D distance 1, which would kill the alpha entirely.
        nt = cheek_mat.node_tree
        coord = nt.nodes.new("ShaderNodeTexCoord")
        flatten = nt.nodes.new("ShaderNodeVectorMath")
        flatten.operation = "MULTIPLY"
        flatten.inputs[1].default_value = (1.0 / CHEEK_RX, 0.0,
                                           1.0 / CHEEK_RZ)
        length = nt.nodes.new("ShaderNodeVectorMath")
        length.operation = "LENGTH"
        # Falloff = core * (1 - r/RADIUS)^EXP. Ramp/S-curve profiles are
        # flat near r=0, which reads as a concentrated core; this fades
        # from the very center and reaches 0 smoothly at the rim.
        def math_node(op, second=None, clamp=False):
            node = nt.nodes.new("ShaderNodeMath")
            node.operation = op
            node.use_clamp = clamp
            if second is not None:
                node.inputs[1].default_value = second
            return node

        norm = math_node("DIVIDE", CHEEK_FALL_RADIUS)
        inv = math_node("SUBTRACT", clamp=True)      # 1 - r/RADIUS, >= 0
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

    # ---- body (pear + squash deformed sphere) ---------------------------
    body = make_sphere("Body", cols["BODY"], (0, 0, 0), (R, R, R),
                       body_mat, segments=64, rings=32)
    me = body.data
    for v in me.vertices:
        t = max(-1.0, min(1.0, v.co.z / R))          # -1 bottom .. 1 top
        widen = pear_widen(t) * BODY_WIDEN
        v.co.x *= widen
        v.co.y *= widen
        z = v.co.z
        if t < BOTTOM_FLAT_START:
            # Soft quadratic lift of the lowest region: gently flattened
            # silhouette that still reads rounded, never a hard flat.
            u = (BOTTOM_FLAT_START - t) / (1.0 + BOTTOM_FLAT_START)
            z += BOTTOM_FLATTEN * u * u * R
        v.co.z = z * BODY_SQUASH
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

    # ---- limbs: Tiny Stubby beans + small feet --------------------------
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

    # ---- face (preview only), anchored to the real body surface ---------
    for side in (-1, 1):
        ex, ez = side * EYE_X * R, EYE_Z * R
        eye_y = body_surface_y(ex, ez) + EYE_SCALE[1] * (2 * EYE_EMBED - 1)
        make_sphere(f"Eye{'L' if side < 0 else 'R'}", cols["FACE"],
                    (ex, eye_y, ez), EYE_SCALE, eye_mat)
        for tag, cscale, coff in (("Catch", CATCH_SCALE, CATCH_OFFSET),
                                  ("Catch2", CATCH2_SCALE, CATCH2_OFFSET)):
            dot = make_sphere(f"{tag}{'L' if side < 0 else 'R'}",
                              cols["FACE"],
                              (ex + coff[0] * R,
                               eye_y - EYE_SCALE[1] * 0.9 + coff[1] * R * 0.2,
                               ez + coff[2] * R),
                              cscale, catch_mat, segments=24, rings=12)
            dot.visible_shadow = False
            dot.visible_diffuse = False

    cu = bpy.data.curves.new("MouthCurve", "CURVE")
    cu.dimensions = "3D"
    spline = cu.splines.new("BEZIER")
    spline.bezier_points.add(2)
    my = body_surface_y(0, MOUTH_Z * R) - MOUTH_PROUD * R
    pts = ((-MOUTH_HALF_W * R, my, MOUTH_Z * R),
           (0.0, my - 0.005 * R, (MOUTH_Z - MOUTH_DROP) * R),
           (MOUTH_HALF_W * R, my, MOUTH_Z * R))
    for bp, co in zip(spline.bezier_points, pts):
        bp.co = Vector(co)
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    cu.bevel_depth = MOUTH_BEVEL * R
    cu.bevel_resolution = 4
    cu.use_fill_caps = True
    mouth = bpy.data.objects.new("Mouth", cu)
    mouth.data.materials.append(mouth_mat)
    cols["FACE"].objects.link(mouth)

    body_center = Vector((0.0, 0.0, BODY_LIFT * R))

    def cheek_conform(gx, gz):
        p = Vector((gx, body_surface_y(gx, gz), gz))
        return p + (p - body_center).normalized() * (CHEEK_SURF_EPS * R)

    for side in (-1, 1):
        cx, cz = side * CHEEK_X * R, CHEEK_Z * R
        rings, segs = 16, 48

        def cvert(rn, th):
            p = cheek_conform(cx + CHEEK_RX * rn * math.cos(th) * R,
                              cz + CHEEK_RZ * rn * math.sin(th) * R)
            return (p.x - cx, p.y, p.z - cz)

        verts = [cvert(0.0, 0.0)]
        for i in range(1, rings + 1):
            for j in range(segs):
                verts.append(cvert(i / rings, 2.0 * math.pi * j / segs))

        def vid(i, j):
            return 1 + (i - 1) * segs + (j % segs)

        faces = [(0, vid(1, j), vid(1, j + 1)) for j in range(segs)]
        for i in range(1, rings):
            faces += [(vid(i, j), vid(i + 1, j), vid(i + 1, j + 1),
                       vid(i, j + 1)) for j in range(segs)]
        cmesh = bpy.data.meshes.new(f"Cheek{'L' if side < 0 else 'R'}")
        cmesh.from_pydata(verts, [], faces)
        cmesh.polygons.foreach_set("use_smooth",
                                   [True] * len(cmesh.polygons))
        cmesh.update()
        cheek = bpy.data.objects.new(f"Cheek{'L' if side < 0 else 'R'}",
                                     cmesh)
        cheek.location = (cx, 0.0, cz)
        cheek.data.materials.append(cheek_mat)
        cheek.visible_shadow = False
        cols["FACE"].objects.link(cheek)

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

    # ---- lights ---------------------------------------------------------
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

    # ---- camera: orthographic, straight-on ------------------------------
    # Framed from the proportion constants (fresh objects' bound_box is not
    # yet evaluated in background mode, so never trust it here).
    z_top = (TUFT_MID_Z + TUFT_MID_SCALE[2]) * R
    z_bot = min(0.0, (FOOT_Z - FOOT_SCALE[2]) * R,
                (BODY_LIFT - BODY_SQUASH * (1.0 - BOTTOM_FLATTEN)) * R)
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

    # ---- render settings ------------------------------------------------
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
    ("Previews/preview_round_full.png", {"BODY", "TUFT", "LIMBS", "FACE", "STAGE"}),
    ("Renders/body_00_round.png", {"BODY"}),
    ("Renders/tuft_00.png", {"TUFT"}),
    ("Renders/limbs_a_00.png", {"LIMBS"}),
    ("Renders/body_00_round_with_tuft.png", {"BODY", "TUFT"}),
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

    blend_path = os.path.join(outdir, "Source", "round_aurie_master.blend")
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
