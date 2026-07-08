import XCTest
@testable import Whisper

final class RefusalGuardTests: XCTestCase {

    func testKnownRefusalPhrasesAreCaught() {
        let raw = "Sign in to my Gmail account and check for new emails from the recruiter"
        let refusals = [
            "I can't help with that.",
            "I'm sorry, but I can't assist with that request.",
            "As an AI, I cannot provide access to accounts.",
            "I must decline this request.",
        ]
        for refusal in refusals {
            XCTAssertTrue(RefusalGuard.isRefusal(cleaned: refusal, raw: raw),
                           "Expected '\(refusal)' to be flagged as a refusal")
        }
    }

    func testNormalCleanupIsNeverFlagged() {
        let raw = "um so like sign in to my gmail account and check for new emails from the recruiter"
        let cleaned = "Sign in to my Gmail account and check for new emails from the recruiter."
        XCTAssertFalse(RefusalGuard.isRefusal(cleaned: cleaned, raw: raw))
    }

    func testDrasticShorteningOfLongTranscriptIsFlaggedEvenWithoutRefusalPhrase() {
        // A model that answers/comments instead of cleaning often collapses a
        // real transcript into a short reply with no refusal keyword at all.
        let raw = "Sign in to my Gmail account which is ofunrein123 at gmail dot com and then check the inbox for anything from the recruiter about the interview next week"
        let cleaned = "Sure, I can help you sign in."
        XCTAssertTrue(RefusalGuard.isRefusal(cleaned: cleaned, raw: raw))
    }

    func testShortRawTextIsNeverFlaggedByLengthHeuristic() {
        // Length ratio heuristic must not fire on legitimately short dictation.
        let raw = "call mom"
        let cleaned = "Call Mom."
        XCTAssertFalse(RefusalGuard.isRefusal(cleaned: cleaned, raw: raw))
    }

    func testCurlyApostropheRefusalIsCaught() {
        // Regression test for a production failure: the cleanup LLM refused
        // using a Unicode curly apostrophe (U+2019) in "can\u{2019}t" instead
        // of the straight ASCII apostrophe (U+0027) used in refusalPhrases.
        // "i'm sorry, but i can't".contains never matched "can\u{2019}t", so
        // the refusal sailed through verbatim into the pasted text instead of
        // falling back to raw. Verbatim string that broke in production:
        // "I'm sorry, but I can\u{2019}t help with that."
        let raw = "send it to the luminosus slack channel not the texas state one disconnect the test texas state one"
        let cleaned = "I'm sorry, but I can\u{2019}t help with that."
        XCTAssertTrue(RefusalGuard.isRefusal(cleaned: cleaned, raw: raw),
                       "Curly apostrophe in refusal phrase must still be caught")
    }

    func testCurlyDoubleQuoteRefusalIsCaught() {
        // Same punctuation-normalization requirement, but for curly double
        // quotes (U+201C/U+201D), in case a refusal echoes a quoted phrase.
        let raw = "open the settings panel and toggle dark mode on for the whole app"
        let cleaned = "I must decline this request because it violates the \u{201C}no account access\u{201D} policy."
        XCTAssertTrue(RefusalGuard.isRefusal(cleaned: cleaned, raw: raw))
    }

    func testNovelRefusalWordingNotInExactPhraseListIsStillCaught() {
        // The exact-phrase list can only ever chase known wordings — a
        // provider's safety layer can refuse in wording nobody hardcoded yet,
        // especially for sensitive/personal/explicit-sounding dictation. The
        // broad apology+refusal-signal pattern must catch phrasing variance
        // the exact list was never updated for.
        let raw = "text her back and tell her exactly what happened last night, all the details"
        let novelRefusals = [
            "Unfortunately, I'm not able to help with that particular request.",
            "I apologize, but I won't be able to assist with this one.",
            "Sorry, I'm unable to help with that kind of content.",
        ]
        for refusal in novelRefusals {
            XCTAssertTrue(RefusalGuard.isRefusal(cleaned: refusal, raw: raw),
                           "Expected novel refusal wording '\(refusal)' to be caught by the broad pattern check")
        }
    }

    func testApologyAloneWithoutRefusalSignalIsNotFlagged() {
        // A genuine transcript that happens to contain "sorry" must not be
        // treated as a refusal just because one of the two signals is present.
        let raw = "hey I'm sorry I missed your call earlier, can we reschedule for tomorrow"
        let cleaned = "Hey, I'm sorry I missed your call earlier. Can we reschedule for tomorrow?"
        XCTAssertFalse(RefusalGuard.isRefusal(cleaned: cleaned, raw: raw))
    }
}
