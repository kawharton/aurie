"""Install the Blender export into the app: crop each layer to its alpha
bbox, write the asset catalog, and GENERATE the Swift manifest.

    python3 install_app_assets.py --export-dir <dir> [--egg-dir <dir>]

Second half of the Stage 3 pipeline. `export_app_layers.py` renders the
layers and writes each body's manifest JSON; this turns those masters into
shipped imagesets plus `AurieBlenderAssets.swift`. Run it after any export
and the whole catalog is reproduced from committed tooling — nothing here is
hand-maintained, and no asset filename is typed by hand anywhere in the app.

Regenerating is safe and idempotent: the catalog is cleared and rebuilt from
the masters, so a layer removed upstream cannot linger.
"""

import argparse
import glob
import json
import os
import pathlib
import sys

import numpy as np
from PIL import Image

# The approved belly-patch rules (edge profile, core definition) come from
# the production reference module — never restated here.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import aurie_belly

HERE = pathlib.Path(__file__).resolve().parent
APP = HERE.parents[2]                      # <repo>/Design/Aurie3D/Scripts
CATALOG = APP / "Auries/Assets.xcassets/AurieBlender"
SWIFT = APP / "Auries/Services/AurieBlenderAssets.swift"

CANVAS_PX = 1024.0
# Round's body+limb footprint measures 665 px in the canvas and the app's
# collision footprint is 350 units, so one canvas = this many points. The
# SAME mapping is used for every body: the bodies are already in correct
# relative proportion to each other in the 3D scenes, so a per-body scale
# would break that (Small must look small).
CANVAS_PT = CANVAS_PX * 350.0 / 665.0
Y_SHIFT_PT = -9.0            # app art centre sits 9 units below the origin
SCALE = CANVAS_PT / CANVAS_PX

# Layers the app does NOT ship. The tail and its anchors stay fully intact
# in the exporter and in the export directory — this only stops them being
# installed, so the accessory work can be picked back up by flipping this.
EXCLUDE_LAYERS = ("tail",)
EMIT_ANCHORS = False

BODIES = ["round", "tall", "small", "egg", "pear", "dumpling", "teardrop",
          "beanbag", "oval", "heart"]

CONTENTS = {"images": [{"filename": None, "idiom": "universal",
                        "scale": "1x"}],
            "info": {"author": "xcode", "version": 1}}


def install(png: pathlib.Path, asset: str, bbox=None):
    """Crop `png` to `bbox` (its own alpha bbox if None) and install it as an
    imageset. Pattern masks pass the BODY layer's bbox so they register
    pixel-for-pixel with the body sprite instead of cropping to their own
    (slightly different, anti-aliased) silhouette. The raw pixel bbox is
    returned as `px_bbox` so the body pass can hand it to the mask pass."""
    im = (png if isinstance(png, Image.Image)
          else Image.open(png)).convert("RGBA")
    if bbox is None:
        bbox = im.getbbox()
    if bbox is None:
        return None
    crop = im.crop(bbox)
    d = CATALOG / f"{asset}.imageset"
    d.mkdir(parents=True, exist_ok=True)
    out = d / f"{asset}.png"
    crop.save(out, optimize=True)
    c = json.loads(json.dumps(CONTENTS))
    c["images"][0]["filename"] = out.name
    (d / "Contents.json").write_text(json.dumps(c, indent=2))
    x0, y0, x1, y1 = bbox
    w, h = x1 - x0, y1 - y0
    return dict(asset=asset, w=w * SCALE, h=h * SCALE,
                x=((x0 + x1) / 2 - CANVAS_PX / 2) * SCALE,
                y=(CANVAS_PX / 2 - (y0 + y1) / 2) * SCALE + Y_SHIFT_PT,
                bytes=out.stat().st_size, decoded=w * h * 4, px_bbox=bbox)


def build_belly(body_png: pathlib.Path, zone_png: pathlib.Path):
    """Compose the shipped BELLY-PATCH layer and its bellyCore.

    Approved recipe (aurie_belly.py, frozen 2026-09-17): the layer's RGB
    is the body's own NEUTRAL beauty render — so it carries that body's
    exact shading, which is what makes it read as body coloration — and
    its alpha is body alpha x the PATCH profile of the generated zone
    (solid boundary, ~8 px soft rim). Peak opacity (0.85 plain / 1.00
    patterned) is applied by the RUNTIME as node alpha, because the same
    body serves both plain and patterned Auries.

    Both inputs are full-frame renders of the same unlifted body scene,
    so they are pixel-registered before any cropping; the composed layer
    is then cropped to the BODY bbox exactly like a pattern mask.

    Returns (PIL image full-frame, core_centre_px, core_size_px) or None
    when the zone is missing. bellyCore uses the proven alpha>0.5
    definition from aurie_belly.belly_core — never recomputed elsewhere.
    """
    if not zone_png.exists():
        return None
    body = np.asarray(Image.open(body_png).convert("RGBA")).astype(np.float64) / 255.0
    zone = np.asarray(Image.open(zone_png).convert("RGBA")).astype(np.float64) / 255.0
    patched = aurie_belly.patch_zone(zone)
    layer = aurie_belly.build_belly_layer(body, patched, peak=1.0)
    centre, size = aurie_belly.belly_core(zone, body[..., 3])
    im = Image.fromarray((np.clip(layer, 0, 1) * 255).round().astype(np.uint8))
    return im, centre, size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--export-dir", required=True,
                    help="output directory of export_app_layers.py")
    ap.add_argument("--egg-dir", default=None,
                    help="directory holding egg_shell_neutral.png")
    args = ap.parse_args()
    global SRC
    SRC = pathlib.Path(args.export_dir).expanduser().resolve()
    if not SRC.exists():
        sys.exit(f"no export at {SRC}")
    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    # Start clean so a removed BODY layer cannot linger — but ONLY across the
    # body layers this script owns, and NEVER the hand-installed hatch assets.
    #
    # The trap: there is a BodyType called "egg", so `owned` below contains the
    # prefix "aurie_egg_". The hatch shell and the seven fracture masks
    # (aurie_egg_shell, aurie_egg_piece_01..07) are authored by hand and
    # regenerated by NOTHING here, yet they ALSO start with "aurie_egg_". A
    # prefix match alone therefore sweeps them up — which is exactly how the
    # dimensional Blender egg got deleted (twice). Guard them explicitly: no
    # body-layer cleanup may ever touch a HATCH_OWNED asset.
    owned = tuple(f"aurie_{b}_" for b in BODIES)
    HATCH_OWNED = ("aurie_egg_shell", "aurie_egg_piece_")
    for old in CATALOG.glob("aurie_*.imageset"):
        if old.stem.startswith(HATCH_OWNED):
            continue                       # hatch asset: hand-installed, keep
        if not old.name.startswith(owned):
            continue                       # not one of ours: leave it alone
        for f in old.iterdir():
            f.unlink()
        old.rmdir()

    per_body, totals = {}, dict(count=0, bytes=0, decoded=0)
    for body in BODIES:
        mpath = SRC / f"{body}_manifest.json"
        if not mpath.exists():
            print(f"SKIP {body}: not exported yet")
            continue
        meta = json.loads(mpath.read_text())
        layers = {}
        back_layers = {}
        body_bbox = None
        back_body_bbox = None
        pattern_pngs = []
        for png in sorted(SRC.glob(f"{body}_*.png")):
            stem = png.stem
            if stem.endswith("_reference_neutral"):
                continue
            key = stem[len(body) + 1:]                 # e.g. face_happy_eyes
            # Orientation suffix: `_back` layers ship as their own
            # imagesets (aurie_<body>_<layer>_back) but key into the
            # manifest WITHOUT the suffix, so runtime lookup is uniform
            # across orientations. Front stays implicit/suffix-less.
            back = key.endswith("_back")
            base_key = key[:-5] if back else key
            if base_key in EXCLUDE_LAYERS:
                continue
            # Pattern masks are deferred: they must be cropped to their
            # orientation's BODY bbox (captured below), not their own, so
            # the mask samples at the same UV as that body sprite in the
            # runtime shader.
            if base_key.startswith("pattern_"):
                pattern_pngs.append((png, key, base_key, back))
                continue
            # The belly ZONE render is an input, not a shipped layer: the
            # composed belly-patch layer is built below (build_belly) once
            # the body bbox is known. Never install the raw falloff.
            if base_key == "belly":
                continue
            asset = f"aurie_{body}_{key}"
            rec = install(png, asset)
            if rec is None:
                print(f"EMPTY LAYER {body}/{key}")
                continue
            if key == "body":
                body_bbox = rec["px_bbox"]
            if key == "body_back":
                back_body_bbox = rec["px_bbox"]
            (back_layers if back else layers)[base_key] = rec
            totals["count"] += 1
            totals["bytes"] += rec["bytes"]
            totals["decoded"] += rec["decoded"]
        # Pattern masks, registered to their orientation's body crop.
        for png, key, base_key, back in pattern_pngs:
            bbox = back_body_bbox if back else body_bbox
            if bbox is None:
                print(f"SKIP PATTERN {body}/{key}: no body layer to register to")
                continue
            rec = install(png, f"aurie_{body}_{key}", bbox=bbox)
            if rec is None:
                print(f"EMPTY PATTERN {body}/{key}")
                continue
            (back_layers if back else layers)[base_key] = rec
            totals["count"] += 1
            totals["bytes"] += rec["bytes"]
            totals["decoded"] += rec["decoded"]
        # BELLY PATCH (2026-09-17): composed from the body layer + zone
        # render, registered to the body crop like a pattern. FRONT-ONLY
        # by construction — no back zone exists, so backLayers never gets
        # a "belly" key and the orientation-strict runtime draws nothing
        # on the back.
        belly_core = None
        if body_bbox is not None:
            built = build_belly(SRC / f"{body}_body.png",
                                SRC / f"{body}_belly.png")
            if built:
                im, centre, size_px = built
                rec = install(im, f"aurie_{body}_belly", bbox=body_bbox)
                if rec:
                    layers["belly"] = rec
                    totals["count"] += 1
                    totals["bytes"] += rec["bytes"]
                    totals["decoded"] += rec["decoded"]
                    belly_core = dict(
                        cx=(centre[0] - CANVAS_PX / 2) * SCALE,
                        cy=(CANVAS_PX / 2 - centre[1]) * SCALE + Y_SHIFT_PT,
                        w=size_px[0] * SCALE, h=size_px[1] * SCALE)
            else:
                print(f"NOTE {body}: no belly zone render — belly not installed")
        per_body[body] = dict(layers=layers, back=back_layers, meta=meta,
                              belly_core=belly_core)
        print(f"{body:10s} {len(layers):3d} layers  "
              f"{sum(l['bytes'] for l in layers.values())/1024:7.0f} KB  "
              f"{sum(l['decoded'] for l in layers.values())/1048576:5.2f} MB decoded")

    anchor_decl = [
        "    /// Where an accessory attaches, in POINTS from the art centre.",
        "    struct Anchors {",
        "        let tail: CGPoint",
        "        let head: CGPoint",
        "        let back: CGPoint",
        "    }",
        "",
    ] if EMIT_ANCHORS else []

    lines = [
        "// GENERATED by Design/Aurie3D/Scripts/install_app_assets.py",
        "// — do not hand-edit.",
        "//",
        "// Every Blender-derived layer for the active launch bodies. Each was",
        "// exported full-frame on the shared 1024 canvas, then cropped to its",
        "// alpha bbox; the crop is baked back in as a point size + offset so",
        "// stacking reproduces the pixel-registered export.",
        "import CoreGraphics",
        "",
        "enum AurieBlenderAssets {",
        f"    static let canvasPoints: CGFloat = {CANVAS_PT:.4f}",
        "",
        "    struct Layer {",
        "        let asset: String",
        "        let size: CGSize",
        "        let position: CGPoint",
        "    }",
        "",
    ] + anchor_decl + [
        "    struct Body {",
        "        let layers: [String: Layer]",
        "        /// Body-group lift per leg style, ALREADY IN POINTS.",
        "        /// The legs were exported with the body raised, so the app",
        "        /// raises body+tuft+face+arms by this much to match. Stored",
        "        /// converted (canvas = `ortho` scene units) because doing it",
        "        /// at runtime with a guessed span floated the body.",
        "        let legLift: [String: CGFloat]",
        "        let limbScale: CGFloat",
        "        /// Arms rendered WITHOUT the body holdout (they keep the",
        "        /// shoulder root), so the app draws them behind the body and",
        "        /// rotates them about the joint without a gap opening.",
        "        let animSafeArms: Bool",
        "        /// Shoulder-joint pivot per arm layer, POINTS from the art",
        "        /// centre — the point an arm rotates about to stay attached.",
        "        let armPivot: [String: CGPoint]",
        "        /// Legs rendered WITHOUT the body holdout (they keep the",
        "        /// hip root), so splits/kicks rotate about a hip joint",
        "        /// without the leg detaching from the body.",
        "        let animSafeLegs: Bool",
        "        /// Hip-joint pivot per leg layer, same point space.",
        "        let legPivot: [String: CGPoint]",
        "        /// BELLY PATCH core (2026-09-17): the zone's solid core in",
        "        /// the SAME point space as layer positions (centre + size),",
        "        /// generated with the belly layer from the same zone render.",
        "        /// The runtime places belly stickers from this and must",
        "        /// never recompute its own rectangle. Size .zero = no belly.",
        "        let bellyCoreCenter: CGPoint",
        "        let bellyCoreSize: CGSize",
        "        /// BACK-orientation layers (turntable renders), keyed",
        "        /// like `layers` (suffix-less); assets carry `_back`.",
        "        /// Empty when a body has no back masters yet — the",
        "        /// runtime then falls back to front.",
        "        let backLayers: [String: Layer]",
        "        /// Back shoulder/hip pivots, derived from the back",
        "        /// sprites by the same exporter rules as the front.",
        "        let backArmPivot: [String: CGPoint]",
        "        let backLegPivot: [String: CGPoint]",
    ] + (["        let anchors: Anchors"] if EMIT_ANCHORS else []) + [
        "    }",
        "",
        "    static let bodies: [String: Body] = [",
    ]
    for body, data in per_body.items():
        lines.append(f'        "{body}": Body(layers: [')
        for key, rec in sorted(data["layers"].items()):
            lines.append(f'            "{key}": Layer(asset: "{rec["asset"]}", '
                         f'size: CGSize(width: {rec["w"]:.2f}, '
                         f'height: {rec["h"]:.2f}), '
                         f'position: CGPoint(x: {rec["x"]:.2f}, '
                         f'y: {rec["y"]:.2f})),')
        # Lift is stored in POINTS, converted here with that body's own
        # camera scale: canvas = `ortho` scene units across CANVAS_PT points.
        ppu = CANVAS_PT / data["meta"]["ortho"]
        lift = ", ".join(f'"{k}": {v * ppu:.3f}'
                         for k, v in data["meta"]["leg_lift"].items())
        anc = data["meta"].get("anchors", {})
        # The canvas centre sits at the camera's height, which the manifest
        # does not carry. Recover it from the body layer itself: its alpha
        # bbox spans the measured bodyTop..bodyBottom, so one linear map
        # gives the world z of any canvas row — no re-render needed.
        bl = data["layers"].get("body")
        top, bot = data["meta"]["bodyTop"], data["meta"]["bodyBottom"]
        if bl and top > bot:
            span_px = bl["h"] / SCALE
            top_row = (CANVAS_PX / 2) - (bl["y"] - Y_SHIFT_PT) / SCALE - span_px / 2
            cam_z = top - (CANVAS_PX / 2 - top_row) / span_px * (top - bot)
        else:
            cam_z = 0.0

        def pt(name):
            v = anc.get(name, [0, 0, 0])
            # scene x -> points right, scene z -> points up, both about the
            # art centre; the same ppu the leg lift uses.
            return (f'CGPoint(x: {v[0] * ppu:.2f}, '
                    f'y: {(v[2] - cam_z) * ppu:.2f})')
        anchor_arg = (f', anchors: Anchors(tail: {pt("tail")}, '
                      f'head: {pt("head")}, back: {pt("back")})'
                      if EMIT_ANCHORS else "")

        # Shoulder pivot per arm layer (anim-safe bodies only): the inner
        # edge of the arm, up near the shoulder. Same point space as the
        # layer position, so the app rotates the arm about it directly.
        anim = bool(data["meta"].get("anim_safe_arms", False))
        pivots = []
        if anim:
            for key, rec in sorted(data["layers"].items()):
                if not key.startswith("arm_"):
                    continue
                w, h, x, y = rec["w"], rec["h"], rec["x"], rec["y"]
                px = (x - w / 2) + 0.12 * w if key.endswith("_r") \
                    else (x + w / 2) - 0.12 * w
                py = y + 0.22 * h
                pivots.append(f'"{key}": CGPoint(x: {px:.2f}, y: {py:.2f})')
        armpiv = "[" + ", ".join(pivots) + "]" if pivots else "[:]"

        # Hip pivot per leg layer (anim-safe legs only): top-centre of the
        # sprite, tucked slightly down so the pivot sits inside the buried
        # root — the point a leg swings about for kicks and splits.
        anim_l = bool(data["meta"].get("anim_safe_legs", False))
        lpivots = []
        if anim_l:
            for key, rec in sorted(data["layers"].items()):
                if not key.startswith("leg_"):
                    continue
                w, h, x, y = rec["w"], rec["h"], rec["x"], rec["y"]
                px = x
                py = y + h / 2 - 0.10 * h
                lpivots.append(f'"{key}": CGPoint(x: {px:.2f}, y: {py:.2f})')
        legpiv = "[" + ", ".join(lpivots) + "]" if lpivots else "[:]"

        def pivots_for(recs, prefix, rule):
            out = []
            for key, rec in sorted(recs.items()):
                if not key.startswith(prefix):
                    continue
                w, h, x, y = rec["w"], rec["h"], rec["x"], rec["y"]
                px, py = rule(key, w, h, x, y)
                out.append(f'"{key}": CGPoint(x: {px:.2f}, y: {py:.2f})')
            return "[" + ", ".join(out) + "]" if out else "[:]"

        back = data.get("back", {})
        backarm = pivots_for(
            back, "arm_",
            lambda k, w, h, x, y: (((x - w / 2) + 0.12 * w)
                                   if k.endswith("_r")
                                   else ((x + w / 2) - 0.12 * w),
                                   y + 0.22 * h))
        backleg = pivots_for(back, "leg_",
                             lambda k, w, h, x, y: (x, y + h / 2 - 0.10 * h))
        bc = data.get("belly_core")
        core = (f'bellyCoreCenter: CGPoint(x: {bc["cx"]:.2f}, '
                f'y: {bc["cy"]:.2f}), '
                f'bellyCoreSize: CGSize(width: {bc["w"]:.2f}, '
                f'height: {bc["h"]:.2f}), ') if bc else \
               ('bellyCoreCenter: .zero, bellyCoreSize: .zero, ')
        head = ('        ], legLift: [' + lift + '], '
                f'limbScale: {data["meta"]["limb_scale"]}, '
                f'animSafeArms: {"true" if anim else "false"}, '
                f'armPivot: {armpiv}, '
                f'animSafeLegs: {"true" if anim_l else "false"}, '
                f'legPivot: {legpiv}, ' + core)
        if back:
            lines.append(head + 'backLayers: [')
            for key, rec in sorted(back.items()):
                lines.append(
                    f'            "{key}": Layer(asset: "{rec["asset"]}", '
                    f'size: CGSize(width: {rec["w"]:.2f}, '
                    f'height: {rec["h"]:.2f}), '
                    f'position: CGPoint(x: {rec["x"]:.2f}, '
                    f'y: {rec["y"]:.2f})),')
            lines.append(f'        ], backArmPivot: {backarm}, '
                         f'backLegPivot: {backleg}'
                         f'{anchor_arg}),')
        else:
            # an empty dictionary literal is [:], never []
            lines.append(head + 'backLayers: [:], backArmPivot: [:], '
                         f'backLegPivot: [:]{anchor_arg}),')
    lines += ["    ]", "",
              "    /// Bodies that shipped with a complete Blender layer set.",
              "    static var supported: Set<String> { Set(bodies.keys) }",
              "}", ""]
    SWIFT.write_text("\n".join(lines))

    if args.egg_dir:
        egg = pathlib.Path(args.egg_dir).expanduser().resolve()
        shell = egg / "egg_shell_neutral.png"
        if shell.exists():
            # Cropped to its own outline so it maps 1:1 onto the rect
            # EggShape already used, keeping the crack paths registered.
            rec = install(shell, "aurie_egg_shell")
            print(f"egg shell   {rec['bytes']/1024:7.0f} KB")
        else:
            print(f"NOTE no egg shell at {shell}")
    print(f"\nTOTAL {totals['count']} layers | "
          f"{totals['bytes']/1048576:.2f} MB on disk | "
          f"{totals['decoded']/1048576:.2f} MB decoded if ALL resident")
    print(f"wrote {SWIFT.relative_to(APP)}")


if __name__ == "__main__":
    main()
