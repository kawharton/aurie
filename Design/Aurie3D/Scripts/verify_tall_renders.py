"""PIL verification for the Tall Aurie (Rig B) renders (no Blender needed).

Run:  python3 Design/Aurie3D/Scripts/verify_tall_renders.py [aurie3d_root]

Tall-specific sibling of verify_renders.py (which is frozen with Round).
Checks: files exist; 1024x1024 RGBA; per-pass alpha nonempty; character
height 62-70% of canvas and horizontally centered; no clipping at canvas
edges; every part pass is a subset of the preview silhouette (pixel
registration); preview belly pixels light and blue-dominant.
"""

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else
            Path(__file__).resolve().parent.parent)

FILES = {
    "preview": ROOT / "Previews/preview_tall_full.png",
    "body": ROOT / "Renders/body_01_tall.png",
    "tuft": ROOT / "Renders/tuft_00_tall.png",
    "limbs": ROOT / "Renders/limbs_b_00.png",
    "body_tuft": ROOT / "Renders/body_01_tall_with_tuft.png",
}
BLEND = ROOT / "Source/tall_aurie_master.blend"

failures = []


def check(label, ok, detail):
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}: {detail}")
    if not ok:
        failures.append(label)


imgs, alphas = {}, {}
for name, path in FILES.items():
    ok = path.exists() and path.stat().st_size > 0
    check(f"{name} exists", ok, path.name)
    if not ok:
        continue
    img = Image.open(path)
    check(f"{name} format", img.size == (1024, 1024) and img.mode == "RGBA",
          f"{img.size} {img.mode}")
    imgs[name] = img.convert("RGBA")
    alphas[name] = imgs[name].getchannel("A").point(lambda a: 255 if a > 8 else 0)
    nonzero = sum(1 for p in alphas[name].getdata() if p)
    check(f"{name} alpha nonempty", nonzero > 0.005 * 1024 * 1024,
          f"{nonzero} px")

check("blend saved", BLEND.exists() and BLEND.stat().st_size > 0,
      f"{BLEND.stat().st_size if BLEND.exists() else 0} bytes")

if {"body_tuft", "limbs"} <= alphas.keys():
    bb1 = alphas["body_tuft"].getbbox()
    bb2 = alphas["limbs"].getbbox()
    left = min(bb1[0], bb2[0])
    top = min(bb1[1], bb2[1])
    right = max(bb1[2], bb2[2])
    bottom = max(bb1[3], bb2[3])
    frac = (bottom - top) / 1024
    check("height fraction 62-70%", 0.62 <= frac <= 0.70, f"{frac:.3f}")
    cx = (left + right) / 2
    check("horizontally centered", abs(cx - 512) <= 4, f"center x={cx:.1f}")
    check("no clipping at canvas edges",
          left > 2 and top > 2 and right < 1022 and bottom < 1022,
          f"bbox=({left},{top},{right},{bottom})")

if "preview" in alphas:
    prev = alphas["preview"].load()
    for name in ("body", "tuft", "limbs", "body_tuft"):
        if name not in alphas:
            continue
        part = alphas[name].load()
        outside = total = 0
        for y in range(1024):
            for x in range(1024):
                if part[x, y]:
                    total += 1
                    if not prev[x, y]:
                        outside += 1
        check(f"{name} registered inside preview", outside < 0.003 * total,
              f"{outside}/{total} px outside")

if "preview" in imgs:
    # Sample the belly region (below the face block, inside the body).
    px = imgs["preview"].load()
    rs = gs = bs = n = 0
    for y in range(560, 800, 4):
        for x in range(400, 624, 4):
            r, g, b, a = px[x, y]
            if a > 200:
                rs += r; gs += g; bs += b; n += 1
    if n:
        r, g, b = rs / n, gs / n, bs / n
        check("preview color sanity", b > r and b > 120,
              f"mean rgb=({r:.0f},{g:.0f},{b:.0f})")

print("RESULT:", "ALL CHECKS PASSED" if not failures else f"FAILURES: {failures}")
sys.exit(1 if failures else 0)
