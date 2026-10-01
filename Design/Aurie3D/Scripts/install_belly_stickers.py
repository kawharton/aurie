#!/usr/bin/env python3
"""Install the charm browse/catalog art shipped with the Charms page.

TWO kinds of asset come out of here:
  * belly stickers  (belly_sticker_<id>)  — the approved graded decals
  * CATALOG-ONLY previews (charm_catalog_<id>) — browse/detail pictures
    for charms whose WEARABLE layers are wrong for a catalog card. The
    backpack's wearable render includes the generated strap harness;
    its catalog picture is the library's clean pack-only preview.
    These are PRESENTATION assets only: nothing about the wearable
    geometry, straps, or equip render path reads them.

Original brief:
Install the approved belly-sticker assets — ONE processed PNG per charm.

    python3 install_belly_stickers.py

For every charm in the approved catalog (aurie_belly_stickers.STICKERS)
this takes the library's one-camera transparent preview
(`AurieCharmLibrary/_THUMBNAILS/<id>.png`), trims the empty frame, bakes
the approved EXTRA SOFT PASTEL grade WITH that charm's CHARM_TRIM
override (frozen 2026-09-17 — the grade is baked offline so the runtime
draws the sticker untinted, like every other charm), and installs it as

    Auries/Assets.xcassets/Charms/belly_sticker_<charm_id>.imageset

Body-agnostic on purpose: there is NO per-body sticker copy. The runtime
scales the one asset to each body's generated bellyCore with the frozen
two-axis fit (0.62 w / 0.88 h) x STICKER_SIZE 0.72 — constants that live
in aurie_belly_stickers.py and are mirrored by name in AurieNode.

Idempotent: the Charms catalog's belly_sticker_* sets are cleared and
rebuilt, so a charm removed from the approved catalog cannot linger.
"""
import json
import pathlib
import sys

import numpy as np
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import aurie_belly_stickers as ABS

REPO = HERE.parents[2]
LIB = REPO / "AurieCharmLibrary/_THUMBNAILS"
CATALOG = REPO / "Auries/Assets.xcassets/Charms"

CONTENTS = {"images": [{"filename": None, "idiom": "universal",
                        "scale": "1x"}],
            "info": {"author": "xcode", "version": 1}}


def main():
    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    # Clear ONLY this pipeline's own sets (2026-09-19: the old
    # belly_sticker_* wildcard also destroyed the 2D sticker family's
    # production imagesets, which install_2d_stickers.py owns).
    for charm_id, _ in ABS.STICKERS:
        old = CATALOG / f"belly_sticker_{charm_id}.imageset"
        if charm_id == "charm_food_apple_01" or not old.exists():
            continue
        for f in old.iterdir():
            f.unlink()
        old.rmdir()

    for charm_id, name in ABS.STICKERS:
        # Apple migrated to the approved 2D sticker family (2026-09-19):
        # its production imageset is owned by install_2d_stickers.py —
        # skipped here so a rerun of this legacy pipeline can never
        # resurrect the Blender apple.
        if charm_id == "charm_food_apple_01":
            print(f"{name:13s} SKIPPED — owned by install_2d_stickers.py")
            continue
        src = LIB / f"{charm_id}.png"
        im = Image.open(src).convert("RGBA")
        im = im.crop(im.getchannel("A").getbbox())
        arr = np.asarray(im).astype(np.float64) / 255.0
        rgb, a = arr[..., :3], arr[..., 3]
        rgb = ABS.treat(rgb, a, **ABS.style_for(charm_id))
        out = Image.fromarray(
            (np.concatenate([rgb, a[..., None]], axis=-1) * 255)
            .round().astype(np.uint8))
        asset = f"belly_sticker_{charm_id}"
        d = CATALOG / f"{asset}.imageset"
        d.mkdir(parents=True)
        out.save(d / f"{asset}.png", optimize=True)
        c = json.loads(json.dumps(CONTENTS))
        c["images"][0]["filename"] = f"{asset}.png"
        (d / "Contents.json").write_text(json.dumps(c, indent=2))
        print(f"{name:13s} {asset}  {out.width}x{out.height}  "
              f"{(d / (asset + '.png')).stat().st_size / 1024:.0f} KB")
    print(f"installed {len(ABS.STICKERS)} belly stickers")

    # CATALOG-ONLY previews: charm id -> why the wearable art is not used.
    CATALOG_ONLY = {
        "charm_object_backpack_01":
            "wearable render carries the generated strap harness; the "
            "catalog shows the clean pack-only library preview",
    }
    for charm_id, why in CATALOG_ONLY.items():
        src = LIB / f"{charm_id}.png"
        im = Image.open(src).convert("RGBA")
        im = im.crop(im.getchannel("A").getbbox())
        asset = f"charm_catalog_{charm_id}"
        d = CATALOG / f"{asset}.imageset"
        if d.exists():
            for f in d.iterdir():
                f.unlink()
            d.rmdir()
        d.mkdir(parents=True)
        im.save(d / f"{asset}.png", optimize=True)
        c = json.loads(json.dumps(CONTENTS))
        c["images"][0]["filename"] = f"{asset}.png"
        (d / "Contents.json").write_text(json.dumps(c, indent=2))
        print(f"catalog-only {asset}  {im.width}x{im.height}  ({why})")


if __name__ == "__main__":
    main()
