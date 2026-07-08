using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Whisper.Core.Providers;

/// Groq's OpenAI-compatible chat completions endpoint, used for the
/// optional cleanup pass. Matches AppSettings.DefaultGroqCleanupModel's
/// mac-side default (openai/gpt-oss-20b).
public sealed class GroqCleanupProvider : ICleanupProvider
{
    private const string Endpoint = "https://api.groq.com/openai/v1/chat/completions";
    private const string Model = "openai/gpt-oss-20b";

    private readonly HttpClient _http;
    private readonly string _apiKey;

    public GroqCleanupProvider(HttpClient http, string apiKey)
    {
        _http = http;
        _apiKey = apiKey;
    }

    public async Task<string> CleanupAsync(string rawTranscript, string instructions, CancellationToken cancellationToken)
    {
        var payload = new
        {
            model = Model,
            messages = new[]
            {
                new { role = "system", content = instructions },
                new { role = "user", content = rawTranscript },
            },
            temperature = 0.2,
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint)
        {
            Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);

        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            using var response = await _http.SendAsync(request, cts.Token);
            response.EnsureSuccessStatusCode();

            var json = await response.Content.ReadAsStringAsync(cts.Token);
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
}
