import SpriteKit

/// The Blender-derived look for one body type, assembled from the modular
/// pixel-registered layers exported from the canonical 3D scenes.
///
/// This is a SKIN, not a second creature: it owns only the sprite stack and
/// hands it to `AurieNode`, which keeps every transform layer, animation,
/// reaction and hit-test it already had. If a body type has no Blender
/// assets, `AurieNode` builds its placeholder sprites exactly as before —
/// nothing else in the app branches on this.
///
/// Layer order was determined empirically, not assumed: each layer was
/// composited against the full 3D reference render and the ordering with the
/// lowest error won (body → tuft → arms → legs → cheeks → mouth → eyes,
/// mean error 0.43/255). The limb passes are rendered with the body as a
/// HOLDOUT, because the limb roots are embedded in the body and no 2D
/// ordering can otherwise be correct.
///
/// Only the neutral layers take the family tint; eyes, mouth, cheeks and
/// catchlights keep their authored colour.
enum AurieBlenderSkin {

    /// Export ids match `BodyType` raw values exactly.
    static func key(_ body: BodyType) -> String { body.rawValue }

    static func layerSet(_ body: BodyType) -> AurieBlenderAssets.Body? {
        AurieBlenderAssets.bodies[key(body)]
    }

    /// How far the body group (body, tuft, face, arms) rises for a leg
    /// style, in POINTS. The generator already converted from scene units
    /// using that body's own camera scale — an earlier version guessed the
    /// canvas span at runtime and lifted the body 1.8x too far, which is
    /// what made the feet look detached.
    static func legLift(_ body: BodyType, _ legStyle: String) -> CGFloat {
        layerSet(body)?.legLift[legStyle] ?? 0
    }

    /// Arms exported without the body holdout (they keep their shoulder root),
    /// so the app draws them BEHIND the body and rotates them about the joint
    /// without a shoulder gap. Only bodies re-exported this way return true.
    static func animSafeArms(_ body: BodyType) -> Bool {
        layerSet(body)?.animSafeArms ?? false
    }

    /// The shoulder pivot for one arm layer (e.g. "arm_01_r"), in points from
    /// the art centre — the point the arm rotates about.
    static func armPivot(_ body: BodyType, _ armLayer: String) -> CGPoint? {
        layerSet(body)?.armPivot[armLayer]
    }

    /// Legs exported without the body holdout (they keep their hip root), so
    /// splits and kicks can rotate the leg about a hip joint without a gap
    /// opening. Only bodies re-exported the 2026-09-12 way return true.
    static func animSafeLegs(_ body: BodyType) -> Bool {
        layerSet(body)?.animSafeLegs ?? false
    }

    /// The hip pivot for one leg layer (e.g. "leg_04_r"), same point space
    /// as `armPivot`.
    static func legPivot(_ body: BodyType, _ legLayer: String) -> CGPoint? {
        layerSet(body)?.legPivot[legLayer]
    }

    /// Any body that shipped with a complete Blender layer set.
    static func isAvailable(_ body: BodyType) -> Bool {
        #if DEBUG
        // A/B against the placeholder path during staged integration.
        if ProcessInfo.processInfo.environment["AURIE_BLENDER_OFF"] == "1" {
            return false
        }
        #endif
        return AurieBlenderAssets.bodies[key(body)] != nil
    }

    /// `rgb * tint`, clamped to alpha. Measured in the Stage 0 spike:
    /// SpriteKit samples these textures WITHOUT sRGB decode, so the multiply
    /// lands in sRGB space and the tint is simply colour / neutral (192).
    /// Alpha is carried through untouched and never forced to 1, so a
    /// translucent body render would composite correctly here later.
    static let tintShaderSource = """
    void main() {
        vec4 c = texture2D(u_texture, v_tex_coord);
        vec3 tinted = min(c.rgb * u_tint, vec3(c.a));
        gl_FragColor = vec4(tinted, c.a);
    }
    """

    /// The neutral master albedo the bodies were rendered at (#C0C0C0).
    /// White clipped 33% of the body's shading; this is the brightest
    /// neutral with zero clipping.
    /// The generated belly-patch core for sticker placement — nil when
    /// this body shipped no belly layer. Emitted by install_app_assets.py
    /// from the same zone render as the belly art; the runtime never
    /// recomputes its own rectangle.
    static func bellyCore(_ body: BodyType)
        -> (center: CGPoint, size: CGSize)? {
        guard let set = layerSet(body),
              set.bellyCoreSize != .zero else { return nil }
        return (set.bellyCoreCenter, set.bellyCoreSize)
    }

    static let neutralAlbedo: CGFloat = 192.0

    static func tintShader(for colour: SKColor) -> SKShader {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        let shader = SKShader(source: tintShaderSource)
        shader.uniforms = [SKUniform(name: "u_tint", vectorFloat3: tintVector(colour))]
        return shader
    }

    /// `colour / neutral`, the multiply factor that turns the #C0C0C0 master
    /// render into a family-tinted body while keeping its shading.
    static func tintVector(_ colour: SKColor) -> SIMD3<Float> {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3(Float(r * 255 / neutralAlbedo),
                     Float(g * 255 / neutralAlbedo),
                     Float(b * 255 / neutralAlbedo))
    }

    /// Same multiply as `tintShader`, but the tint is chosen PER PIXEL between
    /// the body colour and the pattern colour by a greyscale mask (white =
    /// pattern). Because it is still a multiply on the neutral render, the
    /// Blender shading, highlights and alpha are preserved exactly as in the
    /// plain path — the pattern only swaps WHICH family-adjacent colour each
    /// pixel is tinted toward, so it wraps the body's curvature. The mask is
    /// pixel-registered to the body crop, so it is sampled at the same
    /// `v_tex_coord` as the body texture.
    static let patternTintShaderSource = """
    void main() {
        vec4 c = texture2D(u_texture, v_tex_coord);
        float m = texture2D(u_mask, v_tex_coord).r;
        vec3 tint = mix(u_tint, u_pattern_tint, m);
        vec3 tinted = min(c.rgb * tint, vec3(c.a));
        gl_FragColor = vec4(tinted, c.a);
    }
    """

    static func patternTintShader(body bodyColour: SKColor,
                                  pattern patternColour: SKColor,
                                  mask: SKTexture) -> SKShader {
        let shader = SKShader(source: patternTintShaderSource)
        shader.uniforms = [
            SKUniform(name: "u_tint", vectorFloat3: tintVector(bodyColour)),
            SKUniform(name: "u_pattern_tint", vectorFloat3: tintVector(patternColour)),
            SKUniform(name: "u_mask", texture: mask),
        ]
        return shader
    }

    /// The greyscale mask texture for a pattern layer on this body (e.g.
    /// `pattern_spots_v1`), or nil when the body has no such mask — in which
    /// case the caller keeps the plain tint and the Aurie renders unpatterned.
    static func patternMask(_ body: BodyType, _ layer: String,
                            orientation: AurieOrientation = .front)
        -> SKTexture? {
        // Patterns are body-surface markings and CONTINUE AROUND the
        // creature (product rule 2026-09-14): each orientation has its
        // own mask, registered to that orientation's body crop. A
        // missing mask (e.g. stars/hearts backs until their tile
        // sources are restored) degrades to the plain tint.
        guard let spec = orientedLayer(body, layer, orientation),
              let image = UIImage(named: spec.asset) else { return nil }
        let tex = SKTexture(image: image)
        // Sampled in the shader without sRGB decode, matching the body texture.
        tex.filteringMode = .linear
        return tex
    }

    /// Layer record for an orientation, from the generated manifest's
    /// per-orientation maps. Nil = no art for that orientation on this
    /// body — callers fall back to front (the documented rule), never
    /// crash and never fake with a flip.
    static func orientedLayer(_ body: BodyType, _ layer: String,
                              _ orientation: AurieOrientation)
        -> AurieBlenderAssets.Layer? {
        switch orientation {
        case .front:
            return layerSet(body)?.layers[layer]
        case .back:
            return layerSet(body)?.backLayers[layer]
        }
    }

    /// Orientation-aware joint pivots — always the exporter's own
    /// measurements, never hand-tuned Swift coordinates.
    static func armPivot(_ body: BodyType, _ armLayer: String,
                         _ orientation: AurieOrientation) -> CGPoint? {
        orientation == .front
            ? layerSet(body)?.armPivot[armLayer]
            : layerSet(body)?.backArmPivot[armLayer]
    }

    static func legPivot(_ body: BodyType, _ legLayer: String,
                         _ orientation: AurieOrientation) -> CGPoint? {
        orientation == .front
            ? layerSet(body)?.legPivot[legLayer]
            : layerSet(body)?.backLegPivot[legLayer]
    }

    /// Build one layer's sprite at its exported placement, or nil when the
    /// asset is missing (caller then keeps the placeholder for that slot).
    static func sprite(_ body: BodyType, _ layer: String,
                       orientation: AurieOrientation = .front,
                       tinted: SKShader? = nil) -> SKSpriteNode? {
        guard let spec = orientedLayer(body, layer, orientation),
              let image = UIImage(named: spec.asset) else { return nil }
        let node = SKSpriteNode(texture: SKTexture(image: image))
        node.size = spec.size
        node.position = spec.position
        node.shader = tinted
        return node
    }

    /// Face layer ids for an expression, via the central catalog.
    ///
    /// There is deliberately NO expression-to-expression fallback here: a
    /// valid expression that has no artwork must surface as a validation
    /// failure, not as a creature quietly wearing Classic Happy. Only a
    /// completely unknown id (which cannot come from the enum) degrades.
    /// `sparkles` is the movable catchlight layer, nil when there is nothing to
    /// track (arc/heavy-lid eyes) or the body predates the split. It is
    /// deliberately dropped while blinking — a shut eye shows no sparkle.
    static func faceLayers(_ body: BodyType, _ faceId: String,
                           blink: Bool) -> (cheeks: String, mouth: String,
                                            eyes: String, sparkles: String?)? {
        guard let face = AurieFaceCatalog.face(faceId, body: key(body))
        else { return nil }
        let eyes = blink ? (face.blinkEyes ?? face.eyes) : face.eyes
        return (face.cheeks, face.mouth, eyes, blink ? nil : face.sparkles)
    }
}
