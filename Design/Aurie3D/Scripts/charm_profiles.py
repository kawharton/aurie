"""Object-aware processing profiles for the Aurie charm processor.

The brief is explicit: do NOT blindly subdivision-surface every model. A key
must stay a key, a crystal must keep its facets, a snowflake must not become
a blob — while a cupcake may get rounder. So softening is a per-profile
recipe, not one global modifier, and every number here is a FRACTION of the
charm's normalized size so it means the same thing on a dolphin and a coin.

Each profile answers four questions:

    geometry   how much edge rounding, and which edges qualify
    shading    smooth, faceted, or angle-limited
    material   where in the Aurie material family this object sits
    view       which way it faces the camera

Assignment is by charm id first, then by category, then a safe default.
"""

from math import radians

# One canonical charm box. Every processed charm is scaled so its ORIENTED
# front-view bounding box fits this, aspect preserved. It is what makes the
# contact sheets and the app's future layout share one scale.
CHARM_BOX = 1.0

# ---------------------------------------------------------------------------
# Profiles
# ---------------------------------------------------------------------------
# subsurf         Catmull-Clark levels; 0 = none. OPT-IN, never global. An
#                 angle threshold cannot smooth these meshes on its own —
#                 the donut's faces meet at a median 51 degrees, so any
#                 threshold that keeps a cupcake wrapper crisp also facets
#                 the torus. Round things need real geometry. Level 2 was
#                 tested and rejected: it melts the frosting swirl and the
#                 padlock keyhole for almost no gain over level 1.
# crease_angle    edges sharper than this are creased before subdividing, so
#                 rims, stems and bases survive while bodies round out
# bevel_width      fraction of CHARM_BOX; 0 disables bevelling entirely
# bevel_segments   more segments = rounder corner for the same width
# bevel_angle      only edges sharper than this are touched, so flat panels
#                  and intentional facets keep their surfaces
# smooth_angle     None = leave faceted; otherwise smooth under this angle
# roughness        Aurie plush body is 0.80; the band here is deliberately
#                  narrow so charms read as one product
# sat_target       saturation is pulled TOWARD this, never set to it, so a
#                  banana stays yellow and a leaf stays green
# sat_mix          how far toward sat_target (0 = untouched, 1 = forced)
# val_floor        near-black source colours vanish at charm scale
# val_ceiling      blown-out whites lose their form the same way

PROFILES = {
    # Soft food and toy-like objects. The brief says these MAY get rounder.
    "plush": dict(
        subsurf=1, crease_angle=radians(55),
        bevel_width=0.020, bevel_segments=3, bevel_angle=radians(28),
        smooth_angle=radians(65),
        roughness=0.80, specular=0.30, sheen=0.15,
        sat_target=0.62, sat_mix=0.30, val_floor=0.20, val_ceiling=0.95,
        pitch=radians(-6), yaw=radians(-12)),

    # Animals. Softened, but ears, snouts and fins are the whole silhouette,
    # so the bevel is smaller and only rounds genuinely sharp edges.
    "creature": dict(
        subsurf=1, crease_angle=radians(55),
        bevel_width=0.012, bevel_segments=3, bevel_angle=radians(34),
        smooth_angle=radians(62),
        roughness=0.78, specular=0.28, sheen=0.18,
        sat_target=0.58, sat_mix=0.28, val_floor=0.16, val_ceiling=0.93,
        pitch=radians(-5), yaw=radians(-22)),

    # Crystals. Facets are the point: NO subdivision, no smoothing. The
    # bevel is a hairline whose only job is to catch a highlight per edge.
    "faceted": dict(
        bevel_width=0.006, bevel_segments=2, bevel_angle=radians(45),
        smooth_angle=None,
        roughness=0.42, specular=0.45, sheen=0.10,
        sat_target=0.70, sat_mix=0.25, val_floor=0.22, val_ceiling=0.96,
        pitch=radians(-4), yaw=radians(-14)),

    # Snowflakes and other thin filigree. No subdivision — it would round
    # every arm tip into a nub. A bevel wider than the arm itself eats the
    # shape too, so this is the most conservative profile there is.
    "filigree": dict(
        bevel_width=0.004, bevel_segments=2, bevel_angle=radians(50),
        smooth_angle=None,
        roughness=0.55, specular=0.40, sheen=0.12,
        sat_target=0.45, sat_mix=0.20, val_floor=0.26, val_ceiling=0.97,
        pitch=0.0, yaw=0.0),

    # Keys, padlocks, chests, tools. Recognisability lives in the outline,
    # so the silhouette is left alone and only the edges are taken off.
    "mechanical": dict(
        subsurf=1, crease_angle=radians(55),
        bevel_width=0.010, bevel_segments=3, bevel_angle=radians(36),
        smooth_angle=radians(58),
        roughness=0.62, specular=0.36, sheen=0.12,
        sat_target=0.55, sat_mix=0.25, val_floor=0.20, val_ceiling=0.94,
        pitch=radians(-5), yaw=radians(-16)),

    # Flat things: pizza slice, books, coins. Rounding a thin plate turns it
    # into a lozenge, so this rounds the RIM only and leaves the faces flat.
    "panel": dict(
        subsurf=1, crease_angle=radians(55),
        bevel_width=0.008, bevel_segments=3, bevel_angle=radians(40),
        smooth_angle=radians(55),
        roughness=0.72, specular=0.32, sheen=0.14,
        sat_target=0.60, sat_mix=0.28, val_floor=0.20, val_ceiling=0.94,
        pitch=radians(-8), yaw=radians(-10)),

    # Blades. The brief wants the silhouette kept but razor-thin edges made
    # to look unthreatening, which is exactly a wide bevel on sharp edges
    # only — the profile stays, the edge stops looking like a knife.
    "blade": dict(
        subsurf=1, crease_angle=radians(55),
        bevel_width=0.016, bevel_segments=4, bevel_angle=radians(22),
        smooth_angle=radians(35),
        roughness=0.58, specular=0.40, sheen=0.10,
        sat_target=0.50, sat_mix=0.22, val_floor=0.22, val_ceiling=0.95,
        pitch=radians(-4), yaw=radians(-18)),

    # Petals and foliage: soft, but thin parts, so between plush and creature.
    "botanical": dict(
        subsurf=1, crease_angle=radians(55),
        bevel_width=0.009, bevel_segments=3, bevel_angle=radians(38),
        smooth_angle=radians(60),
        roughness=0.74, specular=0.30, sheen=0.16,
        sat_target=0.62, sat_mix=0.28, val_floor=0.20, val_ceiling=0.94,
        pitch=radians(-6), yaw=radians(-10)),
}

# Category fallback, used when a charm has no explicit entry below.
CATEGORY_PROFILE = {
    "animals": "creature",
    "food": "plush",
    "nature": "botanical",
    "magic": "mechanical",
    "objects": "mechanical",
    "adventure": "mechanical",
    "vehicles": "mechanical",
    "characters": "creature",
}

# Per-charm assignment. `attach` is the LOGICAL slot only — V1 bakes no
# hardware of any kind, it just records where a ring would eventually go.
# `orient` overrides the automatic pose when the auto rule reads the object
# wrong; omitted means the automatic rule is trusted.
CHARMS = {
    # --- pilot batch --------------------------------------------------
    # Long and low, so it fills its box but still reads small next to a
    # round charm. Sized up against the rest of the set.
    "charm_animal_fox_01":       dict(profile="creature", attach="BODY_SIDE",
                                      scale=1.15),
    "charm_animal_husky_01":     dict(profile="creature", attach="BODY_SIDE"),
    # Nearly as wide as it is long once the fins are counted, so the auto
    # rule leaves it facing 3/4-front where the stripes foreshorten. Cancel
    # the profile's 3/4 turn and show the true side.
    "charm_animal_clownfish_01": dict(profile="creature", attach="BODY_SIDE",
                                      adj=dict(yaw=radians(22))),
    "charm_animal_dolphin_01":   dict(profile="creature", attach="BODY_SIDE"),
    "charm_food_cupcake_01":     dict(profile="plush", attach="BODY_FRONT"),
    "charm_food_banana_01":      dict(profile="plush", attach="BODY_FRONT"),
    "charm_food_pizza_01":       dict(profile="panel", attach="BODY_FRONT"),
    "charm_food_icecream_01":    dict(profile="plush", attach="BODY_FRONT"),
    "charm_nature_flower_01":    dict(profile="botanical", attach="HEAD"),
    "charm_magic_star_01":       dict(profile="faceted", attach="HANGING"),
    "charm_magic_crown_01":      dict(profile="mechanical", attach="HEAD"),
    "charm_object_backpack_01":  dict(profile="plush", attach="BACK"),
    "charm_magic_crystal_01":    dict(profile="faceted", attach="HANGING"),
    "charm_object_key_01":       dict(profile="mechanical", attach="HANGING"),
    "charm_magic_chest_01":      dict(profile="mechanical", attach="BODY_FRONT"),

    # --- batch 2 -------------------------------------------------------
    "charm_food_apple_01":       dict(profile="plush", attach="BODY_FRONT"),
    # Florets are small bumps; the plush bevel would smear them together.
    "charm_food_broccoli_01":    dict(profile="botanical", attach="BODY_FRONT"),
    # The source red is a dark brick that reads brown under this rig. This
    # is deliberate art direction on one slot, not the global restyle.
    "charm_food_tomato_01":      dict(profile="plush", attach="BODY_FRONT",
                                      colours={"DarkRed": "#DA3B2A"}),
    "charm_food_soda_01":        dict(profile="plush", attach="BODY_FRONT"),
    "charm_animal_cow_01":       dict(profile="creature", attach="BODY_SIDE"),
    "charm_animal_deer_01":      dict(profile="creature", attach="BODY_SIDE"),
    "charm_animal_horse_01":     dict(profile="creature", attach="BODY_SIDE"),
    # Tall fins make the koi almost as deep as it is long, so the auto rule
    # settles on a 3/4 that foreshortens the whole fish. Same cure as the
    # clownfish: cancel the profile turn and show the true side.
    "charm_animal_koi_01":       dict(profile="creature", attach="BODY_SIDE",
                                      adj=dict(yaw=radians(22))),
    "charm_object_first_aid_kit_01": dict(profile="mechanical",
                                          attach="BODY_FRONT"),
    "charm_adventure_tent_01":   dict(profile="mechanical", attach="BODY_SIDE"),

    # --- batch 3: everything else in the library -----------------------
    # Animals all read as companions standing beside the Aurie.
    "charm_animal_anglerfish_01": dict(profile="creature", attach="BODY_SIDE"),
    "charm_animal_fish_01":      dict(profile="creature", attach="BODY_SIDE"),
    "charm_animal_fish_02":      dict(profile="creature", attach="BODY_SIDE"),
    "charm_animal_fish_03":      dict(profile="creature", attach="BODY_SIDE"),
    "charm_animal_shark_01":     dict(profile="creature", attach="BODY_SIDE"),
    "charm_animal_wolf_01":      dict(profile="creature", attach="BODY_SIDE"),
    "charm_animal_zebra_clownfish_01": dict(profile="creature",
                                            attach="BODY_SIDE"),
    "charm_character_cop_01":    dict(profile="creature", attach="BODY_SIDE"),

    # Food is held in front.
    "charm_food_chicken_leg_01": dict(profile="plush", attach="BODY_FRONT"),
    "charm_food_eggplant_01":    dict(profile="plush", attach="BODY_FRONT"),
    # A cut of meat should not have crisp corners; roughly double the plush
    # bevel so the whole outline reads soft.
    "charm_food_steak_01":       dict(profile="plush", attach="BODY_FRONT",
                                      tweak=dict(bevel_width=0.038,
                                                 bevel_segments=4)),
    "charm_food_icecream_02":    dict(profile="plush", attach="BODY_FRONT"),
    "charm_food_icecream_03":    dict(profile="plush", attach="BODY_FRONT"),
    # Rashers are thin wavy sheets, not a solid: panel keeps them from
    # inflating into slabs.
    "charm_food_bacon_01":       dict(profile="panel", attach="BODY_FRONT"),

    # Trees are bulky scenery; they stand beside rather than hang.
    "charm_nature_tree_01":      dict(profile="botanical", attach="BODY_SIDE"),
    "charm_nature_pine_tree_01": dict(profile="botanical", attach="BODY_SIDE"),

    "charm_magic_chest_ingots_01": dict(profile="mechanical",
                                        attach="BODY_FRONT"),
    "charm_magic_chest_open_01": dict(profile="mechanical",
                                      attach="BODY_FRONT"),

    # Vehicles and boats are too big to dangle; they park alongside.
    "charm_vehicle_car_01":      dict(profile="mechanical", attach="BODY_SIDE"),
    "charm_vehicle_car_02":      dict(profile="mechanical", attach="BODY_SIDE"),
    "charm_vehicle_sports_car_01": dict(profile="mechanical",
                                        attach="BODY_SIDE"),
    "charm_vehicle_sports_car_02": dict(profile="mechanical",
                                        attach="BODY_SIDE"),
    "charm_vehicle_taxi_01":     dict(profile="mechanical", attach="BODY_SIDE"),
    # A hull is shallow, so the auto rule calls these flat and stands them
    # up — pointing the camera straight down into the boat. Cancel the
    # stand-up (pitch -90) and turn them broadside, which is the only view
    # in which a small boat reads as a boat. The sail ship and viking boat
    # are tall enough to escape the flat rule and need no help.
    "charm_adventure_boat_01":   dict(profile="mechanical", attach="BODY_SIDE",
                                      adj=dict(pitch=radians(-90),
                                               yaw=radians(90))),
    "charm_adventure_lifeboat_01": dict(profile="mechanical",
                                        attach="BODY_SIDE",
                                        adj=dict(pitch=radians(-90),
                                                 yaw=radians(90))),
    "charm_adventure_sail_ship_01": dict(profile="mechanical",
                                         attach="BODY_SIDE"),
    "charm_adventure_viking_boat_01": dict(profile="mechanical",
                                           attach="BODY_SIDE"),

    # --- batch 4: added with the texture pack --------------------------
    "charm_nature_plant_flowers_01": dict(profile="botanical", attach="HEAD"),
    "charm_nature_petals_01":    dict(profile="botanical", attach="HEAD"),
    "charm_nature_maple_tree_01": dict(profile="botanical", attach="BODY_SIDE"),
    "charm_nature_tree_02":      dict(profile="botanical", attach="BODY_SIDE"),
    # Rocks want SOME angularity kept — mechanical rounds the smooth faces
    # but creases hold the facets, which is what makes a stone read as stone
    # rather than as a pebble-shaped balloon.
    "charm_nature_rock_01":      dict(profile="mechanical", attach="BODY_SIDE"),
    "charm_nature_rock_02":      dict(profile="mechanical", attach="BODY_SIDE"),
    "charm_nature_rock_03":      dict(profile="mechanical", attach="BODY_SIDE"),

    # --- the rest of the library, so the full run needs no new thinking ---
    "charm_nature_snowflake_01": dict(profile="filigree", attach="HANGING"),
    "charm_nature_snowflake_02": dict(profile="filigree", attach="HANGING"),
    "charm_nature_snowflake_03": dict(profile="filigree", attach="HANGING"),
    "charm_magic_crystal_02":    dict(profile="faceted", attach="HANGING"),
    "charm_magic_star_coin_01":  dict(profile="panel", attach="HANGING"),
    "charm_magic_sword_01":      dict(profile="blade", attach="BODY_SIDE"),
    "charm_object_key_02":       dict(profile="mechanical", attach="HANGING"),
    "charm_object_key_03":       dict(profile="mechanical", attach="HANGING"),
    "charm_object_padlock_01":   dict(profile="mechanical", attach="HANGING"),
    "charm_object_fork_01":      dict(profile="mechanical", attach="HANGING"),
    "charm_object_spoon_01":     dict(profile="mechanical", attach="HANGING"),
    # An open book is flat, so the stand-up rule points the camera straight
    # down at the pages and it reads as a beige rectangle. Tilt it back and
    # turn it slightly: the spine, the page curl and the depth come back.
    "charm_object_book_01":      dict(profile="panel", attach="BODY_FRONT",
                                      adj=dict(pitch=radians(-38),
                                               yaw=radians(-15))),
    # Same flat-page problem as Book 1: tilt it back and turn it slightly.
    "charm_object_book_02":      dict(profile="panel", attach="BODY_FRONT",
                                      adj=dict(pitch=radians(-38),
                                               yaw=radians(-15))),
    "charm_nature_flower_02":    dict(profile="botanical", attach="HEAD"),
    "charm_nature_flower_03":    dict(profile="botanical", attach="HEAD"),
    # The thorns are tiny cones on the pad edges and they ARE the cactus.
    # Subdivision alone erased 4% of its silhouette (measured) and the bevel
    # another 1.3%. Smooth SHADING makes the pads read round without moving
    # a single vertex, so the geometry is left nearly alone instead.
    "charm_nature_cactus_flower_01": dict(profile="botanical",
                                          attach="BODY_SIDE",
                                          tweak=dict(subsurf=0,
                                                     bevel_width=0.004,
                                                     smooth_angle=radians(60))),
    "charm_nature_pumpkin_01":   dict(profile="plush", attach="BODY_FRONT"),
    "charm_nature_wood_log_01":  dict(profile="mechanical", attach="BODY_SIDE"),
    "charm_food_donut_01":       dict(profile="plush", attach="HANGING"),
    "charm_food_donut_02":       dict(profile="plush", attach="HANGING"),
    "charm_food_waffle_01":      dict(profile="panel", attach="BODY_FRONT"),
}

DEFAULT_PROFILE = "plush"

# Where the attachment anchor sits on the charm, per slot. This is the point
# on the CHARM that meets the Aurie, expressed on its own surface, plus the
# direction that surface faces. The camera looks along +y, so -y is the face
# the viewer sees and +y is the side that would press against a body.
ANCHOR_RULES = {
    "HEAD":       dict(axis="-z", normal=(0.0, 0.0, -1.0)),
    "HANGING":    dict(axis="+z", normal=(0.0, 0.0, 1.0)),
    "BODY_FRONT": dict(axis="+y", normal=(0.0, 1.0, 0.0)),
    "BODY_SIDE":  dict(axis="-x", normal=(-1.0, 0.0, 0.0)),
    "BACK":       dict(axis="+y", normal=(0.0, 1.0, 0.0)),
}


def for_charm(charm_id, category):
    """Everything the processor needs for one charm, in one place.

        profile  the named recipe it starts from
        prof     that recipe with any per-charm `tweak` merged in — a COPY,
                 so tweaking one charm can never leak into another
        attach   logical attachment slot
        orient   absolute pose override, or None to trust the auto rule
        adj      pose nudge added to the auto rule
        scale    size relative to every other charm (1.0 = the canonical box)
        colours  material name -> hex sRGB, hand-authored art direction that
                 replaces the automatic restyle for that slot only
    """
    entry = CHARMS.get(charm_id, {})
    name = entry.get("profile") or CATEGORY_PROFILE.get(category,
                                                        DEFAULT_PROFILE)
    prof = dict(PROFILES[name])
    prof.update(entry.get("tweak", {}))
    return dict(profile=name, prof=prof,
                attach=entry.get("attach", "HANGING"),
                orient=entry.get("orient"), adj=entry.get("adj"),
                scale=entry.get("scale", 1.0),
                colours=entry.get("colours", {}))
