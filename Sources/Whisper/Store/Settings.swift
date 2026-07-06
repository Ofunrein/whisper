import Foundation

enum STTProviderKind: String, Codable, CaseIterable, Identifiable {
    case groq, elevenLabs, deepgram, openAI, localWhisper
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .groq: return "Groq (whisper-large-v3-turbo)"
        case .elevenLabs: return "ElevenLabs Scribe v2"
        case .deepgram: return "Deepgram Nova-3"
        case .openAI: return "OpenAI"
        case .localWhisper: return "Local whisper.cpp"
        }
    }
    var needsKey: Bool { self != .localWhisper }
}

enum CleanupProviderKind: String, Codable, CaseIterable, Identifiable {
    case groq, cerebras, gemini, ollama, openAI
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .cerebras: return "Cerebras"
        case .gemini: return "Gemini Flash"
        case .ollama: return "Ollama (local)"
        case .openAI: return "OpenAI"
        }
    }
    var needsKey: Bool { self != .ollama }
}

enum OutputMode: String, Codable, CaseIterable, Identifiable {
    case pasteAtCursor      // paste, restore previous clipboard
    case copyOnly           // clipboard only, no paste
    case pasteAndKeep       // paste, leave text on clipboard
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .pasteAtCursor: return "Paste at cursor"
        case .copyOnly: return "Copy to clipboard only"
        case .pasteAndKeep: return "Paste and keep on clipboard"
        }
    }
}

enum HotkeyTriggerStyle: String, Codable, CaseIterable, Identifiable {
    case hold, toggle
    var id: String { rawValue }
}

/// What happens to other apps' audio while Whisper is recording.
enum PlaybackDuckMode: String, Codable, CaseIterable, Identifiable {
    case keepPlaying, pause, lower, mute
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .keepPlaying: return "Keep Playing"
        case .pause: return "Pause"
        case .lower: return "Lower"
        case .mute: return "Mute"
        }
    }
}

/// Pill visual style, SuperWhisper-style: full capsule, a smaller mini dot,
/// or hidden entirely (still functions, just no on-screen indicator).
enum PillStyle: String, Codable, CaseIterable, Identifiable {
    case classic, mini, none
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .mini: return "Mini"
        case .none: return "None"
        }
    }
}

/// Selectable start/stop/error sound cue sets, bundled as WAV trios under
/// Resources/Sounds/<rawValue>/. All are soft, low-pitched tones (see
/// SoundPlayer) rather than the sharp default macOS system sounds.
enum SoundSet: String, Codable, CaseIterable, Identifiable {
    case softChime = "soft-chime"
    case subtleClick = "subtle-click"
    case warmTone = "warm-tone"
    case lowPulse = "low-pulse"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .softChime: return "Soft Chime"
        case .subtleClick: return "Subtle Click"
        case .warmTone: return "Warm Tone"
        case .lowPulse: return "Low Pulse"
        }
    }
}

/// How long saved audio recordings are kept before automatic deletion.
enum RecordingRetention: String, Codable, CaseIterable, Identifiable {
    case oneDay, sevenDays, thirtyDays, forever
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .oneDay: return "1 Day"
        case .sevenDays: return "7 Days"
        case .thirtyDays: return "30 Days"
        case .forever: return "Forever"
        }
    }
    var days: Int? {
        switch self {
        case .oneDay: return 1
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .forever: return nil
        }
    }
}

/// A vocabulary entry: either a bare word/phrase to bias transcription toward
/// (spelled exactly as given), or a snippet that expands `from` -> `to`
/// during post-cleanup text replacement.
struct VocabularyEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var from: String
    var to: String?  // nil = plain vocabulary word, not a replacement
}

let defaultVocabulary: [VocabularyEntry] = [
    VocabularyEntry(from: "Ohireme"),
    VocabularyEntry(from: "Ofunrein"),
    VocabularyEntry(from: "Lumenosis"),
    VocabularyEntry(from: "Claude"),
    VocabularyEntry(from: "Anthropic"),
    VocabularyEntry(from: "cmux"),
    VocabularyEntry(from: "Superwhisper"),
    VocabularyEntry(from: "Groq"),
    VocabularyEntry(from: "Cerebras"),
    VocabularyEntry(from: "Ollama"),
    VocabularyEntry(from: "Xcode"),
    VocabularyEntry(from: "SwiftUI"),
    VocabularyEntry(from: "AVAudioEngine"),
    VocabularyEntry(from: "O Hi Re Me", to: "Ohireme"),
    VocabularyEntry(from: "O Hire Me", to: "Ohireme"),
    VocabularyEntry(from: "O Here Me", to: "Ohireme"),
    VocabularyEntry(from: "OJ", to: "Oje"),
    VocabularyEntry(from: "Aima", to: "Aiah"),
]

/// SuperWhisper-style pill placements along the screen edges, plus a
/// free-form custom position set by dragging.
enum PillPlacement: String, Codable, CaseIterable, Identifiable {
    case bottomCenter, bottomLeft, bottomRight
    case topCenter, topLeft, topRight
    case middleLeft, middleRight
    case custom
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .bottomCenter: return "Bottom Center"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .topCenter: return "Top Center"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .middleLeft: return "Middle Left"
        case .middleRight: return "Middle Right"
        case .custom: return "Custom (drag the pill)"
        }
    }
}

/// A configurable binding: either the Fn key, a key combo, a mouse button,
/// or a held secondary (right) click.
struct HotkeyBinding: Codable, Equatable {
    enum Kind: String, Codable { case fnKey, keyCombo, mouseButton, rightClick }
    var kind: Kind
    var keyCode: UInt16?        // for keyCombo
    var modifiers: UInt64?      // CGEventFlags rawValue for keyCombo
    var mouseButton: Int?       // 2 = middle, 3...10 = extra buttons
    var style: HotkeyTriggerStyle

    static let defaultFn = HotkeyBinding(kind: .fnKey, keyCode: nil, modifiers: nil, mouseButton: nil, style: .hold)
    /// Right Command (keycode 54) — the right Windows key on a PC keyboard.
    static let defaultRightCommand = HotkeyBinding(kind: .keyCombo, keyCode: 54, modifiers: 0, mouseButton: nil, style: .hold)
}

let defaultCleanupInstructions = """
You clean up raw speech-to-text transcripts for a dictation app. Output ONLY the cleaned text,
with no preamble, quotes, or commentary.

DO: remove filler words and verbal tics (um, uh, like, you know, sort of, I mean); remove false
starts and self-corrections, keeping only the final thing the speaker landed on; fix
capitalization, spelling, and punctuation; fix obvious grammar slips.

DO: correctly spell technical and proper-noun terms you recognize from training even if the
speech-to-text engine misheard them phonetically — programming languages, frameworks, libraries,
AI models/companies (e.g. Claude, not "Cloud"; GPT; Anthropic; OpenAI), CLI tools, cloud
platforms, and common tech jargon. Prefer the well-known correct spelling of a recognizable term
over a literal phonetic transcription of it.

DO NOT: add any idea, fact, detail, or word the speaker did not say; remove real content
(facts, names, numbers, requests); summarize, shorten, or expand; change the speaker's tone,
wording, or level of formality. Keep their voice. Keep the length about the same.
If something is ambiguous or clearly misheard, leave it as-is rather than guessing.
"""

struct AppSettings: Codable, Equatable {
    static let defaultGeminiModel = "gemini-3.5-flash"
    static let defaultGroqCleanupModel = "openai/gpt-oss-20b"
    static let defaultCerebrasModel = "llama-3.3-70b"
    static let defaultOpenAICleanupModel = "gpt-4o-mini"
    static let defaultOllamaModel = "llama3.2"
    static let defaultOllamaBaseURL = "http://localhost:11434"

    var sttProvider: STTProviderKind = .groq
    var cleanupProvider: CleanupProviderKind = .groq
    var cleanupEnabled: Bool = true
    var cleanupInstructions: String = defaultCleanupInstructions
    var cleanupTimeoutSeconds: Double = 6.0
    var outputMode: OutputMode = .pasteAtCursor
    var keepOnClipboardAfterPaste: Bool = true
    var saveAudio: Bool = false
    var soundEffectsEnabled: Bool = true
    var soundSet: SoundSet = .softChime
    var preferredInputDevice: String? = nil  // nil = system default mic
    var bindings: [HotkeyBinding] = [.defaultRightCommand]
    var rightClickHoldThresholdMs: Double = 1700
    var geminiModel: String = defaultGeminiModel
    var groqCleanupModel: String = defaultGroqCleanupModel
    var cerebrasModel: String = defaultCerebrasModel
    var openAICleanupModel: String = defaultOpenAICleanupModel
    var ollamaModel: String = defaultOllamaModel
    var ollamaBaseURL: String = defaultOllamaBaseURL
    var pillPlacement: PillPlacement = .bottomCenter
    var pillPositionX: Double? = nil
    var pillPositionY: Double? = nil
    var pillStyle: PillStyle = .classic
    var pillAlwaysShow: Bool = true
    var pillScale: Double = 1.0 // 0.6...1.6, multiplies collapsed/expanded pill size
    var playbackDuckMode: PlaybackDuckMode = .lower
    var launchAtLogin: Bool = false
    var recordingRetention: RecordingRetention = .oneDay
    var recordingsDirectory: String? = nil  // nil = default Application Support location
    var vocabulary: [VocabularyEntry] = defaultVocabulary
}

final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    static let shared = SettingsStore()
    private let defaultsKey = "whisper.settings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
