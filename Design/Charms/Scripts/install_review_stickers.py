#!/usr/bin/env python3
"""TEMPORARY review imagesets for the 2D Birth-Charm sticker proof.

    python3 install_review_stickers.py            # install
    python3 install_review_stickers.py --remove   # clean up

Writes `belly_sticker_birth_<name>` imagesets so the DEBUG belly-proof
harness (AURIE_BELLY_PROOF=birth_<name> on the batch grid) can dress
REAL Auries in the candidate art through the production sticker path.

REVIEW-ONLY assets, namespaced `birth_*` so they can never collide with
real charm ids; they are removed/replaced when the charms are properly
wired. Masters are read, never written.

Presentation comes from sticker_tuning.TUNING and is baked in by
CANVAS GEOMETRY alone — no pixel is resampled or edited:
  * per-sticker `scale`: the tight art sits on a canvas larger by
    1/scale, so the frozen runtime fit renders it that much smaller;
  * `offsetX`/`offsetY` (belly-core points, +x right / +y up): the art
    is placed off-centre by the pixel equivalent, shifting the VISUAL
    mass to the oval's centre (teacup handle problem). The pt->px
    conversion uses the same real round-body bellyCore the runtime fit
    targets, so an offset point on the review sheet is an offset point
    on the creature.
"""
import json
import pathlib
import sys

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from sticker_tuning import NAMES, TUNING  # noqa: E402

REPO = HERE.parents[2]
MASTERS = REPO / "Design/Charms/Masters"
CATALOG = REPO / "Auries/Assets.xcassets/Charms"

COREW, COREH = 126.0, 86.0    # real round-body bellyCore, points

CONTENTS = {"images": [{"filename": None, "idiom": "universal",
                        "scale": "1x"}],
            "info": {"author": "xcode", "version": 1}}


def main():
    remove = "--remove" in sys.argv
    for name in NAMES:
        asset = f"belly_sticker_{name}"
        d = CATALOG / f"{asset}.imageset"
        if d.exists():
            for f in d.iterdir():
                f.unlink()
            d.rmdir()
        if remove:
            print(f"removed {asset}")
            continue
        scale, off_x, off_y = TUNING[name]
        im = Image.open(MASTERS / f"{name}.png")
        im = im.crop(im.getchannel("A").getbbox())
        side_w = int(round(im.width / scale))
        side_h = int(round(im.height / scale))
        # The runtime fit for THIS canvas, pt per canvas px — converts
        # the tuning's point offsets into bake-time pixel offsets.
        fit = min(0.62 * COREW / side_w, 0.88 * COREH / side_h) * 0.72
        dx = int(round(off_x / fit))
        dy = int(round(off_y / fit))
        canvas = Image.new("RGBA", (side_w, side_h), (0, 0, 0, 0))
        px = (side_w - im.width) // 2 + dx
        py = (side_h - im.height) // 2 - dy      # image +y is DOWN
        # Never let an offset push art off-canvas (clips = lost pixels).
        px = min(max(px, 0), side_w - im.width)
        py = min(max(py, 0), side_h - im.height)
        d.mkdir(parents=True)
        canvas.paste(im, (px, py))
        canvas.save(d / f"{asset}.png", optimize=True)
        c = json.loads(json.dumps(CONTENTS))
        c["images"][0]["filename"] = f"{asset}.png"
        (d / "Contents.json").write_text(json.dumps(c, indent=2))
        print(f"{asset}  art {im.width}x{im.height} on {side_w}x{side_h}"
              f"  scale {scale}  offset pt({off_x},{off_y})"
              f" -> px({dx},{-dy})")


if __name__ == "__main__":
    main()
