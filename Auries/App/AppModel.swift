import Foundation
import Observation
import RevenueCat
import UIKit

/// A photo that's been analyzed and is ready to hatch: the extracted signals
/// plus the image itself (kept only in memory for the egg/reveal screens and
/// the thumbnail crop — the full photo is never persisted).
struct PendingHatch: Identifiable {
    let id = UUID()
    let image: UIImage
    let dominantColor: Rgb
    let shape: ShapeSignal
    let recognized: RecognizedObject?
}

/// What ONE successful commit produced, for the reveal flow. TRANSIENT:
/// only `aurie` (whose persisted `birthCharmID` carries the provenance)
/// outlives this value — `newlyUnlocked` describes this commit alone
/// and is deliberately never persisted anywhere. UI driven by this
/// value can only ever describe a COMMITTED hatch; a cancelled egg
/// produces no result at all.
struct HatchCommitResult {
    let aurie: Aurie
    let birthCharm: BirthCharmReveal?
}

/// The Birth Charm a commit awarded: which charm, and whether THIS
/// commit was the account's first unlock of it (an already-owned charm
/// still reveals — the Aurie's origin matters — but must not claim a
/// new unlock).
struct BirthCharmReveal {
    let charmID: String
    let newlyUnlocked: Bool
}

/// App-wide state: the loaded content and the persistent store.
@Observable
final class AppModel {
    let content: AurieContent
    let store: Store
    let wallet: WalletService
    let purchases: PurchaseService
    /// Account-level charm unlocks (charms.json beside wallet.json).
    /// Deleting an Aurie never touches this — equipping is a reference
    /// to an unlock, never a copy.
    let charms: CharmService

    /// A friendly welcome creature shown on Home before the first hatch, so
    /// Home is never empty. Display-only — never saved to the collection, and
    /// stable across launches (fixed seed). Replaced by the real featured Aurie
    /// as soon as one is hatched.
    let greeter: Aurie

    /// Task rewards earned but not yet celebrated (Phase E), in earn
    /// order — a cascade (e.g. the 10th unlock finishing Growing
    /// Collection) can queue several at once, and Home presents them
    /// one sheet at a time, only after any earning activity's own
    /// presentation is done. Deliberately NOT persisted: a relaunch
    /// never replays the celebration — the Charms page already shows
    /// the unlocks.
    var pendingTaskRewards: [CharmTaskResult] = []

    init() {
        content = ContentService.content
        store = Store()
        wallet = WalletService(directory: Store.directory)
        purchases = AppModel.makePurchaseService()
        charms = CharmService(directory: Store.directory)
        greeter = AurieGenerator.generate(
            dominantColor: Rgb(120, 190, 110),                     // soft moss green
            shape: ShapeSignal(aspectRatio: 1.0, roundness: 0.9),  // round
            recognized: nil,
            existingNames: [],
            content: content,
            forcedSeed: 0xA0121E
        )

        #if DEBUG
        debugHatchSamplesIfRequested()
        // A featured creature on demand, so an interaction/animation demo can
        // land on Home in a freshly-installed simulator (which otherwise
        // starts on the empty capture screen). Seeds only when the collection
        // is empty, so it never disturbs a real save.
        if ProcessInfo.processInfo.environment["AURIE_SEED_HOME"] == "1",
           store.auries.isEmpty {
            if ProcessInfo.processInfo.environment["AURIE_SEED_PATTERNS"] == "1" {
                debugSeedPatternMatrix()
            } else if ProcessInfo.processInfo
                .environment["AURIE_HERO_COLLECTION"] == "1" {
                debugSeedHeroCollection()
            } else {
                debugSeedSamples()
            }
            store.settings.featuredAurieId = store.auries.first?.id
            // Natural-activation checks: feature a creature of a specific
            // family (AURIE_SEED_FEATURED_FAMILY=starlight) so Home picks
            // the environment through the real `aurie.family` path with no
            // environment force. Family is normally rolled, so if the seeds
            // produced none, add one with the family overridden — the same
            // post-generate override the pattern matrix uses for body.
            if let raw = ProcessInfo.processInfo.environment["AURIE_SEED_FEATURED_FAMILY"],
               let fam = AuraFamily(rawValue: raw) {
                if let match = store.auries.first(where: { $0.family == fam }) {
                    store.settings.featuredAurieId = match.id
                } else {
                    var extra = AurieGenerator.generate(
                        dominantColor: Rgb(150, 110, 200),
                        shape: ShapeSignal(aspectRatio: 1.0, roundness: 0.8),
                        recognized: nil,
                        existingNames: store.existingNames,
                        content: content)
                    extra.family = fam
                    store.add(extra)
                    store.settings.featuredAurieId = extra.id
                }
            }
            // AURIE_HERO=1 — THE known-good screenshot Aurie, frozen
            // 2026-09-25 for App Store capture. Every part is pinned, so a
            // shot never lands on a random roll: the round body and soft
            // tide blue from the approved app icon, arm_01 "Tiny Hands"
            // and leg_04 "Paw Steps" (the pairing chosen for the icon),
            // the happy resting face, no pattern, and the first
            // body-compatible hair. It replaces whatever the seed rolled as
            // the featured creature — pair it with AURIE_FACE_ONE=happy so
            // idle sleepiness cannot creep into the frame.
            if ProcessInfo.processInfo.environment["AURIE_HERO"] == "1",
               ProcessInfo.processInfo
                   .environment["AURIE_HERO_COLLECTION"] != "1" {
                debugHatchHeroNow()
            }
            // Capture aid: dismiss today's Daily card, so the taller play
            // area (and anything anchored to its corners) can be verified.
            if ProcessInfo.processInfo.environment["AURIE_HIDE_DAILY"] == "1" {
                store.settings.dailyLiftDismissedDate = Date()
            }
            // The whole point of this seed is to land on Home; skip the
            // one-time tutorial so the demo scene appears immediately.
            store.settings.hasSeenTutorial = true
        }
        // AURIE_GREET_PRESET=<name> — put the greeting inputs into one of
        // the states the contextual-greeting system must handle, so each
        // can be launched straight into and read back with AURIE_GREET_LOG.
        // Presets touch ONLY greeting inputs; pair with AURIE_SEED_HOME=1
        // for a creature. `noAurie` is the one that wants NO seed.
        //   noAurie   never hatched (first-Aurie pool)
        //   fresh     hatched, nothing discovered, arrival count 0
        //   toybox / calm / charms0 / charms1 / shake
        //             everything discovered EXCEPT that one feature
        //             (charms0 = none owned; charms1 = owned, unopened)
        //   done      every feature discovered, count past the early window
        //   normal    done + last arrival yesterday
        //   long      done + last arrival 8 days ago
        if let preset = ProcessInfo.processInfo.environment["AURIE_GREET_PRESET"] {
            let cal = Calendar.current
            func discovered(_ on: Bool) {
                store.settings.hasOpenedToyBox = on
                store.settings.hasSeenCalmIntro = on
                store.settings.hasOpenedCharmCollection = on
                store.settings.hasShakenPhone = on
            }
            store.settings.hasHatchedFirstAurie = !store.auries.isEmpty
            store.settings.homeArrivalCount = 0
            store.settings.lastGreetingDate = nil
            switch preset {
            case "noAurie": store.settings.hasHatchedFirstAurie = false
            case "fresh":   discovered(false); charms.debugResetAll()
            case "toybox":  discovered(true); store.settings.hasOpenedToyBox = false
                            store.settings.homeArrivalCount = 1
            case "calm":    discovered(true); store.settings.hasSeenCalmIntro = false
                            store.settings.homeArrivalCount = 1
            case "charms0": discovered(true); store.settings.hasOpenedCharmCollection = false
                            charms.debugResetAll()
                            store.settings.homeArrivalCount = 1
            case "charms1": discovered(true); store.settings.hasOpenedCharmCollection = false
                            charms.debugResetAll(); _ = charms.unlock("charm_food_apple_01")
                            store.settings.homeArrivalCount = 1
            case "shake":   discovered(true); store.settings.hasShakenPhone = false
                            store.settings.homeArrivalCount = 1
            case "done":    discovered(true); store.settings.homeArrivalCount = 12
            case "normal":  discovered(true); store.settings.homeArrivalCount = 12
                            store.settings.lastGreetingDate = cal.date(byAdding: .day, value: -1, to: Date())
            case "long":    discovered(true); store.settings.homeArrivalCount = 12
                            store.settings.lastGreetingDate = cal.date(byAdding: .day, value: -8, to: Date())
            default: NSLog("AURIE_GREET_PRESET unknown '%@'", preset)
            }
            NSLog("AURIE_GREET_PRESET %@ applied", preset)
        }
        // AURIE_HATCH_CREDITS=<n> — top the wallet up through the REAL
        // grant path (`HatchGrantSource.debug`, which the wallet already
        // supports) so device testing is not blocked by the daily free
        // allowance. DEBUG-only; the id keeps the wallet's exactly-once
        // rule honest by varying per launch, so repeated launches with the
        // aid set really do add credits rather than being deduplicated.
        if let raw = ProcessInfo.processInfo
            .environment["AURIE_HATCH_CREDITS"], let n = Int(raw), n > 0 {
            wallet.apply(HatchGrant(
                amount: n, source: .debug,
                transactionId: "debug-\(UUID().uuidString)"))
            NSLog("AURIE_HATCH_CREDITS granted=%d available=%d",
                  n, wallet.hatchesAvailable)
        }
        debugCharmProofPersistIfRequested()
        debugCharmSeedUnlocksIfRequested()
        debugCharmEquipHooksIfRequested()
        debugCharmLiveDemoIfRequested()
        debugCharmMigrationSelftestIfRequested()
        debugBirthProofIfRequested()
        debugRecognitionSelftestIfRequested()
        debugTaskProofIfRequested()
        // Capture aid: seed N distinct counted days through the REAL
        // event path (AURIE_TASK_SEED_DAYS=3), so intermediate progress
        // states can be screenshotted without waiting days. Seeding is
        // setup, not play: any reward the seed itself completed is not
        // celebrated.
        if let raw = ProcessInfo.processInfo
            .environment["AURIE_TASK_SEED_DAYS"], let n = Int(raw), n > 0 {
            for k in 0 ..< n {
                recordCharmTaskEvent(.wonderRevealed, date: Date(
                    timeIntervalSince1970: Double(86_400 * (10 + k))
                        + 43_200))
            }
            pendingTaskRewards = []
        }
        #endif

        // LAUNCH RETROACTIVE PASS (Phase E): long-time players complete
        // state-scan tasks on first launch after the update; rewards
        // queue and celebrate on Home one at a time. Runs after the
        // DEBUG seeds so capture rosters count too.
        retroactiveCharmTaskPass()
        #if DEBUG
        // Greeting presets that need a specific charm state must apply it
        // AFTER the retroactive pass above: a seeded collection completes
        // make_friends at launch and would otherwise be handed Hearts again
        // straight after the preset wiped it.
        switch ProcessInfo.processInfo.environment["AURIE_GREET_PRESET"] {
        case "fresh", "charms0":
            charms.debugResetAll(); pendingTaskRewards = []
        case "charms1":
            charms.debugResetAll(); _ = charms.unlock("charm_food_apple_01")
            pendingTaskRewards = []
        default: break
        }
        #endif

        // Launch repair for the widget (Phase 8B): if the App Group snapshot
        // is missing, stale, from an older schema, or its still image is
        // gone, one export fixes it — deferred a beat so it never competes
        // with first paint.
        let featured = store.featured
        Task { @MainActor in
            let snapshot = WidgetBridge.loadSnapshot()
            let stillExists = snapshot.flatMap { WidgetBridge.imageURL(named: $0.imageFile) }
                .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            if snapshot?.featuredId != featured?.id || (featured != nil && !stillExists) {
                WidgetExporter.exportFeatured(featured)
            }
        }
    }

    /// Today's feel-good lift for Home. Independent of the featured creature.
    var todaysDaily: DailyLiftItem? { ContentService.daily.item() }

    // MARK: - Hatch pipeline (§5, §10)

    /// Photo -> signals. Color/shape extraction and Vision run concurrently
    /// off the main actor.
    ///
    /// `forcedRecognition` lets the bundled samples supply their own known
    /// identity instead of running Vision — the samples are canned objects, and
    /// Vision can't run in the Simulator anyway (see Recognition.classify), so
    /// this is what makes the sample buttons demonstrate Layers 2/3 everywhere.
    /// Real camera/library photos pass nil and go through Vision (works on device).
    func prepareHatch(from image: UIImage, forcedRecognition: RecognizedObject? = nil) async -> PendingHatch {
        async let signals = ImageSignals.extract(from: image)
        let recognized: RecognizedObject?
        if let forcedRecognition {
            recognized = forcedRecognition
        } else {
            recognized = await Recognition.classify(image)
        }
        let s = await signals
        return PendingHatch(image: image,
                            dominantColor: s.dominantColor,
                            shape: s.shape,
                            recognized: recognized)
    }

    /// Signals -> creature, auto-saved to the collection (a hatch is never
    /// wasted, §7). Fresh random seed each call, so two photos of the same
    /// object give related-but-different creatures.
    func completeHatch(_ pending: PendingHatch) -> Aurie {
        let aurie = generateHatch(pending)
        return commitHatch(aurie, from: pending).aurie
    }

    /// The creature, generated but NOT yet persisted. Measured at 0 ms, so it
    /// is safe to call on a critical path — the hatch flow needs the Aurie to
    /// exist behind the shell before the first fragment moves, and must not
    /// pay for disk I/O to get it.
    ///
    /// Generating does NOT spend a hatch. Nothing is committed until
    /// `commitHatch`, so §11 still holds: cancelling costs nothing.
    func generateHatch(_ pending: PendingHatch) -> Aurie {
        var aurie = AurieGenerator.generate(
            dominantColor: pending.dominantColor,
            shape: pending.shape,
            recognized: pending.recognized,
            existingNames: store.existingNames,
            content: content
        )
        #if DEBUG
        // Demo tools (§20): re-roll until the forced family comes up. Debug
        // builds only — rarity is never manipulable by users.
        if let forced = debugForcedFamily {
            var attempts = 0
            while aurie.family != forced && attempts < 600 {
                aurie = AurieGenerator.generate(
                    dominantColor: pending.dominantColor,
                    shape: pending.shape,
                    recognized: pending.recognized,
                    existingNames: store.existingNames,
                    content: content
                )
                attempts += 1
            }
        }
        #endif
        return aurie
    }

    /// Persist the creature and spend the hatch. Call EXACTLY once per egg.
    ///
    /// Deliberately separate from `generateHatch`: `store.add` is a
    /// synchronous write measured at 261 ms, which is far too much to sit in
    /// front of an animation. The hatch flow runs this once the shell is
    /// already in flight.
    @discardableResult
    func commitHatch(_ aurie: Aurie, from pending: PendingHatch)
        -> HatchCommitResult {
        var aurie = aurie
        aurie.sourceThumbnail = store.saveThumbnail(pending.image, for: aurie.id)
        // BIRTH CHARM (Phase D + the D2 launch rule): the SAME outcome
        // resolver the egg preview consumed — trigger eligibility plus
        // the one deterministic drop roll; nothing here can disagree
        // with what the player watched hatch. A losing roll is an
        // ordinary hatch — bornFrom keeps the recognition, birthCharmID
        // stays nil, and NOTHING else happens (no unlock, no ledger
        // entry, no equip, no reveal card). Provenance is stamped
        // BEFORE the save so a won charm persists with the newborn in
        // the same write.
        let outcome = birthCharmOutcome(for: aurie,
                                        recognized: pending.recognized)
        let earned = outcome?.wins == true
        if earned, let outcome { aurie.birthCharmID = outcome.charmID }
        store.add(aurie)
        // The hatch is spent ONLY here — after the creature is safely saved
        // (§11: cancelling the egg or any failure never costs a hatch).
        wallet.consumeHatch()
        var reveal: BirthCharmReveal?
        if earned, let outcome {
            (aurie, reveal) = applyBirthReward(outcome.charmID, to: aurie)
        }
        // Charm-task seam: the collection genuinely grew (fired AFTER
        // any Birth unlock so the state scan sees the new ownership).
        recordCharmTaskEvent(.aurieHatched)
        return HatchCommitResult(aurie: aurie, birthCharm: reveal)
    }

    // MARK: - Birth Charms (Phase D)

    /// The Birth-Charm trigger this recognition earns, mirroring EXACTLY
    /// the generator's acceptance gate (confidence threshold + mapped
    /// category) so provenance can never disagree with the "born from"
    /// identity the app displays: a photo the generator treats as "a
    /// mysterious shape" earns nothing, and a photo that names the
    /// creature's origin is the only kind that can. Label matching is
    /// CANONICAL (hero labels), never raw Vision text.
    private func birthTrigger(for recognized: RecognizedObject?)
        -> BirthCharmTrigger? {
        guard let r = recognized,
              r.confidence >= AurieGenerator.recognitionConfidenceThreshold,
              r.category != .unknown else { return nil }
        return AurieCharmCatalog.birthTrigger(forCanonicalLabel: r.label)
    }

    /// PREVIEW ONLY: the charm a commit of `pending` would be ELIGIBLE
    /// for. Eligibility, not a promise — the newborn still has to win
    /// its `birthCharmDropChance` roll at commit, so UI built on this
    /// must never imply the charm was definitely received. Reads the
    /// same trigger rule as the commit and writes NOTHING — no unlock,
    /// no provenance, no equipment. A cancelled hatch costs nothing.
    func prospectiveBirthCharmID(for pending: PendingHatch) -> String? {
        birthTrigger(for: pending.recognized)?.unlockCharmID
    }

    /// LAUNCH RULE (2026-09-19): a qualifying recognized object gives
    /// its Birth Charm with this chance, not always. ONE global rate;
    /// per-charm rates are a later product decision.
    static let birthCharmDropChance: Double = 0.50

    /// The ONE Birth-Charm roll for a hatch. Deterministic from the
    /// creature's permanent `seed` (salted through a splitmix64 mix so
    /// the outcome is independent of every other seed-derived trait),
    /// so a replayed or retried commit reaches the SAME verdict — the
    /// roll can never be rerolled, and nothing extra is persisted:
    /// `birthCharmID != nil` IS the recorded outcome.
    func birthCharmRollPasses(for aurie: Aurie) -> Bool {
        var x = aurie.seed &+ 0x9E37_79B9_7F4A_7C15   // salt
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        let unit = Double(x >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return unit < Self.birthCharmDropChance
    }

    /// A generated creature's complete Birth-Charm verdict: the charm
    /// its recognition is eligible for, and whether THIS hatch wins the
    /// one deterministic roll. PURE — trigger resolution + the seed
    /// roll, nothing else — and it is the SINGLE source both the egg
    /// preview and `commitHatch` consume, so the outcome the player
    /// first sees through the opening shell is by construction the
    /// outcome the commit persists. Nil = not eligible at all.
    struct BirthCharmOutcome {
        let charmID: String
        let wins: Bool
    }

    func birthCharmOutcome(for aurie: Aurie,
                           recognized: RecognizedObject?)
        -> BirthCharmOutcome? {
        guard let trigger = birthTrigger(for: recognized) else { return nil }
        return BirthCharmOutcome(charmID: trigger.unlockCharmID,
                                 wins: birthCharmRollPasses(for: aurie))
    }

    /// PREVIEW ONLY: the newborn as it must FIRST APPEAR when the shell
    /// opens — already wearing its Birth Charm when this hatch's
    /// outcome is a win, through the one shared equip-record rule.
    /// A pure value transform: nothing is unlocked, no provenance or
    /// ledger is written, nothing is saved — a cancelled egg discards
    /// the value and leaves zero permanent state. The later reveal card
    /// merely REPORTS the result the player already saw.
    func dressedForBirth(_ aurie: Aurie,
                         from pending: PendingHatch) -> Aurie {
        guard let outcome = birthCharmOutcome(
                  for: aurie, recognized: pending.recognized),
              outcome.wins,
              let def = AurieCharmCatalog.definition(outcome.charmID),
              let placement = def.placements.first(
                  where: CharmsView.supportedPlacements.contains)
        else { return aurie }
        var a = aurie
        a.equippedCharms = AurieCharmCatalog.equipping(
            a.resolvedEquippedCharms, with: outcome.charmID, at: placement)
        return a
    }

    /// The PERMANENT half of a Birth Charm, ledger-guarded per hatch so
    /// a replayed commit can never behave as a second reward: unlock at
    /// the account level, then start the newborn with the charm worn —
    /// through the SAME `equipCharm` product rule the Charms page uses,
    /// so one-charm-per-placement stays centralized and the player can
    /// later remove or replace it like any other charm. Ownership is
    /// never gated on the outfit: a missing definition, unsupported
    /// placement or absent art skips the auto-equip and keeps both the
    /// unlock and the provenance (rendering already degrades safely).
    private func applyBirthReward(_ charmID: String, to aurie: Aurie)
        -> (aurie: Aurie, reveal: BirthCharmReveal?) {
        // Owned-before is captured BEFORE the grant — afterwards the
        // charm is always owned, which is exactly why the reveal flow
        // must not infer "newly unlocked" from the collection.
        let ownedBefore = charms.isUnlocked(charmID)
        guard charms.processGrant("birth:\(aurie.id)", unlocking: charmID)
        else { return (aurie, nil) }   // replayed commit: never rewards
        if let def = AurieCharmCatalog.definition(charmID),
           let placement = def.placements.first(
               where: CharmsView.supportedPlacements.contains) {
            equipCharm(def, on: aurie, placement: placement)
        }
        // Return the saved record (now wearing the charm) so the reveal
        // flow shows exactly what Home will.
        return (store.auries.first { $0.id == aurie.id } ?? aurie,
                BirthCharmReveal(charmID: charmID,
                                 newlyUnlocked: !ownedBefore))
    }

    #if DEBUG
    /// Demo tools (§20).
    var debugForcedFamily: AuraFamily?

    /// Debug-only: hatch N creatures through the REAL generator and log the
    /// family/expression each was born with, so family-weighted assignment
    /// can be verified in the running app (there is no UI-test target, and
    /// this environment cannot tap the simulator). Enabled with
    /// `AURIE_HATCH_SAMPLES=<count>`; never runs otherwise, and the sample
    /// creatures are not added to the collection.
    func debugHatchSamplesIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment["AURIE_HATCH_SAMPLES"],
              let count = Int(raw), count > 0 else { return }
        let palette: [Rgb] = [
            Rgb(230, 60, 40), Rgb(240, 200, 60), Rgb(80, 180, 90),
            Rgb(70, 130, 200), Rgb(150, 110, 200), Rgb(160, 155, 150),
            Rgb(180, 200, 255),
        ]
        for i in 0 ..< count {
            let aurie = AurieGenerator.generate(
                dominantColor: palette[i % palette.count],
                shape: ShapeSignal(aspectRatio: 1.0, roundness: 0.8),
                recognized: nil,
                existingNames: [],
                content: content
            )
            NSLog("AURIE_HATCH family=%@ expression=%@",
                  aurie.family.rawValue,
                  aurie.baseExpression?.rawValue ?? "NIL-NOT-ASSIGNED")
        }
    }

    /// The known-good screenshot Aurie (see AURIE_HERO), added through the
    /// REAL `Store.add` seam — so everything that seam does (featured,
    /// hasHatchedFirstAurie) happens exactly as for a real hatch. Called at
    /// init by AURIE_HERO=1, and later by AURIE_GREET_HATCH_AFTER=<s> so the
    /// greeter → first-Aurie transition can be exercised on a live Home.
    func debugHatchHeroNow() {
        var hero = AurieGenerator.generate(
            dominantColor: Rgb(122, 168, 228),
            shape: ShapeSignal(aspectRatio: 1.0, roundness: 0.85),
            recognized: nil,
            existingNames: store.existingNames,
            content: content)
        hero.body = .round
        hero.family = .tide
        hero.baseColor = Rgb(122, 168, 228)
        hero.auraColor = AurieGenerator.auraColors[.tide] ?? hero.auraColor
        hero.baseExpression = .happy
        hero.pattern = PatternType.none
        hero.armStyle = "arm_01"
        hero.legStyle = "leg_04"
        if let hair = AurieLimbCatalog.compatibleHair(for: .round).first {
            hero.hairStyle = hair
        }
        // NO charms on the hero. A belly charm collides with the Worry Jar
        // the creature holds in Calm Mode, one of the six capture states.
        hero.equippedCharms = []
        hero.birthCharmID = nil
        store.add(hero)
        store.settings.featuredAurieId = hero.id
        NSLog("AURIE_HERO seeded name=%@ body=round arms=arm_01 "
              + "legs=leg_04 family=tide", hero.name)
    }

    func debugSeedSamples() {
        let palette: [Rgb] = [
            Rgb(230, 60, 40), Rgb(240, 200, 60), Rgb(80, 180, 90),
            Rgb(70, 130, 200), Rgb(150, 110, 200), Rgb(160, 155, 150),
        ]
        for (i, color) in palette.enumerated() {
            let aurie = AurieGenerator.generate(
                dominantColor: color,
                shape: ShapeSignal(aspectRatio: [1.0, 0.6, 1.6, 1.0, 0.9, 1.2][i],
                                   roundness: [0.9, 0.5, 0.5, 0.2, 0.6, 0.8][i]),
                recognized: nil,
                existingNames: store.existingNames,
                content: content
            )
            store.add(aurie)
        }
    }

    /// DEBUG: `AURIE_HERO_COLLECTION=1` (with `AURIE_SEED_HOME=1`) — SIX
    /// curated Auries for the App Store Collection screenshot, frozen
    /// 2026-09-25. The ordinary sample seed rolls everything, which in
    /// practice produced a grid where several creatures wore sleepy saved
    /// expressions and read as sad. Here every creature is deliberate:
    /// one per family so all six tiles carry a different tint, six
    /// distinct silhouettes, family-true colour, the HAPPY resting face,
    /// and a deliberate resting FACE. Three wear something other than the
    /// classic happy — Excited, Delighted and Curious — chosen from the
    /// cheerful half of the ten base expressions. Sleepy, Worried and
    /// Pouty are deliberately absent: a random roster wearing those is
    /// exactly what made the ungated grid read as sad.
    ///
    /// Tide leads so the featured crown lands on the same soft blue Aurie
    /// the app icon uses (`AURIE_HERO`), and Home shows it too.
    ///
    /// Limbs are an ASSORTMENT, not one repeated pairing: between them the
    /// six wear all three arm styles and all six launch leg styles, so the
    /// grid advertises the variety the generator can actually produce.
    /// Tide keeps the icon pairing (arm_01 + leg_04) because it is the
    /// featured creature and should match the app icon.
    ///
    /// HAIR: all three launch styles appear — the Soft Mohawk (hair_01) on
    /// Tide, the Cloud Puff (hair_00) on Starlight, the baked tuft on the
    /// other four. Note Tide therefore NO LONGER matches the app icon,
    /// which wears the tuft; that was an explicit owner choice 2026-09-26.
    ///
    /// PATTERNS AND CHARMS: two of each, spread so no tile carries both —
    /// stripes on Dusk, spots on Starlight (pinned to the busiest baked
    /// layout), a belly Apple on Moss and an aura Star on Dusk.
    /// The portrait renders the live `AurieNode`, so both show in the grid
    /// exactly as they do on Home.
    ///
    /// TIDE STAYS BARE — no pattern, no charm. It is the featured creature,
    /// so it is also the one Home and Calm Mode show, and a belly charm
    /// sits behind the Worry Jar the creature holds in Calm. Keeping it
    /// clean is what makes all six capture states usable from one seed.
    ///
    /// Nothing is set blind. Each preferred pairing is checked against the
    /// catalog's own compatible lists, and the roller's one hard rule —
    /// LONG arms only with LONG legs — is re-applied afterwards, so a
    /// malformed combination cannot reach the grid however the preferences
    /// are edited later.
    func debugSeedHeroCollection() {
        typealias Row = (AuraFamily, BodyType, Rgb, ShapeSignal,
                         arm: String, leg: String, hair: String,
                         pattern: PatternType, charm: EquippedCharm?,
                         patternVariant: Int?, face: BaseExpression)
        let rows: [Row] = [
            (.tide,      .round,    Rgb(122, 168, 228),
             ShapeSignal(aspectRatio: 1.00, roundness: 0.85),
             arm: "arm_01", leg: "leg_04", hair: "hair_01",
             pattern: .none, charm: nil, patternVariant: nil,
             face: .happy),
            (.ember,     .tall,     Rgb(232, 115,  74),
             ShapeSignal(aspectRatio: 0.70, roundness: 0.45),
             arm: "arm_02", leg: "leg_05", hair: "tuft",
             pattern: .none, charm: nil, patternVariant: nil,
             face: .excited),
            (.moss,      .dumpling, Rgb(124, 184, 110),
             ShapeSignal(aspectRatio: 1.15, roundness: 0.75),
             arm: "arm_02", leg: "leg_04", hair: "tuft",
             pattern: .none,
             charm: EquippedCharm(charmID: "charm_food_apple_01",
                                  slot: CharmSlot.belly.rawValue),
             patternVariant: nil, face: .happy),
            (.glow,      .egg,      Rgb(245, 200,  95),
             ShapeSignal(aspectRatio: 0.80, roundness: 0.70),
             arm: "arm_01", leg: "leg_02", hair: "tuft",
             pattern: .none, charm: nil, patternVariant: nil,
             face: .delighted),
            (.dusk,      .teardrop, Rgb(154, 120, 200),
             ShapeSignal(aspectRatio: 0.95, roundness: 0.60),
             arm: "arm_00", leg: "leg_03", hair: "tuft",
             pattern: .stripes,
             charm: EquippedCharm(charmID: "charm_magic_star_01",
                                  slot: CharmSlot.aura.rawValue),
             patternVariant: nil, face: .happy),
            (.starlight, .oval,     Rgb(186, 200, 245),
             ShapeSignal(aspectRatio: 1.10, roundness: 0.65),
             arm: "arm_01", leg: "leg_00", hair: "hair_00",
             // v0 is the busiest of the three baked spot layouts
             // (~11 marks, against ~10 and ~8).
             pattern: .spots, charm: nil, patternVariant: 0,
             face: .curious),
        ]
        for (family, body, color, shape, wantArm, wantLeg, wantHair,
             pattern, charm, patternVariant, face) in rows {
            var a = AurieGenerator.generate(
                dominantColor: color, shape: shape, recognized: nil,
                existingNames: store.existingNames, content: content)
            a.body = body
            a.family = family
            a.baseColor = color
            a.auraColor = AurieGenerator.auraColors[family] ?? a.auraColor
            a.baseExpression = face
            a.pattern = pattern
            // Pattern LAYOUT is baked art: three variants per body, chosen
            // as (seed >> 41) % 3. There is no density parameter, so the
            // only way to ask for a busier layout is to pin the seed bits
            // that choose it. +3 keeps the seed non-zero.
            if let v = patternVariant {
                a.seed = UInt64(v + 3) << 41
            }
            // Take the row's pairing only if this body allows it, then
            // re-apply the roller's LONG-arms-need-LONG-legs rule rather
            // than bypassing it.
            let arms = AurieLimbCatalog.compatibleArms(for: body)
            let legs = AurieLimbCatalog.compatibleLegs(for: body)
            a.legStyle = legs.contains(wantLeg) ? wantLeg
                                                : (legs.first ?? "leg_00")
            let legIsLong = (AurieLimbCatalog
                .legLength[a.resolvedLegStyle] ?? .standard) >= .long
            let arm = arms.contains(wantArm) ? wantArm
                                             : (arms.first ?? "arm_00")
            a.armStyle =
                (AurieLimbCatalog.armLength[arm] == .long && !legIsLong)
                ? "arm_00" : arm
            // hairExcluded can veto a style per body (hair_01 on Heart),
            // so ask the catalog before trusting the row.
            let hairs = AurieLimbCatalog.compatibleHair(for: body)
            a.hairStyle = hairs.contains(wantHair) ? wantHair
                                                   : (hairs.first ?? "tuft")
            // Only the rows that ask for one, and only on creatures that
            // never appear in Calm (see the note above). A charm the
            // catalog no longer knows is dropped rather than rendered as a
            // gap, so editing the rows can never ship a broken layer.
            a.equippedCharms = charm.flatMap {
                AurieCharmCatalog.definition($0.charmID) != nil ? [$0] : nil
            } ?? []
            a.birthCharmID = nil
            store.add(a)
            NSLog("AURIE_HERO_COLLECTION %@ family=%@ body=%@ arms=%@ "
                  + "legs=%@ hair=%@",
                  a.name, family.rawValue, body.rawValue,
                  a.resolvedArmStyle, a.resolvedLegStyle,
                  a.resolvedHairStyle)
            NSLog("AURIE_HERO_COLLECTION   %@ face=%@ pattern=%@ charms=%@",
                  a.name, a.resolvedBaseExpression.rawValue,
                  a.pattern?.rawValue ?? "none",
                  a.equippedCharms?.map(\.charmID).joined(separator: ",")
                      ?? "none")
        }
    }

    /// DEBUG: a controlled matrix for verifying the pattern system — the six
    /// §8 test bodies, each wearing a different pattern, across families. The
    /// body and pattern are overridden on a generated Aurie so coverage is
    /// deterministic instead of left to the shape/seed roll. Enabled by
    /// `AURIE_SEED_PATTERNS=1` (alongside `AURIE_SEED_HOME=1`).
    func debugSeedPatternMatrix() {
        let rows: [(BodyType, PatternType, Rgb, ShapeSignal)] = [
            (.round,   .spots,    Rgb(230,  60,  40), ShapeSignal(aspectRatio: 1.0, roundness: 0.9)),
            (.tall,    .stripes,  Rgb(240, 200,  60), ShapeSignal(aspectRatio: 0.6, roundness: 0.5)),
            (.small,   .speckles, Rgb( 80, 180,  90), ShapeSignal(aspectRatio: 1.0, roundness: 0.6)),
            (.pear,    .stars,    Rgb( 70, 130, 200), ShapeSignal(aspectRatio: 0.9, roundness: 0.4)),
            (.beanbag, .hearts,   Rgb(150, 110, 200), ShapeSignal(aspectRatio: 1.6, roundness: 0.5)),
            (.heart,   .none,     Rgb(230,  90,  60), ShapeSignal(aspectRatio: 0.9, roundness: 0.3)),
        ]
        for (body, pattern, color, shape) in rows {
            var aurie = AurieGenerator.generate(
                dominantColor: color, shape: shape, recognized: nil,
                existingNames: store.existingNames, content: content)
            aurie.body = body          // force coverage of the §8 bodies
            aurie.pattern = pattern     // force each pattern for a clean read
            store.add(aurie)
        }
    }

    #endif

    // MARK: Charm equipment (phase C)
    // PRODUCTION, deliberately outside every #if DEBUG: the Charms page
    // and the Birth-Charm auto-equip both ship on this pair. (Release-
    // safety audit 2026-09-18: these two lived inside the demo-tools
    // DEBUG region above, which no Debug build could ever notice — the
    // first Release build failed on it.)

    /// PRODUCT RULE: an Aurie wears at most ONE charm per placement.
    /// Equipping into an occupied placement REPLACES the occupant —
    /// same array, same Store seam, no second slot system. Other
    /// placements are untouched, so Belly + Back coexist.
    func equipCharm(_ def: CharmDefinition, on aurie: Aurie,
                    placement: String) {
        var a = aurie
        // Charm-task seam: equipping into a slot that held a DIFFERENT
        // charm is a replacement (Fresh Look); either way an equip
        // happened. Detected BEFORE the write, fired after it.
        let previous = a.resolvedEquippedCharms
            .first { $0.slot == placement }?.charmID
        a.equippedCharms = AurieCharmCatalog.equipping(
            a.resolvedEquippedCharms, with: def.id, at: placement)
        store.update(a)
        if let previous, previous != def.id {
            recordCharmTaskEvent(.charmReplaced)
        }
        recordCharmTaskEvent(.charmEquipped)
    }

    func removeCharm(_ charmID: String, from aurie: Aurie) {
        var a = aurie
        a.equippedCharms = a.resolvedEquippedCharms
            .filter { $0.charmID != charmID }
        store.update(a)
    }

    #if DEBUG
    // MARK: DEBUG charm verification hooks (2026-09-14)
    // Permanent developer tooling in the app's AURIE_* env-hook style;
    // none is a product cheat or debug UI, all compile out of Release.

    /// Equip-rule verification hooks:
    /// AURIE_CHARM_EQUIP=<id>    equip on the featured Aurie through the
    ///                           REAL equipCharm path (placement = first
    ///                           supported), persisted via the Store.
    /// AURIE_CHARM_UNEQUIP=<id>  remove from the featured Aurie.
    /// AURIE_FEATURE_OTHER=1     feature a different Aurie (isolation
    ///                           check: equipment must not leak).
    /// AURIE_CHARM_VERIFY=1      NSLog every Aurie's persisted records.
    private func debugCharmEquipHooksIfRequested() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["AURIE_FEATURE_OTHER"] == "1",
           let featured = store.featured,
           let other = store.auries.first(where: { $0.id != featured.id }) {
            store.setFeatured(other)
        }
        if let id = env["AURIE_CHARM_EQUIP"],
           let def = AurieCharmCatalog.definition(id),
           let aurie = store.featured,
           let placement = def.placements.first(where:
               CharmsView.supportedPlacements.contains) {
            equipCharm(def, on: aurie, placement: placement)
        }
        if let id = env["AURIE_CHARM_UNEQUIP"], let aurie = store.featured {
            removeCharm(id, from: aurie)
        }
        if env["AURIE_CHARM_VERIFY"] == "1" {
            for a in store.auries {
                let recs = a.resolvedEquippedCharms
                    .map { "\($0.slot)=\($0.charmID)" }
                    .joined(separator: ", ")
                NSLog("AURIE_CHARM_VERIFY %@%@ [%@]", a.name,
                      a.id == store.settings.featuredAurieId ? "*" : "",
                      recs)
            }
        }
        #endif
    }

    /// AURIE_CHARM_LIVE_DEMO=1 — the ONE-SESSION equip sequence, no
    /// relaunches: pizza -> apple -> star -> +backpack -> -star ->
    /// -backpack on the featured Aurie, every step through the REAL
    /// equipCharm/removeCharm + Store.update seam while the Home scene
    /// is live. Proves the live-refresh path end to end. Leaves with
    /// the PoC.
    private func debugCharmLiveDemoIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo
            .environment["AURIE_CHARM_LIVE_DEMO"] == "1" else { return }
        func log(_ step: String) {
            let recs = store.featured?.resolvedEquippedCharms
                .map { "\($0.slot)=\($0.charmID)" }
                .joined(separator: ", ") ?? "-"
            NSLog("AURIE_LIVE_DEMO %@ [%@]", step, recs)
        }
        func equip(_ id: String, at t: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self, let def = AurieCharmCatalog.definition(id),
                      let aurie = self.store.featured,
                      let placement = def.placements.first(where:
                          CharmsView.supportedPlacements.contains) else { return }
                self.equipCharm(def, on: aurie, placement: placement)
                log("equip \(id)")
            }
        }
        func unequip(_ id: String, at t: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self, let aurie = self.store.featured else { return }
                self.removeCharm(id, from: aurie)
                log("remove \(id)")
            }
        }
        log("start")
        equip("charm_food_pizza_01", at: 6)
        equip("charm_food_apple_01", at: 14)
        equip("charm_magic_star_01", at: 22)
        equip("charm_object_backpack_01", at: 30)
        unequip("charm_magic_star_01", at: 46)
        unequip("charm_object_backpack_01", at: 54)
        #endif
    }

    /// AURIE_CHARM_SEED_UNLOCKS=id1,id2 — unlock the listed charms
    /// through the REAL account-level CharmService path, so the Charms
    /// page can be reviewed with a mixed locked/unlocked collection.
    private func debugCharmSeedUnlocksIfRequested() {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo
            .environment["AURIE_CHARM_SEED_UNLOCKS"] else { return }
        for id in raw.split(separator: ",").map(String.init) {
            _ = charms.unlock(id)
        }
        #endif
    }

    /// AURIE_CHARM_PROOF_PERSIST=1 — exercise the REAL persistence path
    /// end to end: unlock the proof backpack in the account collection,
    /// equip it on the featured Aurie, save through the store. The next
    /// plain launch must show the charm from disk alone.
    private func debugCharmProofPersistIfRequested() {
        guard ProcessInfo.processInfo
            .environment["AURIE_CHARM_PROOF_PERSIST"] == "1" else { return }
        let id = "charm_object_backpack_01"
        charms.unlock(id)
        guard var featured = store.auries.first(where: {
            $0.id == store.settings.featuredAurieId }) ?? store.auries.first
        else {
            NSLog("AURIE_CHARM_PROOF no saved Aurie to equip")
            return
        }
        if !featured.resolvedEquippedCharms.contains(
            where: { $0.charmID == id }) {
            featured.equippedCharms = featured.resolvedEquippedCharms
                + [EquippedCharm(charmID: id,
                                 slot: CharmSlot.back.rawValue)]
            store.update(featured)
        }
        NSLog("AURIE_CHARM_PROOF unlocked=%d equippedOn=%@",
              charms.isUnlocked(id) ? 1 : 0, featured.name)
    }

    /// AURIE_CHARM_MIGRATION_SELFTEST=1 — decode fixtures shaped like
    /// saves from BEFORE the charm system (including one carrying the
    /// removed tail/head/backAccessoryID keys) through the REAL
    /// decoders, and log PASS/FAIL per check.
    private func debugCharmMigrationSelftestIfRequested() {
        guard ProcessInfo.processInfo
            .environment["AURIE_CHARM_MIGRATION_SELFTEST"] == "1"
        else { return }
        func report(_ name: String, _ ok: Bool) {
            NSLog("AURIE_CHARM_MIGRATION %@ %@", ok ? "PASS" : "FAIL", name)
        }
        do {
            let enc = JSONEncoder(), dec = JSONDecoder()
            // A pre-charm save: no equippedCharms key, stray legacy
            // accessory keys that any experimental build might have
            // written. Both must be harmless.
            var obj = try JSONSerialization.jsonObject(
                with: enc.encode(greeter)) as! [String: Any]
            obj.removeValue(forKey: "equippedCharms")
            obj["tailAccessoryID"] = "charm_magic_star_01"
            obj["headAccessoryID"] = "charm_legacy_placeholder_01"
            let a1 = try dec.decode(Aurie.self, from:
                JSONSerialization.data(withJSONObject: obj))
            report("pre-charm Aurie decodes bare",
                   a1.resolvedEquippedCharms.isEmpty)
            let arr = try dec.decode([Aurie].self, from:
                JSONSerialization.data(withJSONObject: [obj, obj]))
            report("pre-charm collection decodes", arr.count == 2)
            // Equip round-trip through the real coder.
            var a2 = greeter
            a2.equippedCharms = [EquippedCharm(
                charmID: "charm_object_backpack_01",
                slot: CharmSlot.back.rawValue)]
            let a3 = try dec.decode(Aurie.self, from: enc.encode(a2))
            report("equipped charm round-trips",
                   a3.resolvedEquippedCharms == a2.equippedCharms)
            // Future-lenient EquippedCharm: missing slot resolves from
            // the catalog; unknown fields are ignored.
            let worn = try dec.decode(EquippedCharm.self, from: Data("""
                {"charmID": "charm_object_backpack_01", "glow": true}
                """.utf8))
            report("slotless equip resolves from catalog",
                   worn.slot == CharmSlot.back.rawValue)
            // charms.json: empty and future-shaped files decode safely.
            let c1 = try dec.decode(CharmCollection.self,
                                    from: Data("{}".utf8))
            let c2 = try dec.decode(CharmCollection.self, from: Data("""
                {"unlockedCharmIDs": ["a"], "futureField": 3}
                """.utf8))
            report("empty charms.json decodes",
                   c1.unlockedCharmIDs.isEmpty
                   && c1.processedGrantIds.isEmpty)
            report("future charms.json decodes",
                   c2.unlockedCharmIDs == ["a"])
        } catch {
            NSLog("AURIE_CHARM_MIGRATION FAIL threw %@", "\(error)")
        }
    }

    /// AURIE_BIRTH_PROOF=1 — the Phase D regression sequence through the
    /// REAL pipeline (PendingHatch → generateHatch → commitHatch → the
    /// product equip/remove paths), numbered to the requirement list.
    /// Mutates the running install's store exactly like real hatches:
    /// run on a fresh simulator install, read the PASS/FAIL lines,
    /// then uninstall.
    private func debugBirthProofIfRequested() {
        guard ProcessInfo.processInfo
            .environment["AURIE_BIRTH_PROOF"] == "1" else { return }
        var pass = 0, fail = 0
        func check(_ name: String, _ ok: Bool) {
            if ok { pass += 1 } else { fail += 1 }
            NSLog("AURIE_BIRTH_PROOF %@ %@", ok ? "PASS" : "FAIL", name)
        }
        func fetch(_ id: String) -> Aurie {
            store.auries.first { $0.id == id }!
        }
        func belly(_ a: Aurie) -> String? {
            AurieCharmCatalog.equippedCharmID(
                in: a.resolvedEquippedCharms,
                placement: CharmSlot.belly.rawValue)
        }
        let img = UIGraphicsImageRenderer(size: .init(width: 8, height: 8))
            .image { $0.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }
        func pend(_ r: RecognizedObject?) -> PendingHatch {
            PendingHatch(image: img, dominantColor: Rgb(210, 70, 60),
                         shape: ShapeSignal(aspectRatio: 1.0,
                                            roundness: 0.85),
                         recognized: r)
        }
        let apple = RecognizedObject(label: "apple", category: .food,
                                     confidence: 0.92)
        let appleID = "charm_food_apple_01"
        let bellySlot = CharmSlot.belly.rawValue
        // D2 drop rule: the roll is deterministic per creature, so a
        // test can PICK its outcome by regenerating until the wanted
        // verdict comes up — both branches run through the real logic,
        // no bypass hooks.
        func gen(_ p: PendingHatch, winning: Bool) -> Aurie {
            var a = generateHatch(p)
            var tries = 0
            while birthCharmRollPasses(for: a) != winning, tries < 500 {
                a = generateHatch(p)
                tries += 1
            }
            return a
        }

        do {
            // 1. Backwards compatibility: nil is omitted on encode, and
            // an old-shape save (no birthCharmID key) decodes to nil.
            let old = generateHatch(pend(apple))     // never committed
            var dict = try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(old)) as! [String: Any]
            check("1a encoder omits nil birthCharmID",
                  dict["birthCharmID"] == nil)
            dict["equippedCharms"] = nil             // old-shape save
            let back = try JSONDecoder().decode(
                Aurie.self,
                from: JSONSerialization.data(withJSONObject: dict))
            check("1b old save decodes birthCharmID nil",
                  back.birthCharmID == nil)
        } catch { check("1 old-save decode", false) }

        // 3. Cancelled qualifying hatch — even one that WOULD have won
        // its roll: preview may name the charm, nothing permanent moves.
        let unlocks0 = charms.collection.unlockedCharmIDs
        let ledger0 = charms.collection.processedGrantIds
        let count0 = store.auries.count
        check("3a preview names apple (eligibility)",
              prospectiveBirthCharmID(for: pend(apple)) == appleID)
        _ = gen(pend(apple), winning: true)          // cancelled egg
        check("3b cancel: no unlock",
              charms.collection.unlockedCharmIDs == unlocks0)
        check("3c cancel: no ledger entry",
              charms.collection.processedGrantIds == ledger0)
        check("3d cancel: nothing saved", store.auries.count == count0)

        // 12. Qualifying hatch that LOSES its roll (apple not yet
        // owned): an ordinary hatch — recognition kept, nothing else.
        let pLose = pend(apple)
        let rLose = commitHatch(gen(pLose, winning: false), from: pLose)
        check("12a lost roll keeps bornFrom",
              rLose.aurie.bornFrom == "apple")
        check("12b lost roll: no provenance",
              rLose.aurie.birthCharmID == nil)
        check("12c lost roll: no unlock", !charms.isUnlocked(appleID))
        check("12d lost roll: no ledger entry",
              charms.collection.processedGrantIds == ledger0)
        check("12e lost roll: no equipment",
              rLose.aurie.resolvedEquippedCharms.isEmpty)
        check("12f lost roll: no reveal", rLose.birthCharm == nil)

        // 14. PREVIEW DRESSING (hatch-timing fix): the dressed preview
        // of a winning creature already wears the charm through the
        // shared equip rule, while a losing one stays bare — and the
        // dressing itself persists NOTHING.
        let pDress = pend(apple)
        let winPreview = dressedForBirth(gen(pDress, winning: true),
                                         from: pDress)
        let losePreview = dressedForBirth(gen(pDress, winning: false),
                                          from: pDress)
        check("14a winning preview already wears the charm",
              belly(winPreview) == appleID)
        check("14b losing preview stays bare",
              losePreview.resolvedEquippedCharms.isEmpty)
        check("14c dressing persists nothing",
              charms.collection.unlockedCharmIDs == unlocks0
              && charms.collection.processedGrantIds == ledger0
              && store.auries.count == count0 + 1)   // only 12's commit
        check("14d preview and commit share one outcome",
              birthCharmOutcome(for: winPreview,
                                recognized: pDress.recognized)?.wins == true
              && birthCharmOutcome(for: losePreview,
                                   recognized: pDress.recognized)?.wins == false)

        // 2. Committed qualifying hatch that WINS its roll: unlock +
        // provenance + starts worn + first-unlock reveal. Committing
        // the DRESSED preview mirrors the real egg flow.
        let pBrook = pend(apple)
        let rBrook = commitHatch(
            dressedForBirth(gen(pBrook, winning: true), from: pBrook),
            from: pBrook)
        let brook = rBrook.aurie
        check("2a apple unlocked", charms.isUnlocked(appleID))
        check("2b provenance recorded", brook.birthCharmID == appleID)
        check("2c newborn wears apple in belly", belly(brook) == appleID)
        check("2d reveal: newly unlocked",
              rBrook.birthCharm?.charmID == appleID
              && rBrook.birthCharm?.newlyUnlocked == true)
        check("2e roll is stable for a creature",
              birthCharmRollPasses(for: brook)
              == birthCharmRollPasses(for: brook))

        // 5/6/7. No lock-in: replace, remove, re-equip — provenance and
        // ownership never move.
        let pizza = AurieCharmCatalog.definition("charm_food_pizza_01")!
        let appleDef = AurieCharmCatalog.definition(appleID)!
        equipCharm(pizza, on: fetch(brook.id), placement: bellySlot)
        check("5a pizza replaced apple", belly(fetch(brook.id)) == pizza.id)
        check("5b provenance still apple",
              fetch(brook.id).birthCharmID == appleID)
        check("5c apple still unlocked", charms.isUnlocked(appleID))
        removeCharm(pizza.id, from: fetch(brook.id))
        check("6a removal leaves belly bare",
              belly(fetch(brook.id)) == nil)
        check("6b removal keeps provenance",
              fetch(brook.id).birthCharmID == appleID)
        equipCharm(appleDef, on: fetch(brook.id), placement: bellySlot)
        check("7 re-equip returns apple", belly(fetch(brook.id)) == appleID)

        // 10. Non-qualifying recognitions: ordinary hatch, no reward,
        // no reveal for the UI. (Flower is a canonical hero with NO
        // birth trigger — mug graduated to a trigger in D2, so it can
        // no longer serve as the control.)
        let flower = RecognizedObject(label: "flower", category: .plant,
                                      confidence: 0.9)
        let pPlain = pend(flower)
        let rPlain = commitHatch(generateHatch(pPlain), from: pPlain)
        let plain = rPlain.aurie
        check("10a flower hatch: no provenance", plain.birthCharmID == nil)
        check("10b flower hatch: no equipment",
              plain.resolvedEquippedCharms.isEmpty)
        check("10e flower commit exposes no reveal",
              rPlain.birthCharm == nil)
        check("10c low-confidence apple ignored",
              prospectiveBirthCharmID(for: pend(RecognizedObject(
                  label: "apple", category: .food,
                  confidence: 0.2))) == nil)
        check("10d unrecognized photo ignored",
              prospectiveBirthCharmID(for: pend(nil)) == nil)

        // 8. Another Aurie wears the same unlock; neither provenance
        // moves.
        equipCharm(appleDef, on: fetch(plain.id), placement: bellySlot)
        check("8a other aurie wears apple", belly(fetch(plain.id)) == appleID)
        check("8b other provenance still nil",
              fetch(plain.id).birthCharmID == nil)
        check("8c brook provenance unchanged",
              fetch(brook.id).birthCharmID == appleID)

        // 9. Replay: the same hatch's grant must never reward twice —
        // ledger blocks it and the player's later outfit survives.
        equipCharm(pizza, on: fetch(brook.id), placement: bellySlot)
        let ledgerMid = charms.collection.processedGrantIds
        let replay = applyBirthReward(appleID, to: fetch(brook.id))
        check("9a replay: ledger unchanged",
              charms.collection.processedGrantIds == ledgerMid)
        check("9b replay: outfit not re-overwritten",
              belly(fetch(brook.id)) == pizza.id)
        check("9c replay exposes no reveal", replay.reveal == nil)

        // 4. Already-unlocked charm, NEW hatch that WINS: full
        // provenance + equip + a fresh ledger entry; ownership simply
        // stays owned, and the reveal must NOT claim a new unlock.
        let pSecond = pend(apple)
        let rSecond = commitHatch(gen(pSecond, winning: true),
                                  from: pSecond)
        let second = rSecond.aurie
        check("4a second hatch records provenance",
              second.birthCharmID == appleID)
        check("4b second newborn wears apple", belly(second) == appleID)
        check("4c new grant event ledgered",
              // BIRTH entries only: the aurieHatched task seam can
              // legitimately add task: grants during these hatches.
              charms.collection.processedGrantIds
                  .filter { $0.hasPrefix("birth:") }.count
              == ledgerMid.filter { $0.hasPrefix("birth:") }.count + 1)
        check("4d distinct auries, one unlock",
              second.id != brook.id && charms.isUnlocked(appleID))
        check("4e reveal owned, not newly unlocked",
              rSecond.birthCharm?.charmID == appleID
              && rSecond.birthCharm?.newlyUnlocked == false)

        // 13. Already-unlocked charm, NEW hatch that LOSES: ordinary
        // hatch for this newborn; account ownership is untouched.
        let ledgerOwned = charms.collection.processedGrantIds
        let pOF = pend(apple)
        let rOF = commitHatch(gen(pOF, winning: false), from: pOF)
        check("13a owned+lost: no provenance",
              rOF.aurie.birthCharmID == nil)
        check("13b owned+lost: no equipment",
              rOF.aurie.resolvedEquippedCharms.isEmpty)
        check("13c owned+lost: no reveal", rOF.birthCharm == nil)
        check("13d owned+lost: ownership intact",
              charms.isUnlocked(appleID))
        check("13e owned+lost: ledger unchanged",
              charms.collection.processedGrantIds == ledgerOwned)

        NSLog("AURIE_BIRTH_PROOF DONE pass=%d fail=%d", pass, fail)
    }

    /// AURIE_TASK_PROOF=1 — the full launch-task regression suite
    /// through the REAL model paths (12 tasks, three progress kinds,
    /// retroactive scans, the cascade, the reward queue). Fresh
    /// simulator install; read the PASS/FAIL lines.
    private func debugTaskProofIfRequested() {
        guard ProcessInfo.processInfo
            .environment["AURIE_TASK_PROOF"] == "1" else { return }
        // The suite builds its collection from zero; combined runs with
        // other proofs (which hatch their own creatures) would poison
        // the state metrics. Run it on a fresh install, alone.
        guard store.auries.isEmpty,
              charms.collection.unlockedCharmIDs.isEmpty else {
            NSLog("AURIE_TASK SKIPPED - store not fresh; run alone")
            return
        }
        var pass = 0, fail = 0
        func check(_ name: String, _ ok: Bool) {
            if ok { pass += 1 } else { fail += 1 }
            NSLog("AURIE_TASK %@ %@", ok ? "PASS" : "FAIL", name)
        }
        func task(_ id: String) -> CharmTaskDefinition {
            CharmTaskCatalog.all.first { $0.id == id }!
        }
        func done(_ id: String) -> Bool { isCharmTaskCompleted(task(id)) }
        func day(_ k: Int) -> Date {
            Date(timeIntervalSince1970: Double(86_400 * k) + 43_200)
        }
        func newAurie() -> Aurie {
            var a = AurieGenerator.generate(
                dominantColor: Rgb(150, 110, 200),
                shape: ShapeSignal(aspectRatio: 1.0, roundness: 0.8),
                recognized: nil, existingNames: store.existingNames,
                content: content)
            a.family = .tide
            store.add(a)
            return a
        }
        pendingTaskRewards = []

        // 0. Integrity: 9 launch tasks, unique rewards. Every task awards
        // since Try a New Look was withdrawn 2026-09-25, so the reward set
        // no longer contains a nil.
        check("0a nine launch tasks", CharmTaskCatalog.all.count == 9)
        check("0b rewards are unique",
              Set(CharmTaskCatalog.all.map(\.rewardCharmID)).count == 9)

        // 1. Daily Wonders were WITHDRAWN from launch (2026-09-20). The
        // event seams still exist but nothing consumes them, so firing
        // them must move no task and grant nothing at all.
        let ledgerBeforeWonder = charms.collection.processedGrantIds
        let ownedBeforeWonder = charms.collection.unlockedCharmIDs
        for k in 1 ... 30 { markSparkRevealed(date: day(100 + k)) }
        for i in 1 ... 10 { saveToWonderbook("w\(i)") }
        check("1a no launch task consumes Wonder events",
              CharmTaskCatalog.tasks(for: .wonderRevealed).isEmpty
              && CharmTaskCatalog.tasks(for: .wonderSaved).isEmpty)
        check("1b Wonder events grant nothing",
              charms.collection.processedGrantIds == ledgerBeforeWonder
              && charms.collection.unlockedCharmIDs == ownedBeforeWonder)
        check("1c the four Wonder tasks are gone",
              ["five_daily_wonders", "wonder_to_keep", "wonder_collector",
               "month_of_wonders"].allSatisfy { id in
                  !CharmTaskCatalog.all.contains { $0.id == id } })
        // The Star and Crystal auras were REASSIGNED to the two new
        // non-Wonder tasks; the two badges were hidden instead.
        check("1d orphaned Wonder badges exist, unassigned, hidden",
              ["charm_badge_spark_01", "charm_badge_wonderbook_01"]
              .allSatisfy { id in
                  AurieCharmCatalog.definition(id)?.launch == false
                  && !CharmTaskCatalog.all.contains { $0.rewardCharmID == id }
              })

        // 3. Calm visits: distinct days only.
        recordCharmTaskEvent(.calmVisited, date: day(500))
        recordCharmTaskEvent(.calmVisited, date: day(500))   // same day
        check("3a same-day calm visits count once",
              charmTaskProgress(task("quiet_visits")) == 1)
        recordCharmTaskEvent(.calmVisited, date: day(501))
        recordCharmTaskEvent(.calmVisited, date: day(502))
        check("3b three calm days -> snowflake aura",
              done("quiet_visits")
              && charms.isUnlocked("charm_nature_snowflake_01"))

        // 4. Collection + equipment tasks (retroactive state scans
        // driven through the real seams).
        let a1 = newAurie(); let a2 = newAurie()
        recordCharmTaskEvent(.aurieHatched)
        check("4a two auries: friends incomplete", !done("make_friends"))
        let a3 = newAurie()
        recordCharmTaskEvent(.aurieHatched)
        check("4b three auries -> friendship hearts",
              done("make_friends")
              && charms.isUnlocked("charm_friendship_hearts_01"))
        _ = a3

        // Try a New Look was WITHDRAWN FROM LAUNCH 2026-09-25, so there is
        // no longer a reward-less task to exercise. The two equips below
        // stay because 4d needs the SAME charm on two Auries — Apple is
        // used because it is not itself a task reward.
        let plainCharm = AurieCharmCatalog.definition("charm_food_apple_01")!
        equipCharm(plainCharm, on: store.auries.first { $0.id == a1.id }!,
                   placement: CharmSlot.belly.rawValue)
        equipCharm(plainCharm, on: store.auries.first { $0.id == a2.id }!,
                   placement: CharmSlot.belly.rawValue)
        check("4d same charm on 2 -> blossom aura",
              done("share_the_style")
              && charms.isUnlocked("charm_nature_flower_03"))
        let spark = AurieCharmCatalog.definition("charm_badge_spark_01")!
        equipCharm(spark, on: store.auries.first { $0.id == a3.id }!,
                   placement: CharmSlot.belly.rawValue)
        check("4e charms on 3 auries -> team badge",
              done("styled_crew")
              && charms.isUnlocked("charm_badge_team_01"))

        // 5. Replacement (event-only, never retroactive).
        let tree = AurieCharmCatalog.definition("charm_nature_tree_02")!
        equipCharm(tree, on: store.auries.first { $0.id == a1.id }!,
                   placement: CharmSlot.belly.rawValue)
        check("5 replacing a charm -> refresh badge",
              done("fresh_look")
              && charms.isUnlocked("charm_badge_refresh_01"))

        // 5b. A Full House: ten Auries (retroactive state scan, same
        // seam as Make Some Friends).
        check("5b ten auries not yet reached", !done("full_house"))
        for _ in 4 ... 10 { _ = newAurie() }
        recordCharmTaskEvent(.aurieHatched)
        check("5c ten auries -> star aura",
              done("full_house")
              && charms.isUnlocked("charm_magic_star_01"))

        // 5d. Old Friends: 30 DISTINCT days of real interaction. The
        // per-day collapse means repeat pokes on one day count once.
        recordAurieInteraction(date: day(600))
        recordAurieInteraction(date: day(600))   // same day, ignored
        check("5d same-day interactions count once",
              charmTaskProgress(task("old_friends")) == 1)
        for k in 601 ... 629 { recordAurieInteraction(date: day(k)) }
        check("5e thirty interaction days -> crystal aura",
              done("old_friends")
              && charms.isUnlocked("charm_magic_crystal_02"))

        // Ten charms deliberately span BOTH earning paths: task rewards
        // and Birth Charms. Birth Charms are core to the hatch/collection
        // loop, so needing hatch discoveries to reach ten owned charms is
        // intended pacing, not a gap. Unlock a few through the real
        // charms, so unlock a few through the real account path and fire
        // the hatch seam — exactly what commitHatch does after a birth
        // unlock. Without this, growing_collection is unreachable here.
        for id in ["charm_food_apple_01", "charm_food_cake_01",
                   "charm_food_cookie_01", "charm_food_lemon_01"] {
            charms.unlock(id)
        }
        recordCharmTaskEvent(.aurieHatched)

        // 6. Cascade: the grants above pushed ownership/categories far
        // past the thresholds — variety and growing completed WITHOUT
        // their own dedicated events.
        check("6a three categories -> rainbow (cascade)",
              done("charm_variety")
              && charms.isUnlocked("charm_nature_rainbow_cloud_01"))
        check("6b ten charms -> tree (cascade)",
              done("growing_collection")
              && charms.isUnlocked("charm_nature_tree_02"))

        // 7. All 8 complete; ledger exactly one entry per task; the
        // reward queue collected every celebration exactly once.
        check("7a every REWARDED task completed (9 of 10)",
              CharmTaskCatalog.rewarded.count == 9
              && CharmTaskCatalog.rewarded.allSatisfy {
                  isCharmTaskCompleted($0) })
        check("7b one ledger entry per task",
              CharmTaskCatalog.rewarded.allSatisfy { def in
                  charms.collection.processedGrantIds
                      .filter { $0 == CharmTaskCatalog.grantID(def) }
                      .count == 1 })
        check("7c queue holds each reward once",
              pendingTaskRewards.count == 9
              && Set(pendingTaskRewards.map(\.id)).count == 9)

        // 8. UNLOCK-ONLY: nothing was auto-equipped anywhere — the only
        // records are the three the test itself put on.
        let worn = store.auries.flatMap { $0.resolvedEquippedCharms }
        check("8 no auto-equip",
              worn.count == 3 && store.auries
                  .filter { !$0.resolvedEquippedCharms.isEmpty }.count == 3)

        pendingTaskRewards = []
        NSLog("AURIE_TASK DONE pass=%d fail=%d", pass, fail)
    }

    /// AURIE_RECOG_SELFTEST=1 — the canonical matcher through the REAL
    /// `Recognition.select` path (word-boundary fix, 2026-09-18), plus
    /// the chain into the Birth-Charm trigger. Pure — touches nothing.
    private func debugRecognitionSelftestIfRequested() {
        guard ProcessInfo.processInfo
            .environment["AURIE_RECOG_SELFTEST"] == "1" else { return }
        var pass = 0, fail = 0
        func check(_ name: String, _ ok: Bool) {
            if ok { pass += 1 } else { fail += 1 }
            NSLog("AURIE_RECOG %@ %@", ok ? "PASS" : "FAIL", name)
        }
        func run(_ label: String) -> RecognizedObject? {
            Recognition.select(
                from: [(identifier: label, confidence: 0.9)],
                gate: AurieGenerator.recognitionConfidenceThreshold)
        }
        // The Birth-Charm bug class: containment inside another word.
        let pine = run("pineapple")
        check("pineapple NOT apple",
              pine?.label == "pineapple" && pine?.category == .unknown)
        check("pineapple earns no Birth Charm",
              birthTrigger(for: pine) == nil)
        check("bookcase NOT book", run("bookcase")?.category == .unknown)
        // 2026-09-26: eggplant and cupcake are now REAL entries in the
        // object table (they earn a body shape), so "unrecognised" is no
        // longer the thing to assert. The invariant that matters is
        // unchanged and is what these now check: a containing word must
        // resolve to ITSELF, never be canonicalized to the shorter hero
        // hiding inside it.
        check("eggplant resolves to itself, not the plant hero",
              run("eggplant")?.label == "eggplant")
        check("cupcake resolves to itself, not cup or cake",
              run("cupcake")?.label == "cupcake")
        // Canonical hits that must keep working.
        let a = run("apple")
        check("apple -> hero apple",
              a?.label == "apple" && a?.category == .food)
        check("apple chains to birth_apple",
              AurieCharmCatalog.birthTrigger(forCanonicalLabel: a?.label)?
                  .unlockCharmID == "charm_food_apple_01")
        let gs = run("granny smith")
        check("granny smith -> hero apple (alias)",
              gs?.label == "apple" && gs?.category == .food)
        check("Vision underscores normalize",
              run("granny_smith")?.label == "apple")
        check("teddy bear -> hero teddy",
              run("teddy bear")?.label == "teddy")
        check("cellular telephone -> hero phone",
              run("cellular telephone")?.label == "phone")
        check("coffee mug -> hero mug", run("coffee mug")?.label == "mug")
        check("tableware -> container",
              run("tableware")?.category == .container)
        check("sunflower -> hero flower",
              run("sunflower")?.label == "flower")
        check("plural apples still maps",
              run("apples")?.label == "apple")
        check("scissors keyword survives fold",
              run("scissors")?.category == .tool)
        check("unrelated word stays unknown",
              run("escalator")?.category == .unknown)
        // D2 trigger wiring — stable heroes only.
        check("teddy chains to teddy charm",
              AurieCharmCatalog.birthTrigger(
                  forCanonicalLabel: run("teddy bear")?.label)?
                  .unlockCharmID == "charm_toy_teddy_01")
        check("mug chains to mug charm",
              AurieCharmCatalog.birthTrigger(
                  forCanonicalLabel: run("coffee mug")?.label)?
                  .unlockCharmID == "charm_object_mug_01")
        check("teacup canonicalizes to cup and chains",
              run("teacup")?.label == "cup"
              && AurieCharmCatalog.birthTrigger(forCanonicalLabel: "cup")?
                  .unlockCharmID == "charm_object_teacup_01")
        check("flower hero has no trigger (control)",
              AurieCharmCatalog.birthTrigger(
                  forCanonicalLabel: "flower") == nil)
        // D2 wiring round 2 (approved): six word heroes + the phrase
        // hero "beach ball"; orange deliberately un-triggered.
        func chain(_ label: String) -> String? {
            AurieCharmCatalog.birthTrigger(
                forCanonicalLabel: run(label)?.label)?.unlockCharmID
        }
        check("strawberry chains", chain("strawberry")
              == "charm_food_strawberry_01")
        check("lemon chains", chain("lemon") == "charm_food_lemon_01")
        check("carrot chains", chain("carrot") == "charm_food_carrot_01")
        check("cookie chains", chain("cookie") == "charm_food_cookie_01")
        check("cake chains", chain("cake") == "charm_food_cake_01")
        check("carrot cake resolves to Cake (approved)",
              run("carrot cake")?.label == "cake"
              && chain("carrot cake") == "charm_food_cake_01")
        check("balloon chains", chain("balloon")
              == "charm_toy_balloon_01")
        check("beach ball phrase chains", chain("beach ball")
              == "charm_toy_beach_ball_01")
        check("hot air balloon still balloon",
              chain("hot air balloon") == "charm_toy_balloon_01")
        // Required negative cases.
        check("NEG soccer ball earns nothing",
              chain("soccer ball") == nil
              && run("soccer ball")?.category == .toy)
        check("NEG tennis ball earns nothing",
              chain("tennis ball") == nil)
        check("NEG orange juice earns nothing",
              chain("orange juice") == nil)
        check("NEG orange itself earns nothing (no trigger)",
              chain("orange") == nil)
        // Still the real guard: a cupcake must never unlock the Cake or Cup
        // Birth Charm, whether or not the word itself is now recognised.
        check("NEG cupcake earns nothing", chain("cupcake") == nil)
        check("NEG muffin/bagel/donut earn nothing",
              chain("muffin") == nil && chain("bagel") == nil
              && chain("donut") == nil)
        check("NEG eggplant earns nothing (not the egg charm)",
              chain("eggplant") == nil)
        check("NEG pineapple earns nothing",
              chain("pineapple") == nil)
        NSLog("AURIE_RECOG DONE pass=%d fail=%d", pass, fail)
    }
    #endif
}

// MARK: - Today's Spark

extension AppModel {

    /// Today's Spark — ONE daily content system covering Lift, Laugh and Dare.
    ///
    /// Replaces the separate Daily Lift card and the Wonder pool: the same
    /// content, one mechanism. Selected on first use of the day and PERSISTED
    /// immediately by stable id, so relaunch / reshake / reread / changing the
    /// featured Aurie / changing family all return the identical item.
    @discardableResult
    func ensureTodaysSpark(date: Date = Date()) -> DailyLiftItem? {
        guard let pool = ContentService.daily else { return nil }
        let today = CalendarDay.key(for: date)

        if store.settings.savedWonderDayKey == today,
           let id = store.settings.savedWonderID,
           let saved = pool.item(id: id) {
            return saved
        }
        // New day, nothing saved yet, or a content update removed the id.
        // The replacement is persisted before returning, so this happens once.
        guard let pick = pool.item(for: date) else { return nil }
        store.settings.savedWonderDayKey = today
        store.settings.savedWonderID = pick.id
        return pick
    }

    /// Has today's Spark already been revealed by a shake?
    ///
    /// This gates the TEXT ONLY. The snow-globe effect itself runs on every
    /// shake and must never consult this.
    func sparkRevealedToday(date: Date = Date()) -> Bool {
        store.settings.wonderRevealedDayKey == CalendarDay.key(for: date)
    }

    /// Marked at the START of the reveal, so an interruption still counts.
    /// This is the GENUINE Wonder-reveal edge — the caller only reaches
    /// it when the reveal actually begins (never for a prepared/loaded
    /// Wonder, never after an abandoned swirl). The Wonder feature only
    /// EMITS the event; task progress, rewards, and their presentation
    /// belong to the task system — Wonder UI knows nothing about charms.
    func markSparkRevealed(date: Date = Date()) {
        store.settings.wonderRevealedDayKey = CalendarDay.key(for: date)
        recordCharmTaskEvent(.wonderRevealed, date: date)
    }

    // MARK: Charm tasks (Phase E)

    /// What ONE task completion produced. TRANSIENT — the durable
    /// record is the ledger entry. A completion whose reward was
    /// ALREADY owned still completes (newlyCompleted) but must not
    /// claim a new unlock (newlyUnlocked false). Identifiable so the
    /// reward queue can drive an item-based sheet.
    struct CharmTaskResult: Identifiable {
        let task: CharmTaskDefinition
        let newlyCompleted: Bool
        let newlyUnlocked: Bool
        var id: String { task.id }
    }

    /// Completion state for the Earn Charms page: the task's LEDGER
    /// entry, never reward ownership — Orange owned from some other
    /// source must not mark the Wonder task complete.
    func isCharmTaskCompleted(_ def: CharmTaskDefinition) -> Bool {
        CharmTaskCatalog.isCompleted(
            def, processedGrantIds: charms.collection.processedGrantIds)
    }

    /// Progress toward a task's target, by kind: counted distinct days,
    /// a live scan of persisted facts, or 0/1 for event-only tasks.
    func charmTaskProgress(_ def: CharmTaskDefinition) -> Int {
        if isCharmTaskCompleted(def) { return def.target }
        switch def.kind {
        case .distinctDays:
            return store.settings.charmTaskDayKeys[def.id]?.count ?? 0
        case .eventOnce:
            return 0
        case .state(let metric):
            return min(stateMetricValue(metric), def.target)
        }
    }

    /// The persisted fact a state task measures — always the CURRENT
    /// truth, which is exactly what makes those tasks retroactive.
    private func stateMetricValue(_ m: CharmTaskStateMetric) -> Int {
        switch m {
        case .wonderbookCount:
            return store.settings.savedWonderIDs.count
        case .aurieCount:
            return store.auries.count
        case .charmsOwned:
            return charms.collection.unlockedCharmIDs.count
        case .categoriesOwned:
            return Set(charms.collection.unlockedCharmIDs
                .compactMap(AurieCharmCatalog.definition)
                .flatMap(\.categories)).count
        case .auriesWearingCharms:
            return store.auries
                .filter { !$0.resolvedEquippedCharms.isEmpty }.count
        case .mostAuriesSharingACharm:
            var byCharm: [String: Int] = [:]
            for a in store.auries {
                for id in Set(a.resolvedEquippedCharms.map(\.charmID)) {
                    byCharm[id, default: 0] += 1
                }
            }
            return byCharm.values.max() ?? 0
        }
    }

    /// An app activity genuinely happened: advance every task keyed to
    /// that event, then re-evaluate every STATE task (a grant can raise
    /// owned-counts, which can complete further tasks — the cascade
    /// loops until stable). Day tasks count ONE calendar day at most
    /// once. Every completion goes through the ONE grant path Birth
    /// Charms use and is queued for the SEPARATE reward presentation.
    /// UNLOCK-ONLY by rule: a task reward is never auto-equipped and
    /// never touches what any Aurie wears.
    @discardableResult
    func recordCharmTaskEvent(_ event: CharmTaskEvent,
                              date: Date = Date()) -> [CharmTaskResult] {
        var newly: [CharmTaskResult] = []
        let dayKey = CalendarDay.key(for: date)
        for def in CharmTaskCatalog.tasks(for: event) {
            guard !isCharmTaskCompleted(def) else { continue }
            switch def.kind {
            case .distinctDays:
                var days = store.settings.charmTaskDayKeys[def.id] ?? []
                guard !days.contains(dayKey) else { continue }
                days.append(dayKey)
                store.settings.charmTaskDayKeys[def.id] = days
                if days.count >= def.target { complete(def, into: &newly) }
            case .eventOnce:
                complete(def, into: &newly)
            case .state:
                break                    // the cascade below owns these
            }
        }
        runStateCascade(into: &newly)
        pendingTaskRewards.append(contentsOf: newly)
        return newly
    }

    /// Configure RevenueCat ONCE and pick the purchase implementation.
    ///
    /// No usable key for this build configuration (any Release build until
    /// the production Apple key exists, or a fresh clone with no
    /// LocalSecrets.xcconfig) means purchases are simply UNAVAILABLE. We
    /// never fall back to the Test Store outside Debug.
    private static func makePurchaseService() -> PurchaseService {
        guard let key = PurchaseConfiguration.apiKey else {
            NSLog("AURIE_PURCHASE service=unavailable reason=no-api-key-for-this-configuration")
            return UnavailablePurchaseService()
        }
        Purchases.logLevel = .warn
        #if DEBUG
        // Verbose only while the purchase QA harness is driving.
        if ProcessInfo.processInfo.environment["AURIE_PURCHASE_QA"] == "1" {
            Purchases.logLevel = .debug
        }
        #endif
        Purchases.configure(withAPIKey: key)
        NSLog("AURIE_PURCHASE service=revenuecat testStore=%@",
              PurchaseConfiguration.isTestStore ? "YES" : "NO")
        return RevenueCatPurchaseService()
    }

    /// Credit any store transaction that completed but never reached the
    /// wallet — the narrow window where the app dies between the store
    /// finishing a purchase and our atomic save. The transaction-id ledger
    /// makes this a no-op in the normal case.
    func reconcilePurchases() async {
        guard purchases.isAvailable else { return }
        let grants = await purchases.unrecordedGrants()
        guard !grants.isEmpty else { return }
        let credited = wallet.reconcile(grants)
        if credited > 0 {
            NSLog("AURIE_PURCHASE reconciled %d hatch credits", credited)
        }
    }

    /// Home interactions fire on EVERY touch, so this collapses them to
    /// at most one model event per calendar day: if every task keyed to
    /// `.aurieInteracted` has already counted today (or is complete),
    /// there is nothing to record and we skip the cascade entirely.
    /// Without this guard every poke would re-run the state scan.
    func recordAurieInteraction(date: Date = Date()) {
        let dayKey = CalendarDay.key(for: date)
        let hasWorkToDo = CharmTaskCatalog.tasks(for: .aurieInteracted)
            .contains { def in
                guard !isCharmTaskCompleted(def) else { return false }
                return !(store.settings.charmTaskDayKeys[def.id] ?? [])
                    .contains(dayKey)
            }
        guard hasWorkToDo else { return }
        recordCharmTaskEvent(.aurieInteracted, date: date)
    }

    /// LAUNCH RETROACTIVE PASS: state tasks measure persisted facts,
    /// so a long-time player completes them on the first launch after
    /// the update — rewards queue and celebrate on Home, one at a time.
    func retroactiveCharmTaskPass() {
        var newly: [CharmTaskResult] = []
        runStateCascade(into: &newly)
        pendingTaskRewards.append(contentsOf: newly)
    }

    private func runStateCascade(into newly: inout [CharmTaskResult]) {
        var changed = true
        while changed {
            changed = false
            for def in CharmTaskCatalog.stateTasks
            where !isCharmTaskCompleted(def)
                && charmTaskProgress(def) >= def.target {
                let before = newly.count
                complete(def, into: &newly)
                if newly.count > before { changed = true }
            }
        }
    }

    private func complete(_ def: CharmTaskDefinition,
                          into newly: inout [CharmTaskResult]) {
        // A task whose reward is unassigned (art pulled, replacement
        // pending) cannot complete: completion IS the grant, so with
        // nothing to grant there is no ledger entry and no reward.
        guard let rewardID = def.rewardCharmID else { return }
        let ownedBefore = charms.isUnlocked(rewardID)
        guard charms.processGrant(CharmTaskCatalog.grantID(def),
                                  unlocking: rewardID)
        else { return }
        newly.append(CharmTaskResult(task: def, newlyCompleted: true,
                                     newlyUnlocked: !ownedBefore))
    }

    // MARK: Wonderbook

    /// Saved Sparks, newest first. Ids that no longer resolve after a content
    /// update are skipped rather than crashing.
    var wonderbook: [DailyLiftItem] {
        guard let pool = ContentService.daily else { return [] }
        return store.settings.savedWonderIDs.reversed().compactMap { pool.item(id: $0) }
    }

    func isInWonderbook(_ id: String) -> Bool {
        store.settings.savedWonderIDs.contains(id)
    }

    /// Idempotent — saving the same Spark twice never duplicates it.
    func saveToWonderbook(_ id: String) {
        guard !store.settings.savedWonderIDs.contains(id) else { return }
        store.settings.savedWonderIDs.append(id)
        // Charm-task seam: the Wonderbook genuinely grew.
        recordCharmTaskEvent(.wonderSaved)
    }

    func removeFromWonderbook(_ id: String) {
        store.settings.savedWonderIDs.removeAll { $0 == id }
    }
}
