#if DEBUG
import SwiftUI

/// Hidden demo/testing tools (§20) — DEBUG builds only, opened by
/// long-pressing the Home gear. For recording and testing; none of this
/// (especially rarity forcing) may ever ship to users.
struct DemoMenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var bindableModel = model
        NavigationStack {
            List {
                Section("Collection") {
                    Button("Seed 6 sample Auries") {
                        model.debugSeedSamples()
                    }
                    Button("Clear collection", role: .destructive) {
                        model.store.debugClearCollection()
                    }
                }
                Section("Next hatch") {
                    Picker("Force family", selection: $bindableModel.debugForcedFamily) {
                        Text("Off").tag(AuraFamily?.none)
                        ForEach(AuraFamily.allCases, id: \.self) { family in
                            Text(family.rawValue.capitalized).tag(AuraFamily?.some(family))
                        }
                    }
                }
                Section("Daily flags") {
                    Button("Reset greeting / intro / daily-lift flags") {
                        model.store.settings.lastGreetingDate = nil
                        model.store.settings.dailyLiftDismissedDate = nil
                        model.store.settings.hasSeenCalmIntro = false
                    }
                }
                // Contextual greetings (2026-09-27): inspect every input the
                // engine reads, flip them, and replay a greeting on the
                // live Home without relaunching.
                Section("Greetings") {
                    let st = model.store.settings
                    Text("""
                        hatched: \(st.hasHatchedFirstAurie)  arrivals: \(st.homeArrivalCount)
                        toyBox: \(st.hasOpenedToyBox)  calm: \(st.hasSeenCalmIntro)  shake: \(st.hasShakenPhone)
                        charms owned: \(model.charms.collection.unlockedCharmIDs.count)  collection opened: \(st.hasOpenedCharmCollection)
                        last arrival: \(st.lastGreetingDate.map { "\($0.formatted(date: .abbreviated, time: .shortened))" } ?? "never")
                        """)
                        .font(.caption.monospaced())
                    Button("Replay greeting now (re-arm)") {
                        HomeGreetingSession.shared.rearm()
                        dismiss()
                    }
                    Button("Mark ALL features discovered") {
                        model.store.settings.hasOpenedToyBox = true
                        model.store.settings.hasSeenCalmIntro = true
                        model.store.settings.hasOpenedCharmCollection = true
                        model.store.settings.hasShakenPhone = true
                    }
                    Button("Reset ALL discovery flags + arrival count") {
                        model.store.settings.hasOpenedToyBox = false
                        model.store.settings.hasSeenCalmIntro = false
                        model.store.settings.hasOpenedCharmCollection = false
                        model.store.settings.hasShakenPhone = false
                        model.store.settings.homeArrivalCount = 0
                    }
                    Button("Pretend last arrival was 8 days ago") {
                        model.store.settings.lastGreetingDate =
                            Calendar.current.date(byAdding: .day, value: -8, to: Date())
                    }
                    Button("Pretend last arrival was yesterday") {
                        model.store.settings.lastGreetingDate =
                            Calendar.current.date(byAdding: .day, value: -1, to: Date())
                    }
                    Button("Unlock one charm (8B state)") {
                        _ = model.charms.unlock("charm_food_apple_01")
                    }
                    Button("Wipe ALL charms (8A state)", role: .destructive) {
                        model.charms.debugResetAll()
                        model.pendingTaskRewards = []
                    }
                }
                Section("Hatch wallet") {
                    Text("Available: \(model.wallet.hatchesAvailable) (free \(model.wallet.wallet.freeHatchesToday) · ad \(model.wallet.wallet.rewardedHatchBalance) · paid \(model.wallet.wallet.paidHatchBalance))")
                        .font(.footnote)
                    // Same grant path as AURIE_HATCH_CREDITS, reachable
                    // without Xcode: for family iPads running a Debug build.
                    Button("Add 20 hatches") {
                        _ = model.wallet.apply(HatchGrant(
                            amount: 20, source: .debug,
                            transactionId: "debug-\(UUID().uuidString)"))
                    }
                    Button("Reset wallet to fresh first day") {
                        model.wallet.debugReset()
                    }
                    Button("Spend all free hatches (test refill)") {
                        while model.wallet.hatchesAvailable > 0 { model.wallet.consumeHatch() }
                    }
                }
            }
            .navigationTitle("Demo tools")
            .toolbar { Button("Close") { dismiss() } }
        }
    }
}
#endif
