import Foundation

// MARK: - Decoded shapes (mirror aurie_content.json)

public struct FamilyContent: Codable {
    public let family: String
    public let names: [String]
    public let nameSyllables: [String]
    public let lineTemplates: [String]   // may contain {name} and {mood}; Starlight has none
    public let moods: [String]           // fills {mood}; empty for Starlight
    public let shake: [String]           // family-flavoured shake reactions
    public let pet: [String]             // family-flavoured pet reactions
    public let traits: [String]          // personality adjectives; 3 chosen per creature
}

/// Play barks any creature can say (not tied to a family). Repeat freely.
public struct SharedPlay: Codable {
    public let tickle: [String]
    public let pickup: [String]
}

public struct CategoryContent: Codable {
    public let category: String
    public let headCharms: [Int]
    public let bellyPatterns: [Int]
    public let sideDetails: [Int]
    public let tailCharms: [Int]
    public let textures: [Int]
}

public struct HeroObject: Codable {
    public let label: String
    public let category: String
    public var headCharmId: Int?
    public var cheekMarkId: Int?
    public var bellyPatternId: Int?
    public var sideDetailId: Int?
    public var tailCharmId: Int?
    public var textureId: Int?

    func apply(to slots: inout DetailSlots) {
        if let v = headCharmId    { slots.headCharmId = v }
        if let v = cheekMarkId    { slots.cheekMarkId = v }
        if let v = bellyPatternId { slots.bellyPatternId = v }
        if let v = sideDetailId   { slots.sideDetailId = v }
        if let v = tailCharmId    { slots.tailCharmId = v }
        if let v = textureId      { slots.textureId = v }
    }
}

struct AurieContentData: Codable {
    let families: [FamilyContent]
    let sharedPlay: SharedPlay
    let categories: [CategoryContent]
    let heroes: [HeroObject]
}

// MARK: - Runtime content (fast lookups)

public final class AurieContent {
    public let sharedPlay: SharedPlay

    private let familyByName: [String: FamilyContent]
    private let categoryByName: [String: CategoryContent]
    private let heroByLabel: [String: HeroObject]

    init(_ d: AurieContentData) {
        sharedPlay = d.sharedPlay
        familyByName   = Dictionary(uniqueKeysWithValues: d.families.map { ($0.family, $0) })
        categoryByName = Dictionary(uniqueKeysWithValues: d.categories.map { ($0.category, $0) })
        heroByLabel    = Dictionary(uniqueKeysWithValues: d.heroes.map { ($0.label.lowercased(), $0) })
    }

    public func family(_ f: AuraFamily) -> FamilyContent { familyByName[f.rawValue]! }
    public func category(_ c: ObjectCategory) -> CategoryContent? { categoryByName[c.rawValue] }
    public func hero(_ label: String) -> HeroObject? { heroByLabel[label.lowercased()] }

    public static func load(from url: URL) throws -> AurieContent {
        let data = try Data(contentsOf: url)
        return AurieContent(try JSONDecoder().decode(AurieContentData.self, from: data))
    }
}
