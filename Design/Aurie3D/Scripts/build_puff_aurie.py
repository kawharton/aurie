"""Puff (Top-Heavy) Aurie — v1 candidate (rapid phase, rig OPEN).

Identity: fuller upper body over a smaller lower region — soft
cloud/puff weighting, the family's only top-heavy mass. Max width
lands ABOVE center; the base stays substantial and rounded so it
never reads as an inverted triangle. Shared pipeline: aurie_body_common.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aurie_body_common as common  # noqa: E402

PUFF_STRETCH = 1.02
BODY_WIDEN = 0.93
TOP_FULL = 0.16             # cloud weighting biased upward
LOWER_TAPER = 0.20          # smaller lower region, still rounded
FLATTEN = 0.018


def puff_width(t):
    u_bot, u_top = (1 - t) / 2, (1 + t) / 2
    return (BODY_WIDEN * (1 + TOP_FULL * u_top ** 1.3)
            * (1 - LOWER_TAPER * u_bot ** 1.6))


CFG = dict(name="puff", stretch=PUFF_STRETCH, width_fn=puff_width,
           flatten=FLATTEN, eye_frac=0.65)

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", required=True)
    common.render_all(CFG, os.path.abspath(parser.parse_args(argv).outdir))
