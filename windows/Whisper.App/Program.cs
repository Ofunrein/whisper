namespace Whisper.App;

/// Hand-written replacement for the XAML-compiler-generated Main() (see
/// DisableXamlGeneratedMain in Whisper.App.csproj for why). Identical to the
/// generated version except for the WriteStartupDiagnostics() call before
/// Application.Start().
public static class Program
{
    [System.STAThread]
    private static void Main(string[] args)
    {
        WriteStartupDiagnostics();

        global::WinRT.ComWrappersSupport.InitializeComWrappers();
        Trace("before Application.Start");
        global::Microsoft.UI.Xaml.Application.Start((p) =>
        {
            Trace("inside Start callback");
            var context = new global::Microsoft.UI.Dispatching.DispatcherQueueSynchronizationContext(
                global::Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
            global::System.Threading.SynchronizationContext.SetSynchronizationContext(context);
            Trace("before new App()");
            new App();
            Trace("after new App()");
        });
        Trace("Start returned");
    }

    /// Best-effort environment log written immediately before the native WinUI3
    /// XAML engine starts inside Application.Start(). Issue #1 reported a native
    /// fail-fast (0xc000027b) there, uncatchable from managed code, and guessed
    /// the end-of-life Windows 11 21H2 (build 22000) host was to blame.
    ///
    /// It wasn't. On that same box, a minimal unpackaged WinUI3 app on the same
    /// WindowsAppSDK 1.8 starts cleanly; the crash was App.xaml.cs constructing
    /// RecordingIndicatorWindow in a field initializer, which runs before
    /// InitializeComponent() has merged XamlControlsResources (see the comment on
    /// that field). The OS/UBR breadcrumb stays because it cost real time to rule
    /// out, and the Trace() calls below stay because they are what localised the
    /// failing step -- a fail-fast leaves no stack, so the last line written is
    /// the only evidence available.
    internal static void Trace(string msg)
    {
        try
        {
            var dir = System.IO.Path.Combine(
                System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData), "Whisper");
            System.IO.Directory.CreateDirectory(dir);
            System.IO.File.AppendAllText(System.IO.Path.Combine(dir, "startup.log"),
                $"{System.DateTime.Now:HH:mm:ss.fff} TRACE {msg}{System.Environment.NewLine}");
        }
        catch { }
    }

    private static void WriteStartupDiagnostics()
    {
        try
        {
            var dir = System.IO.Path.Combine(
                System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData),
                "Whisper");
            System.IO.Directory.CreateDirectory(dir);

            var version = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
            var line =
                $"{System.DateTime.Now:O} starting Whisper.App {version} " +
                $"OS={System.Environment.OSVersion.VersionString} " +
                $"Build={System.Environment.OSVersion.Version.Build} " +
                $"UBR={GetUbr()}" +
                System.Environment.NewLine;

            System.IO.File.AppendAllText(System.IO.Path.Combine(dir, "startup.log"), line);
        }
        catch
        {
            // Diagnostics must never be the reason startup fails.
        }
    }

    private static string GetUbr()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(
                @"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
            return key?.GetValue("UBR")?.ToString() ?? "?";
        }
        catch
        {
            return "?";
        }
    }
}
