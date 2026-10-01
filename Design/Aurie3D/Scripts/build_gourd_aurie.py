"""Gourd Aurie — v1 candidate (rapid phase, rig OPEN).

REMOVED FROM ACTIVE LIBRARY (2026-08-16): rejected during the
library review — kept on disk as history only. Do not include in
library sheets or lineups.

Identity: a gentle two-mass suggestion — a soft restrained waist dip
between a smaller upper lobe and a fuller lower body. Deliberately
subtle: no hard constriction, no literal gourd. The face sits on the
upper lobe. Shared pipeline: aurie_body_common.
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aurie_body_common as common  # noqa: E402

GOURD_STRETCH = 1.08
BODY_WIDEN = 0.90
LOWER_FULL = 0.15
UPPER_ROUND = 0.13
WAIST_DEPTH = 0.07          # gentle inward dip
WAIST_T, WAIST_W = 0.18, 0.16
LOBE_FULL = 0.10            # soft upper-lobe swell above the waist
LOBE_T, LOBE_W = 0.55, 0.22
FLATTEN = 0.02


def _g(t, c, s):
    return math.exp(-((t - c) / s) ** 2)


def gourd_width(t):
    u_bot, u_top = (1 - t) / 2, (1 + t) / 2
    return (BODY_WIDEN * (1 + LOWER_FULL * u_bot ** 1.3)
            * (1 - UPPER_ROUND * u_top ** 2.0)
            * (1 - WAIST_DEPTH * _g(t, WAIST_T, WAIST_W))
            * (1 + LOBE_FULL * _g(t, LOBE_T, LOBE_W)))


CFG = dict(name="gourd", stretch=GOURD_STRETCH, width_fn=gourd_width,
           flatten=FLATTEN, eye_frac=0.70)

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", required=True)
    common.render_all(CFG, os.path.abspath(parser.parse_args(argv).outdir))
