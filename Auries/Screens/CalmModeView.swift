import SwiftUI

/// Calm Mode — a quieter version of Home, not a separate place (Calm Mode
/// spec). Enter → already in **Just Be**: the creature settles, the family
/// world softens, ambient music fades in, sparkles trail the finger. Two
/// optional activities: **Breathe Together** and the **Worry Jar**.
///
/// Design boundaries (do not change): this is a comforting fictional
/// companion, NOT therapy, an advice engine, an emergency service, or an AI
/// analyzing private thoughts. Never analyze or store worry text. No coins,
/// badges, streaks, or rewards for entering worries or for calm use. No
/// forced timers; Done is always available. Never claim a worry is "gone" or
/// "fixed".
struct CalmModeView: View {
    let aurie: Aurie
    let isGreeter: Bool
    var onDone: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Activity { case justBe, breathe, worryJar }
    @State private var activity: Activity = .justBe
    @State private var handle = SceneHandle()
    @State private var hintVisible = true
    @State private var musicOn = true
    @State private var trackFlash: String?
    @State private var trackFlashTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // The nighttime world: midnight gradient with delicate stars. The
            // scene renders transparent over it, so Aurie and the jar live IN
            // the night rather than on a flat colour.
            CalmNightSkyView(reduceMotion: reduceMotion)
                .ignoresSafeArea()
                // Charm-task seam (Quiet Visits): ENTERING Calm is the
                // whole event — counted by distinct day, and by design
                // it never reads or depends on Worry content or any
                // other private activity inside Calm.
                .onAppear { model.recordCharmTaskEvent(.calmVisited) }

            // Aurie's aura is the SCENE's backlight (CreatureScene's calm
            // glow): attached to the creature itself so it hugs any body
            // type and moves with it — nothing here to misalign.

            // The scene centres the creature at 0.50h; lift it so the
            // hierarchy reads header -> generous sky -> Aurie + jar as the
            // central scene -> copy -> controls.
            GeometryReader { geo in
                CreaturePlayView(aurie: aurie, greeting: entryLine, mode: .calm,
                                 handle: handle, bubbleTopInset: 130,
                                 transparentBackground: true)
                    // Night grade: pull the creature's colours slightly cool
                    // and dim so it shares the moonlight instead of glowing
                    // daylight-red over it.
                    .colorMultiply(Color(red: 0.90, green: 0.895, blue: 1.0))
                    .offset(y: geo.size.height * 0.127)
            }
            .ignoresSafeArea()

            // Soft vignette so the edges feel closer and quieter. Restrained
            // over the painted night — the artwork carries its own darkness.
            RadialGradient(colors: [.clear, .black.opacity(activity == .worryJar ? 0.22 : 0.32)],
                           center: .center, startRadius: 180, endRadius: 520)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            topBar

            switch activity {
            case .justBe:
                justBeControls
            case .breathe:
                BreathingOverlay(name: aurie.name, reduceMotion: reduceMotion) {
                    handle.scene?.endBreatheTogether()
                    activity = .justBe
                }
                .transition(.opacity)
            case .worryJar:
                WorryJarOverlay(aurie: aurie, handle: handle) {
                    activity = .justBe
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: activity)
        .onAppear {
            #if DEBUG
            // Capture aid: open Calm directly on the Worry Jar.
            // AURIE_WORRY_DEMO=1
            if ProcessInfo.processInfo.environment["AURIE_WORRY_DEMO"] == "1" {
                activity = .worryJar
            }
            // Capture aid: open Calm directly on Breathing.
            // AURIE_BREATHE_DEMO=1
            if ProcessInfo.processInfo.environment["AURIE_BREATHE_DEMO"] == "1" {
                activity = .breathe
                // The overlay alone does NOT start the scene-side breathing —
                // that lives in the "Breathe Together" button's action — so
                // the aid has to start it too, once the scene exists.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if !reduceMotion { handle.scene?.beginBreatheTogether() }
                }
            }
            #endif
            musicOn = model.store.settings.calmMusicOn
            SoundPlayer.startAmbient(track: model.store.settings.calmTrack)
            Task {
                try? await Task.sleep(for: .seconds(7))
                withAnimation(.easeOut(duration: 1.5)) { hintVisible = false }
            }
        }
        .onDisappear { SoundPlayer.stopAmbient() }
        // Done is the ONLY exit: a swipe-down exit collided with downward
        // sparkle-drags and kept kicking people out mid-calm.
    }

    /// First visit gets the one-line intro; later visits occasionally a quiet
    /// family line (sparingly — at most one per visit, none most visits).
    private var entryLine: String? {
        #if DEBUG
        // Capture aid: the demo judges the night scene, not the greeting.
        if ProcessInfo.processInfo.environment["AURIE_WORRY_DEMO"] == "1" {
            return nil
        }
        #endif
        if !model.store.settings.hasSeenCalmIntro {
            // Marked seen by HomeView when presenting.
            return "Take a quiet moment with \(aurie.name)."
        }
        return Int.random(in: 0..<3) == 0
            ? ContentService.calm.calmLine(for: aurie.family)
            : nil
    }

    // MARK: Chrome

    private var topBar: some View {
        VStack {
            HStack(alignment: .center) {
                Text(aurie.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    cycleTrack()
                } label: {
                    Image(systemName: "music.note")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(9)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Switch calm music")
                Button {
                    musicOn.toggle()
                    model.store.settings.calmMusicOn = musicOn
                    if musicOn {
                        SoundPlayer.startAmbient(track: model.store.settings.calmTrack)
                    } else {
                        SoundPlayer.stopAmbient()
                    }
                } label: {
                    Image(systemName: musicOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(9)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(musicOn ? "Turn calm music off" : "Turn calm music on")
                Button("Done") { onDone() }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel("Leave Calm Mode")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            if let trackFlash {
                Text(trackFlash)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 6)
                    .transition(.opacity)
            }
            Spacer()
        }
        .animation(.easeInOut(duration: 0.4), value: trackFlash)
    }

    /// Cycle Pad -> Waves -> Chimes, switch playback, flash the name briefly.
    private func cycleTrack() {
        let tracks = SoundPlayer.ambientTracks
        let currentIndex = tracks.firstIndex { $0.id == model.store.settings.calmTrack } ?? 0
        let next = tracks[(currentIndex + 1) % tracks.count]
        model.store.settings.calmTrack = next.id
        if musicOn { SoundPlayer.startAmbient(track: next.id) }
        trackFlashTask?.cancel()
        trackFlash = next.label
        trackFlashTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { trackFlash = nil }
        }
    }

    private var justBeControls: some View {
        VStack {
            Spacer()
            if hintVisible {
                Text("✦ drag the sparkles gently ✦")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
            HStack(spacing: 12) {
                calmActionButton("Breathe Together", icon: "circle.dotted") {
                    activity = .breathe
                    // Reduce Motion: the ring brightens/dims instead of the
                    // creature physically expanding.
                    if !reduceMotion { handle.scene?.beginBreatheTogether() }
                }
                if !isGreeter {
                    calmActionButton(
                        model.store.worry(for: aurie) != nil ? "Worry Jar ✦" : "Worry Jar",
                        icon: "lightbulb.min"
                    ) {
                        activity = .worryJar
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
    }

    private func calmActionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Breathe Together

/// A soft ring behind the creature grows and shrinks (~4s each way) while the
/// creature rises and settles in sync. Gentle wording, no counts, fades away
/// after two cycles. Auto-returns to Just Be after about a minute; Done stays
/// available the whole time (the top bar remains visible above this overlay).
private struct BreathingOverlay: View {
    let name: String
    let reduceMotion: Bool
    var onEnd: () -> Void

    @State private var inhaling = false
    @State private var cyclesShown = 0
    @State private var started = false

    private let halfCycle: Double = 4

    var body: some View {
        ZStack {
            // Centred on the creature, which stands low in the clearing.
            GeometryReader { geo in
                Circle()
                    .stroke(.white.opacity(reduceMotion ? (inhaling ? 0.5 : 0.15) : 0.28), lineWidth: 2)
                    .frame(width: 340, height: 340)
                    .scaleEffect(reduceMotion ? 1 : (inhaling ? 1.12 : 0.78))
                    .position(x: geo.size.width * 0.5,
                              y: geo.size.height * 0.60)
            }
            .allowsHitTesting(false)

            VStack {
                Spacer()
                if cyclesShown < 2 {
                    Text(inhaling ? "Breathe in with \(name)" : "And slowly out")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                        .transition(.opacity)
                        .id(inhaling)   // crossfade between the two lines
                        .padding(.bottom, 20)
                }
                Button("Back") { onEnd() }
                #if DEBUG
                    // Capture aid: AURIE_BREATHE_AUTOSTOP=<seconds> stops
                    // breathing MID-CYCLE through the same onEnd the Back
                    // button uses, so the position-restore fix can be
                    // verified without a tap.
                    .task {
                        guard let raw = ProcessInfo.processInfo
                            .environment["AURIE_BREATHE_AUTOSTOP"],
                              let secs = Double(raw) else { return }
                        try? await Task.sleep(for: .seconds(secs))
                        onEnd()
                    }
                #endif
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .buttonStyle(.plain)
                    .padding(.bottom, 30)
            }
        }
        .animation(.easeInOut(duration: halfCycle), value: inhaling)
        .animation(.easeInOut(duration: 0.8), value: cyclesShown)
        .task {
            guard !started else { return }
            started = true
            inhaling = true
            // ~1 minute of cycles, then gently return. Done/Back always work.
            for cycle in 0..<8 {
                try? await Task.sleep(for: .seconds(halfCycle))
                if Task.isCancelled { return }
                inhaling = false
                try? await Task.sleep(for: .seconds(halfCycle))
                if Task.isCancelled { return }
                inhaling = true
                cyclesShown = cycle + 1
            }
            onEnd()
        }
    }
}

// MARK: - Worry Jar

/// The Worry Jar ritual. Privacy boundary (do not change): the typed text
/// exists only in this view's local state and is discarded the moment it's
/// given to the Aurie — never persisted, logged, or sent anywhere. Only an
/// anonymous date-stamped token (Store.WorryToken) records that this Aurie is
/// holding one light.
private struct WorryJarOverlay: View {
    let aurie: Aurie
    let handle: SceneHandle
    var onClose: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase { case entry, justGiven, holding, releasing }
    @State private var phase: Phase = .entry
    @State private var worryText = ""
    @State private var jarFill: Double = 0
    @State private var lidOpen: Double = 0
    @State private var releaseStart: Date?
    @State private var aurieLine: String?
    #if DEBUG
    // Capture aid: open the support panel straight away
    // (AURIE_SHOW_SUPPORT=1, alongside AURIE_WORRY_DEMO=1) for sheet-fit
    // review. The panel is otherwise only reached by tapping "Need support?".
    @State private var showSupport =
        ProcessInfo.processInfo.environment["AURIE_SHOW_SUPPORT"] == "1"
    #else
    @State private var showSupport = false
    #endif
    @FocusState private var textFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
            // While the keyboard is up, tapping anywhere else dismisses it —
            // otherwise the Give button can sit unreachable behind the keys.
            // The catcher exists ONLY while typing, so scene touches flow
            // normally the rest of the time.
            if textFocused {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { textFocused = false }
            }
            // ONE cohesive column. The previous layout opened with a Spacer,
            // which pushed the prompt, jar and actions apart down the screen
            // and made the whole thing read as a form under a creature.
            VStack(spacing: 0) {
                // Room for Aurie, who stands lower now (offset into the
                // clearing). The jar's mouth must sit just under the chin so
                // the glass overlaps the body, reference-style, and the jar's
                // base lands on the clearing floor.
                // LAYOUT INVARIANT: the region above this spacer belongs
                // to Aurie, the jar and the release animation. No text or
                // control may ever render inside it, in ANY phase — copy,
                // buttons and Back always stack strictly below.
                Color.clear.frame(height: geo.size.height
                                  * (phase == .entry ? 0.795 : 0.662))

                // Entry keeps its prompt above the field; every other state
                // moves the line BELOW the jar so nothing sits over Sable.
                if phase == .entry, let aurieLine {
                    Text(aurieLine)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .shadow(color: .black.opacity(0.55), radius: 6, y: 1)
                        .padding(.horizontal, 34)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }

                // The jar sits directly under Aurie so they read as one
                // interaction. During entry the field owns the space — a
                // keyboard would cover a jar anyway.
                if phase != .entry {
                    WorryJarView(fill: jarFill, lidOpen: lidOpen,
                                 releaseStart: releaseStart,
                                 reduceMotion: reduceMotion)
                        .frame(width: min(geo.size.width * 0.30, 150))
                        // Grounding: a soft dark contact shadow under the
                        // glass, and a restrained warm spill from the swarm
                        // — light interacting with the ground, not a floor
                        // glow.
                        .background(alignment: .bottom) {
                            ZStack {
                                Ellipse()
                                    .fill(.black.opacity(0.38))
                                    .frame(width: min(geo.size.width * 0.30, 150) * 1.18,
                                           height: geo.size.height * 0.016)
                                    .blur(radius: 7)
                                    .offset(y: geo.size.height * 0.008)
                                Ellipse()
                                    .fill(Color(red: 1.0, green: 0.72, blue: 0.32)
                                            .opacity(0.13 * jarFill))
                                    .frame(width: geo.size.width * 0.30,
                                           height: geo.size.height * 0.028)
                                    .blur(radius: 10)
                                    .offset(y: geo.size.height * 0.010)
                            }
                        }
                        .padding(.bottom, 4)
                }

                if phase != .entry, let aurieLine {
                    Text(aurieLine)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .shadow(color: .black.opacity(0.55), radius: 6, y: 1)
                        .padding(.horizontal, 34)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }

                switch phase {
                case .entry:
                    entryControls
                case .justGiven:
                    choiceControls(keepTitle: "Keep it here for now",
                                   releaseTitle: "Release it now")
                case .holding:
                    Text("Ready to release what \(aurie.name) is holding?")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                        .padding(.bottom, 8)
                    choiceControls(keepTitle: "Keep holding it",
                                   releaseTitle: "Release it")
                case .releasing:
                    EmptyView()
                }

                if phase != .entry {
                    Button {
                        onClose()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(.white.opacity(0.16),
                                                       lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .opacity(phase == .releasing ? 0 : 1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: phase)
        .sheet(isPresented: $showSupport) { SupportView() }
        .onAppear {
            if model.store.worry(for: aurie) != nil {
                phase = .holding
                jarFill = 1
            }
            #if DEBUG
            // Capture aid: walk the states without typing or tapping.
            // AURIE_WORRY_DEMO=1
            // (The support sheet has NO auto-open path — debug or otherwise:
            // it appears only when the user taps "Need support?".)
            if ProcessInfo.processInfo.environment["AURIE_WORRY_DEMO"] == "1" {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.0))
                    worryText = "demo"
                    giveWorry()
                    try? await Task.sleep(for: .seconds(4.5))
                    release()
                }
            }
            #endif
        }
    }

    // MARK: Pieces

    private var entryControls: some View {
        VStack(spacing: 8) {
            TextField("", text: $worryText,
                      prompt: Text("What is worrying you?")
                          .foregroundStyle(.white.opacity(0.60)),
                      axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                // A vertical-axis field turns the return key into a newline
                // and never submits — intercept it so return CLOSES the
                // keyboard (the text wraps on its own; no literal newlines).
                .onChange(of: worryText) { _, newValue in
                    if newValue.contains("\n") {
                        worryText = newValue
                            .replacingOccurrences(of: "\n", with: " ")
                        textFocused = false
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { textFocused = false }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
                .padding(.horizontal, 44)
                .focused($textFocused)
                .accessibilityLabel("Write what feels heavy. Your words disappear after you give them.")

            // The privacy promise, shown BEFORE anything sensitive is typed.
            Text("Your words disappear after you give them to \(aurie.name). Only a little light remains in the jar.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.78))
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)

            Button {
                giveWorry()
            } label: {
                Text("Give it to \(aurie.name)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(worryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            HStack(spacing: 26) {
                Button("Need support?") { showSupport = true }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                    .buttonStyle(.plain)
                Button {
                    onClose()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(.white.opacity(0.16),
                                                   lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
    }

    private func choiceControls(keepTitle: String, releaseTitle: String) -> some View {
        HStack(spacing: 12) {
            Button(keepTitle) {
                onClose()   // jar stays held; back to Just Be
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .buttonStyle(.plain)

            Button(releaseTitle) {
                release()
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .buttonStyle(.plain)
        }
    }

    // MARK: Actions

    private func giveWorry() {
        textFocused = false
        // PRIVACY BOUNDARY: discard the words immediately and forever. Only
        // the anonymous token below is stored. Never change this to save,
        // log, transmit, or analyze the text.
        worryText = ""
        model.store.holdWorry(for: aurie)
        // The light arrives in the jar a beat after the field collapses, so
        // the worry reads as moving INTO the glass.
        withAnimation(.easeInOut(duration: 0.9).delay(0.25)) { jarFill = 1 }
        aurieLine = ContentService.calm.holdLine
        phase = .justGiven
    }

    private func release() {
        phase = .releasing
        aurieLine = nil
        model.store.releaseWorry(for: aurie)
        // A quiet family shimmer joins as the light starts birthing
        // fireflies — secondary to the gold, tying the moment to the family.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            handle.scene?.playWorryRelease()
        }
        // Identity-preserving choreography (FlyKinematics): anticipation ->
        // cork wobbles then opens gently -> the SAME residents leave one by
        // one -> the last one lingers, then the jar is empty.
        releaseStart = Date()
        withAnimation(.easeInOut(duration: 0.16).delay(0.12)) { lidOpen = 0.06 }
        withAnimation(.easeInOut(duration: 0.16).delay(0.30)) { lidOpen = 0 }
        withAnimation(.easeInOut(duration: 0.70).delay(0.50)) { lidOpen = 1 }
        // The glass's warm pools drain in step with the light giving
        // itself to the fireflies (births run ~1.25-2.6s after the tap).
        withAnimation(.linear(duration: 1.5).delay(1.15)) { jarFill = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(7.6))
            withAnimation(.easeInOut(duration: 0.7)) { lidOpen = 0 }
        }
        Task {
            try? await Task.sleep(for: .seconds(6.9))
            aurieLine = ContentService.calm.releaseLine
            try? await Task.sleep(for: .seconds(3.1))
            onClose()
        }
    }
}

// MARK: - Human-support doorway

/// A quiet, non-emergency pointer toward real people. Deliberately gentle:
/// Aurie is a comforting fictional companion, not a counselor or a crisis
/// service, and this screen never implies the user's worry is an emergency.
private struct SupportView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.circle")
                .font(.system(size: 40))
                .foregroundStyle(.pink)
                .padding(.top, 18)
            Text("People can hold things, too")
                .font(.title3.weight(.semibold))
            Text("Auries can sit with you, but some things feel lighter when you share them with someone you trust, such as a family member, friend, partner, teacher, counselor, caregiver, or someone else who feels safe to talk to.\n\nIf something has been feeling heavy, you don\u{2019}t have to carry it alone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            // Quiet, warm doorway — a small secondary TEXT link, never a
            // button. Close below remains the panel's only real button.
            VStack(spacing: 2) {
                Link("Call or text 988",
                     destination: URL(string: "tel:988")!)
                    .font(.footnote.weight(.medium))
                    .tint(.gray)
                Text("U.S. emotional and crisis support · available 24/7")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .presentationDetents([.medium])
    }
}
