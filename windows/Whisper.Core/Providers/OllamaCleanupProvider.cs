using System.Text;
using System.Text.Json;

namespace Whisper.Core.Providers;

/// Local Ollama chat cleanup -- no API key, hits a user-configured base URL
/// (default http://localhost:11434). Mirrors
/// Sources/Whisper/Providers/Cleanup/OllamaCleanup.swift.
public sealed class OllamaCleanupProvider : ICleanupProvider
{
    private readonly HttpClient _http;
    private readonly string _baseUrl;
    private readonly string _model;

    public OllamaCleanupProvider(HttpClient http, string baseUrl, string model)
    {
        _http = http;
        _baseUrl = baseUrl;
        _model = model;
    }

    public async Task<string> CleanupAsync(string rawTranscript, string instructions, CancellationToken cancellationToken)
    {
        var payload = new
        {
            model = _model,
            messages = new[]
            {
                new { role = "system", content = instructions },
                new { role = "user", content = rawTranscript },
            },
            stream = false,
        };

        try
        {
            var url = $"{_baseUrl.TrimEnd('/')}/api/chat";
            using var request = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json"),
            };

            using var response = await _http.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();

            var json = await response.Content.ReadAsStringAsync(cancellationToken);
            using var doc = JsonDocument.Parse(json);
            var cleaned = doc.RootElement
                .GetProperty("message")
                .GetProperty("content")
                .GetString();
            return string.IsNullOrWhiteSpace(cleaned) ? rawTranscript : cleaned.Trim();
        }
        catch
        {
            // Cleanup is best-effort -- never block a paste on a broken/slow/unreachable
            // local Ollama instance.
            return rawTranscript;
        }
    }
}
