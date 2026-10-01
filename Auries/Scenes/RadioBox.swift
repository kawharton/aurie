import SpriteKit
import UIKit

/// The Home radio: a small music box that sits in the Aurie's world rather
/// than a music screen laid over it.
///
/// Like the toys, every visual is PROCEDURAL — drawn once into a texture at
/// the right scale — so the radio matches the rest of the play system with no
/// new art dependencies. It carries its own compact controls: tapping the
/// SPEAKER toggles play/pause, tapping the small dial on its right switches to
/// the next loop. Nothing else is added to the Home chrome.
///
/// `RadioBox` owns only the object, its audio, and its beat clock. Everything
/// about the CREATURE — noticing the music, choosing a dance, Stone refusing
/// to dance — lives in `CreatureScene`, which reads `beatInterval` /
/// `beatOrigin` here and drives the choreography through the same primitives
/// and priority rules the earlier passes established.
final class RadioBox {

    /// A loop and the tempo the choreography runs on. No beat detection: the
    /// track states its own BPM, which is what keeps claps, jumps and floss
    /// reversals locked to the music.
    struct Track {
        let id: String
        let label: String
        let bpm: Double
    }

    static let tracks: [Track] = [
        Track(id: "music_sunny",  label: "Sunny",  bpm: 120),
        Track(id: "music_groove", label: "Groove", bpm: 100),
        Track(id: "music_dreamy", label: "Dreamy", bpm: 84),
    ]

    /// Which compact control a tap landed on.
    enum Control { case playPause, nextTrack }

    // MARK: State

    private(set) var isOut = false
    private(set) var isPlaying = false
    private(set) var trackIndex = 0

    var track: Track { Self.tracks[trackIndex] }
    /// Seconds per beat — the choreography's only timing source.
    var beatInterval: TimeInterval { 60.0 / track.bpm }
    /// When the current playback started, so a dance can begin ON a beat.
    private(set) var beatOrigin: TimeInterval = 0

    /// The next beat boundary at or after `now`.
    func nextBeat(after now: TimeInterval) -> TimeInterval {
        guard isPlaying else { return now }
        let elapsed = max(0, now - beatOrigin)
        let n = (elapsed / beatInterval).rounded(.down) + 1
        return beatOrigin + n * beatInterval
    }

    private let root = SKNode()
    private var body: SKSpriteNode?
    private var speaker: SKNode?
    private var dialGlow: SKSpriteNode?
    private var bars: [SKSpriteNode] = []

    /// Texture-space → sprite-space, so the live nodes land exactly on the
    /// speaker and dial that are painted into the shell.
    private static let artSize = CGSize(width: 208, height: 216)
    private static let spriteSize = CGSize(width: 98, height: 102)
    /// On-screen footprint, so the scene can seat the radio against an edge.
    static var footprint: CGSize { spriteSize }

    /// Art-space y of the bottom of the charcoal plinth — the radio's visual
    /// BASE. Below it the texture carries only the little feet and the soft
    /// ground shadow, which must not count when lining the radio up with
    /// other chrome.
    private static let artBaseY: CGFloat = 194

    /// Distance from the sprite's bottom EDGE up to that visual base, in
    /// points. Seating the radio by its base means subtracting this.
    static var baseMargin: CGFloat {
        (artSize.height - artBaseY) * (spriteSize.height / artSize.height)
    }

    /// Move an already-placed radio (the play area can resize when the Daily
    /// card is dismissed, and the radio has to stay seated in its corner).
    func reposition(to point: CGPoint) {
        guard isOut else { return }
        root.position = point
    }
    private static func onArt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: (x - artSize.width / 2) * (spriteSize.width / artSize.width),
                y: (artSize.height / 2 - y) * (spriteSize.height / artSize.height))
    }

    // MARK: Bring out / put away

    /// Place the radio at the point the scene chooses — it is seated against
    /// the play area's bottom-left corner, in line with the Play Shelf.
    func bringOut(in scene: SKScene, at point: CGPoint) {
        guard !isOut else { return }
        isOut = true
        root.removeAllChildren()
        root.zPosition = 28              // just under the toys, above the world
        root.position = point
        root.setScale(0.01)
        scene.addChild(root)

        let sprite = SKSpriteNode(texture: Self.bodyTexture)
        sprite.size = Self.spriteSize
        root.addChild(sprite)
        body = sprite

        // The speaker gets its own node so the whole cone can breathe on the
        // beat; the glow is additive and very soft, never a hotspot.
        let cone = SKNode()
        cone.position = Self.onArt(66, 128)
        cone.zPosition = 1
        root.addChild(cone)
        let halo = SKSpriteNode(texture: Self.speakerGlowTexture)
        halo.size = CGSize(width: 40, height: 40)
        halo.blendMode = .add
        halo.alpha = 0
        halo.name = "halo"
        cone.addChild(halo)
        speaker = cone

        // Dial window: a soft glow plus three little level bars.
        let glow = SKSpriteNode(texture: Self.dialGlowTexture)
        glow.size = CGSize(width: 34, height: 18)
        glow.position = Self.onArt(143, 113)
        glow.zPosition = 1
        glow.blendMode = .add
        glow.alpha = 0.35
        root.addChild(glow)
        dialGlow = glow
        bars.removeAll()
        for i in 0 ..< 3 {
            let bar = SKSpriteNode(color: UIColor(white: 1, alpha: 0.85),
                                   size: CGSize(width: 2.6, height: 5))
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.position = CGPoint(x: glow.position.x + CGFloat(i - 1) * 6,
                                   y: glow.position.y - 5)
            bar.zPosition = 2
            bar.alpha = 0.5
            root.addChild(bar)
            bars.append(bar)
        }

        let pop = SKAction.sequence([.scale(to: 1.08, duration: 0.24),
                                     .scale(to: 1.0, duration: 0.12)])
        pop.timingMode = .easeOut
        root.run(pop)
        SoundPlayer.play("sfx_appear")
    }

    func putAway() {
        guard isOut else { return }
        stop()
        isOut = false
        let shrink = SKAction.sequence([.scale(to: 0.01, duration: 0.2), .removeFromParent()])
        shrink.timingMode = .easeIn
        root.run(shrink)
        body = nil
        speaker = nil
        dialGlow = nil
        bars.removeAll()
    }

    // MARK: Transport

    @discardableResult
    func play() -> Bool {
        guard isOut else { return false }
        if let origin = SoundPlayer.startMusic(track.id) {
            beatOrigin = origin
        } else {
            // Sound is muted or the file is missing: the radio still keeps
            // time so the choreography works, it just plays silently.
            beatOrigin = CACurrentMediaTime()
        }
        isPlaying = true
        pulseSpeaker()
        return true
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        SoundPlayer.pauseMusic()
        idleVisuals()
    }

    func stop() {
        isPlaying = false
        SoundPlayer.stopMusic()
        idleVisuals()
        root.removeAction(forKey: "notes")
    }

    /// Paused/idle: the cone rests, the dial keeps only a faint standby glow.
    private func idleVisuals() {
        speaker?.removeAction(forKey: "beat")
        speaker?.setScale(1)
        speaker?.childNode(withName: "halo")?.run(.fadeAlpha(to: 0, duration: 0.2))
        dialGlow?.removeAction(forKey: "dial")
        dialGlow?.run(.fadeAlpha(to: 0.30, duration: 0.25))
        for (i, bar) in bars.enumerated() {
            bar.removeAction(forKey: "eq")
            bar.run(.group([.resize(toHeight: 5, duration: 0.2),
                            .fadeAlpha(to: 0.5, duration: 0.2)]))
            _ = i
        }
    }

    @discardableResult
    func togglePlay() -> Bool {
        if isPlaying { pause(); return false }
        if SoundPlayer.currentMusic == track.id, let origin = SoundPlayer.resumeMusic() {
            beatOrigin = origin
            isPlaying = true
            pulseSpeaker()
            return true
        }
        return play()
    }

    /// Switch to the next loop. Keeps playing if it already was.
    func nextTrack() {
        trackIndex = (trackIndex + 1) % Self.tracks.count
        let wasPlaying = isPlaying
        SoundPlayer.stopMusic()
        isPlaying = false
        if wasPlaying { play() }
        // A quick dial flick so the switch is visible even when muted.
        let flick = SKAction.sequence([.rotate(byAngle: 0.5, duration: 0.12),
                                       .rotate(byAngle: -0.5, duration: 0.14)])
        root.childNode(withName: "dial")?.run(flick)
    }

    // MARK: Hit testing — the radio's own compact controls

    /// Which control (if any) a scene point lands on. The speaker half is
    /// play/pause, the dial on the right switches loops.
    func control(at scenePoint: CGPoint) -> Control? {
        guard isOut, let body else { return nil }
        let p = CGPoint(x: scenePoint.x - root.position.x,
                        y: scenePoint.y - root.position.y)
        guard body.frame.insetBy(dx: -10, dy: -10).contains(p) else { return nil }
        return p.x > 4 ? .nextTrack : .playPause
    }

    /// True when the point is anywhere on the radio (so the scene can let the
    /// object swallow the tap instead of hopping the Aurie toward it).
    func contains(_ scenePoint: CGPoint) -> Bool { control(at: scenePoint) != nil }

    var position: CGPoint { root.position }

    // MARK: Beat visuals

    private func pulseSpeaker() {
        guard let speaker else { return }
        let b = beatInterval
        // Restrained on purpose: the Aurie is the focal point, the radio just
        // breathes a little.
        let pulse = SKAction.sequence([.scale(to: 1.09, duration: b * 0.16),
                                       .scale(to: 1.0, duration: b * 0.36),
                                       .wait(forDuration: b * 0.48)])
        pulse.timingMode = .easeOut
        speaker.run(.repeatForever(pulse), withKey: "beat")
        if let halo = speaker.childNode(withName: "halo") {
            halo.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.42, duration: b * 0.16),
                .fadeAlpha(to: 0.10, duration: b * 0.40),
                .wait(forDuration: b * 0.44)])), withKey: "beat")
        }
        // Dial glow takes the track's accent colour and breathes with it.
        dialGlow?.color = Self.accent(for: trackIndex)
        dialGlow?.colorBlendFactor = 1
        dialGlow?.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.85, duration: b * 0.2),
            .fadeAlpha(to: 0.45, duration: b * 0.5),
            .wait(forDuration: b * 0.3)])), withKey: "dial")
        // Three level bars, each on its own offset so it reads as a meter.
        for (i, bar) in bars.enumerated() {
            let hi = CGFloat([11, 15, 9][i % 3])
            let seq = SKAction.sequence([
                .wait(forDuration: b * Double(i) * 0.18),
                .repeatForever(.sequence([
                    .group([.resize(toHeight: hi, duration: b * 0.18),
                            .fadeAlpha(to: 0.95, duration: b * 0.18)]),
                    .group([.resize(toHeight: 4, duration: b * 0.42),
                            .fadeAlpha(to: 0.55, duration: b * 0.42)]),
                    .wait(forDuration: b * 0.4)]))])
            bar.run(seq, withKey: "eq")
        }
        // A note drifts up every other beat while the music runs.
        let note = SKAction.sequence([
            .run { [weak self] in self?.emitNote() },
            .wait(forDuration: b * 2)])
        root.run(.repeatForever(note), withKey: "notes")
    }

    private func emitNote() {
        guard isPlaying else { return }
        let note = SKSpriteNode(texture: Self.noteTexture)
        note.size = CGSize(width: 18, height: 22)
        note.position = CGPoint(x: -18, y: 22)
        note.alpha = 0
        note.zRotation = CGFloat.random(in: -0.2 ... 0.2)
        root.addChild(note)
        let drift = SKAction.group([
            .moveBy(x: CGFloat.random(in: -14 ... 22), y: 62, duration: 1.7),
            .sequence([.fadeAlpha(to: 0.85, duration: 0.3),
                       .wait(forDuration: 0.7),
                       .fadeOut(withDuration: 0.7)]),
            .rotate(byAngle: CGFloat.random(in: -0.5 ... 0.5), duration: 1.7)])
        note.run(.sequence([drift, .removeFromParent()]))
    }

    // MARK: Procedural art

    /// A small magical music box, drawn with real dimension: a lit top face,
    /// a shaded right-hand side face, a recessed speaker with an inner
    /// shadow, and knobs that cast onto the shell. Deliberately family-NEUTRAL
    /// — the only colour that moves is the dial glow — so it sits comfortably
    /// in the bright meadows and the dark caverns alike.
    private static let bodyImage: UIImage = {
        let size = CGSize(width: 208, height: 216)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let cream = UIColor(red: 0.97, green: 0.94, blue: 0.88, alpha: 1)
            let creamMid = UIColor(red: 0.90, green: 0.85, blue: 0.77, alpha: 1)
            let creamDark = UIColor(red: 0.70, green: 0.63, blue: 0.55, alpha: 1)
            let charcoal = UIColor(red: 0.28, green: 0.26, blue: 0.29, alpha: 1)
            let charcoalLo = UIColor(red: 0.18, green: 0.17, blue: 0.20, alpha: 1)
            let brass = UIColor(red: 0.90, green: 0.74, blue: 0.40, alpha: 1)
            let brassHi = UIColor(red: 1.00, green: 0.91, blue: 0.66, alpha: 1)
            let brassDark = UIColor(red: 0.55, green: 0.41, blue: 0.17, alpha: 1)
            func grad(_ rect: CGRect, _ from: UIColor, _ to: UIColor,
                      horizontal: Bool = false) {
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: [from.cgColor, to.cgColor] as CFArray,
                                   locations: [0, 1])!
                c.drawLinearGradient(g,
                    start: CGPoint(x: rect.minX, y: rect.minY),
                    end: horizontal ? CGPoint(x: rect.maxX, y: rect.minY)
                                    : CGPoint(x: rect.minX, y: rect.maxY),
                    options: [])
            }

            // Ground shadow.
            c.setFillColor(UIColor(white: 0, alpha: 0.22).cgColor)
            c.fillEllipse(in: CGRect(x: 28, y: 186, width: 152, height: 24))

            // ---- Plinth: top face lighter, front face darker (depth) ----
            let plinthTop = CGRect(x: 22, y: 158, width: 164, height: 16)
            let plinthFront = CGRect(x: 22, y: 168, width: 164, height: 26)
            c.setFillColor(charcoalLo.cgColor)
            c.addPath(UIBezierPath(roundedRect: plinthFront, cornerRadius: 12).cgPath)
            c.fillPath()
            c.setFillColor(charcoal.cgColor)
            c.addPath(UIBezierPath(roundedRect: plinthTop, cornerRadius: 8).cgPath)
            c.fillPath()

            // ---- Shell: front face, then a side face and a lit top face ----
            let shell = CGRect(x: 16, y: 74, width: 176, height: 92)
            let shellPath = UIBezierPath(roundedRect: shell, cornerRadius: 28)
            c.saveGState(); c.addPath(shellPath.cgPath); c.clip()
            grad(shell, cream, creamMid)
            // right-hand side face, as if the box turns away from the light
            grad(CGRect(x: shell.maxX - 34, y: shell.minY, width: 34, height: shell.height),
                 creamMid.withAlphaComponent(0), creamDark, horizontal: true)
            // ambient occlusion where the shell meets the plinth
            grad(CGRect(x: shell.minX, y: shell.maxY - 22, width: shell.width, height: 22),
                 creamDark.withAlphaComponent(0), creamDark.withAlphaComponent(0.75))
            c.restoreGState()
            // Lit top face — a shallow ellipse catching the key light.
            c.setFillColor(UIColor(white: 1, alpha: 0.55).cgColor)
            c.fillEllipse(in: CGRect(x: 32, y: 66, width: 144, height: 30))
            c.setFillColor(UIColor(white: 1, alpha: 0.30).cgColor)
            c.fillEllipse(in: CGRect(x: 46, y: 70, width: 112, height: 18))
            c.setStrokeColor(brassDark.withAlphaComponent(0.30).cgColor)
            c.setLineWidth(2); c.addPath(shellPath.cgPath); c.strokePath()

            // ---- Speaker: recessed, with an inner shadow ring ----
            let sp = CGRect(x: 32, y: 94, width: 68, height: 68)
            c.setFillColor(UIColor(red: 0.30, green: 0.26, blue: 0.24, alpha: 1).cgColor)
            c.fillEllipse(in: sp)
            c.saveGState(); c.addEllipse(in: sp); c.clip()
            grad(sp, UIColor(white: 0, alpha: 0.55), UIColor(white: 0, alpha: 0))
            c.restoreGState()
            c.setFillColor(UIColor(white: 1, alpha: 0.11).cgColor)
            for row in stride(from: sp.minY + 8, to: sp.maxY - 4, by: 7) {
                for col in stride(from: sp.minX + 8, to: sp.maxX - 4, by: 7) {
                    if hypot(col - sp.midX, row - sp.midY) < sp.width / 2 - 7 {
                        c.fillEllipse(in: CGRect(x: col, y: row, width: 3.2, height: 3.2))
                    }
                }
            }
            // Brass bezel with a bright top-left arc.
            c.setStrokeColor(brassDark.cgColor); c.setLineWidth(5)
            c.strokeEllipse(in: sp.insetBy(dx: 1, dy: 1))
            c.setStrokeColor(brass.cgColor); c.setLineWidth(3.4)
            c.strokeEllipse(in: sp.insetBy(dx: 2, dy: 2))
            c.setStrokeColor(brassHi.cgColor); c.setLineWidth(2)
            c.addArc(center: CGPoint(x: sp.midX, y: sp.midY), radius: sp.width / 2 - 2,
                     startAngle: .pi * 0.85, endAngle: .pi * 1.65, clockwise: false)
            c.strokePath()

            // ---- Dial window: inset, glassy ----
            let dial = CGRect(x: 112, y: 98, width: 62, height: 30)
            let dialPath = UIBezierPath(roundedRect: dial, cornerRadius: 11)
            c.saveGState(); c.addPath(dialPath.cgPath); c.clip()
            grad(dial, UIColor(red: 0.13, green: 0.16, blue: 0.20, alpha: 1),
                 UIColor(red: 0.24, green: 0.29, blue: 0.34, alpha: 1))
            c.setFillColor(UIColor(white: 1, alpha: 0.16).cgColor)
            c.fill(CGRect(x: dial.minX, y: dial.minY, width: dial.width, height: 9))
            c.restoreGState()
            c.setStrokeColor(brassDark.cgColor); c.setLineWidth(3.4)
            c.addPath(dialPath.cgPath); c.strokePath()
            c.setStrokeColor(brass.cgColor); c.setLineWidth(1.8)
            c.addPath(dialPath.cgPath); c.strokePath()

            // ---- Knobs: seated, with a cast shadow and a specular dot ----
            for x in [CGFloat(116), CGFloat(148)] {
                c.setFillColor(UIColor(white: 0, alpha: 0.28).cgColor)
                c.fillEllipse(in: CGRect(x: x + 2, y: 140, width: 26, height: 26))
                c.setFillColor(brassDark.cgColor)
                c.fillEllipse(in: CGRect(x: x, y: 136, width: 26, height: 26))
                c.saveGState()
                c.addEllipse(in: CGRect(x: x + 2, y: 138, width: 22, height: 22)); c.clip()
                grad(CGRect(x: x + 2, y: 138, width: 22, height: 22), brassHi, brass)
                c.restoreGState()
                c.setFillColor(UIColor(white: 1, alpha: 0.70).cgColor)
                c.fillEllipse(in: CGRect(x: x + 6, y: 142, width: 8, height: 6))
            }

            // ---- Long antenna, angled back into the scene ----
            c.setStrokeColor(brassDark.cgColor); c.setLineWidth(4.4); c.setLineCap(.round)
            c.move(to: CGPoint(x: 150, y: 86)); c.addLine(to: CGPoint(x: 192, y: 14))
            c.strokePath()
            c.setStrokeColor(brass.cgColor); c.setLineWidth(2.2)
            c.move(to: CGPoint(x: 150, y: 86)); c.addLine(to: CGPoint(x: 192, y: 14))
            c.strokePath()
            c.setFillColor(brassDark.cgColor)
            c.fillEllipse(in: CGRect(x: 184, y: 4, width: 17, height: 17))
            c.setFillColor(brass.cgColor)
            c.fillEllipse(in: CGRect(x: 186, y: 6, width: 13, height: 13))
            c.setFillColor(UIColor(white: 1, alpha: 0.8).cgColor)
            c.fillEllipse(in: CGRect(x: 189, y: 8, width: 5, height: 4))

            // ---- Feet ----
            c.setFillColor(brassDark.cgColor)
            c.fillEllipse(in: CGRect(x: 42, y: 186, width: 22, height: 11))
            c.fillEllipse(in: CGRect(x: 146, y: 186, width: 22, height: 11))
        }
    }()

    private static let bodyTexture = SKTexture(image: bodyImage)

    /// A gentle per-track accent for the dial only — never the whole shell,
    /// so the radio stays family-neutral in every environment.
    private static func accent(for index: Int) -> UIColor {
        switch index % 3 {
        case 0:  return UIColor(red: 1.00, green: 0.86, blue: 0.55, alpha: 1)   // warm gold
        case 1:  return UIColor(red: 0.70, green: 0.90, blue: 1.00, alpha: 1)   // cool blue
        default: return UIColor(red: 0.92, green: 0.74, blue: 1.00, alpha: 1)   // soft violet
        }
    }

    private static let speakerGlowTexture: SKTexture = {
        let size = CGSize(width: 128, height: 128)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [UIColor(white: 1, alpha: 0.75).cgColor,
                                        UIColor(white: 1, alpha: 0).cgColor] as CFArray,
                               locations: [0, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                 endCenter: CGPoint(x: 64, y: 64), endRadius: 62, options: [])
        }
        return SKTexture(image: image)
    }()

    private static let dialGlowTexture: SKTexture = {
        let size = CGSize(width: 128, height: 68)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 1, alpha: 0.9).cgColor)
            c.addPath(UIBezierPath(roundedRect: CGRect(x: 10, y: 10, width: 108, height: 48),
                                   cornerRadius: 20).cgPath)
            c.fillPath()
        }
        let blurred = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: 0.55)
        }
        return SKTexture(image: blurred)
    }()

    private static let noteTexture: SKTexture = {
        let size = CGSize(width: 36, height: 44)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 1, alpha: 0.92).cgColor)
            c.fillEllipse(in: CGRect(x: 4, y: 26, width: 16, height: 13))
            c.setStrokeColor(UIColor(white: 1, alpha: 0.92).cgColor)
            c.setLineWidth(3.4); c.setLineCap(.round)
            c.move(to: CGPoint(x: 18, y: 33)); c.addLine(to: CGPoint(x: 18, y: 6))
            c.addLine(to: CGPoint(x: 30, y: 12))
            c.strokePath()
        }
        return SKTexture(image: image)
    }()

    /// Shelf icon, drawn from the same texture so the tray promises exactly
    /// what the scene puts on the ground.
    static var icon: UIImage {
        // Drawn from the source image (NOT SKTexture.cgImage(), which returns
        // a vertically flipped bitmap), so the tray shows the radio the right
        // way up and exactly as the scene will place it.
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 42)).image { _ in
            bodyImage.draw(in: CGRect(x: 0, y: 0, width: 40, height: 42))
        }
    }
}
