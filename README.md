# Aurie - Swift model + generator + content

The brains of Aurie in Swift: a photographed object becomes one unique, saveable
creature. Base creature always works; object recognition adds flavour on top; each
creature is given one permanent line at hatch, and reacts to play with short lines.

> Supersedes the earlier C# files for the model and generator. `ART_GUIDE.md` covers
> the art pipeline (parts, shading, detail charms, and family backgrounds).

## Files

| File | What it is |
|------|------------|
| `AurieModels.swift` | Enums, structs, `DetailSlots`, `RecognizedObject`, and the `Codable` `Aurie` record. |
| `AurieContent.swift` | Codable shapes mirroring the JSON + a class with lookup maps and a loader. |
| `AurieGenerator.swift` | Hatch pipeline, the permanent-line composer, and the play reaction helpers. |
| `AurieNode.swift` | SpriteKit creature node: assembles parts, tints, and animates (bob, blink, hop, bounce). |
| `aurie_content.json` | All the words + the category / hero tables. The delight lever - expand freely. |
| `daily_content.json` | Home daily-lift content: `quotes` / `jokes` / `dares` (app-wide, not creature lines). |
| `DailyLift.swift` | Loads `daily_content.json` and picks one item per calendar day (deterministic, no storage). |

## The three layers (a hatch)

```
photo -> (Vision + image step) -> dominant colour, ShapeSignal, RecognizedObject?
  Layer 1  ALWAYS: colour -> family, shape -> body, eyes/mouth/limbs, colour, aura,
                   name, the permanent LINE (composed), and a personality trio
  Layer 2  IF recognised (confidence >= 0.40, category != unknown): category fills
                   detail slots (charms, pattern, texture)
  Layer 3  IF a hero object matches the label: stamps that object's signature detail
```

Unknown / low-confidence recognition runs Layer 1 only; the profile reads
"born from a mysterious shape". A bad photo is never a failure, just a plainer creature.

### Colour -> family (hue degrees)

Stone first (saturation < 0.18 or value < 0.12), then: Ember < 40 or >= 330 · Glow 40-70
· Moss 70-165 · Tide 165-255 · Dusk 255-330. Starlight is a ~4% override. Stone is the
most common (most objects are neutral) - that's why it has the driest, funniest lines.

## Lines (two kinds, don't confuse them)

**1. The permanent line** - each creature's identity, unique, never changes.
It is *composed at hatch* by `composeLine`: pick one of the family's `lineTemplates`,
fill `{name}` with the creature's name and `{mood}` with a random family mood word.
Stored on the creature (`Aurie.line`) and shown on Home and the full-screen view.
Because it's built from templates x name x mood, supply is endless and no two feel the
same - so it never runs out (the reason it isn't a hand-written used-once pool).
Starlight is the exception: its `lineTemplates` are hand-written witty one-offs with no
blanks (they're rare, so the pool won't run dry).

**2. Reaction lines** - play barks, repeat freely, NOT stored on the creature:
- `shakeLine(for:)` and `petLine(for:)` - family-flavoured (per-family `shake` / `pet`).
- `tickleLine(_:)` and `pickupLine(_:)` - shared pools (`sharedPlay`), any creature.

Separately, each creature stores a **personality trio** - 3 adjectives drawn from its
family's `traits` pool at hatch (e.g. Calm · Curious · Gentle), kept on `Aurie.traits`
and shown on the detail screen. Not a line.

A third, unrelated "daily" thing lives on Home: the **daily lift** card — an app-wide
quote, joke, or dare (one per calendar day) from `daily_content.json`, handled by
`DailyLift.swift`. It is *not* a creature line and does **not** change when you switch
featured Auries. See `BUILD_BRIEF.md` §18.

## Detail-slot ID vocab (match your Illustrator exports)

| Slot | IDs |
|------|-----|
| headCharm | 0 leaf · 1 petal · 2 antenna · 3 bow |
| bellyPattern | 0 speckle · 1 page-lines · 2 curve-stripe · 3 pocket · 4 pixel |
| sideDetail | 0 handle · 1 button |
| tailCharm | 0 key · 1 peel-curl · 2 leaf-sprig |
| texture | 0 glossy · 1 fabric · 2 mossy |
| cheekMark | 0 freckles · 1 swirl |

## Rendering + tinting (SpriteKit)

Stack parts by `zPosition`: aura -> limbs -> body -> pattern -> charms -> eyes -> mouth.
Tint body/limbs/pattern via `node.color` + `colorBlendFactor = 1` (pattern = a darker
base). Eyes / mouth / charms keep `colorBlendFactor = 0`. Aura is a soft glow node tinted
with `auraColor`, additive, plus a sparkle emitter for the hatch. For the glossy 3D look,
draw each tintable part in three sub-layers (white midtone that gets tinted + highlight +
soft shadow) so it reads dimensional in any colour.

## Family backgrounds

Each aura family has one soft full-screen **background** (7 total), shown on the
single-creature screens (Home + full-screen view) and reflecting the creature's family.
Grid and camera stay neutral. Display with **aspect-fill** and keep the focal art
centred (safe-zone rule in `ART_GUIDE.md`). Until the art exists, fall back to a plain
family-coloured tint. Wire a `background` asset slot per family, like the parts.

## Object recognition (Vision)

`VNClassifyImageRequest` runs on-device, no training, returns labels + confidence. Your
app: sample dominant colour + shape (Layer 1), run Vision for a label + confidence, bucket
the label into an `ObjectCategory` via a lookup table you maintain, and hand a
`RecognizedObject` to `generate` (or `nil` for unknown). Curate the ~10 hero objects
you'll demo with so the Layer-3 details show reliably.

## Expanding content (all JSON, no code change)

- **Lines / voice / traits:** edit a family's `lineTemplates`, `moods`, `shake`, `pet`,
  and `traits` (personality adjectives). Add Starlight one-offs to its `lineTemplates`.
  Shared play barks live in `sharedPlay`.
- **Object flavour:** add IDs to a category's slot pools in `categories`.
- **Hero object:** add an entry to `heroes` with its label, category, and signature slot id(s).
- **Base parts:** add sprites and bump `eyesCount` / `mouthCount` / `limbsCount` in the generator.
- **Backgrounds:** add a `background_<family>` image per family (see `ART_GUIDE.md`).

## Where this fits (see `BUILD_BRIEF.md` for the full plan)

Scaffolding, tabs, persistence, and the sample-image hatch flow (photo → egg → crack →
reveal → auto-save) are already built. Next is core play, then the winning polish — egg
personalities, family hatch/reaction particle effects, a birth reaction, idle moments,
expression states, and haptics (all app-side behaviours layered on `AurieNode`, specified
in `BUILD_BRIEF.md`, not in these data/model files) — then monetization.

Monetization is **consumable hatch packs only**: free hatches (3 on day one, then 1/day),
buy 5 ($2.99) / 10 ($4.99) / 20 ($8.99, best value), and a rewarded-ad hatch. No
subscription, no unlimited, no purchasable rarity odds.
