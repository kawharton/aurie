"""Chubby Star (Five-Lobed) Aurie — v2 candidate (rig OPEN).

Identity: a soft plush chubby five-lobed star — one lobe up, two side
lobes, two leg lobes. v2 reshapes the modulation so the star reads
from the OUTER SILHOUETTE with a full pillowy center: the wave has
BROAD rounded peaks and much SHALLOWER valleys (asymmetric +0.10 lobe
/ -0.045 valley with a peak-broadening exponent, vs v1's symmetric
+/-0.11 cosine), the depth coupling is nearly off (sphi_y 0.15 — no
grooves carving toward the center), and the modulation fades in
further out (fade_rho 0.60). No sharp points, no starfish carving;
thick and volumetric at 3/4. Shared pipeline: aurie_body_common.
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aurie_body_common as common  # noqa: E402

STAR_STRETCH = 1.0
BODY_WIDEN = 0.93
LOBE_FULL = 0.10            # lobe rise above the base radius
VALLEY_DIP = 0.045          # valley dip below base — v1 dipped 0.11;
                            # v2 valleys are ~60% shallower
LOBE_BROADEN = 0.6          # <1 widens the lobe peaks, narrows valleys
LIFT = 1.04                 # 2026-08-17 foot fix: raised from 0.965
                            # (floor-contact crotch) so the body rides
                            # ~0.075 higher ON its feet — the low leg
                            # lobes otherwise cover the pads at any
                            # stance/depth. Geometry unchanged; feet
                            # fill the gap, soles stay at the floor.


def star_width(t):
    return BODY_WIDEN


def star_lobes(phi):
    u = 0.5 * (1.0 + math.cos(5.0 * (phi - math.pi / 2.0)))
    return (1.0 - VALLEY_DIP) + (LOBE_FULL + VALLEY_DIP) * u ** LOBE_BROADEN


CFG = dict(name="star", stretch=STAR_STRETCH, width_fn=star_width,
           s_phi=star_lobes, flatten=0.0, lift=LIFT, eye_frac=0.62,
           sphi_y=0.15, fade_rho=0.60, mesh_res=(96, 48),
           foot_x=0.50, foot_y=-0.22)  # 2026-08-16 placement pass:
                                       # the leg lobes occupy the foot
                                       # zone and swallowed the feet;
                                       # wider stance + forward
                                       # emergence keeps them visible
                                       # under the lobes ("boots")

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", required=True)
    common.render_all(CFG, os.path.abspath(parser.parse_args(argv).outdir))
