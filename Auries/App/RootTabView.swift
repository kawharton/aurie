import SwiftUI

/// Posted when the widget deep link asks for Home: any screen with its own
/// presentation (sheets, covers, Calm) folds itself away so the user lands on
/// the plain Home tab.
extension Notification.Name {
    static let auriesReturnHome = Notification.Name("auriesReturnHome")
    /// Posted by in-app flows (e.g. the task-reward sheet's "View
    /// Charms") to land on the Charms tab — same pattern as the widget
    /// deep link, so navigation stays in RootTabView's hands.
    static let auriesOpenCharms = Notification.Name("auriesOpenCharms")
}

/// Root navigation: the three tabs from the brief (§7), styled per
/// auries_mockup.png — dark theme throughout, third tab labeled "Auries".
/// The full-screen creature view and the paywall appear over these as
/// sheets in later steps.
struct RootTabView: View {
    @Environment(AppModel.self) private var model
    /// The device's real horizontal class, read before the override below.
    @Environment(\.horizontalSizeClass) private var realSizeClass
    @State private var showFirstRunTutorial = false
    #if DEBUG
    // Capture aids: land on the Hatch tab (AURIE_HATCH_DEMO=1), or on any tab
    // by index (AURIE_START_TAB=2 for the collection).
    @State private var selectedTab =
        Int(ProcessInfo.processInfo.environment["AURIE_START_TAB"] ?? "")
        ?? (ProcessInfo.processInfo.environment["AURIE_HATCH_DEMO"] != nil ? 1 : 0)
    #else
    @State private var selectedTab = 0
    #endif

    /// Capture aid: AURIE_TAB_SCRIPT="3@6,0@9" selects Charms 6 s after
    /// launch and Home at 9 s — the same binding change a tab-bar tap makes,
    /// so the greeting's tab-switch protection can be exercised headless
    /// (simctl cannot tap, and `openurl` prompts). Runs once per process.
    private func runTabScriptIfNeeded() async {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["AURIE_TAB_SCRIPT"],
              !Self.tabScriptRan else { return }
        Self.tabScriptRan = true
        let start = Date()
        for step in raw.split(separator: ",") {
            let parts = step.split(separator: "@")
            guard parts.count == 2, let tab = Int(parts[0]), let at = Double(parts[1]) else { continue }
            let wait = at - Date().timeIntervalSince(start)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            selectedTab = tab
            NSLog("AURIE_TAB_SCRIPT tab=%d at=%.1fs", tab, at)
        }
        #endif
    }
    #if DEBUG
    private static var tabScriptRan = false
    #endif

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tag(0)
                .environment(\.horizontalSizeClass, realSizeClass)
                .tabItem { Label("Home", systemImage: "house.fill") }
            HatchView()
                .tag(1)
                .environment(\.horizontalSizeClass, realSizeClass)
                .tabItem { Label("Hatch", systemImage: "camera.fill") }
            CollectionView()
                .tag(2)
                .environment(\.horizontalSizeClass, realSizeClass)
                .tabItem { Label("Auries", systemImage: "square.grid.2x2.fill") }
            CharmsView()
                .tag(3)
                .environment(\.horizontalSizeClass, realSizeClass)
                .tabItem { Label("Charms", systemImage: "sparkles") }
        }
        // Widget tap (Phase 8B): auries://home selects Home and asks any
        // presented screen to fold away. Nothing is recreated — the same
        // model, store, and scene instances stay alive.
        .onOpenURL { url in
            guard url.scheme == "auries" else { return }
            selectedTab = 0
            NotificationCenter.default.post(name: .auriesReturnHome, object: nil)
        }
        .onReceive(NotificationCenter.default
            .publisher(for: .auriesOpenCharms)) { _ in
            selectedTab = 3
        }
        .task { await runTabScriptIfNeeded() }
        // Keep a bottom tab bar on iPad portrait: iPadOS 26 defaults the
        // regular-width TabView to a *top* bar, so the TabView reads compact
        // for its own placement — but each tab's CONTENT re-inherits the real
        // size class above, so nothing downstream is falsified to phone width.
        // Sheets already present with the real device traits regardless.
        .environment(\.horizontalSizeClass, .compact)
        // The whole app is dark and magical in the mockup; force dark so
        // every screen sits on the deep backdrop regardless of system setting.
        .preferredColorScheme(.dark)
        // First-run tutorial (§6): once, then replayable from Settings.
        .onAppear {
            if !model.store.settings.hasSeenTutorial {
                showFirstRunTutorial = true
            }
        }
        .fullScreenCover(isPresented: $showFirstRunTutorial, onDismiss: {
            model.store.settings.hasSeenTutorial = true
        }) {
            TutorialView()
            #if DEBUG
            // Capture aid: AURIE_TUTORIAL_AUTOSKIP=<seconds> closes the
            // tutorial through the same path the Skip button uses, so the
            // tutorial-then-reward ORDERING that HomeView's reward gate
            // depends on can be captured without taps.
                .onAppear {
                    if let raw = ProcessInfo.processInfo
                        .environment["AURIE_TUTORIAL_AUTOSKIP"],
                       let secs = Double(raw) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
                            showFirstRunTutorial = false
                        }
                    }
                }
            #endif
        }
    }
}
