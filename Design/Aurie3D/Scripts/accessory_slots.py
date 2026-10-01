"""The three-slot Aurie accessory system: TAIL_HANGING, HEAD, BACK.

Deliberately NOT a free-placement or dress-up system. Three slots, one
accessory each, every position derived from anchors measured off that
body's own mesh at export time — ten silhouettes do not share a coordinate.

    TAIL_HANGING  hangs from the nub at the tail tip, beside the lower
                  body, clear of the torso, the face and the feet
    HEAD          sits on the crown, coexisting with the tuft
    BACK          drawn BEHIND the body, peeking past one shoulder

Accessories keep their own colours. Nothing here tints them to the family;
they are unified by the shared Blender lighting and material treatment
applied when they were processed.
"""

import pathlib

from PIL import Image

from PIL import ImageDraw

import aurie_composite as AC

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
LIBRARY = REPO / "AurieCharmLibrary"

RENDER_PX = 512.0        # charm thumbnails are square and uncropped
ORTHO = 1.30             # scene units across that render (charm_processor)

SLOTS = ("TAIL_HANGING", "HEAD", "BACK")

# Accessory width as a fraction of the body's own on-screen width. The brief
# asks for 20-30%; thin silhouettes need the upper end to stay readable, so
# each slot has a base and every charm can still scale itself.
SLOT_SCALE = {"TAIL_HANGING": 0.30, "HEAD": 0.34, "BACK": 0.62}

# Charms whose drawn shape is mostly empty space (a key is a thin stem, a
# snowflake is filigree). They are boosted so the INK reads at charm size,
# not just the bounding box.
# A back accessory rides high on the back and shows past ONE shoulder.
#
# Two alternatives were built and rejected against the reference. Centring a
# pack wider than the body (1.24x) made the Aurie look like it was standing
# in front of luggage. Painting 2D shoulder straps across the front read as
# flat bars stuck on the chest — the exact "sticker pasted on" failure the
# brief calls out — because a flat overlay cannot sit on a shaded 3D body.
# A single high shoulder peek is what actually reads as worn.
BACK_PEEK = 0.38          # share of the pack's width that clears the shoulder
BACK_RISE = 0.16          # ride height above the exported back anchor

THIN_BOOST = {
    "charm_object_key_01": 1.30, "charm_object_key_02": 1.30,
    "charm_object_key_03": 1.30, "charm_object_fork_01": 1.35,
    "charm_object_spoon_01": 1.35, "charm_nature_snowflake_01": 1.22,
    "charm_nature_snowflake_02": 1.22, "charm_nature_snowflake_03": 1.22,
}


def body_width_pt(body):
    """On-screen width of the body layer, in points."""
    spec = AC._manifest()[body]["layers"].get("body")
    return float(spec["w"]) if spec else 350.0


def charm_size_pt(body, slot, rec):
    base = body_width_pt(body) * SLOT_SCALE[slot]
    return base * rec.get("relativeScale", 1.0) * THIN_BOOST.get(rec["id"], 1.0)


def anchor_in_charm(im, slot):
    """Where THIS slot grips the charm, in pixels inside the drawn image.

    Deliberately NOT the anchor stored on the charm: that one records the
    charm's own preferred slot, and reusing it elsewhere grips the wrong
    end. The snowflake is stored as a HANGING charm, so its anchor is its
    top; hanging a head accessory by its top dropped the whole snowflake
    down over the creature's eyes.

    Taken from the drawn ink rather than the square canvas, so thin charms
    with lots of empty frame still grip at their real edge.
    """
    b = im.getbbox() or (0, 0, im.width, im.height)
    cx = (b[0] + b[2]) / 2.0
    if slot == "TAIL_HANGING":
        return cx, b[1]          # grip the TOP: the charm dangles below
    if slot == "HEAD":
        return cx, b[3]          # grip the BOTTOM: it rests on the crown
    return cx, (b[1] + b[3]) / 2.0


def place(body, slot, rec, px_per_pt, origin):
    """Return (image, top-left xy, draws_in_front).

    `origin` is the art centre in pixels, which is what every anchor and
    layer position in the manifest is measured from.
    """
    anc = AC.anchors(body)
    size = charm_size_pt(body, slot, rec) * px_per_pt
    im = Image.open(LIBRARY / rec["thumbnailFilename"]).convert("RGBA")
    # The thumbnail frame is ORTHO units wide but the charm box is 1.0, so
    # the drawn frame is proportionally larger than the requested size.
    drawn = size * ORTHO
    im = im.resize((max(1, round(drawn)), max(1, round(drawn))), Image.LANCZOS)
    ax, az = anchor_in_charm(im, slot)

    if slot == "TAIL_HANGING":
        ex, ey = anc["tail"]
        # Hang FROM the nub and OVERLAP it. A charm whose top merely met the
        # nub read as floating beside the creature; tucking it behind the
        # nub, with a connector drawn across the joint, reads as linked.
        # Hang BELOW and slightly OUTBOARD of the nub. Tucking the charm up
        # over the tail hid the tail completely and read as the creature
        # holding the charm in its hand.
        tx = origin[0] + (ex + 0.055 * body_width_pt(body)) * px_per_pt
        ty = origin[1] - ey * px_per_pt + size * 0.16 * px_per_pt
        return im, (round(tx - ax), round(ty - az)), True
    if slot == "HEAD":
        ex, ey = anc["head"]
        tx = origin[0] + ex * px_per_pt
        # Seat it INTO the crown. A light rest on the silhouette looks
        # balanced-on-top; sinking a third of the accessory's height gives
        # the socket contact the limbs have.
        ty = origin[1] - ey * px_per_pt + size * 0.34 * px_per_pt
        return im, (round(tx - ax), round(ty - az)), True
    # BACK. Ride it high on the back and let a fixed share clear the
    # shoulder, measured against this body's own width.
    _, ey = anc["back"]
    w = body_width_pt(body)
    ink = im.getbbox() or (0, 0, im.width, im.height)
    ink_w = (ink[2] - ink[0]) / px_per_pt
    tx = origin[0] - (w / 2.0 - BACK_PEEK * ink_w) * px_per_pt
    ty = origin[1] - (ey + BACK_RISE * w) * px_per_pt
    return im, (round(tx - ax), round(ty - az)), False


def draw_connector(canvas, centre, r, family):
    """A small loop across the tail/charm joint.

    The brief allows a connector to borrow the family palette, and it is
    what turns "charm positioned next to a tail" into "charm hanging off
    it": a visible link over the seam removes the gap the eye reads as
    floating.
    """
    rgb = AC.FAMILY_COLOURS[family]
    d = ImageDraw.Draw(canvas)
    x, y = centre
    dark = tuple(max(0, int(c * 0.72)) for c in rgb)
    d.ellipse([x - r, y - r, x + r, y + r], fill=None, outline=dark + (255,),
              width=max(2, round(r * 0.42)))
    d.ellipse([x - r * 0.92, y - r * 0.92, x + r * 0.92, y + r * 0.92],
              fill=None, outline=rgb + (235,), width=max(1, round(r * 0.24)))


def render(body, family, arm, leg, face, equipped, px_per_pt=1.0):
    """Compose one Aurie wearing up to one accessory per slot.

    Returns (image, union bbox). Back accessories composite BEHIND the
    creature; tail and head in front of it.
    """
    aurie, origin, _parts = AC.compose(body=body, family=family, arm=arm,
                                       leg=leg, face=face,
                                       px_per_pt=px_per_pt)
    canvas = Image.new("RGBA", aurie.size, (0, 0, 0, 0))
    front = []
    boxes = []
    for slot in SLOTS:
        rec = equipped.get(slot)
        if rec is None:
            continue
        im, xy, in_front = place(body, slot, rec, px_per_pt, origin)
        b = im.getbbox() or (0, 0, im.width, im.height)
        boxes.append((xy[0] + b[0], xy[1] + b[1], xy[0] + b[2], xy[1] + b[3]))
        if in_front:
            front.append((im, xy))
        else:
            canvas.alpha_composite(im, xy)
    canvas.alpha_composite(aurie, (0, 0))
    for im, xy in front:
        canvas.alpha_composite(im, xy)
    # The tail connector goes on last, bridging the nub and the charm.
    if equipped.get("TAIL_HANGING") is not None:
        ex, ey = AC.anchors(body)["tail"]
        r = body_width_pt(body) * 0.045 * px_per_pt
        draw_connector(canvas, (origin[0] + ex * px_per_pt,
                                origin[1] - ey * px_per_pt + r * 0.35),
                       r, family)

    ab = aurie.getbbox() or (0, 0, aurie.width, aurie.height)
    boxes.append(ab)
    union = (min(b[0] for b in boxes), min(b[1] for b in boxes),
             max(b[2] for b in boxes), max(b[3] for b in boxes))
    return canvas, union
