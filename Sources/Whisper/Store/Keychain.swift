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

    static func get(_ account: String) -> String? {
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
}
