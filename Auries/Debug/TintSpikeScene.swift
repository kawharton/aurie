#if DEBUG
import SpriteKit
import SwiftUI

/// Stage 0 tint spike — DEBUG ONLY, not part of the shipping app.
///
/// Proves (or disproves) that a neutral Blender render multiply-tinted at
/// runtime reproduces a Blender render made directly in that colour. The
/// offline maths already matches; what this checks is the thing that cannot
/// be reasoned about safely — whether SpriteKit samples the texture as sRGB
/// (so the multiply lands in LINEAR space) or raw (multiply in sRGB space).
/// It draws both candidate tints so the screenshot answers it empirically.
///
/// Reads its PNGs from the app's Documents directory so no asset-catalog or
/// project changes are needed for a throwaway experiment.
enum TintSpike {

    /// `rgb * tint`, clamped to alpha so the premultiplied invariant holds
    /// even where a tint channel exceeds 1 (saturated families need that).
    /// Alpha is carried through untouched — never forced to 1 — so this same
    /// shader keeps working if a translucent body render arrives later.
    static let source = """
    void main() {
        vec4 c = texture2D(u_texture, v_tex_coord);
        vec3 tinted = min(c.rgb * u_tint, vec3(c.a));
        gl_FragColor = vec4(tinted, c.a);
    }
    """

    struct Swatch {
        let name: String
        let linear: SIMD3<Float>   // tint derived in linear space
        let srgb: SIMD3<Float>     // tint derived in sRGB space
    }

    /// body colour / neutral albedo, per channel, in each candidate space.
    /// Neutral master is #C0C0C0 (brightest albedo with zero clipping).
    static let swatches = [
        Swatch(name: "ember", linear: [1.531, 0.325, 0.130],
               srgb: [1.208, 0.599, 0.385]),
        Swatch(name: "moss", linear: [0.382, 0.909, 0.296],
               srgb: [0.625, 0.964, 0.573]),
        Swatch(name: "dusk", linear: [0.613, 0.356, 1.096],
               srgb: [0.781, 0.625, 1.042]),
    ]

    static func image(_ name: String) -> UIImage? {
        let dir = FileManager.default.urls(for: .documentDirectory,
                                           in: .userDomainMask)[0]
        return UIImage(contentsOfFile:
                        dir.appendingPathComponent(name).path)
    }
}

final class TintSpikeScene: SKScene {

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(white: 0.96, alpha: 1)
        scaleMode = .aspectFit
        guard let neutral = TintSpike.image("body_neutralC0.png"),
              let face = TintSpike.image("face_happy.png") else {
            NSLog("AURIE_TINT missing source PNGs in Documents")
            return
        }
        let neutralTex = SKTexture(image: neutral)
        let faceTex = SKTexture(image: face)
        let side: CGFloat = 300
        let cols = TintSpike.swatches.count

        for (row, useLinear) in [(0, true), (1, false)] {
            for (i, sw) in TintSpike.swatches.enumerated() {
                let holder = SKNode()
                holder.position = CGPoint(
                    x: size.width / 2 + CGFloat(i - cols / 2) * (side + 8),
                    y: size.height / 2 + (row == 0 ? side / 2 + 10
                                                   : -side / 2 - 10))
                let body = SKSpriteNode(texture: neutralTex,
                                        size: CGSize(width: side, height: side))
                let shader = SKShader(source: TintSpike.source)
                let t = useLinear ? sw.linear : sw.srgb
                shader.uniforms = [SKUniform(name: "u_tint",
                                             vectorFloat3: t)]
                body.shader = shader
                holder.addChild(body)
                let faceNode = SKSpriteNode(texture: faceTex,
                                            size: CGSize(width: side,
                                                         height: side))
                faceNode.zPosition = 1
                holder.addChild(faceNode)
                addChild(holder)

                let label = SKLabelNode(text:
                    "\(sw.name) \(useLinear ? "linear" : "sRGB")")
                label.fontSize = 15
                label.fontName = "Menlo"
                label.fontColor = .darkGray
                label.position = CGPoint(x: holder.position.x,
                                         y: holder.position.y - side / 2 - 16)
                addChild(label)
            }
        }
        NSLog("AURIE_TINT scene ready")
    }
}

struct TintSpikeView: View {
    var body: some View {
        SpriteView(scene: {
            let s = TintSpikeScene()
            s.size = CGSize(width: 1000, height: 800)
            return s
        }())
        .ignoresSafeArea()
    }
}
#endif
