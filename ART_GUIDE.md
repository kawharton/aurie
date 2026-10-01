# Aurie — art production guide (Illustrator → SpriteKit / iOS)

How to design creature parts, charms, and backgrounds so any combination assembles
into a clean, cute, dimensional creature. Read this once before drawing; it will save
you from re-aligning dozens of parts later.

---

## 1. The one rule: shared canvas + shared anchors + full-frame export

- **One artboard size for everything.** Design every part on an identical square
  artboard — **1024 × 1024 px** is a good default. Never change it between parts.

- **Full-frame export.** Export each part as a full-canvas PNG with a transparent
  background: the part sits where it belongs on the frame, everything else is empty.
  In the app you then stack all layers at the *same* position — no offsets, no maths,
  perfect alignment every time.
  - Trade-off: this uses more texture memory than tightly-cropped sprites. Fine for an
    MVP. Optimise later by packing parts into a SpriteKit texture atlas.

- **Shared anchor zones.** Fixed regions that *every* body variant must respect, so any
  part or charm fits any body:

  | Anchor | Purpose | Suggested zone (on a 1024 canvas) |
  |--------|---------|-----------------------------------|
  | Head-charm spot | top of the head (leaf, petal, bow) | around y = 300–380, centred |
  | Eye-line | where eyes sit | horizontal band around y = 400–520 |
  | Mouth spot | where the mouth sits | around y = 560–640, centred |
  | Shoulder points | where arms attach | around y = 560, x = 300 & 724 |
  | Side-detail spot | body edge (handle, button) | around x = 720, y = 520–600 |
  | Hip points | where legs attach | around y = 760, x = 380 & 644 |
  | Tail-charm spot | lower back / base | around y = 720, behind the body |
  | Body footprint | max body silhouette | centred, within ~700 px tall |

  Treat these as law. Every body keeps its eye-line, shoulders, hips, and charm spots at
  these coordinates, so one set of eyes / limbs / charms fits all five bodies.

---

## 2. Draw order (z-order), back to front

1. **Aura glow** — soft blob behind everything
2. **Limbs** — one piece = a full set (both arms + both legs), drawn *behind* the body
3. **Body**
4. **Pattern** — markings overlaid on the body
5. **Charms / detail slots** — head charm, side detail, tail charm, texture (optional)
6. **Eyes**
7. **Mouth**

Keeping all limbs on the single back layer (matching the one `limbsId` slot) avoids
splitting limbs into front/back — simplest for the MVP.

---

## 3. Colour: what to draw white vs final

The generator gives each creature a **baseColor** (its main colour) and an **auraColor**
(its glow). The renderer tints the "white" parts; the "final" parts are shown as drawn.

| Part | Draw it as | Why |
|------|-----------|-----|
| **Body** | white / very light neutral | tinted by baseColor — white tints to any colour cleanly |
| **Limbs** | white / light neutral | tinted with baseColor so limbs match the body |
| **Pattern** | white / light neutral | tinted with a darker shade of baseColor to read as markings |
| **Eyes** | **final colours** (whites, pupils, highlights) | features; consistent, never tinted |
| **Mouth** | **final colours** (usually a dark shape/line) | a readable feature, not tinted |
| **Charms / details** | **final colours by default** (a leaf is green, a key is gold) | recolouring a charm would break it |
| **Aura glow** | soft white blob | tinted with auraColor at low opacity |

**Tintable charm exception.** If a charm is meant to match the creature (e.g. a
body-coloured bow), draw *that one* white and mark it **tintable**, so it takes baseColor
like the body. Default is final colour; tintable is the opt-in.

### The three-sublayer shading (for the glossy, dimensional look)

A flat white shape tints to any colour but looks flat. To get the soft, 3-D "vinyl toy"
look — while still tinting cleanly — draw each **tintable** part in three stacked
sub-layers:

1. **Midtone** — a white / light-grey base. This is the layer the app tints with baseColor.
2. **Highlight** — a near-white shape on top (upper-left), for the shine.
3. **Shadow** — a soft semi-transparent dark shape (multiply), lower-right, for form.

The form then reads round in *any* colour. Minimum viable version: just the white midtone
plus one soft shadow overlay. Full glossy: add the highlight layer too.

---

## 4. Style consistency (so parts are interchangeable)

- **One viewing angle: front-facing.** Straight-on reads cutest and stays mirror-flippable
  (so left/right facing is free). Don't mix in true 3/4 or side views.
- **One consistent light direction: upper-left.** Highlights top-left, shadows
  bottom-right, on *every* part and charm. This is what makes flat, front-facing art look
  dimensional — the "3/4 look" is created by light, not perspective. Mismatched light is
  what makes combined parts look pasted-on.
- **Uniform outline weight.** Pick one stroke weight relative to the canvas and use it on
  every part, so combined creatures look like one drawing.
- **Consistent proportions.** Size eyes / charms for the shared zones. Because the anchors
  are fixed, sizes just work across all bodies.
- **Keep shapes simple and forgiving.** Blobby, rounded shapes read as charming and hide
  small mismatches. Lean into it — it lowers the risk of the whole system.

---

## 5. Illustrator workflow

- **One master `.ai` file.** Keep all parts in it as your source of truth (vector scales
  to any resolution; you export raster only for the app).
- **Make a locked template layer.** On a bottom layer, draw the canvas bounds and every
  anchor mark from §1 (charm spots, eye-line, mouth, shoulders, hips, footprint), plus a
  faint reference silhouette. Lock it and design every part on top of it. This single
  habit guarantees everything lines up.
- **Work on the pixel grid.** Turn on Pixel Preview / "Align New Objects to Pixel Grid" so
  raster exports stay crisp.
- **Export:** File → Export → Export for Screens (or the Asset Export panel). PNG-24 with
  transparency, sRGB colour. Export at the full 1024 canvas (or larger). In SpriteKit you
  can drop these into the asset catalog and add @2x/@3x variants later; a single high-res
  export is fine to start.

---

## 6. File names — match these to the code exactly

The generator picks parts by **zero-based index**; name your exports so index N maps to
file N. Body maps to the `BodyType` enum order.

```
body_00_round.png      # BodyType.round  = 0
body_01_tall.png       # .tall  = 1
body_02_wide.png       # .wide  = 2
body_03_small.png      # .small = 3
body_04_lumpy.png      # .lumpy = 4

eyes_00 … eyes_07        # eyesId   0..7
mouth_00 … mouth_05      # mouthId  0..5
limbs_00 … limbs_05      # limbsId  0..5  (each = a full arms+legs set)
pattern_00 … pattern_05  # patternId 0..5

# detail charms — optional slots, IDs from the vocab in README.md
headcharm_00   (leaf)  _01 (petal)  _02 (antenna)  _03 (bow)
bellypattern_00 (speckle) _01 (page-lines) _02 (curve-stripe) _03 (pocket) _04 (pixel)
sidedetail_00  (handle) _01 (button)
tailcharm_00   (key)   _01 (peel-curl) _02 (leaf-sprig)
texture_00     (glossy) _01 (fabric)  _02 (mossy)
cheekmark_00   (freckles) _01 (swirl)

# family backgrounds — one per family (see §8)
background_ember   background_glow   background_moss   background_tide
background_dusk    background_stone  background_starlight
```

**Keep the counts in sync** with the constants in `AurieGenerator.swift`:

```swift
static let eyesCount = 8, mouthCount = 6, limbsCount = 6
```

Start with fewer of each if you like — just set the matching constant to how many files
you actually made. All five body types are required (body comes from the object's shape).
The charm IDs must match the vocab in `README.md` and the pools in `aurie_content.json`.

---

## 7. Detail charms (the "object flavour")

Charms are small pieces from *your* reusable kit — a leaf, petal, key, bow — placed on a
creature when the app recognises the object (a flower adds the petal charm). They are
**not** cut from the user's photo; the object only *inspires* which of your clean charms
gets used.

- Draw them in **final colour** (see §3), on the **same canvas** so they land at the right
  anchor (head charm at the head spot, tail charm at the base, side detail at the body
  edge, belly pattern over the body, texture as a full-body overlay).
- Keep them inside the body footprint so they fit any body.
- They're **optional** — most creatures won't have all (or any). Make sure a creature
  reads fine with no charms; charms are a bonus, not a crutch.
- **Draw the hero-object charms first** (leaf, petal, handle, page-lines, key, bow,
  screen/glossy) — those cover your demo objects (banana, apple, flower, mug, book, key,
  teddy, phone). Everything else can come later.

---

## 8. Family backgrounds

One soft full-screen background **per aura family** (7 total), shown on the single-creature
screens — Home and the full-screen view — reflecting the *creature's* family. The grid and
camera stay neutral.

- **Safe-zone rule.** Design on a generous portrait canvas and keep the focal interest in
  the central **~60% width × ~60% height**. The outer margins are soft and expendable — the
  app displays with **aspect-fill**, so different screen shapes (iPhone / iPad portrait, and
  iPad landscape later) crop only the edges, never the centre.
- **Low-contrast.** The creature, its speech bubble, and the play all sit on top, so keep
  backgrounds gentle — a soft gradient or texture, no hard lines or busy detail near the
  centre.
- **One per family, matching its mood:** Ember warm, Glow sunny, Moss forest-green, Tide
  watery blue, Dusk starry violet, Stone soft grey, Starlight night sky.
- **Fallback:** until a background exists, the screen uses a plain family-coloured tint, so
  everything runs before you've drawn any.

---

## 9. Order of work (de-risk before you commit)

1. Draw **one** of each base part (1 body, 1 eyes, 1 mouth, 1 limbs, 1 pattern, 1 glow).
2. Stack them in the app at one position, wire up baseColor / auraColor tinting.
3. Confirm: alignment is right, the style holds together, and tinting looks good.
4. **Only then** mass-produce the rest — parts, then hero charms, then backgrounds.

A solid starter library to ship with:

| Asset | Count | Notes |
|-------|-------|-------|
| Body | 5 | one per BodyType (required) |
| Eyes | 4 | |
| Mouth | 3 | |
| Limbs | 3 | each is a full arms+legs set |
| Pattern | 2 | plus a "none" option is nice |
| Aura glow | 1 | recoloured per family in-engine |
| Charms | ~7 | the hero-object set (§7) |
| Backgrounds | 7 | one per family (color-tint fallback until then) |

The parts alone give hundreds of combinations before colour and the seven aura tints.
Expand whenever you like — nothing in code changes, you just add files and bump the counts.
