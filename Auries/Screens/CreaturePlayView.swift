import SwiftUI
import SpriteKit

/// Lets a hosting view (Calm Mode) send commands to the live scene the
/// CreaturePlayView owns (breathing sync, worry release).
@Observable
final class SceneHandle {
    weak var scene: CreatureScene?
}

/// The speech gate, in one place (Stage C): speaking is an occasional extra on
/// top of the guaranteed physical reaction, never the default result. Scripted
/// lines (the daily greeting, Calm entry) bypass this entirely.
private enum SpeechPolicy {
    /// Chance an otherwise-eligible interaction produces a line (~1 in 3).
    static let reactionChance = 0.3
    /// Hard quiet period after any reaction line appears.
    static let cooldown: TimeInterval = 10
    /// How long a reaction line stays up (unchanged from phase 4).
    static let reactionDuration: TimeInterval = 2.6
    /// Toy Box activity lines keep at least this gap after ANY other line;
    /// their own frequency is the director's job (`ToySpeechPolicy`).
    static let toyGap: TimeInterval = 4
}

/// Bubble placement geometry (Stage C).
private enum BubblePlacement {
    /// Keep-inside padding from the play view's edges.
    static let edgePad: CGFloat = 14
    /// Bubble-rect clearance above the head / below the feet. The idle bob
    /// raises the visual body up to 10 pt and the tail dips 10 pt into this
    /// gap, so it stays comfortably clear of both.
    static let bodyClearance: CGFloat = 24
    /// Bubble-rect clearance beside the body for side placements.
    static let sideClearance: CGFloat = 18
    /// End margin of an edge the tail may not slide past (corner radius 22
    /// plus half the tail base), so the tail always sits on a straight run.
    static let tailMargin: CGFloat = 33
    /// Used for the first layout pass, before the bubble reports its size.
    static let fallbackSize = CGSize(width: 220, height: 64)
}

/// Hosts one live creature in its play (or calm) scene, plus its speech
/// bubble: an optional greeting shown once on appear, and occasional reaction
/// barks from the play gestures. The bubble anchors to the creature's
/// *physical* body — published by the scene — so it follows hops and carries,
/// stays inside this view, and points its tail at the creature. Give the view
/// an `.id(aurie.id)` from the caller so a different creature gets a fresh
/// scene. Reused by Home, the full-screen detail view, the hatch reveal, and
/// Calm Mode.
struct CreaturePlayView: View {
    @Environment(AppModel.self) private var model
    let aurie: Aurie
    var greeting: String? = nil
    /// Changes whenever a NEW greeting is chosen (contextual greetings,
    /// 2026-09-27). Keyed separately from the text so two arrivals that
    /// happen to pick the same line still both show — `onChange` on the
    /// text alone would swallow the second.
    var greetingID: UUID? = nil
    /// Fires when the greeting bubble is actually ON SCREEN — which on a
    /// cold launch is seconds after the greeting was chosen and after the
    /// scene appeared (textures load first). Home ties the pointed-at
    /// control's pulses to this, not to the choice.
    var onGreetingShown: (() -> Void)? = nil
    var mode: CreatureScene.Mode = .play
    var handle: SceneHandle? = nil
    /// While true, no speech bubble is shown and any visible one is dismissed.
    /// Wonder sets this: the greeting was competing with the Wonder card.
    var suppressSpeech: Bool = false
    /// Minimum distance the bubble keeps from this view's top edge (Calm Mode
    /// passes extra room so the bubble stays clear of its lower top bar).
    var bubbleTopInset: CGFloat = 14
    /// Opens with the family hatch burst + a birth reaction (reveal screen).
    var celebratesBirth = false
    /// Home passes true: the scene is transparent so the layered
    /// HomeBackgroundView shows behind it.
    var transparentBackground = false

    @State private var scene: CreatureScene?
    @State private var anchor: CreatureScene.PresentationAnchor?
    @State private var bubbleSize: CGSize = .zero
    @State private var bubbleText: String?
    @State private var bubbleDismissTask: Task<Void, Never>?
    @State private var lastReactionLine: String?
    @State private var lastReactionLineAt: Date?

    /// Stage 1 measurement only: SpriteKit's own node/draw/fps counters,
    /// enabled with AURIE_SK_STATS=1.
    static var debugOverlays: SpriteView.DebugOptions {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AURIE_SK_STATS"] == "1" {
            return [.showsFPS, .showsNodeCount, .showsDrawCount]
        }
        #endif
        return []
    }

    var body: some View {
        ZStack {
            if let scene {
                SpriteView(scene: scene,
                           options: transparentBackground ? [.allowsTransparency] : [],
                           debugOptions: Self.debugOverlays)
                    .background(.clear)
            }
        }
        .overlay { bubbleOverlay }
        // Keyed to the text only: appear/disappear springs, while per-frame
        // position updates from the anchor render immediately (no implicit
        // spring on tracking — motion polish is Stage D's job).
        .animation(.spring(duration: 0.35), value: bubbleText)
        .onAppear {
            guard scene == nil else { return }   // one persistent scene per creature
            let newScene = CreatureScene(aurie: aurie, mode: mode)
            newScene.celebratesBirth = celebratesBirth
            newScene.transparentBackground = transparentBackground
            newScene.onReactionLine = { makeLine in maybeShowReaction(makeLine) }
            newScene.onToyLine = { line in showToyLine(line) }
            // "Old Friends" counts DAYS on which the player actually
            // touched an Aurie. The scene fires on every touch; the model
            // collapses that to at most one event per calendar day.
            newScene.onInteraction = { model.recordAurieInteraction() }
            newScene.onAnchorChange = { anchor = $0 }
            scene = newScene
            handle?.scene = newScene
            if let greeting {
                SoundPlayer.play("sfx_appear")
                show(greeting, for: 4.5)
            }
        }
        // LIVE equipment updates (bug fix 2026-09-17): the scene is
        // deliberately built ONCE and keyed by the Aurie's id, so an
        // equip/remove in the Charms tab used to leave an already-live
        // Home scene drawing stale wearables until relaunch. Forward
        // the new Aurie value to the existing scene; the refresh is
        // targeted (layer stack only) and a no-op when nothing changed.
        .onChange(of: aurie.resolvedEquippedCharms) { _, _ in
            scene?.refreshEquipment(aurie)
        }
        // A greeting that arrives AFTER the scene exists (a return from a
        // long background, a DEBUG replay): show it the same way the
        // on-appear greeting is shown. The scene-creation path above stays
        // exactly as it was, so the first greeting is never shown twice.
        .onChange(of: greetingID) { _, id in
            guard id != nil, scene != nil, let greeting, !suppressSpeech else { return }
            show(greeting, for: 4.5)
        }
        .onChange(of: suppressSpeech) { _, quiet in
            if quiet {
                bubbleDismissTask?.cancel()
                bubbleText = nil
            }
        }
        // The greeting is genuinely on screen only once its bubble is built
        // AND the creature it hangs from has faded in. On a cold launch the
        // anchor arrives late and flips once, so an `onAppear` on the bubble
        // reported too early (Home not yet rendered) and then again — this
        // reports exactly once, at real visibility. Reaction lines never
        // report; only the greeting text does.
        .onChange(of: greetingOnScreen) { _, shown in
            if shown { onGreetingShown?() }
        }
        .onDisappear {
            // Leaving the host screen ends the presentation cleanly; the
            // scene (and its idle/greeting state) lives on untouched —
            // except the radio, whose looping music must never outlive the
            // screen that owns it (SwiftUI can drop this view without the
            // SKView ever calling the scene's willMove(from:)).
            scene?.setRadio(out: false)
            bubbleDismissTask?.cancel()
            bubbleText = nil
        }
    }

    // MARK: Bubble presentation

    /// See the `onChange` in `body`: built bubble + visible creature.
    private var greetingOnScreen: Bool {
        bubbleText != nil && bubbleText == greeting && anchor?.visible == true
    }

    @ViewBuilder
    private var bubbleOverlay: some View {
        GeometryReader { geo in
            // Wait for the creature to be visible (it fades in on scene start)
            // so the bubble never floats over an empty play space.
            if let bubbleText, anchor?.visible != false {
                let layout = bubbleLayout(in: geo.size)
                SpeechBubble(text: bubbleText, tail: layout.tail)
                    // Measure the bubble itself (short lines hug their text);
                    // the flexible frame outside would report maxWidth.
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { bubbleSize = $0 }
                    .frame(maxWidth: min(geo.size.width - 2 * BubblePlacement.edgePad,
                                         HomeTokens.bubbleMaxWidth))
                    .position(layout.position)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .allowsHitTesting(false)   // informational only — never blocks play gestures
    }

    private struct BubbleLayout {
        var position: CGPoint
        var tail: SpeechBubble.Tail
    }

    /// Place the bubble near the physical body: above it when there is room,
    /// else beside it on whichever side has more space, else — last resort —
    /// below it. Always fully inside this view, tail pointing at the creature.
    ///
    /// Scene coordinates are centre-origin with y up (anchorPoint 0.5/0.5;
    /// `.resizeFill` keeps scene size == view size), so a scene point maps to
    /// view coordinates as (W/2 + x, H/2 − y).
    private func bubbleLayout(in viewSize: CGSize) -> BubbleLayout {
        let s = bubbleSize == .zero ? BubblePlacement.fallbackSize : bubbleSize
        let cx = viewSize.width / 2 + (anchor?.center.x ?? 0)
        let cy = viewSize.height / 2 - (anchor?.center.y ?? 0)
        let halfW = anchor?.halfWidth ?? 80
        let headTop = cy - (anchor?.halfUp ?? 80)
        let feetBottom = cy + (anchor?.halfDown ?? 90)

        let pad = BubblePlacement.edgePad
        let topPad = max(pad, bubbleTopInset)
        let clampX = { (x: CGFloat) in
            min(max(x, pad + s.width / 2), viewSize.width - pad - s.width / 2)
        }
        let tailRunX = max(0, s.width / 2 - BubblePlacement.tailMargin)
        let tailRunY = max(0, s.height / 2 - BubblePlacement.tailMargin)

        // 1. Above the creature, horizontally centred over the body.
        if headTop - BubblePlacement.bodyClearance - s.height >= topPad {
            let x = clampX(cx)
            return BubbleLayout(
                position: CGPoint(x: x, y: headTop - BubblePlacement.bodyClearance - s.height / 2),
                tail: .init(edge: .bottom, offset: min(max(cx - x, -tailRunX), tailRunX)))
        }

        // 2. Beside the creature, on whichever side has more room.
        let leftSpace = cx - halfW - pad
        let rightSpace = viewSize.width - pad - (cx + halfW)
        if max(leftSpace, rightSpace) >= s.width + BubblePlacement.sideClearance {
            let left = leftSpace >= rightSpace
            let x = left ? cx - halfW - BubblePlacement.sideClearance - s.width / 2
                         : cx + halfW + BubblePlacement.sideClearance + s.width / 2
            let y = min(max(headTop + s.height * 0.35, topPad + s.height / 2),
                        viewSize.height - pad - s.height / 2)
            return BubbleLayout(
                position: CGPoint(x: x, y: y),
                tail: .init(edge: left ? .trailing : .leading,
                            offset: min(max(cy - y, -tailRunY), tailRunY)))
        }

        // 3. Below the feet — only when neither above nor a side fits.
        let x = clampX(cx)
        return BubbleLayout(
            position: CGPoint(x: x,
                              y: min(feetBottom + BubblePlacement.bodyClearance + s.height / 2,
                                     viewSize.height - pad - s.height / 2)),
            tail: .init(edge: .top, offset: min(max(cx - x, -tailRunX), tailRunX)))
    }

    // MARK: Line lifecycle

    /// The speech gate: every interaction keeps its physical reaction; a line
    /// appears only occasionally, never stacked, never in rapid succession.
    /// Toy Box activity dialogue (`ToyDialogue`). The director upstream owns
    /// frequency; this is only the overlap rule: never replace a greeting or
    /// a reaction line, keep a short gap after any line, and stay quiet when
    /// Wonder owns the screen. Returns whether the line went up, so a start
    /// line can be retried later instead of lost.
    private func showToyLine(_ text: String) -> Bool {
        guard !suppressSpeech, bubbleText == nil else { return false }
        if let at = lastReactionLineAt,
           Date().timeIntervalSince(at) < SpeechPolicy.toyGap { return false }
        lastReactionLine = text
        lastReactionLineAt = Date()
        show(text, for: SpeechPolicy.reactionDuration)
        return true
    }

    private func maybeShowReaction(_ makeLine: () -> String) {
        guard !suppressSpeech else { return }     // Wonder owns the screen
        guard bubbleText == nil else { return }   // one bubble at a time; no roll while visible
        if let at = lastReactionLineAt,
           Date().timeIntervalSince(at) < SpeechPolicy.cooldown { return }
        guard Double.random(in: 0..<1) < SpeechPolicy.reactionChance else { return }
        var line = makeLine()
        var rerolls = 0
        while line == lastReactionLine, rerolls < 3 {   // no immediate repeat when alternatives exist
            line = makeLine()
            rerolls += 1
        }
        lastReactionLine = line
        lastReactionLineAt = Date()
        show(line, for: SpeechPolicy.reactionDuration)
    }

    private func show(_ text: String, for seconds: Double) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AURIE_GREET_LOG"] == "1" {
            NSLog("AURIE_BUBBLE \"%@\"", text)
        }
        #endif
        bubbleDismissTask?.cancel()
        bubbleText = text
        bubbleDismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { bubbleText = nil }
        }
    }
}
