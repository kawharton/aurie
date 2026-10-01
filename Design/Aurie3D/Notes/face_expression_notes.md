# AURIE EXPRESSION LIBRARY — 10 launch expressions + blink (2026-08-17)

STATUS: **FROZEN 2026-08-17** — the ten are approved as the launch
catalog. Do not restyle them; reactions layer on top (see
`reaction_system_notes.md`). Bodies, limbs, materials,
lighting and framing untouched. Implemented in
`Scripts/aurie_face_expressions.py`; render harness
`scratchpad/expr_pass.py`; sheets `preview_expressions_round.png`,
`preview_expressions_bodies.png`, `preview_blink_test.png`.

## ARCHITECTURE

Expressions are built ON the existing surface-conforming face system,
not beside it. Every element is a patch or ribbon projected onto the
body's own front surface with the family epsilon policy (0.003 body,
+0.001 sheen, +0.002 catchlights), so one parameter set lands correctly
on any silhouette. Three primitives only — charcoal eye patch, ribbon
or filled mouth, blush patch — so no expression can drift out of
species. No eyebrows, no teeth, no new materials.

An expression may vary: eye scale, eye tilt, lid coverage (including
per-eye), gaze offset, mouth treatment, blush strength.

## BLINK

`blink` (0..1) raises the same lid the expressions already use, so one
parameter serves every expression and there is no second pipeline:
- lid clip happens in the ellipse's parameter space BEFORE conforming,
  so a closing eye keeps sitting on the surface instead of shearing off;
- the lid edge carries a shallow 0.16 rz arc so it reads as an eyelid;
- catchlights above the lid edge are dropped (otherwise they float on
  the skin above a half-closed eye);
- at blink >= 0.86 the patch is replaced by a thin lash ribbon on the
  same conformed path;
- expressions whose eyes are already arcs (`delighted`) ignore blink,
  which is the sensible handling rather than forcing a standard blink.
Mouth and blush are untouched by blink, so the expression survives it.

## TWO DEFECTS FOUND AND FIXED IN THIS PASS

1. **Round's eye material is legacy.** Round is the only body still
   building proud ellipsoid eyes; its eye material is tuned for that
   curvature. On a flat conforming patch it mirrored the light rig as a
   hard-edged wedge across the whole eye. `tune_eye_material()` forces
   the family conforming spec (roughness 0.42, specular 0.10, no
   metallic/coat) — the "never mirror-glossy" rule this face system was
   built on.
2. **Round has no `AurieEyeSheen` material.** Substituting the
   catchlight material painted an opaque white blob over one eye; the
   sheen patch is now skipped when a body does not provide it. Round's
   eyes therefore read very slightly flatter than the other bodies —
   worth resolving if Round's face is ever brought onto the modern path.

Harness lesson (cost one silent failure): the leg style raises the body
by `LEG_BODY_LIFT`, but each body's `body_surface_y` describes the body
in its BUILT frame. The conform closure must be created after the lift
and subtract it, or every face patch is projected onto the unlifted
surface and ends up buried inside the mesh — invisible, no error.

## THE TEN

| id | label | eyes | mouth | blush |
|----|-------|------|-------|-------|
| happy | Classic Happy | full ellipse, open | ribbon smile | 1.00 |
| excited | Excited | 1.08x1.12, big catchlights | filled open smile | 1.30 |
| sleepy | Sleepy | lid 0.62, slight down-tilt | tiny short smile | 0.85 |
| shy | Shy | lid 0.30, gaze off-axis + down | tiny narrow smile | 1.75 |
| curious | Curious | asymmetric lid (R 0.22), gaze up | small round "o" | 1.00 |
| surprised | Surprised | 1.14x1.18, widest | full round "o" | 0.75 |
| mischievous | Mischievous | lid 0.34, +9 deg outer-corner tilt | one-sided smirk | 1.05 |
| worried | Worried | -11 deg down-and-in tilt, lid 0.12 | wavering ribbon | 0.85 |
| pouty | Pouty | lid 0.22, slight squint | inverted arc | 1.20 |
| delighted | Big Happy | closed happy arcs (ignores blink) | widest open smile | 1.45 |

## NOT DONE / OPEN

Not started: patterns, charms, randomization, animation between
expressions, propagation beyond the four test bodies (round, tall,
pear, heart). Curious vs Surprised separate mainly on mouth size at
app scale — if that proves too subtle in the app, widen the gap by
tilting Curious's eyes rather than growing Surprised further.
