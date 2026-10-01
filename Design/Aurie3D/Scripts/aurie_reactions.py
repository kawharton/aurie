"""Aurie reaction poses — the ART side of the reaction system.

A reaction is a SHORT, REUSABLE override: it borrows the face and nudges
the body, then hands both back to whatever the Aurie's saved base
expression was. Nothing here is an Aurie's personality; base expressions
live in `aurie_face_expressions.EXPRESSIONS` and are persisted by the
app, while these are temporary states that are never saved.

Every pose value is BODY-RELATIVE so one library serves every body:
    dy      vertical offset in units of body HEIGHT (0.10 = a tenth up)
    sx, sz  squash/stretch multipliers about the feet (sx*sz ~ 1 keeps
            volume plausible; the pivot is the floor, not the centre)
    tilt    roll in degrees, deliberately small (plush, not rigid)
    arms    arm lift in degrees about each arm's own anchor
    face    which face to show: any of the ten base expressions or one of
            the three reaction-only faces (dizzy / yawn / calm)
    blink   lid override for that frame
`face=None` means "keep the Aurie's saved base expression", which is what
makes the first and last frame of every reaction identical to rest.

These keyframes are the visual spec for the SpriteKit implementation:
AurieNode already owns squash, hop, tilt, arm and eye actions plus a
duration-based `setExpression`, so each pose maps onto actions that
exist rather than needing a new animation framework. Timings live with
the app (REACTIONS[*]["seconds"] is the intended total, not a hardcode).
"""

# priority: higher wins. Matches the app's interruption rules -
# major events beat taps, taps beat idle, blink yields to everything.
P_HIGH, P_MED, P_LOW = 30, 20, 10

REACTIONS = {
    "blink": dict(
        label="Blink", priority=P_LOW, seconds=0.30, idle=True,
        note="face-only; never moves the body and never interrupts",
        frames=[
            dict(tag="open", face=None, blink=0.0),
            dict(tag="closing", face=None, blink=0.55),
            dict(tag="closed", face=None, blink=1.0),
            dict(tag="reopening", face=None, blink=0.30),
        ]),
    "startled": dict(
        label="Startled", priority=P_HIGH, seconds=0.55, idle=False,
        note="pops up and out; also the entry state for the shake flow",
        frames=[
            dict(tag="base", face=None),
            dict(tag="pop", face="surprised", dy=0.055, sx=0.94, sz=1.08,
                 arms=22.0),
            dict(tag="settle", face="surprised", dy=0.010, sx=1.05,
                 sz=0.96, arms=10.0),
            dict(tag="return", face=None),
        ]),
    "dizzy": dict(
        label="Dizzy / Shaken", priority=P_HIGH, seconds=1.60, idle=False,
        note="cute-dazed hold with a wobble, then a recovery squint",
        frames=[
            dict(tag="base", face=None),
            dict(tag="startled", face="surprised", dy=0.050, sx=0.95,
                 sz=1.07, arms=20.0),
            dict(tag="dizzy", face="dizzy", tilt=6.0, sx=1.04, sz=0.97,
                 arms=6.0),
            dict(tag="wobble", face="dizzy", tilt=-5.0, sx=1.03, sz=0.98,
                 arms=-4.0),
            dict(tag="recover", face="dizzy", blink=0.80, sx=1.02,
                 sz=0.99),
            dict(tag="return", face=None),
        ]),
    "happy_bounce": dict(
        label="Happy Bounce", priority=P_MED, seconds=0.60, idle=False,
        note="the common tap reaction - small on purpose, so Excited Hop "
             "still reads as special",
        frames=[
            dict(tag="base", face=None),
            dict(tag="anticipate", face="happy", dy=-0.012, sx=1.06,
                 sz=0.94),
            dict(tag="peak", face="happy", dy=0.095, sx=0.96, sz=1.06,
                 arms=14.0),
            dict(tag="land", face="happy", dy=0.0, sx=1.07, sz=0.93,
                 arms=4.0),
            dict(tag="return", face=None),
        ]),
    "excited_hop": dict(
        label="Excited Hop", priority=P_HIGH, seconds=1.10, idle=False,
        note="celebration only (hatch, Starlight, Wonder reveal); ~2.5x "
             "the lift of Happy Bounce plus a second smaller bounce",
        frames=[
            dict(tag="base", face=None),
            dict(tag="crouch", face="excited", dy=-0.030, sx=1.10,
                 sz=0.90),
            dict(tag="launch", face="excited", dy=0.150, sx=0.93,
                 sz=1.10, arms=26.0),
            dict(tag="peak", face="delighted", dy=0.240, sx=0.94,
                 sz=1.08, arms=30.0),
            dict(tag="land", face="delighted", dy=0.0, sx=1.12, sz=0.89,
                 arms=8.0),
            dict(tag="rebound", face="delighted", dy=0.060, sx=0.98,
                 sz=1.03, arms=14.0),
            dict(tag="return", face=None),
        ]),
    "curious_look": dict(
        label="Curious Look", priority=P_MED, seconds=1.30, idle=True,
        note="whole-body lean stands in for a head turn (no neck); gaze "
             "leads the tilt",
        frames=[
            dict(tag="base", face=None),
            dict(tag="notice", face="curious", tilt=7.0, dy=0.008,
                 sx=0.99, sz=1.01),
            dict(tag="hold", face="curious", tilt=8.0, arms=-5.0),
            dict(tag="return", face=None),
        ]),
    "sleepy_yawn": dict(
        label="Sleepy / Yawn", priority=P_LOW, seconds=1.80, idle=True,
        note="lids first, then a small oval yawn, then a tiny stretch",
        frames=[
            dict(tag="base", face=None),
            dict(tag="lids", face="sleepy", sx=1.02, sz=0.98),
            dict(tag="yawn", face="yawn", dy=-0.018, sx=1.04, sz=0.96),
            dict(tag="stretch", face="sleepy", dy=0.030, sx=0.97,
                 sz=1.05, arms=12.0),
            dict(tag="return", face=None),
        ]),
    "calm_settle": dict(
        label="Calm Settle", priority=P_MED, seconds=2.40, idle=True,
        note="slowest reaction in the set; a breath, not a bounce",
        frames=[
            dict(tag="base", face=None),
            dict(tag="soften", face="calm", dy=-0.020, sx=1.03, sz=0.97,
                 arms=-8.0),
            dict(tag="breathe", face="calm", dy=-0.006, sx=0.99,
                 sz=1.02, arms=-6.0),
            dict(tag="rest", face="calm", dy=-0.016, sx=1.02, sz=0.98,
                 arms=-8.0),
            dict(tag="return", face=None),
        ]),
}

ORDER = ["blink", "dizzy", "happy_bounce", "startled", "curious_look",
         "sleepy_yawn", "calm_settle", "excited_hop"]

# The Wonderglobe shake is assembled FROM the library above, not written
# as a bespoke character animation: each step names an existing reaction.
WONDERGLOBE = [
    ("startled", "pop"),          # shake detected
    ("dizzy", "dizzy"),           # shaking continues
    ("dizzy", "recover"),         # particles swirl, Aurie recovers
    ("curious_look", "hold"),     # looks toward the globe
    ("excited_hop", "peak"),      # Today's Wonder appears
    ("excited_hop", "return"),    # settles back to its base expression
]


def frame(reaction_id, tag):
    for f in REACTIONS[reaction_id]["frames"]:
        if f["tag"] == tag:
            return f
    raise KeyError(f"{reaction_id} has no frame {tag!r}")
