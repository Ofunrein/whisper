import XCTest
@testable import Whisper

final class PlaceholderTests: XCTestCase {
    func testSettingsDefaults() {
        let s = AppSettings()
        XCTAssertEqual(s.sttProvider, .groq)
        XCTAssertTrue(s.cleanupEnabled)
        XCTAssertEqual(s.outputMode, .pasteAtCursor)
        XCTAssertTrue(s.cleanupInstructions.contains("Output ONLY the cleaned text"))
    }
}
