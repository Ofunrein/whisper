import XCTest
import AppKit
@testable import Whisper

final class SnapPlacementTests: XCTestCase {
    private let visible = NSRect(x: 0, y: 0, width: 1600, height: 900)
    private let size = NSSize(width: 56, height: 14)

    func testBottomRowHasFiveDropZones() {
        XCTAssertEqual(placementAt(x: 24, y: 24), .bottomLeft)
        XCTAssertEqual(placementAt(x: 400, y: 24), .bottomQuarter)
        XCTAssertEqual(placementAt(x: 800, y: 24), .bottomCenter)
        XCTAssertEqual(placementAt(x: 1200, y: 24), .bottomThreeQuarter)
        XCTAssertEqual(placementAt(x: 1576, y: 24), .bottomRight)
    }

    func testTopRowHasFiveDropZones() {
        XCTAssertEqual(placementAt(x: 24, y: 876), .topLeft)
        XCTAssertEqual(placementAt(x: 400, y: 876), .topQuarter)
        XCTAssertEqual(placementAt(x: 800, y: 876), .topCenter)
        XCTAssertEqual(placementAt(x: 1200, y: 876), .topThreeQuarter)
        XCTAssertEqual(placementAt(x: 1576, y: 876), .topRight)
    }

    func testSideAndCenterDropZones() {
        XCTAssertEqual(placementAt(x: 24, y: 225), .leftLower)
        XCTAssertEqual(placementAt(x: 24, y: 450), .middleLeft)
        XCTAssertEqual(placementAt(x: 24, y: 675), .leftUpper)
        XCTAssertEqual(placementAt(x: 1576, y: 225), .rightLower)
        XCTAssertEqual(placementAt(x: 1576, y: 450), .middleRight)
        XCTAssertEqual(placementAt(x: 1576, y: 675), .rightUpper)
        XCTAssertEqual(placementAt(x: 800, y: 450), .center)
    }

    func testInteriorDropsStillSnapToNearestSlot() {
        XCTAssertNotEqual(placementAt(x: 520, y: 360), .custom)
        XCTAssertNotEqual(placementAt(x: 1080, y: 570), .custom)
    }

    private func placementAt(x: CGFloat, y: CGFloat) -> PillPlacement {
        let frame = NSRect(x: x - size.width / 2, y: y - size.height / 2, width: size.width, height: size.height)
        return PillController.nearestPlacement(for: frame, in: visible)
    }
}
