using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Whisper.Core.Providers;

/// Reusable OpenAI-chat-completions-shaped cleanup provider for Groq,
/// Cerebras, and OpenAI -- they all expose the same
/// POST {baseUrl} with {model, messages, temperature} -> choices[0].message.content
/// shape. Mirrors Sources/Whisper/Providers/Cleanup/OpenAICompatCleanup.swift's
/// DRY approach instead of one copy-pasted class per provider.
public sealed class OpenAiCompatCleanupProvider : ICleanupProvider
{
    private readonly HttpClient _http;
    private readonly string _baseUrl;
    private readonly string _model;
    private readonly string _apiKey;
    private readonly string _providerLabel;

    public OpenAiCompatCleanupProvider(HttpClient http, string baseUrl, string model, string apiKey, string providerLabel)
    {
        _http = http;
        _baseUrl = baseUrl;
        _model = model;
        _apiKey = apiKey;
        _providerLabel = providerLabel;
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
            temperature = 0.2,
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, _baseUrl)
        {
            Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);

        try
        {
            using var response = await _http.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();

            var json = await response.Content.ReadAsStringAsync(cancellationToken);
            using var doc = JsonDocument.Parse(json);
            var cleaned = doc.RootElement
                .GetProperty("choices")[0]
                .GetProperty("message")
                .GetProperty("content")
                .GetString();
            return string.IsNullOrWhiteSpace(cleaned) ? rawTranscript : cleaned;
        }
        catch
        {
            // Cleanup is best-effort -- never block a paste on a broken/slow provider.
            return rawTranscript;
        }
    }

    /// _providerLabel is currently unused beyond documentation/future error
    /// surfacing (mac's equivalent throws ProviderError.missingKey(providerLabel)
    /// before ever making the request; this class matches Groq's existing
    /// catch-and-return-raw behavior instead, so the label has no throw site yet).
    public string ProviderLabel => _providerLabel;
}
