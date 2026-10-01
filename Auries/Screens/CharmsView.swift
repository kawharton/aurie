import SwiftUI

/// The dedicated CHARMS page (phase C; visual redesign 2026-09-17).
///
/// Page hierarchy, top to bottom: HEADER (title + count, featured-Aurie
/// chip) → PLACEMENT segmented control (the primary browse dimension)
/// → ONE quiet category control (opens a bottom-sheet picker; no pill
/// strip — a strip would sprawl as the catalog grows) → the charm grid.
///
/// Both filters derive from the generated `CharmDefinition` facets and
/// combine with AND; the view owns no taxonomy. Ownership is
/// account-level (`CharmService`); equips persist on the featured
/// Aurie's `equippedCharms` through the existing `Store.update` seam.
struct CharmsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if DEBUG
    // Capture aids in the app's established style (AURIE_START_TAB…).
    @State private var showEarnCharms = ProcessInfo.processInfo
        .environment["AURIE_SHOW_TASKS"] == "1"
    @State private var placementFilter: String? = ProcessInfo.processInfo
        .environment["AURIE_CHARMS_PLACEMENT"]
    @State private var selectedCategories: Set<String> = Set(
        (ProcessInfo.processInfo.environment["AURIE_CHARMS_CATEGORY"] ?? "")
            .split(separator: ",").map(String.init))
    @State private var detailTarget: CharmDefinition? = ProcessInfo
        .processInfo.environment["AURIE_CHARMS_DETAIL"]
        .flatMap(AurieCharmCatalog.definition)
    @State private var showCategoryPicker = ProcessInfo.processInfo
        .environment["AURIE_CHARMS_PICKER"] == "1"
    #else
    @State private var showEarnCharms = false
    @State private var placementFilter: String? = nil     // nil = All
    @State private var selectedCategories: Set<String> = []   // empty = All
    @State private var detailTarget: CharmDefinition?
    @State private var showCategoryPicker = false
    #endif

    /// Placements with real, shipped product content. Head, wrist, aura…
    /// join this list only when their art pipelines exist.
    // Floating is PAUSED (held for a later personality-trait system):
    // the slot stays dormant in the model, but it is not a user-facing
    // placement, filter, or equip target for launch.
    static let supportedPlacements = [CharmSlot.belly.rawValue,
                                     CharmSlot.back.rawValue,
                                     CharmSlot.aura.rawValue]

    /// iPhone 2-up, iPad 4-up; the whole content column is width-capped
    /// on iPad so the page reads as a laid-out sheet, not a wall.
    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 14),
                     count: count)
    }

    /// Every catalog charm wearable on a supported placement. "All"
    /// means all SUPPORTED placements — a charm whose only placement
    /// has no pipeline yet (bodySide) is not browsable yet.
    private var browsable: [CharmDefinition] {
        AurieCharmCatalog.all
            .filter { def in
                // `launch` is EDITORIAL catalog membership — exactly
                // what a browse grid shows. It remains, as ever, NOT a
                // render/grant gate: a held-out charm that is somehow
                // equipped still renders, and grants ignore it.
                def.launch
                && def.placements.contains(where:
                    Self.supportedPlacements.contains)
            }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Categories offered = exactly those carried by browsable charms,
    /// via the data-driven taxonomy (stable ids → display names).
    private var categories: [String] {
        Array(Set(browsable.flatMap(\.categories)))
            .sorted { CharmTaxonomy.categoryName($0)
                < CharmTaxonomy.categoryName($1) }
    }

    /// Placement is an AND condition; the selected categories OR with
    /// each other (Food + Nature = carries Food OR Nature). Empty
    /// selection = all categories.
    private var filtered: [CharmDefinition] {
        browsable.filter { def in
            (placementFilter.map { def.placements.contains($0) } ?? true)
            && (selectedCategories.isEmpty
                || def.categories.contains(where: selectedCategories.contains))
        }
    }

    var body: some View {
        // The tab's own stack: Earn Charms PUSHES as a real page with a
        // standard Back control (approved polish) — never a fifth tab.
        NavigationStack {
            charmsPage
        }
        // Feature discovery: seeing the collection once retires the
        // "want to see which charms we've found?" greeting for good.
        .onAppear {
            if !model.store.settings.hasOpenedCharmCollection {
                model.store.settings.hasOpenedCharmCollection = true
            }
        }
    }

    private var charmsPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                titleRow
                earnCharmsRow
                    .padding(.top, 12)
                placementControl
                    .padding(.top, 12)
                categoryControl
                    .padding(.top, 11)
                grid
                    .padding(.top, 18)
            }
            .frame(maxWidth: 960)          // iPad: intentional column
            .frame(maxWidth: .infinity)    // …centred in the page
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        // The Charms root keeps its own custom header; the system bar
        // appears only on pushed pages (their Back control).
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showEarnCharms) {
            EarnCharmsView()
        }
        .sheet(item: $detailTarget) { def in
            CharmDetailSheet(def: def)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(categories: categories,
                                selection: $selectedCategories)
                .presentationDetents([.height(categorySheetHeight)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Earn Charms entry

    /// The doorway to the tasks page — a featured row, not a fifth tab.
    private var earnCharmsRow: some View {
        Button { showEarnCharms = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.yellow.opacity(0.9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Earn Charms")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Complete tasks to earn more charms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    // MARK: Header

    private var titleRow: some View {
        HStack(spacing: 10) {
            Text("Charms")
                .font(.title2.weight(.bold))
            Text("\(filtered.count)")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.secondary)
            Spacer()
            if let aurie = model.store.featured {
                // Secondary by design: metadata about who is being
                // customised, quieter than the title and controls.
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow.opacity(0.9))
                    Text(aurie.name)
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.07), in: Capsule())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: Placement — the primary filter, a segmented control

    private var placementControl: some View {
        HStack(spacing: 6) {
            segment("All", value: nil)
            ForEach(Self.supportedPlacements, id: \.self) { p in
                segment(CharmTaxonomy.placementName(p), value: p)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    private func segment(_ label: String, value: String?) -> some View {
        let isOn = placementFilter == value
        return Button {
            placementFilter = value
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    isOn ? AnyShapeStyle(Color.accentColor)
                         : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Category — one quiet control, sheet to choose

    private var categoryControl: some View {
        Button {
            showCategoryPicker = true
        } label: {
            HStack(spacing: 10) {
                Text("Categories")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(categorySummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedCategories.isEmpty ? .secondary
                                                                : .primary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    /// Sheet height fitted to the chip rows (title + rows + Done), so
    /// today's list shows without a hollow middle; the chip area itself
    /// scrolls if a grown catalog ever exceeds the cap.
    private var categorySheetHeight: CGFloat {
        let perRow = sizeClass == .regular ? 6 : 3   // rough chips/row
        let rows = (categories.count + perRow - 1) / perRow
        return min(540, 168 + CGFloat(rows) * 46)
    }

    /// The control's summary of the multi-selection: All Categories /
    /// one name / "A + B" / "N Categories".
    private var categorySummary: String {
        let names = selectedCategories.map(CharmTaxonomy.categoryName)
            .sorted()
        switch names.count {
        case 0: return "All Categories"
        case 1: return names[0]
        case 2: return "\(names[0]) + \(names[1])"
        default: return "\(names.count) Categories"
        }
    }

    // MARK: Grid

    private var grid: some View {
        VStack(spacing: 12) {
            if filtered.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No charms match these filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Clear Filters") {
                        placementFilter = nil
                        selectedCategories = []
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 70)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filtered, id: \.id) { def in
                        CharmTile(def: def,
                                  unlocked: model.charms.isUnlocked(def.id),
                                  equipped: isEquipped(def),
                                  showPlacement: placementFilter == nil)
                            .onTapGesture { detailTarget = def }
                    }
                    // Keep a lone result leading-aligned: fill the row.
                    if filtered.count < columns.count {
                        ForEach(0..<(columns.count - filtered.count),
                                id: \.self) { _ in Color.clear }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func isEquipped(_ def: CharmDefinition) -> Bool {
        model.store.featured?.resolvedEquippedCharms
            .contains { $0.charmID == def.id } ?? false
    }
}

// MARK: - Category picker sheet

/// MULTI-SELECT bottom sheet: wrapping category chips (blue = selected),
/// Clear resets to All Categories, Done closes. Selected categories OR
/// together in the grid filter.
private struct CategoryPickerSheet: View {
    let categories: [String]
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Categories")
                    .font(.headline)
                Spacer()
                Button("Clear") { selection = [] }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selection.isEmpty ? Color.secondary
                                                       : Color.accentColor)
                    .disabled(selection.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 14)
            ScrollView {
                ChipFlow(spacing: 8) {
                    ForEach(categories, id: \.self) { c in
                        chip(c)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .presentationBackground(Color(red: 0.09, green: 0.10, blue: 0.15))
    }

    private func chip(_ id: String) -> some View {
        let isOn = selection.contains(id)
        return Button {
            if isOn { selection.remove(id) } else { selection.insert(id) }
        } label: {
            Text(CharmTaxonomy.categoryName(id))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    isOn ? AnyShapeStyle(Color.accentColor)
                         : AnyShapeStyle(Color.white.opacity(0.07)),
                    in: Capsule())
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// Minimal flow layout: places subviews left-to-right, wrapping into
/// new rows — chips read as a tag cloud, never a horizontal strip.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Cards

/// One charm card: the art is the hero; name below. Locked charms keep
/// their recognisable colours — a soft dim, a light dark veil and a
/// lock badge say "not yours yet" without making the charm ugly.
private struct CharmTile: View {
    let def: CharmDefinition
    let unlocked: Bool
    let equipped: Bool
    let showPlacement: Bool

    var body: some View {
        VStack(spacing: 8) {
            CharmArt(def: def, locked: !unlocked)
                .frame(maxWidth: .infinity)
                .frame(height: 110)
            HStack(spacing: 5) {
                Text(def.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .opacity(unlocked ? 1 : 0.75)
                if showPlacement, let p = def.placements.first(where:
                        CharmsView.supportedPlacements.contains) {
                    Text(CharmTaxonomy.placementName(p))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.10), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.17, green: 0.18, blue: 0.27),
                                    Color(red: 0.10, green: 0.11, blue: 0.17)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .topTrailing) {
            if !unlocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(7)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(8)
            } else if equipped {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.green.opacity(0.9))
                    .padding(9)
            }
        }
    }
}

/// The browse artwork for a charm — the best PROCESSED asset the app
/// ships, in priority order:
///   1. a CATALOG-ONLY preview (charm_catalog_<id>; e.g. the backpack
///      pack-only picture — the wearable strap harness never appears
///      in browse/detail)
///   2. the approved graded belly sticker
///   3. the back-orientation wearable layer, 4. the front layer
/// Nothing here alters wearable assets. LOCKED presentation keeps
/// 100% of the asset's hue and most of its saturation: sat 0.82,
/// slight dim, a 14% dark veil — recognisable, clearly not owned.
// Internal (not file-private) since Phase D: the hatch reveal's
// Birth-Charm card reuses this exact treatment so charm artwork reads
// identically everywhere.
struct CharmArt: View {
    let def: CharmDefinition
    var locked = false
    /// UI-only visual-weight trim so silhouettes feel balanced in the
    /// grid (a wide crystal vs a tall apple). NEVER a wearable scale.
    private static let displayScale: [String: CGFloat] = [
        "charm_magic_star_coin_01": 0.90,
        "charm_magic_crystal_02": 0.94,
        "charm_magic_star_01": 0.95,
        "charm_object_backpack_01": 0.93,
    ]

    var body: some View {
        Group {
            if let image = Self.image(for: def) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(Self.displayScale[def.id] ?? 1)
                    .padding(6)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 42))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        // Locked = the ART ITSELF slightly subdued (hue intact, modest
        // desaturation, gentle dim) + the lock badge. No veil shape: a
        // visible dark sub-card read as a card inside a card.
        .saturation(locked ? 0.8 : 1)
        .brightness(locked ? -0.08 : 0)
        .opacity(locked ? 0.82 : 1)
    }

    static func image(for def: CharmDefinition) -> UIImage? {
        for name in ["charm_catalog_\(def.id)",
                     "belly_sticker_\(def.id)",
                     "aurie_round_\(def.id)_back",
                     "aurie_round_\(def.id)"] {
            if let image = UIImage(named: name) { return image }
        }
        return nil
    }
}

// MARK: - Detail sheet

/// V1 detail: preview → name → quiet category tags → placement →
/// action/locked message. Equip/Remove goes through the EXISTING
/// equipment records — one per placement, no second persistence path.
/// Locked charms never reveal their unlock method.
private struct CharmDetailSheet: View {
    let def: CharmDefinition
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var unlocked: Bool { model.charms.isUnlocked(def.id) }
    private var featured: Aurie? { model.store.featured }
    private var equipped: Bool {
        featured?.resolvedEquippedCharms
            .contains { $0.charmID == def.id } ?? false
    }
    /// The placement an Equip uses: the charm's first placement with a
    /// real pipeline. (A future multi-placement charm would surface a
    /// chooser here; no current charm needs one.)
    private var equipPlacement: String? {
        def.placements.first(where: CharmsView.supportedPlacements.contains)
    }

    var body: some View {
        VStack(spacing: 16) {
            CharmArt(def: def, locked: !unlocked)
                .frame(height: 190)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(colors: [Color(red: 0.19, green: 0.20,
                                                  blue: 0.30),
                                            Color(red: 0.11, green: 0.12,
                                                  blue: 0.18)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 24))
                .overlay(alignment: .topTrailing) {
                    if !unlocked {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(9)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(10)
                    }
                }

            Text(def.displayName)
                .font(.title3.weight(.bold))

            // Quiet metadata tags — deliberately softer than any
            // interactive control so they can't read as filters.
            HStack(spacing: 6) {
                ForEach(def.categories, id: \.self) { c in
                    Text(CharmTaxonomy.categoryName(c))
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.05), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }

            Text(def.placements
                    .filter(CharmsView.supportedPlacements.contains)
                    .map(CharmTaxonomy.placementName)
                    .joined(separator: ", "))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if unlocked {
                if let aurie = featured, equipPlacement != nil {
                    Button {
                        equipped ? remove(from: aurie) : equip(on: aurie)
                        dismiss()
                    } label: {
                        Text(equipped ? "Remove from \(aurie.name)"
                                      : "Equip on \(aurie.name)")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(equipped ? Color(red: 0.45, green: 0.30, blue: 0.55)
                                   : .accentColor)
                } else {
                    Text("Hatch an Aurie to wear this charm.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Generic on purpose: discovery mechanics stay a surprise.
                Label("Discover this charm to unlock it.",
                      systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationBackground(Color(red: 0.07, green: 0.08, blue: 0.12))
    }

    /// One charm per placement (product rule): both actions go through
    /// AppModel's central equip seam — the same one the DEBUG
    /// verification hooks exercise.
    private func equip(on aurie: Aurie) {
        guard let placement = equipPlacement else { return }
        model.equipCharm(def, on: aurie, placement: placement)
    }

    private func remove(from aurie: Aurie) {
        model.removeCharm(def.id, from: aurie)
    }
}

extension CharmDefinition: Identifiable {}
