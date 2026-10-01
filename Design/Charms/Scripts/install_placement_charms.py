#!/usr/bin/env python3
"""Install art for the AURA / FLOATING charm placements (2026-09-19).

    python3 install_placement_charms.py

ONE `charm_catalog_<id>` imageset per charm, trimmed from the existing
library thumbnail (AurieCharmLibrary/_THUMBNAILS — read, never
written): CharmArt already prefers `charm_catalog_*`, so the same asset
serves the Charms page, the task cards, the reward sheet AND the
wearable render — AurieNode sizes it per placement at runtime. No new
charm ids are invented; every id below exists in the library/catalog.

Idempotent; leaves every other imageset alone.
"""
import json
import pathlib

from PIL import Image

REPO = pathlib.Path(__file__).resolve().parents[3]
LIB = REPO / "AurieCharmLibrary/_THUMBNAILS"
CATALOG = REPO / "Auries/Assets.xcassets/Charms"

CHARMS = [
    # aura cluster charms
    "charm_magic_crystal_02",
    "charm_nature_flower_03",
    "charm_nature_snowflake_01",
    # floating charms
    "charm_object_book_01",
    "charm_object_key_01",
    "charm_magic_star_coin_01",
    "charm_food_tomato_01",
    "charm_magic_star_01",
]

CONTENTS = {"images": [{"filename": None, "idiom": "universal",
                        "scale": "1x"}],
            "info": {"author": "xcode", "version": 1}}


def main():
    for cid in CHARMS:
        im = Image.open(LIB / f"{cid}.png").convert("RGBA")
        im = im.crop(im.getchannel("A").getbbox())
        asset = f"charm_catalog_{cid}"
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
        print(f"{asset}  {im.width}x{im.height}")
    print(f"installed {len(CHARMS)} placement-charm assets")


if __name__ == "__main__":
    main()
