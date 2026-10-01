# Sol instruction — Aurie Home screen visual and motion refactor

## Role and scope

Act as a senior SwiftUI/SpriteKit engineer, interaction animator, and visual-design implementer. Perform a **controlled refactor of the Home experience only**. This includes:

1. normal Home layout and visual styling;
2. the featured Aurie presentation placeholder;
3. Home play-space motion and reaction presentation;
4. the Home-to-Calm transition and Calm entry control.

Do **not** redesign the Hatch, Collection, detail, settings, purchase, recognition, persistence, generator, or content systems in this pass. Do not rebuild the app.

## Files and references to inspect first

Use these as the source of truth:

- `BUILD_BRIEF.md` / uploaded merged build brief;
- `README.md`;
- `ART_GUIDE.md`;
- `auries_mockup.png` as the approved visual-direction reference;
- the current Home screenshot;
- the current Home screen recording;
- the entire existing Xcode repository.

The uploaded `.pbxproj` uses a file-system-synchronized group and does not reveal the Swift source-file list. Inspect the actual repository and identify the Home SwiftUI view, SpriteKit play scene, `AurieNode`, placeholder renderer, tab shell, speech-bubble component, Calm Mode files, and any shared theme/style files before proposing changes.

## Non-negotiable protections

- Preserve all working Home behaviors and data flow.
- Do not rewrite validated model, generator, content-loading, recognition, hatch, persistence, or wallet logic.
- Do not change the stored `Aurie` schema merely for appearance.
- Keep the real-art seam intact: presentation placeholders must be replaced automatically by future art through `AssetLoader`.
- Continue supporting iPhone and iPad portrait with flexible/proportional layout; do not tune only for the supplied iPhone 17 Pro screenshot.
- Keep the project compiling and runnable after every stage.
- Use native SwiftUI and SpriteKit. Do not add a new game engine or unnecessary package.
- Respect Reduce Motion, VoiceOver, safe areas, Sound settings, and Calm Mode privacy boundaries.

---

# Stage 1 — audit only; do not edit code yet

Compare the current screenshot and recording against the approved mockup and the build/art guides. Return a concise but concrete audit covering:

- layout hierarchy and empty-space balance;
- top bar and control placement;
- background depth and family identity;
- creature silhouette and body-type compliance;
- layering, tint, highlights, shadows, glow, and grounding;
- speech-bubble placement and relationship to the creature;
- tab-bar visual weight;
- play-space bounds and edge collisions;
- hop/tap/pet/tickle/pickup/shake animation timing;
- expression changes and particle presentation;
- Home-to-Calm transition;
- current Calm sparkles, breathing ring, and Worry Jar legibility;
- iPhone/iPad responsiveness;
- accessibility and Reduce Motion.

Do not begin implementation until the audit is presented.

## Known problems visible in the supplied current build

Confirm these against the code rather than blindly assuming them:

1. **The placeholder Aurie does not currently read as one of the approved body types.** Its very large side lobes and merged lower lobes make it resemble a flower/elephant silhouette instead of a round, tall, wide, small, or lumpy creature with distinct limbs.
2. **The creature is visually flat.** It lacks the intended midtone/highlight/shadow construction, cheeks, dimensional edge treatment, and a convincing contact shadow.
3. **The background is too close to a flat family tint.** The central radial glow helps, but the Home scene still lacks the soft layered depth shown in the mockup.
4. **The top half feels under-composed.** There is a large inactive void between the header and the creature, especially when no line is visible.
5. **Reaction speech bubbles are fixed too far from the moving Aurie.** In the recording the creature moves around the screen while the bubble remains near the top, breaking the sense that the creature is speaking.
6. **Empty-space taps move the creature too broadly and sometimes too near the play-space edges.** The motion reads more like repositioning than a grounded hop.
7. **The movement lacks enough anticipation, arc, stretch, landing squash, and settle.** The creature often appears to slide, jump abruptly, or change position without weight.
8. **The creature has no moving contact shadow**, so it appears to float even when it is meant to land.
9. **The selected tab treatment is visually heavy and generic** compared with the soft mockup.
10. **Calm is represented by a moon icon in the top controls**, but the current specification calls for a discoverable labeled `Calm` capsule on Home.
11. **Calm sparkles are too small/thin to feel like a satisfying sensory interaction.** The Worry Jar screen also becomes text-heavy and visually tiny in the current recording.

Required visible Stage 1 outcomes:
- Clear top-bar hierarchy among creature name, Calm, and Settings.
- Better proportional spacing between the top bar, speech bubble, creature
  play space, and bottom navigation.
- Speech bubble visually associated with the creature rather than floating
  independently near the top.
- Daily-lift area and tab bar must not crowd the creature play space.
- Background treatment should have more depth than a flat solid tint, while
  still remaining a placeholder and low-contrast.
- Buttons and cards should use one consistent corner-radius, material,
  typography, and shadow system.
- Maintain flexible iPhone and iPad portrait layouts.
- Do not change generation, persistence, hatch, collection, Calm Mode logic,
  or creature animation behavior.

  1. Improve the family-background placeholder:
   - layered gradient rather than a flat tint
   - soft center glow behind the creature
   - subtle vignette and sparse atmospheric particles
2. Rebalance the vertical layout:
   - header
   - nearby speech bubble
   - large central creature play area
   - optional daily-lift card
   - tab bar
   The creature must not float in a huge empty area.
3. Restyle the speech bubble so it is visually attached to the creature.
4. Give Home controls consistent materials, corner radii, typography, spacing,
   and shadows.
5. Keep the creature renderer and major motion work for later stages, but add
   a simple contact shadow beneath it if that can be done without restructuring
   animation code.
6. Verify the same Home layout on iPhone and iPad portrait.

---

# Stage 2 — establish a reusable Home visual system

After the audit, create or refine shared design tokens before changing individual elements. Do not scatter unrelated literals through views.

Create semantic tokens for:

- Home horizontal margins;
- top safe-area/header spacing;
- play-space bounds;
- creature default scale ranges by device class;
- control sizes and hit targets;
- corner radii;
- speech-bubble padding and maximum width;
- tab-bar material, height, and selection treatment;
- family background colors;
- placeholder highlight/shadow strengths;
- aura opacity;
- motion durations and spring parameters;
- reaction-line duration and cooldowns.

Use proportional layout derived from `GeometryReader`, scene size, and safe-area insets. Avoid hard-coding positions for one simulator.

---

# Stage 3 — normal Home visual target

## A. Overall composition

Use the approved mockup as **art direction**, not as a pixel-perfect raster to trace.

Desired hierarchy:

1. top header: name/family at leading edge, Settings at trailing edge;
2. permanent or reaction speech bubble in the upper-middle region when visible;
3. a large, calm play space centered beneath the line;
4. optional secondary Home content such as Daily Lift only if already implemented;
5. a small labeled `Calm` capsule above the tab bar;
6. bottom tab bar.

The creature should be the strongest focal element. UI chrome should feel secondary and translucent rather than boxed and heavy.

## B. Top bar

- Keep creature name and family left-aligned.
- Keep only the Settings gear as the primary top-right control.
- Remove the moon-only Calm control from the header.
- Add a small `☾ Calm` or icon-plus-`Calm` capsule above the tab bar, aligned trailing or centered where it does not collide with Daily Lift.
- The Calm control must be discoverable but visually secondary.
- Use minimum 44×44 pt interaction targets even when the visible capsule is compact.

## C. Family background placeholder

Do not wait for final background art. Create a polished procedural fallback that can later be replaced by `background_<family>`.

For Dusk in the supplied example:

- deep blue-violet at the outer/top regions;
- muted violet/lavender center bloom;
- very subtle atmospheric haze;
- sparse, soft star/dust motes with slow movement;
- gentle vignette;
- no sharp objects or busy center detail;
- enough contrast for a white speech bubble and creature face.

Implement the same reusable structure for all families using semantic family colors. Keep the final asset-slot path untouched.

## D. Presentation-quality placeholder Aurie

The current engineering placeholder is not visually sufficient for judging. Replace it with a **presentation placeholder**, while retaining an optional debug-placeholder mode.

The presentation placeholder must:

- use the actual stored `BodyType` proportions: round, tall, wide, small, or lumpy;
- use one main rounded body, with separate arms and legs behind it;
- follow the shared eye, mouth, shoulder, and hip anchor scheme;
- remain front-facing and mirrorable;
- use the stored eye/mouth IDs where possible, with graceful fallback;
- include soft cheeks;
- include an upper-left highlight and lower-right shadow;
- include a subtle outline or edge contrast;
- include a restrained aura glow;
- include a soft elliptical contact shadow that follows the creature;
- avoid giant side lobes that read as ears unless an actual future charm/part specifies them;
- remain deliberately simple so future PNG art drops in without changing layout or interaction code.

Build the placeholder with the same conceptual layer order used by the art pipeline:

aura → limbs → body → pattern/details → eyes → mouth.

Do not create a one-off Iris-only character. The renderer must work for all generated Auries.

## E. Creature size and resting position

- Set the initial resting position near the visual center/lower-center of the play area, not at the geometric center of the whole screen.
- The default creature should occupy roughly 38–48% of the available play-space width on a phone, adjusted by body type, with a sensible cap on iPad.
- Reserve clear space above it for a speech bubble.
- Keep it fully inside a defined play rectangle that excludes header, Calm/Daily Lift controls, and tab bar.

## F. Speech bubbles

Use two related presentation modes:

1. **Permanent daily line:** may begin above the creature in the central composition.
2. **Reaction line:** appears near the creature's current position, with a small tail toward it.

Requirements:

- Clamp the bubble inside the safe area.
- Choose above/left/right placement based on available room.
- Do not leave all reaction bubbles fixed at the top while the creature is elsewhere.
- Limit width for readability and support Dynamic Type.
- Animate with a soft fade/scale, remain long enough to read, then fade without blocking gestures.
- Prevent rapid reaction lines from stacking; use a cooldown/queue policy.

## G. Tab bar

Keep Home / Hatch / Auries and preserve navigation behavior. Refine the current bar so it resembles the approved soft UI:

- dark translucent material with a subtle family tint;
- less bulky selected pill;
- equal spacing and clear labels;
- selected state readable without intense neon blue;
- safe-area-correct placement;
- 44 pt targets;
- no layout shift when selection changes.

Do not implement a visually custom bar if it breaks standard accessibility or tab behavior.

## H. Daily Lift

The current brief describes Daily Lift as being built. Do not invent or delete it during this pass.

- If it already exists, render it as a small secondary card above the Calm/tab region and keep it visually subordinate to the Aurie and speech bubble.
- If it does not exist, leave its data/feature work untouched and reserve layout space only if necessary.
- Do not restore the removed “daily word” design.

---

# Stage 4 — normal Home motion target

Create a small explicit behavior/state coordinator instead of allowing overlapping unrelated `SKAction`s. Suggested states:

- idle;
- reacting;
- hopping;
- beingPetted;
- beingTickled;
- beingHeld;
- landing;
- enteringCalm;
- calm.

Gestures must cancel or defer incompatible actions and return cleanly to idle.

## A. Idle

- subtle breathing cycle, approximately 3–4 seconds;
- small vertical movement and scale change, not constant floating;
- blink at varied intervals;
- occasional tiny glance or sway;
- contact shadow gently changes width/opacity with breathing;
- no large autonomous relocation.

## B. Tap creature

Sequence:

1. notice/face change;
2. quick compression;
3. spring upward or outward slightly;
4. landing squash;
5. small overshoot;
6. return to idle.

Synchronize the face and any particle with the movement. Avoid a plain linear scale pulse.

## C. Tap empty space — hop there

Required sequence:

1. clamp the requested target so the entire creature and shadow remain in the play rectangle;
2. look toward the target;
3. mirror to face the direction;
4. short crouch/anticipation;
5. travel on a visible arc rather than a straight slide;
6. slight vertical stretch near the top of the arc;
7. landing squash and shadow expansion;
8. settle, then resume idle.

Use distance-based duration within a small bounded range. Do not teleport. Do not allow the creature to disappear under the header, tab bar, Calm control, or screen edge.

## D. Pet

- detect a stroke across the body, not any screen drag;
- lean subtly into the finger;
- eyes soften/close;
- small happy wiggle;
- 1–3 hearts or family particles, not a large particle flood;
- reaction line only occasionally and with cooldown;
- return smoothly to the current grounded position.

## E. Tickle

- detect repeated fast taps within a short window;
- laughing expression;
- quick side-to-side giggle with squash/stretch;
- short particles and optional line;
- do not mistake normal single taps for tickling.

## F. Pick up and drop

- long press initiates pickup only in normal Home mode;
- legs dangle and body follows finger with a small spring lag;
- shadow stays on the ground and softens while lifted;
- clamp dragging to safe play bounds;
- drop uses falling anticipation, impact squash, shadow expansion, overshoot, and settle.

## G. Shake

- use a controlled tumble/wobble sequence rather than flinging the node unpredictably;
- keep it inside play bounds;
- switch to dizzy expression temporarily;
- return to an upright grounded state.

## H. Reactions and effects

- Use family-specific placeholder particles where supported.
- Keep Dusk effects soft: tiny stars/mist, not bright arcade particles.
- Particle emitters should be pooled or cleaned up; no accumulating nodes.
- Haptics and sound hooks remain optional/placeholders and respect settings.

## I. Reduced Motion

Provide a valid alternate path:

- replace long travel arcs with short fades/position eases;
- reduce squash/stretch amplitude;
- preserve clear feedback and expression changes;
- avoid continuous particle motion where the user requests reduced motion.

---

# Stage 5 — Home-to-Calm shell polish

Do not rewrite the built Breathe Together or Worry Jar logic in the normal Home pass. First make the Home shell and transition coherent.

## Entry control

- Use the labeled `Calm` capsule above the tab bar, not the current moon-only header button.
- On first use, preserve the existing one-line introduction.

## Transition

- approximately 1.2 seconds;
- regular speech bubble, tab bar, Daily Lift, and normal chrome fade away;
- background becomes slightly dimmer, less saturated, and more vignetted;
- energetic particles slow or disappear;
- creature moves gently to a stable centered seated/resting position; do not teleport;
- normal play gestures are suspended;
- Calm controls fade in after the creature settles.

## Calm interaction shell

- Dragging empty space moves/generates sparkles, **not the Aurie**.
- Sparkles should be larger, softer, and easier to see than the current thin trail.
- The Aurie's eyes may follow and its body may lean slightly, but it stays seated.
- Dragging over the Aurie becomes petting.
- Long hold becomes the calm hold/hug response, not pickup.
- Keep `Done` visible and easy to reach.

## Breathe Together and Worry Jar

Treat these as **Pass B after normal Home is approved**. When polishing them later:

- maintain the exact privacy and non-therapy boundaries in the build brief;
- improve text sizing and vertical hierarchy;
- keep the Worry Jar as the brightest secondary object;
- ensure the keyboard does not cover primary actions;
- keep release animation slow and family-specific;
- do not store, log, transmit, or analyze worry text.

---

# Stage 6 — implementation rules

- Prefer small reusable components and named actions over a monolithic Home view/scene.
- Avoid magic numbers duplicated across SwiftUI and SpriteKit; pass a calculated play rectangle into the scene.
- Keep SpriteKit coordinate conversion explicit and tested.
- Make scene resizing idempotent; do not recreate the creature or lose state whenever SwiftUI lays out.
- Ensure animation nodes have stable names and cleanup paths.
- Do not use infinite actions without keys/cancellation.
- Prevent idle animation from stacking after each reaction.
- Preserve app state when entering/leaving Calm or switching tabs.
- Do not make changes to unrelated screens to satisfy Home styling.

---

# Required delivery after each implementation stage

After the audit is accepted, proceed in small stages:

1. tokens + normal Home layout/background;
2. presentation placeholder Aurie;
3. speech bubbles + play bounds;
4. motion refactor;
5. Home-to-Calm shell.

At the end of every stage:

- build the app;
- fix errors and new warnings;
- list every changed/added file;
- explain what was preserved;
- provide iPhone 17 Pro before/after screenshots;
- provide one smaller-iPhone screenshot and one iPad-portrait screenshot;
- provide a short screen recording for motion stages;
- note any remaining visible differences from the approved mockup;
- stop for review before moving to the next major stage.

---

# Acceptance checklist for this Home pass

The pass is not complete until all of the following are true:

- [ ] Home remains functional with the existing featured creature and persistent data.
- [ ] The initial composition feels intentional even without final art.
- [ ] The placeholder clearly uses one of the five stored body types.
- [ ] Body, limbs, face, aura, and shadow read as separate coordinated layers.
- [ ] The Dusk background has soft depth rather than a flat solid fill.
- [ ] Name/family and Settings are clear; Calm is a labeled secondary capsule above the tab bar.
- [ ] The creature begins in a balanced resting position with room for its line.
- [ ] Reaction speech bubbles appear near the creature and stay on-screen.
- [ ] Empty-space hops use anticipation, arc, landing squash, and settle.
- [ ] The creature never overlaps the header, tab bar, Calm control, or screen edges.
- [ ] Pet, tickle, pickup/drop, and shake remain distinguishable.
- [ ] Animations do not stack or leave the creature scaled/rotated incorrectly.
- [ ] A moving contact shadow grounds the creature.
- [ ] Calm entry is gentle and does not teleport the creature.
- [ ] Calm sparkle dragging does not move the Aurie.
- [ ] Reduce Motion has a coherent fallback.
- [ ] Layout works on iPhone and iPad portrait.
- [ ] No unrelated business logic or data model was rewritten.
- [ ] The project builds and runs after the refactor.

