namespace Whisper.Core.Providers;

public interface ISttProvider
{
    /// wavBytes is 16-bit mono PCM WAV, matching Audio/AudioRecorder's output.
    Task<string> TranscribeAsync(byte[] wavBytes, CancellationToken cancellationToken);
}
