import AppKit

/// Plays short, subtle start/stop cues like Wispr Flow's recording chimes.
/// Uses built-in system sounds so no audio assets need to be bundled.
enum SoundPlayer {
    static func playStart() {
        guard SettingsStore.shared.settings.soundEffectsEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    static func playStop() {
        guard SettingsStore.shared.settings.soundEffectsEnabled else { return }
        NSSound(named: "Pop")?.play()
    }

    static func playError() {
        guard SettingsStore.shared.settings.soundEffectsEnabled else { return }
        NSSound(named: "Basso")?.play()
    }
}
