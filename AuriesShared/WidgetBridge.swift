import Foundation

/// The narrow App Group seam between the app and its widget (Phase 8B).
/// This file is the ONLY place that knows the group identifier, the shared
/// filenames, the snapshot schema, and the deep-link route — and it is the
/// only source file compiled into both targets.
///
/// The main app owns all real data. It exports just enough for the widget to
/// draw one still card: a tiny versioned JSON snapshot plus one rendered
/// creature image. The user's photos, thumbnails, collection, settings, and
/// wallet never enter the App Group.
/// `nonisolated`: both processes use this from arbitrary threads (the app
/// exports off-main; the widget decodes wherever WidgetKit calls it).
nonisolated enum WidgetBridge {

    /// Derived from the app bundle identifier (com.kwharton.auries).
    static let appGroupId = "group.com.kwharton.auries"

    /// The widget kind string, shared by the widget definition and the app's
    /// targeted timeline reloads.
    static let widgetKind = "AurieFeaturedWidget"

    /// Tapping the widget opens the app on Home through this route.
    static let homeURL = URL(string: "auries://home")!

    /// Everything the widget needs, and nothing more. Bump `schemaVersion`
    /// when fields change; readers ignore snapshots from the future.
    struct Snapshot: Codable, Sendable {
        var schemaVersion: Int = Snapshot.currentVersion
        var featuredId: String
        var name: String
        var family: String        // family identifier, for accessibility
        var auraRed: Int          // aura colour, 0-255
        var auraGreen: Int
        var auraBlue: Int
        var backdropRed: Double   // precomputed family-backdrop colour, 0-1
        var backdropGreen: Double
        var backdropBlue: Double
        var imageFile: String     // rendered creature still, in the container
        var updated: Date

        static let currentVersion = 1
    }

    // MARK: Shared locations

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("featured.json")
    }

    static func imageURL(named file: String) -> URL? {
        containerURL?.appendingPathComponent(file)
    }

    // MARK: Reading (widget side, but the app may repair with it too)

    /// The current snapshot, or nil when it is missing, unreadable, corrupt,
    /// or from a newer schema than this reader understands. Never throws —
    /// callers show the friendly empty state on nil.
    static func loadSnapshot() -> Snapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.schemaVersion <= Snapshot.currentVersion else { return nil }
        return snapshot
    }
}
