# SMALL — BODY FROZEN AT V3 (Rig A checkpoint, 2026-08-16)

**The Small v3 BODY and face/render architecture are the canonical Small
baseline.** **`BodyType small → Rig A` — FINAL** (no longer advisory;
see the rig-decision section). Rig is derived from BodyType; no
persisted rig field; enum ordering/IDs untouched (append-only: round=0,
tall=1, wide=2, **small=3**, lumpy=4 → asset `body_03_small`). The
renders on disk ARE v3, produced by the current
`Scripts/build_small_aurie.py`. Round v6 (Rig A), Tall v14 body
(Rig B), and Wide v2 body (Rig C) remain separately frozen.

## Frozen / approved — body

`SMALL_STRETCH 0.855`, `BODY_WIDEN 0.77`, `TOP_FULL 0.09` (reverse
pear — dome-biased fullness), `SIDE_FILL 0.17`, `LOWER_TAPER 0.045`,
`TAPER_START -0.2`, `BOTTOM_FLATTEN 0.02`, `BOTTOM_FLAT_START -0.5`,
`BODY_LIFT 0.848` (bottom at +0.010) — body ≈ 1.69 × 1.59 R,
**H/W ≈ 1.06** (Round 0.96, Tall 1.32, Wide 0.79).

Small v3 is intentionally a **"petite baby-round Aurie"**. Small does
NOT require a dramatically unique silhouette. Its identity is
intentionally carried by the combination of:

- genuinely smaller world dimensions (real geometry, see below)
- mildly more upright body proportions than Round (H/W 1.06 vs 0.96)
- subtle lower-body narrowing (`LOWER_TAPER 0.045` — a shape cue, not
  a strawberry)
- proportionally larger face share (family-size eyes on the ~80% body)
- proportionally larger-reading tuft (family scale, not scaled down)
- proportionally stronger limb presence

This combination is intentional and approved. The sculpted profile
implementation (`small_width` = WIDEN × top-full dome × side-fill ×
lower-taper) and the Small tuning-block organization are part of the
frozen architecture.

## Rig decision — FINAL: BodyType small → Rig A

The visual test is complete; the mapping is recorded as final (not
merely advisory). Reason: Small and Round share the same fundamental
attachment topology —

- side-mounted arms on the lower flank, below the face
- feet under the body at centered depth
- face on the same general front region above center
- tuft on the dome
- no structurally different shoulder/hip system

A separate Small rig would add unnecessary architecture.

**Rig A does NOT mean same values as Round.** Round and Small share
Rig A architecture, but Small has its own body-specific metadata. Do
not copy Round's values blindly into Small. Small-specific metadata
should eventually support:

- physical/world scale
- faceOffset / faceScale
- eye spacing / face placement
- belly offset if needed
- tuft/head-charm anchor
- side-detail anchor
- tail-charm anchor
- limb-set-specific arm anchors
- limb-set-specific foot anchors
- footprint/shadow data

## World scale is part of the design

Approved v3 physical relationship (genuinely smaller GEOMETRY — not a
camera/framing illusion; the canonical 1024 asset fills its frame like
every family asset, the smaller size lives in the world coordinates):

- Small v3 overall character bounds: **≈ 1.94 × 1.90 R** (verifier
  alpha audit — AUTHORITATIVE; analytic geometry ≈ 1.93 × 1.89 R)
- Round: ≈ 2.23 × 2.01 R overall

Preserve the principle that Small occupies a smaller world footprint.

## Frozen / approved — face, tuft, framing, look

- Surface-conforming face system (Tall v10/v11 architecture), approved
  with Small-specific anchors: black eye patches `EYE_RX/RZ
  0.112/0.156` (FAMILY size — deliberately not scaled down → ~25%
  larger relative on the small body) at `EYE_X 0.22` / `EYE_Z 1.09`
  with the controlled glossy treatment (charcoal rim: tone
  (0.075, 0.078, 0.095), start 0.55, mix 0.30; roughness 0.42,
  spec 0.10); gray sheen 0.032×0.085 at (+0.055, −0.015), emissive
  (0.62, 0.65, 0.70)@0.9, alpha 0.60/exp 1.3; catchlights 0.036×0.047
  at (−0.034, +0.050) and 0.0145×0.018 at (0.024, −0.034); conforming
  ribbon mouth (half-w 0.09, drop 0.045, `MOUTH_Z 0.85` — COMPRESSED
  0.24 R eye→mouth gap vs the family 0.28, the baby read; thickness
  0.011); conforming diffuse blush 0.17×0.08 at (±0.40, 0.86), falloff
  0.95/1.5/0.45 (preview-only). EPSILON POLICY: FACE_SURF_EPS 0.003 /
  sheen +0.001 / catchlights +0.002 — anti-z-fighting only, nothing
  proud or floating; features foreshorten/occlude naturally when
  rotated. Do not modify the face.
- Tuft (separate canonical asset, family design, deliberately NOT
  scaled down — its proportionally larger appearance on Small is
  intentional): MID (0.15, 0.15, 0.20) z 1.73; SIDE
  (0.125, 0.125, 0.165) x 0.145, z (1.69, 1.67), tilt (22, 30). Do not
  resize or redesign it.
- Height-limited framing: `FRAME_FILL 0.66` (width guard
  `FRAME_FILL_W 0.80` not binding) → ortho_scale 2.96818, cam z
  0.9505; verification checks height fraction 62–70% AND audits the
  smaller WORLD size via the embedded ortho constant (keep
  `verify_small_renders.py`'s ORTHO in sync with any future framing
  change).
- Material #97C9EF matte vinyl, cheek #F5AFC0, lights 300/90/150 W,
  Standard view transform, samples 128, 1024×1024 registered
  transparent passes — identical family look; body-type differences
  come from shape and world size only.

## LIMBS — PROTOTYPE ONLY (explicitly NOT final Rig A limb geometry)

`limbs_small_proto_00` is a **Tiny Stubby PROTOTYPE baseline**. Its
only purposes: prove Rig A compatibility, verify registration,
establish attachment zones, and set approximate visual scale for
complete-character body review. Do NOT treat these as immutable
constants — future limb sets may independently change every ARM value
(scale/shape/X/Y/Z anchors/tilt/embed/visible protrusion) and every
FOOT value (shape/scale/stance/depth/vertical position/flattening/
amount visible below body):

- Prototype arms: `ARM_SCALE (0.14, 0.115, 0.26)`, `ARM_X 0.72`,
  `ARM_Y -0.08`, `ARM_Z 0.61`, `ARM_TILT_DEG -54` (~45–50% visible).
- Prototype feet: `FOOT_SCALE (0.21, 0.17, 0.12)`, `FOOT_X 0.29`,
  `FOOT_Y -0.05`, `FOOT_Z 0.091`, flatten 0.24 / start −0.5 (centered
  depth, soles at the floor).

ARCHITECTURE: Small uses the same limb-set system as Rig A — per-set
artwork + Small-specific tuning for each limb set. The body is frozen;
the individual limb designs are not. Rig A limb-set production remains
an OPEN task. NAMING NOTE: the prototype asset kept its rig-neutral
name `limbs_small_proto_00.png` (chosen while the rig was undecided);
now that small → Rig A is final, a future Rig A limb-set naming pass
may supersede it — deliberately NOT renamed during this checkpoint.

## Body-roster principle (recorded during Small development)

Not every body-type name requires a radically unique silhouette. Small
primarily represents physical scale, baby proportion, and visual
personality. More distinctive silhouette roles are reserved for
dedicated future bodies: Egg, Pear, Bean, Dumpling, Teardrop,
Top-Heavy/Puff, Beanbag, Oval, Pebble, Gourd, Heart-ish, Chubby Star/
Five-Lobed, Squircle, Mochi. Do not push Small toward those shapes in
future maintenance.

## Body roster status (as of this checkpoint)

- Round V6 → Rig A — frozen
- Tall V14 → Rig B — body frozen
- Wide V2 → Rig C — body frozen
- **Small V3 → Rig A — frozen (this checkpoint)**
- Lumpy → still pending visual testing / rig decision
- Future concepts (each its own body, not Small variants): the roster
  list above. Persisted BodyType enum cases are append-only — nothing
  added or reordered at this checkpoint.

## Why v3 was chosen (development record)

- **Small v1** established the true smaller world scale and the
  baby-like face/tuft proportions, but the body silhouette was too
  similar to Round.
- **Small v2** attempted stronger body differentiation;
  `LOWER_TAPER 0.14` + `TOP_FULL 0.14` overcorrected into a
  strawberry / inverted-teardrop silhouette — rejected.
- **Small v3** reduced `LOWER_TAPER` to 0.045 and `TOP_FULL` to 0.09,
  restored `BODY_WIDEN` to 0.77, `SIDE_FILL` to 0.17,
  `SMALL_STRETCH` to 0.855 — restoring a rounded baby body while
  retaining the genuine smaller world scale — approved.

The v1/v2 tuning history is preserved in the HISTORICAL sections below.

## Verification fingerprints (v3 checkpoint, read-only)

ALL CHECKS PASSED against the untouched renders: height 65.2% of
canvas, world-size audit h=1.94 / w=1.90 R (smaller than Round's
~2.23 × 2.01), centered x=512.0, bbox (185, 173, 839, 841), alpha
counts preview 287839 / body 258191 / tuft 20676 / limbs 45719 /
body+tuft 269563, ≤2 px registration outside, soles at the floor.

## Approved visual record (development evidence, not necessarily Git)

- `preview_body_shapes_round_small_v1_v2_v3.png` (Round v6 / Small v1 /
  v2 / v3 body-only progression — the decisive comparison)
- `preview_small_v2_vs_v3_body_only.png`
- `preview_family_all_four_world_scale_v3.png` (Round/Tall/Wide/Small
  v3 at common world scale)
- `preview_small_v3_diagnostic_34.png` (3/4 — volumetric underside,
  conforming face)

## v3 changes over v2 (HISTORICAL record — the strawberry fix)

DESIGN DECISION RECORDED: with Egg/Pear/Teardrop/Puff/Oval/Mochi etc.
now planned as their own body concepts, Small does NOT need a
dramatically unique silhouette. Small's identity = genuinely smaller
world size + baby proportions (family-size eyes on a smaller body,
compact eye-mouth gap, larger-reading tuft/limbs). The body itself may
stay close to the Round family; v2's LOWER_TAPER 0.14 + TOP_FULL 0.14
had overcorrected into a strawberry / inverted teardrop.

- `LOWER_TAPER` 0.14 → **0.045** (kept as a SUBTLE shape cue only —
  lower body gently narrower, sides flow into a rounded base, no point)
- `TOP_FULL` 0.14 → **0.09** (dome a touch fuller than Round, never
  ballooned over a narrow bottom)
- `BODY_WIDEN` 0.74 → **0.77**, `SIDE_FILL` 0.15 → **0.17** (restored
  plush compact mass and curved sides)
- `SMALL_STRETCH` 0.87 → **0.855** → body ≈ 1.69 × 1.59 R, **H/W ≈
  1.06** (inside the 1.04–1.07 target; modestly more upright than
  Round's 0.96, nowhere near Tall/Oval)
- `BODY_LIFT` 0.848 (derived, bottom at +0.010)

Derived-only anchors: face group at the same ~64%-up layout (EYE_Z
1.09, MOUTH_Z 0.85, CHEEK 0.40/0.86), tuft on the corrected dome
(1.73 / 1.69 / 1.67), arms X 0.72 / Z 0.61, feet stance 0.29. Framing
ortho 2.96818, cam z 0.9505. First target combination passed the
body-only review — no further internal variants needed.

## v2 changes over v1 (HISTORICAL — overcorrected into a strawberry)

v1's body-only silhouette was too similar to Round — the Small identity
leaned on face/tuft/limbs/world size. v2 makes the BODY itself read
Small via a new signature control:

- `LOWER_TAPER 0.14` (NEW) with `TAPER_START -0.2`: the lower third
  narrows progressively (power-1.5 ease) toward a small tucked base —
  ~14% circumference cut at the bottom; no waist, no cone, no pear.
  Widest region sits at the upper-middle. RADIAL (x and y alike), so
  the tuck is volumetric, verified at 3/4.
- `SMALL_STRETCH` 0.84 → **0.87** (petite upright, NOT Tall)
- `TOP_FULL` 0.10 → **0.14** (broad soft baby torso, not a Puff)
- `SIDE_FILL` 0.18 → **0.15** (softer lower-middle)
- `BODY_WIDEN` 0.77 → **0.74**, `BODY_LIFT` 0.833 → **0.863** (derived)

Body ≈ 1.72 × 1.57 R → **H/W ≈ 1.10** (v1: 1.04; Round: 0.96). World
size audited: character bounds 1.97 × 1.85 R vs Round's ~2.23 × 2.01
(height −11%, width −8% incl. limbs; body-only width −22%) — the
smaller footprint is real geometry, unchanged in spirit from v1.

Derived-only anchor updates: face group (EYE_Z 1.11, MOUTH_Z 0.87,
CHEEK_Z 0.88, CHEEK_X 0.39 — same ~64%-up layout and 0.24 gap), tuft
tracks the taller dome (1.76 / 1.72 / 1.70), arms (X 0.70, Z 0.62 —
same normalized flank/visibility), feet stance 0.30 → 0.28 under the
tucked base. No face/tuft/limb redesign. Framing: ortho 3.01364,
cam z 0.9655. No internal body variants were needed — the first
target values solved the silhouette (verified in the body-only trio).

v2 verification: ALL CHECKS PASSED — height 65.2%, world-size check
1.97 × 1.85 R, centered x=512.0, bbox (197, 173, 827, 841), alpha
counts body 246393 / tuft 20049 / limbs 44356 / body+tuft 257428,
≤1 px outside.

## Rig assessments v1–v3 (HISTORICAL — decision now FINAL, see top)

The advisory assessments during development consistently found Small's
attachment TOPOLOGY identical to Rig A's pattern: side-mounted arms
below the face on the mid-lower flank, two feet under the base at
centered depth, face block above center, tuft on dome. Nothing about
the shoulder/hip regions is structurally different from Round — they
are smaller and slightly higher-domed, which per-body metadata
(faceOffset + faceScale + per-set limb tuning) already supports. Using
Rig A does NOT impose awkward universal-limb constraints because limb
sets are per-rig artwork + per-set tuning by architecture. The
genuinely smaller world footprint is a renderer scale/metadata concern
(e.g., a per-body canvas scale), not a rig-topology concern. Each
round's recommendation was "A — Small likely fits Rig A with
Small-specific metadata"; v3's return to Round-compatible body
architecture strengthened it, and the user confirmed the final mapping
at this checkpoint.

## Reference observations (Body Types sheet, SMALL panel)

Small is not a scaled Round: compact slightly UPRIGHT teardrop
(marginally taller than wide, where Round is wider than tall), the
dome/head carries a larger share of the mass, big-eyed face dominates
with a compact eye-to-mouth region, short lower body with a small base,
tiny peeking feet, tiny arm nubs, tuft proportionally larger.

## Design approach (HISTORICAL — v1 exploration framing)

1. GENUINELY SMALLER WORLD SIZE (not framing): body 1.66 R tall ×
   1.60 R wide — ~86% of Round's height, ~79% of its width; total
   character world bounds 1.91 × 1.92 R vs Round's ~2.23 × 2.01.
2. INTRINSICALLY DIFFERENT PROPORTIONS: **H/W ≈ 1.04** (Round: 0.96 —
   the aspect flips to slightly-taller-than-wide) via a REVERSE pear:
   `TOP_FULL` biases fullness to the UPPER body/dome (every other
   family fills the lower half) — the head-heavy baby silhouette.
3. BABY FACE WITHOUT REDESIGN: eyes keep the FAMILY size (0.112×0.156)
   on the ~80% body → automatically ~25% larger relative; eye-to-mouth
   gap compressed to 0.24 R (family: 0.28); tuft kept at FAMILY scale →
   proportionally larger on Small. Face ~64% up the body.
4. Modern conforming face architecture throughout (Tall v10/v11: eye
   rim gradient, gray sheen, catchlights, ribbon mouth, blush; epsilon
   policy 0.003/+0.001/+0.002). No proud/floating geometry.
5. Rig-neutral Tiny Stubby PROTOTYPE limbs (diagnostic only).

## v1 tuning values (complete — HISTORICAL, superseded by v2/v3)

Body: `SMALL_STRETCH 0.84`, `BODY_WIDEN 0.77`, `TOP_FULL 0.10`
(reverse pear), `SIDE_FILL 0.18`, `BOTTOM_FLATTEN 0.02`,
`BOTTOM_FLAT_START -0.5`, `BODY_LIFT 0.833` (bottom at +0.010).

Face: EYE (0.112, 0.156) at (±0.22, 1.07); MOUTH_Z 0.83 (0.24 gap),
half-w 0.09, drop 0.045, bevel 0.011; CHEEK (0.17, 0.08) at
(±0.40, 0.84); sheen/catchlight constants identical to Tall/Wide.

Tuft: FAMILY scale — MID (0.15, 0.15, 0.20) z 1.70; SIDE
(0.125, 0.125, 0.165) x 0.145, z (1.66, 1.64), tilt (22, 30).

PROTOTYPE limbs (rig-neutral, asset `limbs_small_proto_00`): arms
(0.14, 0.115, 0.26) at X 0.73 / Y −0.08 / Z 0.60, tilt −54 (~45–50%
visible); feet (0.21, 0.17, 0.12) at X 0.30 / Y −0.05 / Z 0.091,
flatten 0.24 / start −0.5 (centered depth, soles at the floor).

Framing: height-limited `FRAME_FILL 0.66` (width guard 0.80 not
binding): ortho_scale 2.92273, cam z 0.9355. Same family material/
lighting/render setup — differences come from shape and size only.

v1 verification: ALL CHECKS PASSED — height 65.2%, WORLD SIZE check
h=1.91 / w=1.92 R (audited smaller than Round), centered x=512.0,
bbox (176, 173, 848, 841), alpha counts preview 294930 / body 264236 /
tuft 21301 / limbs 47133 / body+tuft 275913, 0 px outside.

## Files (canonical Small set)

- `Scripts/build_small_aurie.py`, `Scripts/verify_small_renders.py`
- `Renders/body_03_small.png` (BODY ONLY, canonical)
- `Renders/tuft_00_small.png` (TUFT ONLY, Small frame)
- `Renders/limbs_small_proto_00.png` (PROTOTYPE arms+feet — see naming
  note in the LIMBS section)
- `Renders/body_03_small_with_tuft.png` (convenience)
- `Previews/preview_small_full.png`, `Source/small_aurie_master.blend`
- `Notes/small_aurie_v1_notes.md` (this checkpoint document; filename
  follows the family `*_v1_notes.md` convention, like Tall/Wide)
- Approved comparisons/diagnostic: see "Approved visual record" above.
  Earlier development images (`preview_family_all_four_world_scale.png`,
  `preview_round_vs_small_shape.png`,
  `preview_body_shapes_round_smallv1_smallv2.png`,
  `preview_small_v1_vs_v2_body_only.png`, v1/v2 diagnostics) are
  HISTORICAL evidence — do not delete.

## Re-run

```
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --factory-startup --python-exit-code 1 \
  --python Design/Aurie3D/Scripts/build_small_aurie.py -- \
  --outdir "$(pwd)/Design/Aurie3D"
python3 Design/Aurie3D/Scripts/verify_small_renders.py
```

## Process rules (inherited)

Anchors recompute at NORMALIZED body positions on any proportion
change; face artwork always conforms to the surface (epsilons are
z-fighting-only); feet originate under the body near mid-depth; arms
side-mounted, below the face, never ear-like; limb sets are
body/rig-specific artwork + per-set tuning; Small's verifier ORTHO
constant tracks any framing change.
