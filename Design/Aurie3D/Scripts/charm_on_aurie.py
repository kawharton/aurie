"""Every kept charm shown on an Aurie, at its recorded attachment slot.

    python3 charm_on_aurie.py [--out <png>]

This is a MOCKUP, not app behaviour: nothing in the iOS app places charms
yet. Its job is to answer two questions the flat contact sheets cannot —
whether a charm still reads once it is beside a creature, and whether the
attachment slots the processor recorded actually make sense.

Placement uses each charm's own stored anchor (the point ON the charm that
meets the Aurie), so this doubles as a check of that data. The Aurie itself
is composed from the app's shipped layer manifest, and its body, family,
limbs and face are picked deterministically from the charm's id — a
different creature per charm, but the same one every run.
"""

import argparse
import hashlib
import json
import pathlib

from PIL import Image, ImageDraw, ImageFont

import aurie_composite as AC

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
LIBRARY = REPO / "AurieCharmLibrary"
OUTDIR = REPO / "Design/Aurie3D/Previews"

RENDER_PX = 512.0        # charm thumbnails are square, uncropped
ORTHO = 1.30             # scene units across that render (charm_processor)
CHARM_PT = 80.0          # a charm's canonical box, in app points
AURIE_FOOTPRINT_PT = 350.0

FAMILIES = list(AC.FAMILY_COLOURS)
ARMS = ["arm_00", "arm_01", "arm_02"]
LEGS = ["leg_00", "leg_01", "leg_02", "leg_03"]
FACES = ["happy", "curious", "delighted", "excited", "mischievous", "shy"]

INK = (34, 30, 44)
MUTED = (122, 116, 138)
PAPER = (250, 248, 252)
PANEL = (255, 255, 255)
LINE = (226, 221, 234)


def font(size, bold=False):
    for base in ("/System/Library/Fonts/", "/System/Library/Fonts/Supplemental/"):
        p = pathlib.Path(base) / "HelveticaNeue.ttc"
        if p.exists():
            try:
                return ImageFont.truetype(str(p), size, index=1 if bold else 0)
            except OSError:
                pass
    return ImageFont.load_default()


def pick(charm_id):
    """A stable creature per charm. Hashed, not random, so reruns match."""
    h = hashlib.sha256(charm_id.encode()).digest()
    bodies = AC.bodies()
    return dict(body=bodies[h[0] % len(bodies)],
                family=FAMILIES[h[1] % len(FAMILIES)],
                arm=ARMS[h[2] % len(ARMS)], leg=LEGS[h[3] % len(LEGS)],
                face=FACES[h[4] % len(FACES)])


def anchor_px(rec, px_per_pt):
    """Where the charm's attachment point sits inside its own thumbnail."""
    pos = rec["attachment"]["position"]
    scale = RENDER_PX / ORTHO                    # px per scene unit
    ax = RENDER_PX / 2 + pos[0] * scale
    az = RENDER_PX / 2 - pos[2] * scale
    # the thumbnail is drawn ORTHO scene units wide at CHARM_PT per unit
    draw_w = CHARM_PT * ORTHO * px_per_pt
    k = draw_w / RENDER_PX
    return ax * k, az * k, draw_w


def place(slot, parts, sil, charm_w, charm_h, dx, dy):
    """Target point on the Aurie, and whether the charm draws in front.

    Anchored to the creature's ANATOMY, read from the layer manifest, not to
    fractions of its bounding box. A guessed 0.62-of-height put every held
    charm across the mouth, because where the face sits varies with the body
    shape; measuring from the mouth layer itself works on all ten.
    """
    x0, y0, x1, y1 = sil
    cx = (x0 + x1) / 2
    front = True

    def part(key, default):
        b = parts.get(key)
        return (b[0] + dx, b[1] + dy, b[2] + dx, b[3] + dy) if b else default

    body = part("body", sil)
    crown = min(body[1], part("tuft", body)[1])
    mouth = part(next((k for k in parts if k.endswith("_mouth")), ""), None)
    mouth_y = mouth[3] if mouth else body[1] + (body[3] - body[1]) * 0.55
    belly = body[3]                        # bottom of the body, above feet

    if slot == "HEAD":
        target = (cx, crown + charm_h * 0.10)
    elif slot == "BODY_FRONT":             # held against the tummy
        target = (cx, mouth_y + (belly - mouth_y) * 0.52)
    elif slot == "HANGING":                # a pendant, just under the chin
        target = (cx, mouth_y + (belly - mouth_y) * 0.30)
    elif slot == "BACK":                   # worn, peeking past the shoulder
        target = (cx - (body[2] - body[0]) * 0.34,
                  body[1] + (body[3] - body[1]) * 0.30)
        front = False
    else:                                  # BODY_SIDE — a companion alongside
        target = (x1 + charm_w * 0.26, y1 - charm_h * 0.46)
    return target, front


def layout(rec, px_per_pt):
    """Work out the whole scene before deciding where to put it.

    A companion charm stands BESIDE the creature, so centring the creature
    and then placing the charm pushed every side charm off the edge of its
    cell. The union of creature and charm is what has to be centred.
    """
    who = pick(rec["id"])
    aurie, _, parts = AC.compose(px_per_pt=px_per_pt, **who)
    box = aurie.getbbox()
    if box is None:
        return None

    charm = Image.open(LIBRARY / rec["thumbnailFilename"]).convert("RGBA")
    ax, az, draw_w = anchor_px(rec, px_per_pt)
    charm = charm.resize((round(draw_w), round(draw_w)), Image.LANCZOS)

    target, front = place(rec["attachment"]["type"], parts, box,
                          draw_w, draw_w, 0, 0)
    cx, cy = round(target[0] - ax), round(target[1] - az)
    # the charm's own drawn extent, not its square canvas
    cbox = charm.getbbox() or (0, 0, charm.width, charm.height)
    crect = (cx + cbox[0], cy + cbox[1], cx + cbox[2], cy + cbox[3])
    union = (min(box[0], crect[0]), min(box[1], crect[1]),
             max(box[2], crect[2]), max(box[3], crect[3]))
    return dict(who=who, aurie=aurie, charm=charm, xy=(cx, cy),
                front=front, union=union)


def draw_cell(lay, cell_w, cell_h):
    im = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
    u = lay["union"]
    ox = (cell_w - (u[2] - u[0])) // 2 - u[0]
    oy = (cell_h - (u[3] - u[1])) // 2 - u[1]
    cxy = (lay["xy"][0] + ox, lay["xy"][1] + oy)
    if not lay["front"]:
        im.alpha_composite(lay["charm"], cxy)
    im.alpha_composite(lay["aurie"], (ox, oy))
    if lay["front"]:
        im.alpha_composite(lay["charm"], cxy)
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(OUTDIR / "preview_charm_on_aurie.png"))
    ap.add_argument("--cols", type=int, default=5)
    args = ap.parse_args()

    data = json.loads((LIBRARY / "_MANIFESTS/charms.json").read_text())
    kept = [r for r in data["charms"] if r["processed"]]
    kept.sort(key=lambda r: (r["attachment"]["type"], r["displayName"]))

    px_per_pt = 0.62
    # Lay every scene out first, then size the cell to the widest one, so a
    # single scale holds across the sheet and nothing is ever clipped.
    lays = [(r, layout(r, px_per_pt)) for r in kept]
    lays = [(r, l) for r, l in lays if l]
    cell_w = max(l["union"][2] - l["union"][0] for _, l in lays) + 26
    cell_h = max(l["union"][3] - l["union"][1] for _, l in lays) + 22
    label_h, head_h, GAP = 34, 104, 10
    cols = args.cols
    rows = (len(lays) + cols - 1) // cols
    W = cols * (cell_w + GAP) + GAP
    H = head_h + rows * (cell_h + label_h + GAP) + GAP

    sheet = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(sheet)
    d.text((GAP + 8, 24), "Every kept charm on an Aurie",
           font=font(30, True), fill=INK)
    d.text((GAP + 8, 64),
           f"{len(kept)} charms at their recorded attachment slot · charm "
           f"{CHARM_PT:.0f} pt against a {AURIE_FOOTPRINT_PT:.0f} pt body · "
           f"body, family, limbs and face are picked from each charm's id · "
           f"MOCKUP — the app does not place charms yet",
           font=font(15), fill=MUTED)

    for i, (rec, lay) in enumerate(lays):
        cx = GAP + (i % cols) * (cell_w + GAP)
        cy = head_h + (i // cols) * (cell_h + label_h + GAP)
        d.rounded_rectangle([cx, cy, cx + cell_w, cy + cell_h + label_h],
                            10, fill=PANEL, outline=LINE)
        art = draw_cell(lay, cell_w, cell_h)
        sheet.paste(art, (cx, cy), art)
        who = lay["who"]
        d.text((cx + 12, cy + cell_h + 2), rec["displayName"],
               font=font(16, True), fill=INK)
        d.text((cx + 12, cy + cell_h + 20),
               f'{rec["attachment"]["type"].lower()} · {who["body"]} · '
               f'{who["family"]}', font=font(12), fill=MUTED)

    sheet.save(args.out)
    print(f"wrote {args.out}  ({len(kept)} charms)")


if __name__ == "__main__":
    main()
