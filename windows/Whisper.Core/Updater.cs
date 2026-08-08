using System.Diagnostics;

namespace Whisper.Core;

/// <summary>
/// Performs a one-click, fully-silent self-update: download the latest
/// GitHub release's .msi asset, run it via <c>msiexec /qn</c>, then relaunch
/// the app from its installed location once the current process exits so
/// the installer can replace the running files cleanly.
///
/// Mirrors Sources/Whisper/Update/Updater.swift's DMG/PKG flow, adapted to
/// Windows: the .msi is the equivalent of the mac PKG path (it needs
/// elevation because Package.wxs installs into ProgramFiles64Folder, i.e.
/// perMachine scope), not the .dmg path (there's no per-user "just copy the
/// exe" equivalent here worth building -- msiexec already does the
/// copy/registry/shortcut work and handles upgrade-in-place via the MSI's
/// MajorUpgrade element).
/// </summary>
public static class Updater
{
    public enum UpdateOutcome
    {
        Success,
        RestartRequired,
        NoMsiAsset,
        DownloadFailed,
        ElevationDenied,
        InstallFailed,
    }

    public sealed record UpdateResult(UpdateOutcome Outcome, string? Detail = null);

    /// <summary>
    /// Downloads and installs <paramref name="release"/>'s .msi asset, then
    /// schedules a relaunch of the currently-running exe once this process
    /// exits. Never throws -- every failure mode (no asset, network error,
    /// UAC denial, non-zero msiexec exit) comes back as a distinct
    /// <see cref="UpdateOutcome"/> for the caller to present, with the
    /// caller expected to fall back to the manual release-page link.
    /// </summary>
    public static async Task<UpdateResult> DownloadAndInstallAsync(UpdateChecker.Release release, CancellationToken ct = default)
    {
        var msiAsset = release.Assets.FirstOrDefault(a => a.Name.EndsWith(".msi", StringComparison.OrdinalIgnoreCase));
        if (msiAsset is null) return new UpdateResult(UpdateOutcome.NoMsiAsset);

        string msiPath;
        try
        {
            msiPath = await DownloadAsync(msiAsset, ct);
        }
        catch (Exception ex)
        {
            return new UpdateResult(UpdateOutcome.DownloadFailed, ex.Message);
        }

        try
        {
            var exitCode = await RunMsiExecAsync(msiPath, ct);

            // 0 = success. 3010 = success, but a reboot is needed to finish
            // (e.g. a locked file got scheduled for replacement on next
            // boot) -- treat both as installed; anything else is a real
            // failure.
            if (exitCode is 0 or 3010)
            {
                ScheduleRelaunch();
                return new UpdateResult(exitCode == 3010 ? UpdateOutcome.RestartRequired : UpdateOutcome.Success);
            }

            return new UpdateResult(UpdateOutcome.InstallFailed, $"msiexec exited with code {exitCode}");
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            // ERROR_CANCELLED: the user clicked "No" on the UAC prompt.
            return new UpdateResult(UpdateOutcome.ElevationDenied);
        }
        catch (Exception ex)
        {
            return new UpdateResult(UpdateOutcome.InstallFailed, ex.Message);
        }
        finally
        {
            try { File.Delete(msiPath); } catch { /* best effort; temp dir gets cleaned eventually either way */ }
        }
    }

    private static async Task<string> DownloadAsync(UpdateChecker.Asset asset, CancellationToken ct)
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Whisper-App");

        var destination = Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid():N}-{asset.Name}");

        using var response = await client.GetAsync(asset.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, ct);
        response.EnsureSuccessStatusCode();

        await using var fileStream = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None);
        await response.Content.CopyToAsync(fileStream, ct);

        return destination;
    }

    /// <summary>
    /// Runs the installer fully silently. <c>Verb = "runas"</c> triggers the
    /// standard UAC consent prompt -- Package.wxs installs to
    /// ProgramFiles64Folder (perMachine scope), so this needs the same
    /// elevation a manual double-click install of the .msi would need; it's
    /// not new privilege escalation beyond what installing this app already
    /// requires. <c>UseShellExecute = true</c> is required for Verb to take
    /// effect, which means stdout/stderr can't be redirected -- msiexec's
    /// /qn already suppresses UI, and the exit code alone is enough to tell
    /// success from failure.
    /// </summary>
    private static async Task<int> RunMsiExecAsync(string msiPath, CancellationToken ct)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "msiexec.exe",
            Arguments = $"/i \"{msiPath}\" /qn /norestart",
            UseShellExecute = true,
            Verb = "runas",
        };

        using var process = Process.Start(psi) ?? throw new InvalidOperationException("Failed to start msiexec.");
        await process.WaitForExitAsync(ct);
        return process.ExitCode;
    }

    /// <summary>
    /// Spawns a detached helper that waits for this process to exit, then
    /// relaunches the app from its current (installed) path. Mirrors
    /// Updater.swift's relaunch: the caller is expected to quit the app
    /// (Application.Current.Exit() in App.xaml.cs) right after calling this,
    /// so msiexec can replace the running exe's files without a file lock
    /// conflict. Uses PowerShell's Get-Process/-Id polling instead of a
    /// batch-file PID substring match, which can false-match (e.g. PID 12
    /// matching PID 123).
    /// </summary>
    private static void ScheduleRelaunch()
    {
        var exePath = Environment.ProcessPath;
        if (string.IsNullOrEmpty(exePath)) return;

        var pid = Environment.ProcessId;
        var escapedExePath = exePath.Replace("'", "''");
        var command =
            $"while (Get-Process -Id {pid} -ErrorAction SilentlyContinue) {{ Start-Sleep -Milliseconds 200 }}; " +
            $"Start-Process -FilePath '{escapedExePath}'";

        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -NonInteractive -WindowStyle Hidden -Command \"{command}\"",
            UseShellExecute = true,
            WindowStyle = ProcessWindowStyle.Hidden,
        };

        try
        {
            Process.Start(psi);
        }
        catch
        {
            // If the relaunch helper itself fails to spawn, the update is
            // still installed -- the user just has to start the app again
            // manually. Not worth failing the whole update over.
        }
    }
}
