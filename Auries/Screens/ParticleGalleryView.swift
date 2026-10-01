#if DEBUG
import SwiftUI
import SpriteKit

/// DEBUG-only particle showcase: every family's motifs and motion presets side
/// by side on a neutral dark stage with a sample Aurie, so the system can be
/// judged without replaying full animations. Never compiled into Release.
struct ParticleGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    // Capture aids, so every family/mode can be shot without tapping:
    // AURIE_PARTICLE_FAMILY=ember AURIE_PARTICLE_MODE=motifs
    @State private var family: AuraFamily =
        AuraFamily(rawValue: ProcessInfo.processInfo
            .environment["AURIE_PARTICLE_FAMILY"] ?? "") ?? .moss
    @State private var mode: ParticleGalleryScene.Mode =
        ParticleGalleryScene.Mode(rawValue: ProcessInfo.processInfo
            .environment["AURIE_PARTICLE_MODE"] ?? "") ?? .swirl
    @State private var scene: ParticleGalleryScene?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let scene {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .ignoresSafeArea()
                    .id("\(family.rawValue)-\(mode.rawValue)")
            }
            VStack {
                HStack {
                    Text("\(family.rawValue.capitalized) · \(mode.label)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 18)
                Spacer()
                Picker("Mode", selection: $mode) {
                    ForEach(ParticleGalleryScene.Mode.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                Picker("Family", selection: $family) {
                    ForEach(AuraFamily.allCases, id: \.self) {
                        Text($0.rawValue.prefix(2).capitalized).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { rebuild() }
        .onChange(of: family) { rebuild() }
        .onChange(of: mode) { rebuild() }
    }

    private func rebuild() {
        let s = ParticleGalleryScene(size: CGSize(width: 400, height: 800),
                                     family: family, mode: mode)
        s.scaleMode = .resizeFill
        scene = s
    }
}

/// The stage. One scene per (family, mode) so switching is a clean rebuild.
final class ParticleGalleryScene: SKScene {

    enum Mode: String, CaseIterable {
        case motifs, ambient, calm, celebration, swirl
        var label: String {
            switch self {
            case .motifs:      return "Art"
            case .ambient:     return "Ambient"
            case .calm:        return "Calm"
            case .celebration: return "Celebration"
            case .swirl:       return "Swirl"
            }
        }
    }

    private let family: AuraFamily
    private let mode: Mode
    private var field: ParticleField?
    private var creature: AurieNode?
    private var last: TimeInterval = 0

    init(size: CGSize, family: AuraFamily, mode: Mode) {
        self.family = family
        self.mode = mode
        super.init(size: size)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        scaleMode = .resizeFill
        backgroundColor = SKColor(white: 0.06, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func didMove(to view: SKView) {
        removeAllChildren()
        guard mode != .motifs else { return buildMotifSheet() }

        // A sample creature of this family, so particle depth can be judged
        // against a real silhouette.
        var sample = AurieGenerator.generate(
            dominantColor: Rgb(150, 150, 150),
            shape: ShapeSignal(aspectRatio: 1.0, roundness: 0.9),
            recognized: nil, existingNames: [], content: ContentService.content)
        sample.family = family
        sample.auraColor = AurieGenerator.auraColors[family] ?? sample.auraColor
        sample.baseColor = AurieGenerator.nudgeTowardFamily(sample.baseColor, family)

        let node = AurieNode(
            textures: AssetLoader.textures(for: sample),
            baseColor: SKColor(sample.baseColor),
            auraColor: SKColor(sample.auraColor),
            body: sample.body,
            armStyle: sample.resolvedArmStyle,
            legStyle: sample.resolvedLegStyle,
            hairStyle: sample.resolvedHairStyle,
            patternLayer: sample.patternMaskLayer)
        // Match REAL in-app proportions, not an arbitrary thumbnail. The
        // creature was drawn at 0.30 (~100 pt) inside a 370 pt field, so the
        // particles orbited at ~4x the body — nothing judged here would have
        // matched what the hatch or Wonderglobe actually look like.
        let footprint = min(size.width, size.height) * 0.56
        node.setScale(footprint / (AssetLoader.collisionHalfWidth * 2))
        node.position = .zero
        node.zPosition = 0
        addChild(node)
        node.startIdle()
        creature = node

        // Same relationship the hatch reveal uses: field ≈ 1.9x the body.
        let span = footprint * 1.9
        let rect = CGRect(x: -span/2, y: -span/2, width: span, height: span)
        let motion: ParticleMotion
        switch mode {
        case .calm:  motion = .calm
        case .swirl, .celebration: motion = .swirl
        default:     motion = .ambient
        }
        // The creature's ACTUAL rendered bounds, inset past the aura glow —
        // the swirl orbits this, not a guess at the field centre.
        var bodyBox = node.calculateAccumulatedFrame()
        bodyBox = bodyBox.insetBy(dx: bodyBox.width * 0.20,
                                  dy: bodyBox.height * 0.20)
        let f = ParticleField(family: family, area: rect, motion: motion,
                              body: bodyBox)
        addChild(f)
        field = f
        #if DEBUG
        f.showOrbitDebug()
        NSLog("AURIE_ORBIT body=%@ field=%@",
              NSCoder.string(for: bodyBox), NSCoder.string(for: rect))
        #endif

        switch mode {
        case .swirl:
            if ProcessInfo.processInfo.environment["AURIE_SWIRL_CYCLE"] == "1" {
                // QA cycle: settled -> ramp -> peak -> settle, on repeat, so
                // the whole energy arc can be reviewed in one recording.
                run(.repeatForever(.sequence([
                    // 0.38, not the preset's 0.10 rest: below about a third
                    // the staggered pool falls back to its rest points and
                    // the field reads as empty. This is the settled level a
                    // real caller (the hatch, and Wonderglobe) would hold.
                    .run { [weak f] in f?.setEnergy(0.52, duration: 0.1) },
                    .wait(forDuration: 4.0),
                    .run { [weak f] in f?.setEnergy(1.0, duration: 1.2) },
                    .wait(forDuration: 4.5),
                    .run { [weak f] in f?.setEnergy(0.52, duration: 2.5) },
                    .wait(forDuration: 3.5),
                ])), withKey: "swirlCycle")
            } else {
                f.setEnergy(1.0, duration: 0.6)      // hold at Wonderglobe peak
            }
        case .celebration:
            f.setEnergy(0.12, duration: 0.1)
            // Repeat the burst so it can be watched without relaunching.
            run(.repeatForever(.sequence([
                .run { [weak self] in self?.field?.celebrate(at: .zero,
                                                             spread: span * 0.34) },
                .wait(forDuration: 2.2)])), withKey: "celebrate")
        default:
            break
        }
    }

    /// Raw art, laid out large so each motif can be inspected on its own.
    private func buildMotifSheet() {
        let motifs = FamilyParticleArt.motifs(for: family)
        let cols = 3
        let cell = min(size.width / CGFloat(cols), 150)
        for (i, motif) in motifs.enumerated() {
            let sprite = SKSpriteNode(texture: FamilyParticleArt.texture(motif))
            sprite.setScale(1.6)
            sprite.blendMode = .add
            let col = i % cols, row = i / cols
            sprite.position = CGPoint(
                x: (CGFloat(col) - CGFloat(cols - 1) / 2) * cell,
                y: 90 - CGFloat(row) * cell)
            addChild(sprite)

            let label = SKLabelNode(text: motif.rawValue)
            label.fontName = "HelveticaNeue"
            label.fontSize = 10
            label.fontColor = SKColor(white: 0.65, alpha: 1)
            label.position = CGPoint(x: sprite.position.x,
                                     y: sprite.position.y - cell * 0.34)
            addChild(label)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = last > 0 ? currentTime - last : 0
        last = currentTime
        field?.update(dt)
    }
}
#endif
