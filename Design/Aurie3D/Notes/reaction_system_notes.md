# AURIE REACTION SYSTEM — 8 reusable reactions + family weighting

STATUS 2026-08-17: first pass, awaiting review. The 10 base expressions
are FROZEN (approved); this pass adds temporary reactions on top of them.

## THREE SEPARATE THINGS (the whole point of the design)

1. **Base / personality expression** — one of the ten, chosen at hatch,
   PERSISTED, never rerolled. `BaseExpression` in
   `Auries/Models/AurieExpressions.swift`.
2. **Temporary reaction face** — borrowed for a moment, never saved.
   Three reaction-only faces exist (`dizzy`, `yawn`, `calm`); the rest of
   the reactions reuse base expressions as their peak face.
3. **Reusable body reaction** — body-relative pose keyframes in
   `Scripts/aurie_reactions.py`, one library for every body and every
   base expression.

`VisibleFace` holds base + optional reaction and always resolves back to
the base when the reaction ends. Nothing about a reaction is written to
disk, so a tap or a shake can never change an Aurie's personality.

## BUILT ON THE EXISTING APP SEAM, NOT BESIDE IT

`AurieNode` already owns squash, hop, tilt, arm and eye actions plus a
duration-based `setExpression(_:for:)`, and `CreatureScene` already
triggers reactions on tap/shake. So this pass adds the DATA (which face,
which pose, which priority, how long) and leaves the SKAction vocabulary
alone. Durations in `AurieReaction.duration` are the values the art was
posed for, not a new timing system.

## POSE VALUES ARE BODY-RELATIVE

`dy` is a fraction of that body's own height, `sx`/`sz` squash about the
FEET (not the centre), `tilt` is small, `arms` rotate about each arm's
own anchor. One library therefore covers Round/Tall/Pear/Beanbag with no
per-body assets — verified in `preview_reaction_bodies.png`.

## PRIORITY

high 30: excited hop, dizzy, startled — interrupt anything
med  20: happy bounce, curious look, calm settle — interrupt idle only
low  10: blink, sleepy yawn
Blink never displaces a reaction in progress; only one temporary facial
override is ever active; the stack always unwinds to the saved base.

## TWO DEFECTS FOUND BY ACTUALLY RUNNING THINGS

1. **Idle bias was silently dead for three families.** Ember, Glow and
   Starlight list Happy Bounce / Excited Hop as their idle tendencies,
   but both were classified event-only, so `idleReactionWeights` filtered
   them out and those families came back perfectly flat. Fixed by making
   Happy Bounce idle-eligible (a small self-bounce is fine unprompted)
   while keeping Excited Hop event-only so celebrations stay special —
   with `positiveReaction(family:)` letting those families escalate a tap
   into a hop (~33% vs ~17%).
2. **Stale parent matrix wiped the face.** The render harness posed the
   pivot and then read `pivot.matrix_world` to compute each face patch's
   parent inverse. Blender evaluates that matrix lazily, so every frame
   following a transformed frame used the PREVIOUS pose's matrix and the
   face landed off the body. Fixed by rebuilding the face at identity,
   parenting with an identity inverse, and only then applying the pose.
   (Same lazy-evaluation trap as the earlier leg-symmetry probe — worth
   remembering: never read a matrix you just set.)

## VERIFICATION

`swiftc Auries/Models/AurieExpressions.swift AurieModels.swift main.swift`
compiles and runs the sanity test against the REAL shipping table (not a
copy): 20 000 seeded hatches per family show the intended tendencies,
every expression stays reachable in every family, no family exceeds 35%
on its top expression, and the same seed always yields the same
expression (so pre-existing saves resolve stably rather than rerolling).

## NOT DONE

`Aurie.baseExpression` is not yet a stored property — the selection is
deterministic in the existing `seed`, so adding the field is a one-line
optional addition when the hatch flow is wired. Scene wiring
(`CreatureScene` calling the new reactions), Wonderglobe particles/UI,
patterns, charms and inter-expression morphing are all out of scope here.

---

## APP INTEGRATION (2026-08-18) — done and verified in the simulator

Files changed: `Models/AurieExpressions.swift` (new), `Models/AurieModels.swift`,
`Services/Store.swift`, `Generation/AurieGenerator.swift`,
`Scenes/AurieNode.swift`, `Scenes/CreatureScene.swift`, `App/AppModel.swift`.

**Persistence.** `Aurie.baseExpression` is a stored Optional — non-optional
would throw on old JSON and, given Store's `?? []`, silently wipe the whole
collection. New hatches assign it from the family table using the creature's
own seeded RNG. `Store.migrateBaseExpressions()` fills in nil values once on
load and writes them back, so changing the weights later can never repaint an
existing creature. Verified in the running app: stripped the field from
`auries.json`, launched, and the values were resolved, written to disk, and
identical on the next launch.

**Two integration bugs found and fixed (both would have erased personality):**
1. The idle blink reopened the eyes to scale 1.0, so the first blink flattened
   a Sleepy or Delighted base face. It now reopens to the base face's own
   resting scale and skips entirely while a reaction is playing.
2. The legacy `setExpression` paths (pet, tickle, pick-up) also ended at 1.0.
   Every branch now ends by restoring the saved base face.

**Debug hooks** (DEBUG-only, env-gated, off by default):
`AURIE_REACTION_SELFTEST=1` drives the real tap/shake/celebration entry points
and logs what the creature is wearing at each step; `AURIE_HATCH_SAMPLES=<n>`
hatches n creatures through the real generator and logs family/expression.
They exist because there is no UI-test target and this environment cannot tap
the simulator; delete them once a test target exists.

## FACE RENDERER FIX (2026-08-18) — the expressions were not reaching the screen

**Diagnosis.** The reaction state machine was correct (logs proved the right
face id at every step) but it drove a renderer that could not express
anything. The visible face was two BAKED bitmaps: `eyesNode` held one texture
with BOTH eyes drawn into it (`AssetLoader.placeholderEyes`), and `mouthNode`
held a mouth chosen from `parts.mouthId` at hatch. The first `applyFace` only
set scale/rotation on the eye sprite, and never touched the mouth node at all.
So: the mouth was literally constant in every frame, and a uniformly scaled
eye-pair bitmap cannot produce a narrowed lid, a tilted eye, crossed eyes, or
a crescent. Every expression rendered as the same face.

**Fix.** `Services/AurieFaceRenderer.swift` draws each face as real geometry
with Core Graphics — per-eye size, lid clip, mirrored tilt, gaze/cross offset,
closed crescents, catchlights (with a dizzy swirl variant), and six mouth
treatments (smile / tiny / open / round / wavy / frown / smirk). `applyFace`
now swaps BOTH the eye and mouth textures; the node transform returns to rest,
so blink still squashes from a clean 1.0 and skips faces that are already
closed. Follows the approved 3D catalogue's language rather than a second one.

Evidence from the running app: `preview_app_face_parade.png` (six faces, 2s
each, no body animation) and `preview_app_reaction_frames.png` (the five-frame
reaction sequence). Capture note: screenshots initially raced the animation —
the first attempt caught the tap peak and mislabelled it as the base face — so
`AURIE_REACTION_FRAMES=1` holds each state for 3s and the capture script polls
the log for each marker before shooting.

## DIZZY MOTION: 2D-SAFE WOBBLE FOR BLENDER SKINS (2026-08-18)

The shake reaction used a full 360° spin (`reactTumble`). That was fine for
the old placeholder blob, but the Blender skin is flat front-facing layers:
past roughly 90° the parts stay rigidly attached yet stop reading as one
creature, because each layer was rendered for a single viewing angle. In
capture it looked like limbs flying off — diagnosed as neither particles
(reproduced across families), nor the holdout matte (leg alpha tops measured
rounded, not flat-cut), nor layer order.

`reactTumble` now branches: Reduce Motion keeps its tiny steadying wobble,
a Blender-skinned creature gets `dizzyWobble()`, and the placeholder path
keeps the original spin untouched.

`dizzyWobble()` — peak rotation **0.21 rad (12°)**, four decaying alternating
swings plus a return to exactly 0, a ±12 pt horizontal give on its own action
key so it reads as momentum rather than a hinge, and one squash/stretch on the
way out. Total ~0.77 s, matching the previous beat, so reaction timing,
priorities, the shake trigger, the Dizzy face and return-to-base are all
unchanged.

Verified in the running app on round/tall/pear/beanbag/heart:
`preview_app_dizzy_wobble.png` (base → shake midpoint → settled → restored).
