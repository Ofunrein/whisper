import Foundation

struct OllamaCleanup: CleanupProvider {
    let kind: CleanupProviderKind = .ollama
    var baseURL: String
    var model: String

    func clean(text: String, systemInstruction: String) async throws -> String {
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemInstruction],
                ["role": "user", "content": text],
            ],
            "stream": false,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw ProviderError.badResponse("Invalid Ollama base URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await SharedHTTP.session.data(for: request)
        try HTTPCheck.ensure2xx(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ProviderError.badResponse("Missing message.content in Ollama response")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
