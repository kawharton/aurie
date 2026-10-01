import Foundation

/// ONE definition of "today" for the whole app.
///
/// The body below moved verbatim out of `DailyLift.item(for:calendar:)`, whose
/// load-bearing comment is preserved: `ordinality(of: .day, in: .era)` looks
/// right for this but advances at a GMT-anchored boundary rather than local
/// midnight — it was observed flipping the daily item at 8 PM EDT.
///
/// Anything that needs a stable per-day value (Daily Lift, Wonderglobe) must
/// call this rather than writing a second version.
public enum CalendarDay {

    /// Whole calendar days since a fixed reference — increments exactly at
    /// local midnight.
    public static func key(for date: Date = Date(),
                           calendar: Calendar = .current) -> Int {
        let reference = calendar.startOfDay(
            for: Date(timeIntervalSinceReferenceDate: 0))
        return calendar.dateComponents([.day], from: reference,
                                       to: calendar.startOfDay(for: date)).day ?? 0
    }
}
