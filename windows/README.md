# Whisper for Windows

Native C# / WinUI 3 port of the mac dictation app. Same shape: hold a hotkey,
speak, release, get pasted text at your cursor.

**Status: built by CI, never run by a human.** There's no Windows machine
available in the environment this was written in, so nothing here has been
manually exercised. But `.github/workflows/release.yml`'s `build-windows`
job runs on a real `windows-latest` GitHub Actions runner on every push and
every tagged release -- it does a real `dotnet publish -r win-x64
--self-contained` of `Whisper.App` and a real `wix build` of the MSI, so
compiler/linker errors surface there, not just guesswork. `Whisper.Core`
(pure C#, no Windows-only APIs) is additionally verified with `dotnet
build` on macOS. Treat this as CI-compiled but not yet UX/hardware tested
-- first real Windows box should focus on runtime behavior (hotkey capture,
WASAPI device selection, paste-at-cursor), not compilation. Check the
Actions tab for the latest `build-windows` run status before assuming it's
green.

## Layout

- `Whisper.Core/` -- platform-agnostic: settings model, JSON persistence,
  STT/cleanup provider interfaces, Groq implementation (HTTP only, no
  Windows APIs). Builds and runs on any OS.
- `Whisper.App/` -- the actual Windows app (WinUI 3, `net8.0-windows`):
  - `Hotkeys/HotkeyManager.cs` -- `WH_KEYBOARD_LL`/`WH_MOUSE_LL` hook,
    tracks down/up transitions for hold-to-record (no `RegisterHotKey`,
    since that API can't report "still held").
  - `Audio/AudioRecorder.cs` -- WASAPI mic capture via NAudio, resampled to
    16kHz mono 16-bit to match the mac app's pipeline and Groq's expected
    input. System audio is `WasapiLoopbackCapture` off the default render
    device -- notably *simpler* than macOS here, since Windows loopback
    capture needs no special permission or process-tap dance. Off by
    default (`AppSettings.RecordSystemAudio`), mixed in only when enabled.
  - `Security/CredentialStore.cs` -- API keys in Windows Credential Manager
    (`CredWrite`/`CredRead`) instead of the mac Keychain.
  - `Output/PasteService.cs` -- sets clipboard, sends synthetic Ctrl+V via
    `SendInput`, restores prior clipboard contents afterward unless "keep
    on clipboard" is on.
  - `TrayIcon.cs` -- `Shell_NotifyIcon` system-tray presence (Settings /
    Quit menu), the Windows equivalent of the mac app's menu-bar icon. No
    main window opens at launch.
  - `Views/SettingsWindow.xaml` -- API Keys / Output / Hotkey / Vocabulary
    tabs. The API key field uses WinUI's built-in
    `PasswordBox PasswordRevealMode="Peek"`, which is the native
    reveal/hide-with-an-eye-icon control -- same idea as the mac app's
    eye-button toggle, just the platform-native version of it.
  - `Installer/Package.wxs` -- WiX v5 source for the MSI. Built in CI via
    `wix build`, not locally verifiable (the WiX toolset only fully works
    on Windows). Harvests the publish output with `<Files Include>` (WiX
    v4's replacement for `heat.exe`) instead of hand-listing every file.

## Updates

`Whisper.Core/UpdateChecker.cs` hits the GitHub Releases API on launch
(silent -- only surfaces a prompt if a newer tag exists) and from the tray
menu's "Check for Updates..." (always reports a result). Check-only, same
as the mac app's `UpdateChecker.swift`: no silent download/install, just a
link to the release page, since neither app is code-signed yet and a
silently-replaced binary would just re-trigger SmartScreen/Gatekeeper
anyway.

## What's actually wired up vs. stubbed

- **STT**: Groq, OpenAI, Deepgram, ElevenLabs are all implemented
  (`Providers/GroqSttProvider.cs`, `OpenAISttProvider.cs`,
  `DeepgramSttProvider.cs`, `ElevenLabsSttProvider.cs`), matching the mac
  app's cloud providers. `LocalWhisper` (on-device whisper.cpp) is
  deliberately **not** ported -- it needs a bundled native inference
  engine and model-download/management story (see
  `Sources/Whisper/Providers/STT/LocalWhisperTranscriber.swift` +
  `LocalWhisperDownloader.swift` on the mac side), which is a materially
  bigger lift than an HTTP client class and is out of scope here. It's a
  reasonable follow-up if/when Windows on-device inference (e.g. via
  whisper.cpp's own Windows build, or ONNX Runtime) becomes a priority.
- **Cleanup**: Groq, Cerebras, OpenAI (via the shared
  `Providers/OpenAiCompatCleanupProvider.cs`, since all three share the
  OpenAI chat-completions request/response shape -- mirrors
  `OpenAICompatCleanup.swift`'s DRY approach instead of one
  copy-pasted class per provider), plus dedicated `GeminiCleanupProvider.cs`,
  `OllamaCleanupProvider.cs` (local, no key), and
  `AnthropicCleanupProvider.cs` (Messages API, `x-api-key` +
  `anthropic-version` headers, `content[0].text` response shape). All
  routed through `Providers/ProviderFactory.cs`, the Windows analogue of
  `ProviderFactory.swift`.
- **Settings UI**: API Keys tab has one field per provider that needs a
  key (Groq, OpenAI, Deepgram, ElevenLabs, Cerebras, Gemini, Anthropic);
  Output tab has an STT provider picker and a cleanup provider picker
  (plus Ollama base URL/model fields, shown regardless of selection --
  only meaningful when Ollama is selected).
- **Hotkey picker**: fixed preset list (Right Ctrl / Right Alt / Right
  Shift / middle mouse / XButton1 / XButton2) plus a Hold/Toggle trigger
  style picker (`HotkeyBinding.Style`, mirroring the mac app's
  `HotkeyTriggerStyle`). The mac app's visual glyph-based hotkey recorder
  (arbitrary key capture + live glyph rendering) is still not ported --
  that's a meaningfully sized follow-up on its own.
- **Recording indicator**: `Views/RecordingIndicatorWindow.xaml` is a
  small always-on-top "Recording -- click to stop" affordance shown while
  recording, wired to the same stop path the hotkey release (Hold style)
  or second press (Toggle style) already calls. It's a functional
  subset of the mac app's `PillIndicator.swift` -- no waveform, no
  drag-to-reposition, no snap grid -- since porting the full floating
  pill visual is a separate, much bigger UI pass.
- **Vocabulary tab**: add/list only, no inline edit/reorder yet (the mac
  app's vocabulary tab got that treatment in an earlier pass; same feature
  gap here).

## Getting a build

**Easiest: grab CI's output.** Every push builds `Whisper.App` on
`windows-latest` and uploads a `whisper-windows` artifact (portable zip +
MSI) -- check the Actions tab. Every `v*` tag additionally publishes those
as GitHub Release assets alongside the mac DMG/PKG.

**From source, on an actual Windows machine:**

1. Install Visual Studio 2022 (Community is fine) with the "Windows App
   SDK" and ".NET desktop development" workloads.
2. Open `windows/Whisper.sln`.
3. Set `Whisper.App` as the startup project, build, run.
4. First launch: right-click the tray icon -> Settings -> paste a Groq API
   key. Hold Right Ctrl anywhere to record.

Or from the command line: `dotnet publish windows/Whisper.App -c Release
-r win-x64 --self-contained -o publish` produces the same portable EXE CI
ships.

## Known gaps to check first when it's actually running

- `HotkeyManager`'s `WH_MOUSE_LL` hook does read `MSLLHOOKSTRUCT.mouseData`'s
  high-order word to tell XBUTTON1 apart from XBUTTON2 on `WM_XBUTTONDOWN`/
  `WM_XBUTTONUP` (that's the documented Win32 convention, and the code
  already does it -- see `MouseHookCallback`), and the Settings Hotkey tab
  now exposes both as separate picker entries. What's still genuinely
  unverified without hardware: some gaming-mouse vendor drivers (Logitech
  Options+, Razer Synapse, etc.) intercept side buttons before they ever
  generate a real `WM_XBUTTONDOWN`/`UP` at the Win32 level -- they remap
  them to macros/keystrokes instead, in which case this hook never sees
  them regardless of the disambiguation logic being correct. That failure
  mode needs a real mouse + real vendor driver to observe; it can't be
  reasoned about further from source alone.
- No notarization/code-signing story here either, matching the mac app's
  current unsigned distribution -- Windows will show a SmartScreen warning
  on first run until that's addressed (or not, if that's an accepted
  tradeoff same as on mac).

## Troubleshooting: the app doesn't open

If double-clicking `Whisper.App.exe` (from the zip) or launching after MSI
install does nothing -- no window, no error, no tray icon -- the build
itself is real and self-contained (CI does `dotnet publish -r win-x64
--self-contained -p:WindowsAppSDKSelfContained=true`, which bundles the
.NET runtime and all Windows App SDK native DLLs into the output; a
missing ".NET Desktop Runtime" is *not* the cause here the way it would be
for a framework-dependent build). Work through these in order:

1. **SmartScreen / Mark-of-the-Web.** Anything downloaded from a browser
   gets tagged with a hidden zone-identifier stream. For the `.msi`, just
   click "More info" -> "Run anyway" on the SmartScreen dialog if it
   appears. For the portable `.zip`: unblock the zip itself *before*
   extracting -- right-click `Whisper-Windows-*.zip` -> Properties ->
   check "Unblock" at the bottom -> OK -> then extract. If you already
   extracted first, every extracted file carries its own copy of the tag,
   so instead right-click `Whisper.App.exe` -> Properties -> "Unblock" ->
   OK. Same idea as the macOS Gatekeeper right-click-Open note above, just
   the Windows version of it.
2. **Antivirus / Windows Defender silently quarantining it.** This app is
   unsigned and does things that look exactly like heuristic-flagged
   malware behavior to AV engines: a global low-level keyboard/mouse hook
   (`HotkeyManager`'s `WH_KEYBOARD_LL`/`WH_MOUSE_LL`), synthetic input
   injection (`PasteService`'s `SendInput`), and credential storage
   (`CredentialStore`'s `CredWrite`/`CredRead`). Some AV products quarantine
   silently (auto-sample-submission) with no visible prompt -- if nothing
   else here explains it, check Windows Security -> Protection history for
   a recent detection/quarantine of `Whisper.App.exe`, and add an exclusion
   or restore it from quarantine if found.
3. **OS version too old.** The app targets
   `net8.0-windows10.0.19041.0` (Windows 10 version 2004 / build 19041,
   May 2020 update) as its floor, since that's what the Windows App SDK
   runtime bootstrap requires. On an older Windows 10 build, the App SDK
   bootstrap can fail during native initialization before any window or
   message box ever gets a chance to appear -- i.e. exactly a silent
   "nothing happens" failure. Check Settings -> System -> About for the OS
   build number; update Windows if it's older than 19041.
4. **Windows N/KN edition missing the Media Feature Pack.** Not a launch
   blocker by itself (this would surface as a crash on first recording
   attempt, not at startup), but worth ruling out early since it's another
   "just doesn't work, no obvious error" report: `AudioRecorder` uses
   NAudio's `MediaFoundationResampler`, which depends on Windows Media
   Foundation. "N"/"KN" SKUs of Windows (EU/Korea editions sold without
   media features) don't include it by default -- install the "Media
   Feature Pack for N/KN editions" from Windows Update / Microsoft's
   download page if applicable.

None of the above has been confirmed against a real failure report (no
Windows machine or captured error was available when this was written) --
they're the ordered list of what a from-source audit says is most likely,
most-common-first. If you hit this, the single most useful next step is
running `Whisper.App.exe` from a `cmd.exe`/PowerShell window instead of
double-clicking it, so any exception that does print has somewhere to
land instead of vanishing with the process.
