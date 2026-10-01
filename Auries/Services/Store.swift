import Foundation
import Observation
import UIKit

/// On-device persistence (§10): the collection and settings, saved as JSON in
/// Application Support. Codable-to-disk — the collection is small, so every
/// mutation writes the whole file atomically.
///
/// TODO(step 11): move storage into the App Group container so the WidgetKit
/// extension can read the featured creature (swap `directory` only).
@Observable
final class Store {

    struct Settings: Codable {
        var featuredAurieId: String?
        var soundOn = true            // respected by SoundPlayer
        var notificationsOn = false   // TODO(phase 7)
        var hasSeenTutorial = false   // TODO(phase 7)
        /// The last MEANINGFUL Home arrival — an app launch, a return from
        /// a long background, or the first hatch replacing the greeter.
        /// (Originally "when the creature last said its daily line"; the
        /// contextual greeting system, 2026-09-27, keeps the key so older
        /// saves carry over, and reads it as "when was the player last
        /// here" to tell a long absence from an ordinary return.)
        var lastGreetingDate: Date?
        /// Meaningful Home arrivals WITH a real Aurie. Only used to weight
        /// discovery prompts up during the first few visits.
        var homeArrivalCount = 0

        // FEATURE DISCOVERY (contextual greetings, 2026-09-27). Each is set
        // once, at the moment the player uses the feature, and never
        // cleared in production; a tutorial prompt for it stops for good.
        // Calm reuses `hasSeenCalmIntro` below — it already means "has
        // opened Calm once". Charm discovery is derived from the account
        // collection (owned count > 0), not stored again.
        /// At least one Aurie has ever hatched. Permanent, so the
        /// first-Aurie greeting can never return even if the collection is
        /// later emptied.
        var hasHatchedFirstAurie = false
        var hasOpenedToyBox = false
        var hasOpenedCharmCollection = false
        var hasShakenPhone = false
        /// When the daily-lift card was dismissed — hides it for the rest of
        /// that day; tomorrow's item brings it back.
        var dailyLiftDismissedDate: Date?
        /// First Calm Mode visit shows a one-line intro.
        var hasSeenCalmIntro = false
        /// Calm Mode's ambient music toggle (independent of the global Sound
        /// setting, which also gates it).
        var calmMusicOn = true
        /// Which calm soundscape plays (SoundPlayer.ambientTracks id).
        var calmTrack = "pad"

        /// Which local day the saved Wonder belongs to.
        var savedWonderDayKey: Int?
        /// STABLE content id, never an array index.
        var savedWonderID: String?
        /// The day whose Wonder was actually revealed by a shake.
        var wonderRevealedDayKey: Int?
        /// Wonderbook: STABLE Wonder ids the player chose to keep, in save
        /// order. Entirely independent of the daily selection — saving never
        /// influences which Wonder a day gets.
        var savedWonderIDs: [String] = []

        /// CHARM TASK PROGRESS (Phase E): per task id, the CalendarDay
        /// keys already counted toward the target — count = progress,
        /// membership = the same day can never count twice. COMPLETION
        /// is still the grant-ledger entry, never this; this is only
        /// the road there. Survives relaunch like every setting.
        var charmTaskDayKeys: [String: [Int]] = [:]

        init() {}

        /// Lenient decoding: every field falls back to its default when the
        /// key is missing, so adding a new setting never invalidates the
        /// settings.json written by an older build. (Synthesized Codable
        /// would throw on the first missing key and silently reset ALL
        /// settings on app update — featured creature included.)
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            featuredAurieId = try c.decodeIfPresent(String.self, forKey: .featuredAurieId)
            soundOn = try c.decodeIfPresent(Bool.self, forKey: .soundOn) ?? true
            notificationsOn = try c.decodeIfPresent(Bool.self, forKey: .notificationsOn) ?? false
            hasSeenTutorial = try c.decodeIfPresent(Bool.self, forKey: .hasSeenTutorial) ?? false
            lastGreetingDate = try c.decodeIfPresent(Date.self, forKey: .lastGreetingDate)
            homeArrivalCount = try c.decodeIfPresent(Int.self, forKey: .homeArrivalCount) ?? 0
            hasHatchedFirstAurie = try c.decodeIfPresent(Bool.self, forKey: .hasHatchedFirstAurie) ?? false
            hasOpenedToyBox = try c.decodeIfPresent(Bool.self, forKey: .hasOpenedToyBox) ?? false
            hasOpenedCharmCollection = try c.decodeIfPresent(Bool.self, forKey: .hasOpenedCharmCollection) ?? false
            hasShakenPhone = try c.decodeIfPresent(Bool.self, forKey: .hasShakenPhone) ?? false
            dailyLiftDismissedDate = try c.decodeIfPresent(Date.self, forKey: .dailyLiftDismissedDate)
            hasSeenCalmIntro = try c.decodeIfPresent(Bool.self, forKey: .hasSeenCalmIntro) ?? false
            calmMusicOn = try c.decodeIfPresent(Bool.self, forKey: .calmMusicOn) ?? true
            calmTrack = try c.decodeIfPresent(String.self, forKey: .calmTrack) ?? "pad"
            // Omitting any of these three decode lines is the classic silent
            // failure here: CodingKeys stays synthesized, the field compiles,
            // and the value is simply never read back.
            savedWonderDayKey = try c.decodeIfPresent(Int.self, forKey: .savedWonderDayKey)
            savedWonderID = try c.decodeIfPresent(String.self, forKey: .savedWonderID)
            wonderRevealedDayKey = try c.decodeIfPresent(Int.self, forKey: .wonderRevealedDayKey)
            savedWonderIDs = try c.decodeIfPresent([String].self, forKey: .savedWonderIDs) ?? []
            charmTaskDayKeys = try c.decodeIfPresent(
                [String: [Int]].self, forKey: .charmTaskDayKeys) ?? [:]
        }
    }

    /// The Worry Jar's anonymous token (Calm Mode spec, privacy boundary):
    /// records only THAT an Aurie is holding something and since when —
    /// never what was written. The worry text itself must never be
    /// persisted, logged, or transmitted anywhere.
    struct WorryToken: Codable {
        var givenAt: Date
    }

    private(set) var auries: [Aurie] = []
    /// One held worry light per Aurie (v1), keyed by aurie id.
    private(set) var worries: [String: WorryToken] = [:]
    var settings = Settings() {
        didSet { save(settings, to: Self.settingsURL) }
    }

    init() {
        if let data = try? Data(contentsOf: Self.auriesURL) {
            // PER-RECORD decoding: one unreadable Aurie is skipped, the rest
            // survive. A file that cannot be parsed at all is reported as
            // UNREADABLE (not empty) and blocks writes, so the original is
            // never overwritten by a phantom empty collection.
            let outcome = AurieCollectionCodec.decode(data)
            auries = outcome.auries
            auriesFileUnreadable = outcome.fileUnreadable
            if outcome.fileUnreadable {
                quarantineAuriesFile("auries.json could not be parsed")
            } else if outcome.dropped > 0 {
                quarantineAuriesFile(
                    "skipped \(outcome.dropped) unreadable Aurie record(s)")
            }
            migrateSavedTraits()
        }
        if let data = try? Data(contentsOf: Self.settingsURL),
           let loaded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = loaded
        }
        // Backfill for installs that predate the flag: owning an Aurie means
        // one has hatched. (Persisted with the next settings write.)
        if !settings.hasHatchedFirstAurie, !auries.isEmpty {
            settings.hasHatchedFirstAurie = true
        }
        if let data = try? Data(contentsOf: Self.worriesURL),
           let loaded = try? JSONDecoder().decode([String: WorryToken].self, from: data) {
            worries = loaded
        }
    }

    /// True when `auries.json` existed but could not be parsed at all. While
    /// set, the collection in memory says NOTHING about what the file held,
    /// so every write to that file is refused.
    private(set) var auriesFileUnreadable = false

    /// The ONLY path that writes auries.json. Refuses to overwrite a file we
    /// could not read — the difference between "you own no Auries" and "we
    /// could not tell" must never be resolved destructively.
    private func saveAuries() {
        guard !auriesFileUnreadable else {
            print("Store: auries.json was unreadable at launch — refusing to "
                  + "overwrite it. A copy is at auries.corrupt.json.")
            return
        }
        save(auries, to: Self.auriesURL)
    }

    /// Keep one copy of the original bytes the first time anything is wrong,
    /// so a dropped record is recoverable by hand instead of lost.
    private func quarantineAuriesFile(_ reason: String) {
        let backup = Self.directory.appendingPathComponent("auries.corrupt.json")
        print("Store: \(reason); preserving original at \(backup.lastPathComponent)")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try? FileManager.default.copyItem(at: Self.auriesURL, to: backup)
    }

    // MARK: - Migration

    /// One-time fill-in for creatures saved before `baseExpression` was a
    /// stored field. Their face is resolved ONCE from the seed and written
    /// back, so later changes to the weighting table can never repaint the
    /// face of an Aurie that already exists. Runs only when something is
    /// actually missing, so normal launches do no extra disk writes.
    private func migrateSavedTraits() {
        var changed = false
        for index in auries.indices {
            if auries[index].baseExpression == nil {
                auries[index].baseExpression = auries[index].resolvedBaseExpression
                changed = true
            }
            // Same resolve-once rule for limbs: whatever the seed picks
            // TODAY is frozen into the record, so future changes to the
            // limb library cannot re-limb an existing creature.
            if auries[index].armStyle == nil {
                auries[index].armStyle = auries[index].resolvedArmStyle
                changed = true
            }
            if auries[index].legStyle == nil {
                auries[index].legStyle = auries[index].resolvedLegStyle
                changed = true
            }
            // Hair landed 2026-09-12. Pre-hair creatures freeze to the baked
            // tuft they have always worn — never a reroll.
            if auries[index].hairStyle == nil {
                auries[index].hairStyle = auries[index].resolvedHairStyle
                changed = true
            }
            // Patterns landed after these creatures were saved. Resolve ONCE
            // and freeze it. Unlike the limbs the fallback is `.none`, so a
            // pre-pattern Aurie is written back as plain and stays exactly as
            // it looked before — integrating patterns never changes it.
            if auries[index].pattern == nil {
                auries[index].pattern = auries[index].resolvedPattern
                changed = true
            }
        }
        if changed { saveAuries() }
    }

    // MARK: - Worry Jar

    func worry(for aurie: Aurie) -> WorryToken? { worries[aurie.id] }

    /// Marks the Aurie as holding one light. The caller must have already
    /// discarded the typed text — only this date-stamped token exists.
    func holdWorry(for aurie: Aurie) {
        worries[aurie.id] = WorryToken(givenAt: Date())
        save(worries, to: Self.worriesURL)
    }

    func releaseWorry(for aurie: Aurie) {
        worries[aurie.id] = nil
        save(worries, to: Self.worriesURL)
    }

    // MARK: - Collection

    /// The creature Home and the widget show. Falls back to the first in the
    /// collection if none was explicitly chosen (or the chosen one was deleted).
    var featured: Aurie? {
        auries.first { $0.id == settings.featuredAurieId } ?? auries.first
    }

    /// Names already taken, fed to the generator to avoid duplicates.
    var existingNames: Set<String> { Set(auries.map(\.name)) }

    func add(_ aurie: Aurie) {
        auries.append(aurie)
        saveAuries()
        if settings.featuredAurieId == nil {
            settings.featuredAurieId = aurie.id   // first hatch becomes featured
        }
        // Set HERE, not in commitHatch: this is the single seam every Aurie
        // enters the collection through, so the greeting system's
        // "first Aurie has hatched" is true for every path that produces
        // one. Never cleared.
        if !settings.hasHatchedFirstAurie { settings.hasHatchedFirstAurie = true }
        WidgetExporter.exportFeatured(featured)
    }

    /// Replace a saved Aurie in place (matched by id) — the persistence
    /// seam for charm equip/unequip and future edits. Unknown ids are a
    /// no-op: never resurrect a deleted creature by "updating" it.
    func update(_ aurie: Aurie) {
        guard let i = auries.firstIndex(where: { $0.id == aurie.id })
        else { return }
        auries[i] = aurie
        saveAuries()
        if settings.featuredAurieId == aurie.id {
            WidgetExporter.exportFeatured(featured)
        }
    }

    func setFeatured(_ aurie: Aurie) {
        settings.featuredAurieId = aurie.id
        WidgetExporter.exportFeatured(featured)
    }

    func delete(_ aurie: Aurie) {
        auries.removeAll { $0.id == aurie.id }
        saveAuries()
        if settings.featuredAurieId == aurie.id {
            settings.featuredAurieId = auries.first?.id
        }
        if let name = aurie.sourceThumbnail {
            try? FileManager.default.removeItem(at: Self.thumbsDirectory.appendingPathComponent(name))
        }
        if worries[aurie.id] != nil {
            worries[aurie.id] = nil
            save(worries, to: Self.worriesURL)
        }
        // Replacement (the app's existing fallback rule) or the empty state.
        WidgetExporter.exportFeatured(featured)
    }

    // MARK: - Thumbnails ("never store the user's photo", §2)

    /// Saves a small square crop of the photo and returns its filename for
    /// `Aurie.sourceThumbnail`. The full photo is never written anywhere.
    func saveThumbnail(_ image: UIImage, for aurieId: String) -> String? {
        let side: CGFloat = 256
        let scale = max(side / image.size.width, side / image.size.height)
        let scaled = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        // Render at exactly 256 PHYSICAL pixels: the default renderer format
        // inherits the screen scale (3x -> a 768px file), so pin it to 1.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: side, height: side),
                                            format: format).image { _ in
            image.draw(in: CGRect(x: (side - scaled.width) / 2, y: (side - scaled.height) / 2,
                                  width: scaled.width, height: scaled.height))
        }
        guard let data = thumb.jpegData(compressionQuality: 0.8) else { return nil }
        let name = "\(aurieId).jpg"
        do {
            try data.write(to: Self.thumbsDirectory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            print("Store: failed to save thumbnail: \(error)")
            return nil
        }
    }

    func thumbnail(for aurie: Aurie) -> UIImage? {
        guard let name = aurie.sourceThumbnail else { return nil }
        return UIImage(contentsOfFile: Self.thumbsDirectory.appendingPathComponent(name).path)
    }

    #if DEBUG
    /// Demo tools only: wipe the collection (and worries/thumbnails).
    func debugClearCollection() {
        for aurie in auries { delete(aurie) }
        settings.featuredAurieId = nil
    }
    #endif

    // MARK: - Files

    /// Shared with WalletService (wallet.json lives beside the collection).
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Auries", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private static let auriesURL = directory.appendingPathComponent("auries.json")
    private static let settingsURL = directory.appendingPathComponent("settings.json")
    private static let worriesURL = directory.appendingPathComponent("worries.json")
    private static let thumbsDirectory: URL = {
        let dir = directory.appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func save(_ value: some Encodable, to url: URL) {
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            // Persistence failure shouldn't crash play; the collection lives on
            // in memory and the next successful save catches up.
            print("Store: failed to save \(url.lastPathComponent): \(error)")
        }
    }
}
