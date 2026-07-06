import Foundation
import Combine
import AppKit

/// Orchestrates one dictation: hotkey-down starts capture, hotkey-up runs
/// STT -> optional time-boxed cleanup -> output routing -> history.
/// Guarantees: never crashes the app; falls back to the raw transcript on any
/// cleanup failure, missing key, or timeout.
final class DictationPipeline: ObservableObject {
    let recorder = AudioRecorder()
    private let output = OutputRouter()
    private var levelCancellable: AnyCancellable?
    private var busy = false
    private var pasteTargetPID: pid_t?

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
        pasteTargetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        NSLog("Whisper: recordStart")
        recorder.prewarm()
        recorder.start()
        PlaybackDucker.duckForRecording()
        SoundPlayer.playStart()
        onStateChange?(.recording)
    }

    func recordStop() {
        guard !busy else { return }
        guard let wav = recorder.stop() else {
            NSLog("Whisper: recordStop -> no audio captured (too short or engine failed)")
            PlaybackDucker.restoreAfterRecording()
            SoundPlayer.playError()
            onStateChange?(.idle)
            return
        }
        NSLog("Whisper: recordStop -> %d bytes captured", wav.count)
        PlaybackDucker.restoreAfterRecording()
        SoundPlayer.playStop()
        busy = true
        onStateChange?(.processing)

        let settings = SettingsStore.shared.settings
        let pasteTargetPID = pasteTargetPID
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.process(wav: wav, settings: settings, pasteTargetPID: pasteTargetPID)
            await MainActor.run {
                self?.busy = false
                self?.onStateChange?(.idle)
            }
        }
    }

    // MARK: - Processing

    private func process(wav: Data, settings: AppSettings, pasteTargetPID: pid_t?) async {
        // 1. Transcribe
        let raw: String
        do {
            let transcriber = ProviderFactory.transcriber(for: settings)
            raw = try await transcriber.transcribe(wavData: wav)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            NSLog("Whisper: transcription failed: \(error.localizedDescription)")
            await MainActor.run {
                SoundPlayer.playError()
                PillController.shared.flashError()
            }
            return
        }
        guard !raw.isEmpty else { return }

        // 2. Optional cleanup, time-boxed; raw text on any failure.
        let cleaned = settings.cleanupEnabled
            ? await cleanWithTimeout(raw, settings: settings)
            : nil
        // 3. Vocabulary replacements always run, cleanup or not — they fix
        // STT mishears (e.g. a misheard name) the cleanup model may not catch.
        let finalText = VocabularyEngine.applyReplacements(cleaned ?? raw, vocabulary: settings.vocabulary)

        // 4. Output on the main thread (pasteboard + CGEvent).
        let appName = await MainActor.run { () -> String? in
            let target = pasteTargetPID.flatMap { NSRunningApplication(processIdentifier: $0) }
            let name = target?.localizedName ?? self.output.frontmostAppName()
            if let target, target.bundleIdentifier != Bundle.main.bundleIdentifier {
                if let url = target.bundleURL {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: config)
                } else {
                    target.activate()
                }
            }
            self.output.deliver(text: finalText, mode: settings.outputMode, keepOnClipboard: settings.keepOnClipboardAfterPaste, targetPID: pasteTargetPID)
            return name
        }

        // 5. History (off the hot path).
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
        await Self.cleanWithTimeout(text, settings: settings)
    }

    /// Static, UI-free version usable from selftest and tests.
    static func cleanWithTimeout(_ text: String, settings: AppSettings) async -> String? {
        let cleaner = ProviderFactory.cleaner(for: settings)
        let instruction = settings.cleanupInstructions + (VocabularyEngine.hint(for: settings.vocabulary) ?? "")
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
