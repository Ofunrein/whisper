import Foundation
import CoreAudio
import AudioToolbox
import AppKit

/// Ducks system audio output while recording so dictation isn't picked up
/// mixed with music/video, then restores it after. Two independent levers:
/// - Volume (mute/lower): kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
///   the same lever the physical volume keys use — affects every app at once,
///   no per-app permissions needed.
/// - Pause: synthesizes the system Play/Pause media key (NX_KEYTYPE_PLAY),
///   the same event Control Center's Now Playing widget sends — toggles
///   whatever app currently holds the system "now playing" session (Music,
///   Spotify, most browsers' media sessions). Pressed again on restore to
///   resume, so it only works if nothing else was toggled in between.
enum PlaybackDucker {
    private static var savedVolume: Float32?
    private static var isDucked = false
    private static var pausedViaMediaKey = false

    static func duckForRecording() {
        guard !isDucked else { return }
        let mode = SettingsStore.shared.settings.playbackDuckMode
        guard mode != .keepPlaying else { return }
        isDucked = true

        switch mode {
        case .keepPlaying:
            break
        case .pause:
            sendPlayPauseMediaKey()
            pausedViaMediaKey = true
        case .mute:
            if let deviceID = defaultOutputDevice() {
                savedVolume = outputVolume(deviceID)
                setOutputVolume(deviceID, 0)
            }
        case .lower:
            if let deviceID = defaultOutputDevice(), let current = outputVolume(deviceID) {
                savedVolume = current
                setOutputVolume(deviceID, current * 0.25)
            }
        }
    }

    static func restoreAfterRecording() {
        guard isDucked else { return }
        isDucked = false

        if pausedViaMediaKey {
            pausedViaMediaKey = false
            sendPlayPauseMediaKey() // toggle back to resume
        }
        if let deviceID = defaultOutputDevice(), let saved = savedVolume {
            setOutputVolume(deviceID, saved)
        }
        savedVolume = nil
    }

    // MARK: - Media key (Play/Pause)

    private static func sendPlayPauseMediaKey() {
        let NX_KEYTYPE_PLAY: UInt32 = 16
        for down in [true, false] {
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: down ? NSEvent.ModifierFlags(rawValue: 0xa00) : NSEvent.ModifierFlags(rawValue: 0xb00),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: Int((NX_KEYTYPE_PLAY << 16) | (down ? 0xa00 : 0xb00)),
                data2: -1
            ), let cgEvent = event.cgEvent else { continue }
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    // MARK: - CoreAudio volume control

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &id) == noErr else { return nil }
        return id
    }

    private static func outputVolume(_ id: AudioDeviceID) -> Float32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    private static func setOutputVolume(_ id: AudioDeviceID, _ volume: Float32) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &addr) else { return }
        var v = max(0, min(1, volume))
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }
}
