using System.Net.Http.Headers;
using System.Text.Json;

namespace Whisper.Core.Providers;

/// OpenAI's Whisper transcription endpoint. Mirrors
/// Sources/Whisper/Providers/STT/OpenAITranscriber.swift.
public sealed class OpenAISttProvider : ISttProvider
{
    private const string Endpoint = "https://api.openai.com/v1/audio/transcriptions";
    private const string Model = "whisper-1";

    private readonly HttpClient _http;
    private readonly string _apiKey;

    public OpenAISttProvider(HttpClient http, string apiKey)
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
        form.Add(new StringContent(Model), "model");

        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint) { Content = form };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);

        using var response = await _http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadAsStringAsync(cancellationToken);
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("text").GetString() ?? "";
    }
}
