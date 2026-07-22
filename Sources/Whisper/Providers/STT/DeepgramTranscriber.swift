import Foundation

struct DeepgramTranscriber: TranscriptionProvider {
    let kind: STTProviderKind = .deepgram
    var model: String = "nova-3"
    var keyterms: [String] = []

    static func url(model: String = "nova-3", keyterms: [String]) -> URL {
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: "true"),
        ] + keyterms.prefix(100).map { URLQueryItem(name: "keyterm", value: $0) }
        return components.url!
    }

    func transcribe(wavData: Data) async throws -> String {
        guard let key = Keychain.get(Keychain.deepgramKey), !key.isEmpty else {
            throw ProviderError.missingKey("Deepgram")
        }

        var request = URLRequest(url: Self.url(model: model, keyterms: keyterms))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData

        let (data, response) = try await SharedHTTP.session.data(for: request)
        try HTTPCheck.ensure2xx(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let firstChannel = channels.first,
              let alternatives = firstChannel["alternatives"] as? [[String: Any]],
              let firstAlternative = alternatives.first,
              let transcript = firstAlternative["transcript"] as? String else {
            throw ProviderError.badResponse("Unexpected Deepgram response shape")
        }
        return transcript
    }
}
