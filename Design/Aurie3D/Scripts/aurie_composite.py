"""Compose a finished Aurie from the app's OWN shipped layer manifest.

Everything here is read out of `AurieBlenderAssets.swift` and the asset
catalog, so a preview built with this cannot drift from what the app draws:
if the art is re-exported, these pictures follow it. Nothing is hardcoded
except the family colours, which come from `AurieGenerator.auraColors`.
"""

import pathlib
import re

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
SWIFT = REPO / "Auries/Services/AurieBlenderAssets.swift"
CATALOG = REPO / "Auries/Assets.xcassets/AurieBlender"

# AurieGenerator.auraColors, verbatim.
FAMILY_COLOURS = {
    "ember": (255, 94, 58), "glow": (255, 209, 84), "moss": (120, 190, 110),
    "tide": (74, 165, 200), "dusk": (150, 110, 200), "stone": (150, 150, 150),
    "starlight": (180, 200, 255),
}
NEUTRAL_ALBEDO = 192.0          # the neutral the bodies were rendered at

LAYER_RE = re.compile(
    r'"(?P<key>[^"]+)": Layer\(asset: "(?P<asset>[^"]+)", '
    r'size: CGSize\(width: (?P<w>[-\d.]+), height: (?P<h>[-\d.]+)\), '
    r'position: CGPoint\(x: (?P<x>[-\d.]+), y: (?P<y>[-\d.]+)\)\)')

_CACHE = {}


ANCHOR_RE = re.compile(
    r'anchors: Anchors\(tail: CGPoint\(x: ([-\d.]+), y: ([-\d.]+)\), '
    r'head: CGPoint\(x: ([-\d.]+), y: ([-\d.]+)\), '
    r'back: CGPoint\(x: ([-\d.]+), y: ([-\d.]+)\)\)')


def anchors(body):
    """Attachment points in POINTS from the art centre, +y up."""
    return _manifest()[body]["anchors"]


def bodies():
    return sorted(_manifest().keys())


def _manifest():
    if _CACHE:
        return _CACHE
    text = SWIFT.read_text()
    for m in re.finditer(r'"(\w+)": Body\(layers: \[', text):
        name = m.group(1)
        rest = text[m.end():]
        block, tail = rest.split("], legLift:", 1)
        lifts = dict(re.findall(r'"(\w+)": ([\d.]+)', tail.split("]", 1)[0]))
        am = ANCHOR_RE.search(tail.split("),\n", 1)[0])
        anc = ({"tail": (float(am.group(1)), float(am.group(2))),
                "head": (float(am.group(3)), float(am.group(4))),
                "back": (float(am.group(5)), float(am.group(6)))}
               if am else {})
        _CACHE[name] = dict(
            layers={mm["key"]: mm.groupdict()
                    for mm in LAYER_RE.finditer(block)},
            lift={k: float(v) for k, v in lifts.items()}, anchors=anc)
    return _CACHE


def _tint(im, rgb):
    r, g, b, a = im.split()
    table = [min(255, int(i * rgb[c] / NEUTRAL_ALBEDO))
             for c in range(3) for i in range(256)]
    return Image.merge("RGBA", (r.point(table[0:256]), g.point(table[256:512]),
                                b.point(table[512:768]), a))


def compose(body="round", family="tide", arm="arm_01", leg="leg_01",
            face="happy", px_per_pt=1.0, canvas_pt=760, body_image=None):
    """Return (image, origin, parts).

    `origin` is the art centre in pixels — every manifest position is
    relative to it, so anything placed on the creature needs that reference
    rather than the image's own corner. `parts` gives each drawn layer's
    pixel box, which is how a caller can find the crown or the mouth instead
    of guessing at fractions of the silhouette.
    """
    data = _manifest()[body]
    layers, lift = data["layers"], data["lift"].get(leg, 0.0)

    order = ["body", "tuft", f"{arm}_l", f"{arm}_r", f"{leg}_l", f"{leg}_r",
             f"face_{face}_cheeks", f"face_{face}_mouth", f"face_{face}_eyes"]
    tinted = {"body", "tuft", f"{arm}_l", f"{arm}_r", f"{leg}_l", f"{leg}_r"}
    rgb = FAMILY_COLOURS[family]

    size = int(canvas_pt * px_per_pt)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cx = cy = size / 2
    parts = {}
    for key in order:
        spec = layers.get(key)
        if spec is None:
            continue
        src = CATALOG / f'{spec["asset"]}.imageset' / f'{spec["asset"]}.png'
        if not src.exists():
            continue
        w = max(1, round(float(spec["w"]) * px_per_pt))
        h = max(1, round(float(spec["h"]) * px_per_pt))
        if key == "body" and body_image is not None:
            # Already tinted (a pattern was applied); drop it in at the same
            # place so the tuft, limbs and FACE still draw on top of it.
            im = body_image.resize((w, h), Image.LANCZOS)
        else:
            im = Image.open(src).convert("RGBA").resize((w, h), Image.LANCZOS)
            if key in tinted:
                im = _tint(im, rgb)
        # Legs stay put; the whole body group rides up by the leg's lift.
        dy = 0.0 if key.startswith(leg) else lift
        px = cx + float(spec["x"]) * px_per_pt - w / 2
        py = cy - (float(spec["y"]) + dy) * px_per_pt - h / 2
        canvas.alpha_composite(im, (round(px), round(py)))
        parts[key] = (px, py, px + w, py + h)
    return canvas, (cx, cy), parts
