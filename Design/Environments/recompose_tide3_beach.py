#!/usr/bin/env python3
"""Recompose tide3.png (beach painting) into the Tide launch master.

    python3 Design/Environments/recompose_tide3_beach.py

One-shot but REPRODUCIBLE: tide3.png (1086x1448, carries a "Tide" title
label) -> 941x1672 master obeying master_composition_template.png:
sky/distant scenery in the top 20%, the ground-meets-distance
transition band AT 20%, walkable ground 20..84%, framing foreground
below. For the beach (product direction 2026-09-17): DEEP water ends
just ABOVE the far walk line, and the SURF/FOAM zone extends DOWN into
the walkable band — Aurie may walk into the foam at the farthest
positions, never into open ocean. Dry sand fills the rest.

Steps: (1) inpaint the white "Tide" label strokes (thin-stroke TELEA
over the palm fronds), (2) uniform scale to master height, (3) smooth
piecewise VERTICAL remap moving the measured source bands
(sky 0-.12 | sun .12-.21 | deep sea .21-.26 | surf+foam .26-.33 |
wet sand .33-.36 | dry sand) to (0-.09 | .09-.16 | .16-.19 |
.19-.28 | .28-.33 | .33-1): blue water is done by 0.19 (above the
0.20 far line), the surf/foam band is reachable, dry sand from 0.33.
The sun keeps a mild flatten — a setting sun reads naturally squashed.
(4) centre-crop to 941.

The UNDERWATER master is preserved verbatim as Design/Environments/
tide2.png (the shipped imageset was byte-identical to it) for a future
unlockable alternate environment.

Requires: pillow, opencv-python-headless.
"""
import pathlib
import numpy as np
import cv2
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
SRC = HERE / "tide3.png"
OUT = REPO / "Auries/Assets.xcassets/Environments/tide_env_sky.imageset/tide_env_sky.png"

src = np.asarray(Image.open(SRC).convert("RGB"))

# 1. remove the painted-on "Tide" title (top-left, white strokes)
rect = (slice(20, 120), slice(30, 200))
r = src[rect].astype(int)
mask = np.zeros(src.shape[:2], np.uint8)
mask[rect][(r.min(-1) > 165) & (r.max(-1) > 210)
           & (r.max(-1) - r.min(-1) < 55)] = 255
mask = cv2.dilate(mask, np.ones((5, 5), np.uint8))
src = cv2.inpaint(src[:, :, ::-1], mask, 7, cv2.INPAINT_TELEA)[:, :, ::-1]

# 2. uniform scale to master height
H = 1672
im = cv2.resize(src, (round(src.shape[1] * H / src.shape[0]), H),
                interpolation=cv2.INTER_LANCZOS4)
W = im.shape[1]

# 3. piecewise vertical remap (source fractions -> template fractions)
SRC_F = [0.0, 0.12, 0.21, 0.26, 0.33, 0.36, 1.0]
TGT_F = [0.0, 0.090, 0.160, 0.190, 0.280, 0.330, 1.0]
t = np.arange(H, dtype=np.float64) / H
sy = np.interp(t, TGT_F, SRC_F) * H
kern = cv2.getGaussianKernel(61, 18).ravel()          # soften joints
sy = np.convolve(np.pad(sy, 30, mode="edge"), kern, mode="valid")
sy[0], sy[-1] = 0, H - 1
sy = np.maximum.accumulate(sy)
map_y = np.repeat(sy[:, None], W, 1).astype(np.float32)
map_x = np.repeat(np.arange(W, dtype=np.float32)[None, :], H, 0)
out = cv2.remap(im, map_x, map_y, cv2.INTER_LANCZOS4,
                borderMode=cv2.BORDER_REPLICATE)

# 4. centre-crop to master width
x0 = (W - 941) // 2
Image.fromarray(out[:, x0:x0 + 941]).save(OUT)
print(f"wrote {OUT.relative_to(REPO)} 941x{H}")
