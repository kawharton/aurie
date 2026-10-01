"""Squircle Aurie — v1 candidate (rapid phase, rig OPEN).

Identity: a rounded-square mass — the silhouette follows a superellipse
(|t|^3.4 norm) directly: near-constant width through the middle with
soft, fuller corners and no hard edges. Cross-sections stay circular,
so it remains a plush 3D form. Shared pipeline: aurie_body_common.
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aurie_body_common as common  # noqa: E402

SQ_STRETCH = 0.99
BODY_WIDEN = 0.96
SQ_POWER = 3.4              # superellipse exponent (higher = squarer)
FLATTEN = 0.02


def squircle_width(t):
    tc = max(-0.999, min(0.999, t))
    sil = (1.0 - abs(tc) ** SQ_POWER) ** (1.0 / SQ_POWER)
    return BODY_WIDEN * sil / math.sqrt(1.0 - tc * tc)


# 2026-08-16 foot-visibility pass: forward emergence (foot_y -0.10)
# so the pads clear the broad near-constant-width base overhang.
CFG = dict(name="squircle", stretch=SQ_STRETCH, width_fn=squircle_width,
           flatten=FLATTEN, foot_x=0.54, foot_y=-0.18)

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", required=True)
    common.render_all(CFG, os.path.abspath(parser.parse_args(argv).outdir))
