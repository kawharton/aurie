# AURIE BODY LIBRARY — rapid-production phase (2026-08-16)

Objective of this phase: COVERAGE, not per-body perfection — one strong
recognizable V1 per remaining roster body, provisionally accepted when
"good enough to belong in the Aurie body library." None are frozen;
none have BodyType indices (candidate naming throughout); rigs are
recommendations only; all limbs are rig-neutral Tiny Stubby PROTOTYPES.

CLEANUP/REFINEMENT PASS (user review, 2026-08-16): **Gourd, Pebble,
and Mochi are REMOVED from the active library** (files kept on disk as
history, scripts marked rejected; excluded from all library sheets and
lineups). **Star was refined to V2** (broad-lobed pillowy rebuild) and
**Bean to V2** (obvious kidney bow). Pear stays exactly at approved
V2. ACTIVE LIBRARY: 15 bodies — Round, Tall, Wide, Small, Egg, Pear +
Bean v2, Dumpling, Teardrop, Puff, Beanbag, Oval, Heart, Star v2,
Squircle.

## Shared architecture (new this phase)

`Scripts/aurie_body_common.py` centralizes the frozen family pipeline
VERBATIM for candidate bodies: family material (#97C9EF matte vinyl),
the surface-conforming face system (controlled glossy eyes with
charcoal rim + gray sheen + catchlights, ribbon mouth, diffuse blush,
epsilon policy 0.003/+0.001/+0.002), family tuft, prototype limbs,
family lights/camera/render settings, and the registered canonical
passes. Frozen bodies (Round/Tall/Wide/Small/Egg/Pear) keep their own
self-contained frozen scripts — untouched.

- Per-body scripts (`build_<name>_aurie.py`) hold only TUNING + a
  width function (+ optional shape hooks); family-standard anchors
  (face ~63% up, family eye size/spacing ratio, 0.28 eye→mouth gap,
  tuft at top+0.027, arms ~36% up with 0.09 embed, feet under the
  base) are AUTO-DERIVED from the profile — the same normalized layout
  the frozen bodies use.
- Shape hooks: `x_shift_w` (axis bow — Bean), `s_phi` (frontal radial
  lobes/irregularity — Star/Pebble/Beanbag; faded smoothly to zero
  near the frontal pole to avoid the atan2 singularity pucker, with
  configurable depth coupling `sphi_y`), `z_dent` (crown dip — Heart,
  kept above the face zone so conforming stays exact).
- `Scripts/verify_candidate_renders.py <names…>` re-imports each CFG
  (bpy-optional) and RECOMPUTES framing/expected bounds from the same
  constants — no drift possible. Checks: files/format/alpha/blend,
  height- or width-fraction band per framing mode, world bounds vs
  analytic expectation, centering (wider tolerance for asymmetric
  bodies), clipping, pass registration, belly color.
- Framing per body is computed (never hardcoded): recompute via
  `common.framing(common.resolve(CFG))`.

## Candidate roster — tuning + status (all: VERIFIED, ACCEPTED)

1. **bean — V11 (APPROVED FINAL SHAPE)**, matched to
   `References/bean_reference.png` through the v4–v11 body-only
   exploration after v1–v3 (bow-only) were rejected as tilted eggs.
   Structure: curved centerline (LEAN 0.30, RECENTER 0.25), lateral
   asymmetry (ASYM 0.07 tanh x-warp — fuller outer / tucked inner),
   **deep soft one-sided cave** (cos² angular window: DENT 0.42, σ 78°,
   center −4°) with inner lobes (±0.04 at +66°/−52°), broad outer-arc
   swell (+0.05 @ 180°/95°), blunt capped ends (TOP_CAP 0.32 /
   BOT_CAP 0.26, u⁶), STRETCH 1.14, WIDEN 0.94, belly 0.13, and a
   uniform end-stage slimming **post_xy 0.835 → H/W ≈ 1.44**. Depth
   coupling sphi_y 0.45 (reduced at character integration so the
   right-front stays readable — silhouette unaffected).
   CHARACTER INTEGRATION (asymmetric-body firsts): per-side arm
   anchors from each side's signed flank (`arm_lr`: left −0.83/0.82 on
   the outer arc, right +0.46/0.74 tucked below the cave); face seated
   on the UPPER LOBE (eye_frac 0.66) offset onto the outer-arc mass
   (`face_dx` −0.16), eye spacing from the left/right flank average
   (eye_x 0.199). Fixing the buried-face bug required correcting the
   shared surface-inversion composition in `aurie_body_common.py`
   (warp/shift must be stripped BEFORE dividing out s_phi; y now
   carries the sphi_y coupling) — exact conforming faces for all
   hook-combining bodies. Ortho 3.86566 / cam 1.24447 (h-limited).
   v1–v10 HISTORICAL; evidence: `preview_bean_v3_vs_kidney_candidates
   .png`, `preview_bean_candC_vs_v4_body_only.png`, and the
   v4→v5→v6→v7→v8→v9→v10→v11 body-only pair sheets.
2. **dumpling** — squat plump, pinched crown, weighted base. SQUASH
   0.90, WIDEN 1.02, belly 0.12/1.4, pinch 0.13/2.2, flatten 0.025.
   Ortho 3.09955 / 0.99165 (h).
3. **teardrop** — bottom-heavy, long soft continuous upper narrowing,
   rounded crown (no point). STRETCH 1.08, WIDEN 0.95, belly 0.16/1.2,
   narrow 0.32/1.3, flatten 0.02. Ortho 3.64636 / 1.17210 (h).
4. **puff (top-heavy)** — fuller upper mass, smaller rounded lower;
   max width above center; not triangular. STRETCH 1.02, WIDEN 0.93,
   top 0.16/1.3, lower taper 0.20/1.6, flatten 0.018, eye_frac 0.65.
   Ortho 3.46945 / 1.11372 (h).
5. **beanbag** — slouchy settled broad lower mass + gentle radial
   irregularity. SQUASH 0.86, WIDEN 1.05, slump 0.20/1.1, top relax
   0.24/1.4, irr (0.018, 0.012), flatten 0.03. Ortho 3.12554 /
   0.93901 (WIDTH-limited).
6. **oval** — pure ellipsoid, zero sculpting (vs Tall's sculpted
   proportions). STRETCH 1.12, WIDEN 0.90 const, flatten 0.015.
   Ortho 3.77485 / 1.21450 (h).
7. **pebble — REMOVED from active library** (rejected at review; files
   on disk as history). Was: SQUASH 0.80, WIDEN 0.92, side 0.08, irr
   (0.022, 0.014).
8. **gourd — REMOVED from active library** (rejected at review; files
   on disk as history). Was: waist dip 0.07 + upper-lobe swell 0.10
   over lower-full 0.15/1.3, STRETCH 1.08, WIDEN 0.90.
9. **heart** — subtle: full paired shoulders (0.13/1.5 upper-biased),
   smaller base (0.15/1.6), crown center dip DENT 0.14/σ 0.30 above
   t 0.40 (face zone untouched), tuft nestled in the cleft (z 1.93).
   STRETCH 1.02, WIDEN 0.97. Ortho 3.27455 / 1.04940 (h).
10. **star (chubby five-lobed) — V2** (v1's symmetric ±0.11 cosine
    carved starfish grooves): the wave now has BROAD rounded lobes and
    much shallower valleys — s = (1−VALLEY_DIP) + (LOBE_FULL +
    VALLEY_DIP)·u^0.6 with u = (1+cos(5(φ−90°)))/2, **LOBE_FULL 0.10 /
    VALLEY_DIP 0.045** (valleys ~60% shallower than v1), depth
    coupling **sphi_y 0.15** (no grooves toward the center),
    **fade_rho 0.60** (full pillowy center), mesh 96×48, lift 0.965,
    flatten 0. STRETCH 1.0, WIDEN 0.93, eye_frac 0.62. Star identity
    comes from the outer silhouette; thick at 3/4. Ortho 3.52000 /
    1.13040 (h). v1 values HISTORICAL; comparison
    `preview_star_v1_vs_v2_body_only.png`.
11. **squircle** — direct superellipse silhouette |t|^3.4; near-
    constant width, soft fuller corners. STRETCH 0.99, WIDEN 0.96,
    flatten 0.02. Ortho 3.37636 / 1.08300 (h).
12. **mochi — REMOVED from active library** (rejected at review; files
    on disk as history). Was: superellipse |t|^2.4, SQUASH 0.76,
    WIDEN 1.08.

Development incidents (fixed): the frontal-modulation pole pucker
(star/pebble/beanbag) — fixed in common via the smoothstep fade +
star's damped depth coupling and higher mesh resolution; a stray
mis-pathed batch output directory (see git-safety note in the phase
report) — outputs regenerated to the correct paths.

## Honest flags — resolved at the cleanup pass

The earlier flags (bean bow too modest; gourd waist ledge; the
beanbag/pebble/mochi squat cluster) were resolved by the user's
review: Bean strengthened to V2, Star rebuilt to V2, and Gourd /
Pebble / Mochi removed outright. No open flags on the active 15.

## Foot/leg placement pass (2026-08-16, library-wide)

One placement/anchor pass across all 15 active bodies — prototype limb
constants only; every BODY render was pixel-verified BYTE-IDENTICAL
before/after (Round, Pear, Beanbag), and no framing constant changed
anywhere (FOOT_Z − scale_z pinned per body). Verdicts:

- **Round V6 — modernized** (the last pre-architecture stance): tiny
  front-mounted pads (0.13, 0.125, 0.11 at y −0.42) → family plush
  pads (0.21, 0.17, 0.115) UNDER the body at centered depth (x 0.36,
  y −0.05, z 0.085) with the soft sole flatten; ARM_Y 0.05 → −0.08
  (the documented deferred arm fix — real 3D volume, no flat tab).
- **Pear V2 — stance/emergence**: x 0.32 → 0.34, y −0.05 → −0.08 (the
  full base was occluding the feet — the concern noted at the V2
  checkpoint, now resolved).
- **Beanbag — emergence**: foot_y −0.05 → −0.09 (visible under the
  settled slump).
- **Bean V3**: feet auto-follow the bowed axis (common pipeline).
- **No change needed** (already grounded, family-standard stance,
  documented as evaluated): Tall V14, Wide V2, Small V3, Egg V1,
  Dumpling, Teardrop, Puff, Oval, Heart, Star V2, Squircle.

## Limb placement / rig compatibility pass (2026-08-16, all 15 active)

Prototype limbs used as DIAGNOSTIC geometry only; this pass assessed
anchor position / depth / stance / floor contact per body. Evidence:
`preview_foot_placement_all.png` (lower-body crops, front),
`preview_diag34_all.png` (all 15 current 3/4s),
`preview_family_full_lineup_all.png` (world-scale lineup). ONE clear
problem found and fixed: **Star's feet were swallowed by its leg
lobes** → stance 0.38→0.46 + forward emergence foot_y −0.05→−0.12
("boots" under the lobes; framing unchanged, body render unchanged).
All other placements pass the bar (Wide's and Bean's feet are modest
but present — acceptable). Anchor metadata per body (world R units;
"auto" = family-standard derivation from the profile: eyes ~63% up,
arms ~36% up / flank−0.09 embed / Y −0.10 / tilt −53, feet under body
Y −0.05, soles at floor):

| body | rig (proposed) | arms (x, z) | feet (±x, y) | special metadata |
|---|---|---|---|---|
| round v6 | **A** (defining) | ±0.955, 0.72 (Y −0.08, tilt −35) | 0.36, −0.05 | none |
| small v3 | **A** (assigned) | ±0.72, 0.61 (Y −0.08, −54) | 0.29, −0.05 | world scale 0.86 |
| tall v14 | **B** (defining) | ±0.83, 0.82 (−55) | 0.34, −0.05 | none |
| wide v2 | **C** (defining) | ±1.10, 0.65 (−52) | 0.46, −0.05 | width-limited framing |
| egg v1 | **B** (leading) | ±0.85, 0.78 (−53) | 0.33, −0.05 | none |
| pear v2 | **B** (egg cohort) | ±0.86, 0.76 (−53) | 0.34, −0.08 | fwd foot bias (full base) |
| bean v11 | **B** + asym metadata | L (−0.66, 0.82) / R (+0.63, 0.74) | ±0.33 about axis(z), −0.05 | PER-SIDE arm anchors, axis-following feet/face (face_dx −0.16, eye_frac 0.66) |
| dumpling v1 | **A** | ±0.94, 0.65 | 0.41, −0.05 | none |
| teardrop v1 | **B** | ±0.82, 0.78 | 0.36, −0.05 | none |
| puff v1 | **A** | ±0.75, 0.74 | 0.28, −0.05 | face high (0.65) |
| beanbag v1 | **C** | ±0.99, 0.60 | 0.46, −0.09 | fwd foot bias (slump) |
| oval v1 | **B** | ±0.78, 0.81 | 0.29, −0.05 | none |
| heart v1 | **A** | ±0.80, 0.74 | 0.28, −0.05 | crown-dent zone (tuft z 1.93) |
| star v2 | **A** + lobe metadata | ±0.78, 0.72 | 0.46, −0.12 | arms from side lobes; feet under leg lobes |
| squircle v1 | **A**/C border | ±0.87, 0.72 | 0.50, −0.05 | wide stance |

Cohorts: Rig A (round-mid): round, small, dumpling, puff, heart, star,
squircle. Rig B (upright): tall, egg, pear, bean(+asym), teardrop,
oval. Rig C (broad): wide, beanbag. NO new rig needed — every body's
attachment topology is side-arms + under-feet; differences are
metadata (per-body anchors, Bean's per-side asymmetry, Star's lobe
alignment). All PENDING final confirmation at real limb-set testing;
nothing persisted.

## Rig-sharing recommendations (superseded by the table above)

- Upright cohort → likely Rig B language: egg (leading B), pear
  (egg cohort), teardrop, oval, bean.
- Round-ish mid cohort → likely Rig A language: dumpling, heart,
  puff, star, squircle (+ frozen small).
- Wide/squat cohort → likely Rig C language: beanbag.

All pending real limb-set testing; nothing persisted.

## Library evidence

- `Previews/preview_body_library_all.png` — the ACTIVE 15 bodies,
  body-only normalized grid (THE library sheet; excludes the removed
  gourd/pebble/mochi).
- `Previews/preview_family_full_lineup_all.png` — the active 15 full
  characters, common world scale, floors aligned (0.5 render scale).
- `preview_star_v1_vs_v2_body_only.png`,
  `preview_bean_v1_vs_v2_body_only.png` — refinement evidence.
- Per-body: `Renders/body_<name>_candidate.png`, `tuft_00_<name>.png`,
  `limbs_<name>_proto_00.png`, `body_<name>_candidate_with_tuft.png`,
  `Previews/preview_<name>_full.png`,
  `Previews/preview_<name>_v1_diagnostic_34.png` (3/4),
  `Source/<name>_aurie_master.blend`.

## Re-run (any candidate)

```
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --factory-startup --python-exit-code 1 \
  --python Design/Aurie3D/Scripts/build_<name>_aurie.py -- \
  --outdir "$(pwd)/Design/Aurie3D"
python3 Design/Aurie3D/Scripts/verify_candidate_renders.py <name>
```

## Guardrails honored

Frozen Round V6 / Tall V14 / Wide V2 / Small V3 / Egg V1 / Pear V2
untouched (fingerprints verified). No BodyType enum changes. No app
integration. No final limb sets. Nothing staged or committed.

## Correction pass (2026-08-16, post rig assessment)

- **Round V6**: proud cheeks -> conforming patches (the actual source
  of the pink-past-silhouette artifact at 3/4; 143 -> 0 near-edge
  pink px). Look preserved; body byte-identical.
- **Pear V2**: verified ALREADY CLEAN (0 near-edge pink in the current
  3/4) — the reported artifact was the stale pre-foot-pass diagnostic.
- **Wide V2 feet**: stance 0.46 -> 0.50, y -0.05 -> -0.09 (broad body
  was swallowing them). Body byte-identical, framing unchanged.
- **Bean V11 feet**: stance 0.33 -> 0.38, y -0.05 -> -0.10 (shifted
  lower lobe masked the right foot). Body byte-identical.
- **Beanbag**: left alone (already forward-biased; reads acceptably).
- **Star V2**: left alone (fixed in the rig-assessment pass).
- **Bean cheek**: 24 near-edge pink px inspected — on-surface wrap at
  the cave-side limb, fades at the edge, no protrusion; acceptable.
