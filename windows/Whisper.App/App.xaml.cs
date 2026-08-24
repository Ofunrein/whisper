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
    // Constructed in OnLaunched, not as a field initializer: field initializers
    // run before the constructor body, i.e. before InitializeComponent() has
    // merged XamlControlsResources into Application.Resources. Building a Window
    // -- which resolves theme resources in its own InitializeComponent() -- that
    // early fails inside Microsoft.UI.Xaml.dll as a native fail-fast
    // (0xc000027b), before any managed handler can report it. That is the real
    // cause of issue #1, not the OS build: a minimal WinUI3 unpackaged app on the
    // same WindowsAppSDK 1.8 and the same Windows 11 21H2 box starts fine.
    private RecordingIndicatorWindow? _indicator;
    private SettingsWindow? _settingsWindow;

    /// Tracks recording state for Toggle-style bindings, where HotkeyManager
    /// only reports the down-transition (RecordingToggled) and expects the
    /// consumer to decide start-vs-stop itself. Hold-style bindings don't
    /// need this -- RecordingStarted/RecordingStopped already map 1:1 to
    /// down/up.
    private bool _isRecording;

    public App()
    {
        Program.Trace("App ctor entered (fields already initialized)");
        // WinUI installs no default handler for exceptions thrown before or
        // during OnLaunched -- an unhandled one kills the process instantly
        // with no dialog, which is exactly the "just didn't open" symptom
        // this app was originally reported for. These hooks can't catch a
        // true native fail-fast (e.g. a stowed-exception/0xc000027b crash
        // inside Microsoft.UI.Xaml.dll itself, which bypasses managed SEH
        // by design), but they do catch any *managed* exception thrown
        // during startup -- from AppDomain-level (thread pool/finalizer/etc)
        // down to this.UnhandledException (WinUI's own XAML-dispatcher-
        // thread hook) -- and surface it instead of failing silently.
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            ReportFatalStartupException(e.ExceptionObject as Exception, "AppDomain.UnhandledException");
        UnhandledException += (_, e) =>
        {
            ReportFatalStartupException(e.Exception, "Application.UnhandledException");
            e.Handled = true;
        };

        Program.Trace("before App.InitializeComponent");
        InitializeComponent();
        Program.Trace("after App.InitializeComponent");
    }

    private static void ReportFatalStartupException(Exception? ex, string source)
    {
        MessageBox(
            0,
            $"Whisper hit an unexpected error during startup and needs to close.\n\n" +
            $"Source: {source}\n{ex}",
            "Whisper failed to start",
            MB_OK);
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Program.Trace("OnLaunched entered");
        try
        {
            _hotkeys.Binding = _settings.Settings.Bindings.Count > 0
                ? _settings.Settings.Bindings[0]
                : HotkeyBinding.DefaultRightControl();
            _hotkeys.RecordingStarted += OnRecordingStarted;
            _hotkeys.RecordingStopped += OnRecordingStopped;
            _hotkeys.RecordingToggled += OnRecordingToggled;
            _hotkeys.Start();
            Program.Trace("hotkeys started");

            Program.Trace("before new RecordingIndicatorWindow");
            _indicator = new RecordingIndicatorWindow();
            Program.Trace("after new RecordingIndicatorWindow");
            _indicator.StopRequested += OnIndicatorStopRequested;

            _tray.SettingsRequested += ShowSettings;
            _tray.QuitRequested += () => Environment.Exit(0);
            _tray.CheckForUpdatesRequested += () => _ = CheckForUpdatesAsync(silent: false);
            _tray.Create();
            Program.Trace("tray created");

            Program.Trace("before CheckForUpdatesAsync");
            _ = CheckForUpdatesAsync(silent: true);
            Program.Trace("OnLaunched complete");
        }
        catch (Exception ex)
        {
            ReportFatalStartupException(ex, nameof(OnLaunched));
            throw;
        }
    }

    private static string CurrentVersion =>
        System.Reflection.Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.0.0";

    /// Silent on launch (only surfaces UI if actually newer); explicit
    /// from the tray menu always reports a result, including "up to date".
    /// Uses a raw Win32 MessageBox rather than ContentDialog -- this is a
    /// tray-only app with no window guaranteed to be open (ContentDialog
    /// needs a live XamlRoot, which SettingsWindow only has once opened).
    ///
    /// When an update exists, mirrors the mac MenuBar's three-way choice
    /// (Download & Install / View Release Page / Later) via MB_YESNOCANCEL,
    /// since a plain Win32 MessageBox can't have custom button labels.
    /// Download & Install is the default path; anything that goes wrong
    /// (no .msi asset, download failure, UAC denial, msiexec failure) falls
    /// back to offering the release page link instead of failing silently.
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
            $"Whisper {release.TagName} is available. You're on {CurrentVersion}.\n\n" +
            "Yes = Download & Install\nNo = View Release Page\nCancel = Later",
            "Update Available",
            MB_YESNOCANCEL);

        if (choice == IDYES)
        {
            await InstallUpdateAsync(release);
        }
        else if (choice == IDNO)
        {
            await Windows.System.Launcher.LaunchUriAsync(new Uri(release.HtmlUrl));
        }
    }

    /// Downloads, installs, and schedules a relaunch. On success the app
    /// quits itself (Updater.ScheduleRelaunch handles bringing it back up),
    /// so there's no "success" UI path to design here -- only the failure
    /// path needs a visible message, with a fallback back to the manual
    /// release-page link.
    private async Task InstallUpdateAsync(UpdateChecker.Release release)
    {
        var result = await Updater.DownloadAndInstallAsync(release);
        if (result.Outcome is Updater.UpdateOutcome.Success or Updater.UpdateOutcome.RestartRequired)
        {
            Application.Current.Exit();
            return;
        }

        var message = result.Outcome switch
        {
            Updater.UpdateOutcome.NoMsiAsset =>
                "This release doesn't have a Windows installer Whisper knows how to install automatically.",
            Updater.UpdateOutcome.ElevationDenied =>
                "The update needs administrator permission, which wasn't granted.",
            Updater.UpdateOutcome.DownloadFailed =>
                $"Couldn't download the update: {result.Detail}",
            _ => $"Installer failed: {result.Detail}",
        };

        var choice = MessageBox(0, $"{message}\n\nOpen the download page instead?", "Update Failed", MB_YESNO);
        if (choice == IDYES)
        {
            await Windows.System.Launcher.LaunchUriAsync(new Uri(release.HtmlUrl));
        }
    }

    private const uint MB_OK = 0x0;
    private const uint MB_YESNO = 0x4;
    private const uint MB_YESNOCANCEL = 0x3;
    private const int IDYES = 6;
    private const int IDNO = 7;

    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern int MessageBox(nint hWnd, string text, string caption, uint type);

    private void OnRecordingStarted()
    {
        _isRecording = true;
        _recorder.RecordSystemAudio = _settings.Settings.RecordSystemAudio;
        _recorder.Start(_settings.Settings.PreferredInputDeviceId);
        _indicator?.ShowIndicator();
    }

    /// Toggle-style bindings only fire on the down-transition -- the first
    /// press starts recording, the second stops it. Hold-style bindings
    /// don't route through here at all (RecordingStarted/RecordingStopped
    /// already fire directly from HotkeyManager's down/up tracking).
    private void OnRecordingToggled()
    {
        if (_isRecording) OnRecordingStopped();
        else OnRecordingStarted();
    }

    /// Wired to the indicator's click -- the same stop path a released
    /// hold-hotkey or a second toggle-hotkey press already triggers. Lets
    /// users stop a recording with the mouse instead of only via the
    /// keyboard/mouse-button binding (useful for Toggle style especially,
    /// where there's otherwise no on-screen way to tell it's still live).
    private void OnIndicatorStopRequested()
    {
        if (_isRecording) OnRecordingStopped();
    }

    private async void OnRecordingStopped()
    {
        _isRecording = false;
        _indicator?.HideIndicator();

        var wav = _recorder.Stop();
        if (wav == null) return; // silence gate -- nothing worth transcribing

        if (_settings.Settings.SaveAudio)
            await SaveRecordingAsync(wav);

        var sttKind = _settings.Settings.SttProvider;
        // A null account means the provider runs on-device (LocalWhisper) and
        // has no key to look up, so the missing-key bail-out doesn't apply.
        var sttAccount = ProviderFactory.KeyAccountFor(sttKind);
        var sttKey = sttAccount is null ? null : CredentialStore.GetApiKey(sttAccount);
        if (sttAccount is not null && string.IsNullOrEmpty(sttKey)) return; // no key configured -- surface via tray balloon in a follow-up pass

        var stt = ProviderFactory.CreateSttProvider(sttKind, _http, sttKey, _settings.Settings);
        var text = await stt.TranscribeAsync(wav, CancellationToken.None);

        if (_settings.Settings.CleanupEnabled)
        {
            var cleanup = ProviderFactory.CreateCleanupProvider(
                _settings.Settings.CleanupProvider,
                _http,
                _settings.Settings,
                account => CredentialStore.GetApiKey(account));

            if (cleanup != null)
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(_settings.Settings.CleanupTimeoutSeconds));
                text = await cleanup.CleanupAsync(text, _settings.Settings.CleanupInstructions, cts.Token);
            }
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
