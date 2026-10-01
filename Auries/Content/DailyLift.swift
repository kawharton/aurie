import Foundation

// MARK: - The Home "daily lift"
//
// A day's feel-good moment shown in a bottom card on Home — a quote, joke, or dare.
// It is APP-WIDE and independent of the featured creature: it does NOT change when
// you switch Auries, and it is NOT a creature's permanent `line`.
//
// Selection is deterministic by calendar day: the same item all day, a new one at
// local midnight, identical on every device in the same time zone. Nothing is stored
// — it's derived from the date, so there's no state to persist or reset.

/// One item for the daily-lift card.
public struct DailyLiftItem: Equatable {
    public enum Kind: String, Codable { case quote, joke, dare
        /// User-facing secondary label. The primary heading is always
        /// "Today's Spark"; this only distinguishes the flavour.
        public var sparkLabel: String {
            switch self {
            case .quote: return "Lift"
            case .joke:  return "Laugh"
            case .dare:  return "Dare"
            }
        }
    }
    /// STABLE content id — never an array index, so a saved Spark survives
    /// content being reordered or extended.
    public let id: String
    public let kind: Kind
    public let text: String
}

/// Decoded shape of `daily_content.json`.
struct DailyContentData: Codable {
    struct Entry: Codable { let id: String; let text: String }
    let quotes: [Entry]
    let jokes: [Entry]
    let dares: [Entry]
}

public final class DailyLift {

    /// All items, round-robin interleaved (quote, joke, dare, quote, …) so
    /// consecutive days vary in type instead of running 12 quotes in a row.
    private let items: [DailyLiftItem]

    init(_ d: DailyContentData) {
        let columns: [[DailyLiftItem]] = [
            d.quotes.map { DailyLiftItem(id: $0.id, kind: .quote, text: $0.text) },
            d.jokes.map  { DailyLiftItem(id: $0.id, kind: .joke,  text: $0.text) },
            d.dares.map  { DailyLiftItem(id: $0.id, kind: .dare,  text: $0.text) },
        ]
        var out: [DailyLiftItem] = []
        let longest = columns.map(\.count).max() ?? 0
        for i in 0..<longest {
            for column in columns where i < column.count { out.append(column[i]) }
        }
        items = out
    }

    /// The item for a given day (defaults to today). Stable for the whole local day;
    /// advances at local midnight; wraps around when the list is exhausted.
    public func item(for date: Date = Date(), calendar: Calendar = .current) -> DailyLiftItem? {
        guard !items.isEmpty else { return nil }
        // ONE definition of "today", shared with Wonderglobe. See CalendarDay
        // for why this is not `ordinality(of: .day, in: .era)`.
        let dayIndex = CalendarDay.key(for: date, calendar: calendar)
        let i = ((dayIndex % items.count) + items.count) % items.count
        return items[i]
    }

    /// Resolve a saved Spark id. Nil after a content migration removed it —
    /// the caller's cue to fall through and select a replacement.
    public func item(id: String) -> DailyLiftItem? {
        items.first { $0.id == id }
    }

    /// Load + decode from the bundled `daily_content.json`.
    public static func load(from url: URL) throws -> DailyLift {
        let data = try Data(contentsOf: url)
        return DailyLift(try JSONDecoder().decode(DailyContentData.self, from: data))
    }
}
