# Charm & Task System — CURRENT-STATE HANDOFF (2026-09-20, post-cleanup)

CANONICAL document for the charm/task workstream. Everything below was
READ OUT OF THE TREE on 2026-09-20, not recalled from conversation.
`Docs/charm_workstream_handoff.md` is HISTORY only (belly pipeline
internals, backpack construction, Blender runbooks); where the two
disagree, THIS FILE WINS.

Status legend:
  [IMPL]    implemented in the tree AND verified by tests/evidence
  [HELD]    deliberately held out (launch=false) — do not revive
  [PENDING] an open product decision — do not decide unilaterally
  [NO]      rejected — do not revive

==================================================
A. GIT / TREE STATE  (verified 2026-09-20)
==================================================

Branch `aurie-art` · HEAD `383d8e9` "Add 2D Birth Charms, drop rule,
and hatch integration" (prior: b4716fe, 4f308ac, c1a2fb2).
**0 staged. 19 modified. 70 untracked.** The user commits manually —
never stage or commit without an explicit request.

MODIFIED (19): charm_taxonomy.json · AppModel · RootTabView ·
BatchGridScene · CharmCatalog.generated · CharmModels · AurieNode ·
CreatureScene · CalmModeView · CharmsView · EggHatchView · HomeView ·
WonderOverlay · Store · install_2d_stickers.py · sticker_tuning.py ·
charm_workstream_handoff.md · charm-tests/{main.swift,run.sh}

UNTRACKED — PRODUCTION (belongs in the eventual commit):
- Swift: `Auries/Models/CharmTasks.swift`,
  `Auries/Screens/EarnCharmsView.swift`,
  `Auries/Screens/CharmRewardView.swift`
- 13 `belly_sticker_*.imageset` + 8 `charm_catalog_*.imageset`
- `Design/Charms/` — Masters/*.png (13), SourceSheets/*.png (13),
  Scripts/install_placement_charms.py
- `Docs/charm_tasks_current_handoff.md` (this file)

UNTRACKED — **NEVER SWEEP INTO A COMMIT**:
- `Design/Aurie3D/Source/*_experiment.blend` + gourd/mochi/pebble
  masters (unshipped experiments; hair_02 is [NO])
- `Design/Environments/{dusk2,ember2,ember3,glow2,moss2,starlight2,
  stone3,tide2}.png` (future environments pass, not this workstream)
- `.claude/` (local skills)
- `aurie-review-evidence/` and `Design/Aurie3D/Export/` are gitignored.

Verification at handoff time: Debug + Release BUILD SUCCEEDED ·
harness 102/102 · AURIE_TASK_PROOF 22/22 · AURIE_BIRTH_PROOF 48/48.

==================================================
B. TASK SYSTEM — FULLY IMPLEMENTED  [IMPL]
==================================================

**DO NOT return from compaction thinking this still needs building.**
The Earn Charms system exists, is wired, and is test-verified.

>> PARTLY SUPERSEDED BY §M (2026-09-20): Daily Wonders were WITHDRAWN
>> from launch. There are now **10** active tasks, not 12. The
>> `wonderRevealed` / `wonderSaved` seams and the `wonderbookCount`
>> metric below still exist but NO launch task consumes them.

- Earn Charms page (`EarnCharmsView`) — pushed full page from the
  Charms tab (NavigationStack + standard Back), never a 5th tab.
  Cards: reward art + name, title, requirement, progress bar + n/target,
  green ✓ Completed, or "Reward coming soon" when unassigned.
- `CharmTasks.swift`: `CharmTaskDefinition {id, title, description,
  rewardCharmID: String?, event, kind, target, repeatability}`.
  THREE progress kinds:
    `.distinctDays` — per-task CalendarDay keys in
      `Settings.charmTaskDayKeys`; cumulative, forgiving, NEVER streaks
    `.eventOnce` — first qualifying event (not retroactive by design)
    `.state(metric)` — live scan of persisted facts = RETROACTIVE
      (wonderbookCount, aurieCount, charmsOwned, categoriesOwned,
       auriesWearingCharms, mostAuriesSharingACharm)
- Event seams (model layer only): `wonderRevealed` (markSparkRevealed),
  `wonderSaved` (saveToWonderbook), `charmEquipped` + `charmReplaced`
  (equipCharm), `calmVisited` (Calm entry — never reads Worry content),
  `aurieHatched` (commitHatch, fired after any birth unlock).
- `recordCharmTaskEvent` dedupes by day, then runs a state cascade
  (a grant can raise owned-counts and complete further tasks).
- `retroactiveCharmTaskPass()` at the end of AppModel init: long-time
  players complete state tasks on first launch; rewards queue.
- Completion = `task:<id>` in `processedGrantIds` — NEVER inferred
  from reward ownership. Grants ride `CharmService.processGrant`.
- **Task rewards UNLOCK ONLY — never auto-equip** (selftest-asserted).
- Reward presentation: `pendingTaskRewards` queue (transient, never
  persisted → no replay after relaunch) → HomeView item-sheet →
  `CharmRewardView` ("✨ New Charm!", art, name, Done, View Charms).
  Never presents while a Wonder is running; Today's Wonder contains
  ZERO charm UI.

==================================================
C. TASK MAP — **SUPERSEDED BY §M**
==================================================

>> THIS TABLE IS HISTORY. Rows 1-4 (five_daily_wonders, wonder_to_keep,
>> wonder_collector, month_of_wonders) were REMOVED from the launch
>> catalog on 2026-09-20 with Daily Wonders; their reward charms are
>> re-homed or hidden. The live list is the 10 tasks in §M.

| # | task id | requirement | reward | placement |
|---|---------|-------------|--------|-----------|
| 1 | five_daily_wonders | 5 Wonder days | Spark Badge (`charm_badge_spark_01`) | belly |
| 2 | wonder_to_keep | first Wonderbook save | Wonderbook Badge (`charm_badge_wonderbook_01`) | belly |
| 3 | wonder_collector | 10 Wonders saved | Star (`charm_magic_star_01`) | AURA |
| 4 | month_of_wonders | **30** Wonder days | Crystal (`charm_magic_crystal_02`) | AURA |
| 5 | ~~try_new_look~~ | equip a charm | **WITHDRAWN 2026-09-25** | — |
| 6 | fresh_look | replace a charm | Refresh Badge (`charm_badge_refresh_01`) | belly |
| 7 | share_the_style | same charm on 2 Auries | Pink Blossom (`charm_nature_flower_03`) | AURA |
| 8 | styled_crew | charms on 3 Auries | Team Badge (`charm_badge_team_01`) | belly |
| 9 | charm_variety | own 3 categories | Rainbow + Clouds (`charm_nature_rainbow_cloud_01`) | belly |
| 10 | make_friends | 3 Auries | Friendship Hearts (`charm_friendship_hearts_01`) | belly |
| 11 | quiet_visits | Calm on 3 days | Snowflake (`charm_nature_snowflake_01`) | AURA |
| 12 | growing_collection | own 10 charms | Tree (`charm_nature_tree_02`) | belly |

Of the 12 above, 9 remain active and ALL 9 award — `try_new_look` was
WITHDRAWN FROM LAUNCH 2026-09-25 rather than left reward-less, so no
shipping task has `rewardCharmID == nil` any more. (The mechanism is
still in the code: a nil-reward task cannot complete, because
`complete()` returns early and writes no ledger entry.) Discover 5
Wonders = Spark Badge (NOT Orange). Month of Wonders = 30 (NOT 20).

==================================================
D. CLEANUP DONE THIS PASS  [IMPL]
==================================================

**Pink Shoe (`charm_fashion_shoe_01`) — DELETED, not held out.**
Superseded 2026-09-20: first held out, then removed outright. There are
no users yet, so no save compatibility was owed for an unused charm and
a dead catalog entry/imageset was not worth keeping.
- Gone from the taxonomy and the generated catalog (37 → 36 charms).
- Production imageset `belly_sticker_charm_fashion_shoe_01.imageset`
  DELETED. Pipeline entries removed from `install_2d_stickers.py`
  (name map + `CAP_APPLIES_TO`) and `sticker_tuning.py`.
- Removed as the `try_new_look` reward. NO substitute was ever chosen,
  and on 2026-09-25 the TASK was withdrawn from launch instead.
- Original art kept ONLY as archive: `Design/Charms/SourceSheets/
  pink_shoe.png`. The production master under `Design/Charms/Masters/`
  is NOT part of the repo (that directory is a pipeline input).
- **Do not revive it without new art.**

No other charm was held out this pass. A "bronze badge to hold out"
was mentioned as coming next but **never identified** — all four
badges (Spark, Wonderbook, Refresh, Team) remain ACTIVE rewards.

==================================================
E. CHARM PLACEMENTS + AURA — FROZEN  [IMPL]
==================================================

ACTIVE placements (filters All | Belly | Back | Aura): belly, back,
aura — one charm per placement, coexisting
(`AurieCharmCatalog.equipping` is the single record rule).

FLOATING is PAUSED: `AurieNode.floatingPlacementActive = false` gates
rendering only; the CharmSlot case and records stay dormant for save
compatibility. Not a filter, not equippable, not in proofs.

AURA VISUALS — FROZEN (do NOT enlarge, do NOT reintroduce a ring):
tiny gas-particle scatter, base 5.2% of body width × 0.45–0.95
per-instance variation, irregular radii 1.12–1.70, deterministic
16-entry layout (no RNG), counts 13 default / 16 crystal / 11 blossom,
subtle phase-offset motion, Reduce Motion respected, drawn BEHIND the
body so face/belly can never be covered, follows the creature.

ACTIVE AURA POOL: Crystal, Star, Pink Blossom, Snowflake, **Tomato
(spare/unassigned)**.

BACK: Backpack (`charm_object_backpack_01`) is the only Back charm.

==================================================
F. BIRTH CHARMS — FROZEN  [IMPL]
==================================================

- Trigger = ELIGIBILITY only (canonical hero labels, whole-word
  matcher; "pineapple" ≠ apple). 11 triggers live.
- `birthCharmDropChance = 0.50` — ONE deterministic roll per hatch
  (splitmix64 of the creature's permanent seed), replay/retry stable.
- One shared resolver feeds BOTH the egg preview and commitHatch: a
  winning newborn WEARS the charm from the first visible frame.
- Provenance (`Aurie.birthCharmID`) is separate from equipment;
  removable / replaceable / re-equippable; account-level ownership
  survives Aurie deletion; `birth:<aurieID>` ledger blocks replays.
- **Birth Charms auto-equip. Task rewards never do.**

HATCH CONTAINMENT — FROZEN: SwiftUI host-level egg-silhouette mask.
**DO NOT RETRY SKCropNode — it segfaulted SpriteKit's Metal renderer.**
Egg geometry, fracture art, fragment motion, timing, creature scale and
the hidden-until-`bursting` gate stay frozen absent a real bug.

==================================================
G. BELLY ART RULES + THE SHARPNESS LESSON  [IMPL]
==================================================

Art direction: borderless, transparent, crisp glossy 2D/2.5D sticker,
NO white die-cut outline, semantic (not naive alpha-bbox) centering,
per-charm scale/offset tuning in `sticker_tuning.py`, presentation
baked at install by canvas geometry.

SHARPNESS (root cause + fix, keep this lesson):
SpriteKit minifies belly stickers with bilinear filtering and NO
mipmaps. The approved family sits at ~1.7–2.0× minification and looks
crisp; art imported from 1254px sheets landed at ~7× and fine interior
strokes dissolved. Fix in `install_2d_stickers.py`:
`PRODUCTION_ART_CAP = 320` applied via `CAP_APPLIES_TO` — ONE Lanczos
downsample from the untouched full-res master so the runtime does a
single gentle downscale. Badge scale raised to a shared 0.93.
**Never "fix" softness with sharpening, nearest-neighbour, or a global
filtering change.**
PRODUCT LESSON: art that still reads muddy at real Home/belly scale
gets HELD OUT, not endlessly rescued (that is why Pink Shoe is gone).

==================================================
H. HELD OUT (launch=false)  [HELD — verified from taxonomy]
==================================================

Pink Shoe is NOT in this list — it was deleted outright (§D), not held
out. Ten charms are `launch=false`; all keep ids, art and placements,
so any of them can be granted and rendered the moment a path exists.

- `charm_food_pizza_01` Pizza
- `charm_nature_pumpkin_01` Pumpkin
- `charm_object_key_01` Key — parked on dormant `floating`
- `charm_object_book_01` Open Book — parked on dormant `floating`
- `charm_magic_star_coin_01` Star Coin — parked on dormant `floating`

Hidden 2026-09-20 because they had NO acquisition path — players were
browsing locked charms they could never obtain. Editorial visibility
ONLY; rendering and future grant-ability untouched:
- `charm_toy_basketball_01` Basketball
- `charm_nature_rain_cloud_01` Rain Cloud
- `charm_science_flask_01` Flask
- `charm_music_trumpet_01` Trumpet
- `charm_object_chair_01` Chair

Note: those five still declare `acquisitionSources: ["taskReward"]` in
the taxonomy even though no task grants them. Left as-is deliberately —
it records the intent for whoever wires them up later.

Key / Open Book / Star Coin are reserved for a possible future
personality-related Floating system. Do NOT return them to Aura or
Belly rotation. `launch` is EDITORIAL ONLY — never a render or grant
gate; an equipped launch=false charm still renders.

==================================================
I. OPEN DECISIONS  [PENDING — do not decide unilaterally]
==================================================

1. ~~**Replacement reward for `try_new_look`**~~ **RESOLVED
   2026-09-25 — the task was REMOVED FROM LAUNCH** instead of being
   given a reward. Pink Shoe stays deleted and no existing charm was
   substituted. If the task ever returns it needs new art approved
   visually BEFORE wiring.
2. ~~Wire `birth_backpack`?~~ **DONE — verified end to end 2026-09-25.**
   `Recognition.swift:151` canonicalises backpack/knapsack/rucksack to the
   hero label "backpack"; the trigger `birth_backpack` accepts it and
   unlocks `charm_object_backpack_01`; the generated catalog carries both
   (lines 97 and 127) with `acquisitionSources:["birthPhoto"] launch:true`;
   art ships for every body shape and `CharmsView.displayScale` even has a
   per-charm tuning entry for it. Nothing left to do.
3. **Launch-visible but unobtainable charms** — the old "verified list of
   8" is STALE, re-audited 2026-09-25. Orange, Basketball, Rain Cloud,
   Flask, Trumpet and Chair are all `launch=false` now; Tomato and Backpack
   both have birthPhoto paths. Exactly ONE remains:
     **Clownfish (`charm_animal_clownfish_01`)** — `launch:true`,
     `acquisitionSources:[]`, `birthTriggerIDs:[]`, and NO shipped imageset
     (only pipeline sources: a .blend, a library JSON, a thumbnail). It
     renders in the Charms grid as the generic `sparkles` placeholder at
     25% white and can never be unlocked.
   DECISION: set `launch=false`, or give it art AND a path. Do not ship it
   as-is — it is the one visibly unfinished tile among 21 real charms.

==================================================
J. DO NOT REVIVE  [NO]
==================================================

- Pink Shoe as a launch charm / task reward (and no re-sharpening it)
- Orange as the Discover 5 Wonders reward
- 20-day Month of Wonders
- Pizza or Pumpkin in active rotation
- Key as an Aura charm; any ACTIVE Floating charm
- Old random reward pairings: Rain Cloud→Wonderbook, Trumpet→Fresh
  Look, Basketball→Styled Crew, Flask→Charm Variety, Chair→Make Some
  Friends; or any "use it because the asset exists" assignment
- Dual-source rewards (one unlock path per charm)
- White die-cut sticker outlines
- Large / sparse / ring-layout Aura treatment
- Charm-unlock UI embedded inside Today's Wonder
- A fifth bottom tab; hair_02 Side Swoop; SKCropNode hatch masking;
  "ball" as a hero label (phrase "beach ball" only); "orange" as a
  Birth trigger (colour-word false positives)

==================================================
K. WHAT THE NEXT CONTEXT SHOULD DO
==================================================

Read this file first; continue from the ACTUAL tree. Do NOT start a
large new feature. Order of work:
1. ~~Resolve the `try_new_look` reward.~~ DONE 2026-09-25 — task removed.
2. Settle the §I decisions with the product owner.
3. One final task/charm QA pass.
4. Prepare a staging plan (the user commits manually).

DEBUG capture aids (all `#if DEBUG`, permanent per project convention):
AURIE_SHOW_TASKS, AURIE_TASKS_SCROLL_BOTTOM, AURIE_TASK_SEED_DAYS,
AURIE_TASK_PROOF, AURIE_BIRTH_PROOF, AURIE_RECOG_SELFTEST,
AURIE_WONDER_SHAKE, AURIE_WONDER_AUTOCLOSE, AURIE_HATCH_DEMO=<sample>,
AURIE_HATCH_AUTO/FORCE_BIRTH/BODY/HAIR, AURIE_AURA_PROOF,
AURIE_FLOAT_PROOF, AURIE_BELLY_PROOF, AURIE_CHARM_* (see old handoff).
State-mutating selftests must run ALONE on a fresh install.

Added 2026-09-20 (sheet-fit / reward-queue QA; approved to keep, all
`#if DEBUG`, inert unless explicitly invoked):
- `AURIE_REWARD_AUTOCLOSE=<secs>` (CharmRewardView) — acknowledges the
  reward card via the same `dismiss()` the Done button calls, so a QUEUE
  of rewards can be captured without taps. Twin of AURIE_WONDER_AUTOCLOSE.
- `AURIE_TUTORIAL_AUTOSKIP=<secs>` (RootTabView) — closes the first-run
  tutorial the way Skip does. Exists so the tutorial→reward ORDERING that
  HomeView's reward gate depends on stays reproducible.
- `AURIE_SHOW_DAILY_DETAIL=1` (HomeView) — opens today's daily card at
  launch, for sheet-fit review.
- `AURIE_SHOW_SUPPORT=1` (CalmModeView, use with AURIE_WORRY_DEMO=1) —
  opens the Calm support panel, for sheet-fit review.

## SHEET SIZING ON iPAD (learned 2026-09-20 — do not re-learn)
iPad presents a sheet as a FORM SHEET, and `.presentationDetents` resolve
against THAT container (~620pt), not the screen. `.medium` there is only
~310-360pt. Worse, an iPad form sheet is narrow enough that
`horizontalSizeClass` reads COMPACT from INSIDE the sheet content — so a
size-class check within the sheet silently does nothing. Decide iPhone vs
iPad AT THE PRESENTER and pass it in (see CharmRewardView's
`centersVertically` / HomeView's detent choice).
Audited 2026-09-20 and CORRECT on both iPhone and iPad portrait — leave
them alone: `DailyDetailView` (bounded content, longest daily item is 68
chars) and `SupportView`. Both keep a bare `.medium` deliberately.

==================================================
L. LAUNCH READINESS (audit 2026-09-20, HEAD 82023d5)
==================================================
Full findings live in the audit reply; this is the short version so the
next session does not re-derive it. Charm/task workstream is COMMITTED
(82023d5); Debug + Release both green; tree clean apart from the 24
intentionally-excluded files (.claude symlinks, .blend, env candidates).

SUBMISSION BLOCKERS (cannot ship without):
1. App icon is EMPTY — AppIcon.appiconset has 3 entries, 0 filenames.
   Hard upload blocker. Needs a 1024 icon from the owner.
2. Monetization is a STUB that shows real prices. StubPurchaseService
   (PurchaseService.swift:31-56) grants hatches after a sleep; the
   paywall shows $2.99/$4.99/$8.99 (RefillSheet.swift). No StoreKit, no
   RevenueCat, no SPM deps, no .storekit file. Shipping this is a
   Guideline 3.1.1 rejection. DECISION REQUIRED: implement real IAP, or
   remove the paid UI for v1 and ship the free economy only.
3. "Watch an ad for 1 more hatch" (RefillSheet.swift:36-49) plays NO ad
   and has no cap/cooldown — unlimited free hatches + misleading UI.
   Must be removed or backed by a real ad network.
4. External App Store Connect work (see §D of the audit): app record,
   IAP products, privacy questionnaire, age rating, screenshots,
   support/privacy URLs, export compliance.

FREE ECONOMY IS REAL (do not rebuild): HatchWallet.swift implements
3 first-day + 1/day non-accumulating (assignment, not +=), spend order
free -> rewarded -> paid, persisted to wallet.json.

TOP SHOULD-FIX (highest product impact first):
- Charms are INVISIBLE outside Home. AssetLoader.blenderPortrait
  (AssetLoader.swift:68-79) omits charmLayers/belly/aura/floating, so the
  Auries grid, Settings thumb and the widget render creatures bare.
  Home passes all four (CreatureScene.swift:183-186). Small fix.
- 3 launch-visible charms can never be obtained: Orange (belly),
  Tomato (aura), Backpack (back). The BACK tab contains exactly ONE
  charm and it is locked forever. Note "backpack" IS already a
  Recognition hero label (Recognition.swift:151) but has no birth
  trigger, so wiring it is small.
- ~~try_new_look still has no reward.~~ FIXED 2026-09-25 — the task is
  removed from launch, so no "Reward coming soon" row ships.
- Accessibility: 20 screens have ZERO VoiceOver annotations; the hatch
  burst ignores Reduce Motion (Aura/Calm/Home do respect it).
- Audio: AVAudioSession is NEVER configured (no category anywhere);
  turning Sound off does not stop already-playing audio.
- Notifications are effectively decorative: one repeating 10:00 request,
  the "random" line is frozen at enable time, authorization is never
  re-checked, and `notificationsOn` gates nothing.

DO NOT re-derive: worry TEXT is never persisted (only a dated token,
Store.swift:159-167) — that is correct and deliberate.

==================================================
M. DAILY WONDERS WITHDRAWN FROM LAUNCH (2026-09-20)
==================================================
Product decision: the launch app is HATCH · COLLECT · CUSTOMIZE ·
INTERACT · CALM. Daily Wonders and the Wonderbook made it feel
scattered next to the charm systems, so they are OUT of launch.

REMOVED FROM LAUNCH (no reachable UI, no launch-facing copy):
- Today's Wonder card (`WonderSurface`) — no longer presented
- Wonderbook screen + its sheet + "Save to Wonderbook"
- The "Today's Spark" re-read chip and `rereadTodaysSpark()`
- The once-per-day reveal gate on the globe
- The old large Daily Lift card, its detail sheet and dismiss control
  (these were ALREADY dead code — nothing rendered `dailyCard`)
- The four Wonder tasks (see below)

KEPT — now the "Snow Globe", a repeatable playful interaction:
shake -> glass pulse -> particles swirl -> Aurie tumbles with the dizzy
face -> chime + success haptic on stop -> snow settles -> Home handed
back. Visual sequence is UNCHANGED; only the text reveal was removed.
NOTHING is granted, counted or persisted by shaking — it is not a
currency, streak or progress mechanic.
- Entry points: physical shake; Settings ▸ Accessibility ▸ "Shake
  without moving your phone". Both call `startGlobeShake()`.
- The "❄ Snow Globe" CHIP WAS REMOVED 2026-09-21. It called
  `beginWonderSwirl()` without ever producing a shake-STOP, and the
  wind-down hung off `shake.onStop` alone — so the field stayed
  energized, `isGlobeFinished` never became true, `wonderActive` never
  cleared, and `stepWonderCarry` rescaled the creature ±10% every frame
  FOREVER. Tapping it left Aurie pulsing and the globe never settled.

TERMINATION RULE (2026-09-21, deliberate — do not replace with a timer):
a globe ends on ONE condition, `ParticleField.isGlobeFinished`. A clock
that force-ends it removes particles mid-air, which is the exact defect
the poll was written to prevent.
- `releaseWonderShake()` now ARMS the settle poll itself. Previously only
  Home called `settleWonder()`, off an 8.5s timer, so any globe Home had
  not sequenced was never told to finish. The scene watches its own
  particles now, whatever started the globe.
- `wonderMaxShakeSeconds` (12s) only DE-ENERGIZES the field if no
  shake-STOP arrives. It does not end the globe — the particles still
  fall, land and fade on their own clock, and the poll ends it.
- `settleWonder()` is idempotent and guards on `wonderActive`. The old
  version, called after a globe had ended, armed a `repeatForever` poll
  whose `guard let field = wonderSwirl` always returned — a permanently
  spinning leaked action.
- RE-ENTRY: Home re-opens the shake ~5.5s before the scene finishes
  settling, so globes 2..n arrive with one still active (verified: 4
  shakes -> 4 releases -> 1 restore, i.e. one continuous globe that ends
  once). `beginWonderSwirl` therefore KEEPS the baseline it already holds
  instead of re-reading `creature.xScale`, which mid-sequence ranges over
  base×0.90 ... base×1.12 — re-reading would adopt an inflated baseline
  and keep it for every later globe, a permanent cumulative size change.
  Nothing is torn down on re-entry; the live field carries on.
- DEBUG aids: `AURIE_GLOBE_SCALE_LOG=1` logs the baseline capture, a
  per-poll particle-phase histogram and the final restore delta;
  `AURIE_GLOBE_HANG=1` reproduces the removed chip exactly (starts a
  globe with no shake-STOP) and must still end with delta=0.0000.

ACTIVE LAUNCH TASKS = 9 (was 12, then 10): fresh_look,
share_the_style, styled_crew, charm_variety, make_friends,
quiet_visits, full_house, old_friends, growing_collection.
`try_new_look` was withdrawn 2026-09-25 — every remaining task awards.

TWO NEW NON-WONDER TASKS (2026-09-20), replacing nothing — they simply
re-home two freed aura rewards:
- `full_house` "A Full House" — have 10 Auries. Reward: Star aura
  (`charm_magic_star_01`). `.state(.aurieCount)` = a LIVE SCAN of
  `store.auries.count`, so it completes whenever the current collection
  is >= 10. No history tracking, no special retroactive logic — the
  state kind IS the live scan.
- `old_friends` "Old Friends" — interact with any Aurie on 30 different
  days. Reward: Crystal aura (`charm_magic_crystal_02`).
  `.distinctDays` on the NEW `.aurieInteracted` event.

THE `.aurieInteracted` SEAM (new): `CreatureScene.onInteraction` fires
on a body-region tap or a pet stroke, `.play` mode only — never an
empty-space tap and never an autonomous fidget. `CreaturePlayView`
wires it to `AppModel.recordAurieInteraction()`, which COLLAPSES it to
at most one model event per calendar day (otherwise every poke would
re-run the state cascade). Do not call `recordCharmTaskEvent
(.aurieInteracted)` directly from UI.

THE TWO ORPHANED BADGES — kept in the catalog, UNASSIGNED, and now
`launch=false` so they are not browsable as permanently-locked charms
(this also removes the last launch-facing "Wonderbook" word):
Spark Badge (`charm_badge_spark_01`), Wonderbook Badge
(`charm_badge_wonderbook_01`). Art and ids preserved; flip `launch`
back if a future task claims them.

DORMANT — DO NOT MISTAKE FOR AN ACTIVE LAUNCH FEATURE:
- Files kept but never presented: `WonderOverlay.swift` (WonderSurface),
  `WonderbookView.swift`, `DailyDetailView` + `DailyLiftItem.Kind.label`
  in HomeView.swift.
- Model/content kept: `DailyLift`, `daily_content.json`,
  `AppModel.todaysDaily / ensureTodaysSpark / sparkRevealedToday /
  markSparkRevealed / saveToWonderbook / isInWonderbook /
  wonderbookItems / removeFromWonderbook`.
- Task events `.wonderRevealed` / `.wonderSaved` still EXIST and still
  fire from their model seams, but NO launch task consumes them, so they
  grant nothing (selftest-asserted).
- `WonderStage.reading` is never entered; only .off/.swirling are used.
- PERSISTED FIELDS LEFT DORMANT (decode safely, nothing removed):
  `savedWonderDayKey`, `savedWonderID`, `wonderRevealedDayKey`,
  `savedWonderIDs`, `dailyLiftDismissedDate`. Nothing was deleted from
  Settings — there are no production users, but leaving them costs
  nothing and avoids a risky decode change.
- Internal names still say "wonder" (`beginWonderSwirl`, `settleWonder`,
  `wonderRunning`, `.wonderShakeRequested`, `sfx_wonder`). Deliberate:
  renaming the scene/particle layer was out of scope and carried more
  risk than value. NONE of it is player-visible.

NOTIFICATIONS: unchanged. Audited — all three notification lines are
hatch copy ("Who will hatch today?"); there was no Wonder notification.

RESOLVED 2026-09-20 (same day): the Star and Crystal auras were
re-homed onto the two new tasks above; the two badges were hidden with
`launch=false`. Catalog now: 36 charms · 23 browsable · 12 launch=false
· 9 task rewards · **3 still unobtainable** (Orange, Tomato, Backpack —
unchanged, still an open decision).

==================================================
N. HATCH ALLOWANCE + PACING NOTES (2026-09-20)
==================================================
- New accounts get **5** free hatches on day one (was 3). ONE constant:
  `WalletService.freeFirstDay` in `Auries/Services/HatchWallet.swift`.
  `freePerDay` stays **1** and remains NON-accumulating (refreshDaily
  ASSIGNS, never `+=`). The only consumer is `refreshDaily`, which picks
  freeFirstDay on the first-launch day and freePerDay after — so the
  change is self-contained. No player-facing copy hardcodes a number.
- `growing_collection` ("Own 10 charms") intentionally spans BOTH earning
  paths: task rewards AND Birth Charms. Needing hatch discoveries to
  reach ten is DESIGNED PACING, not a gap — do not "fix" it by adding
  more task rewards.

==================================================
O. BIRTH-CHARM EXPANSION + LAUNCH INVARIANT (2026-09-20)
==================================================
Backpack and Tomato became BIRTH CHARMS; Orange did not.

- `birth_backpack` -> label "backpack" -> `charm_object_backpack_01`
  (BACK placement). The hero label already existed in Recognition.swift;
  it had simply never been wired to a trigger.
- `birth_tomato` -> label "tomato" -> `charm_food_tomato_01` (AURA
  placement). "tomato" had NO keyword anywhere in the recognition table
  before this, so a new hero row was added. It is not a colour word, so
  promoting it carries no false-positive risk.
- Birth dressing handles both: `dressedForBirth` picks the first
  SUPPORTED placement, so a newborn wears the Backpack on its back and
  the Tomato as an aura. No belly assumption anywhere.
- Both charms now declare `acquisitionSources: ["birthPhoto"]` and the
  `birthTriggerIDs` back-reference the harness enforces.

**Orange stays `launch=false` — do NOT revive it as a birth charm.**
Recognition.swift states the reason: "orange" doubles as a COLOUR word,
so a hero label for it would false-positive on any orange-ish object.
Decision re-confirmed 2026-09-20 after being raised again. Its id and
art are preserved; `acquisitionSources` cleared (it never had a path).

NEW LAUNCH INVARIANT (harness-enforced): **every charm a player can
BROWSE must be obtainable** — it must have a birth trigger or be a task
reward. The test walks the real catalog, so adding a launch=true charm
with no path now FAILS the harness instead of shipping a dead end.

Catalog after this pass: 36 charms · 13 birth triggers · 9 task rewards
· 13 launch=false · **22 browsable, 0 unobtainable**.

==================================================
P. REVENUECAT / PURCHASES (2026-09-20)
==================================================
SDK: RevenueCat purchases-ios **5.80.3** via SPM (app target only).
RevenueCatUI deliberately NOT added — Aurie has three consumable packs
and its own purchase UI; a generic paywall would be a regression.

KEY PLUMBING (no key ever lives in source or in git):
  Config/AurieConfig.xcconfig          TRACKED, target base configuration
    #include? "LocalSecrets.xcconfig"  OPTIONAL — a fresh clone without it
                                       still opens and builds cleanly
    REVENUECAT_API_KEY[config=Debug]   = $(REVENUECAT_TEST_API_KEY)
    REVENUECAT_API_KEY[config=Release] = $(REVENUECAT_PRODUCTION_API_KEY)
  Config/LocalSecrets.xcconfig         GITIGNORED (.gitignore, not
                                       .git/info/exclude), machine-local
  Config/LocalSecrets.example.xcconfig TRACKED template
  -> Info.plist RevenueCatAPIKey = $(REVENUECAT_API_KEY)
  -> PurchaseConfiguration.apiKey; empty/"$(...)"/test-prefixed-in-Release
     all resolve to nil => UnavailablePurchaseService.

PROVEN 2026-09-20 with a probe value in the local file:
  Debug   -> key resolves
  Release -> EMPTY even though the Test Store key exists on the machine.

MAPPING — gameplay depends on PACKAGE identifiers, never store product
ids (RevenueCatPurchaseService.quantities):
  hatches_5 -> 5 · hatches_10 -> 10 · hatches_20 -> 20
  offering "hatch_packs", falling back to offerings.current.
Prices come from `storeProduct.localizedPriceString`. Quantities are
app-defined; prices are NEVER hardcoded.

EXACTLY-ONCE CREDIT: `WalletService.apply` keys on the STORE transaction
id and writes ledger entry + balance in ONE atomic save. A grant with no
id is REFUSED (it used to fall back to UUID(), which made every such
grant unique and therefore always creditable — the double-credit hole).
`reconcile(_:)` replays RevenueCat's nonSubscriptionTransactions at
launch; the ledger makes that a no-op in the normal case.

RESTORE: none, deliberately. Consumables have no entitlement, and a
SPENT balance cannot be restored by StoreKit or RevenueCat. The UI says
"Hatch packs are used on this device."

KNOWN LOSS WINDOW (cannot be closed without a server/account):
the app is killed after the store finishes a purchase but before the
atomic save AND before RevenueCat records the transaction server-side.
Launch reconciliation covers the common case; a true cross-reinstall
guarantee needs a backed account, which is out of scope.

PRODUCTION SWITCH-OVER (blocked on the Apple Developer account):
 1. Create 3 CONSUMABLE IAPs in App Store Connect.
 2. Set US prices $2.99 / $4.99 / $8.99.
 3. Complete banking / tax / Paid Apps Agreement.
 4. Connect the Apple app to RevenueCat.
 5. Import/map the real Apple products in RevenueCat.
 6. Attach them to the EXISTING hatches_5 / hatches_10 / hatches_20
    packages — do not rename the packages; the app maps on those.
 7. Put the production Apple key in REVENUECAT_PRODUCTION_API_KEY.
 8. Enable the In-App Purchase capability on the Auries target.
 9. Test in Apple Sandbox / TestFlight.
10. Remove Test Store-only tooling before submission.

==================================================
Q. REWARDED ADS — DEFERRED TO 1.1 (decided 2026-09-21)
==================================================
NOT a 1.0 feature. No ad SDK is installed and none may be installed for
1.0. No ad-related privacy/consent/ATT/SKAdNetwork configuration yet.

THE 1.1 RULE (agreed, do not redesign):
  Watch ONE rewarded ad -> receive ONE hatch.
  Maximum once per CALENDAR DAY. NON-ACCUMULATING (a skipped day grants
  nothing later). Optional and never forced. No interstitials, no ads
  during normal play. The hatch is credited ONLY after the ad SDK
  reports successful completion; failed/cancelled/incomplete = no hatch.

ARCHITECTURE ALREADY IN PLACE — keep it, do not rebuild:
- `HatchWallet.rewardedHatchBalance` is a SEPARATE bucket from free and
  paid, persisted in wallet.json, lenient-decoded. Spend order stays
  free -> rewarded -> paid (`consumeHatch`).
- `WalletService.apply` credits `.rewardedAd` grants to that bucket and
  refuses any grant with no transaction id.
- THE DAY-SCOPED GRANT ID: mint the rewarded grant as
  `"ad:\(CalendarDay.key(for: Date()))"`. The existing processedGrantIds
  ledger then enforces ALL THREE rules with no new persisted state:
    once-per-day  -> ledger already contains today's id
    exactly-once  -> a double-firing SDK callback hits the same id
    no accumulation -> yesterday's id can never grant today
  Do NOT add a `lastRewardedAdDate` field; it would duplicate this.
- The Home/refill ad button stays HIDDEN behind `supportsRewardedAds`
  (false) until a real service exists. Never show it without one: it
  previously granted uncapped free hatches for an ad that never played.

WHEN 1.1 STARTS: add a SEPARATE `RewardedAdService` (do not extend
`PurchaseService` — different vendor, different lifecycle), move
`supportsRewardedAds`/`grantRewardedAdHatch` onto it, and fix
`RefillSheet.watchAd` which currently swallows errors with `try?` and
dismisses unconditionally (a failed ad looks like a success).
Recommended provider: AdMob (simplest single placement, first-class
child-directed flags). Ads change the App Privacy label from "Data Not
Collected" to collecting identifiers for advertising, and are
effectively disqualifying if Aurie ever enters the Kids Category —
settle that product question BEFORE integrating.

## R. FAMILY AMBIENT LIFE — VISIBILITY REVISION (2026-09-22)

The first ambient pass was correct in structure and invisible in practice.
Revised against ONE standard: a viewer must be able to tell something is
moving without being told to look.

MEASUREMENT — do not trust a raw "pixels changed" number. Home is never
still: Aurie bobs and wanders, and the background parallaxes with it, so the
scene changes 4–7% frame-to-frame with NO ambient life at all. The first
measurement run reported near-identical motion for four very different
families, which is how the confound was caught. `AURIE_AMBIENT_OFF=1`
(DEBUG) suppresses the ambient node to give a parallax-only control; the
ambient contribution is (on − control). The control is noisy run to run
because Aurie's wandering is random, so for the quiet families (Stone, Dusk,
Starlight) trust an amplified frame diff and your eyes, not the number.

CAPTURE TRAP — `AURIE_SEED_FEATURED_FAMILY` only applies to an EMPTY store
(`AppModel` gates the seed on `store.auries.isEmpty`). Reusing an install
silently keeps the previous family: seven "per-family" videos were recorded
before this was noticed and were all the same Tide scene. ALWAYS uninstall
before capturing a family.

REPLACED EFFECTS
- TIDE — three techniques were tried; only the third works. Read this
  before touching it again.
  1. `tideShimmer` crescents: abstract white arcs, and the `.waterBand`
     zone put them at scene_y +0.04…+0.14 while the painted surf is at
     +0.26…+0.33, so every mark landed on DRY SAND. Removed.
  2. Hand-painted foam bands (`.waves`): crest shapes built from soft
     blooms, slid shoreward, later given an advance/recede cycle.
     Measurably moving, and still wrong — anything DRAWN over this painting
     reads as a mark on top of it, however soft it gets. Two sub-lessons
     kept: a gradient clipped to an ellipse shows its cut ends at FULL
     alpha and reads as a scanline, and additive blending over a bright
     sunset beach blows out to white.
  3. `.surfSlices` — SHIPPED. Narrow horizontal bands are duplicated out of
     the BACKGROUND TEXTURE ITSELF (`SKTexture(rect:in:)` against the sky
     layer, exposed as `HomeEnvironment.skyLayer`), laid back exactly over
     their source, then given a small drift, a tiny vertical in/out and an
     opacity shimmer — each band on its own period. Nothing is drawn, so
     nothing can look foreign to the art.

  THE TWO CONSTRAINTS THAT MAKE IT WORK, both found by looking, not guessing:
  · A duplicated slice GHOSTS any hard edge inside it. Full-width bands over
    the lower shoreline produced visibly doubled rocks — "a sticker sliding
    back and forth", precisely the failure to avoid. Bands cover water only.
  · The rocks are not evenly spread, so one y-band cannot dodge them. There
    are TWO groups: open water (+0.284…+0.344, full width) and the single
    rock-free stretch of lower shoreline (+0.236…+0.286, x 0.24…0.62, found
    by scanning that band for dark columns). `xRange` feathers the mask
    horizontally so the rocky stretches either side stay perfectly still.
  MOTION SHAPE (2026-09-23). The first cut moved each band with a symmetric
  out-and-back over the full period — which is a SHIMMER. Water is
  asymmetric: it arrives fast and leaves slowly. Each band now runs one surf
  cycle — quick run-up (0.32·t, easeOut) · brief hold · slower drain
  (0.54·t) · irregular gap — each with its own phase, hold and gap from the
  golden-ratio walk, so the set never surges as one unit.
  Travel also had to be INVERTED: `lift * (1 - 0.25 * i)` gave the largest
  excursion to i=0, which is the FARTHEST band, and the least to the
  shoreline. It now scales with `near`, so the frontmost foam edge moves
  most (0.55…1.40 × lift).
  Layout: 2 quiet bands in open water (lift 3) + 3 layered bands on the
  rock-free shoreline (lift 11). `lift` is the headline number — at 6 it
  read as shimmer, because 6pt on a 633pt scene is under 1% of height.

  DEPTH, NOT VOLUME (2026-09-24). To make only the FRONT foam edge run
  further, do NOT raise `lift` — that scales the whole group and flattens
  the depth cue. `frontBoost` adds `boost · near³`, which is ~0 at the far
  band, +6% at the middle and +32% at the front. Shoreline uses 0.45; the
  open-water group passes 0, so its behaviour is bit-for-bit unchanged.
  Front-band travel is now 20.4pt vs 11.3 (mid) and 6.05 (far).

  MEASURING A PER-BAND CHANGE: "% pixels changed" CANNOT resolve it — the
  bands overlap, each carries its own irregular gap, and a busy region
  saturates, so that metric reported the front band getting *quieter* after
  a change that provably increased its travel. Track the foam edge instead
  (brightness-weighted centroid of white water inside one band's y-window,
  x 0.24…0.62) and take its range across frames. That reads the gradient
  correctly: front 8.7px · mid 5.3px · far 3.3px.

  SKCropNode CANNOT FEATHER (2026-09-24 — the big one). Its maskNode is an
  ALPHA TEST, not a blend: a gradient mask still yields a hard edge. Every
  band boundary was therefore a straight rectangle the whole time, invisible
  only while the bands barely moved. Raising the front band's travel slid
  enough content across them to expose it, which read as "the rocks are
  moving". The feather is now BAKED INTO THE SLICE IMAGE
  (`featheredSlice`) — crop the sky CGImage, draw it, then `.destinationIn`
  a vertical and a horizontal gradient. No SKCropNode anywhere.

  A SLICE MUST BE PADDED BY ITS OWN TRAVEL. The sprite used to be exactly as
  tall as its window; once travel approached the band height it slid clean
  out and the window blinked empty. `pad = dy + 3` samples extra painting
  above and below.

  BANDS MUST NOT REACH A ROCK, and the rocks are not where a naive scan says
  — a darkness test flags the deep blue sea, and a warm-colour test flags
  wet sand and the sun glitter. The reliable diagnostic is MOTION OVER ROCK
  PIXELS: classify rock as (R > B+25 AND luminance < 150) on a still frame,
  then report, per column band, the share of those pixels that change
  between frames. That found the boulder at x 0.62-0.70 (34% of its pixels
  moving) when every zone-average said the rocks were fine.

  CURRENT WINDOWS — three groups, all sharing period 5.6 so the bay moves
  as ONE body of water rather than as independent patches:
      main water  y .296-.330  x 0.24...0.56  fade .065 vFade .34 lift 5
      right water y .306-.330  x 0.62...0.72  fade .040 vFade .34 lift 5
      far right   y .320-.331  x 0.80...0.96  fade .035 vFade .20 lift 2
      shoreline   y .252-.292  x 0.50...0.565 fade .040 vFade .34 lift 8

  THE HORIZON IS AT scene_y +0.352 — MEASURE IT BEFORE PLACING ANY BAND.
  (R-B across x .20-.45 flips from -37 at y .348 to +91 at y .352.) A
  "far water" band once spanned y .328-.362 and was visibly ANIMATING THE
  SKY on the left. Rows .335-.345 are blocked by distant rocks anyway, so
  there is no usable sea band above y +.332 — nothing up there should move.

  THE ROCK/WATER GEOMETRY, measured row by row (both boundaries):
      y .240-.290  clear x .28 -> .63      boulder field
      y .295-.305  clear x .14 -> .77
      y .310-.330  clear from the left edge -> .78, and -> .95 above .320
      y .335-.345  blocked by distant rocks
      y .352+      SKY
  The right side is a SLOT ~0.010-0.020 tall. A slice cannot be thinner than
  its own feather plus travel padding, so any band reaching past x .62 puts
  some motion on the boulder cluster. That is a real trade-off, not a bug to
  fix: more right-side life costs rock stillness. Current balance:
      middle left 38.5% · middle right 50.4% · far right 31.8%
      sky 0.0% · foreground 0.0% · worst moving-rock 21.6%
  The quieter alternative (right ~6%, far right 0%) held rocks near 5%.

  MEASURING ROCKS: derive the rock mask from the AMBIENT-OFF control frame,
  never from a run's own frame 0 — otherwise the mask shifts per run and the
  numbers are not comparable. Verified stable to +/-4 points across repeat
  runs of one build.

  MEASURE FRAME-TO-FRAME, NOT AGAINST FRAME 0. Comparing every frame to the
  first measures cumulative drift and climbs regardless of how busy the
  effect is — it reported 72–84% for a config that was calmer than one
  reporting 52%. Consecutive-frame change, by zone:
      too-subtle cut:  open water  5.9%   shoreline 17.4%
      shipped:         open water 22.1%   shoreline 52.4%
      rocks 1.3% · foreground 0.0% in both.

  If the Tide master is ever repainted, RE-MEASURE topY/bottomY/xRange —
  they are constants describing that specific painting.
- MOSS (rebuilt again 2026-09-25): 10 green `mossSpore` motes + 3 gold
  pollen, plus a butterfly the creature CHASES. The falling-leaf `.drift`
  that preceded this is gone — 10 large tumbling sprites crossing the frame
  was too much going on. `mossSpore` is a new motif: lobed, not a disc, with
  a two-pass translucent edge, because a clean circle reads as a UI dot.
  BUTTERFLY — it is the one piece of ambient life that is NOT decorative:
  · `FamilyAmbientNode.onVisitorMove` reports its scene position ~10x/sec
    (and nil when it leaves); `CreatureScene.watchAmbientVisitor` is the
    only bridge between ambient life and the creature.
  · The chase reuses the TOY-PLAY beat machinery (`canToyBeat`,
    `lastCreatureBeatAt`, `sceneHop`) so it inherits every existing guard:
    it cannot fight a carry, a reaction, a hop in flight or a finger, and
    `sceneHop` keeps the creature inside the play area.
  · TWO rhythms: follow on a 0.42s gap with SHORT hops, reach on a 3.4s
    gap. One gap for both gave 7 arm-raises in a single crossing. The hop
    is ~56pt and shrinks to whatever distance is left (min 20pt), so the
    creature settles in behind the butterfly instead of overshooting — one
    118pt leap read as teleporting to it rather than following.
  · `close` is `creatureReach + 15`: anything looser and it stops following
    while still visibly trailing.
  · OFF SCREEN IS GONE. The exit carries the butterfly well past the frame
    edge and it reports its position the whole way, so the scene ignores any
    point outside +/-0.47 of scene size and ends the chase there. Without
    that the creature keeps hopping after something it cannot see.
  · The FLIGHT PATH is approach -> hover -> leave, not one sweep: a single
    crossing put it near the creature for only a moment, so Aurie spent the
    visit chasing something already gone. The hover is the interaction
    window. Each segment is a sampled CGPath with two incommensurate sines
    for the bob and a warped `t` so ground speed is uneven — straight
    `moveBy` legs do not read as a butterfly.
  · Interval 150...300s. It is meant to be luck, not a loop.
  · DO NOT gate the chase on `glanceToward`'s return value. It returns false
    whenever the eye sparkle is hidden — which every half-lidded or arc-eyed
    expression does on the Blender skin — so gating on it made Aurie stop
    following the moment it blinked sleepily. Eye tracking is decoration
    here; the chase must run regardless.
  · zPosition 85 on the visitor (= +45 in scene): IN FRONT of the creature.
    Ambient sits at -40 so spores stay behind, but a butterfly being watched
    and reached for cannot be behind the head.
  · It must EXIT THE FRAME. It enters at x -/+0.56w, so the legs have to sum
    past 1.12w or it stops mid-scene and fades where the player can see.
- EMBER: `.heat` — tapered convection plumes that rise and waver. Not a
  displacement shader; nothing here touches the painting underneath.
- STARLIGHT: rebuilt 2026-09-22. Was 16 `starDot`s at scale 0.80 with a 30%
  size pulse in the `.upper` zone — which reads as drifting fireflies over
  the path and the creature, not a night sky. Three separate faults:
  · `.upper` spans scene_y +0.10…+0.46, but the Starlight master's open sky
    is ONLY +0.35…+0.50 (measured), and reliably unbroken only above +0.43
    between x 0.20 and 0.86. Everything below that landed on the valley.
    New `Zone.sky` is confined to the measured band.
  · `starDot` carries a 0.6-alpha bloom across half its canvas, so at
    ambient sizes the halo IS the sprite. New `starPinprick` motif: a hard
    white core with a 0.16-alpha halo, ~1.5pt across in use.
  · A 30% `scalePulse` makes a star swell. Stars do not swell — it is now 0.
  Result: 11 fixed points, base 0.10 → peak 1.00 over 3.4…6.2s, plus a
  `glint` every 9–17s as the occasional brighter one.

  THE SKY IS A WEDGE ABOVE A RIDGE — measure the ridge, not "blueness".
  The mountains here are blue-lit at night, so a blue-dominance test calls
  them sky and stars land on the hillside. Find the ridge per column by the
  luminance step instead: it dips to scene_y +0.417 over the valley
  (x ~= .45) and rises to +0.461 at both edges. `Zone.sky` fills the wedge
  between `ridge + 0.012` and +0.497, so an edge star sits high and a
  central one can sit lower — which is also what stops 11 stars reading as
  one straight band.

  THE TWO WALKS MUST BE INDEPENDENT. `q` was 0.3819660113, which is exactly
  1 - 0.6180339887, so q was the mirror of phi and the axes were perfectly
  ANTI-correlated — every wide star forced low, every high one central, and
  the x range collapsed to the left half. Use 0.7548776662 (the 2D
  low-discrepancy partner of the golden ratio). Do NOT additionally couple
  the x-spread to q: that makes the wide-and-high corner vanishingly rare.
  x takes the full width and the per-column floor does the rest.
  Verified: 11 stars, x .08-.87, y +0.434…+0.491, none below the skyline.

  WHERE THE BRIGHTNESS CEILING IS (2026-09-23). `peak` is node alpha and is
  already 1.00 — there is no headroom left in that parameter, so any further
  contrast has to come from the TEXTURE's light output (`starPinprick`
  bloom 0.16 → 0.52, core → 1.0, radius deliberately unchanged at 0.30) or
  from a lower floor (base 0.18 → 0.10). Do not reach for `scale` or
  `scalePulse`: that is what made the original read as a firefly.

  THE REAL LIMIT IS PLACEMENT, NOT BRIGHTNESS. Measured per star as the
  peak-pixel luminance swing across a frame series: stars 3, 4 and 6 swing
  ~55-63 levels, but stars 1 and 2 measure 0.0 and star 5 ~10, because the
  golden-ratio walk drops them on the painted MILKY WAY where the sky is
  already at luminance 225-250 and an additive point has nowhere to go.
  Three of seven contribute nothing, and no amount of extra brightness
  changes that — only moving them would. Flagged to the user rather than
  done, since fixed positions were an explicit constraint.
  TUNED 2026-09-23. The first cut (5 points, 0.26→0.70) was too quiet
  against a sky that already has painted stars in it. Visibility here comes
  from the SWING, not from size or travel, and the swing is measurable:
  sample a 5×5 patch at each star's position (they are deterministic — the
  `Zone.sky` golden-ratio walk reproduces them exactly, no logging needed)
  across a frame series and take max-min luminance. Before: 4–8 levels out
  of 255, ~2%, indistinguishable from nothing. After: ~27 levels on the
  steady stars, 4.7× more. `scale` and `scalePulse` were NOT touched —
  making a star bigger or letting it swell is what made the original read
  as a firefly. Two of the seven sit on the painted Milky Way (luminance
  ~225-250) and barely move the needle there; that is correct, not a bug —
  a star has no headroom against the brightest part of the sky. `glint` is stationary
  by construction. The shooting-star visitor was removed: nothing travels.
  Verified from the SCENE GRAPH, not from pixels — all 5 children sit at
  y +0.436…+0.474. Pixel differencing cannot answer "is anything outside the
  sky?" here, because Aurie's bob and the greeting bubble dwarf five
  pinpricks; two runs with different greeting text made ambient look like it
  was moving the whole lower half. `AURIE_AMBIENT_LOG` now prints EVERY
  child with normalized coordinates for exactly this reason.

BLENDING RULE: things that EMIT light are additive; things that are merely
LIT (leaves, dust) composite normally. Additive only reads against a darker
background — Stone's cream dust over a sunlit alpine meadow was moving
correctly and was simply invisible.

STONE — SETTLED 2026-09-25. The conflict was real: a small neutral mote is
the same VALUE as a sunlit alpine meadow, so it cannot be seen however many
you add. Enlarging them (scale 2.10) made them visible only as grey discs.
The fix is CONTRAST, not size or brightness: new `stoneMote` motif carries a
faint taupe shadow just outside its body, which separates it from bright
ground without any sparkle, glow or highlight — Stone keeps its brief as the
quietest family. Now 14 motes at scale 1.25 (was 6 at 2.10).
`stoneDust` is left untouched because the emitter also uses it for stone
celebration bursts, where a shadow edge would look wrong.
The motif is built from OFFSET LOBES, not concentric circles — clean rings
read as UI dots rather than dust.

NEW `Zone.broad` (2026-09-25). `.sides` packs everything into two narrow
columns at the frame edges, which is why Stone looked clustered. `.broad`
spreads across x .04-.96 and y .10-.92, and a point that lands in the
creature's column is PUSHED above or below the body band instead of being
dropped — so the distribution stays even and nothing crowds Aurie.
Verified: 14 motes, x .04-.91, left 6 / centre 4 / right 4, zero inside the
body box.

DORMANT: `FamilyAmbient.Visitor.butterfly` and `butterflyNode()` are now
unreferenced — Moss was their only caller. So are the `tideWaveCrest` and
`tideFoamWash` motifs and `FamilyParticleArt.foamLine`, left over from Tide
technique 2, and `Visitor.shootingStar` plus `Zone.upper`, which lost their
only caller when Starlight was rebuilt. All left in place, not deleted.

DEBUG AIDS ADDED: `AURIE_AMBIENT_OFF=1` (parallax-only control),
`AURIE_AMBIENT_FAST=1` (shortens only the WAIT before rare effects, never
their motion and never a production default), `AURIE_NO_SHEETS=1`
(withholds the reward card from a capture; presentation itself unaffected).

## S. THE AURA IS BACKDROP-RELATIVE (2026-09-25)

`AurieNode.auraNode` is an ADDITIVE sprite. Additive glow does not read
equally everywhere: the same alpha over a dark environment is an obvious
halo and over a bright one is nearly nothing. Measured on ONE creature, with
the aura the only variable, sampling OUTSIDE the body box:

    dusk   backdrop  42/255 · lift 24.2 · relative 57.5%
    moss   backdrop  56/255 · lift 21.8 · relative 38.9%
    stone  backdrop 104/255 · lift 25.0 · relative 23.9%   <- "can't see it"

`HomeEnvironment.backdropLuminance` samples the sky artwork ONCE (the band
the creature stands in, x .28-.72 / y .52-.82 of the image — not the whole
painting, which mixes a bright sky with a dark floor and gave the wrong
answer). `AurieNode.applyAuraStrength(backdropLuminance:)` then scales alpha
0.60...1.00 AND size 1.0...1.55x with it. Alpha caps at 1, so on the
brightest backdrops SIZE is the only remaining lever — a broader halo reads
where a brighter one cannot. Stone: halo area +54%, relative 23.9% -> 26.1%;
Dusk unchanged.

MEASURING THE AURA — two traps, both of which produced confident wrong
numbers before being caught:
  1. Every uninstall/install generates a DIFFERENT Aurie. An aura-on vs
     aura-off comparison across two installs measures two different
     creatures. Install ONCE, then launch twice against the same store with
     `AURIE_AURA_OFF=1` (DEBUG) on the second.
  2. Even on one install the creature BOBS, so any window overlapping the
     body registers pose, not aura. Measure outside the body box.
Sanity check before trusting a run: the mean difference inside the body core
must be near zero, because the aura renders BEHIND the body (z .aura = 0).

## T. THE BALL HAS A DEPTH AXIS (2026-09-25)

The ball was a flat side-on sim: `p.x` across, `p.y` as HEIGHT with gravity,
floor at a single `ballGroundY`. It could only ever travel left and right.
It now carries `ballDepth` (0 far … 1 near) and moves down the field too.

WHAT DEPTH TOUCHES — all of it together, or the ball leaves the perspective:
  · floor line   `CreatureScene.toyField(depth:)` -> `playfield.footY`
  · render scale  same call -> `playfield.scaleMultiplier`
  · side walls    narrowed with distance (NOT `playfield.halfWidth` — that is
    the creature's 13-21% walking corridor and would pen the ball into a
    strip; the ball gets most of the frame, narrowing by the same ratio)
  · shadow        scales with the ball's own xScale as well as its height,
    or a ball kicked away keeps a full-size shadow and looks like it is
    floating toward the horizon

HEIGHT IS STORED SEPARATELY from the sprite's y (`ballHeight`, world units).
The floor MOVES when depth changes, so keeping absolute y would make a ball
kicked away appear to leap into the air. Height is scaled only when drawn,
so a bounce keeps its shape wherever the ball is standing.

`ballDepthFar` = 0.34, not 0: at the very far edge the ball is tiny and sits
on the horizon line, which reads as stuck to the backdrop.

KICKS: `kickBall(direction:depth:)`. `depth` is the impulse — negative sends
it away, positive brings it back, 0 is the old sideways kick. A kick with
depth puts proportionally LESS into the sideways throw, or a "forward" kick
still sails off to one side. `ballPlayBeat` picks the direction from where
the ball already is (deep -> bring it back, near -> boot it away) so the
rally travels both ways instead of drifting to one end; a third of kicks
stay purely sideways to keep the original left/right rally in the mix.
A drag release also splits its vertical flick between height and depth, so
the player can throw the ball into the distance.

DEPTH HAS THREE CONSEQUENCES BEYOND MOVEMENT — all reported as bugs:
  1. Z-ORDER. The toy root sits at z 30, above everything, which was fine
     while the ball could only go sideways. A ball rolling on ground FURTHER
     AWAY than Aurie still drew in front of it. `updateBallDepthOrder`
     re-sorts it against the creature every tick; the offset crosses zero
     exactly at the creature's depth, with a +6 bias so a tie renders in
     front (a ball at the feet belongs on the near side).
  2. NO KICKING FROM BEHIND. If the ball is deeper than the creature it
     cannot be struck — that would be kicking backwards through its own
     body. `ballPlayBeat` returns early and instead walks the creature
     AROUND the ball (to `ballDepth - 0.07`, floored at 0.20 so it does not
     trek to the horizon and render tiny), after which the ordinary kick
     applies, now aimed back toward the viewer.
  3. NEAR MEANS NEAR IN THREE AXES. Screen-space `dx` was a sufficient
     proximity test with no depth axis; with one, a ball at the same x can
     be halfway down the field. Kick, bat and two-hand push all additionally
     require `abs(ballDepth - creatureDepth) < 0.10`, and the approach hop
     closes the DEPTH gap as well as the sideways one — otherwise the
     creature arrives alongside and kicks at nothing.

EAGERNESS (2026-09-25). The beat gaps were paced for a toy that only
drifted sideways and made the creature look uninterested once the ball had
a field to travel: approach 9s -> 1.5s, kick 4 -> 2, two-hand push 5 -> 3,
go-around 3.5 -> 1.6, and the approach hop is now an explicit quick one
(0.26s, height 30) rather than the distance-scaled default.
The bigger miss was that a MOVING ball out of range only got a glance — the
creature stood still through the whole rally it had just started. It now
chases a moving ball as well as a resting one.
Measured over 45s: 8 kicks + 1 bat + 2 go-arounds, against 3 kicks before.

LOGGING TRAP: `sceneHop` updates `fieldPos` immediately, so a log line
printed after it reports the DESTINATION depth, not the one just tested —
which makes a correct comparison look wrong ("ball behind 0.38 < 0.26").
Capture the pre-hop depth first.

DEBUG AID: `AURIE_TOY=ball|bubble` opens a toy on launch. It must set BOTH
the `activeToy` state AND call `scene.setActiveToy(...)` — the shelf button
does both, and setting only the state looks right and spawns nothing.
