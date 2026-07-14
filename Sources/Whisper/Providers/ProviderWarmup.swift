import Foundation

enum ProviderWarmup {
    static func preconnectGroq() async {
        guard let key = Keychain.get(Keychain.groqKey), !key.isEmpty else { return }
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
        request.timeoutInterval = 3
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let started = Date()
        do {
            let (_, response) = try await SharedHTTP.session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            NSLog("Whisper: Groq connection warmed in %.0fms", Date().timeIntervalSince(started) * 1_000)
        } catch {
            NSLog("Whisper: Groq preconnect skipped: %@", error.localizedDescription)
        }
    }
}
