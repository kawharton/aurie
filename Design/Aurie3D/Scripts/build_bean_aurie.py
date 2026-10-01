"""Bean Aurie — v11 APPROVED body (rig OPEN).

The final kidney bean, matched to References/bean_reference.png through
the v4-v11 body-only exploration: a curved centerline (balanced C-bow),
one long smooth convex OUTER-left arc (fuller via lateral x-warp + a
broad outer swell), and a deep soft one-sided CAVE on the inner-right
(cos^2 angular window, 0.42 deep x 78 deg wide — unmistakable at
thumbnail size, plush walls, no notch) with rounded lobes above and
below it. Blunt capped ends (localized u^6 fullness), slender overall
proportion via a uniform end-stage horizontal compression (post_xy
0.835, H/W ~ 1.44). v1-v3 (bow-only attempts, rejected as tilted eggs)
and the v4-v10 exploration steps are HISTORICAL.

Because the body is strongly asymmetric, the arms use per-side anchors
computed from each side's own signed flank (the right arm nestles
below the cave on the lower lobe; the left emerges from the full outer
arc), and eye spacing derives from the left/right flank average.
Shared family pipeline: aurie_body_common.
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aurie_body_common as common  # noqa: E402

BEAN_STRETCH = 1.14
BODY_WIDEN = 0.94
BELLY_FULL = 0.13
BEAN_LEAN = 0.30            # balanced C-bow: shift = LEAN*(t^2 - 1/3)
BEAN_RECENTER = 0.25        # centers the asymmetric silhouette bbox
                            # (long outer-left arm arc vs shorter
                            # cave-side right extent)
BEAN_ASYM = 0.07            # fuller convex (-x) / tucked concave (+x)
ASYM_SOFT = 0.5
DENT, DENT_SIGMA = 0.42, 78.0   # deep soft inner cave (v10->v11 depth)
PHI0 = math.radians(-4)
LOBE_UP = (math.radians(66), math.radians(52), 0.04)
LOBE_LO = (math.radians(-52), math.radians(52), 0.04)
OUTER_FULL = 0.05           # one long plush outer arc
TOP_CAP, BOT_CAP, CAP_POW = 0.32, 0.26, 6.0  # blunt rounded ends
POST_XY = 0.835             # slender kidney proportion (H/W ~ 1.44)
SPHI_Y = 0.45               # depth coupling of the cave — reduced at
                            # character integration (0.65 -> 0.45) so
                            # the right-front surface recedes less and
                            # the face stays readable; the approved
                            # v11 x-z SILHOUETTE is unaffected
FLATTEN = 0.02
LIFT = (1.0 - FLATTEN) * BEAN_STRETCH + 0.010


def bean_width(t):
    u_bot, u_top = (1 - t) / 2, (1 + t) / 2
    return (BODY_WIDEN * (1 + BELLY_FULL * u_bot ** 1.3)
            * (1 + TOP_CAP * u_top ** CAP_POW)
            * (1 + BOT_CAP * u_bot ** CAP_POW))


def bean_shift(z_world):
    t = max(-1.0, min(1.0, (z_world - LIFT) / BEAN_STRETCH))
    return BEAN_LEAN * (t * t - 1.0 / 3.0) + BEAN_RECENTER


def bean_warp(x):
    return x * (1.0 - BEAN_ASYM * math.tanh(x / ASYM_SOFT))


def bean_warp_inv(xw):
    x = xw
    for _ in range(3):
        th = math.tanh(x / ASYM_SOFT)
        f = x * (1.0 - BEAN_ASYM * th) - xw
        df = 1.0 - BEAN_ASYM * (th + x * (1.0 - th * th) / ASYM_SOFT)
        x -= f / df
    return x


def _win(phi, center, sigma):
    d = abs(phi - center)
    d = min(d, 2 * math.pi - d)
    if d >= sigma:
        return 0.0
    return math.cos(math.pi * 0.5 * d / sigma) ** 2


def bean_sphi(phi):
    return (1.0
            - DENT * _win(phi, PHI0, math.radians(DENT_SIGMA))
            + LOBE_UP[2] * _win(phi, LOBE_UP[0], LOBE_UP[1])
            + LOBE_LO[2] * _win(phi, LOBE_LO[0], LOBE_LO[1])
            + OUTER_FULL * _win(phi, math.pi, math.radians(95)))


def flank_signed(z, side):
    """World-x of the silhouette on one side at height z (approx)."""
    dz = z - LIFT
    t = max(-1.0, min(1.0, dz / BEAN_STRETCH))
    h = math.sqrt(max(0.0, 1.0 - t * t)) * bean_width(t)
    for _ in range(3):
        phi = math.atan2(dz, side * h)
        h = (math.sqrt(max(0.0, 1.0 - t * t)) * bean_width(t)
             * bean_sphi(phi))
    hw = h * (1.0 - side * BEAN_ASYM * math.tanh(h / ASYM_SOFT))
    return side * hw * POST_XY + bean_shift(z)


# Per-side arm anchors: left on the full outer arc, right tucked below
# the cave on the lower lobe (reference layout). 0.09 embed each.
ARM_L = (flank_signed(0.82, -1) + 0.09, 0.82)
ARM_R = (flank_signed(0.74, 1) - 0.09, 0.74)
# Eye spacing from the left/right flank average at eye height (~63%
# up) so the cave side does not squeeze the face.
_EYE_Z = 0.01 + 0.63 * (LIFT + BEAN_STRETCH - 0.01)
_EYE_X = round(0.28 * (abs(flank_signed(_EYE_Z, -1) - bean_shift(_EYE_Z))
                       + abs(flank_signed(_EYE_Z, 1)
                             - bean_shift(_EYE_Z))) / 2, 3)

CFG = dict(name="bean", stretch=BEAN_STRETCH, width_fn=bean_width,
           x_shift_w=bean_shift, x_warp=bean_warp,
           x_warp_inv=bean_warp_inv, s_phi=bean_sphi, sphi_y=SPHI_Y,
           fade_rho=0.45, post_xy=POST_XY, flatten=FLATTEN, lift=LIFT,
           eye_x=_EYE_X, arm_lr=(ARM_L, ARM_R),
           eye_frac=0.66,          # face on the UPPER LOBE, above the
                                   # cave (reference layout)
           face_dx=-0.16,          # ...and seated on the outer-arc
                                   # front mass, not the global axis
           foot_x=0.42, foot_y=-0.16,  # wider stance + forward
                                   # emergence for a clear front read
           foot_cx=(flank_signed(0.30, -1)
                    + flank_signed(0.30, 1)) / 2,
                                   # feet straddle the LOWER LOBE's
                                   # visual center (base-flank
                                   # midpoint), not the bowed axis at
                                   # floor height — keeps the stance
                                   # balanced under the asymmetric mass
           arm_x=abs(ARM_L[0]))    # framing width from the outer arm

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", required=True)
    common.render_all(CFG, os.path.abspath(parser.parse_args(argv).outdir))
