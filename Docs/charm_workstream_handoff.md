# Charm workstream — durable handoff (2026-09-16)

Continuation brief for the charm/belly workstream. Every path and git
fact below was VERIFIED against the repo at write time, not recalled.

STANDING RULES (never expire)
- **NEVER commit. The user makes every Git commit personally.**
- Stop at visual review gates; small proofs, not big batches.
- When something is approved, FREEZE it and move on.
- If a visual result is weak, say so directly; don't defend it.
- The user is not a Blender expert: deliver deterministic headless
  `bpy` scripts, never manual-modelling instructions. Production stays
  on scripted pipelines (Blender MCP is for inspection, not production).

## 1. GIT STATE (verified)

- Branch: `aurie-art`
- HEAD: **`c9eb1ec` "Add backpack and belly charm foundations"**
  (author kawharton, 2026-09-16 11:12 -0400 — the charm checkpoint IS
  committed; 154 files, +19,393/−36)
- Prior: `33620a2` Home-movement turning, `d6d6978` front/back orientations.
- Nothing staged. Working tree after the checkpoint has ONLY
  intentionally-untracked files:
  - `.claude/` (local skills config — deliberately out)
  - `Design/Aurie3D/Source/*.blend` — 9 experiment/master blends
    (gourd/mochi/pebble masters, hair + metaball leg experiments)
  - `Design/Environments/` — 9 unrelated PNGs (dusk2, ember2, ember3,
    glow2, moss2, starlight2, stone3, tide2, master_composition_template)
    — valuable art, deserves its own separate commit
  - plus one NEW untracked file: `Docs/charm_workstream_handoff.md`
    (this document)

Hygiene decisions in force (all verified in `.gitignore`):
- `.Rhistory` ignored (line 178; a stray `AurieCharmLibrary/.Rhistory`
  exists on disk, ignored, uncommitted)
- `AurieCharmLibrary/_PROCESSED/` ignored (66 MB derived .blend masters)
- `Design/WorryJar/Export/` and `Design/WorryJar/Review/` ignored
- the old broad rule `Design/Aurie3D/Scripts/charm*` was REMOVED —
  it hid seven real source files; a warning comment marks the spot.
  Do not reintroduce wildcards that can hide future source.
- `charm_inventory.csv` is authoritative hand-authored editorial input
  (LaunchStatus + curatorial notes, read by charm_library.py) — TRACKED.
- `aurie-review-evidence/`, `Design/Aurie3D/Export/`, `build/` ignored.

What the checkpoint contains (spot-verified): the 8 modified Swift/
pipeline files, `CharmModels.swift`, `CharmCollection.swift`, promoted
belly scripts, all 7 charm tooling scripts + inventory csv,
`export_charm_layers.py`, both Round backpack imagesets,
`AurieCharmLibrary/` light source (README, 8,689-line
`_MANIFESTS/charms.json`, licences, checksums, 60 thumbnails),
`Design/Belly/belly_circle.png`, both Docs audits, `.gitignore`.

## 2. BACKPACK / BACK CHARM — APPROVED & FROZEN

`charm_object_backpack_01`, placement BACK. All 10 body fits visually
approved. Construction (do not redesign):
- molded strap shell REMOVED from the source (1,564 faces, two shells —
  found by component census, not threshold)
- original strap mesh used ONLY to harvest real top/bottom attachment
  roots, then deleted — one clean generated harness remains
- straps are continuous 3D loops: top pack root → over shoulder → down
  front/outer torso → UNDER the arm → around the body → bottom pack root
- arms sit outside/in front of straps; strap tails penetrate the pack
  (no gaps); pack leans inward ~12°
- pack may overlap hair; hair is NEVER altered for an accessory
- Beanbag fit corrected; the duplicate-arm illusion fixed
- Round keeps its frozen analytic-ellipse ring fit; other bodies use
  smoothed mesh-sampled profiles

PRODUCTION: ALL 10 bodies' front/back imagesets installed 2026-09-17
(the 9 missing bodies were exported + installed during the equipment
bug-fix pass; the caveat below is HISTORICAL). Originally only ROUND
front/back imagesets were installed (`Auries/Assets.xcassets/AurieBlender/aurie_round_charm_object_backpack_01{,_back}.imageset`).
The other nine bodies exist as approved review renders only — the
9-body production install is future work.

## 3. BELLY AREA — APPROVED (all 10 bodies), NOT YET IN APP

A BODY-PRESENTATION feature, not a charm. 2D, front-only, generated,
body-relative, no hand-written Swift coordinates, absent on the back.

- Layer recipe: `belly.rgb` = body's own beauty render; `belly.a` =
  body alpha × soft zone falloff × peak. Tinted with a PALER family
  colour. Nothing multiplies luminance (the earlier "spotlight"
  luminance-mask approach was rejected — never revive it).
- Zone derivation (in `build_pattern_masks.py`, `--zone belly`,
  `belly_params()`): band_top = mouth_z − 0.10·height; band_bot =
  bottom + 0.02·height; constants BELLY_FILL_V 1.37, BELLY_HALFW 0.338
  (~58% silhouette width... user chose "wider at 60%"), depth scale
  1.85. Uses PRE-LIFT measurements (lift/anchor frame mismatch trap).
- Approved treatment: plain peak 0.85 / paleness 0.52; patterned peak
  1.00 / paleness 0.38 — on patterned bodies the belly OCCLUDES the
  markings (residual stripe 0.07 ≈ invisible); outside pattern untouched.
- The proof-rig 48 px pattern-registration bug was found (by the user)
  and fixed — proof patterns now render in the same lifted scene.
  Production was never affected (installer crops all masks to the body
  bbox).

Promoted reproducible source (verified paths, all committed):
- `Design/Aurie3D/Scripts/aurie_belly.py` — belly compositing,
  bellyCore, occlusion constants (PRODUCTION reference; Swift must
  reproduce it exactly)
- `Design/Aurie3D/Scripts/aurie_belly_stickers.py` — sticker catalog,
  fit, grade, trims (PRODUCTION reference)
- `Design/Aurie3D/Scripts/review_belly_render.py` — REVIEW TOOLING
  ONLY; regenerates the evidence passes (body/parts/belly/pattern per
  yaw, pixel-registered)

NOT DONE: no belly imagesets exist in `Auries/Assets.xcassets`
(verified) — installer emission of the belly layer + `bellyCore`
metadata and all Swift wiring are pending, deliberately after the
sticker freeze.

## 4. BELLY STICKERS — APPROVED DIRECTION, one tiny fix left

Flat 2D PNG decals. One transparent PNG per sticker (the library's
`_THUMBNAILS/<id>.png`, 512², one camera — so a new charm costs ONE
preview). Placement: centred on the body-specific `bellyCore` (zone
alpha>0.5 ∩ body bbox). Front-only. NO white outline, NO drop shadow,
NO border. Untinted apart from the grade.

APPROVED GLOBAL PRESENTATION (in `aurie_belly_stickers.py`):

    STICKER_SIZE = 0.72          # 0.75 too dominant, 0.65 too small on phone
    scale = min(0.62·coreW/w, 0.88·coreH/h) × 0.72   # two-axis fit
    GRADE = dict(lift=0.165, contrast=0.955, sat=1.225, val=0.935)
    # = EXTRA SOFT PASTEL. Shadow lift runs FIRST (it dissolves the
    # baked 3D shading); sat>1 restores colour the lift bleached;
    # val<1 trims the over-delivered brightness.
    # Measured: sat −18.7%, value +10.1%, contrast −25.4%,
    # darkest decile lifted +46..+93%.

Goal: "soft Aurie belly sticker", NOT "miniature 3D prop".

APPROVED SET — EIGHT (Clownfish REMOVED: read badly at belly scale):
1. Apple `charm_food_apple_01`
2. Pumpkin `charm_nature_pumpkin_01`
3. Pizza `charm_food_pizza_01`
4. Crystal `charm_magic_crystal_02` (crystal_01 unprocessed)
5. Star `charm_magic_star_01`
6. Pink Blossom `charm_nature_flower_03` (NOT rejected long-stem flower_02)
7. Tomato `charm_food_tomato_01`
8. Star Coin `charm_magic_star_coin_01`

PER-CHARM TRIM mechanism (`CHARM_TRIM` + `style_for`) — keep it; it is
the correct way to fix outliers without touching the shared grade.
Current trims (found via HSV value/peak-highlight, NOT mean luminance,
which missed all three):

    charm_magic_crystal_02  val×0.88 sat×0.90
    charm_nature_flower_03  val×0.87 sat×0.88
    charm_food_tomato_01    val×0.90 sat×0.90

Verification at final settings: 0.0% sticker ink outside the pale core
for every sticker on every body; front-only confirmed (zone max 0.0039
at 135°/180°). Evidence in `aurie-review-evidence/belly_area/`:
`belly_stickers_final_round.png`, `belly_sticker_final_rollout.png`,
`belly_sticker_final_sanity.png`, `belly_sticker_brightness_trim.png`,
plus reports `BELLY_STICKER_REPORT.md`, `BELLY_STICKER_STYLE_REPORT.md`,
`BELLY_2D_DESIGN.md`, `BELLY_AREA_REPORT.md`, `BELLY_ROLLOUT_REPORT.md`.

## 5. NEXT VISUAL TASK — VERY SMALL, then freeze

Two sticker corrections ONLY (no resizes, no global changes, other six
untouched unless a render reveals a clear issue):
- PUMPKIN: slightly muddy/brown → brighten slightly, recover a little
  orange saturation. Expressible TODAY as a `CHARM_TRIM` entry with
  val>1 / sat>1.
- TOMATO: still slightly 3D-object → lift the dark lower shadow a bit
  more. **Implementation note:** `style_for()` currently folds only
  `val` and `sat` from a trim — it does NOT fold `lift`. The Tomato
  fix therefore needs a one-line extension so trims can carry
  `lift` (and optionally `contrast`) before a per-charm lift works.

After these two: belly-sticker visual tuning is FROZEN. New sticker
PNGs can be added later without blocking anything.

## 6. CHARM DATA / OWNERSHIP ARCHITECTURE (committed at c9eb1ec)

Types: `CharmDefinition`, `AurieCharmCatalog` (hand-written, 2 entries,
PoC), `CharmCollection` + `CharmService`
(`Auries/Services/CharmCollection.swift` → charms.json beside
wallet.json), `EquippedCharm`, `Aurie.equippedCharms: [EquippedCharm]?`,
`Store.update(_:)`.

Ownership rules (already correctly implemented — keep):
- account-level, quantity-free, non-consuming
- deleting an Aurie NEVER removes unlocks
- one unlocked charm usable on any number of compatible Auries
- ALL acquisition paths go through the same idempotent
  `CharmService.unlock(...)`; `processedGrantIds` ledger exists for
  grant idempotency
- `EquippedCharm` = {charmID, slot as String, side?} with lenient
  decode. Do NOT replace with a `[String:String]` dictionary — array
  records leave room for future placement metadata.

## 7. THREE CONCEPTS — NEVER COLLAPSE

A. PLACEMENT (where worn): belly, back, head, bodySide, shoulder, neck,
   forehead, cheek, arm, wrist, leg, ankle, floating, aura, tail,
   hanging. Representable in DATA now; build visual pipelines only when
   they exist (launch: belly, back).
B. THEME/CATEGORY (what it is): data-driven stable string IDs +
   separate display names, MULTI-TAG (apple = food, fruit_vegetables,
   nature). NO giant Swift enum/switch. Example catalog: Animals & Pets,
   Wildlife, Ocean & Sea Life, Food, Fruit & Vegetables, Health &
   Medical, Sports, Art, Music, Science, Chemistry, Biology, Space &
   Astronomy, Technology, Books & Reading, Nature, Flowers & Plants,
   Travel, Transportation, Fantasy & Magic, Games & Toys, Holidays,
   Love & Friendship, …
C. ACQUISITION SOURCE (how unlocked): birthPhoto, taskReward,
   achievement, event, seasonal, starter, discovery, futureShop.
   **Birth Charm is an acquisition source, NOT a theme.**

## 8. AUDIT FINDINGS (full text: `Docs/charm_architecture_audit.md`,
   plus `Docs/birth_charms_architecture_audit.md` — both committed)

- Evolve `CharmDefinition`: `category: String` → `categories: [String]`
  (today it holds the LIBRARY FOLDER, a provenance artifact);
  `slot` → `placements: [String]` (+ missing `belly` case);
  `acquisition: String` → `acquisitionSources: [String]`; add
  `birthTriggerIDs: [String]`.
- LOW migration risk: `CharmDefinition` is in-memory catalog metadata;
  the persisted surface (`EquippedCharm` + id sets) is already the
  right shape and does not change.
- The catalog must eventually be GENERATED from the manifest (like
  AurieBlenderAssets.swift), and the product taxonomy must live in an
  AUTHORING file the charm processor never overwrites — generated
  processing output must not become the source of truth for editorial
  metadata.
- Unknown ids already fail safe (equipped: renders bare; unlocked:
  harmless) — needed because many current library charms may be removed.

## 9. BIRTH CHARMS — PHASE D PROOF SHIPPED (2026-09-18, Apple only)

A Birth Charm is an ACQUISITION ORIGIN, never a permanent body feature.
The Apple end-to-end proof is implemented; the trigger CATALOG remains
deliberately one entry until the product owner expands it.

- `Aurie.birthCharmID: String?` (AurieModels) — provenance stamped in
  `commitHatch` before the save, never rewritten; old saves decode nil,
  nil is omitted on encode. NOT an equipment slot: the newborn merely
  STARTS with the charm equipped through the ordinary product rule.
- Matching: `AurieCharmCatalog.birthTrigger(forCanonicalLabel:)` over
  the generated trigger table; `AppModel.birthTrigger(for:)` mirrors
  the GENERATOR'S acceptance gate (confidence ≥ threshold, category !=
  .unknown) so provenance always agrees with the displayed bornFrom.
  `birth_apple` accepts exactly ["apple"] — the canonical hero label
  (audited: "Granny Smith" canonicalizes to it; raw variants never
  reach RecognizedObject.label).
- Transaction: `prospectiveBirthCharmID(for:)` is the preview (writes
  nothing); `commitHatch` stamps provenance + calls the private
  `applyBirthReward`, which is ledger-guarded per hatch
  (`CharmService.processGrant("birth:<aurieID>", unlocking:)`) — a
  replayed commit rewards nothing and never overwrites the player's
  later outfit. Auto-equip goes through the SAME `equipCharm`; a
  missing definition/unsupported placement skips the outfit but KEEPS
  unlock + provenance.
- Proof: harness birth tests (matching + ledger) in
  Tools/charm-tests; AURIE_BIRTH_PROOF=1 runtime selftest (28 checks,
  numbered to the Phase D requirement list) runs the full no-lock-in
  sequence through the real pipeline on a fresh install.
- D2 PRODUCTION WIRING (2026-09-19): the approved borderless 2.5D
  sticker family is PRODUCTION. 12 masters (Design/Charms/Masters,
  extracted by Scripts/extract_birth_masters.py from the final
  birth_charms_stickers.png sheet) install via Scripts/
  install_2d_stickers.py with per-sticker TUNING (sticker_tuning.py:
  scale + visual-centring offsets, baked by canvas geometry — runtime
  untouched). Apple's imageset was REPLACED in place (same id/asset
  name; provenance/ownership/saves/trigger untouched); the legacy
  install_belly_stickers.py skips apple and can no longer clobber the
  2D sets. Catalog: 21 charms; triggers: apple + teddy + mug +
  cup→teacup (STABLE HERO LABELS ONLY — the other 8 stickers await
  approval of hero-promotions in Recognition before wiring).
- D2 DROP RULE (2026-09-19): a qualifying recognition is ELIGIBILITY,
  not a grant — one deterministic 50% roll per hatch
  (AppModel.birthCharmDropChance; splitmix64 of the creature's seed,
  replay-stable, nothing extra persisted). Failure = ordinary hatch:
  bornFrom kept, birthCharmID nil, no unlock/ledger/equip/reveal;
  account ownership never removed. AURIE_BIRTH_PROOF covers both
  branches (win/lose × new/owned) by regenerating until the wanted
  deterministic verdict appears.
- Reveal UI (final polish pass): a quiet Birth-Charm card on the
  existing RevealView under the born-from card — "✨ Birth Charm
  unlocked" (first unlock) vs "✨ Birth Charm" (already owned), shared
  CharmArt artwork. Driven ONLY by `HatchCommitResult.birthCharm`
  (transient, set where commitHatch returns), so it can never describe
  an uncommitted hatch. Same pass fixed Recognition's substring
  matcher to whole-word phrase matching ("pineapple" no longer
  canonicalizes to hero "apple"); AURIE_RECOG_SELFTEST=1 covers it.
- Compact reveal sizing (approved+frozen 2026-09-18): on compact
  reveal stages, make the Aurie AS LARGE AS SAFELY POSSIBLE while
  keeping the complete visible creature inside the scenic frame with
  the approved top/bottom safety margins. Mechanism (CreatureScene):
  per-depth fit clamp in `fieldRender` (crown incl. worn hair, 26 pt
  top budget = 16 visible + 10 idle-bob), compact ENTRY that walks the
  feet nearer only when the home spot would clamp below half the
  stage, and a celebration-hop cap from real headroom (resting size
  has priority over hop distance). Any on-screen percentage a body
  reaches is an OUTCOME of its proportions, never a target. Full-
  height stages (Home/iPad/no-card SE) rest at home, untouched.
  AURIE_FIT_LOG=1 logs measured resting geometry;
  AURIE_HATCH_BODY/HAIR pin the rolled creature for capture.

## 10. TASK-REWARDED CHARMS (after Birth Charms)

No second inventory — rewards flow through `CharmService.unlock(...)`.
Future model: `CharmTask { id, type, target, rewardCharmID,
repeatability, progress }`. Prove with ONE task before many. Candidate
task areas later: pet/play with Aurie, Today's Wonder, Calm, Worry Jar,
multi-day visits, hatch, Birth-Charm discovery, sparkles/butterflies,
movement interactions.

## 11. CHARMS PAGE — next major product work (step 5 in order)

DEDICATED page (NOT crammed into Collection). One inventory browsed
with TWO INDEPENDENT filters: placement (All/Belly/Back/Head/…) and
category (Animals/Food/Medical/…). Detail view eventually: preview,
name, category tags, compatible placements, locked/unlocked,
acquisition hint where appropriate, equip/remove. Do NOT expose exact
Birth-Charm solutions if discovery should stay a surprise.

## 12. HEAD CHARMS — PAUSED (do not resume unprompted)

`charm_nature_flower_02` REJECTED (stem read as growing out of the
skull). Possible later candidates: flower_03, snowflake_01, petals_01,
star_01, crown_01-if-processed. Library lacks purpose-built head
accessories; future custom ideas: Mini Crown, Bow/Heart/Leaf/Butterfly/
Cloud/Shell/Lightning Clips, Crescent Moon Clip, Tiny Tiara.

## 13. LIBRARY / FORMAT RULES

Physical 3D charm → .blend/.glb (then .gltf/.fbx/.obj+mtl). Flat decal
→ transparent PNG (or SVG rasterized later). The current ~80-charm
library is TRANSITIONAL — many assets may be removed; never shape the
taxonomy around its current contents.

## 14. FROZEN — do not reopen without evidence

Home orientation system; approved body art; backpack construction;
belly area; 72% Extra-Soft global sticker style; pattern-registration
fix; limb lighting parity. Launch bodies: Round, Tall, Small, Egg,
Pear, Dumpling, Teardrop, Beanbag, Oval, Heart.

AURA CHARMS (approved+frozen 2026-09-19): gas-particle treatment —
SMALL objects (base 5.2% of body width × 0.45–0.95 variation),
IRREGULAR scattered distances (radial 1.12–1.70, no ring geometry),
subtle phase-offset motion, drawn behind the body; Aurie stays
visually dominant. Do NOT enlarge the objects or reintroduce ring
layouts. Active aura pool frozen: Crystal, Pink Blossom, Snowflake,
Tomato, Star. FLOATING placement paused (AurieNode.
floatingPlacementActive=false) — Key, Open Book, Star Coin held out
for a future personality system. Pizza/Pumpkin held out of rotation
(launch=false, editorial only). New belly charms: Basketball, Rain
Cloud, Pink Shoe, Flask, Trumpet, Chair, Tree.

HATCH CONTAINMENT (approved+frozen 2026-09-19): during the initial
burst the whole creature SpriteView renders through ONE SwiftUI
egg-silhouette mask (EggHatchView/HatchAurieView) sized from the
MEASURED shell frame (97% safety), grown ease-in over 0.55x the
fragment flight, then dropped — so at the first `bursting` instant
nothing (body/hair/limbs/charm) protrudes outside the still-enclosing
shell, and a winning Birth Charm is ALREADY worn on that first visible
frame. Do NOT move this back to SKCropNode: it segfaults SpriteKit's
Metal renderer over the shader-tinted AurieNode tree (two crash
reports, 2026-09-19). Egg geometry, fracture art, fragment motion,
timing, creature scale and the `bursting` gate are all unchanged and
stay frozen. Known-acceptable: in SLOW MOTION the belly charm reads
early through the first seam opening; fine at normal speed (approved).

## 15. DEBUG / PROOF INFRASTRUCTURE (intentionally retained)

All verified inside `#if DEBUG`, none active by default:
- `AURIE_CHARM_PROOF` — CreatureScene.swift ~963, BatchGridScene.swift ~273
- `AURIE_CHARM_PROOF_PERSIST` — AppModel.swift ~284 (writes REAL
  unlock/equip state when enabled — first to remove before release)
- `AURIE_CHARM_MIGRATION_SELFTEST` — AppModel.swift ~310
- `AURIE_BIRTH_PROOF` / `AURIE_RECOG_SELFTEST` — AppModel: the Phase D
  and recognition regression suites (48 + 36 checks)
- `AURIE_HATCH_FORCE_BIRTH` — EggHatchView: regenerate until the
  deterministic Birth-Charm outcome is a WIN (selection through the
  real resolver, never a bypass) for reproducible hatch evidence
- `AURIE_HATCH_BODY` / `AURIE_HATCH_HAIR` — EggHatchView: pin the
  rolled body/hair for worst-case geometry captures
- `AURIE_BELLY_PROOF` on the plain batch grid (BatchGridScene) — the
  whole roster wears a sticker id for on-Aurie art review
Also remember the env-var latch trap: AURIE_* vars persist for the whole
process. Final cleanup is a later phase, before release.

## 16. WORK ORDER AFTER COMPACT

1. Tiny Pumpkin + Tomato corrections (§5) → 2. FREEZE sticker visuals
→ 3. re-audit repo vs taxonomy if needed → 4. smallest
placements/categories/acquisition metadata change → 5. basic dedicated
Charms page → 6. STOP for review → 7. SMALL Birth-Charm proof set →
8. STOP and verify → 9. generic task→charm plumbing with ONE proof task
→ 10. expand only after these work.

DO NOT jump ahead: no hundreds of triggers, no full task catalog, no
shop/currency, no RevenueCat/App Store work, no mass charm export, no
HEAD resumption, no redesign of approved work.

## TIDE ENVIRONMENT (added 2026-09-17)

Tide's launch default is the BEACH (approved): production asset
`Auries/Assets.xcassets/Environments/tide_env_sky.imageset/tide_env_sky.png`,
generated reproducibly by `Design/Environments/recompose_tide3_beach.py`
from `tide3.png`. Deep water ends just above the 20% far walk line;
Aurie may stand in the surf foam, never open ocean. The UNDERWATER
master is preserved at `Design/Environments/tide_underwater_master.png`
(byte-identical to the pre-beach shipping master) for a future
unlockable alternate. No runtime changes were needed (flatMaster).
Future ambient/collectible direction: `Docs/environment_direction.md`.

## VISUAL BUG-FIX PASS IN FLIGHT (2026-09-17 evening) — RUNBOOK

Three rendering bugs root-caused; fixes implemented; the remaining work
is MECHANICAL (long renders + install + verification). State:

1. PATTERNS MISSING ON BACK — FIXED, install pending.
   Cause: stars/hearts tile sources were lost; back masks never
   rendered; runtime degrades to plain. Fixed: make_pattern_tiles.py
   (NEW, deterministic, calibrated vs shipped fronts) + back pass
   un-blocked in build_pattern_masks.py. All 60 back masks ALREADY
   RENDERED into the masters dir. Shipped FRONT masks untouched.

2. BLACK LIMB WEDGES — FIXED, re-export in flight.
   Cause: limb roots sit inside the body volume where the deliberate
   body-shadow (RC1 lighting parity) is total — solid black baked into
   every limb sprite, exposed by dance/splits root rotation. NOT
   caused by the charm holdout work (verified: charm export writes no
   limb assets). Fix: export_app_layers.render_limb two-pass composite
   (shadowed pass + shadow-off pass; only near-black pixels replaced).
   Validated: round arm/leg dark px 3328/4388 -> 0. Batch: 10 bodies x
   2 orientations, limbs only:
     for b in <bodies>; do for o in front back; ...
     export_app_layers.py --skip-body --skip-faces --skip-tail
       --hair-styles none --arm-styles all --leg-styles all
       --anim-safe-arms --anim-safe-legs [--orientation back]
   AFTER: verify every <body>_{arm,leg}_*{,_back}.png has 0 dark px;
   re-run any body/orientation with missing files (one batch run
   crashed from my concurrent foreground Blender - rerun is safe).

3. BACKPACK LOWER STRAPS — PARTIALLY FIXED, residual precisely scoped.
   Fixed for real: the pack model carried THREE molded strap shell
   pairs; only the shoulder pair was being deleted. The LOWER-TAIL
   pair (shells one-sided in x, x-extent>0.30, reaching |x|>0.42) is
   now censused + deleted too (export_charm_layers.py; 3392 faces).
   Re-export all 20 charm layers AFTER the limb batch, then install.
   RESIDUAL (open): the GENERATED band's sagging return — present in
   the user-approved previews — has rising tips whose last visible
   pixels can end outside the bag's ROUNDED silhouette (inside its
   bbox). ROOTDIAG (new --roots-diag flag) proves the designer roots
   project INSIDE the pack on all bodies (e.g. tall px 468/581 vs
   bbox 293-731), so the fix is about where the VISIBLE band leaves
   the camera ray into the bag, not the roots. NEXT DIAGNOSTIC: print
   each strap path key's camera-space px in build_straps and find
   which segment owns the visible tip; then bias only that segment
   into the bag's rounded projection. Do NOT try broad spline tweaks
   (three attempts changed nothing visibly).

4. HATCH — FROZEN. Re-verify once after installs (3 hair styles,
   pre-burst zero creature pixels) then leave alone.

THEN: install_app_assets.py (picks up patterns+limbs+charms), full
build, evidence suite: pattern front/back x stars/spots/hearts +
all-10 sheet; dance/splits close-ups x3 colours; backpack back
close-ups x4 bodies + front under-arm; live Home checks (walk-away
pattern, dance, splits, backpack orientation); charm harness;
git status. NOTHING STAGED, NOTHING COMMITTED throughout.

## APPENDIX — file map (verified)

Production Swift: `Auries/Models/CharmModels.swift`,
`Auries/Models/AurieModels.swift`, `Auries/Services/CharmCollection.swift`,
`Auries/Services/Store.swift`, `Auries/Scenes/AurieNode.swift`,
`Auries/Scenes/CreatureScene.swift`, `Auries/App/AppModel.swift`,
`Auries/Debug/BatchGridScene.swift`, generated
`Auries/Services/AurieBlenderAssets.swift`.

Pipeline: `Design/Aurie3D/Scripts/` → `build_pattern_masks.py` (zones +
patterns), `aurie_belly.py`, `aurie_belly_stickers.py`,
`review_belly_render.py`, `export_charm_layers.py`, charm tooling
(`charm_library.py`, `charm_processor.py`, `charm_profiles.py`,
`charm_on_aurie.py`, `charm_contact_sheet.py`, `charm_inspect.py`,
`charm_inventory.csv`).

Library: `AurieCharmLibrary/` (committed except ignored `_PROCESSED/`);
sticker PNGs at `AurieCharmLibrary/_THUMBNAILS/<charm_id>.png`.

References: `Design/Belly/belly_circle.png` (belly source of truth);
`Design/Aurie3D/References/aurie_body_types_reference.png`.

Evidence (local-only, gitignored): `aurie-review-evidence/belly_area/`
and `aurie-review-evidence/charms/` (incl. `CHARM_SYSTEM_REPORT.md`,
`head_audit/`).

Scratch (TEMPORARY, per-session, regenerable — do not rely on it):
older-session scratchpad
`/private/tmp/claude-502/-Users-Shared-claude-work/26bbbac5-fe92-4e2f-ac8b-b21ceb5b757c/scratchpad/`
still holds the rendered proof passes (`belly_proof/`, `belly_rollout/`
per body: body/parts/belly/pattern per yaw) and working copies of the
now-promoted scripts. If it is gone, regenerate passes with
`review_belly_render.py` (Blender headless) and rebuild sheets from the
promoted modules.
