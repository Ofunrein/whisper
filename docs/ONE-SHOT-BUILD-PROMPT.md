# One-Shot Prompt: Build Your Own Wispr Flow Alternative

> Want the easy route instead? Try Spokenly. Main path below is for owning and customizing the entire app with no subscription.

Paste the full prompt block into GPT-5.6, GPT-5.5, Claude Opus 5, or another frontier coding agent with terminal access.

```text
You are a principal macOS and Windows desktop engineer. Build and ship a complete native, local-first push-to-talk dictation app from an empty folder in this single run. Do not ask questions. Choose sensible defaults, recover from errors, and stop only after code, tests, installers, documentation, GitHub automation, and verification are complete.

GOAL
Build an open-source Wispr Flow alternative the user owns and can customize. Hold a global shortcut, speak, release, transcribe, optionally clean the wording, then paste at the current cursor in any app. Support macOS 14+ and Windows 10 2004+/11. No subscription, telemetry, hosted backend, database, login, or proprietary service. Provider APIs are optional and paid directly by the user. Include a local path where practical.

GITHUB FIRST
1. Inspect the OS, SDKs, package managers, Git, and GitHub CLI. Never print secrets.
2. Initialize Git on `main` if needed. Add `.gitignore`, MIT `LICENSE`, `README.md`, `VERSION`, `SECURITY.md`, `CONTRIBUTING.md`, and CI.
3. Run `gh auth status`. If authenticated and no origin exists, create a private GitHub repo, set origin, and push main. If unavailable, continue locally and provide exact `gh auth login`, `gh repo create`, and push commands. Never block the build on GitHub.
4. Never commit keys, recordings, transcripts, models, credentials, build output, or installers.

CORE EXPERIENCE
- Menu-bar app on macOS; system-tray app on Windows. No main window at launch.
- Global hold and toggle shortcuts. Defaults: Right Command on macOS, Right Ctrl on Windows. Include mouse-button presets where platform APIs allow.
- Record microphone audio while active. Show a movable always-on-top recording pill with state, elapsed time, stop, and cancel.
- On stop: transcribe, optionally clean up, paste at active cursor, then restore prior clipboard. Also support copy-only and keep-on-clipboard modes.
- Never lose dictated text. Cleanup failure, timeout, refusal, or empty output must fall back to raw transcript. Paste failure must preserve text in history and clipboard.
- Local history: raw and cleaned text, timestamp, provider, duration, latency, optional audio path. Add search, copy, retry, delete, clear, and retention controls.
- Vocabulary: add/edit/delete/reorder/import/export. Inject terms into supported STT prompts/keyterms and cleanup context.
- Settings: shortcut, hold/toggle, microphone, optional system audio, STT provider/model, cleanup provider/model, cleanup intensity, language, output mode, sounds, launch at login, history/audio retention, update check, diagnostics.
- Provider health check and test recording.
- Silent GitHub Releases update check. Never silently replace unsigned binaries.
- Diagnostics stay local and redact transcripts, recordings, keys, auth headers, and clipboard content.

PROVIDERS
Use clean protocols/interfaces and a provider factory.
- STT: Groq Whisper, OpenAI transcription, Deepgram Nova, ElevenLabs Scribe.
- macOS local STT: whisper.cpp executable plus a user-selected GGML model, path validation, and setup instructions.
- Windows local STT: include only if a reliable whisper.cpp or ONNX integration can be completed and tested. Otherwise keep the architecture extensible, hide the nonworking option, and document the gap honestly.
- Cleanup: Groq, Cerebras, OpenAI-compatible chat completions, Gemini, Anthropic Messages, and local Ollama.
- Cleanup may remove filler and repair punctuation/structure, but must preserve meaning, names, numbers, code, URLs, emails, paths, commands, and vocabulary.
- Use adaptive cleanup deadlines: short/simple dictation gets a fast budget; long or complex text containing code, URLs, emails, numbers, paths, or vocabulary hits gets more time up to a capped ceiling. Raw text is the hard fallback.
- Reject common silence hallucinations such as repeated thanks, subtitles, and generic refusals without rejecting real short dictation.

MACOS
- Swift 5.9+, SwiftUI/AppKit, Swift Package Manager, macOS 14+.
- AVFoundation microphone capture; provider-compatible 16 kHz mono audio.
- Event taps/global monitors for reliable keyboard and mouse down/up state.
- Accessibility APIs plus NSPasteboard/CGEvent for paste and clipboard restoration.
- Explain/request Microphone and Accessibility permissions; fail gracefully when denied.
- Keychain Services for secrets. SMAppService for launch at login where available.
- Package a real `.app`, drag-to-Applications `.dmg`, and `.pkg` with scripts. Document unsigned Gatekeeper steps honestly.

WINDOWS
- .NET 8, C#, WinUI 3, Windows App SDK. Split platform-neutral code into `Whisper.Core` and integration/UI into `Whisper.App`.
- Low-level `WH_KEYBOARD_LL` and `WH_MOUSE_LL` hooks for hold transitions.
- NAudio/WASAPI microphone capture and optional loopback audio, normalized to 16 kHz mono 16-bit PCM.
- Windows Credential Manager for keys.
- Clipboard plus `SendInput` Ctrl+V with restoration, retries, and safe timing.
- Reliable system tray integration.
- Self-contained x64 portable ZIP and WiX v5 MSI. Document unsigned SmartScreen steps honestly.
- Keep Windows APIs out of the shared core so its tests run cross-platform.

REPOSITORY SHAPE
Use this direct structure unless an existing repo has an equivalent:
- `Sources/Whisper/`: Audio, Hotkey, Output, Pipeline, Providers/STT, Providers/Cleanup, Store, UI, Permissions, Update.
- `Tests/WhisperTests/`.
- `windows/Whisper.Core/`, `windows/Whisper.App/`, `windows/Whisper.Tests/`, `windows/Whisper.sln`.
- `scripts/` for app, DMG, PKG, and verification builds.
- `.github/workflows/` for test/build/release.
Do not create a backend, web app, Electron shell, account system, or speculative abstraction.

SAFETY AND RELIABILITY
- Audio, transcripts, vocabulary, clipboard contents, and keys are private.
- Send audio/text only to the selected provider.
- HTTPS only, explicit timeouts, cancellation, bounded retries, status validation, and redacted errors.
- Recording, uploads, transcription, cleanup, and updates must be asynchronous and cancellable.
- Handle rapid taps, double triggers, release during startup, device removal, empty audio, provider outage, bad keys, rate limits, oversized recordings, clipboard contention, and quit during recording.
- Enforce one active pipeline with an explicit state machine.
- Accessible contrast, keyboard navigation, labels, and reduced motion.

TESTS
Write real tests for:
- Pipeline state transitions and no-double-trigger behavior.
- Raw fallback on cleanup error, timeout, refusal, and empty response.
- Adaptive deadlines increasing for complex/long dictation.
- Vocabulary normalization, deduplication, prioritization, import/export, and prompt injection.
- Silence/hallucination rejection without rejecting real short speech.
- Settings migrations and persistence without secrets.
- Provider request/response parsing through mocked HTTP; no paid live calls.
- Clipboard restore/output routing behind testable adapters.
- Windows core providers/settings.
- Build scripts failing clearly on missing prerequisites.

CI AND RELEASES
Create GitHub Actions that:
- On PR/push: run macOS Swift tests/build, cross-platform `Whisper.Core` tests/build, configured format/lint, and secret scanning.
- On manual dispatch and `v*` tags: build macOS DMG/PKG on macOS and Windows self-contained ZIP/MSI on `windows-latest`; upload artifacts and attach them to tagged GitHub Releases.
- Use one `VERSION` source for every artifact.
- Make signing/notarization optional through documented repository secrets; unsigned fallback must remain explicit.

README FOR A FIRST-TIME USER
Include:
1. What the app does and how ownership differs from a subscription.
2. Fastest install through GitHub Releases.
3. macOS Gatekeeper, Microphone, and Accessibility steps.
4. Windows SmartScreen, tray, microphone, and shortcut steps.
5. How to get and enter a provider key, with Groq as the easy default, without putting keys in source or `.env`.
6. Fully local macOS setup using whisper.cpp plus Ollama, including model path and hardware expectations.
7. Exact source-build commands for both platforms.
8. GitHub account setup, `gh auth login`, repo creation, and release workflow.
9. Privacy, provider costs, limitations, and where to customize prompts/models/hotkeys.
10. Honest status of anything not manually tested on current hardware.

EXECUTION
1. Inspect the environment and write `docs/build-plan.md`, then continue immediately.
2. Scaffold the entire repo and implement shared contracts/state machine first.
3. Implement macOS end to end, then Windows end to end.
4. Add settings, history, vocabulary, providers, packaging, CI, and docs.
5. Run formatters, static checks, unit tests, release builds, and installer scripts available on the current OS.
6. Fix every reproducible failure. Never fabricate runtime results for unavailable hardware; use CI compilation where necessary and label it honestly.
7. Review for secrets, TODO stubs, fake controls, dead code, unchecked errors, and misleading claims. Remove or complete them.
8. Commit focused changes to main and push if authenticated.

DONE MEANS
- Current-OS app builds and tests pass.
- Other platform compiles/tests in GitHub Actions or is explicitly blocked with exact evidence.
- A user can install, grant permissions, enter a key or configure local mode, dictate, and receive pasted text.
- Provider failure cannot destroy the transcript.
- Installers and CI/release workflows use the same version.
- README setup works for a first-time GitHub user.
- `git status` is clean after final commit.

FINAL RESPONSE
Return only: repository URL/path, commit SHA, platforms verified, real tests/builds run, installer artifact paths/links, known hardware/signing limitations, and first three setup steps. Never claim results you did not execute.
```