import Foundation

/// Calm Mode copy, loaded from `calm_content.json` (editable with no code
/// change, like the other content files): sparing per-family calm lines and
/// the Worry Jar's hold/release lines.
///
/// Design boundary (from the Calm Mode spec — do not change): Calm Mode is a
/// comforting fictional companion, NOT therapy, advice, analysis, or an
/// emergency service. Lines never claim a worry is fixed or gone.
public final class CalmContent {

    struct Data: Codable {
        let calmLines: [String: [String]]
        let worryHold: [String]
        let worryRelease: [String]
    }

    private let calmLines: [String: [String]]
    private let worryHold: [String]
    private let worryRelease: [String]

    init(_ d: Data) {
        calmLines = d.calmLines
        worryHold = d.worryHold
        worryRelease = d.worryRelease
    }

    public static func load(from url: URL) throws -> CalmContent {
        let data = try Foundation.Data(contentsOf: url)
        return CalmContent(try JSONDecoder().decode(Data.self, from: data))
    }

    /// One quiet line in the family's voice. Used sparingly — at most once
    /// per Calm Mode visit.
    public func calmLine(for family: AuraFamily) -> String? {
        calmLines[family.rawValue]?.randomElement()
    }

    public var holdLine: String { worryHold.randomElement() ?? "I'll hold this with you." }
    public var releaseLine: String { worryRelease.randomElement() ?? "We can let this one go for now." }
}
