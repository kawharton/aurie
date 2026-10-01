"""Pebble Aurie — v1 candidate (rapid phase, rig OPEN).

REMOVED FROM ACTIVE LIBRARY (2026-08-16): rejected during the
library review — kept on disk as history only. Do not include in
library sheets or lineups.

Identity: low, compact, softly irregular rounded stone — smaller and
more evenly massed than Wide (no dome emphasis), with gentle radial
irregularity for the stone read. Distinct from Beanbag (no bottom
slump — a pebble is even) and Mochi (not pillow-soft-wide). Shared
pipeline: aurie_body_common.
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aurie_body_common as common  # noqa: E402

PEBBLE_SQUASH = 0.80
BODY_WIDEN = 0.92
SIDE_FILL = 0.08            # slight even mid fullness
IRR_A, IRR_B = 0.022, 0.014  # soft stone irregularity
FLATTEN = 0.022


def pebble_width(t):
    return BODY_WIDEN * (1 + SIDE_FILL * t * t * (1 - t * t))


def pebble_irr(phi):
    return (1.0 + IRR_A * math.cos(2 * phi - 0.4)
            + IRR_B * math.sin(3 * phi + 0.8))


CFG = dict(name="pebble", stretch=PEBBLE_SQUASH, width_fn=pebble_width,
           s_phi=pebble_irr, flatten=FLATTEN)

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", required=True)
    common.render_all(CFG, os.path.abspath(parser.parse_args(argv).outdir))
