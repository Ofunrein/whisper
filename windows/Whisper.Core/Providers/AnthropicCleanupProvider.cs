using System.Text;
using System.Text.Json;

namespace Whisper.Core.Providers;

/// Anthropic Messages API cleanup. Windows-side counterpart to the mac
/// app's AnthropicCleanup.swift (added independently, concurrently, by a
/// separate agent working the Sources/Whisper/ tree -- same shape, ported
/// without waiting on that file to land): POST /v1/messages with
/// "x-api-key" + "anthropic-version" headers (no Bearer auth), response
/// text at content[0].text rather than choices[0].message.content.
public sealed class AnthropicCleanupProvider : ICleanupProvider
{
    private const string Endpoint = "https://api.anthropic.com/v1/messages";
    private const string AnthropicVersion = "2023-06-01";
    private const int MaxTokens = 4096;

    private readonly HttpClient _http;
    private readonly string _apiKey;
    private readonly string _model;

    public AnthropicCleanupProvider(HttpClient http, string apiKey, string model = "claude-haiku-4-5-20251001")
    {
        _http = http;
        _apiKey = apiKey;
        _model = model;
    }

    public async Task<string> CleanupAsync(string rawTranscript, string instructions, CancellationToken cancellationToken)
    {
        var payload = new
        {
            model = _model,
            max_tokens = MaxTokens,
            system = instructions,
            messages = new[]
            {
                new { role = "user", content = rawTranscript },
            },
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint)
        {
            Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json"),
        };
        request.Headers.Add("x-api-key", _apiKey);
        request.Headers.Add("anthropic-version", AnthropicVersion);

        try
        {
            using var response = await _http.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();

            var json = await response.Content.ReadAsStringAsync(cancellationToken);
            using var doc = JsonDocument.Parse(json);
            var cleaned = doc.RootElement
                .GetProperty("content")[0]
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
