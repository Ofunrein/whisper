import XCTest
@testable import Whisper

private struct FailingCleaner: CleanupProvider {
    let kind: CleanupProviderKind = .groq
    func clean(text: String, systemInstruction: String) async throws -> String {
        throw ProviderError.missingKey("Groq")
    }
}

private struct SlowCleaner: CleanupProvider {
    let kind: CleanupProviderKind = .groq
    func clean(text: String, systemInstruction: String) async throws -> String {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return "too late"
    }
}

final class PipelineTests: XCTestCase {

    func testCleanupTimeoutHelperFallsBackToNilOnFailure() async {
        // Mirror the pipeline's race logic against a failing provider.
        let result = await race(cleaner: FailingCleaner(), timeout: 2)
        XCTAssertNil(result, "Failure must yield nil so pipeline pastes raw text")
    }

    func testCleanupTimeoutHelperTimesOut() async {
        let start = Date()
        let result = await race(cleaner: SlowCleaner(), timeout: 0.5)
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0, "Deadline must cut off slow cleanup")
    }

    /// Same race construct DictationPipeline.cleanWithTimeout uses.
    private func race(cleaner: CleanupProvider, timeout: Double) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                do {
                    let out = try await cleaner.clean(text: "hello", systemInstruction: "clean")
                    return out.isEmpty ? nil : out
                } catch { return nil }
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

    func testWavHeader() {
        let pcm = Data(repeating: 0, count: 3200) // 0.1s of 16kHz mono 16-bit
        let wav = AudioRecorder.wav(fromPCM: pcm, sampleRate: 16_000, channels: 1, bitsPerSample: 16)
        XCTAssertEqual(wav.count, 44 + pcm.count)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        // sample rate little-endian at offset 24
        let rate = wav.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: rate), 16_000)
    }

    func testMultipartFormShape() {
        var form = MultipartFormBuilder()
        form.addField(name: "model", value: "whisper-large-v3-turbo")
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: Data([1, 2, 3]))
        let body = form.finalize()
        let s = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(s.contains("name=\"model\""))
        XCTAssertTrue(s.contains("whisper-large-v3-turbo"))
        XCTAssertTrue(s.contains("filename=\"audio.wav\""))
        XCTAssertTrue(s.contains("Content-Type: audio/wav"))
        XCTAssertTrue(s.hasSuffix("--\(form.boundary)--\r\n"))
    }

    func testProviderFactoryMapsAllKinds() {
        var settings = AppSettings()
        for kind in STTProviderKind.allCases {
            settings.sttProvider = kind
            XCTAssertEqual(ProviderFactory.transcriber(for: settings).kind, kind)
        }
        for kind in CleanupProviderKind.allCases {
            settings.cleanupProvider = kind
            XCTAssertEqual(ProviderFactory.cleaner(for: settings).kind, kind)
        }
    }

    func testSettingsRoundTrip() throws {
        var s = AppSettings()
        s.cleanupEnabled = false
        s.outputMode = .copyOnly
        s.bindings = [HotkeyBinding(kind: .mouseButton, keyCode: nil, modifiers: nil, mouseButton: 4, style: .toggle)]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(back, s)
    }

    func testDefaultCleanupInstructionsVerbatim() {
        XCTAssertTrue(defaultCleanupInstructions.hasPrefix("You clean up raw speech-to-text transcripts"))
        XCTAssertTrue(defaultCleanupInstructions.contains("If something is ambiguous or clearly misheard, leave it as-is rather than guessing."))
    }
}
