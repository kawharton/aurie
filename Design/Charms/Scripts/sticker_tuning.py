"""Per-sticker presentation tuning for the 2D belly-charm family.

THE one source of truth (approved direction 2026-09-19): every 2D
sticker carries its own scale and visual-centering offsets instead of a
shared percentage. Values are applied AT INSTALL by canvas padding —
the frozen runtime fit then renders the approved presentation with no
runtime changes and no pixel edits (masters are never touched).

    scale    multiplies the frozen 0.72 base belly fit
    offsetX  belly-core POINTS, +x = art shifts RIGHT in the oval
    offsetY  belly-core POINTS, +y = art shifts UP (scene coords)

Offsets exist for VISUAL centering: a teacup centered by its full
silhouette (cup + handle) reads off-center because the cup body is the
visual mass — the offset re-centers the perceived shape in the oval.
"""

# name -> (scale, offsetX, offsetY)
TUNING = {
    "birth_teddy":      (0.92, 0, 0),
    "birth_mug":        (0.90, 4, 0),
    "birth_teacup":     (0.86, 8, 0),
    "birth_beach_ball": (0.92, 0, 0),
    "birth_balloon":    (0.82, 0, -2),
    "birth_strawberry": (0.88, 0, 0),
    "birth_orange":     (0.88, 0, 0),
    "birth_lemon":      (0.86, 0, 0),
    "birth_carrot":     (0.78, 0, -2),
    "birth_cake":       (0.80, 0, 0),
    "birth_cookie":     (0.90, 0, 0),
    # The NEW vectorized apple (approved 2026-09-19) at the approved
    # 0.88 — replaces the Blender-derived apple as the sticker art
    # direction. The PRODUCTION swap of charm_food_apple_01's installed
    # asset happens in the wiring phase; review assets use this now.
    "birth_apple":      (0.88, 0, 0),
    # Single-object drops (2026-09-19) — default fit until reviewed.
    "basketball":       (0.90, 0, 0),
    "rain_cloud":       (0.90, 0, 0),
    "flask":            (0.86, 0, 0),
    "trumpet":          (0.86, 0, 0),
    "chair":            (0.86, 0, 0),
    "tree":             (0.84, 0, 0),
    # Task-reward badges/stickers (finalized 2026-09-20).
    # SHARPNESS PASS 2026-09-20: the four badges share ONE baseline
    # (0.93, up from 0.80) so their inner icons carry enough pixels to
    # read on the belly, landing at ~22% belly area — the approved
    # Apple/Cookie/Cake weight. Rainbow/Hearts/Tree deliberately
    # untouched this pass.
    "badge_spark":      (0.93, 0, 0),
    "badge_wonderbook": (0.93, 0, 0),
    "badge_refresh":    (0.93, 0, 0),
    "badge_team":       (0.93, 0, 0),
    "rainbow_cloud":    (0.90, 0, 0),
    "friendship_hearts": (0.86, 0, 0),
}

NAMES = list(TUNING)
