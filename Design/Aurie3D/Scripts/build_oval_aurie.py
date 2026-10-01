"""Oval Aurie — v1 candidate (rapid phase, rig OPEN).

Identity: a clean elongated oval — a smooth continuous ellipse with NO
profile sculpting at all, which is exactly what separates it from
Tall's sculpted mascot proportions (pear + sustained side fill).
Shared pipeline: aurie_body_common.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aurie_body_common as common  # noqa: E402

OVAL_STRETCH = 1.12
BODY_WIDEN = 0.90           # constant width factor -> pure ellipsoid
FLATTEN = 0.015


def oval_width(t):
    return BODY_WIDEN


CFG = dict(name="oval", stretch=OVAL_STRETCH, width_fn=oval_width,
           flatten=FLATTEN)

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", required=True)
    common.render_all(CFG, os.path.abspath(parser.parse_args(argv).outdir))
