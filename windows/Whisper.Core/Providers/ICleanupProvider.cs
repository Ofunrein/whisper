namespace Whisper.Core.Providers;

public interface ICleanupProvider
{
    /// Returns the cleaned-up transcript, or the original text unchanged if
    /// cleanup fails/times out -- mirrors the mac app's "never block a paste
    /// on a broken cleanup provider" behavior.
    Task<string> CleanupAsync(string rawTranscript, string instructions, CancellationToken cancellationToken);
}
