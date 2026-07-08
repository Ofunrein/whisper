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

    /// Maps typographic punctuation that LLMs commonly substitute for the
    /// plain ASCII forms used in `refusalPhrases` (curly single/double quotes)
    /// to their ASCII equivalents. Without this normalization, a model that
    /// writes "can\u{2019}t" (curly apostrophe) instead of "can't" (straight
    /// apostrophe) silently defeats every `.contains` check below — the
    /// phrase list would need a hardcoded duplicate for every possible
    /// punctuation variant of every phrase, which doesn't scale and will
    /// recur. Normalizing the input once, structurally, closes the whole
    /// class of bug instead of one instance of it.
    private static let punctuationNormalization: [Character: Character] = [
        "\u{2019}": "'", // right single quotation mark (curly apostrophe)
        "\u{2018}": "'", // left single quotation mark
        "\u{201C}": "\"", // left double quotation mark
        "\u{201D}": "\"", // right double quotation mark
    ]

    /// Normalizes typographic punctuation to plain ASCII so phrase matching
    /// can't be defeated by a model's choice of curly quotes vs. straight
    /// ones.
    private static func normalizePunctuation(_ text: String) -> String {
        String(text.map { punctuationNormalization[$0] ?? $0 })
    }

    /// Returns true if `cleaned` looks like a refusal/commentary rather than a
    /// cleaned-up version of `raw`, and should therefore be discarded.
    static func isRefusal(cleaned: String, raw: String) -> Bool {
        let lower = normalizePunctuation(cleaned).lowercased()
        if refusalPhrases.contains(where: lower.contains) {
            return true
        }
        // Broad pattern check, not exact-phrase matching: catches refusal
        // wording the exact-phrase list above was never updated for (any
        // provider can phrase a refusal a new way at any time — an exact
        // phrase list can only ever chase known wordings after the fact).
        // This is the actual reason cleanup for sensitive/personal/NSFW-
        // sounding dictation must never be trusted to "just not refuse":
        // the provider's own safety layer can trigger regardless of prompt
        // instructions, in wording nobody hardcoded yet. Two independent
        // apology/refusal signals anywhere in a short response is enough.
        let apologySignals = ["sorry", "apologize", "unfortunately"]
        let refusalSignals = ["can't help", "cannot help", "can't assist",
                               "cannot assist", "can't provide", "cannot provide",
                               "can't do that", "cannot do that", "won't be able",
                               "not able to help", "not able to assist",
                               "unable to help", "unable to assist"]
        let hasApology = apologySignals.contains { lower.contains($0) }
        let hasRefusalSignal = refusalSignals.contains { lower.contains($0) }
        if hasApology && hasRefusalSignal {
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
