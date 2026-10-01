import SwiftUI

/// Creature page (§6): pushed inside the Auries tab by tapping a grid tile
/// (the tab bar stays), swipe left/right through the whole collection. Each
/// page shows the creature live
/// on its family backdrop with name · family, its permanent line, personality
/// trio, and born-from thumbnail. Set-as-featured is the primary action;
/// Delete is small, set apart, and always confirms.
struct CreatureDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String
    @State private var confirmDeleteId: String?

    init(initial: Aurie) {
        _selection = State(initialValue: initial.id)
    }

    private var currentAurie: Aurie? {
        model.store.auries.first { $0.id == selection }
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(model.store.auries) { aurie in
                page(for: aurie)
                    .tag(aurie.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // The pager sits inside the safe area (so the tab bar below never
        // covers the page's last row); the family backdrop is painted
        // behind it, edge to edge, so the top stays full-bleed.
        .background {
            Color.familyBackdrop(currentAurie?.auraColor ?? Rgb(40, 32, 36))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: selection)
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(20)
        }
        .alert(
            "Delete this Aurie?",
            isPresented: Binding(
                get: { confirmDeleteId != nil },
                set: { if !$0 { confirmDeleteId = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let id = confirmDeleteId,
                      let doomed = model.store.auries.first(where: { $0.id == id }) else { return }
                // Land on a neighbour before the page vanishes.
                if let index = model.store.auries.firstIndex(where: { $0.id == id }) {
                    let neighbors = model.store.auries.enumerated()
                        .filter { $0.offset != index }
                        .map(\.element)
                    if let next = neighbors[safe: max(index - 1, 0)] ?? neighbors.first {
                        selection = next.id
                    }
                }
                model.store.delete(doomed)
                if model.store.auries.isEmpty { dismiss() }
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func page(for aurie: Aurie) -> some View {
        ZStack {
            Color.familyBackdrop(aurie.auraColor)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                // Name · family (+ crown when featured)
                HStack(spacing: 8) {
                    if aurie.id == model.store.featured?.id {
                        Image(systemName: "crown.fill")
                            .font(.subheadline)
                            .foregroundStyle(.yellow)
                    }
                    Text(aurie.name)
                        .font(.largeTitle.weight(.bold))
                    if model.store.worry(for: aurie) != nil {
                        // This Aurie is holding a worry light (Calm Mode).
                        Image(systemName: "lightbulb.min.fill")
                            .font(.caption)
                            .foregroundStyle(Color(aurie.auraColor))
                            .accessibilityLabel("\(aurie.name) is holding something for you")
                    }
                }
                .padding(.top, 26)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(aurie.auraColor))
                        .frame(width: 9, height: 9)
                    Text(aurie.family.rawValue.capitalized + " Family")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                CreaturePlayView(aurie: aurie)
                    .id(aurie.id)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 22)

                Text("“\(aurie.line)”")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                Text(aurie.traits.map(\.capitalized).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                bornFrom(aurie)

                Button {
                    model.store.setFeatured(aurie)
                } label: {
                    Label(
                        aurie.id == model.store.featured?.id ? "Featured on Home" : "Set as featured",
                        systemImage: "crown.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(aurie.auraColor, brightness: 0.75))
                .disabled(aurie.id == model.store.featured?.id)
                .padding(.horizontal, 24)
                .padding(.top, 4)

                // Delete: deliberately small and set apart (§6).
                Button(role: .destructive) {
                    confirmDeleteId = aurie.id
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.footnote)
                }
                .padding(.top, 10)
                .padding(.bottom, 18)
            }
        }
    }

    @ViewBuilder
    private func bornFrom(_ aurie: Aurie) -> some View {
        HStack(spacing: 10) {
            if let thumb = model.store.thumbnail(for: aurie) {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "sparkles")
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            Text("born from \(aurie.bornFrom)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
