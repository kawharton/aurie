import AVFoundation
import UIKit

/// Tiny sound-effect player (§10): real wiring, placeholder files. Missing
/// files no-op silently, so sound slots can fill in later without code
/// changes. Mute comes from the Sound setting via `isEnabled` (wired once at
/// app start).
///
/// Placeholder files live in Resources/Sounds as short generated blips:
///   sfx_tap, sfx_crack, sfx_hatch, sfx_pet, sfx_pickup, sfx_drop,
///   sfx_tickle, sfx_appear
/// TODO(art): replace with real royalty-free/licensed audio, same names.
enum SoundPlayer {

    /// Supplied by AuriesApp at launch; reads the persisted Sound setting.
    static var isEnabled: () -> Bool = { true }

    /// Calm Mode's own music toggle (also gated by `isEnabled`).
    static var isCalmMusicEnabled: () -> Bool = { true }

    // MARK: - Audio session

    /// Configured ONCE, lazily, immediately before the first sound plays.
    ///
    /// `.ambient` is the right category for short app SFX: it OBEYS the
    /// ring/silent switch, and it MIXES, so Aurie never interrupts the
    /// music or podcast someone already has playing. The two alternatives
    /// are both wrong here — `.playback` ignores the silent switch, and the
    /// system default (`.soloAmbient`, which applied before this was
    /// configured at all) stops the other app's audio.
    private static var sessionConfigured = false

    private static func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
        } catch {
            // A session we cannot configure must never silence the app:
            // the players still work under the system default.
            NSLog("AURIE_AUDIO session setup failed: %@",
                  error.localizedDescription)
        }
    }

    private static var players: [String: AVAudioPlayer] = [:]
    private static var ambientPlayer: AVAudioPlayer?

    static func play(_ name: String) {
        guard isEnabled() else { return }
        configureSessionIfNeeded()
        if let player = players[name] {
            player.currentTime = 0
            player.play()
            return
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            return   // placeholder slot not filled — stay silent
        }
        player.volume = 0.5
        players[name] = player
        player.play()
    }

    // MARK: - Calm Mode ambient loop

    /// The selectable calm soundscapes (placeholder files `ambient_<id>.wav`;
    /// TODO(art): real licensed ambient audio, same names).
    static let ambientTracks: [(id: String, label: String)] = [
        ("pad", "Soft pad"), ("waves", "Waves"), ("chimes", "Chimes"),
    ]

    private static var currentAmbient: String?

    /// Fades in the looping calm track (switches cleanly if a different track
    /// is already playing).
    static func startAmbient(track: String) {
        guard isEnabled(), isCalmMusicEnabled() else { return }
        configureSessionIfNeeded()
        let name = "ambient_\(track)"
        if currentAmbient != name {
            ambientPlayer?.stop()
            ambientPlayer = nil
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { return }
            player.numberOfLoops = -1
            ambientPlayer = player
            currentAmbient = name
        }
        ambientPlayer?.volume = 0
        ambientPlayer?.play()
        ambientPlayer?.setVolume(0.3, fadeDuration: 1.2)
    }

    static func stopAmbient() {
        guard let player = ambientPlayer, player.isPlaying else { return }
        player.setVolume(0, fadeDuration: 0.8)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.85))
            if ambientPlayer?.volume == 0 { ambientPlayer?.pause() }
        }
    }

    // MARK: - Radio music loops

    /// The radio's own channel, kept separate from the Calm ambient bed so the
    /// two can never fight over one player. Loops seamlessly; the caller owns
    /// the BPM that the dance beat clock runs on.
    private static var musicPlayer: AVAudioPlayer?
    private(set) static var currentMusic: String?

    /// Start (or switch to) a looping track. Returns the moment playback began
    /// — the beat clock's origin — or nil if the track could not be played.
    @discardableResult
    static func startMusic(_ name: String) -> TimeInterval? {
        guard isEnabled() else { return nil }
        configureSessionIfNeeded()
        if currentMusic != name {
            musicPlayer?.stop()
            musicPlayer = nil
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
            player.numberOfLoops = -1
            player.prepareToPlay()
            musicPlayer = player
            currentMusic = name
        }
        guard let player = musicPlayer else { return nil }
        player.currentTime = 0
        player.volume = 0.55
        player.play()
        return CACurrentMediaTime()
    }

    static func pauseMusic() { musicPlayer?.pause() }

    /// Resume, returning a beat origin aligned to where the loop resumed.
    @discardableResult
    static func resumeMusic() -> TimeInterval? {
        guard isEnabled(), let player = musicPlayer else { return nil }
        configureSessionIfNeeded()
        player.play()
        return CACurrentMediaTime() - player.currentTime
    }

    static func stopMusic() {
        musicPlayer?.stop()
        musicPlayer = nil
        currentMusic = nil
    }
}

// MARK: - Shake detection

extension Notification.Name {
    /// Posted when the device is shaken (Simulator: Device > Shake).
    static let deviceDidShake = Notification.Name("deviceDidShake")
    /// Posted by the Settings accessibility control: run the Wonder shake
    /// without physically shaking the device.
    static let wonderShakeRequested = Notification.Name("wonderShakeRequested")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
