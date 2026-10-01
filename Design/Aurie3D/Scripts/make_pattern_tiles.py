#!/usr/bin/env python3
"""Regenerate the stars/hearts pattern STAMP tiles — deterministic.

    python3 make_pattern_tiles.py

The originals were lost (authored in a session scratchpad that no
longer exists; the generator was never promoted — the exact failure
this file fixes by LIVING IN THE REPO). Writes
Design/Aurie3D/Source/patterns_src/{stars,hearts}_tile.png:
white shape on black, one shape at the tile centre plus wrapped copies
at the corners, so REPEAT box-projection lays a diamond lattice —
matching the shipped (approved) front masks, which were calibrated
against these regenerated tiles on Round before the missing BACK masks
were rendered with them.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Source", "patterns_src")
N = 512                    # tile size
STAR_R = 0.115             # outer radius, fraction of tile
HEART_R = 0.105


def star_points(cx, cy, r_out, r_in, points=5, rot=-math.pi / 2):
    pts = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        a = rot + i * math.pi / points
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def draw_star(d, cx, cy, r):
    d.polygon(star_points(cx, cy, r, r * 0.475), fill=255)


def draw_heart(d, cx, cy, r):
    # Two lobes + a point, built from circles and a triangle — crisp at
    # stamp scale and identical every run.
    lr = r * 0.52
    ly = cy - r * 0.28
    d.ellipse([cx - r * 0.52 - lr, ly - lr, cx - r * 0.52 + lr, ly + lr],
              fill=255)
    d.ellipse([cx + r * 0.52 - lr, ly - lr, cx + r * 0.52 + lr, ly + lr],
              fill=255)
    d.polygon([(cx - r * 1.02, ly + lr * 0.35), (cx + r * 1.02, ly + lr * 0.35),
               (cx, cy + r * 1.05)], fill=255)


def tile(draw_shape, r_frac):
    im = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(im)
    r = r_frac * N
    # centre + wrapped corners = diamond lattice under REPEAT
    for cx, cy in [(N / 2, N / 2), (0, 0), (N, 0), (0, N), (N, N)]:
        draw_shape(d, cx, cy, r)
    return im.convert("RGB")


def main():
    os.makedirs(OUT, exist_ok=True)
    tile(draw_star, STAR_R).save(os.path.join(OUT, "stars_tile.png"))
    tile(draw_heart, HEART_R).save(os.path.join(OUT, "hearts_tile.png"))
    print(f"wrote stars_tile.png, hearts_tile.png -> {os.path.relpath(OUT, HERE)}")


if __name__ == "__main__":
    main()
