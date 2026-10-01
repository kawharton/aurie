import CoreGraphics
import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#endif

/// On-device object recognition (§10): VNClassifyImageRequest's top label +
/// confidence, bucketed into an ObjectCategory via the lookup table below.
/// Labels that match a hero keyword are canonicalized to the hero's exact
/// label in aurie_content.json ("teddy bear" -> "teddy") so Layer 3 fires.
/// Anything unmapped returns category .unknown — the generator then keeps the
/// creature pure Layer 1, which is never a failure.
enum Recognition {

    #if canImport(UIKit)
    /// Async wrapper for the app: runs Vision off the main actor.
    nonisolated static func classify(_ image: UIImage) async -> RecognizedObject? {
        guard let cg = image.cgImage else { return nil }
        return classify(cgImage: cg, orientation: cgOrientation(of: image))
    }

    private nonisolated static func cgOrientation(of image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
    #endif

    /// Core, UIKit-free (also compiled by the macOS verification script).
    nonisolated static func classify(cgImage: CGImage,
                                     orientation: CGImagePropertyOrientation = .up) -> RecognizedObject? {
        // NOTE: VNClassifyImageRequest fails on the iOS Simulator ("Failed to
        // create espresso context") because the neural backend can't init
        // there — so recognition always returns nil in the Simulator and every
        // hatch reads "a mysterious shape". It works on macOS and on real
        // devices. Test recognition/Layers 2-3 on a device, not the Simulator.
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        try? handler.perform([request])
        guard let results = request.results, !results.isEmpty else { return nil }
        let ranked = results.sorted { $0.confidence > $1.confidence }
            .map { (identifier: $0.identifier, confidence: $0.confidence) }
        #if DEBUG
        // AURIE_RECOG_TRACE=1 — dump the classifier's whole ranked head to
        // STDOUT (not NSLog, which `devicectl --console` cannot see), so a
        // miss on a real device can be read directly instead of guessed at.
        if ProcessInfo.processInfo.environment["AURIE_RECOG_TRACE"] == "1" {
            let head = ranked.prefix(10)
                .map { "\($0.identifier)(\(String(format: "%.2f", $0.confidence)))" }
                .joined(separator: " ")
            print("AURIE_TRACE \(head)")
            fflush(stdout)
        }
        #endif
        let picked = select(from: ranked,
                            gate: AurieGenerator.recognitionConfidenceThreshold)
        if let top = ranked.first, let picked {
            // Diagnostic (2026-09-13): shows when the scan rescued a mappable
            // label that the old top-only rule would have discarded.
            #if DEBUG
            if ProcessInfo.processInfo.environment["AURIE_RECOG_TRACE"] == "1" {
                print("AURIE_TRACE -> selected '\(picked.label ?? "-")' "
                      + "[\(picked.category.rawValue)] "
                      + "body=\(AurieGenerator.hintedBody(for: picked.label)?.rawValue ?? "none")")
                fflush(stdout)
            }
            NSLog("AURIE RECOG top raw '%@' (%.2f) -> selected '%@' (%.2f) -> %@",
                  top.identifier, top.confidence, picked.label ?? "-",
                  picked.confidence, picked.category.rawValue)
            #endif
        }
        return picked
    }

    /// Selection core — Vision-free and pure, so it can be exercised
    /// off-device.
    ///
    /// 2026-09-13: instead of mapping ONLY the top label, scan the results
    /// in descending confidence and take the first one that maps to a hero
    /// object or category keyword AND clears the generator's confidence
    /// gate (scanning below the gate would select labels the generator
    /// immediately discards, changing the log but not the creature). If no
    /// mapped result clears the gate, fall back to exactly the previous
    /// behavior for the top label — mapped-or-.unknown — so every outcome
    /// the old rule produced is preserved.
    /// How close a specific hero must be to the best mapped result before it
    /// may displace it. 0.9 keeps the near-ties Vision produces for a label
    /// it is confident about, and rejects a long-shot guess further down.
    static let specificOverrideRatio: Float = 0.9

    /// How close a mapped label must be to the classifier's OWN top answer
    /// before we believe it. Guards the case where Vision is confident about
    /// something we do not model and a weak, distant guess gets promoted.
    static let relevanceRatio: Float = 0.9

    nonisolated static func select(
        from ranked: [(identifier: String, confidence: Float)],
        gate: Float
    ) -> RecognizedObject? {
        guard let top = ranked.first else { return nil }
        // 2026-09-26 SPECIFIC-FIRST. Vision's classifier returns a whole
        // taxonomy branch at near-identical confidence — a photo of a pear
        // scores food(0.97) fruit(0.97) pear(0.97), a mug scores
        // tableware(0.84) utensil(0.84) mug(0.84). Taking the first mapped
        // result by confidence therefore kept the GENERIC ancestor and threw
        // the specific object away, which is why "pear" never reached the
        // generator. So: sweep once for a result that resolves to a named
        // hero, and only then fall back to the by-confidence sweep that
        // accepts a category-only match.
        // RELEVANCE FLOOR (2026-09-26). A mapped label is only believable if
        // the classifier itself rates it near its OWN best answer. A photo of
        // a paper-towel roll really returns:
        //
        //   structure(0.88) wood_processed(0.87) document(0.65) book(0.65) …
        //
        // Vision has no paper-towel class, so its confident answers are ones
        // we do not model, and "book" is a distant fourth. Without this floor
        // the scan walked past the two strong unknowns and announced "book" —
        // confidently wrong, which is worse than admitting ignorance, because
        // .unknown is a SUPPORTED outcome (pure Layer 1, "a mysterious
        // shape") while a wrong hero also mis-assigns a Birth Charm.
        let floorFromTop = top.confidence * Self.relevanceRatio
        let usable = max(gate, floorFromTop)
        var best: (r: (identifier: String, confidence: Float),
                   hit: (label: String, category: ObjectCategory,
                         isHero: Bool))?
        for r in ranked where r.confidence >= usable {
            if let hit = mapped(r.identifier) { best = (r, hit); break }
        }
        // A specific hero may displace it ONLY if it is roughly as confident.
        // Vision ties the branch it is sure about — pear(0.97) sits level
        // with food(0.97), mug(0.84) with tableware(0.84) — so a real
        // specific match costs nothing in confidence. Without this margin
        // ANY hero above the gate won, and a roll of paper towels came back
        // "book" because book(low) outranked paper(high) merely by being a
        // hero. Ratio, not a fixed delta, so it holds at every scale.
        if let best, !best.hit.isHero {
            let floor = best.r.confidence * Self.specificOverrideRatio
            for r in ranked where r.confidence >= max(usable, floor) {
                if let hit = mapped(r.identifier), hit.isHero {
                    return RecognizedObject(label: hit.label,
                                            category: hit.category,
                                            confidence: r.confidence)
                }
            }
        }
        if let best {
            return RecognizedObject(label: best.hit.label,
                                    category: best.hit.category,
                                    confidence: best.r.confidence)
        }
        return RecognizedObject(label: normalize(top.identifier),
                                category: .unknown,
                                confidence: top.confidence)
    }

    private nonisolated static func normalize(_ identifier: String) -> String {
        identifier.lowercased().replacingOccurrences(of: "_", with: " ")
    }

    private nonisolated static func mapped(_ identifier: String)
        -> (label: String, category: ObjectCategory, isHero: Bool)? {
        let normalized = normalize(identifier)
        let words = normalized.split(separator: " ").map(fold)
        for entry in table {
            if entry.keywords.contains(where: { matches(words, $0) }) {
                return (entry.hero ?? normalized, entry.category,
                        entry.hero != nil)
            }
        }
        return nil
    }

    /// Light plural fold so "apples"/"headphones" still meet their
    /// keyword. Applied to BOTH sides of the comparison, so s-final
    /// keywords ("scissors", "pliers") keep matching themselves.
    private nonisolated static func fold(_ word: Substring) -> Substring {
        word.count > 3 && word.hasSuffix("s") ? word.dropLast() : word
    }

    /// WHOLE-WORD phrase match (2026-09-18, replaces `contains`): the
    /// keyword must appear as complete word(s) of the label — "teddy"
    /// in "teddy bear", "granny smith" in "granny smith apple" — and
    /// never inside another word. The old substring rule canonicalized
    /// "pineapple" to hero "apple"; Birth Charms turned that from a
    /// cosmetic mislabel into a wrong PERMANENT unlock, so unrelated
    /// words containing an object name must fail here and degrade to
    /// `.unknown` like any unmapped label.
    private nonisolated static func matches(_ words: [Substring],
                                            _ keyword: String) -> Bool {
        let kw = keyword.split(separator: " ").map(fold)
        guard !kw.isEmpty, words.count >= kw.count else { return false }
        return (0 ... words.count - kw.count).contains { i in
            zip(words[i ..< i + kw.count], kw).allSatisfy { $0 == $1 }
        }
    }

    // MARK: - Label -> category table (first match wins)
    //
    // 2026-09-26: the generic rows were widened substantially. Their job is
    // no longer only to bucket a label into an ObjectCategory — a label that
    // lands in ANY row escapes category .unknown, which is what lets
    // AurieGenerator.bodyHint see it. A word absent from every row can never
    // reach the body table, however good the hint would be.
    //
    // Hero rows come first so their exact labels survive canonicalization;
    // the generic rows below just pick the Layer-2 category. Grow this table
    // freely — unmapped labels degrade safely to .unknown.
    private nonisolated static let table: [(keywords: [String], category: ObjectCategory, hero: String?)] = [
        // The ten curated hero objects (labels must match aurie_content.json)
        (["banana"], .food, "banana"),
        (["apple", "granny smith"], .food, "apple"),
        (["flower", "rose", "daisy", "sunflower", "tulip", "orchid", "blossom"], .plant, "flower"),
        (["mug"], .container, "mug"),
        (["cup", "teacup"], .container, "cup"),
        (["book", "notebook"], .paper, "book"),
        (["key"], .metal, "key"),
        (["phone", "cellular telephone", "smartphone", "iphone"], .tech, "phone"),
        (["backpack", "knapsack", "rucksack"], .fabric, "backpack"),
        // Vision labels a teddy bear "stuffed_animals", never "teddy", so
        // the hero needs its classifier-facing synonyms (2026-09-26).
        (["teddy", "stuffed animal", "plush", "plushie"], .toy, "teddy"),
        // D2 Birth-Charm heroes (approved 2026-09-19): promoted from
        // the generic rows below so their labels are CANONICAL (the
        // keywords already matched; only the emitted label stabilises).
        // Whole-word matching unchanged. Cake sits BEFORE carrot on
        // purpose: "carrot cake" resolves to Cake (approved). "beach
        // ball" is a deliberate PHRASE hero — generic "ball" stays
        // un-promoted so tennis/soccer balls never earn the Beach Ball
        // charm. Orange is intentionally NOT a hero: it doubles as a
        // colour word and would false-positive.
        (["strawberry"], .food, "strawberry"),
        (["lemon"], .food, "lemon"),
        (["cake"], .food, "cake"),
        (["carrot"], .food, "carrot"),
        (["cookie"], .food, "cookie"),
        (["balloon"], .toy, "balloon"),
        (["beach ball"], .toy, "beach ball"),
        // Added 2026-09-20 so Tomato can be a Birth Charm. "tomato" had
        // NO keyword at all before this — not even in the generic food
        // row — so nothing could ever emit it. Unlike "orange" (see the
        // note above) it is not also a colour word, so promoting it
        // carries no false-positive risk.
        (["tomato"], .food, "tomato"),
        // 2026-09-26: rows added so AurieGenerator.bodyHint is REACHABLE
        // from a real photo. Without a row here the label falls through to
        // category .unknown, the Layer 2 gate blocks, and the body nudge
        // can never fire — which is exactly what happened to pear and
        // heart. Canonicalizing to an exact hero label also means
        // "bartlett pear" and "heart shaped pillow" still resolve.
        (["pear"], .food, "pear"),
        // Promoted out of the generic container row so the specific-first
        // sweep can see it: Vision ranks container(0.23) above bottle(0.21).
        (["bottle", "thermos", "flask", "canteen"], .container, "bottle"),
        // A canned drink is one of the most obvious things to photograph
        // and nothing matched it (2026-09-26): Vision offers soda / soft
        // drink / beverage / cola long before the bare word "can".
        (["soda", "soft drink", "soda can", "cola", "beverage", "drink",
          "juice", "energy drink", "tin can", "aluminum can",
          "aluminium can", "beer"], .container, "can"),
        (["egg"], .food, "egg"),
        (["heart"], .fabric, "heart"),
        // Generic category buckets
        (["pizza", "sandwich", "orange", "strawberry", "lemon", "broccoli", "carrot",
          "cake", "cookie", "bread", "fruit", "vegetable", "produce", "food",
         "almond", "asparagus", "aubergine", "avocado", "bagel", "baguette", "biscuit", "burger", "celery", "cherry", "chili", "coconut", "cone", "corn", "cucumber", "cupcake", "donut", "doughnut", "eggplant", "fig", "gourd", "grapefruit", "hamburger", "ice cream", "icecream", "kiwi", "leek", "lime", "loaf", "mango", "meatball", "melon", "muffin", "nut", "olive", "onion", "pancake", "papaya", "peach", "pepper", "pie", "plum", "potato", "pumpkin", "squash", "walnut", "watermelon", "zucchini"], .food, nil),
        (["plant", "tree", "leaf", "cactus", "fern", "bouquet", "succulent", "flora",
         "bamboo", "petal", "pine cone", "pinecone"], .plant, nil),
        (["toy", "ball", "balloon", "doll", "lego", "kite", "puzzle", "dice",
          "stuffed", "plush",
         "bubble", "football", "globe", "marble", "puppet", "rugby ball"], .toy, nil),
        (["computer", "laptop", "keyboard", "monitor", "mouse", "remote", "television",
          "screen", "headphone", "earphone", "tablet", "camera", "console",
          "electronic", "appliance",
         "bulb", "lightbulb"], .tech, nil),
        (["shirt", "sweater", "jacket", "towel", "blanket", "pillow", "sock", "jean",
          "scarf", "hat", "glove", "cloth", "fabric", "bag", "shoe", "sneaker",
          "footwear", "clothing", "textile", "apparel",
         "cushion", "handbag", "hoodie", "mitten", "purse"], .fabric, nil),
        (["hammer", "screwdriver", "wrench", "scissors", "drill", "saw", "pliers",
          "tool", "brush", "tape measure",
         "crayon", "marker", "pen", "pencil", "toothbrush"], .tool, nil),
        (["paper", "envelope", "magazine", "newspaper", "card", "letter", "folder",
          "document", "notepad"], .paper, nil),
        // "tableware"/"drinkware" are what Vision returns for real mugs & cups.
        (["bottle", "jar", "vase", "bowl", "box", "basket", "bucket", "container",
          "jug", "tin", "carton", "pot", "tableware", "drinkware", "dishware",
          "crockery", "glassware", "plate", "dish",
         "barrel", "can", "pitcher", "saucer", "teapot"], .container, nil),
        (["coin", "spoon", "fork", "knife", "pan", "kettle", "ring", "chain",
          "nail", "screw", "metal", "cutlery", "utensil",
         "pebble", "rock", "stone"], .metal, nil),
    ]
}
