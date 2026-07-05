import Foundation

enum ProviderFactory {
    static func transcriber(for settings: AppSettings) -> TranscriptionProvider {
        switch settings.sttProvider {
        case .groq:
            return GroqTranscriber()
        case .elevenLabs:
            return ElevenLabsTranscriber()
        case .deepgram:
            return DeepgramTranscriber()
        case .openAI:
            return OpenAITranscriber()
        case .localWhisper:
            return LocalWhisperTranscriber()
        }
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
        case .ollama:
            return OllamaCleanup(baseURL: settings.ollamaBaseURL, model: settings.ollamaModel)
        }
    }
}
