# Graph Report - whisper  (2026-10-16)

## Corpus Check
- 91 files · ~94,962 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1214 nodes · 1980 edges · 80 communities (66 shown, 14 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 35 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `537cb27e`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]
- [[_COMMUNITY_Community 69|Community 69]]
- [[_COMMUNITY_Community 70|Community 70]]
- [[_COMMUNITY_Community 73|Community 73]]
- [[_COMMUNITY_Community 74|Community 74]]
- [[_COMMUNITY_Community 75|Community 75]]
- [[_COMMUNITY_Community 76|Community 76]]
- [[_COMMUNITY_Community 77|Community 77]]
- [[_COMMUNITY_Community 78|Community 78]]
- [[_COMMUNITY_Community 79|Community 79]]

## God Nodes (most connected - your core abstractions)
1. `AudioRecorder` - 35 edges
2. `PillController` - 29 edges
3. `DeepgramStreamingSession` - 28 edges
4. `SettingsWindow` - 27 edges
5. `PillPlacement` - 24 edges
6. `App` - 24 edges
7. `TrayIcon` - 24 edges
8. `PipelineTests` - 23 edges
9. `MenuBarController` - 21 edges
10. `OutputRouter` - 20 edges

## Surprising Connections (you probably didn't know these)
- `WhisperApp` --implements--> `App`  [EXTRACTED]
  Sources/Whisper/WhisperApp.swift → windows/Whisper.App/App.xaml.cs

## Import Cycles
- None detected.

## Communities (80 total, 14 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.13
Nodes (14): Content, ModelCatalog, Bool, HotkeyTriggerStyle, LocalWhisperModel, SettingsStore, CleanupTab, LocalWhisperSettings (+6 more)

### Community 1 - "Community 1"
Cohesion: 0.09
Nodes (20): Context, NSPanel, NSPoint, NSRect, NSScreen, NSSize, NSTrackingArea, NSView (+12 more)

### Community 2 - "Community 2"
Cohesion: 0.08
Nodes (33): CheckedContinuation, Error, LocalizedError, CleanupProvider, ProviderError, badResponse, http, missingKey (+25 more)

### Community 3 - "Community 3"
Cohesion: 0.08
Nodes (24): CGKeyCode, Notification, NSApplicationDelegate, NSPasteboard, OutputRouter, Scene, Bool, Data (+16 more)

### Community 4 - "Community 4"
Cohesion: 0.09
Nodes (24): AsyncStream, NSObject, Sendable, Bool, Data, Date, Error, Int (+16 more)

### Community 5 - "Community 5"
Cohesion: 0.07
Nodes (24): AnthropicCleanup, GeminiCleanup, OllamaCleanup, OpenAICompatCleanup, CleanupProvider, CleanupProviderKind, String, CleanupProviderKind (+16 more)

### Community 6 - "Community 6"
Cohesion: 0.06
Nodes (8): CGFloat, PillPlacement, AudioDeviceSelectionTests, PlaceholderTests, RefusalGuardTests, SnapPlacementTests, UpdateProgressTests, XCTestCase

### Community 7 - "Community 7"
Cohesion: 0.11
Nodes (17): AVAudioEngine, AVAudioPCMBuffer, Any, AudioRecorder, AudioObjectPropertyListenerBlock, AVAudioConverter, AVAudioFormat, Bool (+9 more)

### Community 8 - "Community 8"
Cohesion: 0.10
Nodes (16): HistoryView, NSHostingController, NSMenuDelegate, NSMenuItem, NSStatusItem, NSWindow, SettingsView, AnyCancellable (+8 more)

### Community 9 - "Community 9"
Cohesion: 0.11
Nodes (20): DeepgramStreamingSession, PillState, DictationPipeline, DictationLatency, LatencyMetrics, AnyCancellable, AppSettings, Bool (+12 more)

### Community 10 - "Community 10"
Cohesion: 0.14
Nodes (11): AudioDevices, PlaybackDucker, AudioObjectID, Float32, OSStatus, AudioDeviceID, AudioObjectPropertyListenerBlock, Bool (+3 more)

### Community 11 - "Community 11"
Cohesion: 0.07
Nodes (22): ICleanupProvider, AnthropicCleanupProvider, GeminiCleanupProvider, OllamaCleanupProvider, OpenAiCompatCleanupProvider, CancellationToken, HttpClient, int (+14 more)

### Community 12 - "Community 12"
Cohesion: 0.11
Nodes (7): RoutedEventArgs, SelectionChangedEventArgs, TextChangedEventArgs, SettingsWindow, bool, HotkeyManager, SettingsStore

### Community 13 - "Community 13"
Cohesion: 0.10
Nodes (17): Application, AudioRecorder, Exception, LaunchActivatedEventArgs, RecordingIndicatorWindow, SettingsWindow, TrayIcon, App (+9 more)

### Community 14 - "Community 14"
Cohesion: 0.07
Nodes (21): ISttProvider, DeepgramSttProvider, ElevenLabsSttProvider, GroqSttProvider, OpenAISttProvider, CancellationToken, HttpClient, string (+13 more)

### Community 15 - "Community 15"
Cohesion: 0.15
Nodes (9): NOTIFYICONDATA, POINT, TrayIcon, DllImport, int, nint, uint, WNDCLASSEX (+1 more)

### Community 16 - "Community 16"
Cohesion: 0.12
Nodes (12): CREDENTIAL, Func, CredentialStore, DllImport, int, AppSettings, CleanupProviderKind, HttpClient (+4 more)

### Community 17 - "Community 17"
Cohesion: 0.17
Nodes (12): Edge, press, release, HotkeyMonitor, Any, Bool, DispatchWorkItem, HotkeyBinding (+4 more)

### Community 18 - "Community 18"
Cohesion: 0.11
Nodes (12): AppWindow, INPUT, PasteService, PointerRoutedEventArgs, ushort, RecordingIndicatorWindow, Window, DllImport (+4 more)

### Community 19 - "Community 19"
Cohesion: 0.13
Nodes (22): Codable, Equatable, Bool, Double, Int, UInt16, AppSettings, HotkeyBinding (+14 more)

### Community 20 - "Community 20"
Cohesion: 0.14
Nodes (11): IDisposable, MemoryStream, MMDevice, MMDeviceEnumerator, object, WasapiCapture, WasapiLoopbackCapture, WaveFormat (+3 more)

### Community 21 - "Community 21"
Cohesion: 0.16
Nodes (15): CaptureError, aggregate, format, ioProc, start, tap, SystemAudioCapture, AudioBufferList (+7 more)

### Community 22 - "Community 22"
Cohesion: 0.19
Nodes (12): ModelCatalog, Provider, anthropic, cerebras, gemini, groq, ollama, openAI (+4 more)

### Community 23 - "Community 23"
Cohesion: 0.19
Nodes (7): HotkeyManager, LowLevelProc, MarshalAs, bool, DllImport, int, nint

### Community 24 - "Community 24"
Cohesion: 0.11
Nodes (19): PillPlacement, bottomCenter, bottomLeft, bottomQuarter, bottomRight, bottomThreeQuarter, center, custom (+11 more)

### Community 26 - "Community 26"
Cohesion: 0.14
Nodes (12): AVAuthorizationStatus, Permissions, Kind, accessibility, microphone, Pane, accessibility, microphone (+4 more)

### Community 27 - "Community 27"
Cohesion: 0.19
Nodes (13): CodingKey, Decodable, Bool, String, Asset, CodingKeys, assets, downloadURL (+5 more)

### Community 28 - "Community 28"
Cohesion: 0.18
Nodes (11): CGEventFlags, ModifierOnlyKeys, ModifierSide, command, control, option, shift, Bool (+3 more)

### Community 29 - "Community 29"
Cohesion: 0.29
Nodes (7): CleanupProviderKind, anthropic, cerebras, gemini, groq, ollama, openAI

### Community 30 - "Community 30"
Cohesion: 0.24
Nodes (5): Date, String, URL, HistoryEntry, HistoryStore

### Community 31 - "Community 31"
Cohesion: 0.33
Nodes (3): String, URL, Keychain

### Community 32 - "Community 32"
Cohesion: 0.29
Nodes (5): CleanupProviderKind, Double, String, FailingCleaner, SlowCleaner

### Community 33 - "Community 33"
Cohesion: 0.27
Nodes (6): Clip, error, start, stop, SoundPlayer, SoundSet

### Community 34 - "Community 34"
Cohesion: 0.32
Nodes (6): Data, String, STTProviderKind, URL, LocalWhisperModel, LocalWhisperTranscriber

### Community 35 - "Community 35"
Cohesion: 0.31
Nodes (6): Asset, UpdateResult, Updater, CancellationToken, Release, Task

### Community 36 - "Community 36"
Cohesion: 0.24
Nodes (9): Double, String, UpdatePhase, downloading, installing, mounting, preparing, relaunching (+1 more)

### Community 37 - "Community 37"
Cohesion: 0.18
Nodes (7): Data, STTProviderKind, BlankTranscriber, FailingTranscriber, GoodTranscriber, SilenceHallucinationTranscriber, SlowTranscriber

### Community 38 - "Community 38"
Cohesion: 0.22
Nodes (9): net8.0, Microsoft.Windows.SDK.BuildTools (10.0.26100.4654), Microsoft.WindowsAppSDK (1.8.260529003), Whisper.App, Whisper.Core, net8.0-windows10.0.19041.0, NAudio (2.2.1), Microsoft.NET.Sdk (+1 more)

### Community 39 - "Community 39"
Cohesion: 0.29
Nodes (5): HTTPCheck, MultipartFormBuilder, Data, String, URLResponse

### Community 40 - "Community 40"
Cohesion: 0.20
Nodes (9): Build locally, Features, Install, Interface, Providers, Release artifacts, Tests, Use (+1 more)

### Community 41 - "Community 41"
Cohesion: 0.33
Nodes (9): cleanup(), key(), keyterms(), main(), make_wav(), normalize(), recognized(), request_json() (+1 more)

### Community 42 - "Community 42"
Cohesion: 0.22
Nodes (8): Constraints (non-negotiable), Goal oracle, Input shape, Interpreted outcome, Likely misfire, Original request, Tranche, Whisper: macOS dictation app

### Community 43 - "Community 43"
Cohesion: 0.28
Nodes (5): UpdateChecker, CancellationToken, Release, string, Task

### Community 44 - "Community 44"
Cohesion: 0.22
Nodes (8): Checking the mic fallback, Getting a build, Known gaps to check first when it's actually running, Layout, Troubleshooting: the app doesn't open, Updates, What's actually wired up vs. stubbed, Whisper for Windows

### Community 45 - "Community 45"
Cohesion: 0.13
Nodes (18): CaseIterable, Identifiable, HotkeyTriggerStyle, hold, toggle, OutputMode, copyOnly, pasteAndKeep (+10 more)

### Community 46 - "Community 46"
Cohesion: 0.46
Nodes (7): main(), make_audio(), multipart(), request_json(), transcribe(), wer(), words()

### Community 47 - "Community 47"
Cohesion: 0.43
Nodes (4): Character, RefusalGuard, Bool, String

### Community 48 - "Community 48"
Cohesion: 0.29
Nodes (3): JsonSerializerOptions, SettingsStore, string

### Community 49 - "Community 49"
Cohesion: 0.48
Nodes (3): VocabularyEngine, String, VocabularyEntry

### Community 50 - "Community 50"
Cohesion: 0.33
Nodes (5): Data, String, STTProviderKind, ElevenLabsTranscriber, TranscriptionProvider

### Community 51 - "Community 51"
Cohesion: 0.40
Nodes (4): Data, String, STTProviderKind, GroqTranscriber

### Community 52 - "Community 52"
Cohesion: 0.40
Nodes (4): Data, String, STTProviderKind, OpenAITranscriber

### Community 54 - "Community 54"
Cohesion: 0.40
Nodes (3): ICleanupProvider, CancellationToken, Task

### Community 55 - "Community 55"
Cohesion: 0.40
Nodes (3): ISttProvider, CancellationToken, Task

### Community 56 - "Community 56"
Cohesion: 0.40
Nodes (3): LocalWhisperModel, URL, LocalWhisperDownloader

### Community 57 - "Community 57"
Cohesion: 0.40
Nodes (5): Kind, fnKey, keyCombo, mouseButton, rightClick

### Community 58 - "Community 58"
Cohesion: 0.40
Nodes (5): PlaybackDuckMode, keepPlaying, lower, mute, pause

### Community 59 - "Community 59"
Cohesion: 0.15
Nodes (16): ObservableObject, CGFloat, Float, Int, IdleDotsView, PillContentView, PillLevelModel, PillState (+8 more)

### Community 60 - "Community 60"
Cohesion: 0.50
Nodes (3): net8.0-windows10.0.19041.0, NAudio (2.2.1), Microsoft.NET.Sdk

### Community 73 - "Community 73"
Cohesion: 0.24
Nodes (6): HotkeyMonitor, Int, NSEvent, String, TimeInterval, HotkeyMonitorTests

### Community 74 - "Community 74"
Cohesion: 0.15
Nodes (12): Hashable, PreferenceKey, CGFloat, Void, SettingsTab, apiKeys, cleanup, hotkey (+4 more)

### Community 75 - "Community 75"
Cohesion: 0.29
Nodes (7): Binding, Set, Int, String, APIKeysTab, vocabulary, VocabularyTab

### Community 76 - "Community 76"
Cohesion: 0.33
Nodes (4): Any, HotkeyBinding, UInt16, HotkeyTab

### Community 77 - "Community 77"
Cohesion: 0.33
Nodes (5): HistoryEntry, Bool, String, HistoryRow, HistoryView

## Knowledge Gaps
- **343 isolated node(s):** `OSStatus`, `Bool`, `AVAudioFormat`, `Date`, `Any` (+338 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **14 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PillController` connect `Community 1` to `Community 59`, `Community 4`?**
  _High betweenness centrality (0.121) - this node is a cross-community bridge._
- **Why does `UInt64` connect `Community 19` to `Community 32`, `Community 9`, `Community 76`?**
  _High betweenness centrality (0.090) - this node is a cross-community bridge._
- **Why does `AppDelegate` connect `Community 3` to `Community 4`?**
  _High betweenness centrality (0.074) - this node is a cross-community bridge._
- **What connects `OSStatus`, `Bool`, `AVAudioFormat` to the rest of the system?**
  _343 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.13157894736842105 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.08695652173913043 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.08067375886524823 - nodes in this community are weakly interconnected._