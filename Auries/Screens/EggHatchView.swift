import SpriteKit
import SwiftUI

/// Full-screen egg flow (mockup screens 3-5): the egg, colored from the
/// photographed object, cracks over three taps, bursts in sparkles, and
/// reveals the new creature — already auto-saved (§7; a hatch is never
/// wasted), so the only button is "Continue".
/// TODO(step 6): crack/hatch sounds via SoundPlayer, respecting mute.
/// TODO(art): swap the drawn egg + sparkles for real egg art when it exists.
/// One temporary pre-hatch mood (§8.1) — rolled per egg, part of the moment,
/// never stored.
enum EggPersonality: String, Codable, CaseIterable {
    case wobbly, sleepy, shy, heavy, sparkly, mystery
}

struct EggHatchView: View {
    let pending: PendingHatch

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var crackStage = 0
    @State private var wobble = false
    @State private var bursting = false
    /// Shared 0->1 driver for the recovered seven-piece burst; each piece
    /// derives its own staggered slice from the approved delay/duration.
    @State private var burstProgress: Double = 0
    /// Draw-on progress for the four cumulative fracture stages (taps 1-4).
    @State private var stageProgress: [CGFloat] = [0, 0, 0, 0]
    /// The seven tap-5 rim seams that finally divide the shell.
    @State private var seamProgress: CGFloat = 0
    /// Faded out before any piece separates, per the recovered timing.
    @State private var promptOpacity: Double = 1
    @State private var stageSize: CGSize = UIScreen.main.bounds.size
    /// The intact shell captured at the instant of separation; every
    /// fragment is a masked view of THIS bitmap, so the pieces carry the
    /// same shading, markings and tint and reassemble exactly.
    @State private var shellSnapshot: UIImage?
    /// The generated Aurie, created ONCE and then reused by both the in-scene
    /// reveal and the profile screen — never generated twice, never re-rolled.
    ///
    /// Generated as soon as the egg appears rather than on the final tap.
    /// Generation is free (0 ms) and spends nothing — but BUILDING THE SCENE
    /// from it costs ~88 ms of texture decode and node construction, and on
    /// the final tap that delay pushed the shell burst from 302 ms to 390 ms.
    /// The scene is therefore warmed early with the creature hidden.
    @State private var preview: Aurie?
    /// Exactly-once latch for the final tap.
    @State private var burstStarted = false
    /// In-scene arrival: the Aurie exists beneath the shell and fades up as
    /// the pieces clear it, so nothing hard-cuts.
    @State private var aurieVisible = false
    /// Set on the final tap, a beat BEFORE the burst: the egg eases out of its
    /// idle personality transform so the intact shell and the fragment
    /// container hand off at identical geometry.
    @State private var settling = false
    private var settled: Bool { settling || bursting }
    @State private var hatched: Aurie?
    /// The shell's on-screen frame (global coords), reported by layout so
    /// the creature scene's egg-interior clip lands EXACTLY on the drawn
    /// egg — no hand-tuned offsets.
    @State private var eggGlobalFrame: CGRect = .zero
    /// The committed hatch's Birth-Charm outcome, for the reveal card.
    /// TRANSIENT (never persisted): written only where `commitHatch`
    /// returns, so it can only ever describe a real committed hatch.
    @State private var birthReveal: BirthCharmReveal?
    /// The reveal scene is torn down a beat AFTER the profile screen arrives,
    /// so the two always overlap instead of crossfading through nothing.
    @State private var hatchHostRetired = false
    @State private var personality = EggPersonality.allCases.randomElement()!
    @State private var idlePhase = false
    @State private var flinched = false

    /// FIVE taps, restored from the frozen sequence: four grow the fracture
    /// network, the fifth completes the seven rim seams. The 3-tap value was
    /// a placeholder on this branch and burst the egg before the shell was
    /// ever fully divided.
    private let tapsToHatch = EggFracture.tapStages.count + 1

    /// Rare odd-tint egg (§8.9): ~1 in 20 eggs leans a little off its
    /// object's colour. Pure delight; the creature is unaffected.
    @State private var oddTint = Int.random(in: 0..<20) == 0

    var body: some View {
        ZStack {
            background
            // The reveal host is FULL SCREEN and transparent. It used to be
            // sized to the creature (399x422), which clipped the glow's
            // falloff and showed the container as a hard-edged rectangle.
            // Sized to the whole screen, every effect fades out well inside
            // its own bounds, so no edge can appear.
            // Held past `hatched` on purpose: RevealView fades in over this,
            // and its environment art needs a moment to draw. Dropping this
            // host the instant `hatched` was set left one empty frame between
            // the two screens.
            if let preview, !hatchHostRetired, !burstHoldSuppressesCreature {
                // No opacity or scale animation: the Aurie is a solid object
                // sitting inside the egg from the moment it is generated. The
                // SHELL is the reveal mechanism — see `bursting` below.
                HatchAurieView(aurie: preview, footprint: 230 * 1.02,
                               // EGG-INTERIOR CLIP (2026-09-19): at the
                               // first bursting instant the fragments
                               // have barely moved, so a body/hair/limb
                               // wider than the shell would pop in
                               // OUTSIDE it. The creature renders
                               // through an egg-silhouette crop that
                               // expands with the burst and is removed
                               // once the fragments have cleared.
                               eggFrame: eggGlobalFrame,
                               clipRelease: 0.80 * slowMo * 0.55,
                               revealing: bursting,
                               // Unhide on the SAME frame the shell
                               // fragments begin to separate — never
                               // earlier. Between the final tap and the
                               // burst (the anticipation beat) only the
                               // intact shell occludes the creature, so
                               // any part taller than the egg (a
                               // mohawk, a future head charm) leaked
                               // out the top. The scene stays pre-built
                               // and warm; this gates VISIBILITY only,
                               // and it gates the WHOLE AurieNode
                               // (body, pattern, belly, limbs, face,
                               // hair, charms) as one unit.
                               creatureHidden: !bursting)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
            if let hatched {
                RevealView(aurie: hatched, photo: pending.image,
                           birthCharm: birthReveal)
            } else {
                eggStage        // shell + fragments stay IN FRONT of the reveal
            }
        }
        .overlay(alignment: .topTrailing) {
            // Cancel is only offered before the creature exists.
            if hatched == nil {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(20)
            }
        }
    }

    /// Deep night backdrop with a soft glow in the egg's (object's) color.
    /// The screen's own atmosphere. During the egg phase it is the quiet
    /// original wash; at the reveal it blooms into a family-lit space so the
    /// creature emerges INTO somewhere rather than onto a dark rectangle.
    private var background: some View {
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.10)
            RadialGradient(colors: [Color(glowColor, brightness: 0.55)
                                        .opacity(aurieVisible ? 0.62 : 0.55),
                                    .clear],
                           center: .center, startRadius: 10,
                           endRadius: aurieVisible ? 430 : 340)
            // A second, lower centre sits under the creature so the lower
            // half of the screen is lit too — the old single wash left the
            // reveal area reading as empty space.
            RadialGradient(colors: [Color(glowColor, brightness: 0.42)
                                        .opacity(aurieVisible ? 0.22 : 0),
                                    .clear],
                           center: UnitPoint(x: 0.5, y: 0.60),
                           startRadius: 20, endRadius: 420)
            // Vignette: the reference keeps real depth at the edges, which
            // a single flat wash loses.
            RadialGradient(colors: [.clear,
                                    Color(red: 0.03, green: 0.03, blue: 0.06)
                                        .opacity(0.75)],
                           center: .center, startRadius: 220, endRadius: 640)
        }
        .animation(.easeOut(duration: 0.9), value: aurieVisible)
        .ignoresSafeArea()
    }

    private var glowColor: Rgb { hatched?.auraColor ?? pending.dominantColor }

    private var eggStage: some View {
        VStack(spacing: 18) {
            Text(crackStage == 0 ? "An egg is ready!" : "Tap to hatch!")
                .opacity(promptOpacity)
                .font(.title.weight(.bold))
            Text(crackStage == 0 ? "Tap the egg to hatch it." : " ")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Intact egg and the seven-piece burst are the SAME shell view:
            // before separation it is drawn whole, after it is drawn through
            // the seven piece masks, which partition that shell's alpha
            // exactly. Nothing is re-rendered at the hand-off, so there is no
            // silhouette jump.
            ZStack {
                // Beneath the shell: revealed in place, so the creature is
                // never a cut to a blank stage.
                if bursting, let snapshot = shellSnapshot {
                    EggBurstFragmentsView(shell: snapshot,
                                          t: burstProgress,
                                          stageSize: stageSize)
                } else {
                    EggView(color: eggColor, stageProgress: stageProgress,
                            seamProgress: seamProgress)
                }
            }
            .frame(width: 230, height: 300)
            // Report where the shell actually sits on screen, for the
            // creature scene's egg-interior clip.
            .background(GeometryReader { geo in
                Color.clear.onAppear { eggGlobalFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, f in
                        eggGlobalFrame = f
                    }
            })
            // The reveal stage is larger than the egg frame, so nothing is
            // clipped by the container the shell used.
            .fixedSize(horizontal: false, vertical: false)
            // The shell's glow is drawn from a STABLE silhouette behind the
            // content rather than as a `.shadow` on it. A shadow is derived
            // from the alpha of whatever it is attached to, and the
            // seven-piece representation has internal seam edges the intact
            // egg does not — so on the swap frame the glow suddenly lit a
            // hairline along every crack. Measured: the fragment state came
            // out lighter on 20% of egg pixels, concentrated on the seams.
            .background {
                EggShape()
                    .fill(eggColor.opacity(0.6))
                    .frame(width: 230, height: 300)
                    .blur(radius: 40)
                    .opacity(bursting
                             ? max(0, 1 - burstProgress / 0.6) : 1)
            }
            .scaleEffect(settled ? 1.0 : (flinched ? 0.96 : personalityScale))
            .opacity(settled ? 1 : personalityOpacity)
            .rotationEffect(.degrees(settled ? 0 : (wobble ? 3 : personalityTilt)))
            .offset(y: settled ? 0 : (flinched ? 6 : 0))
            .overlay { if personality == .sparkly && !bursting { sparklePops } }
            .padding(.top, 8)
            .onTapGesture(perform: tapEgg)
        }
        // Each egg has one temporary pre-hatch personality (§8.1): a slow
        // idle beat that makes it behave a little oddly before it cracks.
        .task {
            // Warm the reveal scene while the player is still cracking, with
            // the creature hidden. Generation spends nothing — §11 still
            // holds, because the hatch is only committed after the burst.
            if preview == nil {
                var born = model.generateHatch(pending)
                #if DEBUG
                // Capture aid: regenerate until the DETERMINISTIC
                // birth outcome is a win — selection through the real
                // resolver, never a logic bypass. Lets the frame-strip
                // evidence force a winning hatch reproducibly.
                // AURIE_HATCH_FORCE_BIRTH=1
                if ProcessInfo.processInfo
                    .environment["AURIE_HATCH_FORCE_BIRTH"] == "1" {
                    var tries = 0
                    while model.birthCharmOutcome(
                              for: born,
                              recognized: pending.recognized)?.wins != true,
                          tries < 500 {
                        born = model.generateHatch(pending)
                        tries += 1
                    }
                }
                // Capture aid: pin the rolled hair so the reveal can be
                // verified per style (tuft | hair_00 | hair_01).
                if let hair = ProcessInfo.processInfo
                    .environment["AURIE_HATCH_HAIR"] {
                    born.hairStyle = hair
                }
                // Capture aid: pin the rolled body the same way, so
                // worst-case stage-fit geometry (tall, crown-heavy) can
                // be verified deterministically. AURIE_HATCH_BODY=tall
                if let raw = ProcessInfo.processInfo
                    .environment["AURIE_HATCH_BODY"],
                   let body = BodyType(rawValue: raw) {
                    born.body = body
                }
                #endif
                // HATCH-TIMING RULE (2026-09-19): a newborn that wins
                // its Birth-Charm roll is DRESSED before the creature
                // is ever unhidden — the first post-shell frame already
                // wears the charm, and the reveal card later merely
                // reports it. Pure value transform; a cancelled egg
                // still leaves zero permanent state.
                preview = model.dressedForBirth(born, from: pending)
            }
        }
        .task {
            while !Task.isCancelled && hatched == nil && !settling {
                withAnimation(.easeInOut(duration: personalityBeat)) { idlePhase.toggle() }
                try? await Task.sleep(for: .seconds(personalityBeat))
            }
        }
        #if DEBUG
        // Capture aid: crack the egg all the way through the REAL tap handler
        // so the reveal (and its swirl) can be recorded without tapping.
        // AURIE_HATCH_AUTO=1
        .task {
            guard ProcessInfo.processInfo.environment["AURIE_HATCH_AUTO"] == "1",
                  !HatchDebugHooks.autoCrackFired
            else { return }
            HatchDebugHooks.autoCrackFired = true
            try? await Task.sleep(for: .seconds(1.4))
            while !Task.isCancelled && hatched == nil && crackStage < tapsToHatch {
                tapEgg()
                try? await Task.sleep(for: .seconds(0.45))
            }
        }
        #endif
    }

    // Personality idle parameters (wobbly rocks, sleepy breathes, heavy barely
    // stirs, mystery shimmers, shy/sparkly react elsewhere).
    private var personalityBeat: Double {
        switch personality {
        case .wobbly: 1.2
        case .sleepy: 2.8
        case .heavy: 2.2
        case .mystery: 2.4
        default: 1.6
        }
    }
    private var personalityTilt: Double {
        switch personality {
        case .wobbly: idlePhase ? 3.5 : -3.5
        case .heavy: idlePhase ? 0.7 : -0.7
        default: 0
        }
    }
    private var personalityScale: CGFloat {
        personality == .sleepy ? (idlePhase ? 1.035 : 0.99) : 1
    }
    private var personalityOpacity: Double {
        personality == .mystery ? (idlePhase ? 0.82 : 1.0) : 1
    }


    private var sparklePops: some View {
        ForEach(0..<3, id: \.self) { i in
            Image(systemName: "sparkle")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(idlePhase == (i % 2 == 0) ? 0.9 : 0))
                .offset(x: [-70, 62, 18][i], y: [-60, -20, 95][i])
        }
    }

    /// Snapshot the fully-cracked shell at display scale, offscreen and at
    /// neutral geometry, so the burst never captures a mid-idle transform.
    @MainActor private func renderShellSnapshot() -> UIImage? {
        let renderer = ImageRenderer(content:
            EggView(color: eggColor, stageProgress: [1, 1, 1, 1],
                    seamProgress: 1)
                .frame(width: 230, height: 300))
        renderer.scale = UIScreen.main.scale
        renderer.isOpaque = false
        return renderer.uiImage
    }

    private var eggColor: Color {
        guard oddTint else { return Color(AurieGenerator.shellColor(pending.dominantColor)) }
        // Rare odd egg: nudge the hue a little.
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Color(AurieGenerator.shellColor(pending.dominantColor)))
            .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(uiColor: UIColor(hue: (h + 0.09).truncatingRemainder(dividingBy: 1),
                                      saturation: s, brightness: b, alpha: a))
    }

    private func tapEgg() {
        guard !bursting else { return }

        // Shy eggs flinch away from the very first touch (§8.1).
        if personality == .shy && !flinched && crackStage == 0 {
            withAnimation(.spring(duration: 0.3)) { flinched = true }
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                withAnimation(.spring(duration: 0.5)) { flinched = false }
            }
        }

        crackStage += 1
        SoundPlayer.play(crackStage >= tapsToHatch ? "sfx_hatch" : "sfx_crack")
        Haptics.light()

        // Quick wobble on every tap (heavier eggs barely budge).
        let wobbleAmount: Double = personality == .heavy ? 0.4 : 1
        withAnimation(.spring(duration: 0.12 * wobbleAmount + 0.06)) { wobble = true }
        withAnimation(.spring(duration: 0.25).delay(0.12)) { wobble = false }

        // Taps 1-4 grow the fracture network; nothing separates yet.
        if crackStage <= EggFracture.tapStages.count {
            withAnimation(.easeOut(duration: 0.34)) {
                stageProgress[crackStage - 1] = 1
            }
            return
        }
        guard crackStage >= tapsToHatch else { return }

        // Tap 5, recovered timing: the prompt leaves first, the seven rim
        // seams complete, the fully fractured shell HOLDS for one readable
        // beat, and only then do the pieces separate.
        withAnimation(.easeOut(duration: 0.10)) { promptOpacity = 0 }
        // Seams must COMPLETE before the representation swap, otherwise the
        // fragment bitmap (always rendered at seamProgress 1) pops against a
        // still-drawing intact egg. Shortened to fit inside the new, much
        // tighter anticipation beat.
        withAnimation(.easeOut(duration: 0.11)) { seamProgress = 1 }
        // The egg leaves its idle personality BEFORE the burst. The intact
        // shell and the fragment container are the same pixels, but the
        // container's transform used to snap from the live personality tilt /
        // scale / opacity to neutral on the frame `bursting` flipped — a
        // one-frame jump of the whole egg right at the hand-off.
        withAnimation(.easeOut(duration: 0.22)) { settling = true }

        // The egg must respond almost immediately, so the anticipation beat
        // is short — but the separation itself is what wants the time, so the
        // flight is long. Time moved out of the pause and into the motion:
        // the pause is dead, the flight is the thing worth watching.
        let anticipation = 0.13 * slowMo
        let flight = 0.80 * slowMo

        // The creature already exists and its scene is already built; this
        // only un-hides it, which is free. Nothing generated, nothing decoded
        // and nothing written on this tap — the burst below starts on the
        // original schedule.
        guard !burstStarted, let born = preview else { return }
        burstStarted = true
        #if DEBUG
        HatchDebugHooks.tapFive = CFAbsoluteTimeGetCurrent()
        #endif

        // A. the burst, on the ORIGINAL schedule and unaffected by any of the
        //    above: release begins at 0.30 s, pieces fly for `flight`.
        Task { @MainActor in
            // Render the burst bitmap DURING the anticipation beat, not at
            // the instant of release. `ImageRenderer` is synchronous, and at
            // the release instant it delayed the first fragment by ~90 ms.
            // Its inputs are fixed ([1,1,1,1], seamProgress 1), so rendering
            // it early produces an identical image.
            let snap = renderShellSnapshot()
            try? await Task.sleep(for: .seconds(anticipation))
            shellSnapshot = snap
            #if DEBUG
            NSLog("AURIE_T burstStart +%.0fms",
                  (CFAbsoluteTimeGetCurrent() - HatchDebugHooks.tapFive) * 1000)
            #endif
            bursting = true
            #if DEBUG
            // AURIE_BURST_HOLD=1 freezes the hand-off frame: the shell swaps
            // to the seven-piece representation at t=0 and NOTHING else
            // changes, so the two states can be diffed pixel-for-pixel.
            if burstHold { return }
            #endif
            aurieVisible = true
            // NOT `.easeOut`: that is cubic-bezier(0, 0, 0.58, 1), whose
            // initial velocity is unbounded — the pieces leave at maximum
            // speed on frame one and read as a cannon blast. This curve has
            // a brief, finite acceleration and then a long deceleration, so
            // the opening is readable and the travel still feels decisive.
            // Control points matter more than `duration` here: a second
            // control point pulled to y=1 early (e.g. 0.35, 1.0) makes the
            // curve flatten at ~a third of the duration, so a 0.75 s flight
            // actually finished in 0.26 s. These spread the travel across the
            // whole flight — initial slope ~2.3 for a quick, finite start,
            // then a long graceful deceleration.
            withAnimation(.timingCurve(0.12, 0.28, 0.55, 0.92,
                                       duration: flight)) {
                burstProgress = 1
            }
            if born.family == .starlight { Haptics.success() } else { Haptics.medium() }
        }

        // B. persistence, concurrent with the flight. `store.add` blocks the
        //    main actor for ~261 ms, so it runs where it always used to — the
        //    shell is already moving and nothing is waiting on it.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(anticipation + flight * 0.18))
            // `saved` differs from `born` only by `sourceThumbnail` (and,
            // for a Birth-Charm hatch, the worn charm), so the already-
            // built scene needs no update — it is the same creature. The
            // commit result also carries the TRANSIENT Birth-Charm reveal:
            // this is the ONLY place `birthReveal` is ever set, so the
            // reward card can never describe anything but a successfully
            // committed hatch (a cancelled egg never reaches this Task).
            let result = model.commitHatch(born, from: pending)
            let saved = result.aurie
            birthReveal = result.birthCharm
            #if DEBUG
            NSLog("AURIE_T committed +%.0fms",
                  (CFAbsoluteTimeGetCurrent() - HatchDebugHooks.tapFive) * 1000)
            #endif

            // Readable in-scene beat before the profile screen takes over.
            try? await Task.sleep(for: .seconds(flight * 0.9 + 1.1))
            #if DEBUG
            NSLog("AURIE_T settled +%.0fms",
                  (CFAbsoluteTimeGetCurrent() - HatchDebugHooks.tapFive) * 1000)
            #endif
            withAnimation(.easeInOut(duration: 0.35)) { hatched = saved }
            // Only now is the reveal scene safe to drop: the profile screen
            // has drawn and is fully opaque on top of it.
            try? await Task.sleep(for: .seconds(0.6))
            hatchHostRetired = true
        }
    }

    #if DEBUG
    /// Stretches ONLY the burst hand-off so it can be reviewed frame by frame.
    /// AURIE_HATCH_SLOWMO=8
    private var slowMo: Double {
        Double(ProcessInfo.processInfo.environment["AURIE_HATCH_SLOWMO"] ?? "")
            ?? 1
    }
    /// Freeze the shell hand-off for an A/B geometry comparison.
    private var burstHold: Bool {
        ProcessInfo.processInfo.environment["AURIE_BURST_HOLD"] == "1"
    }
    /// During the A/B the creature is left out entirely, so the only thing
    /// that can differ between the two captures is the shell representation.
    private var burstHoldSuppressesCreature: Bool { burstHold }
    #else
    private var slowMo: Double { 1 }
    private var burstHoldSuppressesCreature: Bool { false }
    #endif
}

/// The egg shell: the Blender-rendered neutral shell multiplied by the
/// family shell colour, with the SAME `EggShape` silhouette, the same crack
/// overlay and the same timing as before — only the material changed.
///
/// The render is cropped to its own outline, so it maps 1:1 onto the rect
/// `EggShape` used and the existing crack paths still land where they did.
/// The neutral is mid-grey (#C0C0C0, measured at 0% clipping), so the
/// multiply lands deeper than the revealed creature: that is the intended
/// pre-hatch mystery, not a lucky accident.
private struct EggView: View {
    let color: Color
    /// Draw-on progress for fracture stages 1-4 and the tap-5 seams.
    let stageProgress: [CGFloat]
    let seamProgress: CGFloat

    var body: some View {
        ZStack {
            shell
                .overlay(EggFractureView(stageProgress: stageProgress,
                                         seamProgress: seamProgress))
        }
    }

    @ViewBuilder private var shell: some View {
        if let image = UIImage(named: "aurie_egg_shell") {
            Image(uiImage: image)
                .resizable()
                .colorMultiply(color)
        } else {
            // Placeholder fallback, kept so a missing asset cannot break the
            // hatch flow.
            EggShape()
                .fill(color)
                .overlay(speckles.clipShape(EggShape()))
        }
    }

    private var speckles: some View {
        GeometryReader { geo in
            let spots: [(CGFloat, CGFloat, CGFloat)] = [
                (0.30, 0.35, 0.06), (0.62, 0.25, 0.05), (0.72, 0.55, 0.07),
                (0.40, 0.68, 0.05), (0.25, 0.55, 0.04), (0.55, 0.82, 0.05),
            ]
            ForEach(Array(spots.enumerated()), id: \.offset) { _, s in
                Circle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: geo.size.width * s.2 * 2)
                    .position(x: geo.size.width * s.0, y: geo.size.height * s.1)
            }
        }
    }
}

/// Classic egg silhouette: rounder at the bottom, narrower at the top.
private struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.minX + w, y: rect.minY + h * 0.62),
                   control1: CGPoint(x: rect.minX + w * 0.86, y: rect.minY + h * 0.02),
                   control2: CGPoint(x: rect.minX + w, y: rect.minY + h * 0.35))
        p.addCurve(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h),
                   control1: CGPoint(x: rect.minX + w, y: rect.minY + h * 0.86),
                   control2: CGPoint(x: rect.minX + w * 0.78, y: rect.minY + h))
        p.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.62),
                   control1: CGPoint(x: rect.minX + w * 0.22, y: rect.minY + h),
                   control2: CGPoint(x: rect.minX, y: rect.minY + h * 0.86))
        p.addCurve(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY),
                   control1: CGPoint(x: rect.minX, y: rect.minY + h * 0.35),
                   control2: CGPoint(x: rect.minX + w * 0.14, y: rect.minY + h * 0.02))
        p.closeSubpath()
        return p
    }
}

/// Zigzag cracks that grow with each tap.
private struct CrackShape: Shape {
    let stage: Int

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard stage >= 1 else { return p }
        let w = rect.width, h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }
        // First crack: a zigzag across the upper third.
        p.move(to: pt(0.18, 0.40))
        p.addLine(to: pt(0.34, 0.33))
        p.addLine(to: pt(0.46, 0.42))
        p.addLine(to: pt(0.60, 0.31))
        p.addLine(to: pt(0.74, 0.40))
        if stage >= 2 {
            // Branches downward.
            p.move(to: pt(0.46, 0.42))
            p.addLine(to: pt(0.42, 0.56))
            p.addLine(to: pt(0.52, 0.66))
            p.move(to: pt(0.60, 0.31))
            p.addLine(to: pt(0.66, 0.20))
            p.move(to: pt(0.34, 0.33))
            p.addLine(to: pt(0.28, 0.52))
        }
        return p
    }
}

/// Mockup screen 5: the new creature, live, with its "born from" card.
private struct RevealView: View {
    let aurie: Aurie
    let photo: UIImage
    /// The committed hatch's Birth-Charm outcome. nil = ordinary hatch
    /// (or a pre-Phase-D flow): no charm row appears at all.
    let birthCharm: BirthCharmReveal?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            Text(aurie.name)
                .font(.largeTitle.weight(.bold))
                .padding(.top, 24)
            Text("Meet \(aurie.name).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            CreaturePlayView(aurie: aurie, celebratesBirth: true)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 24)
                .padding(.top, 6)

            // The creature's identity, right at birth (§6): line + trio.
            Text("“\(aurie.line)”")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Text(aurie.traits.map(\.capitalized).joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            bornFromCard
                .padding(.horizontal, 24)

            if let birthCharm {
                birthCharmCard(birthCharm)
                    .padding(.horizontal, 24)
            }

            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(aurie.auraColor, brightness: 0.75))
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    /// The Birth-Charm row (Phase D): same quiet card language as
    /// `bornFromCard`, never a modal or celebration. "unlocked" appears
    /// ONLY when this commit was the account's first unlock; an
    /// already-owned charm still shows as this Aurie's origin without
    /// implying a new reward. Artwork is the shared CharmArt treatment.
    private func birthCharmCard(_ reveal: BirthCharmReveal) -> some View {
        HStack(spacing: 12) {
            Group {
                if let def = AurieCharmCatalog.definition(reveal.charmID) {
                    CharmArt(def: def)
                } else {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(Color(aurie.auraColor))
                    Text(reveal.newlyUnlocked
                         ? "Birth Charm unlocked" : "Birth Charm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(AurieCharmCatalog.definition(reveal.charmID)?
                        .displayName ?? "Charm")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var bornFromCard: some View {
        HStack(spacing: 12) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text("born from \(aurie.bornFrom)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(aurie.auraColor))
                        .frame(width: 9, height: 9)
                    Text("\(aurie.family.rawValue.capitalized) Family")
                        .font(.subheadline.weight(.semibold))
                }
            }
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - In-scene hatch reveal

/// The freshly hatched Aurie, revealed inside the hatch scene.
///
/// The stage is deliberately much larger than the creature. The first
/// version sized the SpriteView to the creature itself (143 pt square), so
/// the celebration hop — which lifts the visual root by 78 scene units —
/// ran straight out of the view and clipped. The container now carries the
/// resting body PLUS hop headroom PLUS tuft/hand margin, and the creature's
/// size is set independently by `footprint`.
private struct HatchAurieView: View {
    let aurie: Aurie
    /// Target on-screen width of the body+limb footprint, in points.
    let footprint: CGFloat
    /// The shell's on-screen frame (global), for the egg-interior clip.
    let eggFrame: CGRect
    /// Seconds after `revealing` before the clip has fully expanded and
    /// is removed — sized to the fragment flight, so the reveal opening
    /// tracks the shell pieces.
    let clipRelease: TimeInterval
    /// Flips true the instant the shell fragments begin to separate. The
    /// creature is mounted BEFORE this; only the light show waits for it.
    let revealing: Bool
    /// The scene is built early — texture decode and node construction cost
    /// ~88 ms and must not land on the final tap — but the creature stays
    /// hidden until the hatch actually commits, so nothing haloes out around
    /// an egg that has not been opened yet.
    let creatureHidden: Bool
    @State private var scene: HatchAurieScene?
    /// EGG-INTERIOR CLIP (2026-09-19): until the burst fragments have
    /// cleared, the WHOLE creature scene renders through one egg-
    /// silhouette mask sized to the MEASURED shell frame, so nothing —
    /// body, hair, limbs, charm — can protrude outside the still-
    /// enclosing shell at the first bursting instant. The mask grows
    /// with the burst (ease-in keeps the first instants shell-tight)
    /// and is then dropped entirely. Implemented on the hosting SwiftUI
    /// view because SKCropNode segfaults the Metal renderer over this
    /// shader-tinted node tree (two crash reports on record).
    @State private var clipActive = true
    @State private var clipGrow: CGFloat = 1.0
    /// Slightly inside the drawn shell, so a point of layout rounding
    /// can never let a pixel peek past the real silhouette.
    private static let clipSafety: CGFloat = 0.97

    var body: some View {
        GeometryReader { geo in
            Group {
                if let scene {
                    SpriteView(scene: scene, options: [.allowsTransparency])
                } else {
                    Color.clear
                }
            }
            .mask {
                if clipActive, eggFrame != .zero {
                    let host = geo.frame(in: .global)
                    EggShape()
                        .frame(width: eggFrame.width * Self.clipSafety
                                   * clipGrow,
                               height: eggFrame.height * Self.clipSafety
                                   * clipGrow)
                        .position(x: eggFrame.midX - host.minX,
                                  y: eggFrame.midY - host.minY)
                } else {
                    Rectangle()
                }
            }
            .onAppear {
                if scene == nil {
                    scene = HatchAurieScene(aurie: aurie, size: geo.size,
                                            footprint: footprint)
                }
                scene?.setCreatureHidden(creatureHidden)
                if revealing {
                    // Re-mounted mid/after burst: never re-clip a live
                    // reveal.
                    clipActive = false
                    scene?.beginReveal()
                }
            }
            .onChange(of: creatureHidden) { _, now in
                scene?.setCreatureHidden(now)
            }
            .onChange(of: revealing) { _, now in
                guard now else { return }
                scene?.beginReveal()
                withAnimation(.easeIn(duration: clipRelease)) {
                    clipGrow = 2.4
                }
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + clipRelease) {
                    clipActive = false
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The reveal stage: an atmospheric family-lit space the creature emerges
/// into, rather than a character on an empty background.
///
/// Everything is built from systems the app already has — `AurieNode`, the
/// established celebration reaction, `FamilyEffects` particles and glow — so
/// the reveal inherits the family's visual language automatically instead of
/// needing bespoke art per family.
///
/// Layering, back to front: wide atmospheric wash -> tighter halo bloom ->
/// ground light pool -> creature -> ambient particles.
private final class HatchAurieScene: SKScene {
    private let aurie: Aurie
    private let footprint: CGFloat
    private var ambient: SKAction?
    private var swirl: ParticleField?
    private var lastUpdate: TimeInterval = 0

    init(aurie: Aurie, size: CGSize, footprint: CGFloat) {
        self.aurie = aurie
        self.footprint = footprint
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func glowLayer(_ colour: UIColor, z: CGFloat, scale: CGFloat,
                           at point: CGPoint) -> SKSpriteNode {
        let n = SKSpriteNode(texture: FamilyEffects.radialGlow)
        n.color = colour
        n.colorBlendFactor = 1
        n.blendMode = .add
        n.alpha = 0
        n.zPosition = z
        n.position = point
        n.setScale(scale)
        addChild(n)
        return n
    }

    /// Everything that is LIGHT rather than creature. Built in `didMove` but
    /// held at zero until `beginReveal()`, because before the shell opens the
    /// Aurie is an object sitting inside an egg, not a glowing apparition —
    /// and any glow would halo out around the intact shell and spoil it.
    private var atmosphere: [SKSpriteNode] = []
    private var creature: AurieNode?
    private var bodyCentre: CGPoint = .zero
    private var revealBegun = false
    /// Applied when the node is built, in case the switch arrives first.
    private var pendingHidden = true

    override func didMove(to view: SKView) {
        let aura = UIColor(aurie.auraColor)
        // Screen-relative now that the host is full screen: the creature
        // lands roughly where the egg stood, with the rest of the canvas
        // free for the glow to fall off into.
        let groundY = -size.height * 0.055
        let bodyCentre = CGPoint(x: 0, y: groundY + footprint * 0.30)

        // A. wide atmospheric wash — the "world" the creature emerges into.
        let wash = glowLayer(aura, z: -4, scale: footprint / 210, at: bodyCentre)

        // A2. tighter bloom directly behind the character: it should read as
        // emerging FROM light, so this peaks early and then settles back.
        let bloom = glowLayer(aura, z: -3, scale: footprint / 320, at: bodyCentre)

        // B. ground pool, so the creature has landed somewhere.
        let pool = glowLayer(aura, z: -2, scale: 1,
                             at: CGPoint(x: 0, y: groundY - footprint * 0.26))
        pool.xScale = footprint / 250
        pool.yScale = footprint / 760
        atmosphere = [wash, bloom, pool]

        // The preview creature wears its REAL equipment (Birth-Charm
        // timing rule: a winning newborn is dressed before it is ever
        // unhidden), resolved exactly as the Home scene resolves it.
        let worn = aurie.resolvedEquippedCharms
        let node = AurieNode(textures: AssetLoader.textures(for: aurie),
                             baseColor: UIColor(aurie.baseColor),
                             auraColor: aura,
                             body: aurie.body,
                             armStyle: aurie.resolvedArmStyle,
                             legStyle: aurie.resolvedLegStyle,
                             hairStyle: aurie.resolvedHairStyle,
                             patternLayer: aurie.patternMaskLayer,
                             charmLayers: worn.compactMap {
                                 AurieCharmCatalog.definition($0.charmID)
                                     != nil ? $0.charmID : nil
                             },
                             bellyStickerCharmID:
                                 AurieCharmCatalog.equippedCharmID(
                                     in: worn,
                                     placement: CharmSlot.belly.rawValue),
                             auraCharmID:
                                 AurieCharmCatalog.equippedCharmID(
                                     in: worn,
                                     placement: CharmSlot.aura.rawValue),
                             floatingCharmID:
                                 AurieCharmCatalog.equippedCharmID(
                                     in: worn,
                                     placement: CharmSlot.floating.rawValue))
        node.setScale(footprint / (AssetLoader.collisionHalfWidth * 2))
        node.position = CGPoint(x: 0, y: groundY)
        node.zPosition = 0
        addChild(node)
        node.adoptBaseExpression(aurie.resolvedBaseExpression)
        node.startIdle()

        // The creature is a PHYSICAL OBJECT present inside the egg, fully
        // opaque from the first frame it exists. The shell hides it; nothing
        // fades it in. `beginReveal()` only turns on the light.
        // (The egg-interior burst clip lives on the HOSTING SwiftUI view,
        // not here: SKCropNode segfaults in the Metal renderer over this
        // shader-tinted node tree — two crash reports, 2026-09-19.)
        node.isHidden = pendingHidden
        self.creature = node
        self.bodyCentre = bodyCentre
    }

    /// Called the instant the shell fragments begin to separate. The creature
    /// is already there and already visible through the opening cracks — this
    /// is purely the light show that follows it out.
    /// Kept out of `didMove` so the expensive scene build can happen early
    /// while the creature stays invisible.
    func setCreatureHidden(_ hidden: Bool) {
        creature?.isHidden = hidden
        pendingHidden = hidden
    }

    func beginReveal() {
        guard !revealBegun else { return }
        revealBegun = true

        if atmosphere.count == 3 {
            let wash = atmosphere[0], bloom = atmosphere[1], pool = atmosphere[2]
            wash.run(.sequence([
                .group([.fadeAlpha(to: 0.30, duration: 0.6),
                        .scale(to: footprint / 155, duration: 0.9)]),
                .fadeAlpha(to: 0.19, duration: 0.8),
            ]))
            bloom.run(.sequence([
                .group([.fadeAlpha(to: 0.62, duration: 0.35),
                        .scale(to: footprint / 230, duration: 0.5)]),
                .group([.fadeAlpha(to: 0.32, duration: 0.75),
                        .scale(to: footprint / 265, duration: 0.75)]),
            ]))
            pool.run(.sequence([.wait(forDuration: 0.12),
                                .fadeAlpha(to: 0.5, duration: 0.5),
                                .fadeAlpha(to: 0.4, duration: 0.6)]))
        }

        // Family particles: the creature is ORBITED by its family's magic —
        // the same swirl field Wonderglobe uses, choreographed to peak with
        // the celebration hop and settle into a gentle resting swirl.
        let swirlSpan = footprint * 1.9
        let field = ParticleField(
            family: aurie.family,
            area: CGRect(x: bodyCentre.x - swirlSpan / 2,
                         y: bodyCentre.y - swirlSpan / 2,
                         width: swirlSpan, height: swirlSpan),
            motion: .swirl)
        // Its particles place themselves at ±3 around this, so they pass both
        // behind and in front of the creature at z 0.
        field.zPosition = 0
        addChild(field)
        swirl = field

        // The shell leaving — low, around the creature's feet, so the magic
        // starts at the ground.
        field.burst(count: 15,
                    at: CGPoint(x: bodyCentre.x, y: bodyCentre.y - footprint * 0.42),
                    spread: footprint * 0.8)
        // Wake and build into the reveal. Slow enough that the ring is seen
        // climbing the body rather than arriving around the head.
        field.setEnergy(1.0, duration: 1.15)
        // …then let the energy drain away, leaving a quiet orbit behind. Not
        // all the way to the preset's rest energy: below roughly a third the
        // staggered pool starts dropping back to its rest points, and the
        // name card should still have a slow ring behind it.
        run(.sequence([.wait(forDuration: 1.1),
                       .run { [weak field] in
                           field?.setEnergy(0.44, duration: 1.2)
                       }]),
            withKey: "swirlSettle")

        // The established celebration reaction, once the shell has cleared.
        creature?.run(.sequence([.wait(forDuration: 0.38),
                                 .run { [weak self] in
                                     self?.creature?.play(.excitedHop)
                                 }]))
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate > 0 ? currentTime - lastUpdate : 0
        lastUpdate = currentTime
        swirl?.update(dt)
    }

}
