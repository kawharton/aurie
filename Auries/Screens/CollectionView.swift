import SwiftUI

/// "My Auries" tab (mockup screen 6): count badge in the title row and a
/// two-column grid of family-tinted portrait tiles, crown on the featured
/// creature. Tap a tile for the full-screen view; press-and-hold for the
/// "Set as featured" popup.
struct CollectionView: View {
    @Environment(AppModel.self) private var model
    /// The pushed page, by id (`Aurie` is not Hashable; the id is).
    @State private var detailID: String?

    // Adaptive so iPhone gets ~2 columns and iPad portrait 4-5.
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 14)]

    var body: some View {
        // The detail is PUSHED inside this tab (2026-09-28), not presented as
        // a full-screen cover, so the regular tab bar stays on screen while
        // looking at an Aurie and the other tabs remain one tap away.
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: $detailID) { id in
                    if let aurie = model.store.auries.first(where: { $0.id == id }) {
                        CreatureDetailView(initial: aurie)
                    }
                }
        }
        // Widget deep link: fold the detail so Home is unobstructed.
        .onReceive(NotificationCenter.default.publisher(for: .auriesReturnHome)) { _ in
            detailID = nil
        }
        #if DEBUG
        // Capture aid: AURIE_OPEN_DETAIL=1 opens the first Aurie's page
        // shortly after the tab appears (simctl cannot tap a tile).
        .task {
            guard ProcessInfo.processInfo.environment["AURIE_OPEN_DETAIL"] == "1",
                  !CollectionDebugHooks.opened else { return }
            CollectionDebugHooks.opened = true
            try? await Task.sleep(for: .seconds(1.5))
            detailID = model.store.auries.first?.id
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if model.store.auries.isEmpty {
            VStack(spacing: 0) {
                titleRow
                ContentUnavailableView(
                    "No Auries yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Hatch your first creature from the Hatch tab.")
                )
            }
        } else {
            ScrollView {
                // Title scrolls with the grid (mockup screen 6).
                titleRow
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(model.store.auries) { aurie in
                        AurieTile(aurie: aurie,
                                  isFeatured: aurie.id == model.store.featured?.id)
                            .onTapGesture { detailID = aurie.id }
                            .contextMenu {   // press-and-hold: the small popup
                                Button {
                                    model.store.setFeatured(aurie)
                                } label: {
                                    Label("Set as featured", systemImage: "crown.fill")
                                }
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            // Rubber-band even when the collection fits on one screen (small
            // collections, iPad's wide grid) so the page never feels frozen.
            .scrollBounceBehavior(.always, axes: .vertical)
        }
    }

    private var titleRow: some View {
        HStack(spacing: 10) {
            Text("My Auries")
                .font(.title2.weight(.bold))
            Text("\(model.store.auries.count)")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .opacity(model.store.auries.isEmpty ? 0 : 1)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

#if DEBUG
private enum CollectionDebugHooks {
    static var opened = false
}
#endif

/// One grid tile: portrait on the creature's family tint, name below,
/// crown badge when featured.
private struct AurieTile: View {
    let aurie: Aurie
    let isFeatured: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(uiImage: AssetLoader.portrait(for: aurie))
                .resizable()
                .scaledToFit()
                .padding(6)
            Text(aurie.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color(aurie.auraColor, brightness: 0.45),
                         Color(aurie.auraColor, brightness: 0.22)],
                startPoint: .top, endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(alignment: .topLeading) {
            if isFeatured {
                Image(systemName: "crown.fill")
                    .font(.footnote)
                    .foregroundStyle(.yellow)
                    .padding(8)
            }
        }
    }
}
