import Foundation

/// File/env-backed provider API key storage.
///
/// This deliberately avoids macOS Keychain by default. Keychain ACLs are bound
/// to the exact app signing identity that created the item, and local dev builds
/// can still trigger repeated "Whisper wants to access..." prompts after rebuilds
/// or after keys were seeded by the `security` CLI. A user-owned 0600 JSON file
/// is boring and never prompts.
enum Keychain {
    private static let fileManager = FileManager.default
    private static let appSupportDirectory: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Whisper", isDirectory: true)
    }()
    private static let secretsURL = appSupportDirectory.appendingPathComponent("secrets.json")

    /// Standard env var names checked before the local secrets file.
    private static let envNames: [String: String] = [
        "groq": "GROQ_API_KEY",
        "elevenlabs": "ELEVENLABS_API_KEY",
        "deepgram": "DEEPGRAM_API_KEY",
        "gemini": "GEMINI_API_KEY",
        "cerebras": "CEREBRAS_API_KEY",
        "openai": "OPENAI_API_KEY",
    ]

    static let groqKey = "groq"
    static let elevenLabsKey = "elevenlabs"
    static let deepgramKey = "deepgram"
    static let geminiKey = "gemini"
    static let cerebrasKey = "cerebras"
    static let openAIKey = "openai"

    static func set(_ value: String, for account: String) {
        set(value, account: account)
    }

    static func set(_ value: String, account: String) {
        var secrets = loadSecrets()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            secrets.removeValue(forKey: account)
        } else {
            secrets[account] = trimmed
        }
        saveSecrets(secrets)
    }

    static func get(_ account: String) -> String? {
        if let value = processEnvValue(for: account) { return value }
        if let value = envFileValue(for: account) { return value }
        return loadSecrets()[account].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// GUI apps launched from Finder do not inherit ~/.zshrc env. On launch,
    /// read login shell env once and seed the local no-prompt secrets file.
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
                    set(value, account: account)
                    NSLog("Whisper: imported \(envName) from login shell into local secrets file")
                }
            }
        }
    }

    /// One-time bootstrap path for keys not in shell profile.
    static func bootstrapFromEnvironment() {
        for (account, _) in envNames {
            guard let value = ProcessInfo.processInfo.environment["WHISPER_BOOTSTRAP_KEY_\(account.uppercased())"],
                  !value.isEmpty else { continue }
            set(value, account: account)
            NSLog("Whisper: bootstrapped \(account) key into local secrets file")
        }
    }

    private static func processEnvValue(for account: String) -> String? {
        if let env = ProcessInfo.processInfo.environment["WHISPER_KEY_\(account.uppercased())"], !env.isEmpty { return env }
        if let name = envNames[account], let env = ProcessInfo.processInfo.environment[name], !env.isEmpty { return env }
        return nil
    }

    private static func envFileValue(for account: String) -> String? {
        guard let name = envNames[account] else { return nil }
        let paths = [
            "\(NSHomeDirectory())/Downloads/atlas/.env",
            "\(NSHomeDirectory())/.codex/.env",
            "\(NSHomeDirectory())/.hermes/.env",
        ]
        for path in paths {
            if let value = parseEnvFile(path: path, key: name), !value.isEmpty { return value }
        }
        return nil
    }

    private static func parseEnvFile(path: String, key: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), line.hasPrefix("\(key)=") else { continue }
            var value = String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value.removeFirst()
                value.removeLast()
            }
            return value
        }
        return nil
    }

    private static func loadSecrets() -> [String: String] {
        guard let data = try? Data(contentsOf: secretsURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return decoded
    }

    private static func saveSecrets(_ secrets: [String: String]) {
        do {
            try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(secrets)
            try data.write(to: secretsURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)
        } catch {
            NSLog("Whisper: failed to save local secrets file: \(error.localizedDescription)")
        }
    }
}
