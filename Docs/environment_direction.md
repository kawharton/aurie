# Home environments — recorded product direction (2026-09-17)

DOCUMENTATION ONLY. None of this is scheduled; nothing here may be
implemented without an explicit instruction. Recorded so the charm and
environment work doesn't paint the architecture into a corner.

## Decided now

- **Tide default = BEACH** (tide3 recomposition; approved 2026-09-17).
  Deep water ends just above the far walk line; Aurie may stand in the
  surf FOAM at the farthest positions, never in open ocean.
- **Tide underwater is PRESERVED**, not deleted:
  `Design/Environments/tide_underwater_master.png` (byte-identical to
  the pre-2026-09-17 shipping master). It may later become an
  UNLOCKABLE alternate environment. No selection/unlock system exists
  yet, deliberately.

## Future: environmental charm discovery (Tide first, any family later)

The collection loop, end to end:

    object appears naturally in the environment
        -> Aurie may notice / react
        -> player taps the object
        -> collection feedback
        -> charm unlocks permanently via CharmService.unlock(...)

Example: a shell washes onto the beach -> tap -> shell charm unlocked.

Architecture rules (must hold when this is built):
- The environmental object and the charm are DIFFERENT models. The
  object REFERENCES the charm it awards; spawn/interaction logic never
  lives on `CharmDefinition`.
- Conceptual shape:

      EnvironmentalCollectibleDefinition
          id
          eligibleFamilies/environments
          worldAssetReference
          spawnRule
          interactionType
          rewardCharmID

- Grants route through the ONE unlock path (`CharmService.unlock`),
  idempotent via `processedGrantIds`, account-level, quantity-free.
  The acquisition-source id `environmentDiscovery` already exists in
  the charm taxonomy for this.

## Future: Tide Beach ambient behaviour

- gentle ocean movement; shoreline edging slightly onto/off the sand
- animated foam edge; subtle water sparkle
- occasional shell washing ashore / beach object appearing
- Aurie noticing or reacting to an object

## Future: living environments (all families)

Environments should eventually feel alive via LIGHTWEIGHT RUNTIME
LAYERS over the paintings — never by turning backgrounds into videos.

| family | ambient ideas |
| --- | --- |
| Tide | waves / shoreline / foam, water sparkle, rare shell or object arrival |
| Starlight | independent star twinkles, rare shooting star, subtle particles |
| Moss | light plant/leaf movement, butterfly/firefly, occasional falling leaf |
| Glow | drifting luminous motes, occasional sparkle |
| Dusk | stars/fireflies, slow cloud drift |
| Ember | subtle heat shimmer, drifting embers, restrained distant glow changes |

Rules that must hold:
- ambient movement stays SUBTLE and low-cost; never busy
- **Aurie remains the visual focus** (Ember especially must not swamp
  the creature)
- effects are family-specific, layered SEPARATELY from Aurie, and
  PAUSE when the Home scene is inactive
- ambient effects and collectible spawn logic stay separate from charm
  data

Conceptual shape when it is built:

    EnvironmentAmbientProfile
        family/environmentID
        ambientEffects[]
        interactiveSpawnRules[]

kept separate from `CharmDefinition` and from `HomeEnvironment`'s
shared playfield geometry (which never forks per family).
