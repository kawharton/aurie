# Home environment sources

Standalone paintings, one per family, recomposed to the shared master
frame (941x1672) whose contract is `master_composition_template.png`:
sky/distant scenery in the top 20% ONLY, the ground-meets-distance
transition band AT 20%, open walkable ground 20..84%, framing
foreground below. The runtime (`HomeEnvironment.swift`) is one engine
with ONE shared playfield — backgrounds are skins; art that composes
poorly against the shared frame gets recomposed or replaced, never
special-cased in code.

Shipping masters (2026-09): moss2, glow2, dusk2, tide3 (via
recompose), starlight2, ember3, stone3.

## Tide

    TIDE BEACH      = DEFAULT (launch)   tide3.png -> recompose_tide3_beach.py
                      -> Auries/Assets.xcassets/Environments/tide_env_sky.imageset
    TIDE UNDERWATER = preserved future alternate (NOT selectable yet)
                      tide_underwater_master.png  (the exact 941x1672 master
                      that shipped as tide_env_sky before 2026-09-17;
                      byte-identical to tide2.png). Reinstating it later is
                      a one-file copy into the imageset.

Product decision 2026-09-17: Tide's default is the BEACH. Deep water
ends just above the 20% far walk line; the surf/foam band extends into
the walkable area (Aurie may stand in foam, never in open ocean); dry
sand from ~33%. tide.png / tide2.png are the original underwater
paintings — do not delete. The superseded underwater slice imagesets
(tide_env_mid/ground/fore) remain on disk and are ignored at runtime
(`flatMaster: true`).

Environment selection/unlocking is NOT implemented — see
Docs/environment_direction.md for the recorded future direction.
