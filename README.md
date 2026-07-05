# Whisper

Native macOS dictation app: hold a hotkey, speak, release — your words are transcribed, cleaned up, and pasted at your cursor in any app. A Wispr Flow / SuperWhisper-style tool built for speed.

## Build & run

```bash
./scripts/make-app.sh
open build/Whisper.app
```

Requires macOS 14+ and Xcode command line tools. On first launch, grant:

- **Microphone** — System Settings → Privacy & Security → Microphone
- **Accessibility** — System Settings → Privacy & Security → Accessibility (needed for the global hotkey and paste)

## Use

1. Open Settings from the menu bar icon and paste an API key for your chosen providers (stored in the Keychain).
2. Hold **Fn** (default), speak, release. The pill at the bottom of the screen shows a live waveform while recording.
3. Text is pasted wherever your cursor is.

## Providers

| Stage | Options | Default |
|---|---|---|
| Speech-to-text | Groq (whisper-large-v3-turbo), ElevenLabs Scribe v2, Deepgram Nova-3, OpenAI, local whisper.cpp | Groq |
| Cleanup | Groq, Cerebras, Gemini Flash, Ollama (local), OpenAI | Groq |

Cleanup is optional (menu bar toggle) and time-boxed — if it fails, times out, or has no key, the raw transcript is pasted instead. The cleanup system instruction is editable in Settings.

Local mode: `brew install whisper-cpp`, download a ggml model to `~/Library/Application Support/Whisper/models/`, and pick "Local whisper.cpp" + Ollama in Settings for fully offline dictation.

## Features

- Configurable hotkeys: Fn key, any key combo, or mouse buttons (middle, Mouse 4-10), hold or toggle.
- Output modes: paste at cursor (clipboard restored), copy only, paste and keep on clipboard.
- Movable pill indicator that avoids the Dock and remembers its position.
- History window with a raw/cleaned toggle; optional audio saving.
- Keys live only in the macOS Keychain.

## Tests

```bash
swift test
```
