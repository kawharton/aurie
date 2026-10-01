"""Placement QA for the three-slot accessory system, on the real renderer.

    python3 accessory_qa.py

Two sheets:
  preview_accessory_slots.png   every test accessory in its slot, across
                                the six review bodies
  preview_accessory_combos.png  the seven equip combinations, so clutter
                                and layer order can be judged

Everything is composed from the app's shipped layers — including the new
tail — so what is on the sheet is what the app would draw.
"""

import json
import pathlib

from PIL import Image, ImageDraw, ImageFont

import accessory_slots as SL
import aurie_composite as AC

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
LIBRARY = REPO / "AurieCharmLibrary"
OUTDIR = REPO / "Design/Aurie3D/Previews"

BODIES = ["round", "tall", "small", "pear", "beanbag", "heart"]
TAIL = ["charm_object_key_01", "charm_magic_crystal_02", "charm_magic_star_01"]
# Crown was cut in accessory QA. The rest of the brief's head list stands:
# a flower, a second flower-like shape, and filigree.
HEAD = ["charm_nature_flower_02", "charm_nature_petals_01",
        "charm_nature_snowflake_01"]
BACK = ["charm_object_backpack_01"]

FAMILY_OF = {"round": "tide", "tall": "glow", "small": "moss",
             "pear": "dusk", "beanbag": "ember", "heart": "starlight"}
LOOK = dict(arm="arm_01", leg="leg_01", face="happy")

INK, MUTED, PAPER, PANEL, LINE = ((34, 30, 44), (122, 116, 138),
                                  (250, 248, 252), (255, 255, 255),
                                  (226, 221, 234))


def font(size, bold=False):
    for base in ("/System/Library/Fonts/",
                 "/System/Library/Fonts/Supplemental/"):
        p = pathlib.Path(base) / "HelveticaNeue.ttc"
        if p.exists():
            try:
                return ImageFont.truetype(str(p), size, index=1 if bold else 0)
            except OSError:
                pass
    return ImageFont.load_default()


def charms():
    data = json.loads((LIBRARY / "_MANIFESTS/charms.json").read_text())
    return {r["id"]: r for r in data["charms"] if r["processed"]}


def grid(cells, cols, title, subtitle, out, px_per_pt):
    """cells: list of (caption, image, union). One scale for the whole sheet."""
    cw = max(u[2] - u[0] for _, _, u in cells) + 26
    ch = max(u[3] - u[1] for _, _, u in cells) + 20
    label_h, head_h, GAP = 32, 100, 10
    rows = (len(cells) + cols - 1) // cols
    W = cols * (cw + GAP) + GAP
    H = head_h + rows * (ch + label_h + GAP) + GAP
    sheet = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(sheet)
    d.text((GAP + 8, 24), title, font=font(30, True), fill=INK)
    d.text((GAP + 8, 64), subtitle, font=font(15), fill=MUTED)

    for i, (cap, im, u) in enumerate(cells):
        cx = GAP + (i % cols) * (cw + GAP)
        cy = head_h + (i // cols) * (ch + label_h + GAP)
        d.rounded_rectangle([cx, cy, cx + cw, cy + ch + label_h], 10,
                            fill=PANEL, outline=LINE)
        crop = im.crop(u)
        sheet.paste(crop, (cx + (cw - crop.width) // 2,
                           cy + (ch - crop.height) // 2), crop)
        d.text((cx + 12, cy + ch + 2), cap[0], font=font(15, True), fill=INK)
        d.text((cx + 12, cy + ch + 19), cap[1], font=font(12), fill=MUTED)
    sheet.save(out)
    return out


def main():
    OUTDIR.mkdir(parents=True, exist_ok=True)
    C = charms()
    px = 0.60

    # ---- sheet 1: each accessory in its slot, on every review body ----
    cells = []
    for body in BODIES:
        for slot, ids in (("TAIL_HANGING", TAIL), ("HEAD", HEAD),
                          ("BACK", BACK)):
            for cid in ids:
                rec = C.get(cid)
                if rec is None:
                    continue
                im, u = SL.render(body, FAMILY_OF[body], LOOK["arm"],
                                  LOOK["leg"], LOOK["face"], {slot: rec}, px)
                size = SL.charm_size_pt(body, slot, rec)
                pct = 100 * size / SL.body_width_pt(body)
                cells.append(((f'{body} · {rec["displayName"]}',
                               f'{slot.lower()} · {size:.0f} pt '
                               f'({pct:.0f}% of body)'), im, u))
    a = grid(cells, 7, "Accessory slots on the real Blender renderer",
             "one accessory at a time · six review bodies · tail, head and "
             "back anchors are measured per body, not shared",
             OUTDIR / "preview_accessory_slots.png", px)

    # ---- sheet 2: the seven equip combinations ----
    combos = [("tail only", {"TAIL_HANGING": C[TAIL[0]]}),
              ("head only", {"HEAD": C[HEAD[0]]}),
              ("back only", {"BACK": C[BACK[0]]}),
              ("head + tail", {"HEAD": C[HEAD[1]],
                               "TAIL_HANGING": C[TAIL[1]]}),
              ("back + tail", {"BACK": C[BACK[0]],
                               "TAIL_HANGING": C[TAIL[2]]}),
              ("head + back", {"HEAD": C[HEAD[2]], "BACK": C[BACK[0]]}),
              ("all three", {"HEAD": C[HEAD[0]], "TAIL_HANGING": C[TAIL[0]],
                             "BACK": C[BACK[0]]})]
    cells = []
    for body in BODIES:
        for name, eq in combos:
            im, u = SL.render(body, FAMILY_OF[body], LOOK["arm"], LOOK["leg"],
                              LOOK["face"], eq, px)
            cells.append(((f"{body} · {name}",
                           " + ".join(sorted(s.lower() for s in eq))), im, u))
    b = grid(cells, 7, "Equip combinations",
             "back sits behind the body; tail and head in front · "
             "random generation should usually land on one or two",
             OUTDIR / "preview_accessory_combos.png", px)
    print(f"wrote {a}\nwrote {b}")


if __name__ == "__main__":
    main()
