import XCTest
@testable import Whisper

final class PlaceholderTests: XCTestCase {
    func testSettingsDefaults() {
        let s = AppSettings()
        XCTAssertEqual(s.sttProvider, .deepgram)
        XCTAssertTrue(s.cleanupEnabled)
        XCTAssertEqual(s.rightClickHoldThresholdMs, 100)
        XCTAssertEqual(s.outputMode, .pasteAtCursor)
        XCTAssertTrue(s.cleanupInstructions.contains("Output ONLY the cleaned text"))
    }
}
