# Birth Charms — architecture audit (2026-09-14)

Product requirement audit only. NO code was modified. Scope: where
Birth Charms (charms unlocked only by a qualifying photographed
object, then owned like any other charm) will land in the existing
codebase, and what should change now vs later.

---

## 1. Existing charm-related models/files

Three "charm" systems exist today, at very different maturity:

**A. The charm asset library** — `AurieCharmLibrary/` (repo root).
80 catalogued charms (Quaternius CC0), ids frozen as
`charm_<category>_<name>_NN`. `_MANIFESTS/charms.json` is the single
machine index (39 launch / 33 future / 8 review via `launchStatus`);
`_PROCESSED/*.blend` are the 60 processed masters;
`_THUMBNAILS/*.png` previews; per-charm JSON records in category
folders carry a TRUE-3D `attachment` block (`position` + `normal` in
`charm_local_normalized` space, types BODY_FRONT / BODY_SIDE /
HANGING / HEAD / BACK). Not wired into the app ("Nothing in here is
wired into the iOS app yet" — its README).
Design-side tooling: `Design/Aurie3D/Scripts/charm_library.py`,
`charm_processor.py`, `charm_profiles.py`, `charm_on_aurie.py`,
`charm_contact_sheet.py`, `charm_inventory.csv` (launch status), and
`accessory_slots.py` — the deliberate three-slot placement system
(TAIL_HANGING / HEAD / BACK) with per-body anchors measured off each
mesh at export (`write_manifest` ships `anchors.tail/head/back` per
body in the export manifests).

**B. The dormant per-Aurie accessory fields** —
`Auries/Models/AurieModels.swift:197-217`: `tailAccessoryID` /
`headAccessoryID` / `backAccessoryID` (stable `charm_…` string ids,
"never repurpose one") + the deliberately-closed
`AccessorySlot { tail, head, back }`. A repo-wide grep shows NOTHING
reads or writes these — they are a forward declaration. `AurieNode`
reserves `Z.charm = 4` in its z-order but never adds a sprite there;
`AssetLoader` has the matching TODO.

**C. Legacy 2D DetailSlots** — `AurieModels.swift:131-139`:
`headCharmId/cheekMarkId/bellyPatternId/sideDetailId/tailCharmId/
textureId` as `Int?` sprite-atlas indices, filled by the generator
from `CategoryContent`/`HeroObject`; only `bellyPatternId` ever
renders. NAMING COLLISION WARNING: "headCharmId" (legacy Int) vs
"headAccessoryID" (forward path). Birth Charms belong to system B/A,
never C.

## 2. Where recognition enters generation

`Recognition.classify` (Vision `VNClassifyImageRequest`,
`Services/Recognition.swift`) → `RecognizedObject { label?,
category, confidence }` (`AurieModels.swift:109-118`) → called only
from `AppModel.prepareHatch` (`AppModel.swift:125`) →
`AurieGenerator.generate(dominantColor:shape:recognized:…)`
(`Generation/AurieGenerator.swift:27-104`). The generator uses
`recognized` (gate ≥0.40, category ≠ unknown) to set
`category`/`bornFrom` and fill the LEGACY DetailSlots, with ten hero
labels (banana, apple, flower, mug, cup, book, key, phone, backpack,
teddy) applying hero overrides. It never touches the accessory ids.

Hatch flow: `AppModel.generateHatch` (pure, no persistence,
cancellable free) → `EggHatchView` warms the preview during the
crack → `AppModel.commitHatch` (`AppModel.swift:183-192`) is the ONE
persistence point: thumbnail → `store.add(aurie)` →
`wallet.consumeHatch()`.

## 3. Where the Birth Charm hook cleanly belongs

Two-phase, matching the existing generate/commit split:

- **Determine the grant at generation time** (pure): a lookup from
  `RecognizedObject.label` → charm id, evaluated next to the
  existing hero-object branch in `AurieGenerator.generate` (or a
  sibling pure helper the generator and UI both call). This lets the
  hatch preview SHOW the newborn wearing the charm — the product
  moment — while staying free to cancel. The ten hero labels already
  map 1:1 onto library charms (`charm_object_key_01`,
  `charm_food_apple_01`, `charm_food_banana_01`,
  `charm_object_backpack_01`, `charm_object_book_01`, …).
- **Grant at commit time** (side effects): in `commitHatch`, before
  `store.add` — add the charm to the user-level inventory
  (idempotently) and set the newborn's equipped slot. `commitHatch`
  is already the only place hatch side effects happen
  (`wallet.consumeHatch` lives there), and `HatchWallet`'s
  `processedGrantIds: Set<String>` is the in-repo precedent for
  idempotent grant ledgers.

The "saved differs from born only by sourceThumbnail" invariant
(`EggHatchView.swift:404`) gains one documented delta: the birth
charm equip + inventory grant.

## 4. Data-model assumptions that make removable/shared charms hard

1. **No user-level charm inventory exists.** The per-Aurie accessory
   ids are the only place charm possession could live today. THE key
   hazard: `store.delete(aurie)` erases the Aurie entirely — if a
   birth charm's only record is on the Aurie it arrived with,
   deleting that Aurie destroys a permanent unlock. Ownership must
   be account-level (like `wallet.json`), with per-Aurie fields
   meaning only "equipped here".
2. **Equipment is three hardcoded optional fields**, not a
   slot-keyed map. Growing to the 14-slot future list means adding a
   field per slot forever, or migrating to
   `equippedCharms: [String: String]` (slot rawValue → charm id).
   Because the three fields are dormant (never written, nil in every
   save), replacing them costs nothing TODAY and something every day
   after they first ship populated.
3. **No acquisition metadata anywhere.** `charms.json` has
   provenance/processing/launchStatus but no `acquisition` /
   `trigger` fields; `charm_inventory.csv` has only Launch/Future.
   Purely additive JSON — zero app impact to add now.
4. **`launchStatus` is not read by the app** — any inventory/equip
   feature must add that gate itself (mirror of
   `AurieLimbCatalog.launch*` pools).
5. **Legacy DetailSlots naming collision** (see §1C) invites wiring
   the wrong system; worth a deprecation comment when charms ship.

## 5. Front-only assumptions that could block back/side/3-4 views

- All runtime layout is 2D points on one front canvas
  (`AurieBlenderAssets.Layer {asset, size, position}`, arm/leg
  pivots as `CGPoint` "POINTS from the art centre").
- Orientation is PINNED (`AurieNode.face(_:)` is a deliberate no-op
  — mirror flips were removed because baked lighting swaps sides).
- The export manifests' accessory anchors are `[x, 0, z]` — front
  plane only.
- `accessory_slots.py` placements are front-projection compositing
  rules.

NOT blocked, and worth protecting: the charm library's attachment
data is true 3D (position + normal in charm-local space) and every
charm/body master is a 3D .blend — back/side renders and
per-orientation anchors are derivable from the pipeline at any time.
The rule to preserve: **placement derivation stays in the Blender
export pipeline, never hand-tuned in Swift** — then "add an
orientation" = re-render layers + export per-orientation anchors,
with asset names gaining an orientation key (reserve the
`aurie_<body>_<orientation>_<layer>` namespace; today's assets are
implicitly `front`).

## 6. Smallest launch-safe changes recommended now

Nothing charm-visible ships at launch, so the list is deliberately
tiny:

1. **Convert the three dormant accessory fields to a map**
   (`equippedCharms: [String: String]` keyed by `AccessorySlot`
   rawValue) BEFORE any build writes them. Zero-migration today
   (fields are nil everywhere; lenient `decodeIfPresent` decoding
   already tolerates the change); painful later. ~20 lines.
2. **Reserve the inventory schema** — a `charms.json` sibling of
   `wallet.json`: `{ unlocked: [{id, source, date, bornFromAurieId?}],
   processedGrantIds: [String] }`. It can ship EMPTY and unread; its
   existence pins the contract that ownership is account-level.
   (Even doc-only reservation is acceptable; an empty file decoded
   leniently is safer.)
3. **Add `acquisition` + `trigger` fields to the charm manifest
   schema** (additive JSON in `charms.json` / `charm_library.py`),
   e.g. `acquisition: birthOnly|playReward|achievement|seasonal|
   event`, `trigger: {type: "recognizedLabel", value: "key"}`.
   No app code reads it yet.
4. **One deprecation comment** on `DetailSlots` charm fields
   pointing at the accessory system, to prevent mis-wiring.

Everything else (grant service, inventory UI, discovery book,
equip/unequip UX, per-orientation anchors, additional slots) is
post-launch and fits the architecture above without migration.

## Flagged product decisions (not decided here)

- **Duplicate unlocks**: photographing a second key after the Golden
  Key is owned — no-op, duplicate token, or cosmetic variant?
  (Flagged per the requirement; grant idempotency should be built
  either way.)
- **Simultaneous equip**: can one owned charm be equipped on several
  Auries at once, or is it checked out to one wearer? Inventory
  model supports either; pick before equip UX ships.
- **Category-level Birth Charms** (vs hero-specific): deferred by
  the requirement itself; the trigger schema above already admits
  `{type: "category", value: "food"}`.
