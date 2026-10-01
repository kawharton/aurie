"""Teardrop Aurie — v1 candidate (rapid body-library phase, rig OPEN).

Identity: bottom-heavy with a long, softly narrowing upper body — the
continuous taper Pear deliberately avoids. NOT a pointed droplet: the
crown stays a rounded cap (taper bounded at 0.68), both ends rounded.
Distinct from Egg (far stronger upper narrowing) and Pear (no hip
peak; one smooth continuous flow). Shared pipeline: aurie_body_common.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aurie_body_common as common  # noqa: E402

TEAR_STRETCH = 1.08
BODY_WIDEN = 0.95
BELLY_FULL = 0.16           # heavy rounded base mass
UPPER_NARROW = 0.32         # long soft narrowing (low ease 1.3 —
                            # deliberately continuous for Teardrop)
FLATTEN = 0.02


def teardrop_width(t):
    u_bot, u_top = (1 - t) / 2, (1 + t) / 2
    return (BODY_WIDEN * (1 + BELLY_FULL * u_bot ** 1.2)
            * (1 - UPPER_NARROW * u_top ** 1.3))


CFG = dict(name="teardrop", stretch=TEAR_STRETCH,
           width_fn=teardrop_width, flatten=FLATTEN)

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", required=True)
    common.render_all(CFG, os.path.abspath(parser.parse_args(argv).outdir))
