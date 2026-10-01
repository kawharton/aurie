import SwiftUI

/// The refill sheet (§6/§11) — shown when a capture is attempted with no
/// hatches left. Consumable-only: a pack, one rewarded-ad hatch, or
/// come-back-tomorrow. No unlimited, no subscription, no pressure.
struct RefillSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var watchingAd = false
    #if DEBUG
    @State private var autoPacks = false   // AURIE_SHOW_REFILL=packs
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(.yellow)
                    .padding(.top, 26)
                Text("More eggs are waiting.")
                    .font(.title2.weight(.bold))
                Text("Today's free hatches are used up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if model.purchases.isAvailable {
                    NavigationLink {
                        HatchPackView()
                    } label: {
                        Text("Buy a hatch pack")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }

                // Shown ONLY when a real rewarded-ad network is wired.
                // Without one this offered a free hatch for an ad that never
                // played, with no cap — an unlimited-hatch exploit and
                // misleading UI. `supportsRewardedAds` is false today.
                if model.purchases.supportsRewardedAds {
                    Button {
                        watchAd()
                    } label: {
                        HStack {
                            if watchingAd { ProgressView().padding(.trailing, 4) }
                            Text(watchingAd ? "Playing ad…" : "Watch an ad for 1 more hatch")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(watchingAd)
                    .padding(.horizontal, 24)
                }

                Text("Or come back tomorrow for a free hatch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            #if DEBUG
            .navigationDestination(isPresented: $autoPacks) { HatchPackView() }
            .task {
                guard ProcessInfo.processInfo.environment["AURIE_SHOW_REFILL"] == "packs" else { return }
                try? await Task.sleep(for: .seconds(0.8))
                autoPacks = true
            }
            #endif
        }
        .presentationDetents([.medium, .large])
    }

    private func watchAd() {
        watchingAd = true
        Task {
            // Stub rewarded ad (§10): grants one hatch locally.
            // TODO: RevenueCat/ad-network integration in phase 9.
            if let grant = try? await model.purchases.grantRewardedAdHatch() {
                model.wallet.apply(grant)
            }
            watchingAd = false
            dismiss()
        }
    }
}

/// The hatch-pack screen (§6): three full-width, centered options.
struct HatchPackView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var products: [HatchProduct] = []
    @State private var loading = true
    @State private var unavailable = false
    @State private var purchasing: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 14) {
            Text("Hatch packs")
                .font(.title2.weight(.bold))
                .padding(.top, 20)
            Text("More hatches, more magic.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if loading {
                ProgressView().padding(.top, 24)
            } else if unavailable {
                // Missing key, missing offering, or a missing package —
                // a quiet dead end, never a crash and never a fake price.
                VStack(spacing: 8) {
                    Text("Hatch packs aren’t available right now.")
                        .font(.subheadline.weight(.semibold))
                    Text("Please try again later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
            } else {
                ForEach(products) { product in
                    Button {
                        buy(product)
                    } label: {
                        VStack(spacing: 3) {
                            if product.bestValue {
                                Text("BEST VALUE")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.yellow)
                            }
                            // Quantity is app-defined; the PRICE is the
                            // store's localized string, never hardcoded.
                            Text("Buy \(product.amount) hatches — \(product.displayPrice)")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(product.bestValue ? .indigo : .secondary.opacity(0.35))
                    // Guards every pack while any transaction is in flight,
                    // so repeated taps cannot overlap purchases.
                    .disabled(purchasing != nil)
                    .overlay {
                        if purchasing == product.id { ProgressView() }
                    }
                }
                .padding(.horizontal, 24)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }

            // Consumables: there is no entitlement to restore, and a spent
            // balance cannot be recovered by the store. Say so plainly
            // instead of shipping a misleading Restore button.
            Text("Hatch packs are used on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Spacer()
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        do {
            products = try await model.purchases.loadHatchProducts()
            unavailable = products.isEmpty
        } catch {
            products = []
            unavailable = true
        }
        loading = false
    }

    private func buy(_ product: HatchProduct) {
        guard purchasing == nil else { return }
        purchasing = product.id
        errorMessage = nil
        Task {
            defer { purchasing = nil }
            do {
                let grant = try await model.purchases.purchaseHatchPack(product)
                // CREDIT AND PERSIST FIRST. `apply` writes the ledger entry
                // and the balance in one atomic save, so the hatches are on
                // disk before this flow reports success or dismisses.
                model.wallet.apply(grant)
                dismiss()
            } catch PurchaseError.cancelled {
                // Normal user cancellation: credit nothing, say nothing.
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "That didn’t go through. You can try again."
            }
        }
    }
}
