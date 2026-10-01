# RENDER ARCHITECTURE AUDIT — modular SpriteKit vs RealityKit (2026-08-18)

Decision pass only. No implementation, no exports, no migration.

## A. WHAT DRAWS AURIE TODAY

`AurieNode` (SpriteKit) composes **eight sprite layers** — aura, contact
shadow, limbs, body, belly pattern, eyes, mouth (charm z reserved) — over four
transform layers that each own one kind of motion (position/scale, facing +
tilt, interaction squash, breathing).

Textures come from `AssetLoader.textures(for:)`, which resolves
`UIImage(named:)` and otherwise draws a **procedural Core Graphics
placeholder**. `Assets.xcassets` currently contains **0 imagesets**, so:

> **100% of the visible creature today is placeholder art. No Blender output
> reaches the app at all.**

That is good news for this decision: there is no legacy art pipeline to
migrate, only placeholders to replace behind an interface that already exists.

Other relevant facts:
- Colour is applied with `node.color` + `colorBlendFactor` — a flat lerp
  toward a colour. Fine for flat placeholders; it would **flatten the shading**
  of a Blender render. This is the one real technical gap in Option A.
- No `SKShader` anywhere in the project yet.
- Deployment target **iOS 17.0**.
- `ART_GUIDE.md` already specifies the modular contract: one **1024×1024**
  canvas for every part, full-frame transparent export, fixed shared anchor
  zones, stack every layer at the same position.

## B. WHAT BLENDER PRODUCES TODAY

`Design/Aurie3D/Scripts/`: `aurie_body_common.py` (shared family pipeline),
15 `build_*_aurie.py`, `aurie_limb_styles.py`, `aurie_face_expressions.py`.

**The pipeline already renders pixel-registered layer passes.** `render_all()`
walks `passes_for()` toggling `hide_render` per collection and re-renders the
same camera: BODY / TUFT / LIMBS / FACE / full-frame. Same 1024×1024
orthographic frame, `film_transparent`, PNG RGBA, Standard view transform.

> **The modular export Option A needs is not a new pipeline — it is a longer
> pass list plus a naming convention on the pipeline that already exists.**

Cost per render: ~25–30 s (Cycles CPU, 128 samples).

## C. HOW BIG IS AURIE ACTUALLY ON SCREEN

From the real code, not assumption:

- `collisionHalfWidth = 175`, `halfUp = 172`, `halfDown = 190` → art footprint
  **350 × 362** units.
- `creatureScale = screenWidth × bodyFraction / 350`, clamped 0.40–1.60,
  `bodyFraction` 0.47 (iPhone) → 0.42 (iPad).

| Context | On-screen | Physical px |
|---|---|---|
| Home, iPhone 393 pt | 185 × 191 pt (scale 0.53) | **554 × 573 @3x** |
| Home, iPad 742 pt | 312 × 322 pt (scale 0.89) | **623 × 645 @2x** |
| Collection tile | ~265 pt inside a 340 canvas | ~530 @2x |
| Widget export | fixed | 512 |
| Hatch reveal frame | 190 × 170 pt | ~570 @3x |

> **Aurie never exceeds ~640 device pixels anywhere in the app.** The existing
> 1024 masters are already ~1.6× oversampled. Ship at **768** and there is no
> visible loss; 2K/4K would be pure waste.

## D. OPTION A — MODULAR BLENDER → SPRITEKIT

**Hierarchy:** unchanged from today. `AurieNode` keeps its layers; only the
texture *source* changes from placeholder to Blender PNG.

**Asset matrix (active launch pool):**

| Group | Count | Note |
|---|---|---|
| Body (+tuft baked in) | 10 | one per active body |
| Arms | 3 styles × 2 sides = 6 | rendered once, placed per body from existing anchor metadata, scaled by the per-body multiplier |
| Legs | 4 styles × 2 sides = 8 | same |
| Faces | (10 expressions + blink-closed + 3 reaction faces) × 10 bodies = **140** | faces conform to each body's surface, so these are body-specific |
| Patterns | 5 × 10 = 50 | alpha masks conformed per body |
| **Total** | **≈214** | + charms later |

Faces dominate the count. They are also the *smallest* images (crop to the
face bbox, ~384×256), so they dominate neither bundle nor memory.

**Memory:** only the active Aurie's set is resident — body 768² RGBA ≈ 2.4 MB,
four limb sprites ≈ 0.4 MB, the current body's 14 faces ≈ 5.5 MB, one pattern
≈ 0.3 MB → **≈ 8–9 MB decoded**. Note that SpriteKit `.atlas` packing **trims
transparent margins automatically and restores placement**, so full-frame
1024 exports get cropped memory behaviour for free — this resolves the
trade-off `ART_GUIDE.md` flags as "optimise later".

**Bundle:** mostly-transparent PNGs — roughly 6–10 MB for all 214.

**Draw calls:** 8–10 sprites per creature, batched to ~2–3 draw calls if the
per-body parts share an atlas page. Node count is unchanged from today, so the
existing 60 fps behaviour carries over.

**Colour (the one new piece):** render parts **neutral** and multiply-tint at
runtime with a ~5-line `SKShader` (`gl_FragColor = texture * tint`). Preserves
shading, which `colorBlendFactor` would destroy. Alternative — baking 7
families × 10 bodies = 70 body textures — is rejected as combinatorial bloat.
**This must be validated before anything else is exported.**

**Patterns:** conformed alpha masks multiplied over the body inside the same
shader — not separate body renders.

**Faces/expressions:** the state machine already resolves to a face id string
and calls one function, `AurieNode.applyFace(_ faceId:)`. Pointing that at
`SKTexture(named: "face_<body>_<faceId>")` with the Core Graphics renderer as
fallback is a **one-function change**. Everything else — baseExpression
persistence, family weighting, reaction priorities, override/restore — is
untouched.

**Work required:** export contract + atlas build + tint shader + AssetLoader
preference for real textures + per-body anchor JSON. Estimated **4–6 working
days** with verification gates (plan in §G). Blender render time for ~214
assets ≈ 1.5–2 hours of unattended CPU.

## E. OPTION B — BLENDER → REALITYKIT

**Export:** the bodies are *procedurally generated meshes* from Python, so
they export cleanly to USDZ — that part is genuinely easy.

**Where it stops being easy, specific to this repo:**

1. **iOS 17 floor.** SwiftUI `RealityView` is iOS 18+. This project targets
   **iOS 17.0**, so it means either raising the floor (dropping iOS 17 users
   two weeks before launch) or embedding `ARView` in non-AR mode through
   `UIViewRepresentable` with a hand-configured camera.
2. **`CreatureScene` is ~800 lines of 2D game logic** — roaming, collision
   half-extents and safe zones, carry/drag, pet-stroke detection, shake flail
   with hop chains, Calm Mode sparkle trails, speech-bubble anchoring. All of
   it is in SpriteKit coordinates. A 3D creature means either reimplementing
   that in 3D or running a hybrid where the 3D creature and the 2D effects
   layer must be coordinate-synced every frame — which is the worst of both.
3. **Faces.** RealityKit has no decal system. Each expression becomes either a
   UV-mapped face texture on the body material (still 10 × 10 textures) or
   separate patch meshes parented to the body (100 small meshes), or
   blendshapes authored per body. None is cheaper than 2D face sprites.
4. **Lighting.** Matching the approved Cycles plush look needs IBL plus the
   three-light rig re-tuned in RealityKit's PBR. It will not match for free,
   and "close but different" on the *approved* art is a regression.
5. **Everything downstream** — hatch reveal, Wonderglobe, family particles,
   Calm Mode, iPad layout, collection portraits, the widget exporter (which
   renders a 512 px composite through `AssetLoader`) — is built on the 2D
   assembly and would each need a path.

**What RealityKit would genuinely make better, later:** glass/transparent
Auries (explicitly deferred), true body rotation, dynamic lighting, richer 3D
charms, and one source of truth with no re-render per expression/pattern
combination. All future-facing; none required for Sept 1.

**Estimated work:** weeks, with the riskiest parts (interaction parity,
lighting match, face system) landing last. **Not feasible before Sept 1.**

## F. SIDE-BY-SIDE

| | A: modular SpriteKit | B: RealityKit |
|---|---|---|
| Fidelity to approved Blender art | **Exact** (it *is* the render) | Approximate; needs lighting match |
| App size | ~6–10 MB | ~15–40 MB (meshes + textures) |
| Runtime RAM | **~8–9 MB** decoded | Higher; meshes + materials + IBL |
| GPU | 2–3 batched draw calls | Full 3D pass per frame |
| CPU | Unchanged from today | Higher; ECS + transform sync |
| Animation flexibility | Squash/stretch/tilt in 2D (already built) | Real 3D, better long-term |
| Customisation scaling | Faces × bodies is the cost driver | Materials scale better; faces do not |
| Current-code reuse | **~95%** — `AurieNode`/`CreatureScene` intact | ~30% — scene logic rewritten |
| Engineering risk | Low; one new shader | High; new runtime + interaction parity |
| Implementation time | **4–6 days** | Weeks |
| Sept 1 feasibility | **Yes, with slack** | **No** |
| Future flexibility | Adequate; 3D remains possible later | Better |

## G. RECOMMENDATION

**Sept 1: stay on SpriteKit and feed it modular Blender renders (Option A).**

Three repo-specific reasons, in order of weight:

1. The Blender pipeline **already emits pixel-registered layer passes** — the
   modular export is a pass list, not a new system.
2. The app's art seam is **already a texture-name lookup with a procedural
   fallback**, and the expression system already funnels through one function.
   The reaction/expression work completed this week survives untouched.
3. There is **no legacy art to migrate** (0 imagesets) and **no 3D runtime to
   introduce** (iOS 17 floor vs `RealityView`), two weeks from launch.

**Long-term: revisit RealityKit after launch**, driven by glass/transparency,
body rotation and 3D charms. Option A does not foreclose it — the Blender
scenes stay the source of truth either way, and a 3D runtime would consume the
same `.blend` scripts rather than these PNGs.

## H. STAGED PLAN (each stage has a gate; do not proceed on a red gate)

**Stage 0 — tint spike (½ day).** Render one body neutral, multiply-tint with
an `SKShader` against three family colours, compare to the approved coloured
render. *Gate: shading survives and the hues match the approved look. If not,
fall back to per-family body bakes for 10 bodies × 7 families and re-cost.*

**Stage 1 — export contract (1 day).** Extend `passes_for()` into a per-part
export (body+tuft, each arm/leg side, each face, each pattern) on the
ART_GUIDE 1024 canvas. *Gate: stacking the exported parts reproduces the
existing full-frame preview pixel-for-pixel (diff below threshold).*

**Stage 2 — Round, end to end (1 day).** One body, 3 arms, 4 legs, 14 faces
into an atlas; `AssetLoader` prefers real textures; `AurieNode` unchanged.
*Gate: real-app screenshot of Round matches the Blender preview, and the
existing reaction self-test still passes with the new textures.*

**Stage 3 — remaining 9 bodies (1–2 days).** Ship per-body anchor metadata
(already computed in the Blender scripts) as JSON. *Gate: all 10 bodies
correct at their anchors; collection tiles and widget portraits regenerate.*

**Stage 4 — patterns (½ day).** Masks through the same shader. *Gate: 5
patterns × 3 bodies visually correct, no seams at the silhouette edge.*

**Stage 5 — cleanup.** Keep the procedural renderers as the missing-asset
fallback; stop maintaining them as the primary look.

Total ≈ 4–6 working days, gated, with slack before Sept 1.

---

# I. FUTURE TRANSPARENCY COMPATIBILITY (constraint, not launch work)

Glass/translucent Aurie stays deferred. Launch ships the opaque set only. But
the pipeline must not bake in an "alpha is always 1" assumption. Audit of where
that assumption could enter, and the rules that keep the door open.

## Current state — what already survives translucency

- `film_transparent = True`, PNG **RGBA** exports: alpha is real today.
- Only `auraNode` uses a non-standard blend (`.add`). Body, limbs, pattern,
  eyes and mouth all use SpriteKit's default `.alpha` (premultiplied
  source-over), which composites correctly at any alpha.
- `AssetLoader.composite` uses a default `UIGraphicsImageRendererFormat`, whose
  `opaque` is `false`, so portraits/widget exports already keep alpha.

## Rules that keep translucency possible

1. **The tint shader must be alpha-correct.** Multiply only RGB by the family
   colour and carry the texture's alpha through; never write `a = 1.0`, and
   never sample as if the texture were unassociated — SpriteKit textures are
   **premultiplied**. An opaque-only shader that ignores the alpha channel is
   the single easiest way to block this later.
2. **Patterns must MODULATE, not overwrite.** Applying a pattern as a mask
   multiplied into the body layer stays correct at any body alpha; applying it
   as an opaque overlay sprite does not.
3. **Keep body/limb/face/pattern on `.alpha`.** Never "optimise" them to
   `.replace`, and never set `format.opaque = true` on the portrait/widget
   compositor. Both would look identical today and silently break glass later.
4. **Keep the layer set data-driven.** This is the deep one: **a glass body is
   not the opaque body at lower alpha.** Looking through it, you would see the
   unrendered interior, and the face patch would composite against the
   background rather than against the body's inner surface. A future glass
   variant needs its own Blender render (refraction/interior baked in), and
   possibly an extra interior/backface pass. So the per-body asset manifest
   should be a **list of layers with ids**, letting a body variant declare
   extra passes without changing `AurieNode` code. Hard-coding the eight
   layers in Swift is what would actually block this — not the file format.
5. **Masters at 16-bit, ship at 8-bit.** `color_depth = "8"` is fine for opaque
   cutouts, but soft alpha gradients in glass band at 8 bits, and the
   straight→premultiplied conversion compounds it. Render translucent masters
   at 16-bit PNG (or EXR) and down-convert for shipping.
6. **No lossy alpha in the atlas.** Trimming in a SpriteKit `.atlas` keys on
   alpha > 0 and preserves partial alpha, which is fine — but keep body layers
   RGBA8 lossless. Lossy compression wrecks soft alpha first.
7. **Contact shadow ordering.** The shadow currently sits under an opaque body.
   Under a translucent one it would read *through* the creature; note it now,
   solve it when glass ships.

## What is NOT being built now

No glass materials, no refraction renders, no interior passes, no shader
branches for translucency. Launch optimises the opaque path only. These rules
cost nothing today — they are mostly "don't take the shortcut that looks
identical until the day it doesn't".

---

# J. STAGE 3 ASSET PIPELINE — HOW TO REPRODUCE IT

Two committed scripts, run in order. Nothing else is needed, and no asset
name is hand-maintained anywhere in the app.

**1. Render the masters** (~55 min for the ten active bodies):

    for b in round tall small egg pear dumpling teardrop beanbag oval heart; do
      blender --background --factory-startup --python \
        Design/Aurie3D/Scripts/export_app_layers.py -- --body $b --outdir <EXPORT>
    done

Writes ~68 full-frame 1024 layers per body plus `<body>_manifest.json`
(camera `ortho`, per-leg-style lift, limb scale, face list).

**2. Install into the app + generate the Swift manifest** (seconds):

    blender --background --factory-startup --python \
      Design/Aurie3D/Scripts/build_hatch_egg.py -- --outdir <EGG>     # egg shell
    python3 Design/Aurie3D/Scripts/install_app_assets.py \
      --export-dir <EXPORT> --egg-dir <EGG>

Crops every layer to its alpha bbox, writes `Assets.xcassets/AurieBlender`,
and generates `Auries/Services/AurieBlenderAssets.swift` (per-body layer
placements, leg lift ALREADY CONVERTED TO POINTS using that body's own
`ortho`, limb scale). Clears the catalog first, so a layer deleted upstream
cannot linger. Idempotent: re-running against the same masters reproduces
the catalog byte-for-byte.

HISTORY (2026-08-18): step 2 originally lived only in the session scratchpad,
so the shipped catalog and manifest were NOT reproducible from the repo — the
generated header even pointed at a path that did not exist. The script was
promoted into `Scripts/` unchanged apart from taking its input paths as
arguments (no session-specific paths in committed tooling) and absorbing the
egg-shell install, which had been a one-off inline command. Verified by
regenerating: catalog byte-identical across all 672 entries, manifest
identical apart from the header.
