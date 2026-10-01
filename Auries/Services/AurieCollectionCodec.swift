import Foundation

/// Decoding `auries.json` without letting one bad record destroy the file.
///
/// Before 2026-09-21 the load was `(try? decode([Aurie].self)) ?? []`, so a
/// SINGLE unreadable record — one unknown enum raw value, one malformed
/// `equippedCharms` entry — silently produced an EMPTY collection, which the
/// next `add`/`update` then wrote back over the file. Whole-collection data
/// loss from one bad byte.
///
/// Deliberately UIKit-free so the offline harness can test it directly.
enum AurieCollectionCodec {

    struct Outcome {
        /// Every record that decoded cleanly, in file order.
        let auries: [Aurie]
        /// Records that were present but unreadable, and so were skipped.
        let dropped: Int
        /// The FILE could not be parsed as an array at all, so its contents
        /// are UNKNOWN. Callers must treat this as "unknown", never as
        /// "empty", and must not overwrite the file.
        let fileUnreadable: Bool
    }

    /// One array element that refuses to take the whole array down with it.
    /// `JSONDecoder` still tracks element boundaries, so a failure here
    /// skips exactly this record and decoding continues with the next.
    private struct FailableAurie: Decodable {
        let value: Aurie?
        init(from decoder: Decoder) throws {
            value = try? Aurie(from: decoder)
        }
    }

    static func decode(_ data: Data) -> Outcome {
        let decoder = JSONDecoder()
        if let rows = try? decoder.decode([FailableAurie].self, from: data) {
            let good = rows.compactMap(\.value)
            return Outcome(auries: good,
                           dropped: rows.count - good.count,
                           fileUnreadable: false)
        }
        // The array itself is unparseable (truncated or garbage JSON). We
        // know NOTHING about what it held, so report unreadable rather than
        // claiming the player owns no Auries.
        return Outcome(auries: [], dropped: 0, fileUnreadable: true)
    }
}
