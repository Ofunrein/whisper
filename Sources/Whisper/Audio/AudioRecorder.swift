import Foundation
import AVFoundation
import Combine

/// Captures microphone audio via AVAudioEngine and returns 16kHz mono 16-bit
/// PCM WAV data. Publishes a smoothed RMS level for the waveform UI.
final class AudioRecorder: ObservableObject {
    @Published var level: Float = 0

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: 16_000,
                                             channels: 1,
                                             interleaved: true)!

    private let lock = NSLock()
    private var pcm = Data()
    private var recording = false
    private var engineRunning = false
    private var tapInstalled = false
    private var startTime: Date?

    private var lastLevelPost = Date.distantPast
    private var smoothed: Float = 0

    private let minDuration: TimeInterval = 0.2

    // MARK: - Lifecycle

    /// Start the engine ahead of time so `start()` is instant.
    func prewarm() {
        _ = ensureEngineRunning()
    }

    func start() {
        guard ensureEngineRunning() else { return }
        lock.lock()
        pcm.removeAll(keepingCapacity: true)
        recording = true
        startTime = Date()
        lock.unlock()
    }

    /// Stop capturing and return WAV data, or nil if the take was empty/too short.
    func stop() -> Data? {
        lock.lock()
        recording = false
        let started = startTime
        let raw = pcm
        pcm.removeAll(keepingCapacity: false)
        lock.unlock()

        DispatchQueue.main.async { self.level = 0 }

        if let started = started, Date().timeIntervalSince(started) < minDuration { return nil }
        guard !raw.isEmpty else { return nil }
        return Self.wav(fromPCM: raw, sampleRate: 16_000, channels: 1, bitsPerSample: 16)
    }

    // MARK: - Engine

    private func ensureEngineRunning() -> Bool {
        if engineRunning { return true }
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else { return false }

        converter = AVAudioConverter(from: hwFormat, to: targetFormat)

        if !tapInstalled {
            input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
                self?.process(buffer)
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

    private func process(_ buffer: AVAudioPCMBuffer) {
        publishLevel(from: buffer)

        lock.lock()
        let active = recording
        lock.unlock()
        guard active, let converter = converter else { return }

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
        lock.unlock()
    }

    private func publishLevel(from buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var sum: Float = 0
        let samples = ch[0]
        for i in 0..<frames { let s = samples[i]; sum += s * s }
        let rms = sqrtf(sum / Float(frames))
        let norm = min(1, rms * 12) // rough gain to spread quiet speech across 0...1
        smoothed = smoothed * 0.8 + norm * 0.2

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
