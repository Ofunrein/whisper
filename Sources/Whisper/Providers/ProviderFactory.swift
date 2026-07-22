import Foundation

enum ProviderFactory {
    static func transcriber(for settings: AppSettings) -> TranscriptionProvider {
        switch settings.sttProvider {
        case .groq:
            return GroqTranscriber()
        case .elevenLabs:
            return ElevenLabsTranscriber()
        case .deepgram:
            return DeepgramTranscriber(keyterms: VocabularyEngine.deepgramKeyterms(for: settings.vocabulary))
        case .openAI:
            return OpenAITranscriber()
        case .localWhisper:
            return LocalWhisperTranscriber(modelPath: settings.localWhisperModelPath)
        }
    }

    /// Fast, accuracy-preserving backup order. Only providers with a configured
    /// key are considered; the selected provider always runs first. Local is not
    /// an automatic fallback because spawning a model can make a cloud timeout worse.
    static func fallbackTranscribers(for settings: AppSettings) -> [TranscriptionProvider] {
        let order: [STTProviderKind] = [.deepgram, .groq, .elevenLabs, .openAI]
        return order
            .filter { $0 != settings.sttProvider && hasTranscriptionKey(for: $0) }
            .map { kind in
                var backup = settings
                backup.sttProvider = kind
                return transcriber(for: backup)
            }
    }

    private static func hasTranscriptionKey(for kind: STTProviderKind) -> Bool {
        let account: String?
        switch kind {
        case .groq: account = Keychain.groqKey
        case .elevenLabs: account = Keychain.elevenLabsKey
        case .deepgram: account = Keychain.deepgramKey
        case .openAI: account = Keychain.openAIKey
        case .localWhisper: return false
        }
        return account.flatMap(Keychain.get).map { !$0.isEmpty } ?? false
    }

    static func cleaner(for settings: AppSettings) -> CleanupProvider {
        switch settings.cleanupProvider {
        case .groq:
            return OpenAICompatCleanup(
                kind: .groq,
                baseURL: "https://api.groq.com/openai/v1/chat/completions",
                model: settings.groqCleanupModel,
                keychainAccount: Keychain.groqKey,
                providerLabel: "Groq"
            )
        case .cerebras:
            return OpenAICompatCleanup(
                kind: .cerebras,
                baseURL: "https://api.cerebras.ai/v1/chat/completions",
                model: settings.cerebrasModel,
                keychainAccount: Keychain.cerebrasKey,
                providerLabel: "Cerebras"
            )
        case .openAI:
            return OpenAICompatCleanup(
                kind: .openAI,
                baseURL: "https://api.openai.com/v1/chat/completions",
                model: settings.openAICleanupModel,
                keychainAccount: Keychain.openAIKey,
                providerLabel: "OpenAI"
            )
        case .gemini:
            return GeminiCleanup(model: settings.geminiModel)
        case .anthropic:
            return AnthropicCleanup(model: settings.anthropicModel)
        case .ollama:
            return OllamaCleanup(baseURL: settings.ollamaBaseURL, model: settings.ollamaModel)
        }
    }
}
