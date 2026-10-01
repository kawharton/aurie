#!/usr/bin/env python3
"""Belly-sticker review sheet for the 2D Birth-Charm masters.

    python3 make_sticker_review.py

Reads the extracted masters (Design/Charms/Masters — never modified),
sizes every item by the FROZEN runtime belly fit against the real
installed round-body bellyCore, and renders review bands: neutral
dark / pale belly / darker belly (zoomed for inspection), a TRUE
actual-size band (@2x device pixels), and a previous-vs-new size
comparison. The shipped graded Apple sticker rides along at its
unchanged fit as the scale reference.

Per-sticker presentation comes from sticker_tuning.TUNING (scale +
visual-centering offsets) — the ONE source of truth shared with
install_review_stickers.py, which bakes the same values into the
review imagesets the on-Aurie proof wears.
"""
import pathlib

from PIL import Image, ImageDraw

REPO = pathlib.Path(__file__).resolve().parents[3]
MASTERS = REPO / "Design/Charms/Masters"
APPLE = (REPO / "Auries/Assets.xcassets/Charms/"
         "belly_sticker_charm_food_apple_01.imageset/"
         "belly_sticker_charm_food_apple_01.png")
OUT = REPO / "aurie-review-evidence/birth_charms/ev_2d_sticker_review.png"

NAMES = ["birth_teddy", "birth_mug", "birth_teacup", "birth_beach_ball",
         "birth_balloon", "birth_strawberry", "birth_orange",
         "birth_lemon", "birth_carrot", "birth_cake", "birth_cookie"]

import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sticker_tuning import TUNING  # noqa: E402

COREW, COREH = 126 * 2, 86 * 2   # real round-body bellyCore, @2x px
NAMES = list(TUNING)
COMPARE = ["birth_teddy", "birth_balloon", "birth_carrot",
           "birth_cake", "birth_cookie", "birth_strawberry"]


def fitted(im, boost, reduce=1.0):
    im = im.crop(im.getchannel("A").getbbox())
    s = min(0.62 * COREW / im.width,
            0.88 * COREH / im.height) * 0.72 * reduce * boost
    return im.resize((max(1, int(im.width * s)),
                      max(1, int(im.height * s))), Image.LANCZOS)


def items(boost, reduce):
    xs = [(n.replace("birth_", ""),
           fitted(Image.open(MASTERS / f"{n}.png"), boost,
                  TUNING[n][0] * reduce))
          for n in NAMES]
    xs.append(("APPLE (ref)", fitted(Image.open(APPLE), boost)))  # 1.0
    return xs


def main():
    cell = 260
    bands = [
        ("neutral dark - 1.6x zoom", (30, 32, 40), None, 1.6),
        ("pale Aurie belly - 1.6x zoom", (126, 168, 228),
         (217, 228, 245), 1.6),
        ("darker Aurie belly - 1.6x zoom", (138, 70, 64),
         (201, 150, 143), 1.6),
        ("TRUE ACTUAL SIZE (@2x device px) - pale belly",
         (126, 168, 228), (217, 228, 245), 1.0),
        ("COMPARE - previous (left) vs new -12%% (right), 1.6x zoom",
         (126, 168, 228), (217, 228, 245), 1.6),
    ]
    heights = [cell + 42, cell + 42, cell + 42, 190, cell + 42]
    w = cell * 12
    sheet = Image.new("RGB", (w, sum(heights)), (16, 17, 21))
    d = ImageDraw.Draw(sheet)
    y0 = 0
    for bi, (label, body, patch, boost) in enumerate(bands):
        bh = heights[bi]
        d.rectangle([0, y0, w, y0 + bh - 22], fill=body)
        if bi < 4:
            band = items(boost, 1.0)
        else:
            band = []
            for n in COMPARE:            # old | new pairs
                old = fitted(Image.open(MASTERS / f"{n}.png"), boost)
                new = fitted(Image.open(MASTERS / f"{n}.png"), boost,
                             TUNING[n][0])
                band += [(n.replace("birth_", "") + " OLD", old),
                         (n.replace("birth_", "") + " NEW", new)]
        centers = []
        for i, (n, img) in enumerate(band):
            cx = i * cell + cell // 2
            cy = y0 + (bh - 22) // 2 + 8
            centers.append((cx, cy, img))
            if patch:
                r = min(max(img.width, img.height) * 0.80,
                        cell / 2 - 10)
                d.ellipse([cx - r, cy - r * 0.78, cx + r, cy + r * 0.78],
                          fill=patch)
        for cx, cy, img in centers:
            sheet.paste(img, (cx - img.width // 2,
                              cy - img.height // 2), img)
        d.text((8, y0 + 4), label, fill=(255, 255, 255))
        for i, (n, _) in enumerate(band):
            d.text((i * cell + 10, y0 + bh - 18), n,
                   fill=(235, 235, 240))
        y0 += bh
    OUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT)
    print(f"review -> {OUT}  ({sheet.size[0]}x{sheet.size[1]}) "
          f"per-sticker tuning from sticker_tuning.py")


if __name__ == "__main__":
    main()
