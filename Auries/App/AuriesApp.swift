import SwiftUI

@main
struct AuriesApp: App {
    private let model: AppModel

    init() {
        ContentService.loadBundled()
        let model = AppModel()
        self.model = model
        // Sound effects follow the persisted Sound setting (mute toggle
        // arrives in Settings, phase 7 — the wiring is live now).
        SoundPlayer.isEnabled = { model.store.settings.soundOn }
        SoundPlayer.isCalmMusicEnabled = { model.store.settings.calmMusicOn }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["AURIE_TINT_SPIKE"] == "1" {
                TintSpikeView()          // Stage 0 experiment, debug-only
            } else if ProcessInfo.processInfo
                        .environment["AURIE_BATCH"] == "1" {
                BatchGridView()          // Stage 3 randomized QA grid
            } else {
                RootTabView().environment(model)
                    // Credit any store transaction that completed but never
                    // reached the wallet (app killed right after a purchase).
                    // The transaction-id ledger makes this a no-op normally.
                    .task {
                        await model.reconcilePurchases()
                        #if DEBUG
                        StoreRecoverySelftest.run()
                        await PurchaseQA.verifyPersisted(model: model)
                        await PurchaseQA.run(model: model)
                        #endif
                    }
            }
            #else
            RootTabView().environment(model)
                    // Credit any store transaction that completed but never
                    // reached the wallet (app killed right after a purchase).
                    // The transaction-id ledger makes this a no-op normally.
                    .task {
                        await model.reconcilePurchases()
                        #if DEBUG
                        StoreRecoverySelftest.run()
                        await PurchaseQA.verifyPersisted(model: model)
                        await PurchaseQA.run(model: model)
                        #endif
                    }
            #endif
        }
    }
}
