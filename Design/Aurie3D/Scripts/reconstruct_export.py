"""Rebuild a full-frame export directory from the SHIPPED catalog.

    python3 reconstruct_export.py --outdir <dir>

`install_app_assets.py` regenerates the whole catalog from an export dir —
but it also CLEARS the catalog first, so it needs every layer of every body
present. When the original render output is gone (session scratchpads do
not survive), re-rendering ~100 layers per body just to add a few new ones
would cost hours of GPU time for pixel-identical results.

This script inverts the installer's crop math instead: every installed
imageset PNG is pasted back onto the shared 1024 canvas at the exact spot
its `AurieBlenderAssets.swift` Layer entry records, reproducing the
original full-frame render (the installer's own crop of it is identical).
Manifests are rewritten with the ortho recovered from the leg-lift pair
(points-per-unit = legLift_pt / LEG_BODY_LIFT scene units).

Run it, then selectively re-render ONLY new/changed parts into the same
directory with export_app_layers.py's --skip/--styles flags, then install.
"""

import argparse
import json
import pathlib
import re
import sys

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from aurie_limb_styles import LEG_BODY_LIFT  # noqa: E402

APP = HERE.parents[2]
CATALOG = APP / "Auries/Assets.xcassets/AurieBlender"
SWIFT = APP / "Auries/Services/AurieBlenderAssets.swift"

CANVAS_PX = 1024.0
CANVAS_PT = CANVAS_PX * 350.0 / 665.0
Y_SHIFT_PT = -9.0
SCALE = CANVAS_PT / CANVAS_PX

BODIES = ["round", "tall", "small", "egg", "pear", "dumpling", "teardrop",
          "beanbag", "oval", "heart"]

# arm_03 Bud Nubs, arm_04 Soft Mittens and arm_05 Wing Flaps removed
# 2026-09-13; all three ids burned (they lived on test devices).
ARM_STYLES = ["arm_00", "arm_01", "arm_02"]
# 2026-09-13 renumbering: 04 = metaball Paw Steps, 05 = Bulb Boots
LEG_STYLES = ["leg_00", "leg_01", "leg_02", "leg_03", "leg_04", "leg_05"]
# hair_00 = metaball Cloud Puff (2026-09-13); hair_01 reserved (held
# Twin Poms); hair_02..04 retired, never shipped.
HAIR_STYLES = ["hair_00"]

LAYER_RE = re.compile(
    r'"(?P<key>[^"]+)": Layer\(asset: "(?P<asset>[^"]+)", '
    r'size: CGSize\(width: (?P<w>[-\d.]+), height: (?P<h>[-\d.]+)\), '
    r'position: CGPoint\(x: (?P<x>[-\d.]+), y: (?P<y>[-\d.]+)\)\)')
BODY_RE = re.compile(r'"(?P<body>\w+)": Body\(layers: \[')
TAIL_RE = re.compile(
    r'legLift: \[(?P<lift>[^\]]*)\], limbScale: (?P<m>[\d.]+)')


def parse_swift():
    bodies, current = {}, None
    for line in SWIFT.read_text().splitlines():
        mb = BODY_RE.search(line)
        if mb:
            current = mb.group("body")
            bodies[current] = {"layers": {}, "lift": {}, "m": None}
            continue
        if current is None:
            continue
        ml = LAYER_RE.search(line)
        if ml:
            bodies[current]["layers"][ml.group("key")] = dict(
                asset=ml.group("asset"), w=float(ml.group("w")),
                h=float(ml.group("h")), x=float(ml.group("x")),
                y=float(ml.group("y")))
            continue
        mt = TAIL_RE.search(line)
        if mt:
            bodies[current]["m"] = float(mt.group("m"))
            for part in mt.group("lift").split(","):
                k, v = part.split(":")
                bodies[current]["lift"][k.strip().strip('"')] = float(v)
    return bodies


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    args = ap.parse_args()
    out = pathlib.Path(args.outdir).expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)

    data = parse_swift()
    for body in BODIES:
        if body not in data:
            print(f"SKIP {body}: not in Swift table")
            continue
        rec = data[body]
        # points-per-scene-unit from the one style whose scene lift is
        # known. RC3 rollout (2026-09-14): the catalog ships M-SCALED
        # lifts (LEG_BODY_LIFT * m / 0.85 — see export_app_layers), so
        # the inverse divides by the same. `m` is parsed from the same
        # generated Swift table the lift comes from, so the pair always
        # agrees with whatever pipeline produced the catalog.
        lift_pt = rec["lift"].get("leg_00")
        ppu = lift_pt / (LEG_BODY_LIFT["leg_00"] * rec["m"] / 0.85)
        ortho = CANVAS_PT / ppu
        n = 0
        for key, l in rec["layers"].items():
            src = CATALOG / f'{l["asset"]}.imageset' / f'{l["asset"]}.png'
            if not src.exists():
                print(f"MISSING {src}")
                continue
            im = Image.open(src).convert("RGBA")
            w_px = l["w"] / SCALE
            h_px = l["h"] / SCALE
            cx = l["x"] / SCALE + CANVAS_PX / 2
            cy = CANVAS_PX / 2 - (l["y"] - Y_SHIFT_PT) / SCALE
            x0 = int(round(cx - w_px / 2))
            y0 = int(round(cy - h_px / 2))
            canvas = Image.new("RGBA", (int(CANVAS_PX), int(CANVAS_PX)),
                               (0, 0, 0, 0))
            canvas.paste(im, (x0, y0))
            canvas.save(out / f"{body}_{key}.png")
            n += 1
        faces = sorted({k.split("_")[1] for k in rec["layers"]
                        if k.startswith("face_")})
        manifest = {
            "body": body,
            "limb_scale": rec["m"],
            "ortho": ortho,
            "leg_lift": {k: LEG_BODY_LIFT[k] for k in LEG_STYLES},
            "arm_styles": ARM_STYLES,
            "leg_styles": LEG_STYLES,
            "hair_styles": HAIR_STYLES,
            "anim_safe_arms": True,
            # The export run that follows re-renders EVERY leg style with
            # --anim-safe-legs; stale holdout legs must not survive install.
            "anim_safe_legs": True,
            "faces": faces,
            "no_blink": ["delighted"],
            "anchors": {},
            "bodyTop": 1.0,
            "bodyBottom": 0.0,
        }
        (out / f"{body}_manifest.json").write_text(
            json.dumps(manifest, indent=2))
        print(f"{body:10s} reconstructed {n} layers, ortho {ortho:.4f}")


if __name__ == "__main__":
    main()
