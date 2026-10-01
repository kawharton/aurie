"""Mochi Aurie — v1 candidate (rapid phase, rig OPEN).

REMOVED FROM ACTIVE LIBRARY (2026-08-16): rejected during the
library review — kept on disk as history only. Do not include in
library sheets or lineups.

Identity: low, very soft, slightly compressed pillowy blob with a
broad resting base — a gentle superellipse (|t|^2.4) silhouette under
strong vertical compression. Distinct from Wide (less dome, softer
squarer shoulders, lower), Dumpling (no crown pinch, more compressed),
and Pebble (bigger, pillow-soft, no irregularity). Shared pipeline:
aurie_body_common.
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aurie_body_common as common  # noqa: E402

MOCHI_SQUASH = 0.76
BODY_WIDEN = 1.08
MOCHI_POWER = 2.4           # soft pillow superellipse
FLATTEN = 0.032


def mochi_width(t):
    tc = max(-0.999, min(0.999, t))
    sil = (1.0 - abs(tc) ** MOCHI_POWER) ** (1.0 / MOCHI_POWER)
    return BODY_WIDEN * sil / math.sqrt(1.0 - tc * tc)


CFG = dict(name="mochi", stretch=MOCHI_SQUASH, width_fn=mochi_width,
           flatten=FLATTEN)

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", required=True)
    common.render_all(CFG, os.path.abspath(parser.parse_args(argv).outdir))
