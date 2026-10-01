# WIDE — BODY FROZEN AT V2 (Rig C checkpoint, 2026-08-16)

**The Wide v2 BODY and face/render architecture are the canonical Wide
/ Rig C baseline.** `BodyType wide → Rig C` (rig derived from BodyType;
no persisted rig field; enum ordering/IDs untouched). The renders on
disk ARE v2, produced by the current `Scripts/build_wide_aurie.py`.
Round v6 (Rig A) and the Tall v14 body (Rig B) remain separately
frozen. NOTE: Round V2 (in the Round notes) is the HISTORICAL
accidental-wide starting reference; the canonical Wide body is WIDE V2.

## Frozen / approved — body

`WIDE_SQUASH 0.925`, `BODY_WIDEN 1.12`, `PEAR_AMOUNT 0.10`,
`SIDE_FILL 0.25`, `BOTTOM_FLATTEN 0.02`, `BOTTOM_FLAT_START -0.5`,
`BODY_LIFT 0.917` — body ≈ 1.83 × 2.33 R, **H/W ≈ 0.79** (Round 0.96,
Tall 1.32). Approved because it remains clearly Wide and distinct from
Round/Tall, has a more intentional dome than v1, avoids v1's
squashed-pillow read, keeps rounded side curvature and a soft
lower-body/base transition, and stays volumetric at 3/4. The sculpted
profile implementation (`wide_width` = WIDEN × pear × side-fill) and
the Wide tuning-block organization are part of the frozen architecture.

## Frozen / approved — face, tuft, framing, look

- Surface-conforming face system (Tall v10/v11 architecture): black eye
  patches `EYE_RX/RZ 0.112/0.156` at `EYE_X 0.31` / `EYE_Z 1.17` with
  the controlled glossy treatment (charcoal rim: tone (0.075, 0.078,
  0.095), start 0.55, mix 0.30; roughness 0.42, spec 0.10); gray sheen
  0.032×0.085 at (+0.055, −0.015), emissive (0.62, 0.65, 0.70)@0.9,
  alpha 0.60/exp 1.3; catchlights 0.036×0.047 at (−0.034, +0.050) and
  0.0145×0.018 at (0.024, −0.034); conforming ribbon mouth (half-w
  0.09, drop 0.045, z 0.89, thickness 0.011); conforming blush
  0.22×0.095 at (±0.58, 0.90), falloff 0.95/1.5/0.45 (preview-only).
  EPSILON POLICY: FACE_SURF_EPS 0.003 / sheen +0.001 / catchlights
  +0.002 — z-fighting only, nothing proud or floating; features
  foreshorten/occlude naturally when rotated.
- Tuft (separate canonical asset, family design, NOT widened):
  MID (0.15, 0.15, 0.20) z 1.87; SIDE (0.125, 0.125, 0.165) x 0.145,
  z (1.83, 1.81), tilt (22, 30).
- WIDTH-LIMITED framing (Rig C architecture): `FRAME_FILL_W 0.78`,
  camera ortho = max(height/0.90, width/FILL_W) → ortho_scale 3.50192,
  cam z 1.0185; verification checks WIDTH fraction 74–84%.
- Material #97C9EF matte vinyl, lights 300/90/150 W, Standard view
  transform, 1024×1024 registered transparent passes — identical family
  look; body-type differences come from shape only.

## LIMBS — PROTOTYPE ONLY (explicitly NOT the final Wide limbs)

`limbs_c_00` is the **Rig C / Tiny Stubby PROTOTYPE baseline**. Its
only purposes: prove Rig C limb attachment, establish rough scale,
verify registration, and allow complete-character body review. Future
Rig C limb sets (`limbs_c_01`, `limbs_c_02`, …) may legitimately change
every arm value (shape/size/X/Y/Z/tilt/embed/protrusion) and every foot
value (shape/scale/stance/depth/placement/flattening). Do NOT treat
these as immutable Rig C constants:

- Prototype arms: `ARM_SCALE (0.17, 0.14, 0.31)`, `ARM_X 1.10`,
  `ARM_Y -0.10`, `ARM_Z 0.65`, `ARM_TILT_DEG -52` (~45–50% visible).
- Prototype feet: `FOOT_SCALE (0.26, 0.20, 0.135)`, `FOOT_X 0.46`,
  `FOOT_Y -0.05`, `FOOT_Z 0.102`, flatten 0.24 / start −0.5.

ARCHITECTURE (same principle as Tall): body/rig-specific limb-set
artwork + limb-set-specific tuning — the body is frozen, the individual
limb designs are not. Rig C limb-set production is an OPEN task.

## Verification fingerprints (v2 checkpoint)

ALL CHECKS PASSED read-only against the untouched renders: width
78.1% of canvas, centered x=512.0, bbox (112, 204, 912, 811), alpha
counts preview 322765 / body 297091 / tuft 14897 / limbs 46857 /
body+tuft 305033, ≤2 px registration outside, soles at the floor.

## Approved visual record (development evidence, not necessarily Git)

`preview_bodies_round_tall_wide_v2.png` (family trio),
`preview_wide_v1_vs_v2.png`, `preview_wide_v1_vs_v2_body_only.png`,
`preview_wide_v2_diagnostic_34.png` (3/4),
`preview_round_v2_vs_wide_v1.png` (accidental-wide reference pair).

## v2 changes over v1 (HISTORICAL record)

Wide v1 established Rig C and the correct broad family but read
slightly like a squashed pillow. v2 refined the body only: squash
0.89 → 0.925, pear 0.12 → 0.10, side-fill 0.28 → 0.25, bottom flatten
0.03 → 0.02, width unchanged at 1.12; lift 0.873 → 0.917 (derived).
Derived-only anchor updates: face group +0.05 as one unit, tuft tracks
the taller dome, arms at the same normalized flank (Z 0.65, X 1.10).
No internal body variants were needed. The v1 record below is
HISTORICAL.

## Design approach

Wide v1 is a deliberate Rig C redesign starting from the numerical clue
of Round V2 (the accidental wide: widen 1.07 / squash 0.91 / flatten
0.06 — a uniformly stretched sphere with an over-flat base and
unadapted limbs). Wide v1 differs on purpose:

- SCULPTED width, not X-stretch: the Tall-proven profile machinery
  `w(t) = WIDEN * pear(t) * (1 + SIDE_FILL * t^2 (1 - t^2))` with Wide
  values — SIDE_FILL 0.28 gives broad soft flanks, PEAR 0.12 a gently
  full lower body.
- SUBTLE grounding: flatten 0.03 (half of V2's pancake-ish 0.06) so the
  side-to-bottom transitions stay rounded and plush.
- The face and limbs are designed FOR the width (V2 never adapted them).

Body ≈ 1.75 R tall × 2.34 R wide → **H/W ≈ 0.75** (Round v6 ≈ 0.96,
Tall v14 ≈ 1.32) — ~22% below Round, inside the 15–25% target and
matching the reference WIDE panel. Dimensional at 3/4 (not a disc).

Face: full Tall v10/v11 surface-conforming architecture (eyes with
charcoal rim gradient, gray sheen band, two catchlights, ribbon mouth,
diffuse blush; epsilon policy FACE_SURF_EPS 0.003 / sheen +0.001 /
catchlights +0.002) with WIDE-SPECIFIC anchors: face slightly above the
body center (~63% up) so it dominates the broad body; eyes wider-set
than Tall (matches the family's relative spacing on the broad face).

## v1 tuning values (complete — HISTORICAL, superseded by v2 above)

Body: `WIDE_SQUASH 0.89`, `BODY_WIDEN 1.12`, `PEAR_AMOUNT 0.12`,
`SIDE_FILL 0.28`, `BOTTOM_FLATTEN 0.03`, `BOTTOM_FLAT_START -0.5`,
`BODY_LIFT 0.873` (bottom at +0.010).

Tuft (family design, NOT widened): MID (0.15, 0.15, 0.20) z 1.79;
SIDE (0.125, 0.125, 0.165) x 0.145, z (1.75, 1.73), tilt (22, 30).

Face: `EYE_RX/RZ 0.112/0.156` (same size as Round/Tall), `EYE_X 0.31`,
`EYE_Z 1.12`; sheen/catchlight offsets and eye-shader constants
identical to Tall v14; `MOUTH_Z 0.84` (family 0.28 R eye→mouth gap),
half-w 0.09, drop 0.045, bevel 0.011; cheeks `CHEEK_RX/RZ 0.22/0.095`
at (±0.58, 0.85) — widest blush of the family for the broadest face.

PROTOTYPE Rig C limbs (Tiny Stubby baseline — NOT final Wide limbs,
same policy as Tall's prototype set): arms (0.17, 0.14, 0.31), X 1.11,
Y −0.10, Z 0.62 (clearly below the face), tilt −52 (~45–50% of the bean
visible); feet (0.26, 0.20, 0.135), X 0.46, Y −0.05 (centered depth),
Z 0.102, bottom flatten 0.24 / start −0.5. Future sets: limbs_c_01, …

Framing — WIDTH-limited (new for the family): `FRAME_FILL_W 0.78`
(character width as canvas fraction; the camera takes
max(height/0.90, width/FRAME_FILL_W)). ortho_scale 3.52757, cam z
0.9785. Verification checks WIDTH fraction 74–84% (not height).

Render: samples 128, Standard view transform, body #97C9EF, lights
300/90/150 W — identical family look; differences come from shape only.

v1 verification fingerprints: ALL CHECKS PASSED — width 78.1%, centered
x=512.0, bbox (112, 218, 912, 797), alpha counts preview 308174 / body
283901 / tuft 14688 / limbs 46141 / body+tuft 291668, ≤1 px outside.

## Files

- `Scripts/build_wide_aurie.py`, `Scripts/verify_wide_renders.py`
- `Renders/body_02_wide.png` (BODY ONLY, canonical)
- `Renders/tuft_00_wide.png` (TUFT ONLY, Wide frame)
- `Renders/limbs_c_00.png` (Rig C prototype arms+feet)
- `Renders/body_02_wide_with_tuft.png` (convenience)
- `Previews/preview_wide_full.png`, `Source/wide_aurie_master.blend`
- Comparisons: `Previews/preview_bodies_round_tall_wide.png` (three
  families, common world scale), `Previews/preview_round_v2_vs_wide_v1.png`
- Diagnostic (temporary): `Previews/preview_wide_v1_diagnostic_34.png`

## Re-run

```
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --factory-startup --python-exit-code 1 \
  --python Design/Aurie3D/Scripts/build_wide_aurie.py -- \
  --outdir "$(pwd)/Design/Aurie3D"
python3 Design/Aurie3D/Scripts/verify_wide_renders.py
```

## Process rules (inherited)

Anchors recompute at NORMALIZED body positions on any proportion
change; face artwork always conforms to the surface (epsilons are
z-fighting-only); feet originate under the body near mid-depth; arms
side-mounted, below the face, never ear-like; limb sets are
body/rig-specific artwork + per-set tuning.
