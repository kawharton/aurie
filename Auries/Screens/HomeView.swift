import SwiftUI

/// Home tab: a creature alive in its play space, its line in a speech bubble,
/// and the day's feel-good lift pinned at the bottom (mockup screen 1). Before
/// the first hatch a display-only greeter stands in, so Home is never empty.
#if DEBUG
/// Latches for the greeting capture aids: statics, so a re-appearing Home
/// cannot re-fire them (see the env-var trap note in the project memory).
enum HomeDebugHooks {
    static var replayFired = false
    static var hatchFired = false
    static var clearFired = false
}
#endif

struct HomeView: View {
    @Environment(AppModel.self) private var model
    /// The real device width class (RootTabView re-inherits it per tab), read
    /// so the reward sheet can size itself correctly on iPad.
    @Environment(\.horizontalSizeClass) private var widthClass
    /// Foreground/background, for telling a real arrival from a tab switch.
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    // Capture aid: open Settings straight away (AURIE_SHOW_SETTINGS=1).
    @State private var showSettings =
        ProcessInfo.processInfo.environment["AURIE_SHOW_SETTINGS"] == "1"
    #else
    @State private var showSettings = false
    #endif
    #if DEBUG
    // Capture aids: land straight in Calm Mode
    // (AURIE_WORRY_DEMO=1 / AURIE_BREATHE_DEMO=1).
    @State private var isCalm =
        ProcessInfo.processInfo.environment["AURIE_WORRY_DEMO"] == "1"
        || ProcessInfo.processInfo.environment["AURIE_BREATHE_DEMO"] == "1"
    #else
    @State private var isCalm = false
    #endif
    /// Bridge to the live play scene, for the Play Shelf.
    @State private var playHandle = SceneHandle()
    @State private var activeToy: PlayToy?
    @State private var radioOut = false
    // The Snow Globe happens ON Home — no navigation, no second creature.
    // PRODUCTION state (Release-safety audit 2026-09-18: these lived
    // inside the DEBUG block below and broke the first Release build).
    // `wonderStage` now only ever holds .off / .swirling: the `.reading`
    // stage belonged to the withdrawn Daily Wonder card.
    @State private var wonderStage: WonderStage = .off
    @State private var glassAmount: Double = 0
    /// True for the whole sequence, so extra shake notifications are ignored
    /// until Home is fully back to normal.
    @State private var wonderRunning = false
    @State private var shake = WonderShakeMonitor()
    // CONTEXTUAL GREETING (2026-09-27): chosen ONCE per meaningful arrival
    // by `arriveIfNeeded`; the scene shows the text and the pointed-at
    // control pulses. The rules live in HomeGreeting.swift.
    @State private var greeting: HomeGreeting?
    @State private var blinkTarget: DiscoverableFeature?
    @State private var backgroundedAt: Date?
    /// Home is the selected tab. Arrivals are only consumed while true, so
    /// a foreground on another tab leaves the greeting for the moment the
    /// player actually comes back to Home.
    @State private var isOnScreen = false
    // Charm-task rewards present from `model.pendingTaskRewards` via an
    // item-based sheet below — one at a time, and never while a Wonder
    // presentation is running.
    #if DEBUG
    @State private var showDemoMenu = false
    /// Capture aid: open the particle gallery straight away
    /// (AURIE_PARTICLE_GALLERY=1).
    @State private var showParticleGallery =
        ProcessInfo.processInfo.environment["AURIE_PARTICLE_GALLERY"] == "1"
    #endif

    /// The featured creature, or the welcome greeter until one is hatched.
    private var displayed: Aurie { model.store.featured ?? model.greeter }
    private var isGreeter: Bool { model.store.featured == nil }

    var body: some View {
        ZStack {
            if isCalm {
                CalmModeView(aurie: displayed, isGreeter: isGreeter) {
                    withAnimation(.easeInOut(duration: 1.0)) { isCalm = false }
                }
                .transition(.opacity)
            } else {
                normalHome
                    .transition(.opacity)
            }
        }
        // The tab bar fades away with the rest of the chrome in Calm Mode.
        .toolbar(isCalm ? .hidden : .visible, for: .tabBar)
        .sheet(isPresented: $showSettings) { SettingsView() }
        #if DEBUG
        .sheet(isPresented: $showDemoMenu) { DemoMenuView() }
        .fullScreenCover(isPresented: $showParticleGallery) { ParticleGalleryView() }
        #endif
        // (The Wonderbook sheet was REMOVED 2026-09-20 with Daily
        // Wonders. `WonderbookView` remains in the tree but is dormant —
        // nothing presents it.)
        // Task-earned charm celebrations — their OWN presentation, one
        // sheet at a time from the queue, never while the Wonder is
        // still running. Dismissing one advances to the next.
        .sheet(item: Binding<AppModel.CharmTaskResult?>(
            get: {
                // DO NOT REMOVE the hasSeenTutorial check — it is not
                // cosmetic. The first-run tutorial is a fullScreenCover on
                // RootTabView; a reward queued during AppModel.init would
                // start presenting in the SAME update, and SwiftUI then
                // drops BOTH (verified 2026-09-20: two grants on disk, yet
                // neither tutorial nor card ever appeared). A dropped reward
                // is lost permanently — acknowledgements are transient and
                // the ledger already holds the grant, so nothing re-offers
                // it. Reading the flag here is also what re-evaluates Home
                // the instant the tutorial is dismissed, so the queue drains
                // right after it — no timer, no arbitrary delay.
                guard model.store.settings.hasSeenTutorial,
                      !wonderRunning else { return nil }
                #if DEBUG
                // CAPTURE AID (AURIE_NO_SHEETS=1). A freshly seeded store
                // completes collection tasks immediately, so the reward card
                // covers the lower half of Home and hides the very thing an
                // environment capture is meant to show. Presentation itself is
                // unaffected — this only withholds the sheet from the capture.
                if ProcessInfo.processInfo.environment["AURIE_NO_SHEETS"] == "1" {
                    return nil
                }
                #endif
                return model.pendingTaskRewards.first
            },
            set: { newValue in
                if newValue == nil, !model.pendingTaskRewards.isEmpty {
                    model.pendingTaskRewards.removeFirst()
                }
            })) { reward in
            CharmRewardView(reward: reward,
                            centersVertically: widthClass != .compact)
                // iPad presents a sheet as a FORM SHEET, and detents resolve
                // against THAT short container — `.medium` there is roughly
                // half of ~620pt, which clipped the header and swallowed
                // "View Charms" entirely (iPad QA 2026-09-20). The half-height
                // detent is an iPhone treatment; regular width takes the full
                // form sheet, which the card already fits inside.
                .presentationDetents(widthClass == .compact
                                     ? [.medium] : [.large])
                .presentationDragIndicator(.visible)
        }
        // Home owns the shake. The monitor reports STATE, not an event, so
        // the swirl lasts exactly as long as the player keeps shaking.
        .onAppear {
            shake.onStart = { startGlobeShake() }
            shake.onStop = { playHandle.scene?.releaseWonderShake() }
            shake.start()
        }
        .onDisappear { shake.stop() }
        .onChange(of: shake.energy) { _, e in
            if wonderRunning { playHandle.scene?.sustainWonderShake(energy: e) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wonderShakeRequested)) { _ in
            // Accessibility alternative from Settings: same sequence, with a
            // simulated shake duration since there is no continuous input.
            shake.simulateShake(duration: 1.8)
        }
        #if DEBUG
        // Capture aid: a simulator has no usable accelerometer, so this drives
        // the REAL state machine with a deterministic duration.
        // AURIE_WONDER_SHAKE=<seconds>
        // AURIE_GLOBE_REPEATS=<n> runs the globe n times (default 1), each
        // after the previous one has fully handed Home back — the proof
        // that the Snow Globe is repeatable with no once-a-day gate.
        .task {
            guard let raw = ProcessInfo.processInfo.environment["AURIE_WONDER_SHAKE"],
                  let seconds = Double(raw), !WonderDebugHooks.fired else { return }
            WonderDebugHooks.fired = true
            let repeats = Int(ProcessInfo.processInfo
                .environment["AURIE_GLOBE_REPEATS"] ?? "") ?? 1
            try? await Task.sleep(for: .seconds(2.2))
            shake.simulateShake(duration: seconds)
            for _ in 1 ..< max(repeats, 1) {
                // Wait for the running globe to finish, then go again.
                while wonderRunning { try? await Task.sleep(for: .milliseconds(200)) }
                try? await Task.sleep(for: .seconds(1.0))
                shake.simulateShake(duration: seconds)
            }
        }
        // Capture aid: AURIE_TOY=<ball|bubble> opens a toy straight away, so
        // toy behaviour can be recorded without driving the play shelf by
        // hand. DEBUG only; changes nothing about how the shelf works.
        .task {
            guard let raw = ProcessInfo.processInfo.environment["AURIE_TOY"],
                  let toy = PlayToy(rawValue: raw),
                  !WonderDebugHooks.toyFired else { return }
            WonderDebugHooks.toyFired = true
            try? await Task.sleep(for: .seconds(2.5))
            // BOTH, exactly as the shelf button does: the @State drives the
            // shelf's own UI, `setActiveToy` is what actually spawns the toy
            // in the scene. Setting only the first looks right and spawns
            // nothing.
            activeToy = toy
            playHandle.scene?.setActiveToy(toy)
        }
        // Regression aid: AURIE_GLOBE_HANG=1 reproduces the removed Snow
        // Globe chip EXACTLY — it starts the globe with no shake, so no
        // shake-STOP ever arrives. This used to pulse Aurie forever. The
        // globe must now let go by itself, let the particles fall and fade,
        // and end on `isGlobeFinished` like any other globe: expect a
        // "restore ... delta=0.0000" line and no leftover field.
        .task {
            guard ProcessInfo.processInfo.environment["AURIE_GLOBE_HANG"] == "1",
                  !WonderDebugHooks.hangFired else { return }
            WonderDebugHooks.hangFired = true
            try? await Task.sleep(for: .seconds(2.2))
            playHandle.scene?.beginWonderSwirl()
        }
        #endif
        .onAppear {
            isOnScreen = true
            #if DEBUG
            if ProcessInfo.processInfo.environment["AURIE_GREET_LOG"] == "1" {
                NSLog("AURIE_HOME appear armed=%d", HomeGreetingSession.shared.armed ? 1 : 0)
            }
            // Capture aids for the two arrivals a cold launch cannot show:
            // AURIE_GREET_REPLAY_AFTER=<s> re-arms on a WARM Home (the
            // demo-menu "Replay" without a tap), so the late-greeting path
            // and the control pulse can be measured on rendered frames.
            // AURIE_GREET_HATCH_AFTER=<s> adds the hero while the greeter is
            // showing — the first-hatch transition, from Home's side.
            if let raw = ProcessInfo.processInfo.environment["AURIE_GREET_REPLAY_AFTER"],
               let secs = Double(raw), !HomeDebugHooks.replayFired {
                HomeDebugHooks.replayFired = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(secs))
                    HomeGreetingSession.shared.rearm()
                }
            }
            if let raw = ProcessInfo.processInfo.environment["AURIE_GREET_HATCH_AFTER"],
               let secs = Double(raw), !HomeDebugHooks.hatchFired {
                HomeDebugHooks.hatchFired = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(secs))
                    model.debugHatchHeroNow()
                }
            }
            // AURIE_GREET_CLEAR_AFTER=<s>: delete every Aurie while Home is
            // showing — the Aurie -> greeter transition, from Home's side.
            if let raw = ProcessInfo.processInfo.environment["AURIE_GREET_CLEAR_AFTER"],
               let secs = Double(raw), !HomeDebugHooks.clearFired {
                HomeDebugHooks.clearFired = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(secs))
                    model.store.debugClearCollection()
                }
            }
            #endif
            arriveIfNeeded()
        }
        .onDisappear {
            isOnScreen = false
            #if DEBUG
            if ProcessInfo.processInfo.environment["AURIE_GREET_LOG"] == "1" {
                NSLog("AURIE_HOME disappear")
            }
            #endif
        }
        // A real arrival is a launch, a return from a long enough background,
        // or the first hatch replacing the greeter — never a tab switch or a
        // child screen closing. Those re-run onAppear too, but the session
        // gate is already consumed, so arriveIfNeeded is a no-op for them.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                if let since = backgroundedAt,
                   Date().timeIntervalSince(since) >= GreetingPolicy.rearmAfterBackground {
                    HomeGreetingSession.shared.rearm()
                }
                backgroundedAt = nil
                arriveIfNeeded()
            default:
                break
            }
        }
        .onChange(of: isGreeter) { was, now in
            // The creature on Home changed kind — the first hatch swapped the
            // greeter for a real Aurie, or the last Aurie was deleted and the
            // greeter is back. Either way the play view is rebuilt, and a
            // line chosen for the previous creature must never be shown on
            // this one: drop it and greet afresh (the engine picks the
            // first-Aurie pool for the greeter, its own pools for an Aurie).
            guard was != now else { return }
            greeting = nil
            blinkTarget = nil
            HomeGreetingSession.shared.rearm()
            arriveIfNeeded()
        }
        // Calm covers Home; a greeting is only meaningful once it is back.
        .onChange(of: isCalm) { was, now in
            if was && !now { arriveIfNeeded() }
        }
        // DEBUG replay (demo menu) bumps the generation to greet again.
        .onChange(of: HomeGreetingSession.shared.generation) { _, _ in
            arriveIfNeeded()
        }
        // Widget deep link: land on plain Home — leave Calm, close sheets.
        .onReceive(NotificationCenter.default.publisher(for: .auriesReturnHome)) { _ in
            showSettings = false
            if isCalm {
                withAnimation(.easeInOut(duration: 0.6)) { isCalm = false }
            }
        }
    }

    // MARK: Composition

    /// Header · reserved bubble band · large lower-centre play area · secondary
    /// daily card · (system) tab bar. Proportional so iPhone and iPad portrait
    /// share the composition, centred rather than a narrow floating column.
    private var normalHome: some View {
        GeometryReader { geo in
            let margin = HomeTokens.horizontalMargin(width: geo.size.width)
            // Play space uses nearly the full width; chrome stays capped narrow.
            let playWidth = min(geo.size.width - margin * 2, HomeTokens.playAreaMaxWidth)
            ZStack {
                HomeBackgroundView(aura: displayed.auraColor)

                VStack(spacing: 0) {
                    topBar
                        .frame(maxWidth: HomeTokens.contentMaxWidth)   // readable chrome
                    // Reserve a little room so the creature sits lower-centre
                    // with space for the speech bubble.
                    Color.clear
                        .frame(height: geo.size.height * HomeTokens.bubbleReserveFraction)
                    // Play area: its own (wide) width; height is whatever remains
                    // between the header, Daily Lift, and tab bar.
                    CreaturePlayView(aurie: displayed, greeting: greeting?.text,
                                     greetingID: greeting?.id,
                                     onGreetingShown: {
                                         // Shown once: forget it, so a later
                                         // play-view rebuild (a creature swap)
                                         // cannot replay it.
                                         let shown = greeting
                                         greeting = nil
                                         pulseControl(for: shown)
                                     },
                                     handle: playHandle,
                                     suppressSpeech: wonderRunning,
                                     transparentBackground: true)
                        .id(displayed.id)   // fresh scene when the creature changes
                        // Brief glass shimmer, confined to the environment.
                        // No dim and no tint: the family art keeps its normal
                        // colour, contrast and clarity throughout.
                        .overlay {
                            WonderGlassView(aura: displayed.auraColor,
                                            amount: glassAmount)
                        }
                        // (Daily Wonders were withdrawn from launch: the
                        // card that used to read out Today's Wonder here is
                        // gone. The globe effect itself stays — it is now a
                        // playful Snow Globe interaction with no content.)
                        .overlay(alignment: .bottomTrailing) {
                            // The Play Shelf floats quietly in the play area's
                            // corner; the greeter has no toys.
                            if !isGreeter {
                                PlayShelfView(handle: playHandle,
                                              activeToy: $activeToy,
                                              radioOut: $radioOut,
                                              attention: blinkTarget == .toyBox)
                                    .padding(.trailing, 6)
                                    .padding(.bottom, 10)
                            }
                        }
                        .onChange(of: displayed.id) {
                            // A fresh scene starts toyless; keep the shelf honest.
                            activeToy = nil
                            radioOut = false
                        }
                        .frame(width: playWidth)
                        .frame(maxHeight: .infinity)
                    // (No chip here. The Snow Globe chip was REMOVED
                    // 2026-09-21: shaking is the trigger, with Settings ▸
                    // Accessibility as the no-shake alternative. The chip
                    // also called startGlobeShake() directly, which never
                    // produced a shake-STOP — see the failsafe in
                    // CreatureScene.)
                }
                .frame(maxWidth: .infinity)   // centre everything on iPad
                .padding(.horizontal, margin)
            }
        }
    }

    // MARK: - Today's Wonder, on Home

    /// The full magical shake effect. Its LENGTH is decided by how long the
    /// player shakes — `releaseWonderShake` starts the settle, not a timer.
    /// FULLY REPEATABLE (2026-09-20): there is no longer a once-a-day
    /// gate, because there is no daily content to reveal. `wonderRunning`
    /// is the only guard, so a second shake (or chip tap) while a globe is
    /// already swirling is ignored rather than stacking a second sequence.
    /// Nothing is granted, counted or persisted by shaking.
    private func startGlobeShake() {
        guard !wonderRunning, !isCalm, !isGreeter else { return }
        // Feature discovery: the first real shake retires the shake tutorial
        // greeting for good.
        if !model.store.settings.hasShakenPhone { model.store.settings.hasShakenPhone = true }
        wonderRunning = true
        wonderStage = .swirling
        playHandle.scene?.respondsToShake = false

        // A MOMENT of glass, not a persistent scrim: up fast, then gone by
        // ~0.8 s. From there the particles carry the snow-globe illusion.
        withAnimation(.easeOut(duration: 0.22)) { glassAmount = 1 }
        withAnimation(.easeInOut(duration: 0.55).delay(0.25)) { glassAmount = 0 }
        playHandle.scene?.beginWonderSwirl()
        Haptics.light()
        finishGlobeAfterSettle()
    }

    /// Chime once the player stops shaking, then let the snow fall and hand
    /// Home back. The globe's LENGTH is still decided by how long the player
    /// shakes — this is a settle, not a fixed timer.
    private func finishGlobeAfterSettle() {
        Task { @MainActor in
            while wonderRunning, shake.isActivelyShaking {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard wonderRunning else { return }
            // The payoff beat: Aurie has tumbled, the swirl is peaking.
            Haptics.success()
            SoundPlayer.play("sfx_wonder")
            // Long enough for the snowfall to reach the ground and fade.
            try? await Task.sleep(for: .seconds(8.5))
            guard wonderRunning else { return }
            endWonderSequence()
        }
    }

    /// Fold everything away and hand Home back exactly as it was.
    private func endWonderSequence() {
        withAnimation(.easeInOut(duration: 0.5)) {
            wonderStage = .off
            glassAmount = 0
        }
        playHandle.scene?.settleWonder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            playHandle.scene?.respondsToShake = true
            wonderRunning = false            // another shake is welcome now
            // (Any queued task reward now presents by itself — the
            // reward sheet's item binding watches wonderRunning.)
        }
    }

    private func enterCalm() {
        withAnimation(.easeInOut(duration: 1.2)) { isCalm = true }
        if !model.store.settings.hasSeenCalmIntro {
            // Mark seen a beat later so CalmModeView's first body evaluation
            // still sees "first time" and shows the one-line intro.
            Task {
                try? await Task.sleep(for: .seconds(1))
                model.store.settings.hasSeenCalmIntro = true
            }
        }
    }

    // MARK: Contextual greeting

    /// Everything the greeting engine reads, from persisted state. Calm
    /// reuses `hasSeenCalmIntro` — it already means "has opened Calm once".
    /// Charm discovery is the account collection's owned count, not a flag.
    private var greetingContext: GreetingContext {
        let st = model.store.settings
        let cal = Calendar.current
        let days = st.lastGreetingDate.map {
            cal.dateComponents([.day], from: cal.startOfDay(for: $0),
                               to: cal.startOfDay(for: Date())).day ?? 0
        }
        return GreetingContext(
            hasHatchedFirstAurie: st.hasHatchedFirstAurie,
            hasAurieNow: !isGreeter,
            hasOpenedToyBox: st.hasOpenedToyBox,
            hasOpenedCalm: st.hasSeenCalmIntro,
            hasOpenedCharmCollection: st.hasOpenedCharmCollection,
            hasShakenPhone: st.hasShakenPhone,
            ownedCharmCount: model.charms.collection.unlockedCharmIDs.count,
            daysSinceLastArrival: days,
            homeArrivalCount: st.homeArrivalCount,
            family: isGreeter ? nil : displayed.family,
            aurieLine: isGreeter ? nil : displayed.line,
            avoidTutorial: HomeGreetingSession.shared.lastTutorial)
    }

    /// Pulse the control a tutorial line points at, starting the moment the
    /// bubble is on screen (a cold launch renders Home seconds after the
    /// greeting was chosen). The blink belongs to that one greeting only,
    /// so when tutorial greetings stop, so does blinking.
    private func pulseControl(for greeting: HomeGreeting?) {
        guard let target = greeting?.blink else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["AURIE_GREET_LOG"] == "1" {
            NSLog("AURIE_GREET_SHOWN blink=%@", target.rawValue)
        }
        #endif
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            blinkTarget = target
            try? await Task.sleep(for: .seconds(3))
            if blinkTarget == target { blinkTarget = nil }
        }
    }

    /// ONE greeting per meaningful arrival. The session gate is what makes
    /// this a no-op for tab switches and returning child screens; only the
    /// handlers in `body` re-arm it.
    private func arriveIfNeeded() {
        let session = HomeGreetingSession.shared
        guard session.armed, isOnScreen, !isCalm, !wonderRunning else { return }
        session.consume()

        let context = greetingContext
        let chosen: HomeGreeting
        #if DEBUG
        // AURIE_GREET_SEED=<n> makes the roll deterministic for capture.
        if let raw = ProcessInfo.processInfo.environment["AURIE_GREET_SEED"],
           let seed = UInt64(raw) {
            // Spread so seeds 1, 2, 3… land far apart in the stream.
            var seeded = SeededGenerator(seed: seed &* 0x9E3779B97F4A7C15)
            chosen = HomeGreetingEngine.choose(context, using: &seeded)
        } else {
            var rng = SystemRandomNumberGenerator()
            chosen = HomeGreetingEngine.choose(context, using: &rng)
        }
        #else
        var rng = SystemRandomNumberGenerator()
        chosen = HomeGreetingEngine.choose(context, using: &rng)
        #endif
        greeting = chosen
        if case .tutorial(let feature) = chosen.kind { session.lastTutorial = feature }

        blinkTarget = nil   // the play view calls pulseControl when the bubble shows

        // Stamp the arrival AFTER choosing, so "days away" measured the gap
        // to the previous one. Only arrivals with a real Aurie feed the
        // early discovery window; greeter visits do not count.
        model.store.settings.lastGreetingDate = Date()
        if !isGreeter { model.store.settings.homeArrivalCount += 1 }

        #if DEBUG
        if ProcessInfo.processInfo.environment["AURIE_GREET_LOG"] == "1" {
            NSLog("AURIE_GREET kind=%@ blink=%@ arrivalsBefore=%d daysAway=%@ pool=%@ owned=%d text=\"%@\"",
                  "\(chosen.kind)", chosen.blink?.rawValue ?? "-",
                  context.homeArrivalCount,
                  context.daysSinceLastArrival.map(String.init) ?? "nil",
                  context.undiscovered.map(\.rawValue).joined(separator: ","),
                  context.ownedCharmCount, chosen.text)
        }
        #endif
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayed.name)
                    .font(.title2.weight(.bold))
                Text(displayed.family.rawValue.capitalized + " Family")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // Compact labeled Calm capsule (moon + word) — kept in the header,
            // secondary to the creature, immediately left of Settings.
            Button {
                enterCalm()
            } label: {
                Label("Calm", systemImage: "moon.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: HomeTokens.controlMinSize)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .attentionBlink(active: blinkTarget == .calm)
            .accessibilityLabel("Enter Calm Mode")
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: HomeTokens.controlMinSize, height: HomeTokens.controlMinSize)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            #if DEBUG
            // Demo tools (§20): long-press the gear. DEBUG builds only.
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.7).onEnded { _ in
                showDemoMenu = true
            })
            #endif
        }
        .padding(.top, 8)
    }

    // MARK: Speech bubble

    // MARK: Daily lift card (creature-independent — reads the day, not the creature)

    // The old large Daily Lift card, its detail sheet and its
    // dismiss-for-today control were REMOVED 2026-09-20 with Daily
    // Wonders. They had already been unreachable (nothing rendered
    // `dailyCard`), so this deleted dead UI, not a live feature.
}

/// Card/eyebrow labels for the daily-lift kinds. DORMANT with Daily
/// Wonders — no launch UI reads them (kept with the DailyLift content
/// model so a post-launch return needs no re-derivation).
extension DailyLiftItem.Kind {
    var label: String {
        switch self {
        case .quote: "Daily lift"
        case .joke:  "Daily laugh"
        case .dare:  "Daily dare"
        }
    }
}

/// DORMANT with Daily Wonders (2026-09-20): nothing presents this.
private struct DailyDetailView: View {
    let item: DailyLiftItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text(item.kind.label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
            Text(item.text)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
                .padding(.top, 4)
        }
        .padding(32)
        .presentationDetents([.medium])
    }
}


#if DEBUG
/// Process-level latch for the Wonder capture hook. NOT `@State` — SwiftUI
/// rebuilds views freely and a `@State` latch re-fires (see the hatch demo
/// hook, which caused eggs to hatch on their own).
@MainActor enum WonderDebugHooks {
    static var fired = false
    /// Latched on a static, not @State: Home re-renders many times and an
    /// aid that re-fires per render looks like the app driving itself.
    static var hangFired = false
    static var toyFired = false
}
#endif
