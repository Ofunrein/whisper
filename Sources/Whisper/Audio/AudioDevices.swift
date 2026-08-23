import CoreAudio
import Foundation

/// Enumerates input-capable audio devices so a specific mic (e.g. Yeti X)
/// can be pinned instead of following the system default.
enum AudioDevices {
    static func inputDeviceNames() -> [String] {
        inputDevices().map(\.name)
    }

    static func deviceID(named name: String) -> AudioDeviceID? {
        inputDevices().first { $0.name == name }?.id
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &id) == noErr else { return nil }
        return id
    }

    /// Sets the system-wide default input device. AVAudioEngine's input node
    /// follows this automatically with correct native format negotiation —
    /// poking the IO unit's kAudioOutputUnitProperty_CurrentDevice directly
    /// bypasses AVAudioEngine's own format caching and reliably produces
    /// kAudioUnitErr_FormatNotSupported (-10868) on engine.start().
    @discardableResult
    static func setDefaultInputDevice(_ id: AudioDeviceID) -> OSStatus {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = id
        let sys = AudioObjectID(kAudioObjectSystemObject)
        return AudioObjectSetPropertyData(sys, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID)
    }

    /// Registers a listener for system default-input-device changes, firing
    /// directly on CoreAudio's own notification for
    /// `kAudioHardwarePropertyDefaultInputDevice` rather than relying on
    /// AVAudioEngine's `AVAudioEngineConfigurationChange`, which is a side
    /// effect of engine-graph invalidation and isn't a guaranteed, documented
    /// signal for "the default input changed" — e.g. a Bluetooth device
    /// taking over the default while the engine's current route is otherwise
    /// undisturbed. Returns an opaque token to pass to
    /// `removeDefaultInputDeviceListener`. The callback fires on an internal
    /// CoreAudio dispatch queue, not necessarily the main thread.
    @discardableResult
    static func addDefaultInputDeviceListener(_ handler: @escaping () -> Void) -> AudioObjectPropertyListenerBlock {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        let status = AudioObjectAddPropertyListenerBlock(sys, &addr, DispatchQueue.global(qos: .userInitiated), block)
        if status != noErr {
            NSLog("AudioDevices: failed to add default input device listener (err %d)", status)
        }
        return block
    }

    static func removeDefaultInputDeviceListener(_ block: @escaping AudioObjectPropertyListenerBlock) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectRemovePropertyListenerBlock(sys, &addr, DispatchQueue.global(qos: .userInitiated), block)
    }

    /// Registers a listener for the hardware *device list* changing — i.e. a
    /// USB mic being unplugged or plugged back in.
    ///
    /// This is a distinct signal from `kAudioHardwarePropertyDefaultInputDevice`
    /// and neither of the other two listeners covers it. Replugging a USB mic
    /// (FIFINE, Yeti) does not necessarily change the system default input:
    /// when the device vanishes CoreAudio moves the default elsewhere, and
    /// when it comes back macOS commonly *keeps* the fallback as the default.
    /// No default change means no `kAudioHardwarePropertyDefaultInputDevice`
    /// notification, and a device merely appearing doesn't invalidate the
    /// running engine graph either, so no `AVAudioEngineConfigurationChange`.
    /// Without this listener the pinned mic silently never gets re-asserted
    /// after a replug and the app keeps recording from the fallback device.
    /// The callback fires on an internal CoreAudio dispatch queue.
    @discardableResult
    static func addDeviceListListener(_ handler: @escaping () -> Void) -> AudioObjectPropertyListenerBlock {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        let status = AudioObjectAddPropertyListenerBlock(sys, &addr, DispatchQueue.global(qos: .userInitiated), block)
        if status != noErr {
            NSLog("AudioDevices: failed to add device list listener (err %d)", status)
        }
        return block
    }

    static func removeDeviceListListener(_ block: @escaping AudioObjectPropertyListenerBlock) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectRemovePropertyListenerBlock(sys, &addr, DispatchQueue.global(qos: .userInitiated), block)
    }

    /// Known dedicated-microphone brands, matched case-insensitively against
    /// the device name. Deliberately a small allow-list rather than "any USB
    /// input": USB capture cards, webcams and virtual devices (Camo, Webex,
    /// OBS) all enumerate as input-capable too and are the wrong default.
    /// ponytail: allow-list, order = preference. Add names as users report
    /// mics that should be auto-picked.
    private static let dedicatedMicMatches = [
        "yeti", "fifine", "shure", "rode", "røde", "at2020", "audio-technica",
        "samson", "elgato wave", "hyperx", "blue "
    ]

    /// First connected input device that looks like a dedicated microphone,
    /// used only to seed the preference on first run when the user hasn't
    /// picked one. Returns nil if nothing recognisable is attached, leaving
    /// the app on the system default.
    static func preferredDedicatedMicName() -> String? {
        preferredDedicatedMic(from: inputDeviceNames())
    }

    /// Pure form of `preferredDedicatedMicName`, split out so it is testable
    /// without real hardware attached.
    static func preferredDedicatedMic(from names: [String]) -> String? {
        for match in dedicatedMicMatches {
            if let hit = names.first(where: { $0.lowercased().contains(match) }) { return hit }
        }
        return nil
    }

    static func inputDevices() -> [(id: AudioDeviceID, name: String)] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasInputChannels(id), let name = name(of: id) else { return nil }
            return (id, name)
        }
    }

    private static func hasInputChannels(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buf) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(buf.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cf: CFString?
        let err = withUnsafeMutablePointer(to: &cf) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard err == noErr, let cf else { return nil }
        return cf as String
    }
}
