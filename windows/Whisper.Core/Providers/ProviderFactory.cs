using Whisper.Core.Models;

namespace Whisper.Core.Providers;

/// Windows analogue of Sources/Whisper/Providers/ProviderFactory.swift --
/// central place that maps AppSettings' provider-kind enums to concrete
/// ISttProvider/ICleanupProvider instances, given the caller's per-provider
/// API keys. Callers (App.xaml.cs) look up keys via CredentialStore and
/// pass them in here rather than this class reaching into
/// Whisper.App.Security itself, since Whisper.Core has no Windows-only
/// dependencies and must stay buildable on any OS.
public static class ProviderFactory
{
    /// apiKey may be null/empty for providers that don't need one
    /// (e.g. Ollama) or when the user hasn't configured a key yet --
    /// callers are expected to check SttProviderKind/CleanupProviderKind's
    /// "needs a key" expectations before calling if they want to
    /// short-circuit with a friendlier error than an HTTP 401.
    public static ISttProvider CreateSttProvider(SttProviderKind kind, HttpClient http, string? apiKey, AppSettings settings)
    {
        var key = apiKey ?? "";
        return kind switch
        {
            SttProviderKind.Groq => new GroqSttProvider(http, key),
            SttProviderKind.OpenAI => new OpenAISttProvider(http, key),
            SttProviderKind.Deepgram => new DeepgramSttProvider(http, key),
            SttProviderKind.ElevenLabs => new ElevenLabsSttProvider(http, key),
            SttProviderKind.LocalWhisper => new LocalWhisperSttProvider(
                settings.LocalWhisperExePath, settings.LocalWhisperModelPath, settings.LocalWhisperLanguage),
            _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "Unsupported STT provider"),
        };
    }

    public static ICleanupProvider? CreateCleanupProvider(CleanupProviderKind kind, HttpClient http, AppSettings settings, Func<string, string?> getApiKey)
    {
        switch (kind)
        {
            case CleanupProviderKind.None:
                return null;
            case CleanupProviderKind.Groq:
                return new OpenAiCompatCleanupProvider(
                    http,
                    "https://api.groq.com/openai/v1/chat/completions",
                    settings.GroqCleanupModel,
                    getApiKey("groq") ?? "",
                    "Groq");
            case CleanupProviderKind.Cerebras:
                return new OpenAiCompatCleanupProvider(
                    http,
                    "https://api.cerebras.ai/v1/chat/completions",
                    settings.CerebrasModel,
                    getApiKey("cerebras") ?? "",
                    "Cerebras");
            case CleanupProviderKind.OpenAI:
                return new OpenAiCompatCleanupProvider(
                    http,
                    "https://api.openai.com/v1/chat/completions",
                    settings.OpenAICleanupModel,
                    getApiKey("openai") ?? "",
                    "OpenAI");
            case CleanupProviderKind.Gemini:
                return new GeminiCleanupProvider(http, getApiKey("gemini") ?? "", settings.GeminiModel);
            case CleanupProviderKind.Ollama:
                return new OllamaCleanupProvider(http, settings.OllamaBaseUrl, settings.OllamaModel);
            case CleanupProviderKind.Anthropic:
                return new AnthropicCleanupProvider(http, getApiKey("anthropic") ?? "", settings.AnthropicModel);
            default:
                throw new ArgumentOutOfRangeException(nameof(kind), kind, "Unsupported cleanup provider");
        }
    }

    /// Credential-store account name each provider's key is stored under
    /// (see Whisper.App.Security.CredentialStore, "Whisper:{account}").
    public static string? KeyAccountFor(SttProviderKind kind) => kind switch
    {
        SttProviderKind.LocalWhisper => null, // on-device, no key
        SttProviderKind.Groq => "groq",
        SttProviderKind.OpenAI => "openai",
        SttProviderKind.Deepgram => "deepgram",
        SttProviderKind.ElevenLabs => "elevenlabs",
        _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "Unsupported STT provider"),
    };

    public static string? KeyAccountFor(CleanupProviderKind kind) => kind switch
    {
        CleanupProviderKind.None => null,
        CleanupProviderKind.Groq => "groq",
        CleanupProviderKind.Cerebras => "cerebras",
        CleanupProviderKind.OpenAI => "openai",
        CleanupProviderKind.Gemini => "gemini",
        CleanupProviderKind.Ollama => null, // local, no key
        CleanupProviderKind.Anthropic => "anthropic",
        _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "Unsupported cleanup provider"),
    };
}
