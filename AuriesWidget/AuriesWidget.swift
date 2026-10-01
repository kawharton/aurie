import WidgetKit
import SwiftUI

// The featured-Aurie Home Screen widget (Phase 8B): one warm systemSmall
// card — family-coloured night backdrop, the creature still, its name.
// Everything it shows comes from the App Group snapshot the main app
// exports; there is no SpriteKit, no store, and no timeline churn here.

@main
struct AuriesWidgetBundle: WidgetBundle {
    var body: some Widget {
        FeaturedAurieWidget()
    }
}

struct FeaturedAurieWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.widgetKind,
                            provider: FeaturedProvider()) { entry in
            FeaturedAurieView(entry: entry)
        }
        .configurationDisplayName("Featured Aurie")
        .description("Your featured creature, always close by.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Timeline

struct FeaturedEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetBridge.Snapshot?
    let still: UIImage?

    /// Read whatever the app last exported; any missing or unreadable piece
    /// degrades to the friendly empty state, never a crash or a blank.
    static func current() -> FeaturedEntry {
        guard let snapshot = WidgetBridge.loadSnapshot(),
              let url = WidgetBridge.imageURL(named: snapshot.imageFile),
              let image = UIImage(contentsOfFile: url.path) else {
            return FeaturedEntry(date: Date(), snapshot: nil, still: nil)
        }
        return FeaturedEntry(date: Date(), snapshot: snapshot, still: image)
    }

    static let preview = FeaturedEntry(date: Date(), snapshot: nil, still: nil)
}

struct FeaturedProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeaturedEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (FeaturedEntry) -> Void) {
        completion(.current())
    }

    // The featured creature only changes when the app says so, and the app
    // reloads this widget on every export — so one entry, no refresh churn.
    func getTimeline(in context: Context, completion: @escaping (Timeline<FeaturedEntry>) -> Void) {
        completion(Timeline(entries: [.current()], policy: .never))
    }
}

// MARK: - View

struct FeaturedAurieView: View {
    let entry: FeaturedEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let still = entry.still {
                featured(snapshot, still)
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) { background }
        .widgetURL(WidgetBridge.homeURL)
    }

    /// The creature, dominant, with its name tucked beneath.
    private func featured(_ snapshot: WidgetBridge.Snapshot, _ still: UIImage) -> some View {
        VStack(spacing: 0) {
            Image(uiImage: still)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(snapshot.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.name), \(snapshot.family) family Aurie")
    }

    /// No featured creature yet (or shared data unavailable): stay branded
    /// and gentle, and invite the user in.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.yellow.opacity(0.9))
            Text("A friend is waiting")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
            Text("Open Aurie to hatch one")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aurie. Open the app to hatch or choose a featured creature.")
    }

    /// The family night backdrop, precomputed by the app so it matches Home
    /// exactly; a deep neutral night when nothing is featured.
    private var background: some View {
        let (r, g, b): (Double, Double, Double)
        if let s = entry.snapshot {
            (r, g, b) = (s.backdropRed, s.backdropGreen, s.backdropBlue)
        } else {
            (r, g, b) = (0.09, 0.10, 0.14)
        }
        return LinearGradient(
            colors: [Color(red: r * 1.35, green: g * 1.35, blue: b * 1.35),
                     Color(red: r * 0.75, green: g * 0.75, blue: b * 0.75)],
            startPoint: .top, endPoint: .bottom)
    }
}
