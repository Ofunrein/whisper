import Foundation
import Security

/// Keychain-backed storage for provider API keys. Keys never touch UserDefaults or files.
enum Keychain {
    private static let service = "com.whisper.dictation"

    static func set(_ value: String, for account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        if value.isEmpty { return }
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Standard env var names, checked as fallback when no Keychain item exists
    /// (e.g. GROQ_API_KEY set in the user's shell profile).
    private static let envNames: [String: String] = [
        "groq": "GROQ_API_KEY",
        "elevenlabs": "ELEVENLABS_API_KEY",
        "deepgram": "DEEPGRAM_API_KEY",
        "gemini": "GEMINI_API_KEY",
        "cerebras": "CEREBRAS_API_KEY",
        "openai": "OPENAI_API_KEY",
    ]

    static func get(_ account: String) -> String? {
        // Env override (e.g. WHISPER_KEY_GROQ) — used by --selftest and CI.
        if let env = ProcessInfo.processInfo.environment["WHISPER_KEY_\(account.uppercased())"],
           !env.isEmpty {
            return env
        }
        if let name = envNames[account],
           let env = ProcessInfo.processInfo.environment[name], !env.isEmpty {
            return env
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Well-known accounts
    static let groqKey = "groq"
    static let elevenLabsKey = "elevenlabs"
    static let deepgramKey = "deepgram"
    static let geminiKey = "gemini"
    static let cerebrasKey = "cerebras"
    static let openAIKey = "openai"

    /// GUI apps don't inherit shell env, so keys exported in ~/.zshrc are
    /// invisible here. On launch, read the login shell's env once and seed
    /// the Keychain with any keys the user hasn't set in Settings yet.
    static func importFromLoginShellEnv() {
        DispatchQueue.global(qos: .utility).async {
            for (account, envName) in envNames {
                guard get(account) == nil else { continue }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-ilc", "printf %s \"$\(envName)\""]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                guard (try? p.run()) != nil else { continue }
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let value = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    set(value, for: account)
                    NSLog("Whisper: imported \(envName) from login shell into Keychain")
                }
            }
        }
    }
}
