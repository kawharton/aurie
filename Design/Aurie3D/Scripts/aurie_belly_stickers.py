"""BELLY STICKERS — the approved catalog, fit rule and tone grade.

PRODUCTION SOURCE. Reference implementation of the belly-sticker
presentation approved on 2026-09-16. Values here are APPROVED; do not
retune them without a fresh visual review.

ARCHITECTURE
    * ONE flat PNG per charm — not per body, not per orientation. The
      library's `_THUMBNAILS/<id>.png` are already exactly that
      (512 square, transparent, one camera for all), so a new charm
      costs one preview rather than twenty per-body renders.
    * Placement comes from generated metadata: `aurie_belly.belly_core`
      gives the belly zone's solid core per body, and the sticker is
      centred in it. No hand-tuned coordinates anywhere.
    * Front-only: the sticker is simply not drawn for other
      orientations. Runtime has no 3/4, so this is one check.
    * Untinted: a charm keeps its own colours, like every other charm.
    * Draw order: the reserved `Z.pattern = 3` seam, which the Blender
      path never uses, sits correctly above the body group and below
      the face.
"""
import numpy as np
from PIL import Image

LIBRARY_THUMBS = "AurieCharmLibrary/_THUMBNAILS"

# --- approved sticker catalog (2026-09-16) -----------------------------
# Clownfish was removed on review: long, low-contrast and horizontally
# busy, so it blurred into the pale area instead of reading as a motif.
STICKERS = [
    ("charm_food_apple_01", "Apple"),
    ("charm_nature_pumpkin_01", "Pumpkin"),
    ("charm_food_pizza_01", "Pizza"),
    ("charm_magic_crystal_02", "Crystal"),
    ("charm_magic_star_01", "Star"),
    ("charm_nature_flower_03", "Pink Blossom"),
    ("charm_food_tomato_01", "Tomato"),
    ("charm_magic_star_coin_01", "Star Coin"),
]

# --- approved presentation ---------------------------------------------
STICKER_SIZE = 0.72        # of the fitted scale; 0.75 read too dominant,
                           # 0.65 risked being too small on a phone
# The fit binds on BOTH axes. Width alone was not enough: the core is
# wide and short, so tall stickers (Star, Crystal, Star Coin) spilled
# out of the pale area onto the darker body.
FIT_WIDTH_K = 0.62
FIT_HEIGHT_K = 0.88

# EXTRA SOFT PASTEL. The SHADOW LIFT runs first and is the heart of the
# look: raising the darkest values is what dissolves the baked 3D
# shading that makes these read as miniature objects. Because a lift
# also raises value and drops saturation on its own, `sat` runs ABOVE
# 1.0 to put the colour back and `val` trims the brightness the lift
# over-delivered. Measured on the ink: saturation -18.7%, value +10.1%,
# contrast -25.4%, darkest decile lifted +46..+93%.
GRADE = dict(lift=0.165, contrast=0.955, sat=1.225, val=0.935)

# PER-CHARM TRIMS on top of the shared grade. Mean luminance did NOT
# identify the bright outliers — HSV value and peak highlight did:
# Crystal carried the brightest speculars, Pink Blossom the highest
# value (hot magenta), Tomato a hard highlight over dark red. Trims
# can pull in either direction (Pumpkin's raises); a future charm only
# needs an entry here if it misbehaves — the default stays one global
# grade. `val`/`sat` multiply the grade's; `lift` ADDS to it, for
# charms whose baked shadow survives the shared lift (Tomato).
CHARM_TRIM = {
    "charm_magic_crystal_02": dict(val=0.88, sat=0.90),
    "charm_nature_flower_03": dict(val=0.87, sat=0.88),
    # 2026-09-17 polish: extra shadow lift on the dark lower shading
    # (darkest decile +32%), sat compensated up so it stays clearly
    # red (0.446 vs set avg 0.451); val trim untouched — no global
    # brightening.
    "charm_food_tomato_01":   dict(val=0.90, sat=0.96, lift=0.08),
    # 2026-09-17 polish: was slightly muddy/brown — smallest raise
    # that lands it on the set averages (sat 0.472/val 0.596 vs set
    # 0.451/0.585).
    "charm_nature_pumpkin_01": dict(val=1.05, sat=1.10),
}


def style_for(charm_id, base=GRADE):
    """The shared grade with any per-charm trim folded in."""
    if base is None:
        return None
    st = dict(base)
    trim = CHARM_TRIM.get(charm_id)
    if trim:
        st["val"] = st.get("val", 1.0) * trim.get("val", 1.0)
        st["sat"] = st.get("sat", 1.0) * trim.get("sat", 1.0)
        st["lift"] = st.get("lift", 0.0) + trim.get("lift", 0.0)
    return st


def treat(rgb, a, lift=0.0, contrast=1.0, sat=1.0, val=1.0):
    """The pastel grade. Order matters — see GRADE.

    Silhouette, alpha and the transparent background are never touched;
    only the ink is graded.
    """
    ink = a > 0.35
    if not ink.any():
        return rgb
    out = lift + (1.0 - lift) * rgb                      # shadow lift
    mid = float(out.mean(axis=-1, keepdims=True)[ink].mean())
    out = mid + (out - mid) * contrast                   # contrast
    lum = out.mean(axis=-1, keepdims=True)
    out = lum + (out - lum) * sat                        # saturation
    return np.clip(out * val, 0.0, 1.0)                  # value trim


def sticker_layer(canvas_shape, charm_id, core_centre, core_size,
                  repo_root=".", size=STICKER_SIZE, graded=True):
    """A full-canvas premultiplied RGBA layer holding the sticker.

    `core_centre`/`core_size` come from `aurie_belly.belly_core`, so the
    sticker scales to each body's own belly rather than a fixed size.
    """
    path = f"{repo_root}/{LIBRARY_THUMBS}/{charm_id}.png"
    im = Image.open(path).convert("RGBA")
    im = im.crop(im.getchannel("A").getbbox())          # trim empty frame
    scale = min(FIT_WIDTH_K * core_size[0] / im.width,
                FIT_HEIGHT_K * core_size[1] / im.height) * size
    new = (max(int(round(im.width * scale)), 1),
           max(int(round(im.height * scale)), 1))
    im = im.resize(new, Image.LANCZOS)
    arr = np.asarray(im).astype(np.float64) / 255.0
    rgb, a = arr[..., :3], arr[..., 3]
    if graded:
        st = style_for(charm_id)
        if st:
            rgb = treat(rgb, a, **st)
    out = np.zeros((canvas_shape[0], canvas_shape[1], 4))
    x0 = int(round(core_centre[0] - new[0] / 2))
    y0 = int(round(core_centre[1] - new[1] / 2))
    out[y0:y0 + new[1], x0:x0 + new[0]] = np.concatenate(
        [rgb, a[..., None]], axis=-1)
    return np.concatenate([out[..., :3] * out[..., 3:4], out[..., 3:4]],
                          axis=-1)
