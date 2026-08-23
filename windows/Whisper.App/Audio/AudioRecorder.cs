using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace Whisper.App.Audio;

/// WASAPI mic capture, mirroring Sources/Whisper/Audio/AudioRecorder.swift's
/// pipeline: capture -> resample to 16kHz mono 16-bit -> WAV bytes.
///
/// System audio is simpler here than on macOS: WasapiLoopbackCapture reads
/// straight off the default render device, no process-tap/permission dance
/// needed. Still off by default per Settings.RecordSystemAudio.
///
/// No Windows machine available here, so this is not RUN-tested locally; it is
/// however compile-checked on macOS via windows/tools/MicFallbackCheck, which
/// builds this file alone against NAudio for net8.0-windows
/// (EnableWindowsTargeting=true) and so doesn't need the WinUI3/WindowsAppSDK
/// bits the rest of Whisper.App pulls in. That same project is RUN on real
/// Windows in CI to check the stale-endpoint fallback below; the rest of the
/// end-to-end coverage comes from the release workflow's MSI install + launch
/// steps.
public sealed class AudioRecorder : IDisposable
{
    private static readonly WaveFormat TargetFormat = new(16_000, 16, 1);
    private const float SilenceGate = 0.03f;

    private WasapiCapture? _mic;
    private WasapiLoopbackCapture? _loopback;
    private MemoryStream? _micBuffer;
    private MemoryStream? _loopbackBuffer;
    private float _micPeak;
    private float _loopbackPeak;
    private readonly object _lock = new();

    public bool RecordSystemAudio { get; set; }

    public void Start(string? preferredDeviceId = null)
    {
        _micPeak = 0;
        _loopbackPeak = 0;
        _micBuffer = new MemoryStream();
        _loopbackBuffer = RecordSystemAudio ? new MemoryStream() : null;

        var enumerator = new MMDeviceEnumerator();
        var micDevice = ResolveMicDevice(enumerator, preferredDeviceId);

        _mic = new WasapiCapture(micDevice);
        _mic.DataAvailable += (_, e) => OnData(e, isMic: true);
        _mic.StartRecording();

        if (RecordSystemAudio)
        {
            _loopback = new WasapiLoopbackCapture();
            _loopback.DataAvailable += (_, e) => OnData(e, isMic: false);
            _loopback.StartRecording();
        }
    }

    /// Resolve the pinned capture device, falling back to the system default.
    ///
    /// `PreferredInputDeviceId` is a persisted MMDevice endpoint ID. It goes
    /// stale whenever that mic is unplugged, and a USB mic (FIFINE, Yeti) can
    /// also come back on a different endpoint ID after a replug or a port
    /// change. `GetDevice` throws a COMException for an unknown ID, and it can
    /// also hand back an endpoint that is present but not active (unplugged
    /// but still cached), which then fails inside WasapiCapture instead.
    ///
    /// Start() is called straight from the record-hotkey handler with no
    /// try/catch around it, so either throw was an unhandled exception on the
    /// UI thread -- i.e. pressing the hotkey killed the app. Degrading to the
    /// default mic is strictly better than dying.
    ///
    /// Split from `TryGetActiveDevice` so the stale-ID decision is checkable on
    /// a machine with no capture endpoint at all (GitHub's Windows runners have
    /// none), which the default-endpoint call here can't be.
    internal static MMDevice ResolveMicDevice(MMDeviceEnumerator enumerator, string? preferredDeviceId)
        => TryGetActiveDevice(enumerator, preferredDeviceId)
           ?? enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Communications);

    /// The pinned device if it's present and active, else null meaning "fall
    /// back to the system default". Never throws: an unknown/stale ID is an
    /// expected state, not an error.
    internal static MMDevice? TryGetActiveDevice(MMDeviceEnumerator enumerator, string? preferredDeviceId)
    {
        if (preferredDeviceId == null) return null;

        try
        {
            var device = enumerator.GetDevice(preferredDeviceId);
            if (device.State == DeviceState.Active) return device;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine(
                $"AudioRecorder: preferred input '{preferredDeviceId}' unavailable ({ex.Message}), using default");
        }

        return null;
    }

    private void OnData(WaveInEventArgs e, bool isMic)
    {
        lock (_lock)
        {
            var target = isMic ? _micBuffer : _loopbackBuffer;
            target?.Write(e.Buffer, 0, e.BytesRecorded);

            var peak = ComputePeak(e.Buffer, e.BytesRecorded);
            if (isMic) _micPeak = Math.Max(_micPeak, peak);
            else _loopbackPeak = Math.Max(_loopbackPeak, peak);
        }
    }

    private static float ComputePeak(byte[] buffer, int bytesRecorded)
    {
        float max = 0;
        for (var i = 0; i + 1 < bytesRecorded; i += 2)
        {
            var sample = Math.Abs((short)(buffer[i] | (buffer[i + 1] << 8))) / 32768f;
            if (sample > max) max = sample;
        }
        return max;
    }

    /// Stops capture, resamples both streams to TargetFormat, mixes them,
    /// and returns WAV bytes -- or null if both streams were effectively
    /// silent (mirrors the mac app's discard-near-silent-takes behavior).
    public byte[]? Stop()
    {
        _mic?.StopRecording();
        _loopback?.StopRecording();

        byte[] micPcm, loopbackPcm;
        float micPeak, loopbackPeak;
        lock (_lock)
        {
            micPcm = ResampleToTarget(_micBuffer, _mic?.WaveFormat);
            loopbackPcm = _loopbackBuffer != null
                ? ResampleToTarget(_loopbackBuffer, _loopback?.WaveFormat)
                : Array.Empty<byte>();
            micPeak = _micPeak;
            loopbackPeak = _loopbackPeak;
        }

        _mic?.Dispose();
        _loopback?.Dispose();
        _mic = null;
        _loopback = null;

        if (micPeak < SilenceGate && loopbackPeak < SilenceGate) return null;

        var mixed = loopbackPcm.Length > 0 ? MixPcm(micPcm, loopbackPcm) : micPcm;
        return EncodeWav(mixed);
    }

    private static byte[] ResampleToTarget(MemoryStream? raw, WaveFormat? sourceFormat)
    {
        if (raw == null || sourceFormat == null || raw.Length == 0) return Array.Empty<byte>();

        raw.Position = 0;
        using var sourceStream = new RawSourceWaveStream(raw, sourceFormat);
        using var resampler = new MediaFoundationResampler(sourceStream, TargetFormat) { ResamplerQuality = 60 };

        using var output = new MemoryStream();
        var buffer = new byte[TargetFormat.AverageBytesPerSecond];
        int read;
        while ((read = resampler.Read(buffer, 0, buffer.Length)) > 0)
            output.Write(buffer, 0, read);

        return output.ToArray();
    }

    private static byte[] MixPcm(byte[] a, byte[] b)
    {
        var length = Math.Max(a.Length, b.Length);
        var mixed = new byte[length];
        for (var i = 0; i + 1 < length; i += 2)
        {
            var sa = i + 1 < a.Length ? (short)(a[i] | (a[i + 1] << 8)) : (short)0;
            var sb = i + 1 < b.Length ? (short)(b[i] | (b[i + 1] << 8)) : (short)0;
            var sum = Math.Clamp(sa + sb, short.MinValue, short.MaxValue);
            mixed[i] = (byte)(sum & 0xFF);
            mixed[i + 1] = (byte)((sum >> 8) & 0xFF);
        }
        return mixed;
    }

    /// Manual 44-byte canonical PCM WAV header -- avoids depending on
    /// NAudio WaveFileWriter's stream-ownership semantics on Dispose.
    private static byte[] EncodeWav(byte[] pcm)
    {
        const int headerSize = 44;
        var result = new byte[headerSize + pcm.Length];
        using (var stream = new MemoryStream(result))
        using (var w = new BinaryWriter(stream))
        {
            w.Write("RIFF"u8.ToArray());
            w.Write(36 + pcm.Length);
            w.Write("WAVE"u8.ToArray());
            w.Write("fmt "u8.ToArray());
            w.Write(16);
            w.Write((short)1); // PCM
            w.Write((short)TargetFormat.Channels);
            w.Write(TargetFormat.SampleRate);
            w.Write(TargetFormat.AverageBytesPerSecond);
            w.Write((short)TargetFormat.BlockAlign);
            w.Write((short)TargetFormat.BitsPerSample);
            w.Write("data"u8.ToArray());
            w.Write(pcm.Length);
            w.Write(pcm);
        }
        return result;
    }

    public void Dispose()
    {
        _mic?.Dispose();
        _loopback?.Dispose();
    }
}
