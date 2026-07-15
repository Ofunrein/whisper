using System.Text;
using System.Text.Json;

namespace Whisper.Core.Providers;

/// Google Gemini generateContent cleanup, dedicated (not OpenAI-chat-shaped).
/// Mirrors Sources/Whisper/Providers/Cleanup/GeminiCleanup.swift: auth via
/// "x-goog-api-key" header, payload shape is system_instruction/contents
/// rather than messages, response is candidates[0].content.parts[0].text.
public sealed class GeminiCleanupProvider : ICleanupProvider
{
    private readonly HttpClient _http;
    private readonly string _apiKey;
    private readonly string _model;

    public GeminiCleanupProvider(HttpClient http, string apiKey, string model)
    {
        _http = http;
        _apiKey = apiKey;
        _model = model;
    }

    public async Task<string> CleanupAsync(string rawTranscript, string instructions, CancellationToken cancellationToken)
    {
        var payload = new
        {
            system_instruction = new { parts = new[] { new { text = instructions } } },
            contents = new[] { new { parts = new[] { new { text = rawTranscript } } } },
        };

        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:generateContent";
        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json"),
        };
        request.Headers.Add("x-goog-api-key", _apiKey);

        try
        {
            using var response = await _http.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();

            var json = await response.Content.ReadAsStringAsync(cancellationToken);
            using var doc = JsonDocument.Parse(json);
            var cleaned = doc.RootElement
                .GetProperty("candidates")[0]
                .GetProperty("content")
                .GetProperty("parts")[0]
                .GetProperty("text")
                .GetString();
            return string.IsNullOrWhiteSpace(cleaned) ? rawTranscript : cleaned.Trim();
        }
        catch
        {
            // Cleanup is best-effort -- never block a paste on a broken/slow provider.
            return rawTranscript;
        }
    }
}
