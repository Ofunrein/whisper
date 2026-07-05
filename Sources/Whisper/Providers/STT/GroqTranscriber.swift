import Foundation

struct GroqTranscriber: TranscriptionProvider {
    let kind: STTProviderKind = .groq
    var model: String = "whisper-large-v3-turbo"
    var language: String?

    func transcribe(wavData: Data) async throws -> String {
        guard let key = Keychain.get(Keychain.groqKey), !key.isEmpty else {
            throw ProviderError.missingKey("Groq")
        }

        var form = MultipartFormBuilder()
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: wavData)
        form.addField(name: "model", value: model)
        form.addField(name: "response_format", value: "json")
        if let language, !language.isEmpty {
            form.addField(name: "language", value: language)
        }
        let body = form.finalize()

        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await SharedHTTP.session.data(for: request)
        try HTTPCheck.ensure2xx(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw ProviderError.badResponse("Missing \"text\" field in Groq response")
        }
        return text
    }
}
