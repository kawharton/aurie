// Standalone charm model / compatibility / render-resolution tests.
// Run: Tools/charm-tests/run.sh  (compiles the REAL model sources,
// no simulator or Xcode project needed). Keep OUTSIDE Auries/ so the
// app's synchronized file group never compiles this main into the app.
import Foundation
var pass=0, fail=0
func check(_ name:String,_ ok:Bool){ if ok {pass+=1} else {fail+=1; print("FAIL \(name)")} }
let dec=JSONDecoder(), enc=JSONEncoder()
// 1. legacy slotless record resolves from catalog placements
let w1=try! dec.decode(EquippedCharm.self,from:Data(#"{"charmID":"charm_object_backpack_01","glow":true}"#.utf8))
check("slotless backpack -> back", w1.slot=="back")
// 2. slotless BELLY sticker resolves to belly
let w2=try! dec.decode(EquippedCharm.self,from:Data(#"{"charmID":"charm_food_apple_01"}"#.utf8))
check("slotless apple -> belly", w2.slot=="belly")
// 3. unknown/removed charm id decodes harmlessly
let w3=try! dec.decode(EquippedCharm.self,from:Data(#"{"charmID":"charm_removed_someday_99"}"#.utf8))
check("unknown id decodes, falls back", w3.slot=="back")
check("unknown id has no definition", AurieCharmCatalog.definition("charm_removed_someday_99")==nil)
// 4. future placement string round-trips untouched
let w4=EquippedCharm(charmID:"x",slot:"floating",side:"left")
let w5=try! dec.decode(EquippedCharm.self,from:enc.encode(w4))
check("future slot string round-trips", w5==w4 && w5.slot=="floating")
// 5. explicit slot wins over catalog
let w6=try! dec.decode(EquippedCharm.self,from:Data(#"{"charmID":"charm_food_apple_01","slot":"back"}"#.utf8))
check("explicit slot preserved", w6.slot=="back")
// 6. CharmCollection: empty + future-shaped files decode
let c1=try! dec.decode(CharmCollection.self,from:Data("{}".utf8))
let c2=try! dec.decode(CharmCollection.self,from:Data(#"{"unlockedCharmIDs":["a"],"futureField":3}"#.utf8))
check("empty charms.json decodes", c1.unlockedCharmIDs.isEmpty)
check("future charms.json decodes", c2.unlockedCharmIDs==["a"])
// 7. catalog invariants
check("35 definitions", AurieCharmCatalog.all.count==35)   // 37 - Pink Shoe (2026-09-20) - Clownfish (2026-09-25)
check("pink shoe fully removed from the catalog",
      AurieCharmCatalog.definition("charm_fashion_shoe_01") == nil)
// Editorial visibility only (2026-09-20): these five have no acquisition
// path yet, so players must not browse them as locked-but-unreachable.
// Ids, art and placements are intact so they can be granted later.
check("unobtainable charms hidden from launch",
      ["charm_toy_basketball_01", "charm_nature_rain_cloud_01",
       "charm_science_flask_01", "charm_music_trumpet_01",
       "charm_object_chair_01", "charm_food_orange_01"].allSatisfy {
          guard let d = AurieCharmCatalog.definition($0) else { return false }
          return d.launch == false && !d.placements.isEmpty
      })
// Aura pool moves preserved identity; floating pool + pizza/pumpkin
// held out EDITORIALLY (launch=false) — never a render gate.
check("tomato now renders at aura, not belly",
      AurieCharmCatalog.equippedCharmID(
          in: [EquippedCharm(charmID: "charm_food_tomato_01", slot: "aura")],
          placement: "aura") == "charm_food_tomato_01"
      && AurieCharmCatalog.equippedCharmID(
          in: [EquippedCharm(charmID: "charm_food_tomato_01", slot: "belly")],
          placement: "belly") == nil)
check("held-out book still RENDERS if equipped (launch is editorial)",
      AurieCharmCatalog.equippedCharmID(
          in: [EquippedCharm(charmID: "charm_object_book_01", slot: "floating")],
          placement: "floating") == "charm_object_book_01")
// Aura/floating placements resolve through the same central resolver
// and the same one-per-placement rule.
check("aura charm renders at aura",
      AurieCharmCatalog.equippedCharmID(
          in: [EquippedCharm(charmID: "charm_magic_crystal_02", slot: "aura")],
          placement: "aura") == "charm_magic_crystal_02")
check("floating charm renders at floating",
      AurieCharmCatalog.equippedCharmID(
          in: [EquippedCharm(charmID: "charm_object_book_01", slot: "floating")],
          placement: "floating") == "charm_object_book_01")
check("repurposed crystal no longer renders at belly",
      AurieCharmCatalog.equippedCharmID(
          in: [EquippedCharm(charmID: "charm_magic_crystal_02", slot: "belly")],
          placement: "belly") == nil)
check("four placements coexist under the one equip rule", {
    var records: [EquippedCharm] = []
    for (id, slot) in [("charm_food_orange_01", "belly"),
                       ("charm_object_backpack_01", "back"),
                       ("charm_magic_crystal_02", "aura"),
                       ("charm_object_book_01", "floating")] {
        records = AurieCharmCatalog.equipping(records, with: id, at: slot)
    }
    // A second aura replaces ONLY the aura.
    records = AurieCharmCatalog.equipping(
        records, with: "charm_nature_snowflake_01", at: "aura")
    return records.count == 4
        && AurieCharmCatalog.equippedCharmID(in: records, placement: "belly")
            == "charm_food_orange_01"
        && AurieCharmCatalog.equippedCharmID(in: records, placement: "aura")
            == "charm_nature_snowflake_01"
        && AurieCharmCatalog.equippedCharmID(in: records, placement: "floating")
            == "charm_object_book_01"
}())
let apple=AurieCharmCatalog.definition("charm_food_apple_01")!
check("apple categories", apple.categories==["food","fruit_vegetables","nature"])
check("apple placement belly", apple.placements==["belly"] && apple.primaryPlacement=="belly")
check("apple acquisition birthPhoto", apple.acquisitionSources==["birthPhoto"])
check("apple birth trigger ref", apple.birthTriggerIDs==["birth_apple"])
check("every charm has placements", AurieCharmCatalog.all.allSatisfy{ !$0.placements.isEmpty })
let bp=AurieCharmCatalog.definition("charm_object_backpack_01")!
check("backpack placement back", bp.primaryPlacement=="back")
// 8. trigger table cross-refs
for t in AurieCharmCatalog.birthTriggers {
    check("trigger \(t.id) unlock exists", AurieCharmCatalog.definition(t.unlockCharmID) != nil)
    check("trigger \(t.id) back-ref", AurieCharmCatalog.definition(t.unlockCharmID)!.birthTriggerIDs.contains(t.id))
}
// 9. taxonomy display names + unknown-id fallback
check("category name", CharmTaxonomy.categoryName("fruit_vegetables")=="Fruit & Veg")
check("placement name", CharmTaxonomy.placementName("belly")=="Belly")
check("source name", CharmTaxonomy.acquisitionSourceName("environmentDiscovery")=="Found in the World")
check("unknown category humanised", CharmTaxonomy.categoryName("future_thing")=="Future Thing")
// 10. RENDER RESOLUTION — launch must NOT gate rendering.
// A future seasonal/discovery charm ships launch=false and must still
// resolve for rendering once equipped; launch is editorial metadata.
let futureDef = CharmDefinition(
    id: "charm_future_shell_01", displayName: "Shell",
    categories: ["ocean"], placements: ["belly"],
    acquisitionSources: ["environmentDiscovery"], birthTriggerIDs: [],
    launch: false)
let futureLookup: (String) -> CharmDefinition? = {
    $0 == futureDef.id ? futureDef : AurieCharmCatalog.definition($0)
}
let wornFuture = [EquippedCharm(charmID: "charm_future_shell_01", slot: "belly")]
check("launch=false charm resolves for render",
      AurieCharmCatalog.equippedCharmID(in: wornFuture, placement: "belly",
                                        definitions: futureLookup)
          == "charm_future_shell_01")
// valid launch charm still resolves normally
let wornApple = [EquippedCharm(charmID: "charm_food_apple_01", slot: "belly")]
check("launch charm resolves normally",
      AurieCharmCatalog.equippedCharmID(in: wornApple, placement: "belly")
          == "charm_food_apple_01")
// unknown id: no render, no crash
let wornGone = [EquippedCharm(charmID: "charm_removed_someday_99", slot: "belly")]
check("unknown id resolves to nothing",
      AurieCharmCatalog.equippedCharmID(in: wornGone, placement: "belly") == nil)
// wrong placement (backpack equipped at belly): definition doesn't support it
let wornWrong = [EquippedCharm(charmID: "charm_object_backpack_01", slot: "belly")]
check("unsupported placement resolves to nothing",
      AurieCharmCatalog.equippedCharmID(in: wornWrong, placement: "belly") == nil)
// record slot mismatch: apple equipped at back never renders at belly
let wornOther = [EquippedCharm(charmID: "charm_food_apple_01", slot: "back")]
check("other-slot record not picked for belly",
      AurieCharmCatalog.equippedCharmID(in: wornOther, placement: "belly") == nil)
// ---- Birth Charms (Phase D) ----
// Trigger matching is CANONICAL-label exact: only the hero label the
// recognition pipeline actually produces may fire, and only its ONE charm.
check("canonical apple matches birth_apple",
      AurieCharmCatalog.birthTrigger(forCanonicalLabel: "apple")?
          .unlockCharmID == "charm_food_apple_01")
check("raw Vision variant does not match",
      AurieCharmCatalog.birthTrigger(forCanonicalLabel: "granny smith") == nil)
check("guessed legacy label does not match",
      AurieCharmCatalog.birthTrigger(forCanonicalLabel: "green apple") == nil)
check("untriggered hero label earns nothing",   // mug triggers since D2
      AurieCharmCatalog.birthTrigger(forCanonicalLabel: "banana") == nil)
// D2 round 2: six word heroes + the "beach ball" phrase hero.
for (label, charm) in [("strawberry", "charm_food_strawberry_01"),
                       ("lemon", "charm_food_lemon_01"),
                       ("carrot", "charm_food_carrot_01"),
                       ("cookie", "charm_food_cookie_01"),
                       ("cake", "charm_food_cake_01"),
                       ("balloon", "charm_toy_balloon_01"),
                       ("beach ball", "charm_toy_beach_ball_01")] {
    check("trigger \(label)",
          AurieCharmCatalog.birthTrigger(forCanonicalLabel: label)?
              .unlockCharmID == charm)
}
check("orange has NO trigger (launch decision)",
      AurieCharmCatalog.birthTrigger(forCanonicalLabel: "orange") == nil)
check("raw 'ball' label has NO trigger",
      AurieCharmCatalog.birthTrigger(forCanonicalLabel: "ball") == nil)
check("nil label earns nothing",
      AurieCharmCatalog.birthTrigger(forCanonicalLabel: nil) == nil)
// Injectable trigger table: first match wins, one charm each.
let t1 = BirthCharmTrigger(id: "t1", acceptedRecognitionLabels: ["shell"],
                           unlockCharmID: "a")
let t2 = BirthCharmTrigger(id: "t2", acceptedRecognitionLabels: ["shell"],
                           unlockCharmID: "b")
check("first matching trigger wins",
      AurieCharmCatalog.birthTrigger(forCanonicalLabel: "shell",
                                     triggers: [t1, t2])?.unlockCharmID == "a")
// D2 wiring: the three new stable-hero triggers, each to ONE charm.
check("teddy trigger", AurieCharmCatalog.birthTrigger(forCanonicalLabel: "teddy")?
    .unlockCharmID == "charm_toy_teddy_01")
check("mug trigger", AurieCharmCatalog.birthTrigger(forCanonicalLabel: "mug")?
    .unlockCharmID == "charm_object_mug_01")
check("cup trigger -> teacup charm",
      AurieCharmCatalog.birthTrigger(forCanonicalLabel: "cup")?
    .unlockCharmID == "charm_object_teacup_01")
check("untriggered hero flower earns nothing",
      AurieCharmCatalog.birthTrigger(forCanonicalLabel: "flower") == nil)
// New 2D belly charms resolve slotless records to belly.
let w2d = try! dec.decode(EquippedCharm.self,
    from: Data(#"{"charmID":"charm_food_cookie_01"}"#.utf8))
check("slotless cookie -> belly", w2d.slot == "belly")
check("new charm renders at belly",
      AurieCharmCatalog.equippedCharmID(
          in: [EquippedCharm(charmID: "charm_toy_teddy_01", slot: "belly")],
          placement: "belly") == "charm_toy_teddy_01")
// Grant ledger: one event rewards once; a replay must return false and
// change nothing; a NEW event for an owned charm is still a real event.
let svc = CharmService(directory: nil)
check("new grant processes", svc.processGrant("birth:A", unlocking: "apple"))
check("grant unlocked the charm", svc.isUnlocked("apple"))
check("replayed grant refuses", !svc.processGrant("birth:A", unlocking: "apple"))
check("replay left one ledger entry",
      svc.collection.processedGrantIds == ["birth:A"])
check("new event for owned charm processes",
      svc.processGrant("birth:B", unlocking: "apple"))
check("ownership stays a set", svc.collection.unlockedCharmIDs == ["apple"])
// ---- Charm tasks (Phase E, launch set) ----
check("nine launch tasks", CharmTaskCatalog.all.count == 9)
check("unique task ids",
      Set(CharmTaskCatalog.all.map(\.id)).count == 9)
check("unique grant ids",
      Set(CharmTaskCatalog.all.map(CharmTaskCatalog.grantID)).count == 9)
// Pink Shoe was DELETED from the catalog 2026-09-20 (no users yet, so no
// save compatibility was owed) and its task, Try a New Look, was
// WITHDRAWN FROM LAUNCH 2026-09-25 rather than given someone else's
// charm. So every remaining task awards, and none may inherit Pink Shoe.
let assigned = CharmTaskCatalog.all.compactMap(\.rewardCharmID)
check("every launch task awards a charm", assigned.count == 9)
check("no reward-less task ships",
      CharmTaskCatalog.all.allSatisfy { $0.rewardCharmID != nil })
check("try_new_look is gone from the catalog",
      !CharmTaskCatalog.all.contains { $0.id == "try_new_look" })
check("rewarded helper matches", CharmTaskCatalog.rewarded.count == 9)
check("no task rewards the deleted Pink Shoe",
      !assigned.contains("charm_fashion_shoe_01"))
check("every task reward is a launch charm",
      assigned.allSatisfy {
          AurieCharmCatalog.definition($0)?.launch == true })
check("unique rewards (one acquisition path each)",
      Set(assigned).count == assigned.count)
check("every assigned reward resolves in the catalog",
      assigned.allSatisfy { AurieCharmCatalog.definition($0) != nil })
check("no task reward is a Birth Charm",
      assigned.allSatisfy { id in
          AurieCharmCatalog.birthTriggers.allSatisfy {
              $0.unlockCharmID != id } })
// Aura rewards keep aura placement; sticker rewards keep belly.
let auraRewards = ["charm_magic_star_01", "charm_magic_crystal_02",
                   "charm_nature_flower_03", "charm_nature_snowflake_01"]
check("aura rewards are aura charms", auraRewards.allSatisfy {
    AurieCharmCatalog.definition($0)?.placements == ["aura"] })
check("badge/sticker rewards are belly charms",
      assigned.filter { !auraRewards.contains($0) }
          .allSatisfy {
              AurieCharmCatalog.definition($0)?.placements == ["belly"] })
check("friendship reward is the hearts, not a badge",
      CharmTaskCatalog.all.first { $0.id == "make_friends" }?
          .rewardCharmID == "charm_friendship_hearts_01")
// Daily Wonders + Wonderbook were WITHDRAWN from launch 2026-09-20.
// The four tasks are gone; their reward charms survive, unassigned.
check("no Wonder task remains in the launch catalog",
      ["five_daily_wonders", "wonder_to_keep", "wonder_collector",
       "month_of_wonders"].allSatisfy { id in
          !CharmTaskCatalog.all.contains { $0.id == id } })
check("no launch task consumes Wonder events",
      CharmTaskCatalog.tasks(for: .wonderRevealed).isEmpty
      && CharmTaskCatalog.tasks(for: .wonderSaved).isEmpty)
// The Star and Crystal auras were REASSIGNED to the two new
// non-Wonder tasks (2026-09-20); the two badges were hidden instead.
check("star aura now rewards A Full House",
      CharmTaskCatalog.all.first { $0.id == "full_house" }?
          .rewardCharmID == "charm_magic_star_01")
check("crystal aura now rewards Old Friends",
      CharmTaskCatalog.all.first { $0.id == "old_friends" }?
          .rewardCharmID == "charm_magic_crystal_02")
check("A Full House needs ten Auries",
      CharmTaskCatalog.all.first { $0.id == "full_house" }?.target == 10)
check("Old Friends needs thirty distinct days",
      CharmTaskCatalog.all.first { $0.id == "old_friends" }?.target == 30)
check("Old Friends rides the interaction seam",
      CharmTaskCatalog.tasks(for: .aurieInteracted).map(\.id) == ["old_friends"])
let hiddenBadges = ["charm_badge_spark_01", "charm_badge_wonderbook_01"]
check("orphaned Wonder badges still exist in the catalog",
      hiddenBadges.allSatisfy { AurieCharmCatalog.definition($0) != nil })
check("orphaned Wonder badges are unassigned",
      hiddenBadges.allSatisfy { !assigned.contains($0) })
check("orphaned Wonder badges are hidden from launch",
      hiddenBadges.allSatisfy {
          AurieCharmCatalog.definition($0)?.launch == false })
// Completion is the LEDGER, never ownership.
// A live launch task, used for the ledger/idempotency contract.
let ledgerTask = CharmTaskCatalog.rewarded[0]
check("ledger entry means completed",
      CharmTaskCatalog.isCompleted(ledgerTask,
          processedGrantIds: [CharmTaskCatalog.grantID(ledgerTask)]))
check("ownership alone is not completion",
      !CharmTaskCatalog.isCompleted(ledgerTask,
          processedGrantIds: ["birth:x", "unrelated"]))
// Grant-path idempotency for a task reward (same CharmService
// contract Birth Charms use).
let taskSvc = CharmService(directory: nil)
taskSvc.unlock(ledgerTask.rewardCharmID!)   // owned from "another source"
check("owned reward still leaves task incomplete",
      !CharmTaskCatalog.isCompleted(ledgerTask,
          processedGrantIds: taskSvc.collection.processedGrantIds))
check("task grant processes once",
      taskSvc.processGrant(CharmTaskCatalog.grantID(ledgerTask),
                           unlocking: ledgerTask.rewardCharmID!))
check("task grant refuses replay",
      !taskSvc.processGrant(CharmTaskCatalog.grantID(ledgerTask),
                            unlocking: ledgerTask.rewardCharmID!))
check("no duplicate ownership",
      taskSvc.collection.unlockedCharmIDs
          .filter { $0 == ledgerTask.rewardCharmID! }.count == 1)
check("retired task:first_wonder id completes nothing",
      !CharmTaskCatalog.isCompleted(ledgerTask,
          processedGrantIds: ["task:first_wonder"]))
// LAUNCH INVARIANT (2026-09-20): every charm a player can BROWSE must
// have a real way to get it — a birth trigger or a task reward.
// Orange stays hidden because "orange" is also a colour word and a
// hero label for it would false-positive (Recognition.swift).
let taskRewardIDs = Set(CharmTaskCatalog.all.compactMap(\.rewardCharmID))
// Mirrors CharmsView.supportedPlacements (that file is a screen and is
// deliberately not compiled into this model-only harness).
let supported: Set<String> = ["belly", "back", "aura"]
let browsableCharms = AurieCharmCatalog.all.filter { def in
    def.launch && def.placements.contains(where: supported.contains)
}
let deadEnds = browsableCharms.filter { def in
    def.birthTriggerIDs.isEmpty && !taskRewardIDs.contains(def.id)
}
check("every browsable charm is obtainable", deadEnds.isEmpty)
check("backpack is a birth charm", !(AurieCharmCatalog
    .definition("charm_object_backpack_01")?.birthTriggerIDs.isEmpty ?? true))
check("tomato is a birth charm", !(AurieCharmCatalog
    .definition("charm_food_tomato_01")?.birthTriggerIDs.isEmpty ?? true))
check("orange stays hidden (colour-word false positives)",
      AurieCharmCatalog.definition("charm_food_orange_01")?.launch == false)


// ============================================================
// HATCH WALLET — exactly-once purchase credit (RevenueCat, 2026-09-20)
// ============================================================
// In-memory wallet (directory: nil) so nothing touches disk.
func freshWallet() -> WalletService { WalletService(directory: nil) }

// Free-hatch rules must be untouched by the purchase work.
let wal0 = freshWallet()
check("first day grants 5 free hatches", wal0.wallet.freeHatchesToday == 5)
check("free per day is 1", WalletService.freePerDay == 1)
check("first-day allowance constant is 5", WalletService.freeFirstDay == 5)

// A grant with NO transaction id must be REFUSED, not credited under a
// random id. This was the double-credit hole.
let wal1 = freshWallet()
check("nil transaction id is refused",
      wal1.apply(HatchGrant(amount: 5, source: .purchase, transactionId: nil)) == false
      && wal1.wallet.paidHatchBalance == 0)
check("empty transaction id is refused",
      wal1.apply(HatchGrant(amount: 5, source: .purchase, transactionId: "  ")) == false
      && wal1.wallet.paidHatchBalance == 0)

// Exactly-once across repeated delivery of the SAME transaction.
let wal2 = freshWallet()
let txn = HatchGrant(amount: 5, source: .purchase, transactionId: "txn_A")
check("first delivery credits", wal2.apply(txn) == true && wal2.wallet.paidHatchBalance == 5)
check("replay credits nothing", wal2.apply(txn) == false && wal2.wallet.paidHatchBalance == 5)
check("reconcile replay credits nothing",
      wal2.reconcile([txn, txn, txn]) == 0 && wal2.wallet.paidHatchBalance == 5)

// Distinct legitimate purchases accumulate.
let wal3 = freshWallet()
_ = wal3.apply(HatchGrant(amount: 5,  source: .purchase, transactionId: "t1"))
_ = wal3.apply(HatchGrant(amount: 10, source: .purchase, transactionId: "t2"))
_ = wal3.apply(HatchGrant(amount: 20, source: .purchase, transactionId: "t3"))
check("distinct purchases accumulate to 35", wal3.wallet.paidHatchBalance == 35)
check("ledger holds one entry per transaction",
      wal3.wallet.processedGrantIds == ["t1", "t2", "t3"])

// Reconciliation credits only what is missing.
let wal4 = freshWallet()
_ = wal4.apply(HatchGrant(amount: 5, source: .purchase, transactionId: "seen"))
let credited = wal4.reconcile([
    HatchGrant(amount: 5,  source: .purchase, transactionId: "seen"),    // already
    HatchGrant(amount: 10, source: .purchase, transactionId: "missed"),  // lost credit
])
check("reconcile credits only the missing transaction",
      credited == 10 && wal4.wallet.paidHatchBalance == 15)

// Paid vs rewarded stay in separate buckets; spend order free -> rewarded -> paid.
let wal5 = freshWallet()
_ = wal5.apply(HatchGrant(amount: 2, source: .rewardedAd, transactionId: "ad1"))
_ = wal5.apply(HatchGrant(amount: 3, source: .purchase,  transactionId: "buy1"))
check("rewarded and paid balances are separate",
      wal5.wallet.rewardedHatchBalance == 2 && wal5.wallet.paidHatchBalance == 3)
check("available = free + rewarded + paid", wal5.hatchesAvailable == 5 + 2 + 3)
for _ in 1...5 { wal5.consumeHatch() }          // burns the 5 free first
check("free spent before rewarded/paid",
      wal5.wallet.freeHatchesToday == 0
      && wal5.wallet.rewardedHatchBalance == 2
      && wal5.wallet.paidHatchBalance == 3)
wal5.consumeHatch(); wal5.consumeHatch()          // then rewarded
check("rewarded spent before paid",
      wal5.wallet.rewardedHatchBalance == 0 && wal5.wallet.paidHatchBalance == 3)
wal5.consumeHatch()
check("paid spent last", wal5.wallet.paidHatchBalance == 2)

// Buying must not disturb the daily free reset.
let cal = Calendar.current
let day1 = Date(timeIntervalSince1970: 1_600_000_000)
let wal6 = WalletService(directory: nil, calendar: cal, now: day1)
_ = wal6.apply(HatchGrant(amount: 20, source: .purchase, transactionId: "big"))
let day2 = cal.date(byAdding: .day, value: 1, to: day1)!
wal6.refreshDaily(now: day2)
check("daily reset gives 1 free, not the first-day 5", wal6.wallet.freeHatchesToday == 1)
check("daily reset does not touch purchased hatches", wal6.wallet.paidHatchBalance == 20)
let day5 = cal.date(byAdding: .day, value: 4, to: day1)!
wal6.refreshDaily(now: day5)
check("free hatches do NOT accumulate across skipped days",
      wal6.wallet.freeHatchesToday == 1)


// ============================================================
// AURIES.JSON RESILIENCE (2026-09-21) — one bad record must never
// destroy the collection, and an unreadable file must never be
// silently reported as "empty" and written back.
// ============================================================
func aurieJSON(id: String, extra: String = "", omit: Set<String> = [],
               bad: [String: String] = [:]) -> String {
    var f: [String: String] = [
        "id": "\"\(id)\"", "name": "\"Test\(id)\"", "family": "\"moss\"",
        "body": "\"round\"", "category": "\"food\"", "bornFrom": "\"apple\"",
        "parts": "{\"bodyId\":1,\"eyesId\":1,\"mouthId\":1,\"limbsId\":1}",
        "slots": "{}",
        "baseColor": "{\"r\":10,\"g\":20,\"b\":30}",
        "auraColor": "{\"r\":40,\"g\":50,\"b\":60}",
        "line": "\"hello\"", "traits": "[]",
        "hatchedAt": "0", "seed": "12345",
    ]
    for (k, v) in bad { f[k] = v }
    for k in omit { f.removeValue(forKey: k) }
    let body = f.map { "\"\($0.key)\": \($0.value)" }.joined(separator: ",")
    return "{\(body)\(extra.isEmpty ? "" : "," + extra)}"
}
func decodeAuries(_ json: String) -> AurieCollectionCodec.Outcome {
    AurieCollectionCodec.decode(Data(json.utf8))
}

// Baseline: a clean two-record file.
let okOutcome = decodeAuries("[\(aurieJSON(id: "a")),\(aurieJSON(id: "b"))]")
check("clean file decodes every record",
      okOutcome.auries.count == 2 && okOutcome.dropped == 0
      && !okOutcome.fileUnreadable)

// MODE 1 — MISSING NEW/OPTIONAL FIELD: decodes fine, nothing dropped.
// (Every post-v1 Aurie field is Optional by design.)
let missingField = decodeAuries("[\(aurieJSON(id: "a"))]")
check("missing optional fields decode safely",
      missingField.auries.count == 1 && missingField.dropped == 0
      && !missingField.fileUnreadable)

// MODE 2 — MALFORMED SINGLE AURIE: that record is skipped, the others live.
// Here record 2 is missing the REQUIRED `seed`.
let oneBad = decodeAuries("[\(aurieJSON(id: "a")),"
                          + "\(aurieJSON(id: "b", omit: ["seed"])),"
                          + "\(aurieJSON(id: "c"))]")
check("one malformed Aurie is skipped, the rest survive",
      oneBad.auries.count == 2 && oneBad.dropped == 1
      && !oneBad.fileUnreadable)
check("survivors are the RIGHT records",
      oneBad.auries.map(\.id) == ["a", "c"])

// MODE 3 — UNKNOWN/INVALID ENUM VALUE: same treatment, not a wipe.
// `body` is APPEND-ONLY, so a newer build's value must not erase saves.
let futureEnum = decodeAuries("[\(aurieJSON(id: "a")),"
                              + "\(aurieJSON(id: "future", bad: ["body": "\"hexagon_2027\""]))]")
check("unknown enum raw value drops only that record",
      futureEnum.auries.count == 1 && futureEnum.auries.first?.id == "a"
      && futureEnum.dropped == 1 && !futureEnum.fileUnreadable)

// A malformed nested equippedCharms entry is also just one record.
let badEquip = decodeAuries("[\(aurieJSON(id: "a")),"
    + "\(aurieJSON(id: "wonky", extra: "\"equippedCharms\": [{\"slot\":\"belly\"}]"))]")
check("malformed equippedCharms drops only that record",
      badEquip.auries.count == 1 && badEquip.dropped == 1
      && !badEquip.fileUnreadable)

// MODE 4 — COMPLETELY MALFORMED JSON: UNREADABLE, never "empty".
for (name, junk) in [("truncated", "[{\"id\":\"a\""),
                     ("garbage", "not json at all"),
                     ("wrong shape", "{\"auries\":[]}")] {
    let o = decodeAuries(junk)
    check("totally malformed JSON (\(name)) reports UNREADABLE, not empty",
          o.fileUnreadable && o.auries.isEmpty)
}
// An intentionally EMPTY collection is readable and NOT flagged — the
// distinction the write guard depends on.
let emptyFile = decodeAuries("[]")
check("a genuinely empty array is readable, not flagged unreadable",
      emptyFile.auries.isEmpty && !emptyFile.fileUnreadable
      && emptyFile.dropped == 0)

print("\(pass) passed, \(fail) failed")
exit(fail==0 ? 0 : 1)
