using NAudio.CoreAudioApi;
using Whisper.App.Audio;

// Checks AudioRecorder's stale-endpoint fallback on a real Windows machine
// without requiring any particular microphone.
//
// The bug this guards: PreferredInputDeviceId is a persisted MMDevice endpoint
// ID, and a mic that gets unplugged (or comes back on a different port) leaves
// a stale one behind. The old code passed it straight to
// MMDeviceEnumerator.GetDevice, which throws for an unknown ID -- and Start()
// is called from the record-hotkey handler with no try/catch, so pressing the
// hotkey killed the app.
//
// Deliberately split into two levels so it still proves something on GitHub's
// Windows runners, which have no audio endpoints at all:
//   * TryGetActiveDevice must resolve a stale ID to "use the default" instead
//     of throwing. Needs no audio hardware, so it always runs.
//   * ResolveMicDevice must actually hand back the default capture device.
//     Needs a capture endpoint to exist; skipped, loudly, when none does.

const string stalePlausibleId = "{0.0.1.00000000}.{deadbeef-dead-beef-dead-beefdeadbeef}";
const string garbageId = "not-an-endpoint-id-at-all";

var failures = 0;

void Pass(string message) => Console.WriteLine($"PASS  {message}");

void Fail(string message)
{
    Console.WriteLine($"::error::FAIL  {message}");
    failures++;
}

void Skip(string message) => Console.WriteLine($"::warning::SKIP  {message}");

MMDeviceEnumerator enumerator;
try
{
    enumerator = new MMDeviceEnumerator();
}
catch (Exception ex)
{
    // MMDevAPI itself is unusable, so nothing below can run. Not a defect in
    // the code under test, so don't fail the release over it -- but say so
    // clearly rather than exiting 0 as if the checks had passed.
    Console.WriteLine($"::warning::MMDeviceEnumerator unavailable ({ex.GetType().Name}: {ex.Message}); mic fallback checks DID NOT RUN");
    return 0;
}

Console.WriteLine("--- Capture endpoints visible to this machine ---");
foreach (var state in new[] { DeviceState.Active, DeviceState.Unplugged, DeviceState.Disabled, DeviceState.NotPresent })
{
    foreach (var device in enumerator.EnumerateAudioEndPoints(DataFlow.Capture, state))
    {
        Console.WriteLine($"  [{state}] {device.FriendlyName} -- {device.ID}");
    }
}

// 1. Stale/garbage IDs must resolve to "use the default", never throw.
foreach (var (label, id) in new[] { ("plausible-but-stale", stalePlausibleId), ("garbage", garbageId) })
{
    try
    {
        var resolved = AudioRecorder.TryGetActiveDevice(enumerator, id);
        if (resolved == null)
        {
            Pass($"{label} endpoint ID -> null (falls back to default)");
        }
        else
        {
            Fail($"{label} endpoint ID unexpectedly resolved to '{resolved.FriendlyName}'");
        }
    }
    catch (Exception ex)
    {
        Fail($"{label} endpoint ID threw {ex.GetType().Name}: {ex.Message} -- this is the crash-on-hotkey bug");
    }
}

// Sanity check that those IDs really are rejected by NAudio, i.e. the checks
// above aren't passing vacuously against IDs that happen to be valid here.
try
{
    var raw = enumerator.GetDevice(stalePlausibleId);
    Fail($"stale ID '{stalePlausibleId}' actually exists on this machine ('{raw.FriendlyName}') -- pick a different fake ID");
}
catch (Exception ex)
{
    Pass($"bare GetDevice on the stale ID throws {ex.GetType().Name} (so the guard above is doing real work)");
}

// 2. Null preference means "no pin", which is also the default path.
try
{
    if (AudioRecorder.TryGetActiveDevice(enumerator, null) == null)
    {
        Pass("null preferred ID -> null (falls back to default)");
    }
    else
    {
        Fail("null preferred ID resolved to a device");
    }
}
catch (Exception ex)
{
    Fail($"null preferred ID threw {ex.GetType().Name}: {ex.Message}");
}

// 3. Full fallback, which needs a capture endpoint to fall back *to*.
MMDevice? systemDefault = null;
Exception? defaultLookupError = null;
try
{
    systemDefault = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Communications);
}
catch (Exception ex)
{
    defaultLookupError = ex;
}

if (systemDefault != null)
{
    Console.WriteLine($"--- Default capture endpoint: {systemDefault.FriendlyName} ({systemDefault.State}) ---");

    try
    {
        var resolved = AudioRecorder.ResolveMicDevice(enumerator, stalePlausibleId);
        if (resolved.ID == systemDefault.ID && resolved.State == DeviceState.Active)
        {
            Pass($"stale pin -> default capture device '{resolved.FriendlyName}' (active)");
        }
        else
        {
            Fail($"stale pin -> '{resolved.FriendlyName}' ({resolved.State}), expected the active default '{systemDefault.FriendlyName}'");
        }
    }
    catch (Exception ex)
    {
        Fail($"stale pin threw {ex.GetType().Name}: {ex.Message} despite a default capture device existing");
    }

    // A live pin must still win over the default -- the fallback must not have
    // turned pinning into a no-op. Uses whatever mic this machine has.
    try
    {
        var resolved = AudioRecorder.ResolveMicDevice(enumerator, systemDefault.ID);
        if (resolved.ID == systemDefault.ID)
        {
            Pass($"live pin -> honoured ('{resolved.FriendlyName}')");
        }
        else
        {
            Fail($"live pin '{systemDefault.ID}' resolved to a different device '{resolved.ID}'");
        }
    }
    catch (Exception ex)
    {
        Fail($"live pin threw {ex.GetType().Name}: {ex.Message}");
    }
}
else
{
    Skip($"no default capture endpoint on this machine ({defaultLookupError?.GetType().Name}: {defaultLookupError?.Message}) -- "
         + "stale-ID handling was verified, but resolving to a real mic was NOT; that needs a machine with a microphone");

    // Still worth asserting the failure comes from the default lookup rather
    // than the stale-ID lookup, i.e. execution got past the guard.
    try
    {
        var resolved = AudioRecorder.ResolveMicDevice(enumerator, stalePlausibleId);
        Fail($"stale pin returned '{resolved.FriendlyName}' on a machine with no capture endpoint");
    }
    catch (Exception ex) when (ex.HResult == defaultLookupError!.HResult)
    {
        Pass($"stale pin fails at the default-endpoint lookup (HRESULT 0x{ex.HResult:X8}), i.e. past the stale-ID guard");
    }
    catch (Exception ex)
    {
        Fail($"stale pin threw {ex.GetType().Name} (HRESULT 0x{ex.HResult:X8}), but the bare default lookup threw "
             + $"0x{defaultLookupError!.HResult:X8} -- the failure isn't coming from the default lookup");
    }
}

Console.WriteLine(failures == 0 ? "All mic fallback checks passed." : $"{failures} mic fallback check(s) failed.");
return failures == 0 ? 0 : 1;
