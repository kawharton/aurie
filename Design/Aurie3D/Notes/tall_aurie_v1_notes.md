# TALL — BODY FROZEN AT V14 (Rig B checkpoint, 2026-08-16)

**The Tall v14 BODY and face/render architecture are the canonical
Tall / Rig B baseline.** `BodyType tall → Rig B`. The renders on disk
ARE v14, produced by the current `Scripts/build_tall_aurie.py`.
Round v6 remains separately frozen and untouched.

## Frozen / approved

- Body geometry & proportions: `TALL_STRETCH 1.18`, `BODY_WIDEN 0.85`,
  `PEAR_AMOUNT 0.105`, `SIDE_FILL 0.27`, `BOTTOM_FLATTEN 0.02`,
  `BOTTOM_FLAT_START -0.5`, `BODY_LIFT 1.166` — body H/W ≈ 1.32
  (Round ≈ 0.96). The v13 major proportion reset established this
  direction; v14 is the final refinement checkpoint.
- Surface-conforming face system (v10 architecture + v11 gloss):
  - Eyes: conforming patches `EYE_RX 0.112` / `EYE_RZ 0.156` at
    `EYE_X 0.26`, `EYE_Z 1.53`; shader = deep black + charcoal rim
    gradient (`EYE_EDGE_TONE (0.075, 0.078, 0.095)`, start 0.55,
    mix 0.30; roughness 0.42, spec 0.10 — never mirror-glossy).
  - Gray sheen patch per eye: 0.032×0.085 at (+0.055, −0.015),
    emissive (0.62, 0.65, 0.70)@0.9, alpha core 0.60 / exp 1.3.
  - Catchlights: 0.036×0.047 at (−0.034, +0.050) and 0.0145×0.018 at
    (0.024, −0.034), emissive white 1.5.
  - Mouth: conforming ribbon, half-w 0.09, drop 0.045, z 1.25,
    half-thickness 0.011, 12% tip taper.
  - Blush: conforming patch 0.20×0.09 at (±0.48, 1.26), falloff
    radius 0.95 / exp 1.5 / core alpha 0.45. Preview-only.
  - EPSILON POLICY (z-fighting only, never visible lift):
    `FACE_SURF_EPS 0.003` (eye/mouth/cheek), sheen +0.001,
    catchlights +`CATCH_EXTRA_EPS 0.002`.
- Tuft: MID (0.15, 0.15, 0.20) z 2.38; SIDE (0.125, 0.125, 0.165)
  x 0.145, z (2.34, 2.32), tilt (22, 30).
- Material (#97C9EF matte vinyl), lighting 300/90/150 W, Standard view
  transform, ortho camera architecture, 1024×1024 registered passes.
  Framing: ortho_scale 3.95758, cam z 1.274.
- PLACEMENT PRINCIPLES (apply to all future Rig B limb sets):
  feet originate under the body near mid-depth (never front-mounted);
  arms side-mounted with visible 3D volume (negative-Y bias, low flank,
  down-and-out, never ear-like); all face artwork conforms to the body
  surface.

## Limbs: PROTOTYPE ONLY — explicitly NOT the final Tall limbs

The current arms/feet are the **Rig B / Tiny Stubby PROTOTYPE
baseline**. They prove Rig B limb attachment, establish rough scale,
and test registration — but Aurie will have MULTIPLE limb sets, each
created and tested independently. Future limb sets may legitimately
differ in arm scale/shape/anchors/tilt/protrusion and foot
scale/shape/stance/depth/flattening. Do NOT treat these values as
immutable Rig B constants:

- Prototype arms (Tiny Stubby): `ARM_SCALE (0.17, 0.14, 0.325)`,
  `ARM_X 0.83`, `ARM_Y -0.10`, `ARM_Z 0.82`, `ARM_TILT_DEG -55`
  (~47% of the bean visible).
- Prototype feet (Tiny Stubby): `FOOT_SCALE (0.24, 0.19, 0.132)`,
  `FOOT_X 0.34`, `FOOT_Y -0.05`, `FOOT_Z 0.100`,
  `FOOT_BOTTOM_FLATTEN 0.24` / `FOOT_FLAT_START -0.5`.

ARCHITECTURE: limb selection is **body/rig-specific limb-set artwork +
limb-set-specific tuning** — not one universal limb geometry reused
across bodies. `limbs_b_00.png` = Rig B, limb-set 00 (Tiny Stubby
prototype); future sets become `limbs_b_01`, `limbs_b_02`, … each with
their own tuning block. Rig B limb-set production is an OPEN task.

## Verification fingerprints (v14 checkpoint)

ALL CHECKS PASSED read-only against the untouched renders: height
65.3%, centered x=512.0, bbox (223, 173, 801, 842), alpha counts
preview 247984 / body 226330 / tuft 11690 / limbs 36476 / body+tuft
233167, 0 px registration outside.

## v14 changes over v13 (LIMBS ONLY — HISTORICAL record)

v13 fixed the body/limb ratio but slightly overshot: arms read
flipper/wing-like, feet read paddle/shoe-like. v14 trimmed to stubby:
arms (0.185, 0.15, 0.355) → (0.17, 0.14, 0.325), tilt −58 → −55,
ARM_X 0.87 → 0.83 (visible ~55% → ~47%); feet (0.26, 0.20, 0.125) →
(0.24, 0.19, 0.132), FOOT_Z 0.094 → 0.100. Limb pass 41340 → 36476 px
(between v12's 28508-too-small and v13's 41340-slightly-big).

Comparisons: `preview_tall_v12_v13_v14.png` (progression),
`preview_round_v6_vs_tall_v14.png`, `preview_tall_v13_vs_v14_limbs.png`
(2.2× arm/feet grid). Diagnostics: `preview_tall_v14_diagnostic_34.png`,
`preview_tall_v14_diagnostic_side.png`. v13 and earlier records below
are HISTORICAL development (v13 = the major proportion reset that
established the current body direction).

## v13 changes over v12 (deliberate rebalance — HISTORICAL)

REFERENCE FINDINGS (re-inspected before editing): the reference Tall is
a slim soft gumdrop (~1.4–1.5 H/W visually) — v12's 1.24 read as a
broad blob; and the reference limbs carry roughly TWICE v12's visual
share (arms = obvious fat beans on the flanks; Tiny Stubby feet =
rounded pads ~1/4 of body width each).

BODY (height unchanged, STRETCH 1.18 / LIFT 1.166): `BODY_WIDEN` 0.90 →
**0.85**, `PEAR_AMOUNT` 0.125 → **0.105**, `SIDE_FILL` 0.29 → **0.27**.
H/W ≈ 2.34/1.77 ≈ **1.32** (v12 1.24; Round 0.96). Soft side curvature
kept — narrower, not capsule.

ARMS: `ARM_SCALE` (0.15, 0.12, 0.30) → **(0.185, 0.15, 0.355)** (fat
stubby bean per reference); `ARM_X` 0.88 → **0.87** (embed recomputed
for the narrower flank → ~55% of the bean form visible, target 50–60%);
Y −0.10 / Z 0.82 / tilt −58 kept (side-mounted, low, down-and-out).

FEET: `FOOT_SCALE` (0.21, 0.165, 0.105) → **(0.26, 0.20, 0.125)** (~30%
of the narrower body's width each); `FOOT_X` 0.36 → **0.34** (stance
recomputed for the narrower base); `FOOT_Y` −0.05 kept (centered
depth); `FOOT_Z` **0.094** (sole rests at z ≈ 0; flatten unchanged).

Limb share of the character: limb pass 28508 → **41340 px (+45%)**
while the body pass shrank 243056 → 226519 (−7%) — limbs now ~15% of
the rendered character vs ~10% in v12.

Face: dimensions untouched (§ the narrower body made the current eye
size/spacing read correctly — no adjustment needed); all conforming
behavior intact. Tuft/materials/lighting/camera unchanged. Framing:
ortho 3.95606, cam z 1.2745.

One candidate was rendered and judged against the reference before
locking (no version churn); these are the actual final values.

Comparisons: `preview_round_v6_tall_v12_v13.png` (3-way, common world
scale), `preview_tall_v12_vs_v13.png`, `preview_tall_v13_limbs.png`
(2.5× arm/feet crops). Diagnostics: `preview_tall_v13_diagnostic_34.png`,
`preview_tall_v13_diagnostic_side.png`. v12 and earlier records below
are HISTORICAL.

## v12 changes over v11 (FEET ONLY — HISTORICAL)

DIAGNOSIS: the v10/v11 feet were centered correctly but their mass hid
behind the belly's underside curve; blanket enlargement (v11) only grew
the hidden portion. The soles already rest on the floor, so "lower the
feet" is implemented as a LOW-PROFILE pad + lower center + wider
stance + tiny forward bias — visibility now comes from placement, not
hidden scale:

- `FOOT_SCALE` (0.20, 0.165, 0.125) → **(0.21, 0.165, 0.105)** — width
  +5%, height −16% (wide+low pad; mass sits in the z-band below the
  belly edge), depth unchanged.
- `FOOT_X` 0.33 → **0.36** — the body's lower silhouette rises steeply
  toward the sides, so the wider stance exposes the outer half of each
  pad while staying close and cute.
- `FOOT_Y` −0.0 → **−0.05** — within the allowed small forward window:
  the pad's front face sits just ahead of the body's thin near-edge
  shell so the foot emerges around the underside edge instead of being
  knife-cut by it. Still essentially centered (nothing like v9's −0.41).
- `FOOT_Z` 0.094 → **0.079** — derived: the flattened sole (flatten
  treatment unchanged: 0.24 / start −0.5) rests exactly at z ≈ 0.

Front view: roughly 40% of each visible pad's height sits fully below
the body silhouette; each foot reads with a rounded emerging top, broad
middle, and flat contact edge; two clearly separate feet. Body, arms,
face (eyes/sheen/catchlights/mouth/cheeks), and tuft untouched.
Framing shifted a hair (z_bot −0.031 → −0.026 → ortho 3.94848,
cam z 1.277) — comparisons use per-version constants.

Comparisons: `preview_tall_v9_v10_v11_v12_feet.png` (front progression:
front-mounted → hidden → larger-still-hidden → centered+visible),
`preview_tall_v11_vs_v12.png` (pair + 2.5× feet crops). Diagnostics:
`preview_tall_v12_diagnostic_34.png`, `preview_tall_v12_diagnostic_side.png`.
v11 and earlier records below are HISTORICAL.

## v11 changes over v10 (eye richness + foot visibility — HISTORICAL)

EYES — v9 look restored INSIDE the conforming architecture (no proud
geometry, no mirror materials; all layers remain surface patches):
1. Eye base shader: deep black center + subtle charcoal RIM gradient
   (Object-space elliptical radius → SMOOTHERSTEP MapRange from
   EYE_EDGE_START 0.55 → rim mix EYE_EDGE_MIX 0.30 toward
   EYE_EDGE_TONE (0.075, 0.078, 0.095); built with VectorMath
   SCALE+ADD — no Mix node, version-safe). Roughness 0.42 / spec 0.10
   for a whisper of real response — still no light-blob risk.
2. Gray sheen: NEW conforming patch per eye (EYESHEEN 0.032×0.085 at
   (+0.055, −0.015) — right side of BOTH eyes, matching v9's real
   Fill-light reflection), emissive gray (0.62, 0.65, 0.70)@0.9 with
   the standard alpha falloff (core 0.60, exp 1.3) — dimmer than the
   white catchlights. Epsilon 0.004 (between eye 0.003 and catch 0.005).
3. Catchlights unchanged (two white emissive conforming patches).
Front read: deep glossy black + soft gray reflection + large white
catchlight + small dot — the v9 toy-eye character, flush on the face.

FEET — kept centered (`FOOT_Y 0.0`), enlarged so the correct depth
stays readable: `FOOT_SCALE` (0.185, 0.148, 0.122) → **(0.20, 0.165,
0.125)** (width+depth led; depth growth is symmetric around the body
center, so it does NOT re-front-mount them), `FOOT_X` 0.32 → **0.33**
(bigger pads don't crowd), `FOOT_Z` 0.092 → **0.094** (derived: the
flattened bottom still rests at z ≈ 0; flatten treatment unchanged).
Front-view occlusion ≈ 40–45% per foot (v10 was 50–60%).

MOUTH — inspected against v9: the v10 conforming ribbon already
matches the approved front appearance; no adjustment made.

Body/arms/tuft constants byte-identical to v10 (render alpha counts
differ only at denoiser fringe level, ≤0.06%). Framing unchanged.

Comparisons: `preview_tall_v9_v10_v11.png` (front trio),
`preview_tall_v9_v10_v11_eyes.png` (3× eye trio),
`preview_tall_v11_feet_depth.png` (side trio: front-mounted → hidden →
centered+enlarged). Diagnostics: `preview_tall_v11_diagnostic_34.png`,
`preview_tall_v11_diagnostic_side.png`. v10 and earlier records below
are HISTORICAL.

## v10 changes over v9 (feet depth + global face rule — HISTORICAL)

FEET (depth only — size/stance/flatten kept): `FOOT_Y` −0.41 → **0.0**
(negative = toward camera; the old value pasted the feet onto the front
belly). The feet now originate at the body's depth center; the body
naturally occludes their upper/inner portions (~50–60% per foot) and
the lower/outer pads emerge from underneath — still clearly two feet
from the front. FOOT_SCALE (0.185, 0.148, 0.122), FOOT_X 0.32 and
FOOT_Z 0.092 unchanged (no enlargement was needed after centering);
flattened bottoms still rest on the floor.

GLOBAL FACE RULE (v10, applies to all future body types): ALL face
artwork — black eyes, catchlights, mouth, blush — is built as
SURFACE-CONFORMING patches on the analytic body surface. Nothing
floats, nothing stands proud, nothing adds silhouette at any angle;
features foreshorten and occlude naturally as the body turns.
- Shared helper `make_surface_patch` (elliptical disc, 16×48 default,
  every vertex on `body_surface_y` + epsilon along local outward).
- EYES: proud glossy spheres → conforming patches (EYE_RX/EYE_RZ =
  0.112/0.156, same front footprint — ortho projects along Y).
  MATERIAL NOTE: the old mirror-gloss eye material on a flat-ish patch
  reflected the big area lights as one silver blob; the patch is now
  deep matte black (rough 0.5, spec 0.05) and the emissive catchlights
  carry the glossy sparkle. EYE_EMBED deleted.
- CATCHLIGHTS: emissive spheres → small conforming emissive patches
  (CATCH_RX/RZ 0.036/0.047 at (−0.034, +0.050); CATCH2 0.0145/0.018 at
  (0.024, −0.034)) layered on the eye patch.
- MOUTH: proud bevel curve (MOUTH_PROUD deleted) → conforming ribbon
  along the smile parabola; same width/drop/half-thickness (0.011),
  tips taper softly over the last 12% to stay rounded.
- CHEEKS: unchanged v9 conforming blush, now via the shared helper.

SURFACE-OFFSET POLICY: epsilons exist ONLY to prevent z-fighting —
`FACE_SURF_EPS 0.003 R` (eye/mouth/cheek), catchlights at
`FACE_SURF_EPS + CATCH_EXTRA_EPS 0.002` (total 0.005 R ≈ 1.3 px).
Never use offsets to lift artwork off the face.

Body/arms/tuft bit-identical to v9 (body 242334 / body+tuft 249109
alpha px unchanged; all constants untouched; framing unchanged).

FOR ROUND (when explicitly reopened — NOT done now): port the entire
v10 conforming-face treatment (eyes/catchlights/mouth/cheeks + matte
eye patch material) to replace Round's front-view-only proud geometry.

Diagnostics: `preview_tall_v10_diagnostic_34.png` (35°),
`preview_tall_v10_diagnostic_side.png` (75°),
`preview_tall_v10_feet_depth.png` (v9-vs-v10 side crops).
Comparison: `preview_tall_v9_vs_v10.png` (1:1 + face crops).
v9 and earlier records below are HISTORICAL.

## v9 changes over v8 (arm side-placement + conforming cheeks — HISTORICAL)

ARMS (placement only — design/scale/tilt/Z preserved): `ARM_Y` −0.20 →
**−0.10** (partway back: v8 was too front-mounted; negative = toward
camera) and `ARM_X` 0.85 → **0.88** (+0.03 lateral; arms sit at
side*ARM_X so larger = farther out). The rearward move raises the
front-visibility boundary; the lateral move compensates — visible
fraction of the bean stays ~45%, redistributed from the front to the
side (lateral silhouette protrusion ~0.20 → ~0.23 R). Progression:
v7 too hidden → v8 visible but front-mounted → v9 visible and
side-mounted.

CHEEKS — ROTATION-SAFE REIMPLEMENTATION. The old cheek was a flattened
sphere floated 0.10 R toward the camera (CHEEK_PROUD) — it visibly
detached in any non-front view. v9 replaces it with a surface-
conforming patch: a 16-ring × 48-segment elliptical disc whose every
vertex sits ON the analytic body surface (`body_surface_y`) plus
`CHEEK_SURF_EPS 0.003 R` along the local outward direction (pure
anti-z-fighting epsilon, ~0.8 px). CHEEK_SCALE/CHEEK_SINK/CHEEK_PROUD
were deleted; the footprint is now `CHEEK_RX 0.20` / `CHEEK_RZ 0.09`.
The falloff material is unchanged except its normalization vector
(1/RX, 0, 1/RZ) since patch-local coords are world-unit. KEY PROPERTY:
the ortho camera projects along Y, so the on-surface patch has exactly
the same front-view footprint and gradient as the old floating disc —
the approved blush look is preserved while the blush now hugs the
curvature, contributes zero silhouette, and is naturally occluded at
side angles (verified in the 35° and 75° diagnostics; the far cheek
correctly disappears near side-on).

NOTE FOR ROUND: frozen Round v6 still uses the old CHEEK_PROUD float
(cheeks are preview-only there). If Round is ever reopened or its
preview is used at non-front angles, port this v9 conforming-patch
implementation.

Body/feet/face/tuft bit-identical to v8 (body 242334 / body+tuft 249109
alpha px unchanged; framing unchanged). Limbs pass 28606 → 28586 px
(the isolated limb pass is unoccluded, so the placement change barely
alters it — the redistribution shows in the assembled preview).

Diagnostics (temporary, non-canonical):
`Previews/preview_tall_v9_diagnostic_34.png` (35°),
`Previews/preview_tall_v9_diagnostic_side.png` (75°). Comparison:
`Previews/preview_tall_v8_vs_v9.png` (1:1 + arm crops). The v8 3/4
diagnostic is kept for the before/after cheek contrast. v8 and earlier
records below are HISTORICAL.

## v8 changes over v7 (ARMS ONLY — deliberately strong — HISTORICAL)

v7's micro-adjustments read identical to v6 at normal size. ROOT CAUSE
found: with ARM_Y >= 0 the whole bean sat BEHIND the body's front
surface (camera looks down +Y; NEGATIVE y = toward camera — same
convention as the face parts), so only the outline sliver could ever
show, regardless of scale/tilt → the "side tab" read. v8:

- `ARM_Y` +0.02 → **−0.20** — THE key change: the bean's front face now
  sits proud of the local flank surface (~−0.26 there), so its lit 3D
  volume renders against the body. Still a side limb — the belly front
  bulges to y ≈ −0.94, far in front of the arm.
- `ARM_SCALE` (0.138, 0.112, 0.26) → **(0.15, 0.12, 0.30)** — visibly
  longer bean.
- `ARM_Z` 0.90 → **0.82** — anchor clearly lower (deliberate placement
  change, NOT the old normalized position).
- `ARM_TILT_DEG` −48 → **−58** — mostly down, slightly out.
- `ARM_X` 0.87 → **0.85** — with the above, ~45% of the bean's form is
  visible (attachment, shaft, rounded hanging tip; tip reaches z ≈ 0.62,
  sideways protrusion ~0.19 R at the widest).

Honest visual verdict from the comparison: v8 IS clearly different from
v7 at normal size — lower hanging arms with a readable downward tip and
lit front volume, not just a bigger bump. Limb pass 24703 → 28606 px
(+16%). Body/feet/face/tuft bit-identical (body 242334, body+tuft
249109 alpha px unchanged; framing unchanged).

DIAGNOSTIC (temporary): `Previews/preview_tall_v8_diagnostic_34.png` —
3/4 azimuth-35° render showing the arm attachment; NOT a canonical
asset. Known artifact at this angle: the cheek discs visibly float off
the face — that is the documented CHEEK_PROUD anti-occlusion trick,
valid only for the straight-on ortho camera. Ignore it when judging.

Comparison: `Previews/preview_tall_v7_vs_v8.png` (1:1 full size + 2.5x
arm close crops). v7 and earlier records below are HISTORICAL.

## v7 changes over v6 (ARMS ONLY — HISTORICAL; read identical to v6)

The v6 arms still read as side tabs: mostly the outward tip was visible.
v7 reveals the bean's vertical length instead of adding sideways bulk:

- `ARM_SCALE` (0.135, 0.11, 0.24) → **(0.138, 0.112, 0.26)** —
  length-biased (+8% vertical, near-zero added width).
- `ARM_Z` 0.935 → **0.90** — hangs slightly lower on the flank.
- `ARM_TILT_DEG` −42 → **−48** — mostly down, slightly out.
- `ARM_X` 0.90 → **0.87** — embed recomputed for the steeper hang so the
  SIDEWAYS protrusion stays at v6's ~0.15 R (no extra outward push);
  the exposed portion now includes the attachment, a visible narrowing,
  and the rounded lower tip (tip hangs to z ≈ 0.73, ~0.14 R outside the
  local surface).
- `ARM_Y` 0.02 unchanged.

Body and feet UNCHANGED — verified by identical alpha counts (body
242334, body+tuft 249109) and identical framing (ortho 3.95455, cam z
1.275 → v6/v7 previews are 1:1 comparable). Limb pass 23199 → 24703 px
(+6.5%, the added hanging length).

v7 verification fingerprints: height 65.4%, centered x=512.0, bbox
(231, 173, 793, 843), ≤1 px registration outside.

Comparisons: `Previews/preview_tall_v6_vs_v7.png` (1:1) and
`Previews/preview_round_v6_tall_v6_v7.png` (common world scale, floors
aligned). v6 and earlier records below are HISTORICAL.

## v6 changes over v5 (narrower body, arm form, foot grounding — HISTORICAL)

BODY (narrower, not taller — height deliberately unchanged at STRETCH
1.18): `BODY_WIDEN` 0.93 → **0.90**, `PEAR_AMOUNT` 0.14 → **0.125**,
`SIDE_FILL` 0.26 → **0.29**. Result: soft vertical oblong instead of the
v5 egg — H/W ≈ 2.34/1.89 ≈ **1.24** (v5 was 1.19; Round 0.96), with
slightly straighter-but-still-curved sidewalls (shoulder/belly ratio
0.885 vs v5's 0.877 — nowhere near v1's wide capsule because the body
is much narrower overall). BODY_LIFT 1.166 unchanged.

ARMS (flap fix — expose the bean's length, all three levers): scale
(0.125, 0.105, 0.225) → **(0.135, 0.11, 0.24)**; tilt −35 → **−42**
(more down than out: hanging stub, not flap); `ARM_Y` 0.05 → **0.02**
(less rearward so the lit front volume shows); `ARM_X` 0.94 → **0.90**
(less embed). Visible protrusion ~0.13 → **~0.15 R** (+15%). ARM_Z
0.935 unchanged.

FEET (shape/grounding, size kept from v5): new parameter-driven soft
bottom flatten — `FOOT_BOTTOM_FLATTEN 0.24` with `FOOT_FLAT_START −0.5`
applies the SAME quadratic-ease lift as the body grounding to the foot
mesh: flattens ~12% of the foot height progressively, top stays fully
rounded (no hard cut / pancake). `FOOT_Z` 0.092 now puts the flattened
bottom exactly at the floor (z ≈ −0.001); `FOOT_X` 0.33 → **0.32** and
`FOOT_Y` −0.43 → **−0.41** (derived: stance/tuck preserved on the
narrower base — rear still ~0.02 R inside the belly).

UNCHANGED: face (1.53/1.25/1.26 + eye size/spacing/mouth/cheeks), tuft
(2.38/2.34/2.32, scale/design), materials, lighting, camera, framing
constants (ortho 3.95455, cam z 1.275 — v5 and v6 previews are 1:1
comparable).

v6 verification fingerprints: height 65.4% (feet now rest AT the floor
instead of dipping 0.03 below → char is 0.03 R shorter in frame),
centered x=512.0, bbox (229, 173, 795, 843), alpha counts body 242334 /
tuft 11703 / limbs 23199 / body+tuft 249109, ≤2 px registration outside.

Comparisons: `Previews/preview_tall_v5_vs_v6.png` (1:1) and
`Previews/preview_round_v6_tall_v5_v6.png` (common world scale, floors
aligned). v5 and earlier records below are HISTORICAL.

## v5 changes over v4 (height increase + slight limb enlargement — HISTORICAL)

HEIGHT — `TALL_STRETCH` 1.135 → **1.18**; `BODY_LIFT` 1.122 → **1.166**
(derived: bottom stays at +0.010 R, flatten unchanged at 0.02). All four
profile-shape constants (WIDEN 0.93, PEAR 0.14, SIDE_FILL 0.26, FLATTEN
0.02) deliberately unchanged — same v3/v4 contour character, just
taller. Body H/W ≈ 2.34/1.96 ≈ **1.19** (v4 was 1.15; Round 0.96 → ~24%
taller ratio than Round).

ARMS — `ARM_SCALE` (0.115, 0.095, 0.21) → **(0.125, 0.105, 0.225)**
(modest growth, still an elongated bean); visible protrusion ~0.12 →
**~0.13 R**; `ARM_Z` 0.90 → **0.935** (derived: same normalized flank
position on the taller body); `ARM_X` 0.94 unchanged (the larger pill's
embed recomputes to the same value). Tilt −35 / Y 0.05 unchanged.

FEET — `FOOT_SCALE` (0.17, 0.14, 0.115) → **(0.185, 0.148, 0.122)**
(width-led, ratio 1.52); `FOOT_Z` 0.085 → **0.092** (derived: bottom
stays at −0.03); `FOOT_X` 0.33 / `FOOT_Y` −0.43 unchanged (rear still
tucks ~0.02 R inside the belly).

FACE — derived correction only: the group moved +0.06 with the taller
body (EYE_Z 1.47 → **1.53**, MOUTH_Z 1.19 → **1.25**, CHEEK_Z 1.20 →
**1.26**) — identical normalized position (~65% up) and internal
offsets as v4; eye size/spacing/mouth/cheek treatment untouched.

TUFT — derived: MID_Z 2.29 → **2.38**, SIDE_Z (2.25, 2.23) →
**(2.34, 2.32)** (tracks body top 2.346). Scale/design unchanged.

Framing: ortho_scale 3.95455, cam z 1.275. v5 verification
fingerprints: height 66.2%, centered x=512.0, bbox (225, 173, 799, 851),
alpha counts body 250872 / tuft 11703 / limbs 22136 / body+tuft 257609
(limb mass ≈ +16% over v4 at equal world scale after correcting for the
framing change), ≤1 px registration outside.

Comparisons (both at common world scale, floors aligned):
`Previews/preview_tall_v4_vs_v5.png` and
`Previews/preview_round_v6_tall_v4_v5.png`. v4 and earlier records below
are HISTORICAL.

## v4 changes over v3 (arms and feet ONLY — HISTORICAL)

The v3 limbs read as tiny dots/beads, which made the (possibly correct)
body look disproportionately large. v4 resizes the limbs toward the
Tiny Stubby reference relationship; the body profile is deliberately
frozen for this pass so it can be re-judged with proper limbs.

ARMS — the arm itself grew (not just pushed outward): `ARM_SCALE`
(0.095, 0.085, 0.185) → **(0.115, 0.095, 0.21)** (+~50% volume, still an
elongated bean), `ARM_X` 0.945 → **0.94** (embed retuned for the larger
pill). Visible protrusion ~0.10 → **~0.12 R** (+20%); rendered limb-pass
pixel mass +36% (15036 → 20501 px). Direction (−35 down-and-out), Y
(0.05 rearward), Z (0.90 lower flank) unchanged.

FEET — from beads to wide plush pads: `FOOT_SCALE` (0.13, 0.125, 0.11)
→ **(0.17, 0.14, 0.115)** (main growth horizontal: width/height ratio
1.18 → 1.48), `FOOT_X` 0.30 → **0.33** (modestly wider stance),
`FOOT_Z` 0.08 → **0.085** (keeps the foot bottom at exactly −0.03 →
framing byte-identical to v3), `FOOT_Y` −0.43 unchanged but the deeper
pad now tucks its rear ~0.02 R inside the belly surface (attached, not
pasted on the front edge).

UNCHANGED (verified by identical alpha counts on body 258839 and
body+tuft 266013): all body-profile constants (STRETCH 1.135, WIDEN
0.93, PEAR 0.14, SIDE_FILL 0.26, FLATTEN 0.02, LIFT 1.122), face
(1.47/1.19/1.20, eye size/spacing), cheeks, tuft, materials, lighting,
camera, framing (ortho 3.81818, cam z 1.23).

v4 verification fingerprints: height 66.2%, centered x=512.0, bbox
(218, 173, 806, 851), limbs 20501 px, ≤1 px registration outside.

Comparisons: `Previews/preview_tall_v3_vs_v4.png` (tight 1:1 — identical
framing) and `Previews/preview_round_v6_tall_v3_v4.png` (common world
scale, floors aligned). v3/v2/v1 records below are HISTORICAL.

## v3 changes over v2 (body contour ONLY — HISTORICAL)

The v1→v2→v3 progression: v1 = capsule (sidewalls too uniform), v2 =
egg/pear (shoulders too narrow, lower third dominant), v3 = the balanced
middle — soft upright chubby oblong with gentle side curvature.

Only two profile constants moved (no new shoulder control was needed —
the PEAR/SIDE_FILL balance reached the target without parameter
ping-pong):

- `PEAR_AMOUNT` 0.16 → **0.14** (lower third subtle, not dominant)
- `SIDE_FILL` 0.22 → **0.26** (restores shoulder/upper-middle substance;
  v1's 0.32 was the capsule, v2's 0.22 the pear)

Shoulder-to-belly width ratio W(t=+0.5)/W(t=−0.2): v1 0.894 (capsule),
v2 0.867 (pear), v3 0.877 (middle). Body H/W ≈ 2.25/1.96 ≈ 1.15 — still
~19% taller ratio than Round's 0.96.

Derived-only update: `ARM_X` 0.95 → **0.945** (−0.005 compensates the
v3 surface so the visible arm protrusion stays exactly at v2's ~0.10 R).
Everything else byte-for-byte the same tuning as v2: face position
(EYE_Z 1.47 / MOUTH_Z 1.19 / CHEEK_Z 1.20), eye size/spacing, cheeks,
arm scale/tilt/Y/Z, feet (FOOT_Y −0.43 still flush within 0.005 on the
new belly), tuft (2.29 / 2.25 / 2.23), BODY_LIFT 1.122, STRETCH 1.135,
WIDEN 0.93, flatten 0.02, framing (ortho 3.81818, cam z 1.23).

v3 verification fingerprints: height 66.2%, centered x=512.0, bbox
(223, 173, 801, 851), alpha counts body 258839 / tuft 12564 / limbs
15036 / body+tuft 266013, ≤1 px registration outside.

Comparisons: `Previews/preview_round_v6_tall_v1_v2_v3.png` (common world
scale, floors aligned) and `Previews/preview_tall_v2_vs_v3.png` (tight
1:1 pair — v2 and v3 share identical framing). v2/v1 values below are
HISTORICAL.

## v2 changes over v1 (three targeted fixes — HISTORICAL)

1. SILHOUETTE — v1 read as a rounded capsule: sidewalls too straight,
   width too uniform vertically. v2 redistributes width instead of
   changing the design: `SIDE_FILL` 0.32 → 0.22 (less sidewall
   straightening → visible side curvature), `PEAR_AMOUNT` 0.12 → 0.16
   (fuller lower third, narrower shoulder region), `TALL_STRETCH`
   1.16 → 1.135, `BODY_LIFT` 1.147 → 1.122 (same +0.010 floor contact,
   flatten unchanged at 0.02). Body H/W now ≈ 2.25/1.98 ≈ 1.14 — still
   ~18% taller ratio than Round's 0.96, clearly Tall, no longer capsule.
2. FACE — lowered 0.06 as ONE unit (internal eye/mouth/cheek offsets
   unchanged): EYE_Z 1.53 → 1.47, MOUTH_Z 1.25 → 1.19, CHEEK_Z
   1.26 → 1.20. Face sits ~65% up the body (was ~66% on a taller body),
   centered in the visual mass; eye size/spacing untouched (the new
   body width at eye height matches v1 within 0.3%, so EYE_X 0.26
   needed no change).
3. ARMS — visible protrusion ~0.09 → ~0.10 R (+11%) via the embed
   relationship only: ARM_X 0.93 → 0.95, ARM_Z 0.92 → 0.90 (same
   normalized flank position on the shorter body). Scale, −35 tilt,
   and ARM_Y unchanged.

Derived-only registration updates: TUFT_MID_Z 2.34 → 2.29, TUFT_SIDE_Z
(2.30, 2.28) → (2.25, 2.23) (track body top 2.257), FOOT_Y −0.41 → −0.43
(rear flush with the fuller belly). Feet/tuft design and scale unchanged.
Framing: ortho_scale 3.81818, cam z 1.23.

v2 verification fingerprints: height 66.2%, centered x=512.0, bbox
(221, 173, 803, 851), alpha counts body 259459 / tuft 12564 / limbs
15046 / body+tuft 266634, ≤2 px registration outside.

Comparison: `Previews/preview_round_v6_tall_v1_tall_v2.png` (common
world scale, floors aligned; Tall v1 panel preserved from the session
backup). v1 values below are HISTORICAL.

## Design approach

Tall is sculpted as its own silhouette, not a stretched Round. The body
is a unit sphere remapped by a Tall-specific WIDTH PROFILE plus vertical
stretch:

    w(t) = BODY_WIDEN * pear(t) * (1 + SIDE_FILL * t^2 (1 - t^2))
    z    = TALL_STRETCH * (t + bottom flatten)

- `pear(t)` (0.12) keeps the lower half fuller (subtle organic pear).
- `SIDE_FILL` (0.32) widens the shoulder/hip latitudes — a bump peaked
  at |t| = 0.707, zero at poles and equator — so the sides run
  straighter and softer than raw sphere curvature. This term is what
  prevents the "long egg / vertically scaled Round" read.
- Rounded dome top, no waist, 0.02 soft bottom flatten for gentle floor
  contact.

Resulting body-only proportions: height 2.30 R, max width 1.95 R →
H/W ≈ 1.18 vs Round v6's ≈ 0.96 — about +23% apparent height-to-width,
the upper end of the 15–25% target range.

Face: same eye/catchlight/mouth/blush design language as Round v6, but
Tall-specific placement — the face block sits ~2/3 up the body (Round's
is ~60%), eye spacing pulled in for the narrower body (0.26 vs 0.28),
eye SIZE deliberately kept at the Round value so the face reads slightly
larger/dominant on the narrower form. Same world-space eye→mouth gap as
Round (0.28 R) so the face doesn't stretch with the body.

Arms (Rig B): same successful v5/v6 language — slim pill, NEGATIVE tilt
(down-and-out flipper, never up like an ear), embedded, slightly
rearward — but Tall-specific anchors: z 0.92 (clearly below the face
block, lower-middle flank) and ~0.09 R visible protrusion (slightly more
than Round's 0.085) so they read on the bigger form.

Feet (Rig B): same tiny pads as Round (not enlarged), spaced closer
(x 0.30 vs 0.34) because the tall base is narrower; rear edge flush with
the belly surface (y −0.41).

Tuft: same design and scale as Round v6 (deliberately NOT enlarged),
repositioned to the tall dome (mid z 2.34 = body top + 0.03, sides
2.30/2.28, same overlap/asymmetry/tilts).

## v1 tuning values (complete — HISTORICAL, superseded by v2 above)

Body: `TALL_STRETCH 1.16`, `BODY_WIDEN 0.93`, `PEAR_AMOUNT 0.12`,
`SIDE_FILL 0.32`, `BOTTOM_FLATTEN 0.02`, `BOTTOM_FLAT_START -0.5`,
`BODY_LIFT 1.147` (bottom at +0.010).

Tuft: `TUFT_MID_SCALE (0.15, 0.15, 0.20)`, `TUFT_MID_Z 2.34`,
`TUFT_SIDE_SCALE (0.125, 0.125, 0.165)`, `TUFT_SIDE_X 0.145`,
`TUFT_SIDE_Z (2.30, 2.28)`, `TUFT_TILT_DEG (22, 30)`.

Arms: `ARM_SCALE (0.095, 0.085, 0.185)`, `ARM_X 0.93`, `ARM_Y 0.05`,
`ARM_Z 0.92`, `ARM_TILT_DEG -35`.

Feet: `FOOT_SCALE (0.13, 0.125, 0.11)`, `FOOT_X 0.30`, `FOOT_Y -0.41`,
`FOOT_Z 0.08`.

Eyes: `EYE_SCALE (0.112, 0.066, 0.156)`, `EYE_X 0.26`, `EYE_Z 1.53`,
`EYE_EMBED 0.60`; catchlights identical to Round v6.

Mouth: `MOUTH_HALF_W 0.09`, `MOUTH_DROP 0.045`, `MOUTH_Z 1.25`,
`MOUTH_PROUD 0.015`, `MOUTH_BEVEL 0.011`.

Cheeks (approved v6 treatment, Tall-fitted): `CHEEK_SCALE
(0.20, 0.010, 0.09)`, `CHEEK_X 0.48`, `CHEEK_Z 1.26`, `CHEEK_SINK 0.50`,
`CHEEK_PROUD 0.10`, `CHEEK_FALL_RADIUS 0.95`, `CHEEK_FALL_EXP 1.5`,
`CHEEK_CORE_ALPHA 0.45`; preview-only, never in canonical renders.

Rendering: `FRAME_FILL 0.66` (Tall-specific constant, currently equal to
Round's), samples 128, Standard view transform, body #97C9EF, cheek
#F5AFC0, lights 300/90/150 W. Framing: ortho_scale 3.89394, cam z 1.255.

Verification fingerprints (v1): height 66.2% of canvas, centered
x=512.0, bbox (232, 173, 792, 851), alpha counts body 254325 / tuft
12089 / limbs 14491 / body+tuft 261228; ≤1 px registration outside.

## Reused from Round (technical infrastructure only)

Materials (body/eye/catchlight/cheek incl. the approved v6 blush falloff
node chain), light rig and world, orthographic straight-on camera with
constants-derived framing, Cycles/render settings, pass isolation via
collection hide_render, `body_surface_y` analytic anchoring pattern,
bmesh sphere helper. All geometry values and anchors are Tall-specific.

## Rig B specifics (differ from Rig A / Round)

Arm anchors (x/y/z, protrusion), foot anchors (x/y), face placement
(EYE_Z ~2/3 up, EYE_X spacing), cheek placement, tuft z positions, body
profile controls (`TALL_STRETCH`, `SIDE_FILL` — Round has neither), and
the framing constants. Rig B limb asset name: `limbs_b_00.png`.

## Files

- `Scripts/build_tall_aurie.py` — pipeline (own TALL TUNING block).
- `Scripts/verify_tall_renders.py` — Tall verification (Round's
  `verify_renders.py` untouched).
- `Renders/body_01_tall.png` — BODY ONLY (canonical).
- `Renders/tuft_00_tall.png` — TUFT ONLY (tuft design 00 registered on
  the Tall frame; separate for future charm replacement).
- `Renders/limbs_b_00.png` — RIG B arms + feet only (canonical).
- `Renders/body_01_tall_with_tuft.png` — convenience reference.
- `Previews/preview_tall_full.png` — assembled preview + temporary face.
- `Previews/preview_round_v6_vs_tall_v1.png` — comparison at common
  world scale, floors aligned (natural proportions, heights NOT
  equalized).
- `Source/tall_aurie_master.blend`.

## Re-run

```
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --factory-startup --python-exit-code 1 \
  --python Design/Aurie3D/Scripts/build_tall_aurie.py -- \
  --outdir "$(pwd)/Design/Aurie3D"
python3 Design/Aurie3D/Scripts/verify_tall_renders.py
```

## Process rule (inherited from Round)

Anchors are recomputed at NORMALIZED body positions whenever body
proportions change; never copy raw world-z values between body types or
versions. The deferred Round arm-polish item applies to Round only and
was not implemented here.
