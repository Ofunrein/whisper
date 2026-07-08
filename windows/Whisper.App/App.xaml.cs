using Microsoft.UI.Xaml;
using Whisper.App.Audio;
using Whisper.App.Hotkeys;
using Whisper.App.Output;
using Whisper.App.Security;
using Whisper.App.Views;
using Whisper.Core;
using Whisper.Core.Models;
using Whisper.Core.Providers;

namespace Whisper.App;

/// Entry point: wires SettingsStore -> HotkeyManager -> AudioRecorder ->
/// STT/cleanup providers -> PasteService, plus the tray icon. No main
/// window is shown at launch (tray-only app, like the mac menu-bar app);
/// SettingsWindow opens on demand from the tray menu.
public partial class App : Application
{
    private readonly SettingsStore _settings = new();
    private readonly HotkeyManager _hotkeys = new();
    private readonly AudioRecorder _recorder = new();
    private readonly HttpClient _http = new();
    private readonly TrayIcon _tray = new();
    private SettingsWindow? _settingsWindow;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _hotkeys.Binding = _settings.Settings.Bindings.Count > 0
            ? _settings.Settings.Bindings[0]
            : HotkeyBinding.DefaultRightControl();
        _hotkeys.RecordingStarted += OnRecordingStarted;
        _hotkeys.RecordingStopped += OnRecordingStopped;
        _hotkeys.Start();

        _tray.SettingsRequested += ShowSettings;
        _tray.QuitRequested += () => Environment.Exit(0);
        _tray.CheckForUpdatesRequested += () => _ = CheckForUpdatesAsync(silent: false);
        _tray.Create();

        _ = CheckForUpdatesAsync(silent: true);
    }

    private static string CurrentVersion =>
        System.Reflection.Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.0.0";

    /// Silent on launch (only surfaces UI if actually newer); explicit
    /// from the tray menu always reports a result, including "up to date".
    /// Uses a raw Win32 MessageBox rather than ContentDialog -- this is a
    /// tray-only app with no window guaranteed to be open (ContentDialog
    /// needs a live XamlRoot, which SettingsWindow only has once opened).
    private async Task CheckForUpdatesAsync(bool silent)
    {
        var release = await UpdateChecker.CheckForUpdateAsync(CurrentVersion);
        if (release is null)
        {
            if (!silent)
            {
                MessageBox(0, $"Whisper {CurrentVersion} is the latest version.", "You're up to date", MB_OK);
            }
            return;
        }

        var choice = MessageBox(
            0,
            $"Whisper {release.TagName} is available. You're on {CurrentVersion}.\n\nOpen the download page?",
            "Update Available",
            MB_YESNO);

        if (choice == IDYES)
        {
            await Windows.System.Launcher.LaunchUriAsync(new Uri(release.HtmlUrl));
        }
    }

    private const uint MB_OK = 0x0;
    private const uint MB_YESNO = 0x4;
    private const int IDYES = 6;

    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern int MessageBox(nint hWnd, string text, string caption, uint type);

    private void OnRecordingStarted()
    {
        _recorder.RecordSystemAudio = _settings.Settings.RecordSystemAudio;
        _recorder.Start(_settings.Settings.PreferredInputDeviceId);
    }

    private async void OnRecordingStopped()
    {
        var wav = _recorder.Stop();
        if (wav == null) return; // silence gate -- nothing worth transcribing

        if (_settings.Settings.SaveAudio)
            await SaveRecordingAsync(wav);

        var apiKey = CredentialStore.GetApiKey("groq");
        if (string.IsNullOrEmpty(apiKey)) return; // no key configured -- surface via tray balloon in a follow-up pass

        ISttProvider stt = new GroqSttProvider(_http, apiKey);
        var text = await stt.TranscribeAsync(wav, CancellationToken.None);

        if (_settings.Settings.CleanupEnabled)
        {
            ICleanupProvider cleanup = new GroqCleanupProvider(_http, apiKey);
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(_settings.Settings.CleanupTimeoutSeconds));
            text = await cleanup.CleanupAsync(text, _settings.Settings.CleanupInstructions, cts.Token);
        }

        if (string.IsNullOrWhiteSpace(text)) return;

        if (_settings.Settings.OutputMode == OutputMode.PasteAtCursor)
            await PasteService.PasteAsync(text, _settings.Settings.KeepOnClipboardAfterPaste);
    }

    private static Task SaveRecordingAsync(byte[] wav)
    {
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Whisper", "Recordings");
        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, $"{DateTime.Now:yyyyMMdd-HHmmss}.wav");
        return File.WriteAllBytesAsync(path, wav);
    }

    private void ShowSettings()
    {
        _settingsWindow ??= new SettingsWindow(_settings, _hotkeys);
        _settingsWindow.Activate();
    }
}
