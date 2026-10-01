"""Heart-ish Aurie — v1 candidate (rapid phase, rig OPEN).

Identity: VERY subtle heart influence — full paired shoulders and a
barely-suggested soft crown indentation (a smooth center dip the tuft
nestles into). Explicitly NOT a Valentine heart: no point, no lobed
outline, just the hint. The dent lives entirely above the face zone so
the conforming-face surface stays exact. Shared pipeline:
aurie_body_common.
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aurie_body_common as common  # noqa: E402

HEART_STRETCH = 1.02
BODY_WIDEN = 0.97
SHOULDER_FULL = 0.13        # upper-biased fullness (paired shoulders)
LOWER_TAPER = 0.15          # slightly smaller rounded base
DENT_DEPTH = 0.14           # crown center dip
DENT_SIGMA = 0.30           # dip half-width in x
DENT_START_T = 0.40         # dip zone begins here (face is below)
FLATTEN = 0.02
LIFT = (1.0 - FLATTEN) * HEART_STRETCH + 0.010


def heart_width(t):
    u_bot, u_top = (1 - t) / 2, (1 + t) / 2
    return (BODY_WIDEN * (1 + SHOULDER_FULL * u_top ** 1.5)
            * (1 - LOWER_TAPER * u_bot ** 1.6))


def heart_dent(x, z_world):
    u = (z_world - (LIFT + DENT_START_T * HEART_STRETCH)) \
        / ((1 - DENT_START_T) * HEART_STRETCH)
    if u <= 0:
        return 0.0
    return DENT_DEPTH * math.exp(-(x / DENT_SIGMA) ** 2) * u * u


CFG = dict(name="heart", stretch=HEART_STRETCH, width_fn=heart_width,
           z_dent=heart_dent, flatten=FLATTEN, lift=LIFT,
           eye_frac=0.62, tuft_z=1.93)

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", required=True)
    common.render_all(CFG, os.path.abspath(parser.parse_args(argv).outdir))
