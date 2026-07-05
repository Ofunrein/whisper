import Foundation

struct OpenAITranscriber: TranscriptionProvider {
    let kind: STTProviderKind = .openAI
    var model: String = "whisper-1"

    func transcribe(wavData: Data) async throws -> String {
        guard let key = Keychain.get(Keychain.openAIKey), !key.isEmpty else {
            throw ProviderError.missingKey("OpenAI")
        }

        var form = MultipartFormBuilder()
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: wavData)
        form.addField(name: "model", value: model)
        let body = form.finalize()

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await SharedHTTP.session.data(for: request)
        try HTTPCheck.ensure2xx(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw ProviderError.badResponse("Missing \"text\" field in OpenAI response")
        }
        return text
    }
}
