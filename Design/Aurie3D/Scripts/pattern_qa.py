"""Pattern QA sheets, composited exactly the way the runtime shader will.

    python3 pattern_qa.py

The app tints a neutral #C0C0C0 body render by MULTIPLYING, which is what
keeps the Blender shading. A pattern does not paint over that render — it
changes WHICH colour gets multiplied in:

    out.rgb = bodyLuminance * mix(bodyTint, patternTint, mask)

This script does that arithmetic in Python so the sheet is a faithful
preview of the shader rather than an artist's impression of it. If a
pattern looks pasted on here, it will look pasted on in the app.
"""

import colorsys
import pathlib

from PIL import Image, ImageDraw, ImageFont
import numpy as np

AC_CANVAS_PT = 538.9474
Y_SHIFT_PT = -9.0

import aurie_composite as AC

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
MASKS = pathlib.Path("/private/tmp/claude-502/-Users-Shared-claude-work/"
                     "521c3611-482c-4647-b17d-de610a41ca43/scratchpad/patterns")
OUTDIR = REPO / "Design/Aurie3D/Previews"

BODIES = ["round", "tall", "small", "pear", "beanbag", "heart"]
FAMILIES = ["ember", "moss", "dusk", "tide"]
PATTERNS = ["stripes", "speckles_v0", "spots_v0", "stars_v0", "hearts_v0"]
# The ones redone since the first review, for the before/after sheet.
REVISED = ["speckles_v0", "spots_v0"]
BEFORE = MASKS.parent / "patterns_before"
NEUTRAL = 192.0

# How each pattern's colour is derived from the family colour. Never a fixed
# palette: the shift is applied to whatever the family is, so one rule keeps
# the pattern readable on Stone as well as on Ember.
#   dv  value shift, ds  saturation scale, dh  hue rotation (turns)
SHIFT = {
    "stripes":        dict(dv=-0.17, ds=1.05, dh=-0.010),
    "speckles":       dict(dv=-0.22, ds=1.12, dh=-0.006),
    # DARKER again, now that the mask is clean solid circles rather than
    # muddy blotches. On a defined disc a darker, slightly more saturated
    # tone reads as an intentional spot (the reference's darker-on-body
    # marking) instead of the dirt it looked like on a fuzzy smear.
    "spots":          dict(dv=-0.17, ds=1.05, dh=+0.014),
    "stars":          dict(dv=+0.26, ds=0.70, dh=+0.014),
    "hearts":         dict(dv=+0.24, ds=0.86, dh=-0.018),
}

INK, MUTED, PAPER, PANEL, LINE = ((34, 30, 44), (122, 116, 138),
                                  (250, 248, 252), (255, 255, 255),
                                  (226, 221, 234))


def font(size, bold=False):
    for base in ("/System/Library/Fonts/",
                 "/System/Library/Fonts/Supplemental/"):
        p = pathlib.Path(base) / "HelveticaNeue.ttc"
        if p.exists():
            try:
                return ImageFont.truetype(str(p), size, index=1 if bold else 0)
            except OSError:
                pass
    return ImageFont.load_default()


def pattern_colour(family_rgb, pattern):
    """Coordinate with the body colour without matching or fighting it."""
    key = pattern.split("_v")[0]
    sh = SHIFT[key]
    r, g, b = (c / 255.0 for c in family_rgb)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    h = (h + sh["dh"]) % 1.0
    s = max(0.0, min(1.0, s * sh["ds"]))
    v = max(0.06, min(1.0, v + sh["dv"]))
    return tuple(int(round(c * 255)) for c in colorsys.hsv_to_rgb(h, s, v))


def apply_pattern(body, family, pattern, px_per_pt, mask_dir=None):
    """Tint the BODY layer through the mask, then compose normally.

    The patterned body is handed to the compositor rather than pasted over
    the finished creature — pasting it on top covered the face, which is
    the same "layer drawn over everything" mistake the pattern system as a
    whole exists to avoid.
    """
    rgb = AC.FAMILY_COLOURS[family]
    if pattern == "none":
        return AC.compose(body=body, family=family, arm="arm_01",
                          leg="leg_01", face="happy",
                          px_per_pt=px_per_pt)[0]

    mpath = (mask_dir or MASKS) / f"{body}_pattern_{pattern}.png"
    spec = AC._manifest()[body]["layers"]["body"]
    src = (REPO / "Auries/Assets.xcassets/AurieBlender"
           / f'{spec["asset"]}.imageset' / f'{spec["asset"]}.png')
    if not mpath.exists() or not src.exists():
        return AC.compose(body=body, family=family, arm="arm_01",
                          leg="leg_01", face="happy",
                          px_per_pt=px_per_pt)[0]

    plain = Image.open(src).convert("RGBA")
    # The mask is a full-canvas render; the body PNG was cropped to its own
    # alpha bbox at install. Cropping the mask to that same bbox is what
    # keeps the two pixel-registered.
    mask = Image.open(mpath).convert("L")
    bbox = _uncropped_bbox(body)
    mask = mask.crop(bbox).resize(plain.size, Image.LANCZOS)

    lum = np.asarray(plain, dtype=np.float32) / 255.0
    mk = (np.asarray(mask, dtype=np.float32) / 255.0)[..., None]
    base = np.array(rgb, dtype=np.float32) / NEUTRAL
    pat = np.array(pattern_colour(rgb, pattern), dtype=np.float32) / NEUTRAL
    tint = base * (1.0 - mk) + pat * mk
    out = np.clip(lum[..., :3] * tint, 0.0, 1.0) * 255.0
    tinted = np.dstack([out, np.asarray(plain, dtype=np.float32)[..., 3:]])
    patterned = Image.fromarray(tinted.astype(np.uint8))

    return AC.compose(body=body, family=family, arm="arm_01", leg="leg_01",
                      face="happy", px_per_pt=px_per_pt,
                      body_image=patterned)[0]


_BBOX = {}


def _uncropped_bbox(body):
    """Where the body sat on the shared 1024 canvas before install cropped
    it. Recovered from the manifest, which is the only record of it."""
    if body in _BBOX:
        return _BBOX[body]
    spec = AC._manifest()[body]["layers"]["body"]
    scale = 1024.0 / AC_CANVAS_PT
    w = float(spec["w"]) * scale
    h = float(spec["h"]) * scale
    cx = 512.0 + float(spec["x"]) * scale
    cy = 512.0 - (float(spec["y"]) + Y_SHIFT_PT) * scale
    box = (round(cx - w / 2), round(cy - h / 2),
           round(cx + w / 2), round(cy + h / 2))
    _BBOX[body] = box
    return box


def sheet(cells, cols, title, subtitle, out):
    boxes = [im.getbbox() or (0, 0, 1, 1) for _, im in cells]
    cw = max(b[2] - b[0] for b in boxes) + 22
    ch = max(b[3] - b[1] for b in boxes) + 16
    label_h, head_h, GAP = 30, 100, 9
    rows = (len(cells) + cols - 1) // cols
    W, H = cols * (cw + GAP) + GAP, head_h + rows * (ch + label_h + GAP) + GAP
    sh = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(sh)
    d.text((GAP + 8, 24), title, font=font(29, True), fill=INK)
    d.text((GAP + 8, 62), subtitle, font=font(15), fill=MUTED)
    for i, ((cap, sub), im) in enumerate(cells):
        cx = GAP + (i % cols) * (cw + GAP)
        cy = head_h + (i // cols) * (ch + label_h + GAP)
        d.rounded_rectangle([cx, cy, cx + cw, cy + ch + label_h], 9,
                            fill=PANEL, outline=LINE)
        crop = im.crop(im.getbbox())
        sh.paste(crop, (cx + (cw - crop.width) // 2,
                        cy + (ch - crop.height) // 2), crop)
        d.text((cx + 11, cy + ch + 1), cap, font=font(14, True), fill=INK)
        d.text((cx + 11, cy + ch + 17), sub, font=font(11), fill=MUTED)
    sh.save(out)
    return out


def main():
    OUTDIR.mkdir(parents=True, exist_ok=True)
    px = 0.62
    fam_of = dict(zip(BODIES, ["ember", "moss", "dusk", "tide", "ember",
                               "moss"]))

    cells = []
    for body in BODIES:
        for pat in ["none"] + PATTERNS:
            im = apply_pattern(body, fam_of[body], pat, px)
            cells.append(((f"{body} · {pat.replace('_v0', '')}",
                           fam_of[body]), im))
    a = sheet(cells, 6, "Launch patterns on the real Blender bodies",
              "mask x tint, exactly as the runtime shader composites it · "
              "body shading is never painted over",
              OUTDIR / "preview_patterns_bodies.png")

    # ---- before / after for the four that were redone ----
    cells = []
    for body in BODIES:
        for pat in REVISED:
            for tag, mdir in (("before", BEFORE), ("after", MASKS)):
                im = apply_pattern(body, fam_of[body], pat, px, mask_dir=mdir)
                cells.append(((f"{body} · {pat.replace('_v0', '')}",
                               tag.upper()), im))
    c = sheet(cells, 8, "Revised patterns — before and after",
              "belly oval, speckles, gradient belly and spots rebuilt · "
              "stripes deliberately untouched",
              OUTDIR / "preview_patterns_revised.png")
    print(f"wrote {c}")

    cells = []
    for fam in FAMILIES:
        for pat in ["none"] + PATTERNS:
            im = apply_pattern("round", fam, pat, px)
            cells.append(((f"{fam} · {pat.replace('_v0', '')}",
                           "pattern colour derived from the family"), im))
    b = sheet(cells, 6, "Pattern colour across families",
              "one rule per pattern, applied to whatever the family colour "
              "is — the palette itself is unchanged",
              OUTDIR / "preview_patterns_families.png")
    print(f"wrote {a}\nwrote {b}")


if __name__ == "__main__":
    main()
