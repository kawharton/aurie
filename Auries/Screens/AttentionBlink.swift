import SwiftUI

/// A few soft pulses on a control the Aurie has just pointed at ("tap the
/// Calm button", "open the Toy Box"), so the player can see which thing
/// the line means. Presentation only: it never blocks or moves anything,
/// and it runs exactly once per activation, so once the tutorial
/// greetings stop, the blinking stops with them.
///
/// Driven step by step rather than with a repeating animation, so the
/// control is guaranteed to end fully opaque — a `repeatCount` on a Bool
/// would leave the model value at the dimmed state when it finished.
/// Reduce Motion skips the pulses entirely.
struct AttentionBlink: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false
    @State private var run: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.35 : 1)
            .scaleEffect(dim ? 0.94 : 1)
            .onChange(of: active) { _, on in
                guard on, !reduceMotion else { return }
                run?.cancel()
                run = Task { @MainActor in
                    for _ in 0 ..< GreetingPolicy.blinkPulses {
                        withAnimation(.easeInOut(duration: 0.34)) { dim = true }
                        try? await Task.sleep(for: .seconds(0.34))
                        guard !Task.isCancelled else { break }
                        withAnimation(.easeInOut(duration: 0.34)) { dim = false }
                        try? await Task.sleep(for: .seconds(0.34))
                        guard !Task.isCancelled else { break }
                    }
                    withAnimation(.easeOut(duration: 0.2)) { dim = false }
                }
            }
            .onDisappear { run?.cancel(); dim = false }
    }
}

extension View {
    func attentionBlink(active: Bool) -> some View {
        modifier(AttentionBlink(active: active))
    }
}
