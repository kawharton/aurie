"""Re-partition the frozen seven egg piece masks against the Blender shell.

    python3 adapt_egg_piece_masks.py --old-masks <dir> --full-mask <png>

RECOVERY TOOL. The seven piece masks come from `hatch-sequence-polish`
(commit b8639be); extract them without checking the branch out:

    for i in 01 02 03 04 05 06 07; do
      git show b8639be:Auries/Assets.xcassets/egg_piece_mask_$i.imageset/egg_piece_mask_$i.png \
        > <dir>/piece_$i.png
    done
    git show b8639be:Auries/Assets.xcassets/egg_mask_full.imageset/egg_mask_full.png > <full>

Those masks were authored for the older Illustrator egg, which is ~5.6%
narrower than the current approved silhouette (aspect 0.7240 vs 0.7672;
normalised IoU 0.965). The SHELL IS AUTHORITATIVE and is never reshaped:
the masks are mapped into its bounds instead, then every shell pixel is
assigned to exactly one piece, so the union reproduces the shell alpha with
no slivers, gaps or overhang. Piece centroids are normalised to the egg
frame, so they survive this remap unchanged.
"""

import argparse
import json
import pathlib

import numpy as np
from PIL import Image

APP = pathlib.Path(__file__).resolve().parents[3]
SHELL = (APP / "Auries/Assets.xcassets/AurieBlender/"
         "aurie_egg_shell.imageset/aurie_egg_shell.png")
CATALOG = APP / "Auries/Assets.xcassets/AurieBlender"
CONTENTS = {"images": [{"filename": None, "idiom": "universal",
                        "scale": "3x"}],
            "info": {"author": "xcode", "version": 1}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old-masks", required=True)
    ap.add_argument("--full-mask", required=True)
    args = ap.parse_args()
    old = pathlib.Path(args.old_masks)

    # Generate at the EXACT rendered pixel size (230x300 pt at 3x) and ship
    # the imagesets as 3x, so the mask maps 1:1 onto the drawn egg. Scaled
    # masks give seam pixels whose alphas do not sum to 1 across neighbours,
    # which let the background through as thin dark lines along every seam.
    EGG_PT = (230, 300)
    SCALE = 3
    w, h = EGG_PT[0] * SCALE, EGG_PT[1] * SCALE
    shell_alpha = np.array(Image.open(SHELL).convert("RGBA")
                           .resize((w, h), Image.LANCZOS))[..., 3]
    bbox = Image.open(args.full_mask).convert("RGBA").getbbox()

    stack = []
    for i in range(1, 8):
        m = Image.open(old / f"piece_{i:02d}.png").convert("RGBA").crop(bbox)
        stack.append(np.array(m.resize((w, h), Image.LANCZOS))[..., 3]
                     .astype(np.int16))
    stack = np.stack(stack)

    labels = np.where(stack.max(axis=0) > 8, stack.argmax(axis=0) + 1, 0)
    labels[shell_alpha <= 8] = 0
    gap = (shell_alpha > 8) & (labels == 0)
    for _ in range(64):                      # grow into unclaimed shell px
        if not gap.any():
            break
        grown = labels.copy()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.roll(labels, (dy, dx), (0, 1))
            take = gap & (grown == 0) & (sh > 0)
            grown[take] = sh[take]
        labels = grown
        gap = (shell_alpha > 8) & (labels == 0)

    union = np.zeros((h, w), dtype=np.int32)
    for i in range(1, 8):
        # HARD partition: no dilation. Overlapping pieces double-composite
        # their antialiased edges, which thinned every crack stroke where it
        # crossed a seam. Each pixel now belongs to exactly one piece and the
        # seven cut bitmaps tile the shell exactly.
        sel = labels == i
        alpha = (sel.astype(np.float32) * shell_alpha).clip(0, 255)
        rgba = np.dstack([np.full((h, w), 255, np.uint8)] * 3
                         + [alpha.astype(np.uint8)])
        name = f"aurie_egg_piece_{i:02d}"
        d = CATALOG / f"{name}.imageset"
        d.mkdir(parents=True, exist_ok=True)
        Image.fromarray(rgba).save(d / f"{name}.png", optimize=True)
        c = json.loads(json.dumps(CONTENTS))
        c["images"][0]["filename"] = f"{name}.png"
        (d / "Contents.json").write_text(json.dumps(c, indent=2))
        union += sel

    shell_px = int((shell_alpha > 8).sum())
    print(f"partition: union {int((union > 0).sum())} vs shell {shell_px} | "
          f"double-claimed {int((union > 1).sum())} | "
          f"uncovered {int(((shell_alpha > 8) & (union == 0)).sum())}")


if __name__ == "__main__":
    main()
