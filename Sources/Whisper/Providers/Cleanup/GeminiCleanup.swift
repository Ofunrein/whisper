import Foundation

struct GeminiCleanup: CleanupProvider {
    let kind: CleanupProviderKind = .gemini
    var model: String

    func clean(text: String, systemInstruction: String) async throws -> String {
        guard let key = Keychain.get(Keychain.geminiKey), !key.isEmpty else {
            throw ProviderError.missingKey("Gemini")
        }

        let payload: [String: Any] = [
            "system_instruction": ["parts": [["text": systemInstruction]]],
            "contents": [["parts": [["text": text]]]],
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await SharedHTTP.session.data(for: request)
        try HTTPCheck.ensure2xx(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let responseText = firstPart["text"] as? String else {
            throw ProviderError.badResponse("Missing candidates[0].content.parts[0].text in Gemini response")
        }
        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
