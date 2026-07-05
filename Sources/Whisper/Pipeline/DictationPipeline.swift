import Foundation
import Combine

/// Orchestrates one dictation: hotkey-down starts capture, hotkey-up runs
/// STT -> optional time-boxed cleanup -> output routing -> history.
/// Guarantees: never crashes the app; falls back to the raw transcript on any
/// cleanup failure, missing key, or timeout.
final class DictationPipeline: ObservableObject {
    let recorder = AudioRecorder()
    private let output = OutputRouter()
    private var levelCancellable: AnyCancellable?
    private var busy = false

    var onStateChange: ((PillState) -> Void)?

    init() {
        levelCancellable = recorder.$level.sink { [weak self] level in
            PillController.shared.setLevel(level)
            _ = self // keep self captured for lifetime parity
        }
    }

    // MARK: - Hotkey entry points

    func recordStart() {
        guard !busy else { return }
        recorder.prewarm()
        recorder.start()
        SoundPlayer.playStart()
        onStateChange?(.recording)
    }

    func recordStop() {
        guard !busy else { return }
        guard let wav = recorder.stop() else {
            SoundPlayer.playError()
            onStateChange?(.idle)
            return
        }
        SoundPlayer.playStop()
        busy = true
        onStateChange?(.processing)

        let settings = SettingsStore.shared.settings
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.process(wav: wav, settings: settings)
            await MainActor.run {
                self?.busy = false
                self?.onStateChange?(.idle)
            }
        }
    }

    // MARK: - Processing

    private func process(wav: Data, settings: AppSettings) async {
        // 1. Transcribe
        let raw: String
        do {
            let transcriber = ProviderFactory.transcriber(for: settings)
            raw = try await transcriber.transcribe(wavData: wav)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            NSLog("Whisper: transcription failed: \(error.localizedDescription)")
            return
        }
        guard !raw.isEmpty else { return }

        // 2. Optional cleanup, time-boxed; raw text on any failure.
        let cleaned = settings.cleanupEnabled
            ? await cleanWithTimeout(raw, settings: settings)
            : nil
        let finalText = cleaned ?? raw

        // 3. Output on the main thread (pasteboard + CGEvent).
        let appName = await MainActor.run { () -> String? in
            let name = self.output.frontmostAppName()
            self.output.deliver(text: finalText, mode: settings.outputMode)
            return name
        }

        // 4. History (off the hot path).
        var audioFileName: String? = nil
        if settings.saveAudio {
            let name = "\(UUID().uuidString).wav"
            let url = HistoryStore.audioDirectory.appendingPathComponent(name)
            if (try? wav.write(to: url, options: .atomic)) != nil {
                audioFileName = name
            }
        }
        HistoryStore.shared.add(HistoryEntry(
            date: Date(),
            rawText: raw,
            cleanedText: cleaned,
            appName: appName,
            audioFileName: audioFileName
        ))
    }

    /// Run cleanup with a deadline so paste never stalls; nil means "use raw".
    func cleanWithTimeout(_ text: String, settings: AppSettings) async -> String? {
        let cleaner = ProviderFactory.cleaner(for: settings)
        let instruction = settings.cleanupInstructions
        let timeout = settings.cleanupTimeoutSeconds

        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                do {
                    let result = try await cleaner.clean(text: text, systemInstruction: instruction)
                    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                } catch {
                    NSLog("Whisper: cleanup failed, using raw text: \(error.localizedDescription)")
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
