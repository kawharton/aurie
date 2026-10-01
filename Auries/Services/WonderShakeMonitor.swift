import CoreMotion
import Foundation

/// Continuous shake STATE, not a one-shot event.
///
/// `UIWindow.motionEnded` (which drives `.deviceDidShake`) only reports that a
/// shake finished — it cannot say "still shaking", so it can never drive an
/// effect whose length depends on how long the player shakes. This watches the
/// accelerometer directly and maintains an active/idle state with hysteresis.
///
/// Deliberately forgiving: a hand pausing for an instant between shake strokes
/// must not end the effect.
@Observable
@MainActor
final class WonderShakeMonitor {

    /// True from the first strong jolt until motion has been quiet for
    /// `graceWindow`.
    private(set) var isActivelyShaking = false
    /// 0…1, how hard the player is shaking. Feeds flow speed and tumble
    /// energy. Clamped — a normal intentional shake reaches most of the range.
    private(set) var energy: CGFloat = 0

    /// Fired when shaking starts, and again when it has genuinely stopped.
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    // Tuned for a normal intentional shake, in g above rest.
    private let startThreshold: Double = 1.15
    private let sustainThreshold: Double = 0.55
    /// Motion must stay below `sustainThreshold` for this long before the
    /// shake is declared over. Without it, the natural pause between strokes
    /// would end the effect.
    private let graceWindow: TimeInterval = 0.4

    private let motion = CMMotionManager()
    private var lastStrong = Date.distantPast
    private var decayTimer: Timer?

    var isAvailable: Bool { motion.isAccelerometerAvailable }

    func start() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive
        else { return }
        motion.accelerometerUpdateInterval = 1.0 / 50
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            // Magnitude minus 1g of rest gravity: what's left is real motion,
            // whatever orientation the phone is held in.
            let jolt = abs(sqrt(a.x * a.x + a.y * a.y + a.z * a.z) - 1.0)
            self.ingest(jolt: jolt)
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
        decayTimer?.invalidate()
        decayTimer = nil
        isActivelyShaking = false
        energy = 0
    }

    private func ingest(jolt: Double) {
        let now = Date()
        if isActivelyShaking {
            // A LOWER bar keeps it alive than the one that started it.
            if jolt > sustainThreshold { lastStrong = now }
            energy = min(1, max(energy * 0.94, CGFloat(jolt / 2.2)))
            if now.timeIntervalSince(lastStrong) > graceWindow { finish() }
        } else if jolt > startThreshold {
            isActivelyShaking = true
            lastStrong = now
            energy = min(1, CGFloat(jolt / 2.2))
            onStart?()
        }
    }

    private func finish() {
        isActivelyShaking = false
        energy = 0
        onStop?()
    }

    /// Drive the real state machine with a fixed duration instead of the
    /// accelerometer. PRODUCTION, not a debug harness (Release-safety
    /// audit 2026-09-18: this was #if DEBUG, silently breaking the
    /// shipping path that uses it): Settings' Accessibility "Shake
    /// without moving your phone" runs the whole Wonder sequence through
    /// it. The DEBUG capture hooks reuse it for the same reason a
    /// simulator does — no usable accelerometer.
    func simulateShake(duration: TimeInterval) {
        guard !isActivelyShaking else { return }
        isActivelyShaking = true
        energy = 0.8
        onStart?()
        decayTimer?.invalidate()
        decayTimer = Timer.scheduledTimer(withTimeInterval: duration,
                                          repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }
}
