namespace Whisper.Core.Models;

public enum SttProviderKind { Groq, OpenAI, Deepgram, ElevenLabs }
public enum CleanupProviderKind { None, Groq, Cerebras, OpenAI, Gemini }
public enum OutputMode { PasteAtCursor, CopyOnly }

/// Windows analogue of Sources/Whisper/Store/Settings.swift AppSettings.
/// Only Groq STT/cleanup are actually wired up (see Providers/); the other
/// enum cases exist so the settings file round-trips and the UI has a slot
/// to fill in later without another migration.
public sealed class AppSettings
{
    public const string DefaultCleanupInstructions =
        "Fix punctuation, capitalization, and obvious transcription errors. " +
        "Keep the speaker's words and meaning otherwise unchanged.";

    public SttProviderKind SttProvider { get; set; } = SttProviderKind.Groq;
    public CleanupProviderKind CleanupProvider { get; set; } = CleanupProviderKind.Groq;
    public bool CleanupEnabled { get; set; } = true;
    public string CleanupInstructions { get; set; } = DefaultCleanupInstructions;
    public double CleanupTimeoutSeconds { get; set; } = 6.0;

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
