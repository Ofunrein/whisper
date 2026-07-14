import Foundation

/// Claude has no STT API — this is cleanup-only. Anthropic's Messages API
/// isn't OpenAI-chat-shaped (system prompt is a top-level field, not a
/// "system" message; response content is a typed block array rather than
/// choices[0].message.content), so this mirrors GeminiCleanup's dedicated
/// pattern instead of routing through OpenAICompatCleanup.
struct AnthropicCleanup: CleanupProvider {
    let kind: CleanupProviderKind = .anthropic
    var model: String

    func clean(text: String, systemInstruction: String) async throws -> String {
        guard let key = Keychain.get(Keychain.anthropicKey), !key.isEmpty else {
            throw ProviderError.missingKey("Claude")
        }

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemInstruction,
            "messages": [
                ["role": "user", "content": text],
            ],
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await SharedHTTP.session.data(for: request)
        try HTTPCheck.ensure2xx(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let responseText = first["text"] as? String else {
            throw ProviderError.badResponse("Missing content[0].text in Claude response")
        }
        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
