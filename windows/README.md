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

- **STT/cleanup**: only Groq (`Providers/GroqSttProvider.cs`,
  `GroqCleanupProvider.cs`). OpenAI/Deepgram/ElevenLabs exist as enum cases
  in `AppSettings` so the settings file has room for them, but there's no
  implementation yet -- same interfaces (`ISttProvider`/`ICleanupProvider`)
  the mac app effectively mirrors, so adding one is a new class, not a
  redesign.
- **Hotkey picker**: fixed preset list (Right Ctrl / Right Alt / Right
  Shift / middle mouse). The mac app's visual glyph-based hotkey recorder
  (arbitrary key capture + live glyph rendering) is not ported -- that's a
  meaningfully sized follow-up on its own.
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

- `TrayIcon.cs`'s `LoadIcon` call uses the stock `IDI_APPLICATION` icon
  placeholder -- swap in a real `.ico` before shipping.
- `HotkeyManager` doesn't yet distinguish which XButton fired reliably
  across all mice/drivers -- worth a real hardware test.
- No notarization/code-signing story here either, matching the mac app's
  current unsigned distribution -- Windows will show a SmartScreen warning
  on first run until that's addressed (or not, if that's an accepted
  tradeoff same as on mac).
