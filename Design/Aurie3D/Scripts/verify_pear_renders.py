"""PIL verification for the Pear Aurie candidate renders (no Blender).

Run:  python3 Design/Aurie3D/Scripts/verify_pear_renders.py [aurie3d_root]

Pear-specific sibling of the family verifiers (height-limited: height
fraction 62-70%; normal family world scale, upright). Additionally
measures the BODY-ONLY silhouette to support (not replace) visual
review: H/W, the vertical position of the maximum width (must sit
below the body center — Pear is bottom-heavy by definition), and the
upper-third vs lower-third width relationship. Keep ORTHO/CAM_Z in
sync with any framing change in build_pear_aurie.py.
"""

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else
            Path(__file__).resolve().parent.parent)

FILES = {
    "preview": ROOT / "Previews/preview_pear_full.png",
    "body": ROOT / "Renders/body_pear_candidate.png",
    "tuft": ROOT / "Renders/tuft_00_pear.png",
    "limbs": ROOT / "Renders/limbs_pear_proto_00.png",
    "body_tuft": ROOT / "Renders/body_pear_candidate_with_tuft.png",
}
BLEND = ROOT / "Source/pear_aurie_master.blend"
ORTHO = 3.59242             # Pear v1 framing (from build_pear_aurie)
CAM_Z = 1.15450

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
    hfrac = (bottom - top) / 1024
    check("height fraction 62-70%", 0.62 <= hfrac <= 0.70, f"{hfrac:.3f}")
    world_h = (bottom - top) / 1024 * ORTHO
    world_w = (right - left) / 1024 * ORTHO
    check("world bounds normal family scale, upright",
          2.2 <= world_h <= 2.6 and 1.9 <= world_w <= 2.4 and world_h > world_w,
          f"world h={world_h:.2f} R, w={world_w:.2f} R "
          f"(expected ~2.37 x ~2.24; Round: h~2.23, w~2.01 incl. limbs)")
    cx = (left + right) / 2
    check("horizontally centered", abs(cx - 512) <= 4, f"center x={cx:.1f}")
    check("no clipping at canvas edges",
          left > 2 and top > 2 and right < 1022 and bottom < 1022,
          f"bbox=({left},{top},{right},{bottom})")

# ---- body-only silhouette metrics (supporting visual review) -------------
if "body" in alphas:
    body = alphas["body"].load()
    bb = alphas["body"].getbbox()
    rows = []
    for y in range(bb[1], bb[3]):
        xs = [x for x in range(bb[0], bb[2]) if body[x, y]]
        if xs:
            rows.append((y, xs[-1] - xs[0] + 1))
    if rows:
        body_h = rows[-1][0] - rows[0][0] + 1
        body_w = max(w for _, w in rows)
        max_y = max(rows, key=lambda r: r[1])[0]
        # fraction of body height below the top (0 = top, 1 = bottom)
        frac_down = (max_y - rows[0][0]) / body_h
        world_maxw_z = CAM_Z + (512 - (max_y + 0.5)) * ORTHO / 1024
        third = body_h / 3.0
        upper = max(w for y, w in rows if y - rows[0][0] < third)
        lower = max(w for y, w in rows if y - rows[0][0] >= 2 * third)
        print(f"  [INFO] body H/W {body_h / body_w:.3f} "
              f"({body_h}px x {body_w}px)")
        print(f"  [INFO] max width at {frac_down:.1%} down the body "
              f"(world z {world_maxw_z:.3f})")
        print(f"  [INFO] upper-third max width {upper}px vs lower-third "
              f"{lower}px -> upper/lower {upper / lower:.3f}")
        check("max width below body center (bottom-heavy)",
              frac_down > 0.52, f"{frac_down:.1%} down (Egg ~59%)")

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
    # Sample the belly region (below the face, inside the broad lower body).
    px = imgs["preview"].load()
    rs = gs = bs = n = 0
    for y in range(590, 740, 4):
        for x in range(420, 610, 4):
            r, g, b, a = px[x, y]
            if a > 200:
                rs += r; gs += g; bs += b; n += 1
    if n:
        r, g, b = rs / n, gs / n, bs / n
        check("preview color sanity", b > r and b > 120,
              f"mean rgb=({r:.0f},{g:.0f},{b:.0f})")

print("RESULT:", "ALL CHECKS PASSED" if not failures else f"FAILURES: {failures}")
sys.exit(1 if failures else 0)
