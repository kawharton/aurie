"""Contact sheets for the charm pilot batch.

    python3 charm_contact_sheet.py --batch batch2 --source-dir <dir>
    python3 charm_contact_sheet.py --batch all --source-dir <dir>

Sheet 1  SOURCE vs AURIE-PROCESSED, same camera, background and scale, so
         the only difference visible is the processing.
Sheet 2  the processed charms ALONE at the size they would actually sit on
         an Aurie, with a real Aurie composed from the app's own shipped
         layer manifest as the scale reference — a guessed reference would
         make the whole sheet meaningless.
"""

import argparse
import json
import pathlib
from PIL import Image, ImageDraw, ImageFont

import aurie_composite as AC

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
LIBRARY = REPO / "AurieCharmLibrary"
OUTDIR = REPO / "Design/Aurie3D/Previews"

INK = (34, 30, 44)
MUTED = (122, 116, 138)
FLAG = (176, 46, 62)
PAPER = (250, 248, 252)
PANEL = (255, 255, 255)
LINE = (226, 221, 234)

# What the app actually uses: the Aurie's collision footprint is 350 points
# wide. A charm reads at roughly a quarter of that.
AURIE_FOOTPRINT_PT = 350.0
CHARM_ON_AURIE_PT = 80.0
# A spread of silhouettes for the scale strip: long, spiky, thin, chunky.
REFERENCE_CHARMS = ("charm_animal_fox_01", "charm_magic_star_01",
                    "charm_object_key_01", "charm_magic_chest_01")


def font(size, bold=False):
    for name in (("HelveticaNeue.ttc",) if not bold else
                 ("HelveticaNeue.ttc",)):
        for base in ("/System/Library/Fonts/", "/Library/Fonts/",
                     "/System/Library/Fonts/Supplemental/"):
            p = pathlib.Path(base) / name
            if p.exists():
                try:
                    return ImageFont.truetype(str(p), size,
                                              index=1 if bold else 0)
                except OSError:
                    pass
    return ImageFont.load_default()


def fit(im, box):
    """Scale to fit a square box without cropping, transparency preserved."""
    im = im.copy()
    im.thumbnail((box, box), Image.LANCZOS)
    out = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    out.alpha_composite(im, ((box - im.width) // 2, (box - im.height) // 2))
    return out


# ---------------------------------------------------------------------------
# a real Aurie, composed from the shipped manifest
# ---------------------------------------------------------------------------

def round_aurie(px_per_pt=3.0):
    """The Round Aurie exactly as the app stacks it, for scale reference.

    Composed from the GENERATED manifest by the shared compositor, so if the
    art is re-exported this reference follows it instead of going stale.
    """
    im, _, _ = AC.compose(body="round", family="tide", arm="arm_01",
                          leg="leg_01", face="happy", px_per_pt=px_per_pt)
    return im.crop(im.getbbox())


# ---------------------------------------------------------------------------

def load(cid, source_dir):
    proc = Image.open(LIBRARY / f"_THUMBNAILS/{cid}.png").convert("RGBA")
    sp = pathlib.Path(source_dir) / f"{cid}_source.png"
    src = Image.open(sp).convert("RGBA") if sp.exists() else None
    return src, proc


def sheet_comparison(records, source_dir, out, title):
    CELL, GAP, COLS = 214, 26, 3
    label_h, head_h = 48, 108
    pair_w = CELL * 2 + 10
    cell_w = pair_w + GAP * 2
    cell_h = CELL + label_h + GAP
    rows = (len(records) + COLS - 1) // COLS
    W = cell_w * COLS + GAP
    H = head_h + cell_h * rows + GAP

    im = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(im)
    d.text((GAP + 8, 26), title, font=font(30, True), fill=INK)
    d.text((GAP + 8, 66),
           "left: SOURCE   right: AURIE-PROCESSED   "
           "identical camera, lighting, background and scale",
           font=font(17), fill=MUTED)

    for i, rec in enumerate(records):
        cx = GAP + (i % COLS) * cell_w
        cy = head_h + (i // COLS) * cell_h
        d.rounded_rectangle([cx, cy, cx + pair_w + GAP, cy + CELL + label_h],
                            10, fill=PANEL, outline=LINE)
        src, proc = load(rec["id"], source_dir)
        if src is not None:
            im.paste(fit(src, CELL), (cx + GAP // 2, cy + 6),
                     fit(src, CELL))
        im.paste(fit(proc, CELL), (cx + GAP // 2 + CELL + 10, cy + 6),
                 fit(proc, CELL))
        d.line([cx + GAP // 2 + CELL + 5, cy + 14,
                cx + GAP // 2 + CELL + 5, cy + CELL - 8], fill=LINE)

        ty = cy + CELL + 4
        p = rec.get("processing", {})
        d.text((cx + GAP // 2, ty), rec["displayName"], font=font(19, True),
               fill=INK)
        g = p.get("geometry", {})
        d.text((cx + GAP // 2, ty + 23),
               f'{p.get("profile", "?")} · {p.get("source", {}).get("polys", 0)}'
               f' -> {g.get("polysAfter", 0)} tris  ·  '
               f'{rec["attachment"]["type"].lower()}',
               font=font(15), fill=MUTED)
        if not p.get("colourComplete", True):
            d.text((cx + pair_w - 146, ty + 26), "SOURCE TEXTURE MISSING",
                   font=font(13, True), fill=FLAG)
    im.save(out)
    return out


def sheet_charm_scale(records, out, title):
    """The processed charms at the size they sit on an Aurie."""
    S = int(CHARM_ON_AURIE_PT)
    # Prefer a column count that fills its last row, but only among WIDE
    # options: at 66 charms the old (5,4,3) preference picked 3 and produced
    # a 4500px ribbon. A ragged last row beats an unreadable sheet.
    COLS = next((c for c in (6, 5, 7, 4, 8) if len(records) % c == 0), 6)
    GAP = 62
    head_h, label_h = 104, 34
    # The cell has to hold the widest NAME, not just the charm: at three
    # columns "Open Treasure Chest" ran straight into "Chicken Leg".
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    widest = max(probe.textlength(r["displayName"], font=font(14, True))
                 for r in records)
    cell = int(max(S + GAP, widest + 14))
    rows = (len(records) + COLS - 1) // COLS
    grid_h = rows * (S + label_h + GAP)

    aurie = round_aurie(px_per_pt=1.0)
    ref_h = aurie.height + 70
    ref = [r for r in records if r["id"] in REFERENCE_CHARMS]

    sub = (f"each charm drawn {S:.0f} pt wide — the Aurie below is the same "
           f"scale ({AURIE_FOOTPRINT_PT:.0f} pt footprint)")

    # Width is driven by whatever is widest — grid, heading or the reference
    # row. Sizing to the grid alone clipped the subtitle and silently
    # dropped every reference charm off the right edge.
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    text_w = max(probe.textlength(title, font=font(28, True)),
                 probe.textlength(sub, font=font(16)))
    ref_w = aurie.width + 40 + len(ref) * (S + 18)
    W = int(max(COLS * cell + GAP, text_w + 2 * GAP, ref_w + 2 * GAP))
    H = head_h + grid_h + ref_h + GAP
    im = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(im)
    d.text((GAP, 24), title, font=font(28, True), fill=INK)
    d.text((GAP, 62), sub, font=font(16), fill=MUTED)

    for i, rec in enumerate(records):
        x = GAP + (i % COLS) * cell
        y = head_h + (i // COLS) * (S + label_h + GAP)
        proc = fit(Image.open(LIBRARY / f'_THUMBNAILS/{rec["id"]}.png')
                   .convert("RGBA"), S)
        im.paste(proc, (x, y), proc)
        d.text((x, y + S + 6), rec["displayName"], font=font(14, True),
               fill=INK)
        d.text((x, y + S + 21), rec["attachment"]["type"].lower(),
               font=font(12), fill=MUTED)

    ry = head_h + grid_h + 12
    d.line([GAP, ry - 14, W - GAP, ry - 14], fill=LINE)
    d.text((GAP, ry - 6), "scale reference", font=font(14, True), fill=MUTED)
    im.paste(aurie, (GAP, ry + 18), aurie)
    ax = GAP + aurie.width + 40
    for rec in ref:
        proc = fit(Image.open(LIBRARY / f'_THUMBNAILS/{rec["id"]}.png')
                   .convert("RGBA"), S)
        im.paste(proc, (ax, ry + 18 + aurie.height - S), proc)
        ax += S + 18
    im.save(out)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source-dir", required=True)
    ap.add_argument("--batch", default="batch1",
                    help="a batch name from the manifest, or 'all'")
    args = ap.parse_args()

    manifest = json.loads((LIBRARY / "_MANIFESTS/charms.json").read_text())
    by_id = {r["id"]: r for r in manifest["charms"]}
    if args.batch == "all":
        ids = [r["id"] for r in manifest["charms"] if r["processed"]]
        label, stem = "every processed charm", "library"
    else:
        ids = manifest["batches"][args.batch]
        label, stem = args.batch, args.batch
    records = [by_id[c] for c in ids if by_id[c]["processed"]]
    if not records:
        raise SystemExit(f"nothing processed in {args.batch}")
    OUTDIR.mkdir(parents=True, exist_ok=True)

    written = []
    # The comparison sheet needs a source render per charm; the library-wide
    # sheet is about cohesion across batches, so it skips that half.
    if args.batch != "all":
        written.append(sheet_comparison(
            records, args.source_dir,
            OUTDIR / f"preview_charm_{stem}_compare.png",
            f"Aurie Charm Processor v1 — {label}"))
    written.append(sheet_charm_scale(
        records, OUTDIR / f"preview_charm_{stem}_scale.png",
        f"{label.capitalize()} at actual charm scale"))
    print("\n".join(f"wrote {w}" for w in written))


if __name__ == "__main__":
    main()
