# ROUND — FROZEN (v6, 2026-08-14)

**Round v6 is the canonical Round Aurie source of truth.** The five
renders in `Renders/` + `Previews/preview_round_full.png` and
`Source/round_aurie_master.blend` currently on disk ARE v6, produced by
the current `Scripts/build_round_aurie.py`. Round maps to **Rig A**.
The v6 diffuse-cheek treatment is **visually approved**. The v5/v6 arm
redesign (down-and-out flipper stub) **successfully fixed the prior
ear-like read**. No further Round visual changes should occur unless
Round is explicitly reopened by the user.

## Frozen v6 tuning values (complete)

Body: `BODY_WIDEN 1.01`, `BODY_SQUASH 0.97`, `PEAR_AMOUNT 0.10`,
`BOTTOM_FLATTEN 0.015`, `BOTTOM_FLAT_START -0.5`, `BODY_LIFT 0.965`.

Tuft: `TUFT_MID_SCALE (0.15, 0.15, 0.20)`, `TUFT_MID_Z 1.965`,
`TUFT_SIDE_SCALE (0.125, 0.125, 0.165)`, `TUFT_SIDE_X 0.145`,
`TUFT_SIDE_Z (1.925, 1.905)`, `TUFT_TILT_DEG (22, 30)`.

Arms: `ARM_SCALE (0.095, 0.085, 0.185)`, `ARM_X 0.955`, `ARM_Y 0.05`,
`ARM_Z 0.72`, `ARM_TILT_DEG -35` (negative = tip points down-and-out).

Feet: `FOOT_SCALE (0.13, 0.125, 0.11)`, `FOOT_X 0.34`, `FOOT_Y -0.42`,
`FOOT_Z 0.08`.

Eyes: `EYE_SCALE (0.112, 0.066, 0.156)`, `EYE_X 0.28`, `EYE_Z 1.16`,
`EYE_EMBED 0.60`; catchlights `CATCH_SCALE (0.036, 0.018, 0.047)` at
`(-0.034, -0.052, 0.050)`, `CATCH2_SCALE (0.0145, 0.010, 0.018)` at
`(0.024, -0.050, -0.034)`.

Mouth: `MOUTH_HALF_W 0.09`, `MOUTH_DROP 0.045`, `MOUTH_Z 0.88`,
`MOUTH_PROUD 0.015`, `MOUTH_BEVEL 0.011`.

Cheeks (approved; preview-only, never in canonical renders):
`CHEEK_SCALE (0.22, 0.010, 0.095)`, `CHEEK_X 0.52`, `CHEEK_Z 0.89`,
`CHEEK_SINK 0.50`, `CHEEK_PROUD 0.10`, `CHEEK_SOFT True`,
`CHEEK_FALL_RADIUS 0.95`, `CHEEK_FALL_EXP 1.5`, `CHEEK_CORE_ALPHA 0.45`;
falloff `alpha = core * (1 - r/RADIUS)^EXP` built from plain Math nodes;
cheek objects have `visible_shadow = False`.

Rendering/look: `FRAME_FILL 0.66`, `SAMPLES 128`, view transform
`Standard`, `EXPOSURE 0.0`, body `#97C9EF`, cheek `#F5AFC0`,
Key/Fill/Rim `300 / 90 / 150 W`. Framing derived from constants:
ortho_scale 3.32576, camera z 1.0675.

Verification fingerprints (v6): height 66.2% of canvas, centered at
x=512.0, alpha pixel counts body 302582 / tuft 16512 / limbs 19693 /
body+tuft 311646; all part passes register 0 px outside the preview
silhouette.

## Deferred arm polish — NOT IMPLEMENTED

The current v6 arms correctly read as arms instead of ears, but they may
eventually benefit from approximately **10–20% more visible protrusion**.
If this is reopened later:

- preserve the current down-and-out direction (negative tilt)
- preserve the current slim pill/bean shape
- preserve the low placement
- preserve the rearward/deep embed relationship
- do not raise the arms toward the face
- do not return to rounded side nubs
- prefer a small visibility/embed adjustment (e.g. ARM_X) over
  substantially increasing arm scale

This is a future polish note only and does not change the v6 freeze.

## Architecture

- BodyType `round` → **Rig A**.
- Hybrid asset architecture remains approved: full-frame 1024×1024
  pixel-registered artwork + a small per-rig metadata table later
  (rig metadata must support faceOffset AND faceScale).
- No app renderer integration yet.
- No persisted `rig` field for V1 — derive the rig from BodyType.
- BodyType persisted IDs and enum ordering remain untouched
  (append-only).
- Canonical separation: `body_00_round.png` = BODY ONLY, `tuft_00.png` =
  TUFT ONLY (separate so future head charms can replace/cover it),
  `limbs_a_00.png` = ARMS + FEET ONLY, `body_00_round_with_tuft.png` =
  convenience reference only. Cheeks are preview-only.

## What this is

A fully programmatic Blender pipeline (no manual modeling) that builds one
Round Aurie matching `References/aurie_body_types_reference.png` (ROUND),
`aurie_limb_sets_reference.png` (Tiny Stubby), and `aurie_face_reference.png`
(Oval eyes), then renders registered transparent 1024×1024 passes.

## Re-run (reproduces frozen v6 exactly — deterministic, seed 0)

```
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --factory-startup --python-exit-code 1 \
  --python Design/Aurie3D/Scripts/build_round_aurie.py -- \
  --outdir "$(pwd)/Design/Aurie3D"
python3 Design/Aurie3D/Scripts/verify_renders.py
```

Blender 5.2.0 LTS. ~2 min total (5 Cycles CPU passes at 128 samples).

## Outputs (canonical v6 set)

- `Previews/preview_round_full.png` — assembled character + temporary face.
- `Renders/body_00_round.png` — BODY ONLY (canonical).
- `Renders/tuft_00.png` — TUFT ONLY (canonical).
- `Renders/limbs_a_00.png` — arms + feet only (canonical).
- `Renders/body_00_round_with_tuft.png` — convenience reference only.
- `Source/round_aurie_master.blend` — full scene (open in Blender any time).

All five renders share one fixed orthographic camera, so they stack as
pixel-registered full-frame layers.

Review comparisons preserved in `Previews/` (do not regenerate):
`preview_round_v5_vs_v6.png` (key cheek review),
`preview_round_v1_v2_v3_v4_v5.png`, `preview_round_v1_v2_v3_v4.png`,
`preview_round_v1_v2_v3.png`, `preview_round_v1_vs_v2.png`.

## How it works (for future edits)

- Everything is parameterized in the `TUNING` block at the top of
  `Scripts/build_round_aurie.py` — proportions, colors, light powers,
  framing, samples. Iterate by editing constants and re-running.
- Body = 64×32 UV sphere with a pear deform (lower half widened ~10%),
  1.01 widen, 0.97 z-squash, and a 0.015 soft bottom flatten, smooth-shaded.
  Tuft = three overlapping ellipsoid lobes (middle tallest, slightly
  asymmetric). Arms/feet = tilted ellipsoids embedded in the body.
- Face parts anchor to `body_surface_y(x, z)` — the analytic surface of the
  deformed body — so they stay ON the surface whenever proportions change.
  Catchlights are small emissive spheres (guaranteed, art-directable).
- Cycles CPU, 128 samples + OpenImageDenoise, `film_transparent`, view
  transform **Standard** (the factory default AgX washes out pastels).
- Passes are isolated by collection `hide_render` flags; camera and lights
  never change, which is what keeps the layers registered.
- PROCESS RULE: the body center moves whenever body proportions change
  (0.86→0.94→0.965 R across v2→v4). Every body-relative anchor
  (tuft/arm/foot/eye/mouth/cheek z, arm embed x, foot embed y) must be
  recomputed at the same NORMALIZED position on the new body. Apply the
  same rule when designing any new body type.

## Known limitations / decisions

- **No ground shadow in the preview**: with a perfectly straight-on
  orthographic camera the floor plane is edge-on (zero projected area), so
  a shadow catcher cannot appear. Per the approved amendment this was
  omitted rather than tilting the camera and breaking layer registration.
  A separate beauty-shot camera (slightly high angle + shadow catcher)
  could be added later purely for marketing/previews.
- Per-part passes lack occlusion/bounce from hidden parts (the preview is
  the ground truth for the assembled look).
- The `CHEEK_PROUD` anti-occlusion float is only valid for the fixed
  straight-on ortho camera (no parallax); cheeks are preview-only, so
  that is fine.
- The soft crease where tuft lobes meet the body is real geometry
  intersection — reads correctly at 1024. Tuft lobes could eventually
  read more organic than three attached bumps — deliberately deferred.

## Historical / superseded Round iterations

These records are design history only; v6 above is the single source of
truth. Do not delete.

**v6 (frozen — cheek-only correction over v5):** everything except
cheeks bit-identical to v5 (verified via unchanged alpha pixel counts on
all non-preview passes). Three cheek fixes:
1. FALLOFF SHAPE — MapRange S-curves (smoothstep/smootherstep) are flat
   near r=0, which always leaves a concentrated core no matter how wide
   the gradient. v6 uses alpha = CORE * (1 - r/RADIUS)^EXP (plain Math
   nodes: DIVIDE→SUBTRACT(clamped)→POWER→MULTIPLY): fades immediately
   from the center, gradual across the disc, smooth zero at the rim.
2. INTENSITY — CHEEK_CORE_ALPHA 0.85 → 0.45; wider flatter disc
   (0.22, 0.010, 0.095), z 0.90 → 0.89.
3. OCCLUSION CUT — a wide flat cheek slab lying ON the curved body gets
   occluded by the body surface toward the face center, slicing the
   blush with a hard inner edge. Fix: CHEEK_PROUD floats the slab 0.10 R
   toward the camera with visible_shadow=False.

**v5 cheek values (replaced in v6):** CHEEK_SCALE (0.16, 0.010, 0.11),
CHEEK_X 0.52, CHEEK_Z 0.90, CHEEK_FALL (0.10, 0.95), CHEEK_CORE_ALPHA
0.85, SMOOTHERSTEP MapRange, no CHEEK_PROUD, shadow-casting on.

**v5 (arm + first cheek cleanup):** targeted cheek + arm cleanup on the
v4 body; nothing else touched. ARMS no longer read as ears: the key fix
is the TILT SIGN — a positive tilt points the ellipsoid's visible tip
up-and-out, which is exactly ear geometry; v5 uses −35 so the stub
emerges low on the side pointing down-and-out like a tiny flipper. Also
slimmer pill (0.095, 0.085, 0.185), lower (z 0.72), slightly rearward
(ARM_Y 0.05, new tunable), deeper embed (ARM_X 0.955 puts the center
inside the body; visible protrusion ~0.085 R vs ~0.117 in v4).

**v4 (body/silhouette pass over v3):** v3 was back in the Round family
but still slightly broad/heavy through the lower third; v4 took another
small step toward v1's upright buoyant read without literally restoring
it: widen 1.02→1.01, squash 0.95→0.97, bottom flatten 0.02→0.015
(subtle pear kept at 0.10). Feet width trimmed ~4% (0.135→0.13).
Cheeks broadened/softened (superseded by v6).
v4 arm/cheek values (replaced in v5): ARM_SCALE (0.115, 0.095, 0.19),
ARM_X 1.02, ARM_Z 0.79, ARM_TILT_DEG +28 (no ARM_Y); CHEEK_SCALE
(0.145, 0.012, 0.10), CHEEK_X 0.50, CHEEK_Z 0.94, CHEEK_FALL
(0.18, 0.95), CHEEK_CORE_ALPHA 0.90, LINEAR falloff.

**v3 (return toward v1 after v2 overshot):** widen 1.02, squash 0.95,
flatten 0.02, lift 0.94; anchors TUFT_MID_Z 1.92, TUFT_SIDE_Z
(1.88, 1.86), ARM_X 1.03, ARM_Z 0.77, FOOT (0.135, 0.125, 0.11) y −0.45,
EYE_Z 1.13, MOUTH_Z 0.86, CHEEK (0.125, 0.012, 0.088) x 0.51 z 0.92;
ortho 3.25758, cam z 1.045.

**v1 (original POC):** no widen, squash 0.96, no flatten, lift 0.97;
larger tuft/arms/feet, smaller wider-set eyes; superseded by the v2–v6
detail work but its near-circular silhouette guided v3/v4.

The soft-cheek gotcha (applies to any future blush work): alpha falloff
must use radial distance in the cheek's local x/z disc plane — a 3D
spherical gradient evaluates to 0 at every surface point of a sphere and
makes the cheek invisible. Cheeks stay preview-only and may ultimately
ship as a 2D/global asset.

## v2 — starting reference for future `body_02_wide` (do not lose)

v2 is NOT a failed Round: it overshot Round horizontally and is
preserved as the deliberate starting point for the future Wide body
exploration. Values: BODY_WIDEN 1.07, BODY_SQUASH 0.91, PEAR_AMOUNT
0.10, BOTTOM_FLATTEN 0.06, BOTTOM_FLAT_START −0.5, BODY_LIFT 0.86;
anchors tuned for that body: TUFT_MID_Z 1.80, TUFT_SIDE_Z (1.76, 1.74),
ARM_X 1.08, ARM_Z 0.70, FOOT_SCALE (0.145, 0.135, 0.115), FOOT_Y −0.62,
EYE_X 0.29, EYE_Z 1.04, MOUTH_Z 0.78, CHEEK_X 0.54, CHEEK_Z 0.84.
Framing then: ortho_scale 3.08333, cam z 0.9825. Its preview appears in
the historical comparison PNGs. Wide has NOT been started.

## Future ideas (not applied, optional)

1. Slight subsurface (Subsurface Weight 0.03–0.05) for waxier vinyl depth.
2. Arms: optional gentle bend (Simple Deform) for more "bean" curvature.
3. A 3/4 beauty camera + shadow catcher as a second, non-canonical preview.
4. If a marketing render is ever wanted: bump samples to 512.

## 2026-08-16 foot/leg placement pass (PROTOTYPE LIMBS ONLY)

Library-wide placement pass, user-directed. Round's prototype limbs
were the last on the pre-architecture stance and were modernized:
FEET (0.13, 0.125, 0.11) at x 0.34 / y -0.42 / z 0.08 (front-mounted
pads) -> (0.21, 0.17, 0.115) at x 0.36 / y -0.05 / z 0.085 with the
family soft sole flatten (0.24 / -0.5) — centered depth under the
body; ARM_Y 0.05 -> -0.08 (the deferred arm fix: toward-camera bias
for real 3D volume). FOOT_Z - scale_z pinned at -0.030 so the frozen
V6 framing (ortho 3.32576 / cam 1.0675) is unchanged, and the V6 BODY
render was pixel-verified BYTE-IDENTICAL after the rebuild. The BODY
remains frozen; these remain prototype limb values.

## 2026-08-16 correction pass: cheeks ported to conforming patches

The v6 proud ellipsoid cheeks (CHEEK_PROUD 0.10 float) were the last
proud face geometry in the family and visibly poked past the
silhouette at 3/4 (measured: 143 pink pixels within 4 px of the
silhouette edge). Ported to the family surface-conforming patch
system: same footprint (0.22 x 0.095 at +-0.52 / 0.89), same
airbrushed falloff (0.95 / 1.5 / 0.45), CHEEK_SURF_EPS 0.003
(z-fighting only). After: 0 near-edge pink pixels; front-view blush
look preserved. Eyes/mouth untouched (their proud placement does not
violate the silhouette). BODY render pixel-verified BYTE-IDENTICAL.
