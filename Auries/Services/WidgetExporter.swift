import UIKit
import WidgetKit

/// Publishes the featured creature to the widget's App Group (Phase 8B):
/// one rendered still + one tiny snapshot JSON, written atomically, then a
/// targeted timeline reload. Store calls this from every featured-changing
/// mutation; AppModel calls it once at launch to repair a missing or stale
/// snapshot.
///
/// Failure here is always harmless: the app never blocks on it, and the
/// widget shows its friendly empty state until the next successful export.
enum WidgetExporter {

    /// Export the current featured creature (nil clears to the empty state).
    /// The still renders on the main actor (milliseconds at 512 px); encoding
    /// and file writes hop to a utility queue, and every outcome ends with a
    /// reload so the widget converges on whatever the app now believes.
    static func exportFeatured(_ aurie: Aurie?) {
        guard let container = WidgetBridge.containerURL,
              let snapshotURL = WidgetBridge.snapshotURL,
              let imageURL = WidgetBridge.imageURL(named: imageFile) else {
            debugLog("App Group container unavailable — widget shows empty state")
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.widgetKind)
            return
        }

        guard let aurie else {
            // Collection is empty: clear to the widget's empty state.
            DispatchQueue.global(qos: .utility).async {
                try? FileManager.default.removeItem(at: snapshotURL)
                try? FileManager.default.removeItem(at: imageURL)
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.widgetKind)
            }
            return
        }

        let png = AssetLoader.widgetStill(for: aurie).pngData()
        let backdrop = familyBackdropComponents(aurie.auraColor)
        let snapshot = WidgetBridge.Snapshot(
            featuredId: aurie.id,
            name: aurie.name,
            family: aurie.family.rawValue,
            auraRed: aurie.auraColor.r,
            auraGreen: aurie.auraColor.g,
            auraBlue: aurie.auraColor.b,
            backdropRed: backdrop.r,
            backdropGreen: backdrop.g,
            backdropBlue: backdrop.b,
            imageFile: imageFile,
            updated: Date())

        DispatchQueue.global(qos: .utility).async {
            defer { WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.widgetKind) }
            do {
                guard let png else {
                    debugLog("could not encode widget still")
                    return
                }
                try FileManager.default.createDirectory(at: container,
                                                        withIntermediateDirectories: true)
                try png.write(to: imageURL, options: .atomic)
                try JSONEncoder().encode(snapshot).write(to: snapshotURL, options: .atomic)
            } catch {
                debugLog("export failed: \(error)")
            }
        }
    }

    /// One stable filename: each export overwrites the previous still, so the
    /// container never accumulates images.
    private static let imageFile = "featured_still.png"

    private nonisolated static func debugLog(_ message: String) {
        #if DEBUG
        print("WidgetExporter: \(message)")
        #endif
    }
}
