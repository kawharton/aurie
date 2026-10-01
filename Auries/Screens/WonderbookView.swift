import SwiftUI

/// The Wonderbook: Wonders the player chose to keep.
///
/// Intentionally small — a list of saved pages, newest first, with a remove
/// action and an empty state. No categories, search, sharing or streaks.
struct WonderbookView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Family tint, so the book belongs to the Aurie the player is with.
    let aura: Rgb

    private var items: [DailyLiftItem] { model.wonderbook }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    empty
                } else {
                    List {
                        ForEach(items, id: \.id) { item in
                            page(item)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16,
                                                          bottom: 6, trailing: 16))
                                .swipeActions {
                                    Button(role: .destructive) {
                                        model.removeFromWonderbook(item.id)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(background)
            .navigationTitle("Wonderbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var background: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.11)
            RadialGradient(colors: [Color(aura, brightness: 0.5).opacity(0.20), .clear],
                           center: UnitPoint(x: 0.5, y: 0.18),
                           startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    private func page(_ item: DailyLiftItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkle")
                .font(.footnote)
                .foregroundStyle(Color(aura, brightness: 0.95).opacity(0.85))
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.kind.sparkLabel.uppercased())
                    .font(.caption2.weight(.semibold))
                    .kerning(0.8)
                    .foregroundStyle(Color(aura, brightness: 0.95).opacity(0.75))
                Text(item.text)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(aura, brightness: 0.9).opacity(0.18),
                                      lineWidth: 1)
                )
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color(aura, brightness: 0.9).opacity(0.7))
            Text("No Sparks saved yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Shake your Aurie to find today's Spark, then keep the ones you love.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
