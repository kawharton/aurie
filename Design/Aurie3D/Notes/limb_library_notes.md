# AURIE LAUNCH LIMB LIBRARY

## BODY x LIMB COMPATIBILITY PASS (2026-08-17)

Active set tested: arms `arm_00/01/02`, legs `leg_00/01/02/03`
(leg_04 removed). 15 bodies x 6 renders = 90 frames at 64 samples
(review quality, family standard is 128), scratchpad `matrix/`, sheets
`preview_compat_arms_{1,2}.png`, `preview_compat_legs_{1,2}.png`,
`preview_compat_34_checks.png`. Harness
`scratchpad/body_limb_matrix.py` adapts both body-script interfaces
(standalone module constants vs `aurie_body_common` CFG) and derives a
per-body limb scale from the measured silhouette
(`0.85 * sqrt(h*w / round h*w)`, clamped 0.78–1.15) with Round/Tall/Wide
keeping their approved multipliers.

TWO RIG-METADATA FIXES FOUND (no body or style redesign):
1. `leg_02` gained a `stance` kwarg (default 1.62). The fixed 1.62x
   multiplier is right on Round's narrow foot anchor but on bodies whose
   approved anchor is already wide (wide/squircle 0.54, star 0.50,
   beanbag 0.46) it threw the feet past the silhouette edge and the
   character read as crouching on all fours. Callers clamp with
   `min(1.62, 0.62 * half_width / foot_x)`. This turned wide+chibi and
   squircle+chibi from BAD to ACCEPTABLE.
2. Arm scale needs a width bias on short-but-wide bodies: the
   sqrt(h*w) rule scaled beanbag's arms DOWN (short) while its girth is
   the largest in the library, so the flipper vanished. Boosts:
   beanbag 1.20x, dumpling 1.12x. Beanbag+flipper BAD -> ACCEPTABLE.

SYSTEMIC FINDING: `leg_03` Splayed Feet is the weakest style in the
library — three of four independent blind reviewers called it
duck-footed on nearly every body, and it is the only BAD left (star).
The problem is the style, not the bodies.

WEAKEST BODIES: star (its own lobes read as limbs, so arms are
ambiguous in most styles) and, mildly, squircle (flat base fights
standing legs). Both survive with restrictions. Bean works, but its
near-side arm is occluded in 3/4 on the cave side.

---


## CURRENT ARM/LEG STATUS (2026-08-17) — supersedes everything below

ACTIVE ARMS (3 of the launch 5, all on ROUND V6 as the design body):
- `arm_00` Rounded Flipper — **APPROVED**, do not redesign. No hand.
  Rescaled to `K = 0.75` of the sculpted size on user instruction
  (2026-08-17): K multiplies the path AND the radii together, so the
  flipper shrinks proportionally rather than merely shortening, and the
  root stays on the approved anchor while only the tip moves inward.
- `arm_01` Tiny Hands — oversized plush hand, 3 extended digits +
  thumb. Palm `rp 0.190 m`, `reach 1.10`, forearm r
  `[0.10, 0.092, 0.088] m`.
- `arm_02` Noodle Arms — long dangling J-curve, forearm slimmed three
  times (0.135 → 0.124 → 0.115 → **r `[0.086, 0.078, 0.075, 0.075] m`**,
  a straight 25% cut on user instruction, ~36% under the first sculpted
  pass), hand `rp 0.170 m`, `reach 1.05`. The distal radii do not taper,
  so the hand grows out of the noodle instead of ballooning off a stick.
  At this diameter the hand is much wider than the arm — deliberate, but
  the "slender arm, plush hand" contrast is now the style's signature; if
  it ever reads lollipop-ish, shrink `rp`, do not re-thicken the arm.

THUMB (both hand styles, 2026-08-17 — redesigned): an **opposable stub
of the palm**, not a fourth finger. Rules that made it read, each one
learned by getting it wrong first:
- Root mid-palm on the **outer** flank (`c + 0.64 rp ux`, ux = away
  from the torso), well proximal of the finger knuckles. On the inner
  flank it hid behind the palm in 3/4 and grazed the body; rooted any
  higher it was swallowed by the wrist-bridge blob.
- Travels mostly **sideways** (`normalize(0.90 ux + 0.14 f + 0.30 n)`,
  n = toward the viewer) so it opposes the fingers instead of
  paralleling them. A strong forward lean foreshortens it to nothing.
- Built as a **dense chain of soft kernels** (d 0.00/0.31/0.62/0.95 rp,
  r 0.44/0.39/0.34/0.28 rp, hardness 1.2–1.3) with a small f-offset per
  step for the upturn. Three widely spaced steep kernels waisted at the
  palm and balled up at the tip — the "bead on a neck" read that two
  independent blind reviewers caught.
- Shallow web: the thumb's valley is softer than the finger clefts, so
  the thumb belongs to the palm.
- The wrist bridge sits ON the wrist (not distal of it) so it fills the
  arm join without inflating the palm flank.
- Noodle hand grown to `rp 0.170 m`: at 0.148 the palm was too small
  against that forearm for any thumb to register, which is why the two
  styles first looked like different hand designs.

REMOVED / HELD OUT — never use these to fill the two free slots:
- `arm_03` Soft Bent Arms — REJECTED by the user; deleted earlier.
- Wave (`_wave_held_out`) — the replacement concept built for that
  slot; never user-reviewed, held out of the active set, hand is still
  the old smooth end.
- Belly Paws (`_belly_paws_removed`) — REMOVED from the active set by
  user direction; do not refine, do not include in arm sheets.
- `arm_03`/`arm_04` are therefore FREE IDs for the two new arm
  concepts still needed to reach five.

LEGS — **only `leg_01` Bounce Feet is APPROVED / FROZEN** (user,
2026-08-17). leg_00, leg_02, leg_03 and leg_04 are all still under
review; do NOT treat them as approved.

THICKENING PASS (2026-08-17): all four unapproved styles read as BIRD
legs — thin ankles, narrow tapered feet, delicate stems under a heavy
body. Fixed by a large proportion correction, not small nudges:
- `leg_00` column 0.125 → **0.185 m**, foot → `(0.250, 0.305, 0.190) m`.
- `leg_02` stubs 0.155 → **0.205 m**, feet → `(0.285, 0.305, 0.190) m`,
  yaw 24° → 11°, stronger A-frame (top tucked in, foot kicked out).
- `leg_03` half-height 0.100 → **0.190 m**, blunt outer end, shorter.
- `leg_04` ankle 0.105 → **0.160 m**, boot `(0.250, 0.300, 0.200) m`,
  bigger forward toe; ankle deliberately slimmer than the boot so the
  silhouette has a CUFF STEP (that step is what separates it from
  leg_00, whose column flows straight into its foot).
Two structural lessons: (1) a swept leg must END INSIDE the foot mass,
otherwise its rounded cap pokes out below as a pointed nub and a waist
forms at the join — that combination is what read as an ankle; (2) each
style's own `LEG_BODY_LIFT` has to grow with the foot, or the new volume
is simply swallowed by Round's underside.

Earlier silhouette rebuild of `leg_01` / `leg_02` / `leg_03`:
- `leg_01` Bounce Feet — oversized ball feet `(0.305, 0.335, 0.285) m`,
  light flatten 0.18, set forward `fy − 0.14`, no visible leg.
- `leg_02` Chibi Stance — stance `1.72x` the anchor, thick short stubs
  `r 0.155→0.145 m` reaching up to `0.335 m` (a wide stance needs TALL
  stubs: a round body's underside rises with |x|, so short + wide left
  the feet floating), feet `(0.215, 0.245, 0.105) m` yawed 24°.
- `leg_03` Splayed Feet — swept (not ellipsoid) tapered flat pods,
  inner-rear to outer-front diagonal, outer tip raised so the splay
  also reads in a straight-on front view.
Foot/leg PLACEMENT (`FOOT_X` / `FOOT_Y`) is complete and untouched; only
each style's own `LEG_BODY_LIFT` was adapted, which is what the dict is
for. At lift 0.0 the ball feet and flat pods were both swallowed whole
by Round's underside.

SILHOUETTE TEST (labels removed, alpha-only, after thickening):
`leg_02` (widest A-frame) and `leg_03` (broad pods spanning outward) are
unmistakable. `leg_00`, `leg_01` and `leg_04` are all "chunky pair under
the body" and the closest pair is **leg_00 vs leg_04** — thickening
leg_00 moved it toward the others, so distinctness got *worse* as mass
went up. Still open; reported, not silently fixed.

Blind review (3 viewers, no project context): none read as bird-legged
after the pass; two independently flagged the leg_00/leg_02 cap-nub and
waist, which was then fixed before presenting. One viewer reported
leg_02's feet as asymmetric — a rendered-alpha mirror test shows 0 px
mismatch (max alpha delta 12/255, i.e. antialiasing), so that was the
key light from −x, not geometry. Note for future probes: comparing mesh
vertices right after building is unreliable because `matrix_world` is
lazily evaluated and Blender renames duplicate objects; measure the
rendered alpha instead.

HAND LANGUAGE (learned the hard way — three rejected generations):
one continuous implicit surface (Gaussian blobby field + marching
tetrahedra), never primitives glued together. Each digit is a
3-element chain (knuckle → mid → tip) with a steep falloff so the
valleys stay deep, on a soft-falloff palm/wrist so the whole thing is
one skin. Grooves that only *shade* disappear at app scale — the digit
separations must cut the SILHOUETTE, hence the wide knuckle fan
(±0.74 rp) and splayed tips (0.33 rp). The wrist bridge element is
clamped to the incoming arm radius (`r_arm`); when it was smaller the
hand looked pinched onto the arm (measured 0.86× on the slimmed
noodle). Blind reviewers reliably count 3 digits + thumb at close-up
and read "hand" down to ~240 px character height; below ~160 px the
digits merge into the palm mass — that is a scale limit, not a
geometry defect.

EVIDENCE (current): `preview_round_active_arms.png` (active three on
Round, front + 3/4), `preview_active_hand_detail.png` (true close-up
renders of both hands), `preview_active_arms_app_scale.png` (240 px /
160 px readability gate). Sources: scratchpad `armpass4/`.

---

## HISTORICAL — the five-style copy pass (2026-08-17)

STATUS: 5 arm + 5 leg styles COPIED from the user-supplied
`References/limbs_to_copy.png` ("Aurie Limb Options" — the visual
source of truth). The earlier self-designed roster is superseded and
replaced in `Scripts/aurie_limb_styles.py`. Awaiting user approval;
NOT propagated beyond the three rig representatives (Round/Tall/Wide).
Bodies, faces, tufts, materials, approved anchors: untouched.

ARCHITECTURE: independent components (arm_XX x leg_YY = 25 combos);
builders place one side at the APPROVED per-body anchors + scale
multiplier (round 0.85 / tall 1.00 / wide 1.05). NEW: 3D rounded-tube
sweeps, and belly-wrapping arm styles take the body's front-surface
function — every path point rides y = surf(x,z) + clearance, so
wrapped arms rest against the actual belly of ANY body (first
implementation sank into the bulge; fixed with surface-riding paths).
Legs each compute their own z so soles land on the floor; `fcx`
stance-center override supports asymmetric bodies (Bean).

ARMS (ref panel 1)         LEGS (ref panel 2)
- arm_00 Rounded Flipper   - leg_00 Short Standing Legs
- arm_01 Tiny Hands        - leg_01 Bounce Feet
- arm_02 Noodle Arms       - leg_02 Chibi Stance
- arm_03 Soft Bent Arms    - leg_03 Splayed Feet
- arm_04 Belly Paws        - leg_04 Tiny Boot Feet

EVIDENCE: `preview_arm_catalog.png` (5 arms x Round/Tall/Wide, legs
pinned to leg_00), `preview_leg_catalog.png` (5 legs x 3 bodies, arms
pinned to arm_00), `preview_limb_styles_all.png` (geometry sheet),
`preview_limb_diag34.png` (5 mixed-combo 3/4s). Sources: scratchpad
limbcat/ (not canonical).

NEXT (pending approval): propagate across all 15 bodies via anchor
metadata; canonical limb-asset passes + registration verifiers.
