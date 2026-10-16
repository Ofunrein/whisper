namespace Whisper.Core.Models;

/// LocalWhisper runs whisper.cpp's whisper-cli against a local GGML model
/// (Providers/LocalWhisperSttProvider). It needs no API key and sends no
/// audio off the machine; the binary and model are pointed at by
/// LocalWhisperExePath/LocalWhisperModelPath rather than bundled, since the
/// models are hundreds of MB and which one to use is a speed/accuracy
/// tradeoff only the user can make.
public enum SttProviderKind { Groq, OpenAI, Deepgram, ElevenLabs, LocalWhisper }

public enum CleanupProviderKind { None, Groq, Cerebras, OpenAI, Gemini, Ollama, Anthropic }
public enum OutputMode { PasteAtCursor, CopyOnly }

/// Windows analogue of Sources/Whisper/Store/Settings.swift AppSettings.
/// All STT providers except LocalWhisper (Groq, OpenAI, Deepgram,
/// ElevenLabs) and all cleanup providers (Groq, Cerebras, OpenAI, Gemini,
/// Ollama, Anthropic) are wired up -- see Providers/ and ProviderFactory.
public sealed class AppSettings
{
    public const string DefaultCleanupInstructions =
        "Fix punctuation, capitalization, and obvious transcription errors. " +
        "Keep the speaker's words and meaning otherwise unchanged.";

    public const string DefaultGroqCleanupModel = "openai/gpt-oss-20b";
    public const string DefaultCerebrasModel = "gpt-oss-120b";
    public const string DefaultOpenAICleanupModel = "gpt-4o-mini";
    public const string DefaultGeminiModel = "gemini-3.5-flash";
    public const string DefaultOllamaModel = "llama3.2";
    public const string DefaultOllamaBaseUrl = "http://localhost:11434";
    public const string DefaultAnthropicModel = "claude-haiku-4-5-20251001";

    private static string LocalWhisperRoot => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Whisper", "whisper.cpp");

    public static string DefaultLocalWhisperExePath => Path.Combine(LocalWhisperRoot, "Release", "whisper-cli.exe");
    public static string DefaultLocalWhisperModelPath => Path.Combine(LocalWhisperRoot, "ggml-base.en.bin");

    public SttProviderKind SttProvider { get; set; } = SttProviderKind.Groq;
    public CleanupProviderKind CleanupProvider { get; set; } = CleanupProviderKind.Groq;
    public bool CleanupEnabled { get; set; } = true;
    public string CleanupInstructions { get; set; } = DefaultCleanupInstructions;
    public double CleanupTimeoutSeconds { get; set; } = 6.0;

    public string GroqCleanupModel { get; set; } = DefaultGroqCleanupModel;
    public string CerebrasModel { get; set; } = DefaultCerebrasModel;
    public string OpenAICleanupModel { get; set; } = DefaultOpenAICleanupModel;
    public string GeminiModel { get; set; } = DefaultGeminiModel;
    public string OllamaModel { get; set; } = DefaultOllamaModel;
    public string OllamaBaseUrl { get; set; } = DefaultOllamaBaseUrl;
    public string AnthropicModel { get; set; } = DefaultAnthropicModel;

    /// Where the whisper.cpp release was unpacked and which GGML model to run.
    /// Defaults match the layout the README's setup step produces; both are
    /// editable in Settings because neither ships with the app.
    public string LocalWhisperExePath { get; set; } = DefaultLocalWhisperExePath;
    public string LocalWhisperModelPath { get; set; } = DefaultLocalWhisperModelPath;
    public string LocalWhisperLanguage { get; set; } = "en";

    public OutputMode OutputMode { get; set; } = OutputMode.PasteAtCursor;
    public bool KeepOnClipboardAfterPaste { get; set; } = true;
    public bool SaveAudio { get; set; } = false;
    public bool SoundEffectsEnabled { get; set; } = true;

    /// Off by default. Uses WASAPI loopback on the default render device --
    /// no special OS permission needed on Windows (unlike the macOS Core
    /// Audio process-tap path), just mixed in alongside the mic.
    public bool RecordSystemAudio { get; set; } = false;

    public List<HotkeyBinding> Bindings { get; set; } = new() { HotkeyBinding.DefaultRightControl() };
    public List<VocabularyEntry> Vocabulary { get; set; } = new();

    public string? PreferredInputDeviceId { get; set; }
}
