"""BELLY AREA — the approved belly-layer compositing rules.

PRODUCTION SOURCE. This is the reference implementation of the belly
presentation that was approved on 2026-09-16; the Swift integration
must reproduce these rules exactly, and the review tooling imports
them rather than restating them.

WHAT THE BELLY IS
    A FRONT-ONLY 2D art layer, not a shader term:

        belly.rgb = the BODY's own beauty render  (so it carries that
                    body's exact shading and curvature, which is what
                    makes it read as body COLORATION rather than a
                    light shining on the creature)
        belly.a   = body alpha x soft zone falloff x peak

    drawn over the body with the standard tint shader fed a PALER
    family colour. Nothing multiplies luminance, so nothing can glow —
    an earlier luminance-mask version read as a spotlight and was
    rejected.

WHERE THE ZONE COMES FROM
    The soft falloff itself is rendered by `build_pattern_masks.py`
    (`--zone belly`), whose `belly_params()` derives each body's oval
    from that body's own measured mouth height and base. Nothing here
    hardcodes a per-body number.

WHY PATTERNED BODIES DIFFER
    On a patterned Aurie the belly OCCLUDES the markings instead of
    lightening them: inside the belly the pale area is one solid body
    colour, so a stripe stops at the belly edge instead of ghosting
    through it, and the belly is authored slightly darker there so it
    reads as solid coloration rather than a translucent wash.
"""
import numpy as np
from PIL import Image

# Must match AurieBlenderSkin.neutralAlbedo (0xC0) and
# export_app_layers.NEUTRAL. The app tints by colour/192.
NEUTRAL_ALBEDO = 192.0

# --- approved presentation constants (2026-09-16) ----------------------
BELLY_PEAK = 0.85          # layer alpha at the zone core, plain body
BELLY_PALENESS = 0.52      # how far the belly colour sits toward white
PATTERNED_PEAK = 1.00      # fully opaque core, so markings cannot show
PATTERNED_PALENESS = 0.38  # and a touch darker, so it reads as solid

# --- approved belly-PATCH edge profile (2026-09-17, Round) -------------
# The belly reads as a defined patch, not a fog: the zone's long
# feather is remapped to a solid boundary with a slight soft rim
# (~8 px at the 1024 render). Half-width in ZONE-VALUE space, centred
# on the same 0.5 iso-line bellyCore thresholds at — so the visible
# boundary and the sticker-placement rect coincide and bellyCore is
# byte-identical under this remap.
# STATUS: approved on Round; the 10-body rollout review is still a
# pending gate before production install.
PATCH_EDGE = 0.16


def patch_zone(zone, edge=PATCH_EDGE):
    """The approved patch profile: smoothstep the zone about 0.5."""
    t = np.clip((zone[..., :1] - (0.5 - edge)) / (2 * edge), 0, 1)
    s = t * t * (3 - 2 * t)
    return np.repeat(s, 4, axis=-1)


def tint_vec(rgb):
    return np.array(rgb, dtype=np.float64) / NEUTRAL_ALBEDO


def darken(rgb, f=0.34):
    """The pattern colour, matching AurieNode's darken(baseColor, 0.34)."""
    return tuple(v * (1.0 - f) for v in rgb)


def pale(rgb, f):
    """The belly's albedo: the family colour blended toward white.

    Matches the reference, whose belly is ~55% less saturated than the
    body while its luminance barely moves.
    """
    return tuple(v + (255.0 - v) * f for v in rgb)


def load_rgba(path):
    """Straight-alpha float RGBA in 0..1."""
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float64) / 255.0


def over(dst, src):
    """Premultiplied source-over."""
    oa = src[..., 3:4] + dst[..., 3:4] * (1 - src[..., 3:4])
    rgb = src[..., :3] + dst[..., :3] * (1 - src[..., 3:4])
    return np.concatenate([rgb, oa], axis=-1)


def build_belly_layer(body, zone, peak):
    """The shipped belly PNG: body pixels cut out by the soft zone."""
    a = body[..., 3:4] * zone[..., :1] * peak
    return np.concatenate([body[..., :3], a], axis=-1)


def belly_core(zone, body_alpha, thresh=0.5):
    """`bellyCore` — the zone's SOLID core, as (centre, size) in pixels.

    This is the rect the installer should emit for sticker placement.
    The belly layer's own bbox includes its long feather and therefore
    overstates the usable area, so placement uses the alpha>0.5 region
    instead. Derived per body; never hand-tuned.
    """
    m = (zone[..., 0] > thresh) & (body_alpha > 0.5)
    ys, xs = np.nonzero(m)
    return (np.array([(xs.min() + xs.max()) / 2.0,
                      (ys.min() + ys.max()) / 2.0]),
            np.array([xs.max() - xs.min(), ys.max() - ys.min()]))


def compose(body, zone=None, mask=None, colour=(120, 190, 110),
            peak=BELLY_PEAK, paleness=BELLY_PALENESS,
            occlude_pattern=True):
    """Body (+ optional pattern) with the belly layer drawn over it.

    Reproduces the shipped body shader
    (AurieBlenderSkin.patternTintShaderSource) including the
    `min(..., c.a)` clamp, then composites the belly layer on top.
    """
    c = body[..., :3] * body[..., 3:4]          # premultiply, as SpriteKit
    a = body[..., 3:4]
    t = tint_vec(colour)
    if mask is not None:
        m = mask[..., :1]
        t = t * (1 - m) + tint_vec(darken(colour)) * m
    out = np.concatenate([np.minimum(c * t, a), a], axis=-1)
    if zone is None or peak <= 0:
        return out

    if mask is not None and occlude_pattern:
        layer = build_belly_layer(body, zone, PATTERNED_PEAK)
        bt = tint_vec(pale(colour, PATTERNED_PALENESS))
        rgb = np.minimum(layer[..., :3] * layer[..., 3:4] * bt, layer[..., 3:4])
    else:
        layer = build_belly_layer(body, zone, peak)
        bt = tint_vec(pale(colour, paleness))
        rgb = np.minimum(layer[..., :3] * layer[..., 3:4] * bt, layer[..., 3:4])
    return over(out, np.concatenate([rgb, layer[..., 3:4]], axis=-1))


def to_image(arr):
    """Premultiplied float RGBA -> PIL image."""
    rgb = np.clip(np.divide(arr[..., :3], np.maximum(arr[..., 3:4], 1e-6)), 0, 1)
    return Image.fromarray(
        (np.concatenate([rgb, arr[..., 3:4]], axis=-1) * 255)
        .round().astype(np.uint8))
