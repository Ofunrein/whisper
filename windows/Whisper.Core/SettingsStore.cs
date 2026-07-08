using System.Text.Json;
using Whisper.Core.Models;

namespace Whisper.Core;

/// JSON-file analogue of Sources/Whisper/Store/Settings.swift SettingsStore.
/// Swift's version autosaves via `didSet` on the whole struct; C# has no
/// equivalent for in-place mutation of nested collections, so callers must
/// call Save() after editing Settings (the WinUI code-behind does this in
/// every control's changed handler -- same "no explicit save button" rule
/// as the mac app, just one line more explicit per call site).
public sealed class SettingsStore
{
    private readonly string _path;
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new System.Text.Json.Serialization.JsonStringEnumConverter() },
    };

    public AppSettings Settings { get; private set; } = new();

    public SettingsStore(string? path = null)
    {
        _path = path ?? DefaultPath();
        Load();
    }

    private static string DefaultPath()
    {
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Whisper");
        Directory.CreateDirectory(dir);
        return Path.Combine(dir, "settings.json");
    }

    private void Load()
    {
        if (!File.Exists(_path)) return;
        try
        {
            var json = File.ReadAllText(_path);
            var loaded = JsonSerializer.Deserialize<AppSettings>(json, JsonOptions);
            if (loaded != null) Settings = loaded;
        }
        catch
        {
            // Corrupt/unreadable settings file -- keep defaults rather than crash on launch.
        }
    }

    public void Save()
    {
        var json = JsonSerializer.Serialize(Settings, JsonOptions);
        File.WriteAllText(_path, json);
    }
}
