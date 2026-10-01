"""Render the five launch pattern MASKS for one body.

    blender --background --factory-startup --python-exit-code 1 \
        --python build_pattern_masks.py -- --body round --outdir <dir>

ARCHITECTURE
    A pattern is not artwork. It is a greyscale MASK, rendered on the real
    3D body with the shipped camera, that says how much of the pattern
    colour applies at each pixel. The app already tints a neutral #C0C0C0
    body render by multiplying, which is what keeps the Blender shading; a
    mask lets the same shader multiply by a DIFFERENT colour where the mask
    is white, so the pattern inherits every highlight and every bit of
    curvature instead of covering them.

        out.rgb = bodyLuminance * mix(bodyTint, patternTint, mask)

    Because the mask is family-independent, the set is bodies x patterns,
    not bodies x families x patterns: 50 masks instead of 350, and adding
    an eighth family costs nothing.

    The patterns are evaluated in OBJECT space via shader nodes, so they
    wrap the actual geometry. A 2D overlay cannot do this — it would slide
    across the silhouette and read as a sticker, which is the failure mode
    the brief calls out.

    Seeded patterns (speckles, spots) are rendered as a few VARIANTS; the
    app picks one from the Aurie's persisted seed, so a creature's layout
    is stable forever without baking a mask per creature.
"""

import argparse
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import export_app_layers as E  # noqa: E402

# Patterns whose look is seeded per creature, and how many variants to bake.
VARIANTS = {"speckles": 3, "spots": 3, "stars": 3, "hearts": 3}
PATTERNS = ["stripes", "speckles", "spots", "stars", "hearts"]
# Stamps for the shaped speckles (stars_tile.png, hearts_tile.png).
# RESTORED 2026-09-17: the original tiles were lost (authored in a
# session scratchpad; generator never promoted). make_pattern_tiles.py
# now regenerates them DETERMINISTICALLY in-repo, calibrated against
# the shipped (approved) Round front masks. The shipped FRONT masks
# remain untouched; the previously-missing BACK masks render with the
# regenerated tiles, so patterns continue around the body.
TILES = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "..", "Source", "patterns_src")


def mask_material(name, build):
    """A material that renders a flat 0..1 mask, ignoring the light rig."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    coord = nt.nodes.new("ShaderNodeTexCoord")
    value = build(nt, coord)
    nt.links.new(value, emit.inputs["Color"])
    return mat


def _ramp(nt, src, lo, hi, invert=False):
    """Soft threshold. WHITE always means "pattern here".

    Element colours are set explicitly rather than relying on the default
    black-to-white order: several of these patterns want white at the LOW
    end (inside a patch, at a cell centre) and reading the default order
    backwards is what printed every pattern as its own negative.
    """
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.interpolation = "EASE"
    a, b = r.color_ramp.elements
    a.position, b.position = min(lo, hi), max(lo, hi)
    white = (1.0, 1.0, 1.0, 1.0)
    black = (0.0, 0.0, 0.0, 1.0)
    a.color, b.color = (white, black) if invert else (black, white)
    nt.links.new(src, r.inputs["Fac"])
    return r.outputs["Color"]


def _remap(nt, src, from_lo, from_hi):
    """Bring an object-space value into the 0..1 the ramps expect.

    Object coordinates run roughly -1..1 here, so feeding them straight to
    a colour ramp clamps everything outside 0..1 — which turned the belly
    gradient into a hard horizontal edge instead of a fade.
    """
    m = nt.nodes.new("ShaderNodeMapRange")
    m.clamp = True
    m.inputs["From Min"].default_value = from_lo
    m.inputs["From Max"].default_value = from_hi
    nt.links.new(src, m.inputs["Value"])
    return m.outputs["Result"]


def _sep(nt, coord):
    s = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Object"], s.inputs["Vector"])
    return s


def p_stripes(nt, coord, seed=0):
    """3-5 broad soft bands. Wave texture in object Z, so they ride the
    body's curvature and stay horizontal on tall and wide silhouettes
    alike rather than being one graphic stretched to fit."""
    w = nt.nodes.new("ShaderNodeTexWave")
    w.wave_type = "BANDS"
    w.bands_direction = "Z"
    w.wave_profile = "SIN"
    # Broad, not zebra: about four readable bands across the body.
    w.inputs["Scale"].default_value = 0.52
    w.inputs["Distortion"].default_value = 0.9
    w.inputs["Detail"].default_value = 1.0
    nt.links.new(coord.outputs["Object"], w.inputs["Vector"])
    return _ramp(nt, w.outputs["Fac"], 0.40, 0.60)


def p_speckles(nt, coord, seed=0):
    """Many small irregular marks. Voronoi at high scale gives varied size
    and spacing without the even wash of plain noise."""
    v = nt.nodes.new("ShaderNodeTexVoronoi")
    v.feature = "F1"
    v.inputs["Scale"].default_value = 8.0 + seed * 1.4
    v.inputs["Randomness"].default_value = 0.62   # spaced, not clumped
    m = nt.nodes.new("ShaderNodeMapping")
    m.inputs["Location"].default_value = (seed * 3.7, seed * 1.9, seed * 2.6)
    nt.links.new(coord.outputs["Object"], m.inputs["Vector"])
    nt.links.new(m.outputs["Vector"], v.inputs["Vector"])
    # Tight band = a round dot with a soft rim, instead of a smear that
    # fades out over the whole cell and reads as noise.
    return _ramp(nt, _remap(nt, v.outputs["Distance"], 0.0, 0.5),
                 0.15, 0.21, invert=True)


def _face_guard(nt, coord):
    """0 over the face, 1 everywhere else — a multiplier for any pattern
    that must not land on the features.

    Built in GENERATED space like the belly oval, so it tracks each body's
    own proportions instead of a fixed coordinate, and it includes the DEPTH
    axis so it only suppresses the front of the head. Guarding by height
    alone would have cleared a band right around the body.
    """
    return _face_field(nt, coord.outputs["Generated"], 0.56, 0.82)


def _face_field(nt, vec, lo, hi):
    """Distance-to-face field in generated space: ~0 over the face, ~1 away.

    `vec` is any generated-space point — the shading point for a per-pixel
    guard, or a spot's centre for a per-cell one. Centred between the eyes
    and the mouth and wide enough to clear both plus the cheeks; the depth
    axis keeps it on the FRONT of the head so it does not clear a band right
    around the body. `lo`/`hi` set the zone radius, so the same field can be
    a tight actual-face zone or a larger keep-out for whole spots.
    """
    s_ = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(vec, s_.inputs["Vector"])

    def off(src, centre, scale):
        sub = nt.nodes.new("ShaderNodeMath")
        sub.operation = "SUBTRACT"
        sub.inputs[1].default_value = centre
        nt.links.new(src, sub.inputs[0])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        mul.inputs[1].default_value = scale
        nt.links.new(sub.outputs["Value"], mul.inputs[0])
        return mul.outputs["Value"]

    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(off(s_.outputs["X"], 0.50, 1.00), comb.inputs["X"])
    nt.links.new(off(s_.outputs["Y"], 0.14, 0.75), comb.inputs["Y"])
    nt.links.new(off(s_.outputs["Z"], 0.60, 1.45), comb.inputs["Z"])
    length = nt.nodes.new("ShaderNodeVectorMath")
    length.operation = "LENGTH"
    nt.links.new(comb.outputs["Vector"], length.inputs[0])
    return _ramp(nt, _remap(nt, length.outputs["Value"], 0.0, 0.5), lo, hi)


# ---------------------------------------------------------------- ZONES
# A ZONE is not a pattern. Patterns are a per-creature cosmetic choice
# from a catalogue; a zone is part of every Aurie's body presentation
# and ships one mask per body, unseeded and unvariant. Zones therefore
# live OUTSIDE `PATTERNS`/`BUILDERS` and write `<body>_<zone>.png`, so
# nothing can accidentally offer "belly" as a pattern a user can pick.

# Belly zone, generated space (0..1 across this body's own bbox, so the
# numbers are proportions of EVERY body, never scene units):
#   X 0.5  = lateral midline
#   Y 0.12 = well toward the FRONT (generated Y runs front 0 -> back 1)
#   Z 0.31 = lower torso, between the legs and the face
# The axis scales divide the ellipsoid: a LARGER scale is a TIGHTER
# extent on that axis. Z is squashed hardest so the zone is a broad
# lower-front wash rather than a ball; Y is deliberately tight enough
# that the wash dies before the flank and is gone by the true back.
# The belly zone is DERIVED PER BODY, not constant: every body wears
# its face at a different height, so a fixed generated-space oval would
# ride over one body's mouth and float above another's legs. The zone
# fills the band between the mouth (minus a clearance gap) and the
# base, which is what makes it "as large as this body has room for" —
# Round's band is 0.332 of its height, Tall's is 0.411.
BELLY_MOUTH_GAP = 0.10     # of body height, kept clear under the mouth
BELLY_FLOOR = 0.02         # of body height, kept clear above the base
# The ramp's fade tail reaches past the visible edge, so the analytic
# half-extent runs wider than the band it must appear inside. 1.37 is
# the measured analytic:visible ratio — it reproduces the APPROVED
# Round oval exactly and carries to every other body unchanged.
BELLY_FILL_V = 1.37
# Half-width as a fraction of the body's own width. 0.338 analytic
# reads as ~58% of the silhouette — the approved Round value.
BELLY_HALFW = 0.338
BELLY_DEPTH_SCALE = 1.85   # keeps the zone frontal: no 3/4-back bleed


def belly_params(meas, pos):
    """Generated-space (centre, scale) for THIS body's belly oval."""
    h, btm, top = meas["height"], meas["bottom"], meas["top"]
    # mouth_z is the body's own measured face anchor; the fallback only
    # matters for a builder that never shipped one.
    mouth = pos.get("mouth_z", top - 0.35 * h)
    band_top = mouth - BELLY_MOUTH_GAP * h
    band_bot = btm + BELLY_FLOOR * h
    cz = (band_top + band_bot) / 2.0
    half = max((band_top - band_bot) / 2.0, 1e-4)
    gz_centre = (cz - btm) / h
    gz_half = BELLY_FILL_V * (half / h)
    return ((0.50, 0.10, gz_centre),
            (0.5 / BELLY_HALFW, BELLY_DEPTH_SCALE, 0.5 / gz_half))
# Ramp band: core out to `lo`, fading to nothing at `hi`. The gap is
# enormous on purpose — the brief forbids a traceable edge, so the
# feather is as long as the core is wide. `lo` is kept SMALL so the
# saturated core stays a small crest and almost the whole zone is
# gradient; a wide plateau reads as a decal edge no matter how soft
# its rim.
BELLY_LO, BELLY_HI = 0.45, 1.00


def z_belly(nt, coord, params=None):
    """A broad, edgeless lightening over the lower FRONT torso.

    Same ellipsoidal-distance machinery as `_face_field`, moved down and
    inverted so the centre is white. Generated space keeps it
    body-relative; the depth axis is what makes it a belly instead of a
    band right around the creature, and what makes it vanish on the
    turntable's back render without any special-casing.
    """
    centre, scales = params
    s_ = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Generated"], s_.inputs["Vector"])

    def off(src, centre, scale):
        sub = nt.nodes.new("ShaderNodeMath")
        sub.operation = "SUBTRACT"
        sub.inputs[1].default_value = centre
        nt.links.new(src, sub.inputs[0])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        mul.inputs[1].default_value = scale
        nt.links.new(sub.outputs["Value"], mul.inputs[0])
        return mul.outputs["Value"]

    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    for axis, c, s in zip("XYZ", centre, scales):
        nt.links.new(off(s_.outputs[axis], c, s), comb.inputs[axis])
    length = nt.nodes.new("ShaderNodeVectorMath")
    length.operation = "LENGTH"
    nt.links.new(comb.outputs["Vector"], length.inputs[0])
    field = _ramp(nt, _remap(nt, length.outputs["Value"], 0.0, 0.5),
                  BELLY_LO, BELLY_HI, invert=True)
    # sRGB PRE-COMPENSATION. Masks render through the "Standard" view
    # transform (linear -> sRGB) and the app samples them WITHOUT sRGB
    # decode. The shipped patterns are near-binary, so that mismatch
    # cancels at 0 and 1 and never mattered. A soft gradient lives
    # entirely in the midtones, where it does not: an authored 0.5
    # would be written as ~188 and read back as 0.74, shipping a belly
    # far stronger and larger than authored. Gamma 2.2 here is the
    # inverse of the encode, so the app reads what this graph draws.
    g = nt.nodes.new("ShaderNodeGamma")
    g.inputs["Gamma"].default_value = 2.2
    nt.links.new(field, g.inputs["Color"])
    return g.outputs["Color"]


ZONES = {"belly": z_belly}


def p_spots(nt, coord, seed=0):
    """A scatter of clean SOLID circles, varied in size, kept off the face.

    Voronoi F1 distance thresholded per cell is a disc centred on each
    feature point. Two things stop those discs reading as dirt: LOWER
    randomness so they stay round instead of clipping into polygons where
    cells crowd, and a TIGHT ramp so each circle is a filled shape with a
    crisp edge rather than a fuzzy smear. A per-cell random (the voronoi
    Color output) shifts each disc's radius, so the sizes vary like the
    reference instead of a uniform polka dot.

    Kept off the face by WHOLE SPOT, not per pixel. The earlier version
    multiplied a soft face field into the finished mask, which sliced any
    circle straddling the boundary into a crescent. Here the field is
    sampled at each spot's OWN CENTRE (the voronoi Position, unmapped back
    to generated space), so a spot is kept or dropped entirely and every
    shown circle is complete.
    """
    # Run the voronoi in GENERATED space so its Position output shares the
    # face field's space and can be tested directly.
    # Generated space spans 0..1 (half the range of object space), so the
    # mapping scale is ~2x the old object-space value to keep the same spot
    # count; the voronoi's own Scale is set to 1 so ONLY this mapping sizes
    # the cells (its 5.0 default would otherwise shrink them to dust).
    loc = (seed * 3.1, seed * 1.7, seed * 2.3)
    scale = 4.7
    m = nt.nodes.new("ShaderNodeMapping")
    m.inputs["Location"].default_value = loc
    m.inputs["Scale"].default_value = (scale, scale, scale * 0.9)
    nt.links.new(coord.outputs["Generated"], m.inputs["Vector"])
    v = nt.nodes.new("ShaderNodeTexVoronoi")
    v.feature = "F1"
    v.inputs["Scale"].default_value = 1.0
    v.inputs["Randomness"].default_value = 0.48
    nt.links.new(m.outputs["Vector"], v.inputs["Vector"])

    # Per-cell random -> a small +/- shift of the circle radius.
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(v.outputs["Color"], sep.inputs["Color"])
    jit = nt.nodes.new("ShaderNodeMapRange")
    jit.inputs["From Min"].default_value = 0.0
    jit.inputs["From Max"].default_value = 1.0
    jit.inputs["To Min"].default_value = -0.045
    jit.inputs["To Max"].default_value = 0.055
    nt.links.new(sep.outputs[0], jit.inputs["Value"])
    adj = nt.nodes.new("ShaderNodeMath")
    adj.operation = "ADD"
    nt.links.new(_remap(nt, v.outputs["Distance"], 0.0, 1.0), adj.inputs[0])
    nt.links.new(jit.outputs["Result"], adj.inputs[1])

    # Tight band = a filled circle with a crisp, faintly plush edge.
    spots = _ramp(nt, adj.outputs["Value"], 0.20, 0.25, invert=True)

    # Un-map the cell centre back to generated space: gen = (Position - L)/S.
    subv = nt.nodes.new("ShaderNodeVectorMath")
    subv.operation = "SUBTRACT"
    nt.links.new(v.outputs["Position"], subv.inputs[0])
    subv.inputs[1].default_value = loc
    genpos = nt.nodes.new("ShaderNodeVectorMath")
    genpos.operation = "DIVIDE"
    nt.links.new(subv.outputs["Vector"], genpos.inputs[0])
    genpos.inputs[1].default_value = (scale, scale, scale * 0.9)

    # Per-cell keep (LARGER, sharper zone so a kept spot never reaches the
    # face) times a per-pixel guard on the actual face as insurance. Because
    # the cell zone is bigger, the pixel guard never has to slice anything.
    cell_keep = _face_field(nt, genpos.outputs["Vector"], 0.74, 0.90)

    m1 = nt.nodes.new("ShaderNodeMix")
    m1.data_type, m1.blend_type = "RGBA", "MULTIPLY"
    m1.inputs["Factor"].default_value = 1.0
    nt.links.new(spots, m1.inputs[6])
    nt.links.new(cell_keep, m1.inputs[7])

    m2 = nt.nodes.new("ShaderNodeMix")
    m2.data_type, m2.blend_type = "RGBA", "MULTIPLY"
    m2.inputs["Factor"].default_value = 1.0
    nt.links.new(m1.outputs[2], m2.inputs[6])
    nt.links.new(_face_guard(nt, coord), m2.inputs[7])
    return m2.outputs[2]


def _stamped(nt, coord, tile, seed, scale):
    """Project a tileable stamp onto the body.

    Node maths cannot describe a five-point star or a heart, so these use a
    small image stamp with BOX projection: it wraps a rounded body from
    three directions and keeps the shape crisp, which a procedural
    approximation would not.
    """
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(os.path.join(TILES, tile))
    img.projection = "BOX"
    img.projection_blend = 0.35
    img.extension = "REPEAT"
    img.interpolation = "Cubic"
    m = nt.nodes.new("ShaderNodeMapping")
    m.inputs["Scale"].default_value = (scale, scale, scale)
    m.inputs["Location"].default_value = (seed * 0.37, seed * 0.21,
                                          seed * 0.29)
    nt.links.new(coord.outputs["Object"], m.inputs["Vector"])
    nt.links.new(m.outputs["Vector"], img.inputs["Vector"])
    return _ramp(nt, img.outputs["Color"], 0.42, 0.58)


def p_stars(nt, coord, seed=0):
    """Small five-point stars, evenly scattered."""
    return _stamped(nt, coord, "stars_tile.png", seed, 1.55)


def p_hearts(nt, coord, seed=0):
    """Small hearts, evenly scattered."""
    return _stamped(nt, coord, "hearts_tile.png", seed, 1.55)


BUILDERS = {"stripes": p_stripes,
            "speckles": p_speckles, "spots": p_spots,
            "stars": p_stars, "hearts": p_hearts}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--body", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--samples", type=int, default=24)
    ap.add_argument("--only", default="",
                    help="comma-separated pattern names, for a partial rerun")
    ap.add_argument("--zone", default="",
                    help="render body-presentation ZONES instead of "
                         "patterns (e.g. 'belly'). Zones ship one mask "
                         "per body as <body>_<zone>.png — they are not "
                         "selectable patterns and are never seeded.")
    ap.add_argument("--orientation", default="front",
                    choices=["front", "back"],
                    help="back = rotate the BODY 180 deg under the fixed "
                         "camera (the approved turntable). Patterns are "
                         "OBJECT-SPACE so the back render is their real "
                         "backside.")
    args = ap.parse_args(argv)
    out = os.path.abspath(args.outdir)
    os.makedirs(out, exist_ok=True)

    name = args.body
    (mod, scene, cols, R, centre, surf, pos, arm, foot,
     fixed_m) = E.build_body(name)
    cols["STAGE"].hide_render = True
    scene.cycles.samples = args.samples
    # A mask is flat emission; lights and world would only add noise.
    for c in cols.values():
        for ob in c.objects:
            if ob.type == "LIGHT":
                ob.hide_render = True
    scene.world = None
    cam = scene.camera
    cam.data.ortho_scale *= 1.08          # same framing as the layer export

    for cname, col in cols.items():
        if cname != "RIG":
            col.hide_render = cname != "BODY"

    bodies = [ob for ob in cols["BODY"].objects if ob.type == "MESH"]
    # Back orientation: the approved turntable — rotate the BODY under
    # the fixed camera. Patterns are OBJECT-SPACE shaders, so the back
    # render IS the pattern's real backside, registered to the back
    # body layer.
    osfx = "_back" if args.orientation == "back" else ""
    if args.orientation == "back":
        import math as _math
        turn = bpy.data.objects.new("TurnPivot", None)
        scene.collection.objects.link(turn)
        turn.rotation_euler = (0.0, 0.0, _math.pi)
        from mathutils import Matrix
        for ob in bodies:
            # identity inverse — the body-local attachment invariant
            # (see export_app_layers.orient_new); the pivot's own
            # matrix is lazily computed and must never be read here
            ob.parent = turn
            ob.matrix_parent_inverse = Matrix.Identity(4)
        bpy.context.view_layer.update()
    original = [list(ob.data.materials) for ob in bodies]

    if args.zone:
        for zone in [z for z in args.zone.split(",") if z]:
            if zone not in ZONES:
                sys.exit(f"unknown zone {zone}; have {sorted(ZONES)}")
            zp = belly_params(E.measure_body(cols), pos)
            print(f"AURIE ZONE {zone} params centre={tuple(round(v,3) for v in zp[0])} "
                  f"scale={tuple(round(v,3) for v in zp[1])}")
            mat = mask_material(f"Zone_{zone}",
                                lambda nt, c, z=zone, p=zp: ZONES[z](nt, c, p))
            for ob in bodies:
                ob.data.materials.clear()
                ob.data.materials.append(mat)
            scene.render.filepath = f"{out}/{name}_{zone}{osfx}.png"
            bpy.ops.render.render(write_still=True)
            print("AURIE ZONE:", os.path.basename(scene.render.filepath))
        for ob, mats in zip(bodies, original):
            ob.data.materials.clear()
            for m in mats:
                ob.data.materials.append(m)
        print(f"AURIE ZONES DONE {name}")
        return

    wanted = [x for x in args.only.split(",") if x] or PATTERNS
    for pat in wanted:
        for v in range(VARIANTS.get(pat, 1)):
            mat = mask_material(f"Mask_{pat}_{v}",
                                lambda nt, c, p=pat, s=v: BUILDERS[p](nt, c, s))
            for ob in bodies:
                ob.data.materials.clear()
                ob.data.materials.append(mat)
            suffix = f"_v{v}" if pat in VARIANTS else ""
            scene.render.filepath = (f"{out}/{name}_pattern_{pat}{suffix}{osfx}.png")
            bpy.ops.render.render(write_still=True)
            print("AURIE MASK:", os.path.basename(scene.render.filepath))

    for ob, mats in zip(bodies, original):
        ob.data.materials.clear()
        for m in mats:
            ob.data.materials.append(m)
    print(f"AURIE PATTERNS DONE {name}")


if __name__ == "__main__":
    main()
