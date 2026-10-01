# PEAR — BODY FROZEN AT V2 (rig assignment pending, 2026-08-16)

**The Pear v2 BODY and face/render architecture are the canonical
approved Pear baseline.** v2 was selected because it delivers the
strong bottom-heavy Pear identity with the best balance of side
curvature and softness; the later v3/v4 explorations did not improve
on it enough to justify continuing and are recorded as rejected
history. The renders on disk ARE v2 — restored deterministically from
the exact approved v2 implementation and verified BYTE-IDENTICAL to
the preserved v2 body render (pixel diff: none). RIG ASSIGNMENT
PENDING. Candidate naming (no numeric body index). Round v6, Tall v14,
Wide v2, Small v3, and Egg v1 remain separately frozen.

## Frozen / approved — body (v2)

Localized smooth hip-bulge architecture — `pear_width(t) = BODY_WIDEN
· hips · taper · base · side` with `hips = 1 + HIP_FULL·cos²(π/2·
min(1, |t−HIP_CENTER|/HIP_SPREAD))` (C¹-smooth window: no seam, no
waist — a width PEAK, not v1's plateau):

- `PEAR_STRETCH 1.06`, `BODY_WIDEN 0.90`
- `HIP_FULL 0.18`, `HIP_CENTER -0.40`, `HIP_SPREAD 0.72`
- `UPPER_TAPER 0.30`, `TAPER_EASE 1.5`
- `BASE_FULL 0.04`, `BASE_START 0.55`
- `SIDE_FILL 0.03`
- `BOTTOM_FLATTEN 0.02`, `BOTTOM_FLAT_START -0.5`
- `BODY_LIFT 1.049` (bottom at +0.010)

Measured: body 2.099 × 1.895 R → **H/W ≈ 1.107**; **widest region
≈ 65% down the body (t ≈ −0.30)**, ≈ 0.32 R below the geometric
center; upper/lower thirds ratio 0.750; one soft width maximum
(2%-of-max span t −0.41..−0.17); flank at t −0.7 holds 76% of max
(v1's plateau held 87%). Normal family world scale, Round/Egg mass
class (world bounds 2.35 × 2.24 R incl. limbs/tuft).

EGG vs PEAR distinction (both frozen): Egg is the MODERATE
bottom-heavy body — smoother, more continuous, max width t −0.18,
upper/lower 0.894; Pear pushes the mass distribution substantially
further — visibly smaller upper body, max width t −0.30, upper/lower
0.750, broader lower-middle. Instantly distinguishable body-only.

## Frozen / approved — face, tuft, framing, look

Surface-conforming face system with Pear-specific anchors: EYE
(0.112, 0.156) at (**±0.21**, 1.36) — ~64.5% up, spacing ~0.29 of the
eye-height flank 0.728; MOUTH_Z 1.08 (family 0.28 R gap), bevel 0.011;
CHEEK (0.19, 0.085) at (±0.40, 1.10); sheen/catchlight/eye-shader
constants identical to the family; epsilons 0.003/+0.001/+0.002. Tuft
(family design/scale, separate canonical asset): MID (0.15, 0.15,
0.20) z 2.14, SIDE (0.125, 0.125, 0.165) x 0.145, z (2.10, 2.08),
tilt (22, 30). Height-limited framing: FRAME_FILL 0.66 → ortho_scale
3.59242, cam z 1.15450 (verifier ORTHO/CAM_Z track this). Family
material #97C9EF / lights 300/90/150 W / Standard view transform.

## LIMBS — PROTOTYPE ONLY

`limbs_pear_proto_00` is a rig-neutral Tiny Stubby PROTOTYPE
(attachment zones / registration / balance only). Prototype arms
(0.16, 0.13, 0.30) at X 0.86 / Y −0.10 / Z 0.76, tilt −53; prototype
feet (0.24, 0.19, 0.13) at **X 0.32** / Y −0.05 / Z 0.099, flatten
0.24 / start −0.5. Future Pear limb sets may change every value.

## Rig assessment — PENDING

UNDECIDED; **likely cohort with Egg** (nearly identical vertical
anchor layout: face ~64.5% vs ~63% up, arms ~36% up both, feet under
base) — decide after real limb-set testing on the Egg/Pear cohort.
Egg's leading candidate is Rig B. No Rig D warranted. Nothing
persisted or hard-coded.

## Version history

- **v1 (HISTORICAL)**: monotonic `HIP_FULL 0.34 / HIP_EASE 1.6`,
  `UPPER_TAPER 0.30/1.5`, `BASE_FULL 0.06/0.6`, `SIDE_FILL 0.05`;
  H/W 1.107, max 64.8% down, thirds 0.792; EYE_X 0.22, FOOT_X 0.36.
  Rejected: width plateau (t −0.49..−0.14) → straight gumdrop
  sidewalls.
- **v2 (CANONICAL)**: the localized hip bulge above. Correct fix.
- **v3 (REJECTED exploration)**: crown-concentrated taper
  (`UPPER_TAPER 0.25/ease 2.6`, `WIDEN 0.86`, `HIP_CENTER −0.43`) —
  metrics moved but the silhouette read essentially the same as v2.
- **v4 (REJECTED exploration)**: explicit PCHIP width-profile
  architecture (control-point silhouette, cap-safe S-space spline) —
  produced a genuinely different curved-shoulder read, but judged not
  an improvement over v2's balance. The PCHIP machinery itself is
  sound and available for future bodies.
- Evidence preserved: `preview_pear_v1_vs_v2_body_only.png`,
  `preview_pear_v2_vs_v3_body_only.png`,
  `preview_pear_v2_vs_v4_body_only.png`,
  `preview_body_shapes_egg_pearv1_pearv2.png`,
  `preview_body_shapes_egg_pearv1_v2_v3.png`,
  `preview_body_shapes_egg_pearv2_pearv4.png`,
  `preview_egg_vs_pear_body_only.png`,
  `preview_body_shapes_round_egg_pear.png`,
  `preview_family_six_world_scale_pear_v1.png`, and the four 3/4
  diagnostics (v1 restored, v2, v3, v4).

## Verification (v2 restored, read-only)

ALL CHECKS PASSED — height 65.3%, world bounds h=2.35 / w=2.24 R,
centered x=512.0, bbox (193, 173, 831, 842), body metrics H/W 1.107 /
max width 64.7% down / thirds 0.750, alpha counts preview 254632 /
body 232781 / tuft 14160 / limbs 40257 / body+tuft 241441, ≤1 px
registration outside, soles at the floor. Restored body render
byte-identical to the preserved v2 backup.

## Files

- `Scripts/build_pear_aurie.py` (v2), `Scripts/verify_pear_renders.py`
- `Renders/body_pear_candidate.png`, `Renders/tuft_00_pear.png`,
  `Renders/limbs_pear_proto_00.png` (PROTOTYPE),
  `Renders/body_pear_candidate_with_tuft.png`
- `Previews/preview_pear_full.png`, `Source/pear_aurie_master.blend`
- `Notes/pear_aurie_v1_notes.md` (this checkpoint document)

## Re-run

```
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --factory-startup --python-exit-code 1 \
  --python Design/Aurie3D/Scripts/build_pear_aurie.py -- \
  --outdir "$(pwd)/Design/Aurie3D"
python3 Design/Aurie3D/Scripts/verify_pear_renders.py
```

## Process rules (inherited)

Anchors recompute at NORMALIZED body positions; face artwork conforms
to the surface (epsilons z-fighting-only); feet under the body near
mid-depth; arms side-mounted below the face; limb sets = body/rig-
specific artwork + per-set tuning.

## 2026-08-16 foot/leg placement pass (PROTOTYPE LIMBS ONLY)

Library-wide placement pass, user-directed: FOOT_X 0.32 -> 0.34,
FOOT_Y -0.05 -> -0.08 — resolves the checkpoint-noted front occlusion
of the feet by the full base. Framing unchanged; the frozen V2 BODY
render was pixel-verified BYTE-IDENTICAL after the rebuild.
