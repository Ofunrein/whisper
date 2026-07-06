import Foundation

struct LocalWhisperDownloader {
    static func download(_ model: LocalWhisperModel) async throws -> URL {
        LocalWhisperTranscriber.ensureModelDirectory()
        let destination = model.localURL
        if FileManager.default.fileExists(atPath: destination.path) { return destination }

        let tmp = destination.appendingPathExtension("download")
        try? FileManager.default.removeItem(at: tmp)
        let (downloaded, response) = try await URLSession.shared.download(from: model.url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ProviderError.badResponse("Model download failed: HTTP \(http.statusCode)")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: downloaded, to: tmp)
        try FileManager.default.moveItem(at: tmp, to: destination)
        return destination
    }
}
