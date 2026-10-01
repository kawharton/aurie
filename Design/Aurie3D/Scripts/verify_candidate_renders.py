"""PIL verification for rapid-phase body candidates (no Blender).

Run:  python3 Design/Aurie3D/Scripts/verify_candidate_renders.py \
          <name> [<name> ...]

Imports each body's CFG through the bpy-optional common module and
recomputes framing/anchors from the SAME constants the build used, so
expected bounds and fill fractions can never drift from the scripts.
"""

import importlib
import sys
from pathlib import Path

from PIL import Image

SCRIPTS = Path(__file__).resolve().parent
ROOT = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))
import aurie_body_common as common  # noqa: E402

failures = []


def check(label, ok, detail):
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}: {detail}")
    if not ok:
        failures.append(label)


def verify(name):
    print(f"---- {name} ----")
    mod = importlib.import_module(f"build_{name}_aurie")
    c = common.resolve(mod.CFG)
    fr = common.framing(c)
    files = {
        "preview": ROOT / f"Previews/preview_{name}_full.png",
        "body": ROOT / f"Renders/body_{name}_candidate.png",
        "tuft": ROOT / f"Renders/tuft_00_{name}.png",
        "limbs": ROOT / f"Renders/limbs_{name}_proto_00.png",
        "body_tuft": ROOT / f"Renders/body_{name}_candidate_with_tuft.png",
    }
    blend = ROOT / f"Source/{name}_aurie_master.blend"
    imgs, alphas = {}, {}
    for key, path in files.items():
        ok = path.exists() and path.stat().st_size > 0
        check(f"{key} exists", ok, path.name)
        if not ok:
            continue
        img = Image.open(path)
        check(f"{key} format",
              img.size == (1024, 1024) and img.mode == "RGBA",
              f"{img.size} {img.mode}")
        imgs[key] = img.convert("RGBA")
        alphas[key] = imgs[key].getchannel("A").point(
            lambda a: 255 if a > 8 else 0)
        nz = sum(1 for p in alphas[key].getdata() if p)
        check(f"{key} alpha nonempty", nz > 5000, f"{nz} px")
    check("blend saved", blend.exists() and blend.stat().st_size > 0,
          blend.name)
    if {"body_tuft", "limbs"} <= alphas.keys():
        b1 = alphas["body_tuft"].getbbox()
        b2 = alphas["limbs"].getbbox()
        left, top = min(b1[0], b2[0]), min(b1[1], b2[1])
        right, bottom = max(b1[2], b2[2]), max(b1[3], b2[3])
        wf = (right - left) / 1024
        hf = (bottom - top) / 1024
        if fr["limited"] == "h":
            check("height fraction 62-70%", 0.62 <= hf <= 0.70, f"{hf:.3f}")
        else:
            check("width fraction 74-84%", 0.74 <= wf <= 0.84, f"{wf:.3f}")
        wh = hf * fr["ortho"]
        ww = wf * fr["ortho"]
        eh = fr["z_top"] - fr["z_bot"]
        if c["arm_lr"]:
            import math as _m
            _at = _m.radians(c["arm_tilt"])
            _ah = _m.sqrt((c["arm_scale"][0] * _m.cos(_at)) ** 2
                          + (c["arm_scale"][2] * _m.sin(_at)) ** 2)
            ew = (abs(c["arm_lr"][0][0]) + _ah) + (c["arm_lr"][1][0] + _ah)
        else:
            ew = 2 * fr["half_w"]
        check("world bounds near expected",
              abs(wh - eh) < 0.10 * eh and abs(ww - ew) < 0.10 * ew,
              f"h={wh:.2f} (exp {eh:.2f}), w={ww:.2f} (exp {ew:.2f}) R")
        cx = (left + right) / 2
        tol = 14 if c["x_shift_w"] else 4
        check("horizontally centered", abs(cx - 512) <= tol,
              f"center x={cx:.1f} (tol {tol})")
        check("no clipping", left > 2 and top > 2 and right < 1022
              and bottom < 1022, f"bbox=({left},{top},{right},{bottom})")
    if "preview" in alphas:
        prev = alphas["preview"].load()
        for key in ("body", "tuft", "limbs", "body_tuft"):
            if key not in alphas:
                continue
            part = alphas[key].load()
            out = tot = 0
            for y in range(1024):
                for x in range(1024):
                    if part[x, y]:
                        tot += 1
                        if not prev[x, y]:
                            out += 1
            check(f"{key} registered", out < 0.003 * tot,
                  f"{out}/{tot} px outside")
    if "preview" in imgs:
        py = int(512 + (fr["cam_z"] - c["lift"]) * 1024 / fr["ortho"])
        px = imgs["preview"].load()
        rs = gs = bs = n = 0
        for y in range(max(0, py - 40), min(1024, py + 60), 4):
            for x in range(452, 572, 4):
                r, g, b, al = px[x, y]
                if al > 200:
                    rs += r
                    gs += g
                    bs += b
                    n += 1
        if n:
            check("preview color sanity", bs / n > rs / n and bs / n > 120,
                  f"mean rgb=({rs/n:.0f},{gs/n:.0f},{bs/n:.0f})")


for body in sys.argv[1:]:
    verify(body)
print("RESULT:", "ALL CHECKS PASSED" if not failures
      else f"FAILURES: {failures}")
sys.exit(1 if failures else 0)
