using System.Net.Http.Headers;
using System.Text.Json;

namespace Whisper.Core.Providers;

/// ElevenLabs Speech-to-Text (Scribe v2). Mirrors
/// Sources/Whisper/Providers/STT/ElevenLabsTranscriber.swift: multipart
/// upload with an "xi-api-key" header (not Bearer auth, unlike the other
/// providers here).
public sealed class ElevenLabsSttProvider : ISttProvider
{
    private const string Endpoint = "https://api.elevenlabs.io/v1/speech-to-text";
    private const string Model = "scribe_v2";

    private readonly HttpClient _http;
    private readonly string _apiKey;

    public ElevenLabsSttProvider(HttpClient http, string apiKey)
    {
        _http = http;
        _apiKey = apiKey;
    }

    public async Task<string> TranscribeAsync(byte[] wavBytes, CancellationToken cancellationToken)
    {
        using var form = new MultipartFormDataContent();
        var audioContent = new ByteArrayContent(wavBytes);
        audioContent.Headers.ContentType = new MediaTypeHeaderValue("audio/wav");
        form.Add(audioContent, "file", "audio.wav");
        form.Add(new StringContent(Model), "model_id");

        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint) { Content = form };
        request.Headers.Add("xi-api-key", _apiKey);

        using var response = await _http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadAsStringAsync(cancellationToken);
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("text").GetString() ?? "";
    }
}
