# Whisper: macOS dictation app

## Original request
Build a complete, working macOS AI dictation app called "Whisper" (Wispr Flow / SuperWhisper clone): hold a hotkey to record, release to transcribe + clean up + paste at cursor. Faster than Wispr Flow and SuperWhisper. Provider-pluggable (cloud + local), SuperWhisper-style movable pill UI, output modes, history, secure keys.

## Interpreted outcome
A runnable native Swift/SwiftUI macOS app that: records while a configurable keyboard/mouse hotkey is held (Fn default), transcribes via a selectable STT provider (Groq whisper-large-v3-turbo default; ElevenLabs Scribe v2, Deepgram nova-3, local whisper.cpp, OpenAI), optionally cleans up via a selectable LLM provider (Groq default; Cerebras, Gemini Flash, Ollama, OpenAI), and routes the result per output mode (paste at cursor default; copy-only; paste+keep clipboard). Movable SuperWhisper-style pill indicator with waveform. History window with raw/cleaned toggle. Keys in Keychain. Cleanup instructions editable in Settings, default text verbatim from spec. Never crash: fallback to raw text on any cleanup failure.

## Input shape
existing_plan - full plan at ~/.cursor/plans/"Whisper dictation app-88801255.plan.md" (validated with live API research on 2026-07-05).

## Goal oracle
The app builds (`xcodebuild` succeeds), launches, and an end-to-end walkthrough passes: hold Fn -> pill shows waveform -> release -> transcript pasted into a target text field; cleanup toggle changes output; history shows raw+cleaned; settings persist keys to Keychain; pill draggable and Dock-avoiding. Unit tests for pipeline fallback logic and provider request construction pass.

## Constraints (non-negotiable)
- Native Swift/SwiftUI. No Electron.
- Latency is a first-class constraint: pre-warm on hotkey-down, keep-alive URLSession, cleanup time-box with raw fallback.
- Keys only in Keychain. Never in code, plists, or JSON.
- Cleanup default system instruction must be the user's text word-for-word.
- Raw-paste fallback on cleanup failure or missing key; no crashes.
- App Sandbox disabled (event tap + synthetic paste).

## Likely misfire
Building a demo that transcribes but skips the hard parts: global Fn event tap, Accessibility-gated paste, pill drag/Dock avoidance, provider pluggability, Keychain. All are required.

## Tranche
Complete the full app per plan todos: scaffold, permissions, hotkeys (keyboard+mouse), audio+pre-warm, pill UI+positioning, STT providers, cleanup providers, pipeline, output router, speed wiring, Keychain+settings, settings UI, history UI, menu bar items. Verify with build + tests + walkthrough audit.
