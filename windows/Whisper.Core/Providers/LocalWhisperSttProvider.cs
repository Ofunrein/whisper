using System.Diagnostics;
using System.Text;

namespace Whisper.Core.Providers;

/// On-device transcription via whisper.cpp's whisper-cli, the one STT path
/// that sends no audio anywhere. Everything else in Providers/ posts the
/// recording to a vendor endpoint; this shells out to a local binary and a
/// local GGML model instead, so it also works with no network at all.
///
/// Shelling out rather than P/Invoking libwhisper: whisper.cpp ships
/// prebuilt Windows binaries but no stable C# binding, and the process
/// boundary keeps a native crash inside inference from taking the app down
/// with it. The cost is one process spawn per utterance, which is noise next
/// to the inference itself.
///
/// AudioRecorder already produces exactly what whisper-cli wants -- 16 kHz
/// mono 16-bit PCM (Audio/AudioRecorder.TargetFormat) -- so the WAV bytes go
/// to a temp file untouched.
public sealed class LocalWhisperSttProvider : ISttProvider
{
    private readonly string _exePath;
    private readonly string _modelPath;
    private readonly string _language;

    public LocalWhisperSttProvider(string exePath, string modelPath, string language = "en")
    {
        _exePath = exePath;
        _modelPath = modelPath;
        _language = string.IsNullOrWhiteSpace(language) ? "en" : language;
    }

    public async Task<string> TranscribeAsync(byte[] wavBytes, CancellationToken cancellationToken)
    {
        if (!File.Exists(_exePath))
            throw new FileNotFoundException($"whisper-cli not found at {_exePath}. Set it in Settings.", _exePath);
        if (!File.Exists(_modelPath))
            throw new FileNotFoundException($"Whisper model not found at {_modelPath}. Set it in Settings.", _modelPath);

        var wavPath = Path.Combine(Path.GetTempPath(), $"whisper-{Guid.NewGuid():N}.wav");
        await File.WriteAllBytesAsync(wavPath, wavBytes, cancellationToken);

        try
        {
            // -np suppresses the banner and progress lines, -nt the timestamps,
            // which together leave stdout as the bare transcript.
            var psi = new ProcessStartInfo
            {
                FileName = _exePath,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            psi.ArgumentList.Add("-m");
            psi.ArgumentList.Add(_modelPath);
            psi.ArgumentList.Add("-f");
            psi.ArgumentList.Add(wavPath);
            psi.ArgumentList.Add("-l");
            psi.ArgumentList.Add(_language);
            psi.ArgumentList.Add("-np");
            psi.ArgumentList.Add("-nt");

            using var process = new Process { StartInfo = psi };
            var stdout = new StringBuilder();
            var stderr = new StringBuilder();
            process.OutputDataReceived += (_, e) => { if (e.Data != null) stdout.AppendLine(e.Data); };
            process.ErrorDataReceived += (_, e) => { if (e.Data != null) stderr.AppendLine(e.Data); };

            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            try
            {
                await process.WaitForExitAsync(cancellationToken);
            }
            catch (OperationCanceledException)
            {
                // Otherwise inference keeps running, holding the temp WAV open.
                try { process.Kill(entireProcessTree: true); } catch { /* already gone */ }
                throw;
            }

            if (process.ExitCode != 0)
                throw new InvalidOperationException($"whisper-cli exited with code {process.ExitCode}: {stderr}");

            return stdout.ToString().Trim();
        }
        finally
        {
            try { File.Delete(wavPath); } catch { /* best effort; temp dir gets cleaned eventually either way */ }
        }
    }
}
