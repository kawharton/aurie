# A — Charm system architecture audit (2026-09-16)

READ-ONLY. Nothing changed, nothing committed. Scope: what the current
`CharmDefinition` / `CharmService` / `equippedCharms` must change to
support placement × theme × acquisition as three independent concepts,
hundreds of future charms, and a charm library that will lose members.

## 1. What exists today

| piece | file | state |
| --- | --- | --- |
| `CharmSlot` | Models/CharmModels.swift | enum: head, back, bodySide, bodyFront, hanging |
| `EquippedCharm` | same | `{charmID, slot: String, side: String?}`, lenient decode |
| `CharmDefinition` | same | `{id, displayName, category: String, slot, launch, acquisition: String}` |
| `AurieCharmCatalog` | same | hand-written, **2 entries** (proof scope) |
| `CharmCollection` | Services/CharmCollection.swift | `{unlockedCharmIDs: Set, processedGrantIds: Set}` → charms.json |
| `CharmService` | same | `isUnlocked`, `unlock` (idempotent), atomic save |
| `Aurie.equippedCharms` | Models/AurieModels.swift | `[EquippedCharm]?` + `resolvedEquippedCharms` |
| `Store.update(_:)` | Services/Store.swift | the equip/unequip persistence seam |

## 2. What ALREADY satisfies the new requirements — keep as-is

These were built the right way and need no change:

1. **Ownership is account-level, quantity-free, non-consuming.**
   `unlockedCharmIDs` is a `Set<String>` in charms.json beside
   wallet.json. Deleting an Aurie cannot touch it; equipping does not
   remove it; the same id can be equipped on any number of Auries.
   Requirements §8 are already met.
2. **One unlock mechanism for every acquisition path.**
   `CharmService.unlock(id)` is idempotent and returns whether the
   unlock was NEW. Birth photo, task reward, achievement and any future
   source all call this one function — §6's "all acquisition paths call
   the SAME unlock mechanism" is already true.
3. **Grant idempotency ledger.** `processedGrantIds` exists and is
   unused — exactly what §13's "granting must be idempotent" needs.
4. **Equipped state is per-Aurie and extensible.** `equippedCharms` is
   an array of records, and `slot` persists as a **String**, so new
   placements need no migration (§1's "represent them without a
   migration later").
5. **Lenient decoding throughout.** Pre-charm saves decode, unknown
   future fields are ignored, a missing slot resolves from the catalog.

## 3. What must CHANGE

### 3.1 `category: String` (single) → `categories: [String]` — REQUIRED

§2 requires multiple tags per charm (apple = Food + Fruit & Vegetables
+ Nature). Today it is one string, and worse, it currently holds the
*library folder* ("objects", "animals") — a provenance artifact, not a
product taxonomy. **This is the single biggest mismatch.**

### 3.2 `slot: CharmSlot` (single) → `placements: [String]` — REQUIRED

§1 says "a charm may support more than one compatible placement".
Today a charm has exactly one. Also `CharmSlot` is missing `belly`
entirely — the placement we just built art for — plus the eleven
planned ones. Note `EquippedCharm.slot` is already a String, so only
the *definition* side is rigid.

Recommendation: keep `CharmSlot` as a convenience enum for the few
placements with real pipelines, but make the definition's list
`[String]` so the catalog can express placements the enum does not yet
name. Add `belly` to the enum now.

### 3.3 `acquisition: String` (single) → `acquisitionSources: [String]` — REQUIRED

§6 lists eight sources, and one charm may be reachable by more than one
(a starter charm that is also a task reward). Today it is one string,
currently "unassigned" everywhere.

### 3.4 Birth triggers must NOT live on the definition's category — NEW

§4 demands a separate trigger system. Nothing exists yet. The
definition needs only a back-reference (`birthTriggerIDs: [String]`);
the trigger table itself is a separate catalog:

    BirthCharmTrigger { id, acceptedRecognitionLabels: [String], unlockCharmID }

Keeping it separate is what stops "food" unlocking every food charm.

### 3.5 The category catalog must be data-driven — NEW

§12 forbids a switch-per-category. Categories should be stable string
ids (`animals`, `ocean`, `medical`) plus a separate catalog supplying
display names, so adding a theme is data, not code.

### 3.6 `AurieCharmCatalog` must become GENERATED — REQUIRED

It is hand-written with 2 entries. §CORE says the taxonomy must not
depend on the current library and must scale to hundreds. The
installer already generates `AurieBlenderAssets.swift` from the
manifest; the charm catalog should be generated the same way, from a
manifest that carries the new fields.

**Consequence worth stating:** the taxonomy fields (categories,
placements, acquisition, triggers) do not exist in `charms.json`
today. They are product metadata, not processing output — so they need
an authoring file the processor does not overwrite, merged into the
generated catalog. Otherwise re-running the charm processor would
erase the taxonomy.

### 3.7 Charms that disappear from the library — NEW

§CORE says some charms will be removed. Two rules are needed:
- a saved Aurie equipping a now-unknown id must render bare, not crash
  (today `charmLayerKeys` already drops unknown ids — **safe**);
- an unlocked id that no longer exists must stay in `unlockedCharmIDs`
  harmlessly (today it does — a `Set<String>` with no validation).
Both already behave correctly; they just need a test and a comment.

## 4. Smallest viable change set

| # | change | risk |
| --- | --- | --- |
| 1 | `category: String` → `categories: [String]` | low — 2 call sites |
| 2 | `slot: CharmSlot` → `placements: [String]` (+ `belly` case) | low — definition side only; `EquippedCharm` untouched |
| 3 | `acquisition: String` → `acquisitionSources: [String]` | low — currently unused |
| 4 | add `birthTriggerIDs: [String]` (default empty) | none |
| 5 | new `CharmCategoryCatalog` (id → display name), data-driven | none |
| 6 | new `BirthCharmTrigger` table, separate from categories | none |
| 7 | generate `AurieCharmCatalog` from manifest + taxonomy file | medium — new authoring file + installer work |

**Backward compatibility:** `CharmDefinition` is a pure in-memory
catalog type — it is NEVER persisted. Only `EquippedCharm` and
`CharmCollection` touch disk, and neither needs to change. So items
1–6 are free of migration risk entirely; nothing on disk moves.

That is the key finding: **the taxonomy rework costs no migration**,
because the persisted surface (`{charmID, slot, side}` + a set of ids)
is already the right shape and is deliberately decoupled from the
catalog.

## 5. What is NOT needed yet

- `rarity`, `sortOrder`, `discoveryHint` — §11 says only if needed; no
  evidence yet. Adding them later costs nothing (in-memory type).
- A second inventory for task rewards — §7 explicitly forbids it;
  `CharmService.unlock` already covers it.
- Any change to `CharmCollection`, `Store`, or `equippedCharms`.

## 6. Open questions for the product owner

1. **Placement compatibility vs. art.** A charm may *declare* several
   placements, but art exists per placement. Does a charm with
   `placements: [belly, back]` need art for both before it can be
   offered in either, or should the UI offer only the placements that
   have art?
2. **Category source of truth.** The taxonomy file is hand-authored
   (categories are editorial judgements). Should it live beside the
   manifest in `AurieCharmLibrary/`, or in the app repo?
3. **`bodyFront` vs `belly`.** The existing enum has `bodyFront` (from
   the library's attachment type) and the new work introduces `belly`.
   These are the same surface under two names — recommend `belly` as
   the product term, with `bodyFront` retained only as a library-side
   attachment value.

## Not done

No code changed. Next steps B–E remain queued and gated.
