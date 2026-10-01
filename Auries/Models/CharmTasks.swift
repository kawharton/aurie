import Foundation

// CHARM TASKS (Phase E, launch set 2026-09-20): charms earned through
// ordinary app activity, riding the SAME account-level ownership path
// as Birth Charms — completion produces a stable grant id through
// CharmService.processGrant; no second inventory, no quantities, and
// no automatic equipment. Small on purpose: three progress kinds cover
// every launch task, and nothing here is a quest engine.

/// The app activity that drives a task. Each case corresponds to ONE
/// model-layer seam (never a UI event), so a task can only move when
/// the activity GENUINELY happened.
public enum CharmTaskEvent: String, Codable {
    /// DORMANT (not a launch event): Daily Wonders were withdrawn from
    /// the launch product 2026-09-20. The case is kept so the seam in
    /// AppModel still compiles and so a future Wonder feature can be
    /// re-enabled by adding tasks back — NO launch task consumes it.
    case wonderRevealed
    /// DORMANT, same reason as `wonderRevealed`.
    case wonderSaved
    /// A charm equipped through the product path (AppModel.equipCharm).
    case charmEquipped
    /// A charm equipped into a slot that held a DIFFERENT charm.
    case charmReplaced
    /// Calm Mode entered. Counted by distinct day; never reads or
    /// depends on Worry content.
    case calmVisited
    /// A new Aurie committed to the collection (AppModel.commitHatch).
    case aurieHatched
    /// The player genuinely touched an Aurie on Home — a body tap or a
    /// pet stroke (CreatureScene.onInteraction → AppModel
    /// .recordAurieInteraction, which collapses it to one per day).
    /// Never an autonomous fidget and never an empty-space tap.
    case aurieInteracted
}

/// How a task measures progress.
public enum CharmTaskKind: Equatable {
    /// Distinct calendar days on which the task's event fired — the
    /// day-key machinery Discover 5 Wonders proved. Cumulative and
    /// forgiving; never a streak.
    case distinctDays
    /// Completes the first time the task's event fires. Not
    /// retroactive by design (used when history was never stored).
    case eventOnce
    /// A live scan of already-persisted facts (collection, equipment,
    /// Wonderbook, unlocks) — RETROACTIVE by definition: reaching the
    /// threshold counts no matter when or how it happened.
    case state(CharmTaskStateMetric)
}

/// The persisted facts a state task can measure. Computation lives in
/// AppModel (it owns store/charms); the catalog only names the metric.
public enum CharmTaskStateMetric: String, Codable {
    /// Wonders currently saved in the Wonderbook.
    case wonderbookCount
    /// Auries in the collection.
    case aurieCount
    /// Charms owned (unlockedCharmIDs).
    case charmsOwned
    /// Distinct catalog categories across owned charms.
    case categoriesOwned
    /// Auries currently wearing at least one charm.
    case auriesWearingCharms
    /// The largest number of different Auries wearing the SAME charm.
    case mostAuriesSharingACharm
}

/// One player-facing charm task.
public struct CharmTaskDefinition: Identifiable {
    public let id: String
    public let title: String
    public let description: String
    /// nil = the reward is UNASSIGNED (its art was pulled and no
    /// replacement has been chosen). The task still shows on the Earn
    /// Charms page, but it cannot complete or grant until a reward is
    /// assigned — never substitute an arbitrary charm to fill the gap.
    public let rewardCharmID: String?
    public let event: CharmTaskEvent
    public let kind: CharmTaskKind
    public let target: Int
    public let repeatability: CharmTaskRepeatability
}

public enum CharmTaskRepeatability: String, Codable {
    case once
    // future: .daily — grant ids gain a CalendarDay suffix.
}

public enum CharmTaskCatalog {
    /// The launch task list (approved map, 2026-09-20). Order is the
    /// display order on the Earn Charms page.
    public static let all: [CharmTaskDefinition] = [
        // WITHDRAWN FROM LAUNCH 2026-09-20 — Daily Wonders and the
        // Wonderbook are not part of the launch product, so the four
        // tasks that depended on them (five_daily_wonders,
        // wonder_to_keep, wonder_collector, month_of_wonders) are gone
        // from this catalog. Their reward charms are deliberately NOT
        // deleted and NOT reassigned — Spark Badge, Wonderbook Badge,
        // Star aura and Crystal aura are unassigned and available for a
        // future, smaller launch task list. Do not invent replacement
        // tasks for them without an explicit product decision.
        // WITHDRAWN FROM LAUNCH 2026-09-25 — "Try a New Look" (equip a
        // charm on an Aurie) is gone. Its reward, Pink Shoe, was DELETED
        // 2026-09-20 (art not good enough at belly scale) and no
        // replacement was ever chosen, so the task could accrue progress
        // but never complete or grant. Withdrawing the task is the fix,
        // not pointing it at some other charm — one acquisition path per
        // charm. Every remaining launch task awards something.
        CharmTaskDefinition(
            id: "fresh_look",
            title: "Fresh Look",
            description: "Swap an equipped charm for a different one.",
            rewardCharmID: "charm_badge_refresh_01",
            event: .charmReplaced, kind: .eventOnce, target: 1,
            repeatability: .once),
        CharmTaskDefinition(
            id: "share_the_style",
            title: "Share the Style",
            description: "Equip the same charm on 2 different Auries.",
            rewardCharmID: "charm_nature_flower_03",       // Blossom AURA
            event: .charmEquipped, kind: .state(.mostAuriesSharingACharm),
            target: 2, repeatability: .once),
        CharmTaskDefinition(
            id: "styled_crew",
            title: "Styled Crew",
            description: "Have charms equipped on 3 different Auries.",
            rewardCharmID: "charm_badge_team_01",
            event: .charmEquipped, kind: .state(.auriesWearingCharms),
            target: 3, repeatability: .once),
        CharmTaskDefinition(
            id: "charm_variety",
            title: "Charm Variety",
            description: "Own charms from 3 different categories.",
            rewardCharmID: "charm_nature_rainbow_cloud_01",
            event: .aurieHatched, kind: .state(.categoriesOwned),
            target: 3, repeatability: .once),
        CharmTaskDefinition(
            id: "make_friends",
            title: "Make Some Friends",
            description: "Have 3 Auries in your collection.",
            rewardCharmID: "charm_friendship_hearts_01",
            event: .aurieHatched, kind: .state(.aurieCount), target: 3,
            repeatability: .once),
        CharmTaskDefinition(
            id: "quiet_visits",
            title: "Quiet Visits",
            description: "Visit Calm Mode on 3 different days.",
            rewardCharmID: "charm_nature_snowflake_01",    // Snowflake AURA
            event: .calmVisited, kind: .distinctDays, target: 3,
            repeatability: .once),
        CharmTaskDefinition(
            id: "full_house",
            title: "A Full House",
            description: "Have 10 Auries in your collection.",
            rewardCharmID: "charm_magic_star_01",          // Star AURA
            event: .aurieHatched, kind: .state(.aurieCount), target: 10,
            repeatability: .once),
        CharmTaskDefinition(
            id: "old_friends",
            title: "Old Friends",
            description: "Interact with any Aurie on 30 different days.",
            rewardCharmID: "charm_magic_crystal_02",       // Crystal AURA
            event: .aurieInteracted, kind: .distinctDays, target: 30,
            repeatability: .once),
        CharmTaskDefinition(
            id: "growing_collection",
            title: "Growing Collection",
            description: "Own 10 charms.",
            rewardCharmID: "charm_nature_tree_02",
            event: .aurieHatched, kind: .state(.charmsOwned), target: 10,
            repeatability: .once),
    ]

    /// The stable ledger id ("task:<id>") — the durable evidence of
    /// completion, never reward ownership.
    public static func grantID(_ def: CharmTaskDefinition) -> String {
        "task:\(def.id)"
    }

    public static func isCompleted(_ def: CharmTaskDefinition,
                                   processedGrantIds: Set<String>) -> Bool {
        processedGrantIds.contains(grantID(def))
    }

    public static func tasks(for event: CharmTaskEvent)
        -> [CharmTaskDefinition] {
        all.filter { $0.event == event }
    }

    /// Tasks that can actually award today (reward assigned). A task
    /// awaiting replacement art is excluded — it never grants.
    public static var rewarded: [CharmTaskDefinition] {
        all.filter { $0.rewardCharmID != nil }
    }

    /// Every state task, regardless of trigger event — the launch
    /// retroactive pass and the post-grant cascade evaluate these.
    public static var stateTasks: [CharmTaskDefinition] {
        all.filter { if case .state = $0.kind { return true }
                     return false }
    }
}
