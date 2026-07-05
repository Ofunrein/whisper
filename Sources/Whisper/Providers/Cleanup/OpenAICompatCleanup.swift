import Foundation

/// Reusable OpenAI-chat-compatible cleanup provider for Groq, Cerebras, and OpenAI.
struct OpenAICompatCleanup: CleanupProvider {
    let kind: CleanupProviderKind
    let baseURL: String
    let model: String
    let keychainAccount: String
    let providerLabel: String

    func clean(text: String, systemInstruction: String) async throws -> String {
        guard let key = Keychain.get(keychainAccount), !key.isEmpty else {
            throw ProviderError.missingKey(providerLabel)
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemInstruction],
                ["role": "user", "content": text],
            ],
            "temperature": 0.2,
            "stream": false,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await SharedHTTP.session.data(for: request)
        try HTTPCheck.ensure2xx(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ProviderError.badResponse("Missing choices[0].message.content in \(providerLabel) response")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
