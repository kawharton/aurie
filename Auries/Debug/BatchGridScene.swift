#if DEBUG
import CoreImage
import SpriteKit
import SwiftUI

/// Stage 3 QA harness — DEBUG ONLY.
///
/// Generates a batch with the REAL `AurieGenerator` (random photo signals and
/// colours, so body / family / colour / limbs / weighted base expression all
/// come from the shipping code paths) and lays them out in a grid of real
/// `AurieNode`s. One screenshot then covers every active body, which is both
/// the contact sheet and a worst-case memory/node stress test.
///
/// Nothing here is a mock: same generator, same node, same Blender skin, same
/// tint shader as Home.
final class BatchGridScene: SKScene {

    var count = 40
    private(set) var roster: [Aurie] = []

    override func didMove(to view: SKView) {
        backgroundColor = ProcessInfo.processInfo
            .environment["AURIE_BATCH_ICON"] == "1"
            // A deep teal that the tide aura sits on cleanly, so a square
            // crop of the render needs no compositing afterwards.
            ? SKColor(red: 0.055, green: 0.115, blue: 0.145, alpha: 1)
            : SKColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)
        scaleMode = .aspectFit
        var rng = SystemRandomNumberGenerator()
        guard let content = ContentService.content else {
            NSLog("AURIE_BATCH content not loaded"); return
        }

        // AURIE_BACK_PROOF: Round front/back orientation proof
        // (2026-09-14). Three fixed pairs (tuft / hair_00 / hair_01)
        // shown FRONT|BACK from the real 3D-exported back layers, plus
        // one node that swaps orientation in place every 1.5 s —
        // proving front assets -> orientation change -> back assets
        // with no position/scale jump. Round-only, DEBUG-only.
        if ProcessInfo.processInfo.environment["AURIE_BACK_PROOF"] == "1" {
            buildBackProof(content: content)
            return
        }

        // AURIE_BATCH_ONE_PER_BODY: force coverage of all ten launch bodies
        // (a random roster can miss one, as the first 40-run did for tall).
        let forced = ProcessInfo.processInfo
            .environment["AURIE_BATCH_ONE_PER_BODY"] == "1"
            ? BodyType.launchPool : []
        func fresh() -> Aurie {
            let shape = ShapeSignal(
                aspectRatio: Float.random(in: 0.55...1.7, using: &rng),
                roundness: Float.random(in: 0.15...0.95, using: &rng))
            let colour = Rgb(Int.random(in: 40...230, using: &rng),
                             Int.random(in: 40...230, using: &rng),
                             Int.random(in: 40...230, using: &rng))
            return AurieGenerator.generate(
                dominantColor: colour, shape: shape, recognized: nil,
                existingNames: Set(roster.map(\.name)), content: content)
        }
        // AURIE_BATCH_EXTREMES: the compatibility-boundary sheet. Per launch
        // body, one row: shortest-compatible arms+legs, longest-compatible
        // arms+legs, then one cell per wearable hair style on the default
        // limbs. Heart (fewer wearable hairs) sits last so rows stay aligned.
        // AURIE_BATCH_BODIES=round,tall — optional body subset, for zoomed
        // inspection sheets where 76 cells would be too small to judge.
        let bodyFilter: Set<BodyType> = {
            guard let csv = ProcessInfo.processInfo
                .environment["AURIE_BATCH_BODIES"] else { return [] }
            return Set(csv.split(separator: ",")
                .compactMap { BodyType(rawValue: String($0)) })
        }()
        // AURIE_BATCH_HAIRSHOW: Gallery A — ONE fixed body, colour, face
        // and limb set; only the hairstyle changes cell to cell, so the
        // styles can be compared directly under identical conditions.
        if ProcessInfo.processInfo
            .environment["AURIE_BATCH_HAIRSHOW"] == "1" {
            let body = bodyFilter.first ?? .round
            // Shows whatever the launch pool currently allows.
            for hairdo in AurieLimbCatalog.compatibleHair(for: body) {
                var a = fresh()
                a.body = body
                a.family = .tide
                a.baseColor = Rgb(122, 168, 228)
                a.auraColor = AurieGenerator.auraColors[.tide] ?? a.auraColor
                a.baseExpression = .happy
                a.pattern = PatternType.none
                a.armStyle = "arm_00"
                a.legStyle = "leg_00"
                a.hairStyle = hairdo
                roster.append(a)
            }
            count = roster.count
        } else if ProcessInfo.processInfo
            .environment["AURIE_BATCH_ICON"] == "1" {
            // APP-ICON CANDIDATES. One creature per launch body in a single
            // soft blue, all wearing the same happy face and clean belly, so
            // the only thing differing cell to cell is the SILHOUETTE — which
            // is what has to carry an icon at 60pt. Same palette the hair
            // gallery uses, so candidates match shipped art rather than being
            // a one-off tint.
            //
            // AURIE_BATCH_COLS=1 with AURIE_BATCH_BODIES=<one> renders a
            // single candidate large enough to crop for the 1024 asset.
            // AURIE_BATCH_ICON_LIMBS=1 — instead of one cell per body, show
            // one BODY wearing every arm/leg pairing worth considering, so
            // limb choices can be compared under identical conditions.
            // Honours the roller's rule that long arms only accompany long
            // legs, even though setting styles directly would bypass it.
            let limbMode = ProcessInfo.processInfo
                .environment["AURIE_BATCH_ICON_LIMBS"] == "1"
            let iconBody = bodyFilter.first ?? .round
            let combos: [(String, String)] = limbMode
                ? [("arm_02", "leg_04"), ("arm_02", "leg_05"),
                   ("arm_01", "leg_04"), ("arm_01", "leg_05"),
                   ("arm_00", "leg_04"), ("arm_01", "leg_00")]
                : []
            for (armS, legS) in combos {
                var a = fresh()
                a.body = iconBody
                a.family = .tide
                a.baseColor = Rgb(122, 168, 228)
                a.auraColor = AurieGenerator.auraColors[.tide] ?? a.auraColor
                a.baseExpression = .happy
                a.pattern = PatternType.none
                a.armStyle = armS
                a.legStyle = legS
                if let hair = AurieLimbCatalog.compatibleHair(for: iconBody).first {
                    a.hairStyle = hair
                }
                roster.append(a)
            }
            for body in BodyType.launchPool
            where !limbMode && (bodyFilter.isEmpty || bodyFilter.contains(body)) {
                var a = fresh()
                a.body = body
                a.family = .tide
                a.baseColor = Rgb(122, 168, 228)
                a.auraColor = AurieGenerator.auraColors[.tide] ?? a.auraColor
                a.baseExpression = .happy
                a.pattern = PatternType.none
                // arm_01 "Tiny Hands" (.short) — the stubby arms that end in
                // actual hands. arm_00 is the Rounded Flipper, which reads as
                // a nub at icon size.
                // AURIE_BATCH_ICON_ARM / _LEG override the defaults so a
                // chosen pairing can be rendered on its own for capture.
                a.armStyle = ProcessInfo.processInfo
                    .environment["AURIE_BATCH_ICON_ARM"] ?? "arm_01"
                a.legStyle = ProcessInfo.processInfo
                    .environment["AURIE_BATCH_ICON_LEG"] ?? "leg_00"
                if let hair = AurieLimbCatalog.compatibleHair(for: body).first {
                    a.hairStyle = hair
                }
                roster.append(a)
            }
            count = roster.count
        } else if ProcessInfo.processInfo
            .environment["AURIE_BATCH_EXTREMES"] == "1" {
            func byLength(_ ids: [String], _ rank: [String: Int]) -> [String] {
                ids.sorted { (rank[$0] ?? 9, $0) < (rank[$1] ?? 9, $1) }
            }
            for body in BodyType.launchPool
            where bodyFilter.isEmpty || bodyFilter.contains(body) {
                let arms = byLength(
                    AurieLimbCatalog.compatibleArms(for: body),
                    AurieLimbCatalog.armLength.mapValues(\.rawValue))
                let legs = byLength(
                    AurieLimbCatalog.compatibleLegs(for: body),
                    AurieLimbCatalog.legLength.mapValues(\.rawValue))
                let hairs = AurieLimbCatalog.compatibleHair(for: body)
                var cells = [(arms.first!, legs.first!, "tuft"),
                             (arms.last!, legs.last!, "tuft")]
                cells += hairs.map { ("arm_00", "leg_00", $0) }
                for (arm, leg, hairdo) in cells {
                    var a = fresh()
                    a.body = body
                    a.armStyle = arm
                    a.legStyle = leg
                    a.hairStyle = hairdo
                    roster.append(a)
                }
            }
            count = roster.count
        } else {
            for i in 0..<count {
                var made = fresh()
                if i < forced.count {
                    // Forcing the body AFTER generation can leave parts the
                    // real generator would never pair with it (it rolls from
                    // body-compatible pools). Sanitize to the same rules.
                    made.body = forced[i]
                    if !AurieLimbCatalog.compatibleArms(for: made.body)
                        .contains(made.resolvedArmStyle) {
                        made.armStyle = "arm_00"
                    }
                    if !AurieLimbCatalog.compatibleLegs(for: made.body)
                        .contains(made.resolvedLegStyle) {
                        made.legStyle = "leg_00"
                    }
                    // The generator also gates LONG arms on LONG legs;
                    // mirror it so forced cells only show real pairings.
                    if AurieLimbCatalog.armLength[made.resolvedArmStyle]
                        == .long,
                       (AurieLimbCatalog.legLength[made.resolvedLegStyle]
                        ?? .standard) < .long {
                        made.armStyle = "arm_00"
                    }
                    if !AurieLimbCatalog.compatibleHair(for: made.body)
                        .contains(made.resolvedHairStyle) {
                        made.hairStyle = "tuft"
                    }
                }
                roster.append(made)
            }
        }

        // AURIE_BATCH_ICON_BG=<family> puts that family's painting behind the
        // candidates, so an icon can be judged (and captured) against the
        // real environment art rather than a flat ground.
        if let fam = ProcessInfo.processInfo
            .environment["AURIE_BATCH_ICON_BG"],
           let art = UIImage(named: "\(fam)_env_sky") {
            // BACKGROUND TREATMENT for icon legibility. At 60pt the painting's
            // palms and rocks compete with the creature, so the capture can
            // push the environment back: _BG_BLUR is a gaussian radius,
            // _BG_DIM a flat black veil (0…1) and _BG_VIG an edge vignette
            // (0…1). All render in-scene, so the aura still composites over
            // the treated backdrop instead of being pasted on afterwards.
            func num(_ key: String, _ fallback: Double) -> CGFloat {
                CGFloat(Double(ProcessInfo.processInfo
                    .environment[key] ?? "") ?? fallback)
            }
            let blurR = num("AURIE_BATCH_ICON_BG_BLUR", 0)
            let dim = num("AURIE_BATCH_ICON_BG_DIM", 0)
            let vig = num("AURIE_BATCH_ICON_BG_VIG", 0)
            // Blurring through an SKEffectNode rasterizes the full-size
            // painting and blows past Metal's 8192 texture limit, so blur a
            // downsampled copy up front and use a plain sprite.
            let plate = blurR > 0
                ? Self.blurredPlate(art, radius: blurR) : art
            let bg = SKSpriteNode(texture: SKTexture(image: plate))
            let t = bg.texture!.size()
            let sc = max(size.width / t.width, size.height / t.height)
            bg.setScale(sc)
            // WHICH PART of a portrait painting lands behind the creature.
            // Aspect-fill crops to a slice and centring picks the middle —
            // for Tide that is bare sand, not the sunset.
            // AURIE_BATCH_ICON_BG_F is the image fraction (0 top … 1 bottom)
            // to centre on, clamped so the art never uncovers an edge.
            let fRaw = ProcessInfo.processInfo
                .environment["AURIE_BATCH_ICON_BG_F"] ?? ""
            let f = CGFloat(Double(fRaw) ?? 0.30)
            let slack = max(0, (t.height * sc - size.height) / 2)
            let dy = min(slack, max(-slack, t.height * sc * (f - 0.5)))
            bg.position = CGPoint(x: size.width / 2,
                                  y: size.height / 2 + dy)
            bg.zPosition = -1000
            addChild(bg)
            // _BG_TINT=r,g,b,a (0…1) veils the painting in a colour rather
            // than flat black — how the DARK-appearance icon is graded to
            // night without repainting the environment art. Falls back to
            // _BG_DIM's black veil when unset.
            let tintRaw = (ProcessInfo.processInfo
                .environment["AURIE_BATCH_ICON_BG_TINT"] ?? "")
                .split(separator: ",").compactMap { Double($0) }
            if tintRaw.count == 4 {
                let veil = SKSpriteNode(
                    color: SKColor(red: CGFloat(tintRaw[0]),
                                   green: CGFloat(tintRaw[1]),
                                   blue: CGFloat(tintRaw[2]), alpha: 1),
                    size: size)
                veil.alpha = CGFloat(min(1, max(0, tintRaw[3])))
                veil.position = CGPoint(x: size.width / 2,
                                        y: size.height / 2)
                veil.zPosition = -960
                addChild(veil)
            } else if dim > 0 {
                let veil = SKSpriteNode(color: .black, size: size)
                veil.alpha = min(1, dim)
                veil.position = CGPoint(x: size.width / 2,
                                        y: size.height / 2)
                veil.zPosition = -960
                addChild(veil)
            }
            if vig > 0 {
                let side = max(size.width, size.height)
                let r = UIGraphicsImageRenderer(
                    size: CGSize(width: side, height: side))
                let img = r.image { ctx in
                    let c = ctx.cgContext
                    let cols = [UIColor.black.withAlphaComponent(0).cgColor,
                                UIColor.black.withAlphaComponent(
                                    min(1, vig)).cgColor] as CFArray
                    guard let g = CGGradient(
                        colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: cols,
                        locations: [0.28, 1.0]) else { return }
                    let mid = CGPoint(x: side / 2, y: side / 2)
                    c.drawRadialGradient(
                        g, startCenter: mid, startRadius: 0,
                        endCenter: mid, endRadius: side * 0.72,
                        options: [.drawsAfterEndLocation])
                }
                let v = SKSpriteNode(texture: SKTexture(image: img))
                v.size = CGSize(width: side, height: side)
                v.position = CGPoint(x: size.width / 2, y: size.height / 2)
                v.zPosition = -950
                addChild(v)
            }
        }

        let cols = ProcessInfo.processInfo
            .environment["AURIE_BATCH_COLS"].flatMap(Int.init) ?? 8
        let rows = (count + cols - 1) / cols
        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rows)
        var scale = min(cellW / 420, cellH / 460)
        // ICON FRAMING. The grid's cell fit is wrong for a single candidate
        // that has to fill a 1024 square: AURIE_BATCH_ICON_SCALE sets the node
        // scale outright and AURIE_BATCH_ICON_Y its height as a fraction of
        // the scene (0 bottom … 1 top), so framing can be iterated from the
        // command line without another build.
        let iconSingle = ProcessInfo.processInfo
            .environment["AURIE_BATCH_ICON"] == "1" && roster.count == 1
        if iconSingle {
            let sRaw = ProcessInfo.processInfo
                .environment["AURIE_BATCH_ICON_SCALE"] ?? ""
            scale = CGFloat(Double(sRaw) ?? 3.0)
        }
        let iconY: CGFloat = {
            let raw = ProcessInfo.processInfo
                .environment["AURIE_BATCH_ICON_Y"] ?? ""
            return CGFloat(Double(raw) ?? 0.46)
        }()

        for (i, aurie) in roster.enumerated() {
            let node = AurieNode(
                textures: AssetLoader.textures(for: aurie),
                baseColor: SKColor(red: CGFloat(aurie.baseColor.r) / 255,
                                   green: CGFloat(aurie.baseColor.g) / 255,
                                   blue: CGFloat(aurie.baseColor.b) / 255,
                                   alpha: 1),
                auraColor: SKColor(red: CGFloat(aurie.auraColor.r) / 255,
                                   green: CGFloat(aurie.auraColor.g) / 255,
                                   blue: CGFloat(aurie.auraColor.b) / 255,
                                   alpha: 1),
                body: aurie.body,
                armStyle: aurie.resolvedArmStyle,
                legStyle: aurie.resolvedLegStyle,
                hairStyle: aurie.resolvedHairStyle,
                patternLayer: aurie.patternMaskLayer,
                // Same capture aid as the back-proof grid: the whole
                // roster wears AURIE_BELLY_PROOF=<id> through the
                // production sticker path (2D sticker review needs it
                // on varied colors/patterns, not one fixed tint).
                bellyStickerCharmID: ProcessInfo.processInfo
                    .environment["AURIE_BELLY_PROOF"],
                auraCharmID: ProcessInfo.processInfo
                    .environment["AURIE_AURA_PROOF"],
                floatingCharmID: ProcessInfo.processInfo
                    .environment["AURIE_FLOAT_PROOF"])
            node.adoptBaseExpression(aurie.resolvedBaseExpression)
            node.setScale(scale)
            let r = i / cols, c = i % cols
            node.position = iconSingle
                ? CGPoint(x: size.width / 2, y: size.height * iconY)
                : CGPoint(x: cellW * (CGFloat(c) + 0.5),
                          y: size.height - cellH * (CGFloat(r) + 0.62))
            addChild(node)
            // AURIE_BATCH_SPLITS: every creature loops the split dance so a
            // couple of screenshots catch all of them mid-pose — the rig
            // check for hip-joint extension on every body/leg combination.
            if ProcessInfo.processInfo
                .environment["AURIE_BATCH_SPLITS"] == "1" {
                node.run(.repeatForever(.sequence([
                    .wait(forDuration: 0.6),
                    .run { [weak node] in
                        _ = node?.dance(.split, beat: 0.5, measures: 1)
                    },
                    .wait(forDuration: 5.0)])))
            }

            // Icon candidates are CAPTURED, not read — a caption under the
            // feet lands inside any square crop of the cell.
            if ProcessInfo.processInfo
                .environment["AURIE_BATCH_ICON"] == "1" { continue }

            let label = SKLabelNode(text: "\(aurie.body.rawValue) "
                                    + "\(aurie.resolvedBaseExpression.rawValue.prefix(4))")
            label.fontName = "Menlo"
            label.fontSize = 11
            label.fontColor = SKColor(white: 0.72, alpha: 1)
            label.position = CGPoint(x: node.position.x,
                                     y: node.position.y - cellH * 0.34)
            addChild(label)
            let hairTag = aurie.resolvedHairStyle == "tuft"
                ? "tf" : String(aurie.resolvedHairStyle.suffix(2))
            let sub = SKLabelNode(text: "\(aurie.family.rawValue) "
                                  + "a\(aurie.resolvedArmStyle.suffix(2))/"
                                  + "l\(aurie.resolvedLegStyle.suffix(2))/"
                                  + "h\(hairTag)")
            sub.fontName = "Menlo"
            sub.fontSize = 10
            sub.fontColor = SKColor(white: 0.5, alpha: 1)
            sub.position = CGPoint(x: node.position.x,
                                   y: label.position.y - 13)
            addChild(sub)
        }

        // Roster + coverage, so a missing body shows up in the log too.
        var perBody: [String: Int] = [:]
        var skins: [String: Int] = [:]
        for a in roster {
            perBody[a.body.rawValue, default: 0] += 1
            let skin = AurieBlenderSkin.isAvailable(a.body) ? "blender"
                                                           : "placeholder"
            skins[skin, default: 0] += 1
        }
        NSLog("AURIE_BATCH n=%d bodies=%@ skins=%@", roster.count,
              perBody.sorted { $0.key < $1.key }
                  .map { "\($0.key):\($0.value)" }.joined(separator: ","),
              skins.map { "\($0.key):\($0.value)" }.joined(separator: ","))
        var nodes = 0
        func walk(_ n: SKNode) { nodes += 1; n.children.forEach(walk) }
        walk(self)
        NSLog("AURIE_BATCH totalNodes=%d", nodes)
    }
}

extension BatchGridScene {
    /// Downsample to ~1200px wide and gaussian-blur, clamping the edges so
    /// the result stays opaque to its own border (a raw blur fades out and
    /// would ring the icon crop). DEBUG icon-capture aid only.
    static func blurredPlate(_ image: UIImage, radius: CGFloat) -> UIImage {
        let w: CGFloat = 1200
        let h = (image.size.height / max(1, image.size.width)) * w
        let small = UIGraphicsImageRenderer(
            size: CGSize(width: w, height: h)).image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        guard let ci = CIImage(image: small) else { return small }
        let clamped = ci.clampedToExtent()
        guard let blur = CIFilter(name: "CIGaussianBlur",
                                  parameters: [kCIInputImageKey: clamped,
                                               kCIInputRadiusKey: radius]),
              let out = blur.outputImage else { return small }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(out, from: ci.extent) else {
            return small
        }
        return UIImage(cgImage: cg)
    }

    /// Round front/back proof harness (see the env check in didMove).
    private func fixedRound(hair: String,
                            content: AurieContent) -> Aurie {
        var a = AurieGenerator.generate(
            dominantColor: Rgb(122, 168, 228),
            shape: ShapeSignal(aspectRatio: 1.0, roundness: 0.8),
            recognized: nil, existingNames: [], content: content)
        a.body = .round
        a.family = .tide
        a.baseColor = Rgb(122, 168, 228)
        a.auraColor = AurieGenerator.auraColors[.tide] ?? a.auraColor
        a.baseExpression = .happy
        a.pattern = PatternType.none
        a.armStyle = "arm_00"
        a.legStyle = "leg_00"
        a.hairStyle = hair
        return a
    }

    private func proofNode(_ a: Aurie,
                           _ o: AurieOrientation) -> AurieNode {
        let n = AurieNode(
            textures: AssetLoader.textures(for: a),
            baseColor: SKColor(red: CGFloat(a.baseColor.r) / 255,
                               green: CGFloat(a.baseColor.g) / 255,
                               blue: CGFloat(a.baseColor.b) / 255,
                               alpha: 1),
            auraColor: SKColor(red: CGFloat(a.auraColor.r) / 255,
                               green: CGFloat(a.auraColor.g) / 255,
                               blue: CGFloat(a.auraColor.b) / 255,
                               alpha: 1),
            body: a.body,
            armStyle: a.resolvedArmStyle,
            legStyle: a.resolvedLegStyle,
            hairStyle: a.resolvedHairStyle,
            patternLayer: a.patternMaskLayer,
            // DEBUG capture aid: the proof gallery wears the proof
            // backpack when AURIE_CHARM_PROOF=1, through the
            // production charm layer path. Permanent evidence tooling.
            charmLayers: ProcessInfo.processInfo
                .environment["AURIE_CHARM_PROOF"] == "1"
                ? ["charm_object_backpack_01"] : [],
            // DEBUG capture aid: the grid wears a belly sticker when
            // AURIE_BELLY_PROOF=<charm_id>, through the production path.
            bellyStickerCharmID: ProcessInfo.processInfo
                .environment["AURIE_BELLY_PROOF"],
            auraCharmID: ProcessInfo.processInfo
                .environment["AURIE_AURA_PROOF"],
            floatingCharmID: ProcessInfo.processInfo
                .environment["AURIE_FLOAT_PROOF"],
            orientation: o)
        n.setScale(0.62)
        return n
    }

    func buildBackProof(content: AurieContent) {
        // ALL-10 orientation gallery: one FRONT|BACK pair per launch
        // body through the real render path — hair rotates
        // tuft/hair_00/hair_01 (bodies where hair_01 is excluded fall
        // back via compatibleHair), pattern rotates the three
        // procedural masks so back-pattern continuity is visible.
        // AURIE_BATCH_BODIES=round,tall zooms a subset as usual.
        let bodyFilter: Set<BodyType> = {
            guard let csv = ProcessInfo.processInfo
                .environment["AURIE_BATCH_BODIES"] else { return [] }
            return Set(csv.split(separator: ",")
                .compactMap { BodyType(rawValue: String($0)) })
        }()
        let bodies = BodyType.launchPool.filter {
            bodyFilter.isEmpty || bodyFilter.contains($0)
        }
        // AURIE_BATCH_HAIR pins one style for a body x hair evidence
        // matrix (invalid styles still fall back via compatibleHair).
        let pinnedHair = ProcessInfo.processInfo
            .environment["AURIE_BATCH_HAIR"]
        let hairCycle = pinnedHair.map { [$0] }
            ?? ["hair_01", "hair_00", "tuft"]
        // stars/hearts joined 2026-09-18: their back masks now exist
        // (regenerated stamp tiles), so the proof cycles ALL patterns.
        let patternCycle: [PatternType] = [.stripes, .speckles, .spots,
                                           .stars, .hearts]
        let cols = 4                      // body pairs, two per row
        let pairW = size.width / CGFloat(cols / 2)
        let rows = (bodies.count + 1) / 2
        let rowH = size.height / CGFloat(rows)
        for (i, body) in bodies.enumerated() {
            var a = fixedRound(hair: hairCycle[i % hairCycle.count],
                               content: content)
            a.body = body
            if !AurieLimbCatalog.compatibleHair(for: body)
                .contains(a.resolvedHairStyle) {
                a.hairStyle = "hair_00"
            }
            a.pattern = patternCycle[i % patternCycle.count]
            let px = CGFloat(i % 2) * pairW
            let py = size.height - (CGFloat(i / 2) + 0.55) * rowH
            // A single-body subset is a zoom request: fill the pair
            // row so detail (charms, pattern seams) is inspectable.
            let zoom: CGFloat = bodies.count == 1 ? 1.05 : 0.34
            for (c, o) in [(0, AurieOrientation.front), (1, .back)] {
                let n = proofNode(a, o)
                n.setScale(zoom)
                n.position = CGPoint(
                    x: px + pairW * (c == 0 ? 0.28 : 0.66), y: py)
                addChild(n)
            }
            let label = SKLabelNode(
                text: "\(body.rawValue) \(a.resolvedHairStyle) "
                    + "\(a.pattern?.rawValue ?? "none")")
            label.fontName = "Menlo"
            label.fontSize = 22
            label.fontColor = SKColor(white: 0.72, alpha: 1)
            label.position = CGPoint(x: px + pairW * 0.47,
                                     y: py - rowH * 0.42)
            addChild(label)
        }
    }
}

struct BatchGridView: View {
    var body: some View {
        SpriteView(scene: {
            let s = BatchGridScene()
            s.count = Int(ProcessInfo.processInfo
                .environment["AURIE_BATCH_COUNT"] ?? "40") ?? 40
            // A SQUARE scene for icon capture: aspect-fit then renders a
            // full-width square band on the device, so the 1024 asset is a
            // straight crop-and-downscale with no upscaling.
            s.size = ProcessInfo.processInfo
                .environment["AURIE_BATCH_ICON"] == "1"
                ? CGSize(width: 2048, height: 2048)
                : CGSize(width: 2400, height: 1500)
            return s
        }())
        .ignoresSafeArea()
    }
}
#endif
