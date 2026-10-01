import Foundation

/// Loads the bundled `aurie_content.json` once at launch and holds it for the
/// whole app. Content is a bundled resource, so a load failure is a build
/// mistake (file missing from the target, or JSON no longer matching the
/// Codable shapes in AurieContent.swift) — fail fast and loudly.
enum ContentService {

    /// The app's content. Set by `loadBundled()` in the app delegate before
    /// any screen needs it.
    private(set) static var content: AurieContent!

    /// The daily feel-good pools (sayings, jokes, dares) shown on Home.
    private(set) static var daily: DailyLift!

    /// Calm Mode copy: per-family calm lines + Worry Jar hold/release lines.
    private(set) static var calm: CalmContent!

    static func loadBundled() {
        guard let url = Bundle.main.url(forResource: "aurie_content", withExtension: "json") else {
            fatalError("aurie_content.json is not in the app bundle — check target membership")
        }
        do {
            content = try AurieContent.load(from: url)
        } catch {
            fatalError("aurie_content.json failed to decode: \(error)")
        }

        guard let dailyURL = Bundle.main.url(forResource: "daily_content", withExtension: "json") else {
            fatalError("daily_content.json is not in the app bundle — check target membership")
        }
        do {
            daily = try DailyLift.load(from: dailyURL)
        } catch {
            fatalError("daily_content.json failed to decode: \(error)")
        }

        guard let calmURL = Bundle.main.url(forResource: "calm_content", withExtension: "json") else {
            fatalError("calm_content.json is not in the app bundle — check target membership")
        }
        do {
            calm = try CalmContent.load(from: calmURL)
        } catch {
            fatalError("calm_content.json failed to decode: \(error)")
        }
    }

    /// Human-readable proof the content is usable — touches every family and
    /// category lookup (the family accessor traps on a missing family).
    static var loadedSummary: String {
        let families = AuraFamily.allCases.count
        let names = AuraFamily.allCases.reduce(0) { $0 + content.family($1).names.count }
        let categories = ObjectCategory.allCases.filter { content.category($0) != nil }.count
        return "\(families) families · \(names) names · \(categories) categories"
    }
}
