import Foundation

/// Applies user-configured vocabulary to a transcript: known terms are fed to
/// the cleanup model as a spelling hint, and explicit from -> to pairs are
/// applied as a literal, case-insensitive, whole-word replacement pass that
/// runs regardless of whether cleanup is enabled (it fixes STT mishears the
/// cleanup model may not catch, e.g. a misheard name).
enum VocabularyEngine {
    /// Appended to the cleanup system instruction so the model spells these
    /// terms correctly instead of guessing from the phonetic transcript.
    static func hint(for vocabulary: [VocabularyEntry]) -> String? {
        let plainTerms = vocabulary.filter { $0.to == nil }.map(\.from)
        guard !plainTerms.isEmpty else { return nil }
        return "\n\nKnown terms — spell these exactly as given whenever the speaker says something " +
            "that sounds like one of them: " + plainTerms.joined(separator: ", ") + "."
    }

    /// Runs each from -> to replacement pair over the text, case-insensitive,
    /// whole-word/phrase matched so short terms (e.g. "OJ") don't clobber
    /// substrings inside unrelated words.
    static func applyReplacements(_ text: String, vocabulary: [VocabularyEntry]) -> String {
        var result = text
        for entry in vocabulary {
            guard let to = entry.to, !entry.from.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: entry.from)
            guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: .caseInsensitive) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: to)
        }
        return result
    }
}
