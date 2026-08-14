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
        global::Microsoft.UI.Xaml.Application.Start((p) =>
        {
            var context = new global::Microsoft.UI.Dispatching.DispatcherQueueSynchronizationContext(
                global::Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
            global::System.Threading.SynchronizationContext.SetSynchronizationContext(context);
            new App();
        });
    }

    /// Best-effort environment log written immediately before the native WinUI3
    /// XAML engine starts inside Application.Start(). See issue #1: on at least
    /// one real Windows 11 21H2 (build 22000, an end-of-life build with no
    /// updates since Oct 2023) machine, that call fails with a native fail-fast
    /// (0xc000027b) before any managed exception handler -- including the ones
    /// already registered in App()'s constructor -- ever gets a chance to run.
    /// That kind of failure is architecturally uncatchable from managed code, so
    /// this can only leave a breadcrumb beforehand: if it happens again, whoever
    /// investigates has the OS build/UBR and resolved app version to go on
    /// instead of a silent, contextless crash.
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
