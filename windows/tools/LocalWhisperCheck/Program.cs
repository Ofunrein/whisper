using Whisper.Core;
using Whisper.Core.Models;
using Whisper.Core.Providers;

// Checks that LocalWhisperSttProvider actually transcribes on this machine.
//
// The provider shells out to whisper.cpp's whisper-cli, so the things that can
// break it are all outside the C#: a missing binary, a missing model, a flag
// the CLI stopped accepting, or output that isn't the bare transcript. None of
// that is visible to a compile, and none of it is worth a mock -- the whole
// point of this provider is the real subprocess.
//
// Usage: dotnet run --project tools/LocalWhisperCheck [path-to-16khz-mono.wav]
// With no argument it synthesises silence, which only proves the plumbing runs.
// Pass a real recording to check the transcript itself.

// Reads the app's own settings.json rather than fresh defaults, so this also
// answers "is the installed app actually configured to run locally?" -- a
// settings file that fails to parse silently falls back to the cloud defaults,
// which is invisible until a recording gets uploaded.
var settings = new SettingsStore().Settings;
Console.WriteLine($"settings: SttProvider={settings.SttProvider} CleanupEnabled={settings.CleanupEnabled} CleanupProvider={settings.CleanupProvider}");

var exe = settings.LocalWhisperExePath;
var model = settings.LocalWhisperModelPath;

if (!File.Exists(exe) || !File.Exists(model))
{
    Console.WriteLine($"SKIP  whisper.cpp not installed (looked for {exe} and {model})");
    return 0;
}

byte[] wav;
if (args.Length > 0)
{
    wav = File.ReadAllBytes(args[0]);
    Console.WriteLine($"using {args[0]} ({wav.Length} bytes)");
}
else
{
    wav = SilentWav(seconds: 1);
    Console.WriteLine("using 1s of generated silence (plumbing check only)");
}

var provider = new LocalWhisperSttProvider(exe, model, settings.LocalWhisperLanguage);

try
{
    using var cts = new CancellationTokenSource(TimeSpan.FromMinutes(2));
    var started = DateTime.UtcNow;
    var text = await provider.TranscribeAsync(wav, cts.Token);
    var elapsed = DateTime.UtcNow - started;

    Console.WriteLine($"PASS  transcribed in {elapsed.TotalSeconds:F1}s");
    Console.WriteLine($"      \"{text}\"");
    return 0;
}
catch (Exception ex)
{
    Console.WriteLine($"::error::FAIL  {ex.Message}");
    return 1;
}

// 16 kHz mono 16-bit PCM, matching AudioRecorder's output format.
static byte[] SilentWav(int seconds)
{
    const int sampleRate = 16_000;
    var dataBytes = sampleRate * 2 * seconds;

    using var ms = new MemoryStream();
    using var w = new BinaryWriter(ms);
    w.Write("RIFF"u8.ToArray());
    w.Write(36 + dataBytes);
    w.Write("WAVE"u8.ToArray());
    w.Write("fmt "u8.ToArray());
    w.Write(16);
    w.Write((short)1);
    w.Write((short)1);
    w.Write(sampleRate);
    w.Write(sampleRate * 2);
    w.Write((short)2);
    w.Write((short)16);
    w.Write("data"u8.ToArray());
    w.Write(dataBytes);
    w.Write(new byte[dataBytes]);
    w.Flush();
    return ms.ToArray();
}
