using System.Text.Json;

namespace Whisper.Core.Providers;

/// Deepgram Nova-3, raw-body upload (no multipart) with query-string params
/// for model/smart_format. Mirrors
/// Sources/Whisper/Providers/STT/DeepgramTranscriber.swift.
public sealed class DeepgramSttProvider : ISttProvider
{
    private const string Model = "nova-3";

    private readonly HttpClient _http;
    private readonly string _apiKey;

    public DeepgramSttProvider(HttpClient http, string apiKey)
    {
        _http = http;
        _apiKey = apiKey;
    }

    public async Task<string> TranscribeAsync(byte[] wavBytes, CancellationToken cancellationToken)
    {
        var uri = $"https://api.deepgram.com/v1/listen?model={Model}&smart_format=true";

        using var content = new ByteArrayContent(wavBytes);
        content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("audio/wav");

        using var request = new HttpRequestMessage(HttpMethod.Post, uri) { Content = content };
        request.Headers.Add("Authorization", $"Token {_apiKey}");

        using var response = await _http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadAsStringAsync(cancellationToken);
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement
            .GetProperty("results")
            .GetProperty("channels")[0]
            .GetProperty("alternatives")[0]
            .GetProperty("transcript")
            .GetString() ?? "";
    }
}
