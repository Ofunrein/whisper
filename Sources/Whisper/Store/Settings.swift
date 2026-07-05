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

/// SuperWhisper-style pill placements along the screen edges, plus a
/// free-form custom position set by dragging.
enum PillPlacement: String, Codable, CaseIterable, Identifiable {
    case bottomCenter, bottomLeft, bottomRight
    case topCenter, topLeft, topRight
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
        case .custom: return "Custom (drag the pill)"
        }
    }
}

/// A configurable binding: either the Fn key, a key combo, or a mouse button.
struct HotkeyBinding: Codable, Equatable {
    enum Kind: String, Codable { case fnKey, keyCombo, mouseButton }
    var kind: Kind
    var keyCode: UInt16?        // for keyCombo
    var modifiers: UInt64?      // CGEventFlags rawValue for keyCombo
    var mouseButton: Int?       // 2 = middle, 3...10 = extra buttons
    var style: HotkeyTriggerStyle

    static let defaultFn = HotkeyBinding(kind: .fnKey, keyCode: nil, modifiers: nil, mouseButton: nil, style: .hold)
}

let defaultCleanupInstructions = """
You clean up raw speech-to-text transcripts for a dictation app. Output ONLY the cleaned text,
with no preamble, quotes, or commentary.

DO: remove filler words and verbal tics (um, uh, like, you know, sort of, I mean); remove false
starts and self-corrections, keeping only the final thing the speaker landed on; fix
capitalization, spelling, and punctuation; fix obvious grammar slips.

DO NOT: add any idea, fact, detail, or word the speaker did not say; remove real content
(facts, names, numbers, requests); summarize, shorten, or expand; change the speaker's tone,
wording, or level of formality. Keep their voice. Keep the length about the same.
If something is ambiguous or clearly misheard, leave it as-is rather than guessing.
"""

struct AppSettings: Codable, Equatable {
    var sttProvider: STTProviderKind = .groq
    var cleanupProvider: CleanupProviderKind = .groq
    var cleanupEnabled: Bool = true
    var cleanupInstructions: String = defaultCleanupInstructions
    var cleanupTimeoutSeconds: Double = 6.0
    var outputMode: OutputMode = .pasteAtCursor
    var saveAudio: Bool = false
    var soundEffectsEnabled: Bool = true
    var bindings: [HotkeyBinding] = [.defaultFn]
    var geminiModel: String = "gemini-3.5-flash"
    var groqCleanupModel: String = "openai/gpt-oss-20b"
    var cerebrasModel: String = "llama-3.3-70b"
    var openAICleanupModel: String = "gpt-4o-mini"
    var ollamaModel: String = "llama3.2"
    var ollamaBaseURL: String = "http://localhost:11434"
    var pillPlacement: PillPlacement = .bottomCenter
    var pillPositionX: Double? = nil
    var pillPositionY: Double? = nil
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
