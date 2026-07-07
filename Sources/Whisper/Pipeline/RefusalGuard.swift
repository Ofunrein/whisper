import Foundation

/// Deterministic, provider-agnostic check that the cleanup LLM handed back a
/// cleaned transcript and not a refusal/disclaimer/commentary. This exists
/// because a system prompt can never *guarantee* a model won't refuse — the
/// only reliable fix is to detect refusal-shaped output after the fact and
/// discard it, falling back to the raw transcript. No exceptions, no config
/// flag to disable it: a refusal is always a pipeline failure, never a valid
/// cleaned result.
enum RefusalGuard {
    /// Substrings that show up in near-universal refusal/disclaimer phrasing
    /// across providers (OpenAI, Anthropic, Gemini, Groq, local Ollama models).
    /// Matched case-insensitively against the whole cleaned string.
    private static let refusalPhrases: [String] = [
        "i can't help with that",
        "i cannot help with that",
        "i can't assist with that",
        "i cannot assist with that",
        "i'm not able to help with that",
        "i am not able to help with that",
        "i can't provide",
        "i cannot provide",
        "i won't be able to",
        "as an ai", "as a language model",
        "i'm sorry, but i can't",
        "i'm sorry, but i cannot",
        "i must decline",
        "i'm unable to comply",
        "this request violates",
        "against my guidelines",
        "i don't feel comfortable",
    ]

    /// Returns true if `cleaned` looks like a refusal/commentary rather than a
    /// cleaned-up version of `raw`, and should therefore be discarded.
    static func isRefusal(cleaned: String, raw: String) -> Bool {
        let lower = cleaned.lowercased()
        if refusalPhrases.contains(where: lower.contains) {
            return true
        }
        // A cleaned transcript should be roughly the same length as the raw
        // one (filler-word removal shrinks it a bit, nothing more). A model
        // that collapses a real transcript down to a one-line reply is
        // answering/refusing instead of formatting — e.g. raw is 40 words and
        // cleaned is "Sure, I can help you sign in." (5 words).
        let rawWords = raw.split(separator: " ").count
        let cleanedWords = cleaned.split(separator: " ").count
        if rawWords >= 6 && cleanedWords > 0 && cleanedWords < rawWords / 3 {
            return true
        }
        return false
    }
}
