"""Aurie charm library — structure, provenance and the central manifest.

    python3 charm_library.py init      # build the tree, record provenance
    python3 charm_library.py report    # what is in the library right now
    python3 charm_library.py verify    # every processed charm's files are sane

This is the LIBRARIAN half of the charm pipeline; it never opens Blender and
never touches a source .blend. `charm_processor.py` is the other half and is
the only thing that writes into _PROCESSED/ and _THUMBNAILS/.

WHERE THE ORIGINALS LIVE
    The 53 MB of Quaternius .blend files stay exactly where they were
    downloaded, in Design/Aurie3D/Charms/. Copying them into the library
    would double the repo for no benefit, so _SOURCE_ORIGINALS/ holds a
    POINTER plus a SHA-256 for every file instead. The checksums are the
    point: they turn "we did not modify the originals" from a promise into
    something re-checkable at any time (`report` re-hashes and diffs).

WHAT EACH FOLDER IS FOR
    _SOURCE_ORIGINALS/  pointer + checksums for the untouched downloads
    _SOURCE_LICENSES/   the original licence/readme files, kept forever
    _MANIFESTS/         charms.json — the one machine-readable index
    _PROCESSED/         <charm_id>.blend, the processed Aurie masters
    _THUMBNAILS/        <charm_id>.png, transparent previews
    <category>/         <charm_id>.json — the per-charm processing record
                        (inspection, decisions, attachment anchor). Browsing
                        by category is how a human looks for a charm, so the
                        category folders hold the readable record and the
                        flat folders hold the machine-addressed outputs. No
                        file is stored twice.
"""

import csv
import hashlib
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]                      # .../Auries
SOURCE_DIR = REPO / "Design/Aurie3D/Charms"
LIBRARY = REPO / "AurieCharmLibrary"
INVENTORY = HERE / "charm_inventory.csv"

PROCESSOR_VERSION = "v1"

CATEGORIES = ["animals", "food", "nature", "magic", "objects", "adventure",
              "vehicles", "characters"]
UNDERSCORE_DIRS = ["_SOURCE_ORIGINALS", "_SOURCE_LICENSES", "_MANIFESTS",
                   "_PROCESSED", "_THUMBNAILS"]

# Provenance. Everything here is READ OFF the licence file shipped with the
# download — none of it is inferred. Anything not stated there is UNKNOWN
# rather than a plausible guess.
CREATOR = "Quaternius"
CREATOR_URL = "https://www.patreon.com/quaternius"
LICENSE = "CC0"
LICENSE_URL = "https://creativecommons.org/publicdomain/zero/1.0/"

# Charms are processed in reviewed batches, and the batches are recorded so
# the library can always say WHEN something was made and against which
# review.
#
# CUT records what was processed, reviewed and rejected. It exists so the
# library REMEMBERS: without it a later full-library run would quietly
# re-process every rejected charm and put it back on a contact sheet. Cut
# charms keep their inventory row and their source; only their output was
# deleted.
CUT = {
    "charm_magic_crystal_01": "review 1: reads poorly at charm scale",
    "charm_magic_crown_01": "cut twice: as a standalone charm in review 1, and again as a HEAD accessory at 34% of body width in the accessory QA. Do not reinstate a third time.",
    "charm_nature_flower_01": "review 1: unusable — its atlas is an external file absent from the download; the supplied Flowers.png is a different layout (its UVs sample the wrong regions). Flowers 2 and 3 carry their atlas packed and are fine.",
    "charm_animal_dolphin_01": "review 2: a grey sliver at 80 pt, not readable",
    "charm_animal_koi_01": "review 2: wide-headed model, no angle reads cleanly",
    "charm_adventure_tent_01": "review 2: dark and hairline-thin at charm scale",
    "charm_food_donut_02": "review 2: source has one material, no glaze or sprinkles",
    "charm_character_cop_01": "review 3: cut (also mislabelled — Cop.blend is a police car, not a character)",
    "charm_vehicle_taxi_01": "review 3: cut",
    "charm_vehicle_car_01": "review 3: cut (the light blue car; Car (Alt) kept)",
    "charm_magic_sword_01": "review 3: cut",
    "charm_animal_zebra_clownfish_01": "review 3: cut",
    "charm_food_icecream_03": "review 3: cut",
    "charm_food_cupcake_01": "review 3: cut, looked weird",
    "charm_adventure_boat_01": "review 3: cut",
    "charm_food_waffle_01": "review 3: cut",
    "charm_adventure_lifeboat_01": "review 3: cut",
    "charm_nature_rock_01": "review 4: cut (Boulder kept)",
    "charm_nature_rock_02": "review 4: cut (Boulder kept)",
    "charm_object_book_02": "review 4: cut (Open Book kept)",
}

BATCHES = {
    "batch1": [
        "charm_animal_fox_01", "charm_animal_husky_01",
        "charm_animal_clownfish_01",
        "charm_food_banana_01",
        "charm_food_pizza_01", "charm_food_icecream_01",
        "charm_magic_star_01", "charm_object_backpack_01",
        "charm_object_key_01", "charm_magic_chest_01",
    ],
    # Batch 2: the next 20 Launch charms. Chosen to finish the launch set
    # AND to exercise every profile batch 1 never touched — filigree has a
    # snowflake, panel has a coin and a book, botanical has a cactus. Left
    # out on purpose: Flower 2/3 (same missing atlas as the cut Flower, so
    # they can only come out grey), Crystal 5 (same subject as a cut charm),
    # Ice Cream 2 (near-duplicate of one already approved).
    "batch2": [
        "charm_food_apple_01", "charm_food_broccoli_01",
        "charm_food_tomato_01", "charm_food_soda_01",
        "charm_food_donut_01",
        "charm_animal_cow_01", "charm_animal_deer_01",
        "charm_animal_horse_01",
        "charm_object_book_01", "charm_object_key_02",
        "charm_object_padlock_01", "charm_object_first_aid_kit_01",
        "charm_nature_snowflake_01", "charm_nature_pumpkin_01",
        "charm_nature_cactus_flower_01",
        "charm_magic_star_coin_01",
    ],
    # Batch 3: every remaining charm, so the whole library is prepared and
    # can be judged in one pass. Includes the four Launch charms held back
    # from batch 2 — among them Flower 2 and 3, which will come out in
    # placeholder grey because their atlas is missing from the download.
    "batch3": [
        "charm_animal_anglerfish_01",
        "charm_food_bacon_01",
        "charm_magic_chest_ingots_01",
        "charm_magic_chest_open_01",
        "charm_food_chicken_leg_01",
        "charm_nature_tree_01",
        "charm_magic_crystal_02",
        "charm_food_eggplant_01",
        "charm_animal_fish_01",
        "charm_animal_fish_02",
        "charm_animal_fish_03",
        "charm_nature_flower_02",
        "charm_nature_flower_03",
        "charm_object_fork_01",
        "charm_food_icecream_02",
        "charm_object_key_03",
        "charm_vehicle_car_02",
        "charm_nature_pine_tree_01",
        "charm_adventure_sail_ship_01",
        "charm_animal_shark_01",
        "charm_nature_snowflake_02",
        "charm_nature_snowflake_03",
        "charm_object_spoon_01",
        "charm_vehicle_sports_car_01",
        "charm_vehicle_sports_car_02",
        "charm_food_steak_01",
        "charm_adventure_viking_boat_01",
        "charm_animal_wolf_01",
        "charm_nature_wood_log_01",
    ],
    # Batch 4: charms added on 2026-08-19 alongside the texture pack that
    # finally resolves the flower atlas.
    "batch4": [
        "charm_nature_plant_flowers_01", "charm_nature_petals_01",
        "charm_nature_rock_03",
        "charm_nature_maple_tree_01", "charm_nature_tree_02",
    ],
}
PILOT = BATCHES["batch1"]

# A cut charm must never sit in a batch — that is how a rejected render
# comes back.
for _name, _ids in BATCHES.items():
    _clash = sorted(set(_ids) & set(CUT))
    assert not _clash, f"{_name} still contains cut charms: {_clash}"


def batch_of(charm_id):
    for name, ids in BATCHES.items():
        if charm_id in ids:
            return name
    return None


def sha256(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(chunk), b""):
            h.update(block)
    return h.hexdigest()


def display_name(source_filename):
    """A human label from the source filename, e.g. IceCream_1 -> Ice Cream.

    Only the mechanical part is automated; anything ambiguous is corrected
    in DISPLAY_OVERRIDES so the manifest never ships a mangled name.
    """
    stem = pathlib.Path(source_filename).stem
    out = []
    for w in stem.replace("_", " ").replace("-", " ").split():
        w = w.rstrip("0123456789")           # Crystal4 -> Crystal, Key1 -> Key
        if not w:
            continue
        # CamelCase -> Camel Case
        parts, cur = [], ""
        for ch in w:
            if ch.isupper() and cur and not cur[-1].isupper():
                parts.append(cur)
                cur = ch
            else:
                cur += ch
        parts.append(cur)
        out += [p for p in parts if p]
    return " ".join(out).strip()


DISPLAY_OVERRIDES = {
    "charm_food_apple_01": "Green Apple",
    "charm_food_bacon_01": "Bacon",
    "charm_food_chicken_leg_01": "Chicken Leg",
    "charm_food_icecream_01": "Ice Cream",
    "charm_food_icecream_02": "Ice Cream Cone",
    "charm_food_icecream_03": "Ice Cream Sundae",
    "charm_food_pizza_01": "Pizza Slice",
    "charm_object_first_aid_kit_01": "First Aid Kit",
    "charm_object_book_01": "Open Book",
    "charm_object_book_02": "Open Book (Alt)",
    "charm_magic_chest_01": "Treasure Chest",
    "charm_magic_chest_open_01": "Open Treasure Chest",
    "charm_magic_chest_ingots_01": "Chest of Ingots",
    "charm_magic_star_coin_01": "Star Coin",
    "charm_magic_sword_01": "Sword",
    "charm_nature_cactus_flower_01": "Flowering Cactus",
    "charm_nature_tree_01": "Tree",
    "charm_nature_pine_tree_01": "Pine Tree",
    "charm_nature_wood_log_01": "Wood Log",
    "charm_animal_horse_01": "White Horse",
    "charm_animal_zebra_clownfish_01": "Zebra Clownfish",
    "charm_vehicle_car_01": "Car",
    "charm_vehicle_car_02": "Car (Alt)",
    "charm_vehicle_sports_car_01": "Sports Car",
    "charm_vehicle_sports_car_02": "Sports Car (Alt)",
    "charm_adventure_sail_ship_01": "Sail Ship",
    "charm_adventure_viking_boat_01": "Viking Boat",
    "charm_character_cop_01": "Police Officer",
    "charm_nature_maple_tree_01": "Maple Tree",
    "charm_nature_tree_02": "Tree (Alt)",
    "charm_nature_petals_01": "Petals",
    "charm_nature_plant_flowers_01": "Flowering Plant",
    "charm_nature_rock_01": "Rock",
    "charm_nature_rock_02": "Rock (Alt)",
    "charm_nature_rock_03": "Boulder",
}


def read_inventory():
    with open(INVENTORY, newline="") as fh:
        return list(csv.DictReader(fh))


def build_records():
    records, missing = [], []
    for row in read_inventory():
        cid = row["ProcessedID"]
        src = SOURCE_DIR / row["SourceFile"]
        present = src.exists()
        if not present:
            missing.append(row["SourceFile"])
        rec = {
            "id": cid,
            "displayName": DISPLAY_OVERRIDES.get(cid,
                                                 display_name(row["SourceFile"])),
            "category": row["Category"].lower(),
            "sourceFilename": row["SourceFile"],
            "sourceCreator": CREATOR,
            "sourcePack": "UNKNOWN",
            "sourceURL": "",
            "sourceCreatorURL": CREATOR_URL,
            "license": LICENSE,
            "licenseVerified": True,
            "licenseFile": "_SOURCE_LICENSES/Quaternius_LowPoly_License.txt",
            "sourcePresent": present,
            "sourceSHA256": sha256(src) if present else "",
            "sourceBytes": src.stat().st_size if present else 0,
            "processed": False,
            "launchStatus": row["LaunchStatus"].lower(),
            "processedFilename": "",
            "thumbnailFilename": "",
            "processorVersion": "",
            "batch": batch_of(cid),
            "cut": CUT.get(cid, ""),
            "notes": row["Notes"],
        }
        records.append(rec)
    return records, missing


def merge(old_records, new_records):
    """Keep everything the processor wrote; refresh only librarian fields."""
    by_id = {r["id"]: r for r in old_records}
    out = []
    for rec in new_records:
        prev = by_id.get(rec["id"])
        on_disk = bool(prev) and prev.get("processedFilename") and \
            (LIBRARY / prev["processedFilename"]).exists()
        if prev and on_disk:
            for k in ("processed", "processedFilename", "thumbnailFilename",
                      "processorVersion", "processing", "attachment",
                      "inspection"):
                if k in prev:
                    rec[k] = prev[k]
        out.append(rec)
    return out


def manifest_path():
    return LIBRARY / "_MANIFESTS/charms.json"


def load_manifest():
    p = manifest_path()
    if not p.exists():
        return {"charms": []}
    return json.loads(p.read_text())


def save_manifest(data):
    manifest_path().write_text(json.dumps(data, indent=2) + "\n")


def cmd_init():
    for d in UNDERSCORE_DIRS + CATEGORIES:
        (LIBRARY / d).mkdir(parents=True, exist_ok=True)

    # Licence files are copied, never moved: the download keeps its own copy.
    src_lic = SOURCE_DIR / "License.txt"
    dst_lic = LIBRARY / "_SOURCE_LICENSES/Quaternius_LowPoly_License.txt"
    if src_lic.exists():
        dst_lic.write_bytes(src_lic.read_bytes())

    records, missing = build_records()
    old = load_manifest()
    records = merge(old.get("charms", []), records)

    data = {
        "schema": "aurie.charm.manifest/1",
        "processorVersion": PROCESSOR_VERSION,
        "sourceRoot": str(SOURCE_DIR.relative_to(REPO)),
        "sourceCreator": CREATOR,
        "sourceCreatorURL": CREATOR_URL,
        "license": LICENSE,
        "licenseURL": LICENSE_URL,
        "licenseVerified": True,
        "batches": BATCHES,
        "cut": CUT,
        "counts": {
            "total": len(records),
            "present": sum(1 for r in records if r["sourcePresent"]),
            "missing": len(missing),
            "launch": sum(1 for r in records if r["launchStatus"] == "launch"),
            "future": sum(1 for r in records if r["launchStatus"] == "future"),
            "review": sum(1 for r in records if r["launchStatus"] == "review"),
            "processed": sum(1 for r in records if r["processed"]),
        },
        "missingSources": missing,
        "charms": records,
    }
    save_manifest(data)

    # The checksum file is what makes "originals untouched" verifiable.
    lines = ["# SHA-256 of every charm source, recorded at import.",
             "# Sources are READ-ONLY: re-run `charm_library.py report` to",
             "# prove none of them changed.", ""]
    for r in records:
        if r["sourcePresent"]:
            lines.append(f'{r["sourceSHA256"]}  {r["sourceFilename"]}')
    (LIBRARY / "_SOURCE_ORIGINALS/CHECKSUMS.sha256").write_text(
        "\n".join(lines) + "\n")
    (LIBRARY / "_SOURCE_ORIGINALS/README.md").write_text(f"""\
# Source originals

The canonical, untouched charm sources are NOT copied here. They live at:

    {SOURCE_DIR.relative_to(REPO)}/

{len(records) - len(missing)} `.blend` files, {sum(r["sourceBytes"] for r in records) / 1048576:.0f} MB, by {CREATOR}, licensed {LICENSE}.
Duplicating them into the library would double that for nothing, so this
folder holds `CHECKSUMS.sha256` instead — one SHA-256 per source file,
recorded at import.

Nothing in the pipeline writes to that folder. `charm_processor.py` opens
each `.blend` read-only and always saves elsewhere, so a checksum mismatch
means something outside this pipeline touched a source.

Verify at any time:

    python3 Design/Aurie3D/Scripts/charm_library.py report

Missing at import time: {", ".join(missing) if missing else "none"}
""")

    print(f"library    {LIBRARY.relative_to(REPO)}")
    print(f"folders    {len(UNDERSCORE_DIRS)} system + {len(CATEGORIES)} category")
    print(f"licence    {dst_lic.relative_to(LIBRARY)}"
          if src_lic.exists() else "licence    MISSING")
    print(f"manifest   {len(records)} charms "
          f"({data['counts']['launch']} launch / {data['counts']['future']} future"
          f" / {data['counts']['review']} review)")
    print(f"checksums  {data['counts']['present']} files hashed")
    if missing:
        print(f"MISSING    {len(missing)} listed in the inventory but not on "
              f"disk: {', '.join(missing)}")


def cmd_report():
    data = load_manifest()
    records = data.get("charms", [])
    if not records:
        sys.exit("no manifest — run `charm_library.py init` first")

    changed, absent = [], []
    for r in records:
        src = SOURCE_DIR / r["sourceFilename"]
        if not src.exists():
            absent.append(r["sourceFilename"])
        elif r["sourceSHA256"] and sha256(src) != r["sourceSHA256"]:
            changed.append(r["sourceFilename"])

    by_cat = {}
    for r in records:
        c = by_cat.setdefault(r["category"], [0, 0])
        c[0] += 1
        c[1] += 1 if r["processed"] else 0

    print(f"{'category':12s} {'total':>6s} {'processed':>10s}")
    for cat in sorted(by_cat):
        n, p = by_cat[cat]
        print(f"{cat:12s} {n:6d} {p:10d}")
    print(f"{'TOTAL':12s} {len(records):6d} "
          f"{sum(1 for r in records if r['processed']):10d}")
    print()
    for name, ids in BATCHES.items():
        done = sum(1 for r in records
                   if r.get("batch") == name and r["processed"])
        print(f"{name:14s}{len(ids)} charms, {done} processed")
    print(f"{'cut':14s}{len(CUT)} charms rejected in review")
    print(f"licence       {data['license']} "
          f"(verified={data['licenseVerified']}) — {CREATOR}")
    print(f"sources       {len(records) - len(absent)} present, "
          f"{len(absent)} absent")
    print("integrity     " + ("ALL SOURCES UNCHANGED"
                              if not changed else f"CHANGED: {changed}"))
    if absent:
        print(f"absent        {', '.join(absent)}")
    if changed:
        sys.exit(1)


def cmd_verify():
    """Check that what the manifest claims is processed really is.

    A Cycles render once came back with a large opaque black block on three
    charms in one batch — same script, same inputs, and a re-run was clean.
    Nothing failed and nothing logged, so the only defence against shipping
    a corrupt thumbnail is to look at the pixels afterwards.
    """
    from PIL import Image
    import numpy as np

    data = load_manifest()
    problems = []
    checked = 0
    for rec in data.get("charms", []):
        if not rec["processed"]:
            continue
        checked += 1
        for key in ("processedFilename", "thumbnailFilename"):
            if not (LIBRARY / rec[key]).exists():
                problems.append(f'{rec["id"]}: missing {rec[key]}')
        png = LIBRARY / rec["thumbnailFilename"]
        if not png.exists():
            continue
        a = np.array(Image.open(png).convert("RGBA"))
        opaque = a[..., 3] > 250
        if opaque.sum() == 0:
            problems.append(f'{rec["id"]}: thumbnail is empty')
            continue
        # Real shading never lands on exactly 0,0,0 in any quantity; the
        # corrupt renders were thousands of pure-black pixels.
        pure = ((a[..., 0] == 0) & (a[..., 1] == 0) & (a[..., 2] == 0)
                & opaque).sum()
        if pure > 0.05 * opaque.sum():
            problems.append(f'{rec["id"]}: {pure} pure-black opaque pixels '
                            f'({100 * pure / opaque.sum():.1f}%) — re-render')
        cat = LIBRARY / rec["category"] / f'{rec["id"]}.json'
        if not cat.exists():
            problems.append(f'{rec["id"]}: no processing record in {rec["category"]}/')

    print(f"checked {checked} processed charms")
    for p in problems:
        print("  PROBLEM", p)
    print("OK" if not problems else f"{len(problems)} PROBLEMS")
    if problems:
        sys.exit(1)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "report"
    {"init": cmd_init, "report": cmd_report,
     "verify": cmd_verify}[cmd]()
