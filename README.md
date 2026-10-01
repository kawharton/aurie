# Aurie - Swift model + generator + content

Aurie in Swift: a photographed object becomes one unique, saveable
creature. Base creature always works; object recognition adds additional detail; each
creature is given one permanent line at hatch, and reacts to play with short lines.

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
photo -> (Vision + image step) -> dominant color, ShapeSignal, RecognizedObject?
  Layer 1  ALWAYS: color -> family, shape -> body, eyes/mouth/limbs, color, aura,
                   name, the permanent LINE (composed), and a personality trio
  Layer 2  IF recognized (confidence >= 0.40, category != unknown): category fills
                   detail slots (charms, pattern, texture)
  Layer 3  IF a hero object matches the label: stamps that object's signature detail
```

Unknown / low-confidence recognition runs Layer 1 only; the profile reads
"born from a mysterious shape". A bad photo is never a failure, just a plainer creature.

### Color -> family (hue degrees)

Stone first (saturation < 0.18 or value < 0.12), then: Ember < 40 or >= 330 · Glow 40-70
· Moss 70-165 · Tide 165-255 · Dusk 255-330. Starlight is a ~4% override. 

## Lines

**1. The permanent line** - each creature's identity, unique, never changes.
It is *composed at hatch* by `composeLine`: pick one of the family's `lineTemplates`,
fill `{name}` with the creature's name and `{mood}` with a random family mood word.
Stored on the creature (`Aurie.line`) and shown on Home and the full-screen view.

**2. Reaction lines** - not stored on the creature:
- `shakeLine(for:)` and `petLine(for:)` - family-flavored (per-family `shake` / `pet`).
- `tickleLine(_:)` and `pickupLine(_:)` - shared pools (`sharedPlay`), any creature.

Separately, each creature stores a **personality trio** - 3 adjectives drawn from its
family's `traits` pool at hatch, kept on `Aurie.traits`
and shown on the detail screen.


## Rendering + tinting (SpriteKit)

Stack parts by `zPosition`: aura -> limbs -> body -> pattern -> charms -> eyes -> mouth.
Tint body/limbs/pattern via `node.color` + `colorBlendFactor = 1` (pattern = a darker
base). Eyes / mouth / charms keep `colorBlendFactor = 0`. Aura is a soft glow node tinted
with `auraColor`, additive, plus a sparkle emitter for the hatch. For the glossy 3D look,
draw each tintable part in three sub-layers (white midtone that gets tinted + highlight +
soft shadow) so it reads dimensional in any color.

## Family backgrounds

Each aura family has one soft full-screen **background** (7 total), shown on the
single-creature screens (Home + full-screen view) and reflecting the creature's family.
Grid and camera stay neutral. Display with **aspect-fill** and keep the focal art
centered (safe-zone rule in `ART_GUIDE.md`). 

## Object recognition (Vision)

`VNClassifyImageRequest` runs on-device, no training, returns labels + confidence. Your
app: sample dominant color + shape (Layer 1), run Vision for a label + confidence, bucket
the label into an `ObjectCategory` via a lookup table you maintain, and hand a
`RecognizedObject` to `generate` (or `nil` for unknown).

## Expanding content (all JSON)

- **Lines / voice / traits:** edit a family's `lineTemplates`, `moods`, `shake`, `pet`,
  and `traits` (personality adjectives). Add Starlight one-offs to its `lineTemplates`.
  Shared play barks live in `sharedPlay`.
- **Object additions:** add IDs to a category's slot pools in `categories`.
- **Hero object:** add an entry to `heroes` with its label, category, and signature slot id(s).
- **Base parts:** add sprites and bump `eyesCount` / `mouthCount` / `limbsCount` in the generator.
- **Backgrounds:** add a `background_<family>` image per family (see `ART_GUIDE.md`).

## Where this fits 

Scaffolding, tabs, persistence, and the sample-image hatch flow (photo → egg → crack →
reveal → auto-save) are already built. Next is core play, then the egg
personalities, family hatch/reaction particle effects, a birth reaction, idle moments,
expression states, and haptics (all app-side behaviors layered on `AurieNode`, specified
in `BUILD_BRIEF.md`, not in these data/model files) — then monetization.

Monetization is **consumable hatch packs only**: free hatches (3 on day one, then 1/day), use RevenueCat
