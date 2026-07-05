import Foundation

enum ProviderError: Error, LocalizedError {
    case missingKey(String)
    case http(Int, String)
    case badResponse(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .missingKey(let p): return "Missing API key for \(p)"
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .badResponse(let why): return "Bad response: \(why)"
        case .timeout: return "Request timed out"
        }
    }
}

protocol TranscriptionProvider {
    var kind: STTProviderKind { get }
    /// Transcribe 16kHz mono WAV data to text.
    func transcribe(wavData: Data) async throws -> String
}

protocol CleanupProvider {
    var kind: CleanupProviderKind { get }
    /// Clean a raw transcript using the given system instruction.
    func clean(text: String, systemInstruction: String) async throws -> String
}

/// Shared keep-alive session for all cloud calls (speed: connection reuse, HTTP/2).
enum SharedHTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
}
