"""Dumpling Aurie — v1 candidate (rapid body-library phase, rig OPEN).

Identity: squat and plump with a gently pinched/rounded upper contour
and a soft weighted base. Distinct from Round (lower mass bias,
squatter, tapered crown) and Wide (narrower, more dome shaping).
Shared family pipeline: aurie_body_common.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aurie_body_common as common  # noqa: E402

DUMPLING_SQUASH = 0.90
BODY_WIDEN = 1.02
BELLY_FULL = 0.12           # soft weighted base
CROWN_PINCH = 0.13          # gentle upper pinch, concentrated high
FLATTEN = 0.025


def dumpling_width(t):
    u_bot, u_top = (1 - t) / 2, (1 + t) / 2
    return (BODY_WIDEN * (1 + BELLY_FULL * u_bot ** 1.4)
            * (1 - CROWN_PINCH * u_top ** 2.2))


CFG = dict(name="dumpling", stretch=DUMPLING_SQUASH,
           width_fn=dumpling_width, flatten=FLATTEN)

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", required=True)
    common.render_all(CFG, os.path.abspath(parser.parse_args(argv).outdir))
