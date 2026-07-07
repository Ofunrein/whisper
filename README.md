# Whisper

Native macOS dictation app. Hold a hotkey, speak, release, then Whisper transcribes, optionally cleans up, and pastes at your cursor in any app.

## Install

Download the latest macOS build from GitHub Releases.

If macOS blocks first launch because the app is not notarized yet, right-click `Whisper.app`, choose Open, then approve the prompt.

## Build locally

```bash
./scripts/make-app.sh
open /Applications/Whisper.app
```

Requires macOS 14+ and Xcode command line tools.

On first launch, grant:

- Microphone: System Settings > Privacy & Security > Microphone
- Accessibility: System Settings > Privacy & Security > Accessibility

`make-app.sh` installs `/Applications/Whisper.app` and asks LaunchServices, Spotlight, and Raycast to index the installed app.

## Use

1. Open Whisper from Raycast, Spotlight, Finder, or `/Applications`.
2. Add provider keys in Settings.
3. Place the cursor in any text field.
4. Hold the configured recording shortcut, speak, then release.
5. Whisper pastes the transcript at the cursor.

Default shortcuts:

- Right Command hold
- Right-click hold

Quick right-clicks pass through to normal context menus. Rapid double right-click does not start recording.

## Providers

| Stage | Options | Default |
|---|---|---|
| Speech-to-text | Groq Whisper, ElevenLabs Scribe, Deepgram Nova, OpenAI, local whisper.cpp | Groq |
| Cleanup | Groq, Cerebras, Gemini, Ollama, OpenAI | Groq |

Cleanup is optional. If cleanup fails, times out, or has no key, Whisper pastes the raw transcript instead.

Local mode: install `whisper-cpp`, put any ggml model in `~/Library/Application Support/Whisper/models/`, then pick local whisper.cpp in Settings. The app can browse, remember, and switch local model paths. Pick Ollama separately for local cleanup.

## Features

- Hold-to-record hotkeys for keyboard and mouse buttons.
- Auto-paste at cursor with clipboard restore.
- Copy-only and paste-keep-on-clipboard output modes.
- Movable snapping pill indicator with waveform.
- History window with raw and cleaned text.
- Optional audio saving and retention pruning.
- Provider keys stored locally at `~/Library/Application Support/Whisper/secrets.json` with user-only file permissions.

## Release artifacts

Do not commit `.app`, `.zip`, or `.dmg` release artifacts into the repo. Build them locally, then upload them as GitHub Release assets.

Useful commands:

```bash
./scripts/make-app.sh
mkdir -p dist
ditto -c -k --keepParent build/Whisper.app dist/Whisper-0.1.1-macOS.zip
mkdir -p dist/dmg-root
rm -rf dist/dmg-root/*
cp -R build/Whisper.app dist/dmg-root/
ln -s /Applications dist/dmg-root/Applications
hdiutil create -volname Whisper -srcfolder dist/dmg-root -ov -format UDZO dist/Whisper-0.1.1-macOS.dmg
```

## Tests

```bash
swift test
```
