import Foundation

struct DeepgramTranscriber: TranscriptionProvider {
    let kind: STTProviderKind = .deepgram
    var model: String = "nova-3"

    func transcribe(wavData: Data) async throws -> String {
        guard let key = Keychain.get(Keychain.deepgramKey), !key.isEmpty else {
            throw ProviderError.missingKey("Deepgram")
        }

        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: "true"),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
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
