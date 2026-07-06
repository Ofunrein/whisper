import Foundation


struct LocalWhisperModel: Identifiable, Equatable {
    let filename: String
    let label: String
    let size: String
    let url: URL

    var id: String { filename }

    var localURL: URL {
        LocalWhisperTranscriber.modelDirectory.appendingPathComponent(filename)
    }
}

struct LocalWhisperTranscriber: TranscriptionProvider {
    let kind: STTProviderKind = .localWhisper
    var modelPath: String

    static let candidateBinaryPaths = [
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cli",
        "/opt/homebrew/bin/whisper-cpp",
        "/usr/local/bin/whisper-cpp",
        "/opt/homebrew/bin/main",
        "/usr/local/bin/main",
    ]

    static var modelDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Whisper/models", isDirectory: true)
    }

    static var defaultModelPath: String {
        modelDirectory.appendingPathComponent("ggml-base.en.bin").path
    }

    static let downloadableModels: [LocalWhisperModel] = [
        model("ggml-tiny.en.bin", "Tiny English", "75 MB"),
        model("ggml-tiny.bin", "Tiny multilingual", "75 MB"),
        model("ggml-base.en.bin", "Base English", "142 MB"),
        model("ggml-base.bin", "Base multilingual", "142 MB"),
        model("ggml-small.en.bin", "Small English", "466 MB"),
        model("ggml-small.bin", "Small multilingual", "466 MB"),
        model("ggml-medium.en.bin", "Medium English", "1.5 GB"),
        model("ggml-medium.bin", "Medium multilingual", "1.5 GB"),
        model("ggml-large-v3-turbo.bin", "Large v3 Turbo", "1.5 GB"),
        model("ggml-large-v3.bin", "Large v3", "2.9 GB"),
    ]

    private static func model(_ filename: String, _ label: String, _ size: String) -> LocalWhisperModel {
        LocalWhisperModel(
            filename: filename,
            label: label,
            size: size,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
        )
    }

    static func installedModels() -> [String] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: modelDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "bin" || $0.lastPathComponent.hasPrefix("ggml-") }
            .map(\.path)
            .sorted()
    }

    static func ensureModelDirectory() {
        try? FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
    }

    init(modelPath: String? = nil) {
        let trimmed = modelPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            self.modelPath = (trimmed as NSString).expandingTildeInPath
        } else if let first = Self.installedModels().first {
            self.modelPath = first
        } else {
            self.modelPath = Self.defaultModelPath
        }
    }

    func transcribe(wavData: Data) async throws -> String {
        guard let binaryPath = Self.candidateBinaryPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ProviderError.badResponse("whisper-cli not found. Install with: brew install whisper-cpp")
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            Self.ensureModelDirectory()
            throw ProviderError.badResponse("Local Whisper model not found: \(modelPath). Put ggml-base.en.bin or another ggml model in \(Self.modelDirectory.path).")
        }

        let wavURL = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-\(UUID().uuidString).wav")
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
            throw ProviderError.badResponse("Failed launch whisper-cli: \(error.localizedDescription)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let err = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard proc.terminationStatus == 0 else {
                    continuation.resume(throwing: ProviderError.badResponse("whisper-cli \(proc.terminationStatus): \(err.prefix(200))"))
                    return
                }
                continuation.resume(returning: out)
            }
        }
    }
}
