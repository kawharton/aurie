# Aurie — build brief (merged, v2)

A single spec to keep building Aurie with Claude Code. Core model/generator/content/node
files already exist and are validated — reuse them. Keep the app runnable with placeholders
at every step. Where this brief and older notes conflict, this brief wins.

**Current state:** build steps for scaffolding, tab navigation, persistence, and the
**sample-image hatch flow are already done** (photo → colour/shape + Vision → `generate` →
tap-to-crack egg → reveal → auto-save). Continue from the working code: **audit, preserve,
and polish — do not rebuild.** Only patch what fails an audit.

---

## 0. How to use this brief (for Claude Code)

- Build into the existing **Auries** Xcode project; add new files to the app target.
- Reuse the existing files in §3 verbatim. Don't regenerate the model/generator/content/node.
- Keep it **running at every step** with placeholders (art, sample images, stub purchases,
  placeholder sounds/videos). Never leave it non-building.
- Everything needing art/sound/video/accounts gets a labeled stub + TODO.

## 1. What Aurie is + principles

A soft, magical toy: **take a photo → an egg appears → the egg behaves oddly → tap to crack
→ a cute Aurie is born → play with it → want to hatch one more.** Make the first 60 seconds
delightful; prioritise the hatch + play loop over big secondary systems.

- **Reliably cute beats literal.** The photographed object is never the creature body — it
  only *influences* body type, base colour, aura family, born-from label/thumbnail, and
  optional detail slots.
- **No wasted hatch.** Once a hatch is spent, the creature is auto-saved.
- **No dark patterns.** No guilt, pay-or-lose, streak loss, storage-hostage, or purchasable
  rarity odds.
- **Consumable hatch packs only** for MVP — no unlimited, no subscription.
- **The core loop must work empty.**

## 2. Platform, project, conventions

Swift. **SwiftUI** shell + navigation; **SpriteKit** (via `SpriteView`) for the creature,
play space, and hatch scene (reuse `AurieNode`). **Portrait only**, universal **iPhone +
iPad**, **flexible/proportional layouts** (no fixed pixels). Local persistence only. **Never
store the user's photo** — thumbnail reference + extracted colour/shape only. Generator is
**deterministic by seed**. Target iOS 17+.

## 3. Existing files (reuse)

| File | Role |
|------|------|
| `AurieModels.swift` | Enums, structs, `DetailSlots`, `RecognizedObject`, `Aurie` record (stores `line` + `traits`). |
| `AurieContent.swift` | Codable content model + loader. |
| `AurieGenerator.swift` | Hatch pipeline, permanent-line composer, reaction helpers, seeded RNG. |
| `AurieNode.swift` | SpriteKit creature: assembles parts, tints, animates (bob, blink, hop, bounce). Extend for polish. |
| `aurie_content.json` | Names, line templates, moods, shake/pet, traits, shared tickle/pickup, categories, heroes. |
| `README.md`, `ART_GUIDE.md` | Model/content reference, and the Illustrator→SpriteKit art pipeline. |

## 4. Data + generation (three layers)

```
photo → dominant colour + ShapeSignal + RecognizedObject?
 Layer 1 ALWAYS: colour→family, shape→body, eyes/mouth/limbs, colour, aura, name,
                 permanent LINE (composed), personality trio
 Layer 2 IF recognised (confidence ≥ 0.40, category ≠ unknown): category fills detail slots
 Layer 3 IF hero object matches label: stamps that object's signature detail
```

- Families (7): ember, glow, moss, tide, dusk, stone, starlight. Starlight = ~4% override,
  **never purchasable**. Colour→family + detail-slot vocab are in `README.md`.
- Body types: round, wide, tall, small, lumpy (from shape). Don't block adding more later.
- Unknown / low confidence → Layer 1 only, `bornFrom = "a mysterious shape"` (feels
  intentional, not an error). Don't block the build on perfect recognition — Vision is a
  bonus layer; the app must hatch a full creature from colour + shape alone.
- **New creature every photo** (fresh seed each hatch; pass existing names to avoid dupes).

## 5. Lines + traits

- **Permanent line** — composed at hatch (`composeLine`), stored on `Aurie.line`, shown on
  Home + full-screen. Endless supply via templates × name × mood. Starlight = hand-written
  one-offs.
- **Reaction lines** (repeat freely, not stored): `shakeLine`/`petLine` family-flavoured;
  `tickleLine`/`pickupLine` shared (`sharedPlay`).
- **Personality trio** — 3 adjectives from the family's `traits` pool, stored on
  `Aurie.traits`, shown on the detail screen.

## 6. Screens

**Nav:** 3 tabs — Home / Hatch / Collection. Overlays: full-screen creature, refill sheet,
hatch-pack sheet. Settings opens from the Home gear. First-run tutorial (short placeholder
videos; replayable from Settings).

- **Home** — featured Aurie alive on its **family background**; name + gear in top bar; its
  permanent **line** in a speech bubble once per day, then a **pure play space** (§7). No
  on-screen gesture instructions (tutorial teaches them). **Empty-home greeter:** before the
  first real hatch, show a display-only greeter Aurie (not saved, not counted) that gently
  points toward hatching, e.g. "I found an empty egg. Want to see who's inside?"
- **Hatch** — neutral (the app doesn't know the object yet). Ready copy: **"Who will hatch
  today?"** + tips (good light · fill the frame · plain background · hold steady) + actions:
  Take Photo / Choose Photo / Sample Images. Egg is **coloured from the object**; tap through
  crack stages; reveal shows the creature, name, family, born-from thumbnail, trio, and line.
  Reveal copy: **"Meet {name}"** or **"{name} hatched from {bornFrom}"** — never "It's a new
  Aurie!". **Auto-saved before Continue.** No keep/discard, **no share button** (MVP).
- **Collection** — neutral grid; tap → full-screen; press-and-hold → "Set as featured" popup.
- **Full-screen creature** (overlay) — creature on its family background; name · family; the
  **line**; the **personality trio**; small **born-from thumbnail** (image, not words). **Set
  as featured** is primary; **Delete** is small, set apart, and **always confirms**. Swipe
  left/right through the whole collection.
- **Settings** — Featured creature, Sound, Notifications, How to play.
- **Refill sheet** ("More eggs are waiting.") — **Buy a hatch pack** (opens pack screen),
  **Watch an ad for 1 more**, and "Come back tomorrow for a free hatch." No unlimited.
- **Hatch packs** — full-width, centered labels: **Buy 5 hatches — $2.99**, **Buy 10 hatches
  — $4.99**, **Buy 20 hatches — $8.99 · Best value**.

## 7. Play mechanics (Home play space)

Six gestures, each producing **movement + sound/haptic + a reaction line or particle**:
tap → bounce; tap empty space → hop + face; **pet** → wiggle + hearts/particles + pet line;
**shake** → tumble + dizzy + shake line; **pick up / drop** → dangle + nervous line, then
squash-bounce; **tickle** → giggle + silly line. Respect the Sound setting.

## 8. Fun / winning polish (add after core play works, in this order)

1. **Egg personalities** — one temporary pre-hatch behavior: wobbly, sleepy, shy, heavy,
   sparkly, mystery. Not stored (part of the moment).
   ```swift
   enum EggPersonality: String, Codable, CaseIterable { case wobbly, sleepy, shy, heavy, sparkly, mystery }
   ```
2. **Family hatch effects** (SpriteKit particles, placeholder art ok): Ember sparks · Moss
   leaves · Tide bubbles · Dusk mist+stars · Stone dust · Glow warm flash · Starlight galaxy.
3. **Birth reaction** — one short animation at reveal (blink/look around, fall over + pop up,
   wave, stretch, sparkle) before/while showing the line.
4. **Idle moments** — Aurie is always at least breathing; when idle it may also blink, look
   around, yawn, stretch, sit, wave, sneeze, notice offscreen, or do a tiny family effect.
   Short; never interrupt a gesture.
5. **Family reaction particles** — same per-family palette on tap/pet/shake/hatch/rare idle.
6. **Expression states** (sprite swaps + small actions, no rig): neutral, happy, surprised,
   dizzy, sleepy/closed, laughing — used on hatch, tap, pet, shake, tickle, pickup/drop,
   blink. Fall back to neutral if art is missing.
7. **Haptics** — light on tap/bounce and each egg crack, medium on hatch, soft on
   pickup/drop, special on Starlight/rare. Respect system settings.
8. **Sound hooks** — build early with placeholder files: tap, egg crack, hatch, pet, daily
   appear, pickup/drop, tickle, rare reveal. Respect the Sound setting.
9. **Rarity moments** — delightful surprises only, never sold: rare Starlight hatch, rare
   double-blink, odd-egg colour, rare idle sneeze-of-sparkles, etc.

## 9. Family backgrounds

One soft full-screen background per family (7), shown on the single-creature screens (Home +
full-screen), reflecting the creature's family. Grid + camera stay neutral. **Aspect-fill**
with a centered safe zone (rule in `ART_GUIDE.md`); low-contrast so the creature + bubble
stay readable; plain family-colour tint as fallback until art exists. Do not build. Will be added later. Use a placeholder. 

## 10. Services (real vs stub)

- **Recognition — REAL** (bonus layer). `VNClassifyImageRequest` on-device → top label +
  confidence → bucket into an `ObjectCategory` via a lookup table you maintain. Unknown/low →
  `nil`. Don't block the build on it.
- **Colour + shape — REAL.** Dominant colour + bounding-box aspect ratio + roundness.
- **Camera + fallback.** Sample images first (Simulator), then photo-library picker, then
  AVFoundation camera.
- **Persistence — REAL.** Collection + settings on-device; featured creature in an **App
  Group** (for the widget); store a small thumbnail only.
- **Purchases — STUB first, RevenueCat later.** Buttons work; the stub grants hatch balance
  locally. Clean protocol seam so RevenueCat replaces it without touching the UI. No
  unlimited — only consumable packs or one rewarded-ad hatch.
  ```swift
  protocol PurchaseService {
      func loadHatchProducts() async throws -> [HatchProduct]
      func purchaseHatchPack(_ product: HatchProduct) async throws -> HatchGrant
      func grantRewardedAdHatch() async throws -> HatchGrant
  }
  struct HatchGrant: Codable, Equatable { let amount: Int; let source: HatchGrantSource; let transactionId: String? }
  enum HatchGrantSource: String, Codable { case purchase, rewardedAd, debug }
  ```
- **Sound — REAL wiring, placeholder files**, with a mute toggle.

## 11. Monetization (consumable-only)

- **Free hatches:** tunable. Default **3 on the first day, then 1/day**. Refill trigger: out
  of hatches and the user taps capture.
- **Products (consumable):** 5 — $2.99 · 10 — $4.99 · 20 — $8.99 (best value). Rewarded ad
  grants 1. **No** subscription, unlimited, rarity odds, or storage-slot sales.
- **HatchWallet / HatchLimitService** owns balances (not the UI):
  ```swift
  struct HatchWallet: Codable {
      var firstLaunchDate: Date
      var lastDailyRefreshDate: Date
      var freeHatchesToday: Int
      var paidHatchBalance: Int
      var rewardedHatchBalance: Int
      var processedGrantIds: Set<String>
  }
  ```
  Rules: spend **free → rewarded → paid**; **only consume a hatch after the Aurie is
  generated and saved** (never deduct on failure); purchase grants are **idempotent** (record
  transaction/grant IDs; never double-grant on retry/resume); paid balance is **local-only**.
- **RevenueCat (when wiring for real):** don't hardcode products — use **Offerings**;
  placements `out_of_hatches`, `after_great_hatch`, `settings_store` (build `out_of_hatches`
  first; `after_great_hatch` catches the "one more" moment). Product IDs e.g.
  `com.<yourbundle>.aurie.hatches5/10/20` (match your bundle). **Consumables can't be restored
  without an account system** — don't promise cross-device restoration; user copy: "Hatch
  packs are used on this device."
- Aurie is a **feel-good app for everyone — all ages**, not a kids-only app. (The
original §1 note "audience includes kids" still holds: everyone includes kids, and it
works on iPad.) Design for warmth and gentleness across the board; because some users
are children and the App Store treats broadly-appealing apps accordingly, avoid any
dark pattern (guilt, loss-aversion, pay-or-lose) — those are bad for every user anyway.

## 12. Notifications

- **Pre-photo** (no photo yet today): "Who will hatch today?" / "Something ordinary is waiting
  to become magical." / "Find something tiny to hatch."
- **Post-photo** (only if egg processing is async): "Your egg is ready to hatch." / "Something
  is tapping from inside the egg."
- **Never** say "a new egg is ready" before the user has taken a photo.

## 13. Runs-empty guarantee

The app builds and plays with no art, sounds, videos, camera, or accounts: placeholder
creatures hatch from sample images, get names/lines/trios, auto-save, greet, animate, react,
and trigger the refill sheet (stubbed grants). Art, camera, sounds, videos, and the RevenueCat
swap drop in independently.

## 14. Out of scope for MVP + Shipaton (leave clean seams, don't build)

Feeding, mini-games, dress-up/accessories, battles, decorating rooms, social/sharing
(including a **share button** in v1), accounts/cloud sync, trading, multiplayer, leaderboards,
guilt/streak-loss systems, **iPad landscape**. Design extension points; do not build now.

## 15. v2 ideas (post-Shipaton)

Gift-a-copy via deterministic share codes (QR/AirDrop, no server/accounts); gentle moods
(sleepy/"missed you", cheered instantly by petting — never sick/decaying); cosmetic
habitats/albums (never storage capacity); accessories; tiny per-family mini-games.

## 16. Build order - if anything in these steps has already been completed, just skip over it. Do not redo it. 

- **Phase 0 — sync/cleanup (do now):** remove all unlimited/subscription references + the
  `unlimited` stub state; add hatch-pack prices; use refill copy; confirm no share button;
  keep it all-ages and non-predatory, add an empty-home greeter.
- **Phase 1 — foundation audit:** existing files load unchanged; tabs exist; AssetLoader
  returns placeholders/real; empty-home greeter present; family-background colour fallback.
- **Phase 2 — persistence/collection audit:** storage, featured, settings, grid, full-screen
  overlay, set featured, delete-with-confirm. Add any that are missing.
- **Phase 3 — hatch core audit (was step 4 from previous build brief, done):** sample images work; colour/shape extract;
  Vision wired if available (else colour+shape still hatches); `generate` called right;
  coloured egg; tap-to-crack; reveal; auto-save; Continue; no keep/discard; no share; no "It's
  a new Aurie!". Patch mismatches only; don't refactor for style.
- **Phase 4 — core play:** the six gestures + reaction lines + sound hooks.
- **Phase 5 — winning polish:** egg personalities → family hatch effects → birth reaction →
  idle moments → family reaction particles → expression states → haptics → demo tools.
- **Phase 6 — monetization MVP:** HatchWallet + refresh rules + refill sheet + pack screen +
  stub grants + rewarded-ad stub.
- **Phase 7 — settings / notifications / tutorial:** sound + notification toggles; pre-photo
  daily notification; post-photo only if async; how-to-play placeholder videos + replay.
- **Phase 8 — real device:** AVFoundation camera; photo-library picker; iPad portrait checks;
  App Group; widget target (featured creature still image).
- **Phase 9 — RevenueCat real:** replace `StubPurchaseService` with `RevenueCatPurchaseService`;
  fetch products; complete consumables; idempotent local grants; sandbox test; UI unchanged.
- **Phase 10 — final polish + App Store readiness:** swap in real assets; verify empty states,
  thumbnail-only storage, no-deduct-on-failure, delete-confirm, no share button, no
  unlimited/subscription copy, offline-except-purchases/ads.

## 17. Hackathon constraints (RevenueCat Shipaton 2026)

Ship a new app to the App Store **Aug 1 – Sep 30, 2026**. The app must integrate the
**RevenueCat SDK** to power at least one in-app purchase — **consumable hatch packs qualify**,
so no subscription is required. Replace the purchase stub with real RevenueCat **before
submission**. Needs the Apple Developer Program ($99/yr) + products in App Store Connect;
budget buffer for review.

## 18. Daily lift (Home) — building now

A daily feel-good moment on Home, **independent of the featured creature** (it's the
day's lift for the whole app, unchanged when you switch Auries):

- A card pinned at the bottom of Home rotating one item per day — an **inspirational
  saying**, a **joke**, or a **positive dare** (no "word of the day"). Content lives in
  `daily_content.json` (`quotes` / `jokes` / `dares`), editable with no code change.
  Selection is deterministic by calendar day (stable all day, rotates at midnight, no
  storage). Separate from each creature's own permanent `line` (shown in the Home
  speech bubble).
- **Empty Home:** before the first hatch, a **display-only greeter Aurie** stands in
  (not saved, stable across launches) with a welcome line, so Home is never bare and
  the daily lift still shows.


## 18b. Calm Mode (built)

A quieter version of Home — same creature, same family world, softened. Entered via a
small `◯ Calm` capsule on Home (no hidden gestures); first visit shows one line ("Take a
quiet moment with {name}."). Gentle ~1.2s crossfade; tab bar and chrome fade out; ambient
music fades in (own toggle, `calmMusicOn`, independent of global Sound). **Just Be is the
default** — no menu, no questionnaire: the creature settles (slow bob/breath/blinks),
sparkles trail the finger and its eyes follow, stroke → lean with eyes nearly closed,
hold → lean + soft rhythmic haptic, tap → slow blink/nod, tap away → it looks but stays
seated, shake → mostly ignored. Two optional activities at the bottom:

- **Breathe Together** — soft ring + creature rising/expanding in sync, ~4s each way,
  wording only ("Breathe in with {name}" / "And slowly out", fades after two cycles),
  no counts, ~1 minute then back to Just Be. Done always visible. Reduce Motion swaps
  body expansion for a brightening ring.
- **Worry Jar** — the signature ritual. Prompt: "What feels heavy right now? {name} can
  hold it with you." Privacy promise shown *before* typing: "Your words disappear after
  you give them to {name}. Only a little light remains in the jar." → Give it to {name}
  → text becomes a light in the jar → hold line → **Keep it here for now / Release it
  now**. One light per Aurie (v1); the jar belongs to that Aurie (tiny lamp icon on its
  detail page). Release is slow (4–6s): lights rise and become the family effect —
  Ember fireflies · Moss leaves · Tide bubbles · Dusk sleepy stars · Stone glowing dust
  · Glow light rays · Starlight mini constellations — backdrop opens slightly, one soft
  haptic, closing line "We can let this one go for now." A quiet **"Need support from a
  person?"** link opens a gentle non-emergency screen about talking to a trusted person.
- Calm copy lives in `calm_content.json` (per-family `calmLines`, used sparingly, +
  jar hold/release lines). Backdrop = family tint desaturated/dimmed + vignette +
  family-colored center glow (no new art needed; calm background art can drop in later,
  same per-family identity — Ember still feels like Ember).

**Hard boundaries (do not change, ever):** Calm Mode is a comforting fictional
companion — NOT therapy, NOT advice, NOT an emergency service, NOT an AI analyzing
private thoughts. **The worry text is never stored, logged, transmitted, or analyzed** —
it is discarded on submit; only an anonymous date-stamped token per Aurie persists
(`worries.json`). No coins, badges, streaks, or rewards for worries or calm use — never
incentivize manufacturing distress. No forced timers, no completion tracking, no
"failed" sessions, no "your worry is gone / Aurie fixed it" framing ("for now" wording).

## 19. Asset & content pipeline (art/sound/video come later)

- **AssetLoader** keyed to the naming convention in `ART_GUIDE.md`
  (`body_00_round`, `eyes_00`, `pattern_00`, plus the detail-slot IDs, plus
  `background_<family>`). It returns the real sprite if present, else the
  **placeholder** (colored shapes) so the app runs before art exists. Bump the part
  counts in the generator when new sprites are added.
- **Content** is all in `aurie_content.json` (names, line templates, moods, shake/pet,
  shared tickle/pickup, categories, heroes). Editing it needs no code change.
- **Sounds** and **tutorial videos** are bundled resources with placeholder files and
  labeled slots.



## 20. Demo / judging polish

- **Curated sample set** (plain backgrounds, strong dominant colours) that reliably shows
  different families/bodies: yellow/tall → Glow/Ember tall · green → Moss · blue → Tide ·
  purple → Dusk · gray/brown → Stone · round/wide/lumpy → matching body.
- **Demo mode** (debug-only, hidden from users): reset hatches, clear collection, load sample
  set, force a family/body, optionally force Starlight once. For recording/testing only —
  never expose rarity manipulation to users.
- **First-60-seconds test:** launch → non-empty Home (greeter) → Hatch → pick sample → egg
  appears fast with personality/wobble → satisfying tap-to-crack → cute named auto-saved
  reveal with family/born-from/trio → play immediately → user understands how to hatch another.
