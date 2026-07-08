namespace Whisper.Core.Models;

/// Mirrors Sources/Whisper/Store/Settings.swift VocabularyEntry.
/// To == null (or empty) means "known term" (spelling hint only);
/// non-empty means a literal misheard-phrase -> correct-spelling pair.
public sealed class VocabularyEntry
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string From { get; set; } = "";
    public string? To { get; set; }
}
