#!/usr/bin/env python3
"""Extract the individual 2D Birth-Charm masters from the transparent
source sheets (Design/Charms/SourceSheets — NEVER modified).

    python3 extract_birth_masters.py

Pixel-faithful by construction: each object is CROPPED out of the sheet
through its alpha bounds — nothing is redrawn, recolored, resampled or
filtered. Every master keeps the source resolution, gains a consistent
transparent MARGIN, and sits on a SQUARE canvas centered on the alpha-
weighted (visual) centroid — so a balloon string or mug handle doesn't
drag the object off-center — clamped so no pixel ever leaves the canvas.

Segmentation is alpha connected-components (pure numpy union-find; no
scipy in this environment). Tiny satellites (outline speckles, detached
texture dots) are unioned into the nearest big component when close, so
their pixels are preserved; only sub-`DEBRIS` isolated specks — PNG
export dust, not art — are dropped, and every drop is logged.

Naming is deterministic: components are ordered by grid position
(row band, then x) and mapped to the fixed name lists below, which
mirror the sheets' visual layout.
"""
import pathlib
import sys

import numpy as np
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
SHEETS = HERE.parent / "SourceSheets"
OUT = HERE.parent / "Masters"

ALPHA_MIN = 8        # alpha > this counts as object
BIG_AREA = 20_000    # px: a real object on these ~1250px sheets
NEAR = 80            # px: satellite-to-object adoption distance
DEBRIS = 400         # px: isolated blobs smaller than this are dust
MARGIN = 28          # transparent margin on every side of the master

# FINAL sheet (fourth drop, 2026-09-19 14:39 — the art source): ONE
# combined sheet, 12 objects, TRUE RGBA transparency, NO die-cut
# borders (approved direction: the artwork's own coloured outline is
# the edge). Three loose reading-order rows: 3 / 3 / 6. Extraction is
# pure alpha-bounds; names map in reading order.
SHEET_NAMES = {
    "birth_charms_stickers.png": [
        "birth_teddy", "birth_mug", "birth_teacup",
        "birth_beach_ball", "birth_balloon", "birth_apple",
        "birth_strawberry", "birth_orange", "birth_lemon",
        "birth_carrot", "birth_cake", "birth_cookie",
    ],
}

# Ground classification for alpha-less sheets: light-to-mid greys and
# whites (background, die-cut border AND its soft shadow — the shadow
# must count as ground or it fences the border off from the edge fill
# and partial white rings survive around the artwork).
BG_VAL_MIN = 175      # brightness floor for candidate ground
BG_SAT_MAX = 46       # saturation ceiling (0-255 scale)
EDGE_FEATHER = 1.2    # px of mask feathering (masking only — the
                      # artwork pixels themselves are never altered)


def components(mask):
    """Union-find connected components (4-neighbour) on a bool mask."""
    h, w = mask.shape
    label = np.zeros((h, w), dtype=np.int32)
    parent = [0]

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb)] = min(ra, rb)

    nxt = 1
    for y in range(h):
        row = mask[y]
        for x in range(w):
            if not row[x]:
                continue
            up = label[y - 1, x] if y else 0
            left = label[y, x - 1] if x else 0
            if up and left:
                label[y, x] = min(up, left)
                union(up, left)
            elif up or left:
                label[y, x] = up or left
            else:
                parent.append(nxt)
                label[y, x] = nxt
                nxt += 1
    # resolve
    flat = np.array([find(i) for i in range(nxt)], dtype=np.int32)
    return flat[label]


def bbox_of(ys, xs):
    return xs.min(), ys.min(), xs.max(), ys.max()


def bbox_gap(a, b):
    """Smallest axis gap between two bboxes (0 if overlapping)."""
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    dx = max(bx0 - ax1, ax0 - bx1, 0)
    dy = max(by0 - ay1, ay0 - by1, 0)
    return max(dx, dy)


def derive_alpha(arr):
    """Alpha for an RGB sheet: ground = light, unsaturated pixels
    CONNECTED to the sheet edge (background + die-cut border + soft
    shadows). Enclosed light regions (mug body, frosting) stay opaque.
    The returned alpha is a lightly feathered mask — artwork pixel
    values are untouched."""
    rgb = arr[..., :3].astype(np.int16)
    val = rgb.max(axis=2)
    sat = val - rgb.min(axis=2)
    candidate = (val >= BG_VAL_MIN) & (sat <= BG_SAT_MAX)
    lab = components(candidate)
    edge_ids = np.unique(np.concatenate(
        [lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    ground = np.isin(lab, edge_ids[edge_ids > 0])
    mask = (~ground).astype(np.float64)
    if EDGE_FEATHER > 0:                        # tiny box feather
        r = max(1, int(round(EDGE_FEATHER)))
        pad = np.pad(mask, r, mode="edge")
        acc = np.zeros_like(mask)
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                acc += pad[r + dy:r + dy + mask.shape[0],
                           r + dx:r + dx + mask.shape[1]]
        mask = acc / ((2 * r + 1) ** 2)
    return (mask * 255).round().astype(np.uint8)


def extract_grid(sheet_path, names):
    """Deterministic 1xN grid slicing for the final sheets: the soft
    halos of neighbouring stickers touch, so connectivity can merge
    objects — equal cells cannot. Within a cell the bbox is computed at
    a modest alpha threshold (ignores a neighbour's faint spill), and
    every pixel inside that bbox ships untouched."""
    arr = np.asarray(Image.open(sheet_path))
    assert arr.shape[2] == 4, f"{sheet_path.name}: expected RGBA"
    h, w = arr.shape[:2]
    cw = w / len(names)
    for i, name in enumerate(names):
        cell = arr[:, int(round(i * cw)):int(round((i + 1) * cw))].copy()
        a = cell[..., 3]
        ys, xs = np.nonzero(a > 24)
        assert len(ys), f"{sheet_path.name}: empty cell for {name}"
        x0, x1 = xs.min(), xs.max()
        y0, y1 = ys.min(), ys.max()
        crop = cell[y0:y1 + 1, x0:x1 + 1]
        ch, cwid = crop.shape[:2]
        side = max(cwid, ch) + 2 * MARGIN
        canvas = np.zeros((side, side, 4), dtype=np.uint8)
        af = crop[..., 3].astype(np.float64)
        cy = (af.sum(axis=1) @ np.arange(ch)) / af.sum()
        cx = (af.sum(axis=0) @ np.arange(cwid)) / af.sum()
        px = int(round(side / 2 - cx))
        py = int(round(side / 2 - cy))
        px = min(max(px, MARGIN // 2), side - cwid - MARGIN // 2)
        py = min(max(py, MARGIN // 2), side - ch - MARGIN // 2)
        canvas[py:py + ch, px:px + cwid] = crop
        out = OUT / f"{name}.png"
        Image.fromarray(canvas).save(out, optimize=True)
        print(f"  {name:20s} obj {cwid}x{ch}px -> {side}x{side} canvas")


def extract(sheet_path, names):
    im = Image.open(sheet_path)
    if im.mode != "RGBA":
        rgb = np.asarray(im.convert("RGB"))
        arr = np.dstack([rgb, derive_alpha(rgb)])
    else:
        arr = np.asarray(im)
    # AUTO-THRESHOLD (final sheets): neighbouring stickers' soft halos
    # touch at low alpha, merging objects. Sweep upward until the
    # expected object count appears; pixels fainter than the working
    # threshold at the far periphery are sub-visible and are the only
    # thing sacrificed.
    lab = big = small = None
    for t in (ALPHA_MIN, 16, 24, 32, 48, 64, 96, 128):
        lab = components(arr[..., 3] > t)
        ids, counts = np.unique(lab[lab > 0], return_counts=True)
        big, small = [], []
        for cid, n in zip(ids, counts):
            ys, xs = np.nonzero(lab == cid)
            entry = {"id": cid, "area": int(n), "bbox": bbox_of(ys, xs)}
            (big if n >= BIG_AREA else small).append(entry)
        if len(big) == len(names):
            print(f"  segmentation threshold alpha>{t}")
            break
    assert len(big) == len(names), (
        f"{sheet_path.name}: found {len(big)} objects, expected "
        f"{len(names)} at every threshold — adjust BIG_AREA")

    # Adopt satellites into the nearest big component; drop true dust.
    merged = {b["id"]: [b["id"]] for b in big}
    for s in small:
        gaps = [(bbox_gap(s["bbox"], b["bbox"]), b["id"]) for b in big]
        gap, owner = min(gaps)
        if gap <= NEAR:
            merged[owner].append(s["id"])
        elif s["area"] >= DEBRIS:
            # sizable but far from everything: keep with nearest anyway
            # rather than lose art pixels, and say so.
            merged[owner].append(s["id"])
            print(f"  NOTE {sheet_path.name}: {s['area']}px blob "
                  f"{s['bbox']} far from all objects (gap {gap:.0f}) — "
                  f"kept with nearest")
        else:
            print(f"  drop dust {s['area']}px at {s['bbox']} "
                  f"(gap {gap:.0f})")

    # Order objects by grid position: row bands by centroid y, then x.
    objs = []
    for b in big:
        sel = np.isin(lab, merged[b["id"]])
        ys, xs = np.nonzero(sel)
        a = arr[..., 3].astype(np.float64) * sel
        cy = (a.sum(axis=1) @ np.arange(arr.shape[0])) / a.sum()
        cx = (a.sum(axis=0) @ np.arange(arr.shape[1])) / a.sum()
        objs.append({"sel": sel, "bbox": bbox_of(ys, xs),
                     "cx": cx, "cy": cy})
    # Reading order for ANY row layout: cluster centroids into rows
    # wherever the y-gap between successive (sorted) centroids exceeds
    # a fraction of the sheet height, then left-to-right within a row.
    objs.sort(key=lambda o: o["cy"])
    row_gap = arr.shape[0] * 0.12
    row = 0
    objs[0]["row"] = 0
    for prev, cur in zip(objs, objs[1:]):
        if cur["cy"] - prev["cy"] > row_gap:
            row += 1
        cur["row"] = row
    objs.sort(key=lambda o: (o["row"], o["cx"]))

    for name, o in zip(names, objs):
        x0, y0, x1, y1 = o["bbox"]
        crop = arr[y0:y1 + 1, x0:x1 + 1].copy()
        keep = o["sel"][y0:y1 + 1, x0:x1 + 1]
        crop[~keep] = 0            # other objects' pixels never bleed in
        h, w = crop.shape[:2]
        side = max(w, h) + 2 * MARGIN
        canvas = np.zeros((side, side, 4), dtype=np.uint8)
        # Visual centering: alpha centroid to canvas centre, clamped so
        # the full bbox keeps at least half the margin on every side.
        px = int(round(side / 2 - (o["cx"] - x0)))
        py = int(round(side / 2 - (o["cy"] - y0)))
        px = min(max(px, MARGIN // 2), side - w - MARGIN // 2)
        py = min(max(py, MARGIN // 2), side - h - MARGIN // 2)
        canvas[py:py + h, px:px + w] = crop
        out = OUT / f"{name}.png"
        Image.fromarray(canvas).save(out, optimize=True)
        print(f"  {name:20s} obj {w}x{h}px -> {side}x{side} canvas")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for sheet, names in SHEET_NAMES.items():
        print(sheet)
        extract(SHEETS / sheet, names)
    print(f"masters -> {OUT}")


if __name__ == "__main__":
    main()
