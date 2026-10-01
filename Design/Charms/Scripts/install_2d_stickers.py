#!/usr/bin/env python3
"""Install the PRODUCTION 2D belly-sticker imagesets (frozen 2026-09-19).

    python3 install_2d_stickers.py

The approved borderless 2.5D sticker family: each extracted master
(Design/Charms/Masters — never modified) is installed as the charm's
production `belly_sticker_<charm_id>` imageset. Per-sticker presentation
comes from sticker_tuning.TUNING and is baked by CANVAS GEOMETRY alone
(padding for scale, asymmetric placement for the visual-centering
offsets — mug/teacup centre on the cup BODY, not the handle-inclusive
bounds); the frozen runtime fit then renders the approved look with no
runtime changes and no pixel edits.

This also REPLACES the Blender-derived Apple sticker: same
`charm_food_apple_01` id and asset name, new approved art —
provenance, ownership, saves and the birth trigger are untouched
because only the drawn PNG changes. install_belly_stickers.py now
skips apple so a rerun of the old pipeline cannot resurrect it.

Idempotent: production 2D imagesets are cleared and rebuilt; any
leftover review-only `belly_sticker_birth_*` sets are removed.
"""
import json
import pathlib
import sys

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from sticker_tuning import TUNING  # noqa: E402

REPO = HERE.parents[2]
MASTERS = REPO / "Design/Charms/Masters"
CATALOG = REPO / "Auries/Assets.xcassets/Charms"

COREW, COREH = 126.0, 86.0    # real round-body bellyCore, points

# master name -> production charm id (catalog: charm_taxonomy.json)
CHARM_IDS = {
    "birth_teddy":      "charm_toy_teddy_01",
    "birth_mug":        "charm_object_mug_01",
    "birth_teacup":     "charm_object_teacup_01",
    "birth_beach_ball": "charm_toy_beach_ball_01",
    "birth_balloon":    "charm_toy_balloon_01",
    "birth_apple":      "charm_food_apple_01",
    "birth_strawberry": "charm_food_strawberry_01",
    "birth_orange":     "charm_food_orange_01",
    "birth_lemon":      "charm_food_lemon_01",
    "birth_carrot":     "charm_food_carrot_01",
    "birth_cake":       "charm_food_cake_01",
    "birth_cookie":     "charm_food_cookie_01",
    "basketball":       "charm_toy_basketball_01",
    "rain_cloud":       "charm_nature_rain_cloud_01",
    "flask":            "charm_science_flask_01",
    "trumpet":          "charm_music_trumpet_01",
    "chair":            "charm_object_chair_01",
    "tree":             "charm_nature_tree_02",
    "badge_spark":      "charm_badge_spark_01",
    "badge_wonderbook": "charm_badge_wonderbook_01",
    "badge_refresh":    "charm_badge_refresh_01",
    "badge_team":       "charm_badge_team_01",
    "rainbow_cloud":    "charm_nature_rainbow_cloud_01",
    "friendship_hearts": "charm_friendship_hearts_01",
}

CONTENTS = {"images": [{"filename": None, "idiom": "universal",
                        "scale": "1x"}],
            "info": {"author": "xcode", "version": 1}}

# PRODUCTION TEXTURE DENSITY (sharpness pass 2026-09-20).
#
# SpriteKit minifies belly stickers with plain bilinear filtering and no
# mipmaps, so it samples a 2x2 texel neighbourhood no matter how far the
# texture is being shrunk. The approved sticker family happens to sit at
# ~1.7-2.0x minification and therefore looks crisp; the later art drops
# came off 1254px sheets and landed at ~7x, where fine interior strokes
# (badge icons, shoe laces) collapse into mush. Same pipeline, different
# source resolution — this is the whole cause of the softness.
#
# Fix, per the approved direction: keep the FULL-RES master on disk and
# do ONE high-quality Lanczos downsample here, so the production texture
# arrives at the family's proven density and the runtime performs a
# single gentle downscale. No sharpening, no filtering-mode change.
#
# 320px on the long edge of the visible artwork puts a belly sticker at
# ~2x minification at @3x Home size — the same regime as Apple/Cookie.
PRODUCTION_ART_CAP = 320
# Applied ONLY to the charms in this pass; Rainbow/Hearts/Tree were
# explicitly held out of the sharpness pass and keep their current
# textures (they read fine: large flat shapes, no fine strokes).
CAP_APPLIES_TO = {
    "badge_spark", "badge_wonderbook", "badge_refresh", "badge_team",
}


def clear(d):
    if d.exists():
        for f in d.iterdir():
            f.unlink()
        d.rmdir()


def main():
    for review in CATALOG.glob("belly_sticker_birth_*.imageset"):
        clear(review)
        print(f"removed review set {review.name}")
    for name, charm_id in CHARM_IDS.items():
        scale, off_x, off_y = TUNING[name]
        im = Image.open(MASTERS / f"{name}.png")
        im = im.crop(im.getchannel("A").getbbox())
        # ONE high-quality downsample from the full-res master (see
        # PRODUCTION_ART_CAP above) — never an intermediate raster.
        if name in CAP_APPLIES_TO and max(im.size) > PRODUCTION_ART_CAP:
            k = PRODUCTION_ART_CAP / max(im.size)
            im = im.resize((max(1, round(im.width * k)),
                            max(1, round(im.height * k))), Image.LANCZOS)
        side_w = int(round(im.width / scale))
        side_h = int(round(im.height / scale))
        fit = min(0.62 * COREW / side_w, 0.88 * COREH / side_h) * 0.72
        dx = int(round(off_x / fit))
        dy = int(round(off_y / fit))
        canvas = Image.new("RGBA", (side_w, side_h), (0, 0, 0, 0))
        px = (side_w - im.width) // 2 + dx
        py = (side_h - im.height) // 2 - dy      # image +y is DOWN
        px = min(max(px, 0), side_w - im.width)
        py = min(max(py, 0), side_h - im.height)
        canvas.paste(im, (px, py))
        asset = f"belly_sticker_{charm_id}"
        d = CATALOG / f"{asset}.imageset"
        clear(d)
        d.mkdir(parents=True)
        canvas.save(d / f"{asset}.png", optimize=True)
        c = json.loads(json.dumps(CONTENTS))
        c["images"][0]["filename"] = f"{asset}.png"
        (d / "Contents.json").write_text(json.dumps(c, indent=2))
        print(f"{asset}  art {im.width}x{im.height} on {side_w}x{side_h}"
              f"  scale {scale}  offset pt({off_x},{off_y})")
    print(f"installed {len(CHARM_IDS)} production 2D stickers")


if __name__ == "__main__":
    main()
