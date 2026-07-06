import Foundation

/// Fetches the live model list from each provider's /models endpoint so the
/// Settings dropdowns always show current models — new releases appear
/// automatically, SuperWhisper-style. Results are per-session cached;
/// re-opening Settings refreshes.
@MainActor
final class ModelCatalog: ObservableObject {
    static let shared = ModelCatalog()

    enum Provider: String, CaseIterable {
        case gemini, groq, cerebras, openAI, ollama
    }

    @Published var models: [Provider: [String]] = [:]
    @Published var ollamaModelSizes: [String: Int64] = [:] // bytes, installed models only
    @Published var pullingOllamaModel: String? = nil
    @Published var pullProgress: String = ""

    func refresh() {
        for provider in Provider.allCases {
            Task { [weak self] in
                guard let list = try? await Self.fetch(provider), !list.isEmpty else { return }
                await MainActor.run { self?.models[provider] = list }
            }
        }
        Task { [weak self] in
            guard let sizes = try? await Self.fetchOllamaSizes() else { return }
            await MainActor.run { self?.ollamaModelSizes = sizes }
        }
    }

    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// True once the model is confirmed present in the fetched list for that
    /// provider. Only meaningful for Ollama, where "not fetched yet" and
    /// "not installed locally" are the same signal — Ollama's /api/tags only
    /// lists models already pulled, unlike the other providers' catalogs
    /// which list everything available to the account.
    func isOllamaModelInstalled(_ name: String) -> Bool {
        models[.ollama]?.contains(name) ?? false
    }

    /// Pulls a model via Ollama's streaming /api/pull endpoint and refreshes
    /// the installed-model list on completion.
    func pullOllamaModel(_ name: String) async {
        guard pullingOllamaModel == nil else { return }
        await MainActor.run {
            pullingOllamaModel = name
            pullProgress = "Starting…"
        }
        defer { Task { @MainActor in pullingOllamaModel = nil; pullProgress = "" } }

        let base = SettingsStore.shared.settings.ollamaBaseURL
        guard let url = URL(string: "\(base)/api/pull") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name])

        guard let (byteStream, response) = try? await URLSession.shared.bytes(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            await MainActor.run { pullProgress = "Failed to start pull" }
            return
        }

        do {
            for try await line in byteStream.lines {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let status = json["status"] as? String ?? ""
                await MainActor.run { self.pullProgress = status }
            }
        } catch {
            await MainActor.run { self.pullProgress = "Pull interrupted: \(error.localizedDescription)" }
        }

        if let list = try? await Self.fetch(.ollama) {
            await MainActor.run { self.models[.ollama] = list }
        }
        if let sizes = try? await Self.fetchOllamaSizes() {
            await MainActor.run { self.ollamaModelSizes = sizes }
        }
    }

    /// Ollama's /api/tags includes a `size` field (bytes on disk) per
    /// installed model — read directly rather than re-deriving from `fetch`,
    /// which only extracts names.
    private static func fetchOllamaSizes() async throws -> [String: Int64] {
        let base = SettingsStore.shared.settings.ollamaBaseURL
        guard let url = URL(string: "\(base)/api/tags") else { return [:] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var sizes: [String: Int64] = [:]
        for m in json["models"] as? [[String: Any]] ?? [] {
            guard let name = m["name"] as? String else { continue }
            if let size = m["size"] as? Int64 { sizes[name] = size }
            else if let size = m["size"] as? Int { sizes[name] = Int64(size) }
        }
        return sizes
    }

    private static func fetch(_ provider: Provider) async throws -> [String] {
        var request: URLRequest
        switch provider {
        case .groq:
            guard let key = Keychain.get("groq") else { return [] }
            request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .openAI:
            guard let key = Keychain.get("openai") else { return [] }
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .cerebras:
            guard let key = Keychain.get("cerebras") else { return [] }
            request = URLRequest(url: URL(string: "https://api.cerebras.ai/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .gemini:
            guard let key = Keychain.get("gemini") else { return [] }
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=\(key)")!)
        case .ollama:
            let base = SettingsStore.shared.settings.ollamaBaseURL
            guard let url = URL(string: "\(base)/api/tags") else { return [] }
            request = URLRequest(url: url)
        }
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return parse(provider, data: data)
    }

    private static func parse(_ provider: Provider, data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var ids: [String] = []
        switch provider {
        case .gemini:
            // {"models":[{"name":"models/gemini-...","supportedGenerationMethods":[...]}]}
            for m in json["models"] as? [[String: Any]] ?? [] {
                let methods = m["supportedGenerationMethods"] as? [String] ?? []
                guard methods.contains("generateContent"),
                      let name = m["name"] as? String else { continue }
                ids.append(name.replacingOccurrences(of: "models/", with: ""))
            }
        case .ollama:
            // {"models":[{"name":"llama3.2:latest"}]}
            for m in json["models"] as? [[String: Any]] ?? [] {
                if let name = m["name"] as? String { ids.append(name) }
            }
        case .groq, .openAI, .cerebras:
            // OpenAI-style {"data":[{"id":"..."}]}
            for m in json["data"] as? [[String: Any]] ?? [] {
                if let id = m["id"] as? String { ids.append(id) }
            }
            if provider == .groq {
                // Cleanup needs chat models; drop STT/TTS/guard entries.
                ids.removeAll { id in
                    let l = id.lowercased()
                    return l.contains("whisper") || l.contains("tts") || l.contains("guard")
                }
            }
            if provider == .openAI {
                // Keep chat-capable families; the raw list is full of
                // embeddings/audio/image/moderation models.
                ids.removeAll { id in
                    let l = id.lowercased()
                    return !(l.hasPrefix("gpt") || l.hasPrefix("o1") || l.hasPrefix("o3") || l.hasPrefix("o4") || l.hasPrefix("chatgpt"))
                        || l.contains("audio") || l.contains("realtime") || l.contains("transcribe")
                        || l.contains("tts") || l.contains("image") || l.contains("search")
                }
            }
        }
        return ids.sorted()
    }
}
