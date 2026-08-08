using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;

namespace Whisper.Core;

/// <summary>
/// Checks GitHub Releases for a newer tagged version than the running app.
/// Mirrors the mac app's UpdateChecker: pure metadata lookup (including the
/// release's asset list, so <see cref="Updater"/> can pick out the .msi to
/// silently install) plus a fallback html_url for the "open the release page"
/// manual path. Historically this was check-only with no assets parsed --
/// that reasoning (no code-signed update channel) is the same one the mac
/// app outgrew: silently replacing an unsigned app with another copy of the
/// same unsigned app from the same publisher isn't a new trust boundary.
/// </summary>
public static class UpdateChecker
{
    public const string Repo = "Ofunrein/whisper";

    public sealed record Asset(string Name, string DownloadUrl);

    public sealed record Release(string TagName, string HtmlUrl, IReadOnlyList<Asset> Assets);

    public static async Task<Release?> CheckForUpdateAsync(string currentVersion, CancellationToken ct = default)
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Whisper-App");

        try
        {
            using var response = await client.GetAsync($"https://api.github.com/repos/{Repo}/releases/latest", ct);
            if (!response.IsSuccessStatusCode) return null;

            using var stream = await response.Content.ReadAsStreamAsync(ct);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
            var tagName = doc.RootElement.GetProperty("tag_name").GetString();
            var htmlUrl = doc.RootElement.GetProperty("html_url").GetString();
            if (string.IsNullOrEmpty(tagName) || string.IsNullOrEmpty(htmlUrl)) return null;

            var assets = new List<Asset>();
            if (doc.RootElement.TryGetProperty("assets", out var assetsEl) && assetsEl.ValueKind == JsonValueKind.Array)
            {
                foreach (var assetEl in assetsEl.EnumerateArray())
                {
                    var name = assetEl.TryGetProperty("name", out var nameEl) ? nameEl.GetString() : null;
                    var url = assetEl.TryGetProperty("browser_download_url", out var urlEl) ? urlEl.GetString() : null;
                    if (!string.IsNullOrEmpty(name) && !string.IsNullOrEmpty(url))
                        assets.Add(new Asset(name, url));
                }
            }

            var latest = tagName.StartsWith('v') ? tagName[1..] : tagName;
            return IsNewer(latest, currentVersion) ? new Release(tagName, htmlUrl, assets) : null;
        }
        catch
        {
            return null;
        }
    }

    private static bool IsNewer(string a, string b)
    {
        var av = ParseVersion(a);
        var bv = ParseVersion(b);
        for (var i = 0; i < Math.Max(av.Length, bv.Length); i++)
        {
            var x = i < av.Length ? av[i] : 0;
            var y = i < bv.Length ? bv[i] : 0;
            if (x != y) return x > y;
        }
        return false;
    }

    private static int[] ParseVersion(string v) =>
        v.Split('.').Select(p => int.TryParse(p, out var n) ? n : 0).ToArray();
}
