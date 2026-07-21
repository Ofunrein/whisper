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
    private var isRecording = false
    private var processingCount = 0
    private var pasteTargetPID: pid_t?
    private var deepgramStream: DeepgramStreamingSession?

    var onStateChange: ((PillState) -> Void)?

    init() {
        levelCancellable = recorder.$level.sink { [weak self] level in
            PillController.shared.setLevel(level)
            _ = self // keep self captured for lifetime parity
        }
        Task.detached(priority: .utility) {
            await ProviderWarmup.preconnectGroq()
        }
    }

    // MARK: - Hotkey entry points

    func recordStart() {
        guard !isRecording else { return }
        isRecording = true
        pasteTargetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let settings = SettingsStore.shared.settings
        deepgramStream?.cancel()
        deepgramStream = nil
        recorder.setPCMChunkHandler(nil)
        if settings.sttProvider == .deepgram, settings.recordSystemAudio != true {
            let stream = DeepgramStreamingSession()
            deepgramStream = stream
            recorder.setPCMChunkHandler { [weak stream] chunk in stream?.push(chunk) }
            stream.start()
        }
        NSLog("Whisper: recordStart")
        recorder.prewarm()
        recorder.start()
        PlaybackDucker.duckForRecording()
        SoundPlayer.playStart()
        onStateChange?(.recording)
    }

    func recordStop() {
        guard isRecording else { return }
        isRecording = false
        let releasedAt = Date()
        let stream = deepgramStream
        deepgramStream = nil
        recorder.setPCMChunkHandler(nil)
        guard let wav = recorder.stop() else {
            stream?.cancel()
            NSLog("Whisper: recordStop -> no audio captured (too short or engine failed)")
            PlaybackDucker.restoreAfterRecording()
            SoundPlayer.playError()
            onStateChange?(processingCount == 0 ? .idle : .processing)
            return
        }
        NSLog("Whisper: recordStop -> %d bytes captured", wav.count)
        PlaybackDucker.restoreAfterRecording()
        SoundPlayer.playStop()
        processingCount += 1
        onStateChange?(.processing)

        let settings = SettingsStore.shared.settings
        let pasteTargetPID = pasteTargetPID
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.process(
                wav: wav,
                settings: settings,
                pasteTargetPID: pasteTargetPID,
                deepgramStream: stream,
                releasedAt: releasedAt
            )
            guard let self else { return }
            await MainActor.run {
                self.processingCount = max(0, self.processingCount - 1)
                if !self.isRecording && self.processingCount == 0 {
                    self.onStateChange?(.idle)
                }
            }
        }
    }

    // MARK: - Processing

    private func process(
        wav: Data,
        settings: AppSettings,
        pasteTargetPID: pid_t?,
        deepgramStream: DeepgramStreamingSession?,
        releasedAt: Date
    ) async {
        // 1. Transcribe. A failed provider gets one or more already-configured
        // cloud backups, each bounded by the STT deadline; never leave a dictation
        // spinner waiting on the old 10-minute transport timeout.
        let raw: String
        var transport = "batch"
        let sttStarted = Date()
        do {
            if let deepgramStream {
                do {
                    let streamed = try await deepgramStream.finish()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if Self.isLikelySilenceHallucination(streamed) {
                        throw ProviderError.badResponse("Deepgram stream returned a silence hallucination")
                    }
                    raw = streamed
                    transport = "streaming"
                } catch {
                    NSLog("Whisper: Deepgram stream failed (%@), using batch fallback", error.localizedDescription)
                    raw = try await Self.transcribeWithFallback(
                        wavData: wav,
                        primary: ProviderFactory.transcriber(for: settings),
                        fallbacks: ProviderFactory.fallbackTranscribers(for: settings),
                        timeout: settings.effectiveSTTTimeoutSeconds
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                raw = try await Self.transcribeWithFallback(
                    wavData: wav,
                    primary: ProviderFactory.transcriber(for: settings),
                    fallbacks: ProviderFactory.fallbackTranscribers(for: settings),
                    timeout: settings.effectiveSTTTimeoutSeconds
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            NSLog("Whisper: STT completed in %.0fms", Date().timeIntervalSince(sttStarted) * 1_000)
        } catch {
            NSLog("Whisper: transcription failed after %.0fms: \(error.localizedDescription)", Date().timeIntervalSince(sttStarted) * 1_000)
            await MainActor.run {
                SoundPlayer.playError()
                PillController.shared.flashError()
            }
            return
        }
        guard !raw.isEmpty else { return }
        let sttMs = Date().timeIntervalSince(sttStarted) * 1_000

        // 2. Optional cleanup, time-boxed; raw text on any failure.
        let cleanupStarted = Date()
        let cleaned = settings.cleanupEnabled
            ? await cleanWithTimeout(raw, settings: settings)
            : nil
        let cleanupMs = settings.cleanupEnabled ? Date().timeIntervalSince(cleanupStarted) * 1_000 : 0
        // 3. Vocabulary replacements always run, cleanup or not — they fix
        // STT mishears (e.g. a misheard name) the cleanup model may not catch.
        let finalText = VocabularyEngine.applyReplacements(cleaned ?? raw, vocabulary: settings.vocabulary)

        // 4. Output on the main thread (pasteboard + CGEvent).
        let pasteStarted = Date()
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
        let pasteMs = Date().timeIntervalSince(pasteStarted) * 1_000

        await LatencyMetrics.shared.record(DictationLatency(
            date: Date(),
            provider: settings.sttProvider.rawValue,
            transport: transport,
            words: finalText.split(whereSeparator: { $0.isWhitespace }).count,
            sttMs: sttMs,
            cleanupMs: cleanupMs,
            pasteMs: pasteMs,
            releaseToPasteMs: Date().timeIntervalSince(releasedAt) * 1_000
        ))

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

    /// STT deadline + ordered backup path. Each provider gets a bounded chance;
    /// a blank response counts as a failure so it cannot beat a usable backup.
    static func transcribeWithFallback(
        wavData: Data,
        primary: TranscriptionProvider,
        fallbacks: [TranscriptionProvider],
        timeout: Double
    ) async throws -> String {
        var lastError: Error = ProviderError.timeout
        for provider in [primary] + fallbacks {
            do {
                let text = try await transcribeWithDeadline(provider, wavData: wavData, timeout: timeout)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    throw ProviderError.badResponse("\(provider.kind.displayName) returned an empty transcript")
                }
                guard !isLikelySilenceHallucination(text) else {
                    throw ProviderError.badResponse("\(provider.kind.displayName) returned a silence hallucination")
                }
                return text
            } catch {
                lastError = error
                NSLog("Whisper: STT %@ failed (%@); trying backup if configured", provider.kind.displayName, error.localizedDescription)
            }
        }
        throw lastError
    }

    static func isLikelySilenceHallucination(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [
            "thank you",
            "thank you thank you",
            "thanks for watching",
            "thank you for watching",
            "ご視聴ありがとうございました",
        ].contains(normalized)
    }

    static func transcribeWithDeadline(
        _ provider: TranscriptionProvider,
        wavData: Data,
        timeout: Double
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await provider.transcribe(wavData: wavData) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(timeout, 0.1) * 1_000_000_000))
                throw ProviderError.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw ProviderError.timeout }
            return first
        }
    }

    /// Run cleanup with a deadline so paste never stalls; nil means "use raw".
    func cleanWithTimeout(_ text: String, settings: AppSettings) async -> String? {
        await Self.cleanWithTimeout(text, settings: settings)
    }

    /// Choose a cleanup budget from the transcript shape. This avoids the bad
    /// tradeoff of a single deadline: short "yes, tomorrow works" dictation
    /// returns quickly, while URLs, code, names, numbers, vocabulary, and long
    /// dictation get enough time for the model to repair them correctly.
    static func cleanupDeadline(for text: String, settings: AppSettings) -> Double {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        var recommended: Double
        switch words {
        case 0...12: recommended = 2.5
        case 13...60: recommended = 4.0
        case 61...180: recommended = 6.0
        default: recommended = 8.0
        }

        let edgeCasePattern = #"(?i)(https?://|www\.|@|[/\\]|--|\b\d{3,}\b|[{}<>])"#
        let hasStructuredContent = text.range(of: edgeCasePattern, options: .regularExpression) != nil
        let hasKnownVocabulary = settings.vocabulary.contains {
            !$0.from.isEmpty && text.range(of: $0.from, options: .caseInsensitive) != nil
        }
        if hasStructuredContent || hasKnownVocabulary { recommended += 2.0 }

        let ceiling = min(max(settings.cleanupTimeoutSeconds, 2.0), 15.0)
        return min(recommended, ceiling)
    }

    /// Static, UI-free version usable from selftest and tests.
    static func cleanWithTimeout(_ text: String, settings: AppSettings) async -> String? {
        let cleaner = ProviderFactory.cleaner(for: settings)
        let instruction = settings.cleanupInstructions + (VocabularyEngine.hint(for: settings.vocabulary) ?? "")
        let timeout = cleanupDeadline(for: text, settings: settings)

        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                do {
                    let result = try await cleaner.clean(text: text, systemInstruction: instruction)
                    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { return nil }
                    if RefusalGuard.isRefusal(cleaned: trimmed, raw: text) {
                        NSLog("Whisper: cleanup returned a refusal-shaped response, using raw text instead")
                        return nil
                    }
                    return trimmed
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
