import Foundation
import AVFoundation
import CoreAudio
import Combine

/// Captures microphone audio via AVAudioEngine and returns 16kHz mono 16-bit
/// PCM WAV data. Publishes a smoothed RMS level for the waveform UI.
final class AudioRecorder: ObservableObject {
    @Published var level: Float = 0

    private var engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: 16_000,
                                             channels: 1,
                                             interleaved: true)!

    private let lock = NSLock()
    private var pcm = Data()
    private var recording = false
    private var pcmChunkHandler: ((Data) -> Void)?
    private var engineRunning = false
    private var tapInstalled = false
    private var startTime: Date?

    private var systemAudioCapture: Any?  // SystemAudioCapture, type-erased for the macOS 14.2 availability gate
    private var systemPCM = Data()
    private var systemPeakLevel: Float = 0
    private let systemLock = NSLock()

    private var lastLevelPost = Date.distantPast
    private var smoothed: Float = 0
    private var peakLevel: Float = 0

    private let minDuration: TimeInterval = 0.2

    // MARK: - Lifecycle

    /// Start the engine ahead of time so `start()` is instant.
    func prewarm() {
        _ = ensureEngineRunning()
    }

    private var configObserver: NSObjectProtocol?
    private var rebuildWorkItem: DispatchWorkItem?
    private var repinWorkItem: DispatchWorkItem?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var deviceListListener: AudioObjectPropertyListenerBlock?
    /// Whether the pinned mic was present in the device list at the last
    /// check, so a replug can be distinguished from unrelated list churn.
    private var pinnedDevicePresent = false
    /// Engines replaced by `reconfigure()`, held past any in-flight AVFAudio
    /// callback. See the comment in `reconfigure()`.
    private var retiredEngines: [AVAudioEngine] = []

    /// Mic-pin circuit breaker state. See `applyPreferredDevice`.
    private var pinTarget: String?
    private var pinFailures = 0
    private var pinSuspended = false
    private static let maxPinFailures = 3

    /// Rebuild rate floor. See `observeEngine`.
    private var lastRebuild = Date.distantPast
    private static let minRebuildInterval: TimeInterval = 2

    init() {
        observeEngine()
        observeDefaultInputDevice()
        observeDeviceList()
    }

    deinit {
        if let listener = defaultInputListener {
            AudioDevices.removeDefaultInputDeviceListener(listener)
        }
        if let listener = deviceListListener {
            AudioDevices.removeDeviceListListener(listener)
        }
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
    }

    /// Input device changes (AirPods connect, USB mic unplug) stop the
    /// engine and invalidate the tap format. Rebuild (debounced — several
    /// fire back-to-back mid-transition) so the next recording works.
    private func observeEngine() {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            NSLog("AudioRecorder: engine configuration changed, rebuilding")
            self.rebuildWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.reconfigure() }
            self.rebuildWorkItem = work
            // Rate floor on top of the debounce: a device that flaps
            // continuously (two apps fighting over the default input) would
            // otherwise have us tearing the engine down every ~2s forever.
            // Coalesce into one rebuild per `minRebuildInterval`.
            let earliest = self.lastRebuild.addingTimeInterval(Self.minRebuildInterval)
            let delay = max(0.4, earliest.timeIntervalSinceNow)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    /// Listen directly to CoreAudio's `kAudioHardwarePropertyDefaultInputDevice`
    /// instead of only reacting to `AVAudioEngineConfigurationChange`.
    ///
    /// The engine notification is a side effect of the audio *graph* being
    /// invalidated — it's not a documented guarantee that it fires every time
    /// the system default input changes (e.g. a Bluetooth device can claim
    /// the default while the engine's already-running route is otherwise
    /// left alone). Listening to the HAL property directly gives us the
    /// actual, guaranteed signal for "the default input changed", so a
    /// pinned mic (e.g. Yeti X) gets re-asserted even in cases the engine
    /// notification misses.
    ///
    /// This fires in addition to (and independently of) the engine-config
    /// listener; both funnel into the same debounced re-pin so a device
    /// swap that trips both doesn't double-fire.
    private func observeDefaultInputDevice() {
        defaultInputListener = AudioDevices.addDefaultInputDeviceListener { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                NSLog("AudioRecorder: system default input device changed")
                self.scheduleRepin()
            }
        }
    }

    /// Re-assert the pinned mic when it is plugged back in.
    ///
    /// A USB mic replug (FIFINE, Yeti) frequently changes neither the system
    /// default input nor the engine graph, so neither of the other two
    /// listeners fires and the pin was never re-applied — the app kept
    /// recording from whatever device took over while the mic was unplugged.
    /// Only act on the disappeared -> reappeared edge; the device list also
    /// churns for unrelated reasons (virtual devices, screen-share audio) and
    /// re-pinning on every notification would reintroduce the pin/rebuild
    /// storm the circuit breaker exists to stop.
    private func observeDeviceList() {
        // Seed so a mic already present at launch isn't treated as a replug.
        pinnedDevicePresent = currentPinnedDeviceExists()
        deviceListListener = AudioDevices.addDeviceListListener { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                let present = self.currentPinnedDeviceExists()
                defer { self.pinnedDevicePresent = present }
                guard present, !self.pinnedDevicePresent else { return }
                NSLog("AudioRecorder: pinned input device reappeared, re-pinning")
                // A replug is a genuinely new situation: clear the circuit
                // breaker so a mic that was suspended earlier gets a fresh
                // chance instead of staying permanently unpinnable.
                self.pinFailures = 0
                self.pinSuspended = false
                self.scheduleRepin()
            }
        }
    }

    private func currentPinnedDeviceExists() -> Bool {
        guard let wanted = SettingsStore.shared.settings.preferredInputDevice else { return false }
        return AudioDevices.deviceID(named: wanted) != nil
    }

    /// Debounced re-pin, separate from the full engine `reconfigure()` path.
    /// Bluetooth accessories can take a while to settle their default-device
    /// negotiation after connecting, so a short delay plus a verify/retry in
    /// `applyPreferredDevice()` gives CoreAudio room to finish before we
    /// re-assert our preferred device.
    private func scheduleRepin() {
        repinWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyPreferredDevice() }
        repinWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func start() {
        guard ensureEngineRunning() else { return }
        lock.lock()
        pcm.removeAll(keepingCapacity: true)
        recording = true
        startTime = Date()
        peakLevel = 0
        lock.unlock()
        startSystemAudioIfEnabled()
    }

    func setPCMChunkHandler(_ handler: ((Data) -> Void)?) {
        lock.lock()
        pcmChunkHandler = handler
        lock.unlock()
    }

    private func startSystemAudioIfEnabled() {
        guard SettingsStore.shared.settings.recordSystemAudio == true else { return }
        guard #available(macOS 14.2, *) else {
            NSLog("AudioRecorder: system audio capture requires macOS 14.2+, skipping")
            return
        }
        systemLock.lock()
        systemPCM.removeAll(keepingCapacity: true)
        systemPeakLevel = 0
        systemLock.unlock()
        let capture = SystemAudioCapture()
        do {
            try capture.start { [weak self] chunk in
                guard let self else { return }
                self.systemLock.lock()
                self.systemPCM.append(chunk)
                chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    let samples = raw.bindMemory(to: Int16.self)
                    for s in samples {
                        let norm = min(1, abs(Float(s)) / Float(Int16.max))
                        if norm > self.systemPeakLevel { self.systemPeakLevel = norm }
                    }
                }
                self.systemLock.unlock()
            }
            systemAudioCapture = capture
        } catch {
            NSLog("AudioRecorder: failed to start system audio capture: \(error)")
            systemAudioCapture = nil
        }
    }

    @available(macOS 14.2, *)
    private func stopSystemAudioIfRunning() -> (pcm: Data, peak: Float) {
        guard let capture = systemAudioCapture as? SystemAudioCapture else { return (Data(), 0) }
        capture.stop()
        systemAudioCapture = nil
        systemLock.lock()
        let captured = systemPCM
        let peak = systemPeakLevel
        systemPCM.removeAll(keepingCapacity: false)
        systemPeakLevel = 0
        systemLock.unlock()
        return (captured, peak)
    }

    /// Sample-for-sample additive mix of two 16-bit mono PCM streams (same
    /// sample rate/format). Leftover tail from the longer stream is kept
    /// as-is. Not sample-accurate (mic and system taps start a few ms
    /// apart), which is fine for STT input.
    private static func mixPCM(_ a: Data, _ b: Data) -> Data {
        guard !b.isEmpty else { return a }
        guard !a.isEmpty else { return b }
        let sampleCountA = a.count / 2
        let sampleCountB = b.count / 2
        let sampleCount = max(sampleCountA, sampleCountB)
        var mixed = [Int16](repeating: 0, count: sampleCount)
        a.withUnsafeBytes { (rawA: UnsafeRawBufferPointer) in
            let samplesA = rawA.bindMemory(to: Int16.self)
            for i in 0..<sampleCountA { mixed[i] = samplesA[i] }
        }
        b.withUnsafeBytes { (rawB: UnsafeRawBufferPointer) in
            let samplesB = rawB.bindMemory(to: Int16.self)
            for i in 0..<sampleCountB {
                let sum = Int32(mixed[i]) + Int32(samplesB[i])
                mixed[i] = Int16(max(Int32(Int16.min), min(Int32(Int16.max), sum)))
            }
        }
        return mixed.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Stop capturing and return WAV data, or nil if the take was empty/too short.
    func stop() -> Data? {
        lock.lock()
        recording = false
        let started = startTime
        var raw = pcm
        pcm.removeAll(keepingCapacity: false)
        // Read the mic peak under the same lock the audio thread writes it
        // with. Previously this was an unsynchronized read of a Float written
        // on the render thread: `stop()` could observe a stale 0 for a take
        // that had real speech in it and throw the recording away as silent.
        // That is the intermittent "I talked and nothing got typed" failure.
        let micPeak = peakLevel
        lock.unlock()

        var systemPeak: Float = 0
        if #available(macOS 14.2, *) {
            let system = stopSystemAudioIfRunning()
            systemPeak = system.peak
            if !system.pcm.isEmpty {
                raw = Self.mixPCM(raw, system.pcm)
            }
        }

        DispatchQueue.main.async { self.level = 0 }

        if let started = started, Date().timeIntervalSince(started) < minDuration { return nil }
        guard !raw.isEmpty else { return nil }
        // Silence gate: STT models hallucinate ("Thank you.") on silent audio,
        // which would paste garbage on an accidental hotkey press. Checked
        // against mic AND system audio peak so a quiet mic doesn't discard
        // a take that's carrying real system audio (e.g. meeting playback).
        if micPeak < 0.03 && systemPeak < 0.03 {
            NSLog("AudioRecorder: discarding silent take (peak %.3f, system %.3f)", micPeak, systemPeak)
            return nil
        }
        return Self.wav(fromPCM: raw, sampleRate: 16_000, channels: 1, bitsPerSample: 16)
    }

    // MARK: - Engine

    private func ensureEngineRunning() -> Bool {
        if engineRunning {
            if engine.isRunning { return true }
            // The engine died without an AVAudioEngineConfigurationChange —
            // sleep/wake, a HAL error, or a device yanked mid-session all do
            // this. Trusting the flag alone left the app permanently deaf:
            // start() reported success, the tap never fired, and every take
            // came back nil ("Whisper stopped responding after a while").
            NSLog("AudioRecorder: engine stopped underneath us, rebuilding")
            reconfigure()
            return engineRunning
        }
        // Pin BEFORE touching `engine.inputNode`. The first access to
        // inputNode instantiates the IO node and binds it to whatever the
        // system default input is at that instant, caching that device's
        // format. Pinning afterwards left the node bound to the outgoing
        // device (e.g. AirPods at 24kHz mono) while the hardware had already
        // moved to the pinned mic (FIFINE at 48kHz stereo), so the engine
        // either started against a stale format or immediately fired a
        // configuration change and rebuilt. Setting the default first means
        // the node is created already pointing at the right device.
        applyPreferredDevice()
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else {
            NSLog("AudioRecorder: input format sampleRate=0 (no mic access or no input device)")
            return false
        }
        NSLog("AudioRecorder: engine starting, hw=%.0fHz %dch", hwFormat.sampleRate, hwFormat.channelCount)

        if !tapInstalled {
            // nil format = follow the hardware. Passing an explicit format
            // crashes with an NSException if the device changes between the
            // format read and tap install (observed when pinning the mic).
            input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
                // Audio threads never drain autorelease pools on their own;
                // without this, per-callback ObjC allocations accumulate forever.
                autoreleasepool { self?.process(buffer) }
            }
            tapInstalled = true
        }

        engine.prepare()
        do {
            try engine.start()
            engineRunning = true
            return true
        } catch {
            NSLog("AudioRecorder: engine start failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Pin the configured mic (e.g. Yeti X) by setting it as the system
    /// default input device. AVAudioEngine's input node follows the system
    /// default with correct native format negotiation; poking the IO unit's
    /// CurrentDevice property directly bypasses that and reliably fails to
    /// start (-10868, format not supported).
    ///
    /// Bluetooth accessories (AirPods) can claim the default input mid
    /// negotiation and keep re-asserting it for a moment after connecting,
    /// so `AudioObjectSetPropertyData` can return `noErr` here and still get
    /// silently overwritten a beat later by CoreAudio settling the new
    /// device. Verify the pin actually stuck and retry once after a short
    /// delay if it didn't, instead of firing-and-forgetting the call.
    ///
    /// Bounded by a circuit breaker. Another app can *hold* the default input
    /// device (FineTune's "lock input device", Hammerspoon mic locks, meeting
    /// clients) and slam it back within ~80ms, forever. Retrying into that
    /// produced a self-sustaining fight: pin → their revert → our
    /// default-device listener → repin → AVAudioEngineConfigurationChange →
    /// engine rebuild → repin. The engine was torn down every ~2s, so no
    /// hotkey press ever captured audio (the "Whisper stops responding after a
    /// while" report) and the churn eventually segfaulted AVFAudio. After
    /// `maxPinFailures` consecutive misses we stop writing and follow the
    /// system default instead — degraded mic beats deaf app.
    private func applyPreferredDevice(retriesRemaining: Int = 1) {
        guard let wanted = SettingsStore.shared.settings.preferredInputDevice,
              let deviceID = AudioDevices.deviceID(named: wanted) else { return }
        // A different target means a fresh fight worth having.
        if wanted != pinTarget {
            pinTarget = wanted
            pinFailures = 0
            pinSuspended = false
        }
        guard !pinSuspended else { return }
        // Skip when already the default: setting it unconditionally fires
        // AVAudioEngineConfigurationChange, which triggers a rebuild, which
        // re-pins... an endless restart loop that captures nothing.
        guard AudioDevices.defaultInputDeviceID() != deviceID else { return }
        let err = AudioDevices.setDefaultInputDevice(deviceID)
        NSLog("AudioRecorder: pinning input to '%@' (err %d)", wanted, err)

        guard retriesRemaining > 0 else { return }
        // Re-check shortly after: give CoreAudio/Bluetooth negotiation a beat
        // to settle, then confirm the pin held and retry once if it got
        // clobbered by the system re-asserting the newly connected device.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            if AudioDevices.defaultInputDeviceID() == deviceID {
                self.pinFailures = 0
                return
            }
            self.pinFailures += 1
            guard self.pinFailures < Self.maxPinFailures else {
                self.pinSuspended = true
                NSLog("AudioRecorder: '%@' will not hold as the default input after %d attempts — something else is locking it. Following the system default instead.",
                      wanted, self.pinFailures)
                return
            }
            NSLog("AudioRecorder: pin to '%@' did not stick, retrying", wanted)
            self.applyPreferredDevice(retriesRemaining: retriesRemaining - 1)
        }
    }

    /// Tear down and restart with a FRESH engine (input device change).
    /// Reusing the old engine after a device swap leaves a stale graph that
    /// fails to start with kAudioUnitErr (-10868).
    func reconfigure() {
        // A pending repin from the default-input-device listener is
        // superseded by the fresh pin ensureEngineRunning() below performs
        // against the new engine; drop it so it doesn't fire redundantly.
        repinWorkItem?.cancel()
        lastRebuild = Date()
        let old = engine
        old.stop()
        old.inputNode.removeTap(onBus: 0)
        engine = AVAudioEngine()
        // Hold `old` past this turn of the run loop rather than letting it
        // deallocate inline. AVFAudio installs an IO-unit property listener
        // whose callback is dispatched onto its own AVAudioIOUnit queue and
        // dereferences the engine's internal IO unit without retaining it; a
        // queued callback landing after teardown segfaults in
        // AVAudioIOUnit::IOUnitPropertyListener (EXC_BAD_ACCESS in
        // objc_msgSend). This retain only narrows the dealloc-time window — it
        // does NOT close it, and on its own it did not stop the crash. What
        // actually stopped it was removing the rebuild storm that made the race
        // near-certain: see the circuit breaker in `applyPreferredDevice` and
        // the rate floor in `observeEngine`. Every observed crash happened
        // while the engine was being torn down several times a second.
        retiredEngines.append(old)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.retiredEngines.removeAll { $0 === old }
        }
        observeEngine()
        converter = nil
        converterInputFormat = nil
        tapInstalled = false
        engineRunning = false
        _ = ensureEngineRunning()
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let active = recording
        lock.unlock()

        // Engine runs 24/7 (prewarmed); only push level updates to the main
        // queue while recording. Idle dispatching at 30/s can pile up
        // unboundedly if the main thread ever stalls — that was the 7GB blowup.
        if active { publishLevel(from: buffer) }

        guard active else { return }
        if converter == nil || converterInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            converterInputFormat = buffer.format
        }
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard capacity > 0,
              let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var err: NSError?
        let status = converter.convert(to: out, error: &err) { _, outStatus in
            if fed { outStatus.pointee = .noDataNow; return nil }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0,
              let channel = out.int16ChannelData else { return }

        let byteCount = Int(out.frameLength) * MemoryLayout<Int16>.size
        let chunk = Data(bytes: channel[0], count: byteCount)
        lock.lock()
        pcm.append(chunk)
        let handler = pcmChunkHandler
        lock.unlock()
        handler?(chunk)
    }

    private func publishLevel(from buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        // Take the loudest channel, not channel 0. USB mics commonly present
        // as 2-channel (the FIFINE does, at 48kHz stereo) and some put the
        // capsule on one channel with the other left dead. Measuring only
        // channel 0 on such a device reads silence for real speech, which
        // both flatlines the waveform UI and trips the silence gate in
        // `stop()` so the take is discarded.
        var rms: Float = 0
        for c in 0..<Int(buffer.format.channelCount) {
            var sum: Float = 0
            let samples = ch[c]
            for i in 0..<frames { let s = samples[i]; sum += s * s }
            rms = max(rms, sqrtf(sum / Float(frames)))
        }
        let norm = min(1, rms * 12) // rough gain to spread quiet speech across 0...1
        smoothed = smoothed * 0.8 + norm * 0.2
        lock.lock()
        if norm > peakLevel { peakLevel = norm }
        lock.unlock()

        let now = Date()
        guard now.timeIntervalSince(lastLevelPost) >= 1.0 / 30.0 else { return }
        lastLevelPost = now
        let value = smoothed
        DispatchQueue.main.async { self.level = value }
    }

    // MARK: - WAV

    static func wav(fromPCM pcm: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var data = Data()
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = pcm.count
        let chunkSize = 36 + dataSize

        func appendString(_ s: String) { data.append(contentsOf: s.utf8) }
        func appendLE32(_ v: Int) {
            var le = UInt32(v).littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendLE16(_ v: Int) {
            var le = UInt16(v).littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        appendString("RIFF"); appendLE32(chunkSize); appendString("WAVE")
        appendString("fmt "); appendLE32(16); appendLE16(1) // PCM
        appendLE16(channels); appendLE32(sampleRate); appendLE32(byteRate)
        appendLE16(blockAlign); appendLE16(bitsPerSample)
        appendString("data"); appendLE32(dataSize)
        data.append(pcm)
        return data
    }
}
