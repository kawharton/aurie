"""Beanbag Aurie — v1 candidate (rapid phase, rig OPEN).

Identity: relaxed, slouchy, broad settled lower mass with a narrow
relaxed top — plus a whisper of low-frequency radial irregularity so
it reads settled rather than geometric. Distinct from Wide (symmetric
broad oval) and Mochi/Pebble (see their scripts). Shared pipeline:
aurie_body_common.
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aurie_body_common as common  # noqa: E402

BAG_SQUASH = 0.86
BODY_WIDEN = 1.05
SLUMP = 0.20                # strong low mass (low ease -> settled)
TOP_RELAX = 0.24            # narrow relaxed top
IRR_A, IRR_B = 0.018, 0.012  # gentle settle irregularity
FLATTEN = 0.03


def beanbag_width(t):
    u_bot, u_top = (1 - t) / 2, (1 + t) / 2
    return (BODY_WIDEN * (1 + SLUMP * u_bot ** 1.1)
            * (1 - TOP_RELAX * u_top ** 1.4))


def beanbag_settle(phi):
    return (1.0 + IRR_A * math.cos(2 * phi + 0.6)
            + IRR_B * math.cos(3 * phi - 1.1))


# 2026-08-16 foot/leg placement pass: the broad settled base was
# hiding the feet from the front; more forward emergence (foot_y -0.09)
# keeps them visible under the slump. Framing unchanged.
CFG = dict(name="beanbag", stretch=BAG_SQUASH, width_fn=beanbag_width,
           s_phi=beanbag_settle, flatten=FLATTEN, foot_y=-0.09)

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", required=True)
    common.render_all(CFG, os.path.abspath(parser.parse_args(argv).outdir))
