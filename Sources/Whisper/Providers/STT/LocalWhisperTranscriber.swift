import Foundation

struct LocalWhisperTranscriber: TranscriptionProvider {
    let kind: STTProviderKind = .localWhisper
    var modelPath: String

    private static let candidateBinaryPaths = [
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cli",
    ]

    init(modelPath: String? = nil) {
        if let modelPath {
            self.modelPath = modelPath
        } else {
            let base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Whisper/models/ggml-base.en.bin")
            self.modelPath = base.path
        }
    }

    func transcribe(wavData: Data) async throws -> String {
        guard let binaryPath = Self.candidateBinaryPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ProviderError.badResponse(
                "whisper-cli not found. Install it with: brew install whisper-cpp"
            )
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw ProviderError.badResponse(
                "Whisper model not found at \(modelPath). Download a ggml model (e.g. ggml-base.en.bin) into that location."
            )
        }

        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent("whisper-\(UUID().uuidString).wav")
        try wavData.write(to: wavURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["-m", modelPath, "-f", wavURL.path, "-nt", "-np"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ProviderError.badResponse("Failed to launch whisper-cli: \(error.localizedDescription)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if proc.terminationStatus != 0 {
                    let errString = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: ProviderError.badResponse(
                        "whisper-cli exited with status \(proc.terminationStatus): \(errString.prefix(200))"
                    ))
                    return
                }
                continuation.resume(returning: output)
            }
        }
    }
}
