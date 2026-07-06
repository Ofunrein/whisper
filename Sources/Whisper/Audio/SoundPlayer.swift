import AppKit

/// Plays short, subtle start/stop/error cues like Wispr Flow's recording chimes.
///
/// Prefers bundled low-pitched WAV tones under Resources/Sounds/<set>/, chosen
/// via `SettingsStore.shared.settings.soundSet`. Falls back to built-in macOS
/// system sounds when running unbundled (e.g. `swift run` / selftest) where
/// `Bundle.main` has no Resources directory to load from.
enum SoundPlayer {
    enum Clip: String {
        case start = "record-start"
        case stop = "record-stop"
        case error = "record-error"

        var systemSoundFallback: String {
            switch self {
            case .start: return "Tink"
            case .stop: return "Pop"
            case .error: return "Basso"
            }
        }
    }

    static func playStart() {
        guard SettingsStore.shared.settings.soundEffectsEnabled else { return }
        play(.start, set: SettingsStore.shared.settings.soundSet)
    }

    static func playStop() {
        guard SettingsStore.shared.settings.soundEffectsEnabled else { return }
        play(.stop, set: SettingsStore.shared.settings.soundSet)
    }

    static func playError() {
        guard SettingsStore.shared.settings.soundEffectsEnabled else { return }
        play(.error, set: SettingsStore.shared.settings.soundSet)
    }

    /// Plays `clip` from `set` regardless of the sound-effects-enabled toggle
    /// or the user's currently-saved sound set. Used by the Settings preview
    /// "Play" buttons so users can audition a set before applying it.
    static func preview(_ clip: Clip, set: SoundSet) {
        play(clip, set: set)
    }

    private static func play(_ clip: Clip, set: SoundSet) {
        if let url = Bundle.main.url(
            forResource: clip.rawValue,
            withExtension: "wav",
            subdirectory: "Sounds/\(set.rawValue)"
        ), let sound = NSSound(contentsOf: url, byReference: false) {
            sound.play()
            return
        }
        // Unbundled execution (swift run / selftest): no Resources dir exists,
        // so fall back to a built-in system sound.
        NSSound(named: clip.systemSoundFallback)?.play()
    }
}
