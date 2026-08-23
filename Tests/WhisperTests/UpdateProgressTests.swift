import XCTest
@testable import Whisper

final class UpdateProgressTests: XCTestCase {
    func testDownloadFractionMidway() {
        let phase = UpdatePhase.downloading(receivedBytes: 5_000_000, totalBytes: 10_000_000)
        XCTAssertEqual(phase.fractionCompleted ?? -1, 0.5, accuracy: 0.0001)
    }

    /// GitHub asset redirects can omit Content-Length, in which case
    /// URLSession reports -1 (and we seed the phase with 0). Either must render
    /// as an indeterminate bar rather than dividing by a bogus total.
    func testUnknownTotalIsIndeterminate() {
        XCTAssertNil(UpdatePhase.downloading(receivedBytes: 1_024, totalBytes: 0).fractionCompleted)
        XCTAssertNil(UpdatePhase.downloading(receivedBytes: 1_024, totalBytes: -1).fractionCompleted)
    }

    func testFractionIsClamped() {
        let over = UpdatePhase.downloading(receivedBytes: 20, totalBytes: 10)
        XCTAssertEqual(over.fractionCompleted ?? -1, 1.0, accuracy: 0.0001)
    }

    /// Non-download phases are short and unmeasurable, so they must not claim
    /// a determinate fraction.
    func testNonDownloadPhasesHaveNoFraction() {
        for phase in [UpdatePhase.preparing, .mounting, .installing, .relaunching] {
            XCTAssertNil(phase.fractionCompleted, "\(phase) should be indeterminate")
            XCTAssertNil(phase.detail, "\(phase) should have no byte detail")
            XCTAssertFalse(phase.title.isEmpty, "\(phase) needs a user-visible title")
        }
    }

    func testDownloadDetailShowsBothSizes() {
        let detail = UpdatePhase.downloading(receivedBytes: 1_500_000, totalBytes: 3_000_000).detail
        XCTAssertNotNil(detail)
        XCTAssertTrue(detail?.contains(" of ") == true, "expected 'x of y', got \(detail ?? "nil")")
    }

    /// With no known total there's nothing to say "of", so only the received
    /// count is shown.
    func testDownloadDetailWithUnknownTotalOmitsOf() {
        let detail = UpdatePhase.downloading(receivedBytes: 1_500_000, totalBytes: 0).detail
        XCTAssertNotNil(detail)
        XCTAssertFalse(detail?.contains(" of ") == true, "expected received-only, got \(detail ?? "nil")")
    }

    /// The phase is seeded at 0 bytes before the first callback arrives.
    /// ByteCountFormatter renders that as "Zero KB", which shipped visibly in
    /// the progress window until this was caught, so it must stay suppressed.
    func testZeroBytesShowsNoDetail() {
        XCTAssertNil(UpdatePhase.downloading(receivedBytes: 0, totalBytes: 0).detail)
        XCTAssertNil(UpdatePhase.downloading(receivedBytes: 0, totalBytes: 2_900_000).detail)
    }
}
