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
}
