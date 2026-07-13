import Foundation

struct ElevenLabsTranscriber: TranscriptionProvider {
    let kind: STTProviderKind = .elevenLabs
    var modelId: String = "scribe_v2"

    func transcribe(wavData: Data) async throws -> String {
        guard let key = Keychain.get(Keychain.elevenLabsKey), !key.isEmpty else {
            throw ProviderError.missingKey("ElevenLabs")
        }

        var form = MultipartFormBuilder()
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: wavData)
        form.addField(name: "model_id", value: modelId)
        let body = form.finalize()

        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await SharedHTTP.session.data(for: request)
        try HTTPCheck.ensure2xx(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw ProviderError.badResponse("Missing \"text\" field in ElevenLabs response")
        }
        return text
    }
}
