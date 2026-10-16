import AppKit
import XCTest
@testable import Whisper

final class HotkeyMonitorTests: XCTestCase {
    private var monitor: HotkeyMonitor!
    private var edges: [String] = []
    private var holdDuration: TimeInterval {
        SettingsStore.shared.settings.rightClickHoldThresholdMs / 1000
    }

    override func setUp() {
        super.setUp()
        edges = []
        monitor = HotkeyMonitor(bindings: [
            HotkeyBinding(kind: .rightClick, keyCode: nil, modifiers: nil, mouseButton: nil, style: .hold)
        ])
        monitor.onRecordStart = { [weak self] in self?.edges.append("start") }
        monitor.onRecordStop = { [weak self] in self?.edges.append("stop") }
    }

    override func tearDown() {
        monitor.stop()
        pump(0.02)
        monitor = nil
        super.tearDown()
    }

    func testSuccessiveHoldsStartWithoutDoubleClickCooldown() {
        for click in 1...3 {
            let timestamp = Double(click) * (holdDuration + 0.06)
            send(.rightMouseDown, at: timestamp, clickCount: 1)
            pump(holdDuration + 0.05)
            send(.rightMouseUp, at: timestamp + holdDuration + 0.05, clickCount: 1)
            pump(0.01)
        }
        XCTAssertEqual(edges, ["start", "stop", "start", "stop", "start", "stop"])
    }

    func testHeldSecondAndThirdClicksStart() {
        for click in 1...3 {
            let timestamp = Double(click) * (holdDuration + 0.06)
            send(.rightMouseDown, at: timestamp, clickCount: click)
            pump(holdDuration + 0.05)
            send(.rightMouseUp, at: timestamp + holdDuration + 0.05, clickCount: click)
            pump(0.01)
        }
        XCTAssertEqual(edges, ["start", "stop", "start", "stop", "start", "stop"])
    }

    func testHoldImmediatelyAfterQuickClickStarts() {
        send(.rightMouseDown, at: 1, clickCount: 1)
        send(.rightMouseUp, at: 1.01, clickCount: 1)
        send(.rightMouseDown, at: 1.02, clickCount: 2)
        pump(holdDuration + 0.05)
        XCTAssertEqual(edges, ["start"])
        send(.rightMouseUp, at: 1.02 + holdDuration + 0.05, clickCount: 2)
        pump(0.01)
        XCTAssertEqual(edges, ["start", "stop"])
    }

    func testQuickDoubleClickDoesNotRecord() {
        for click in 1...2 {
            let timestamp = Double(click) * 0.02
            send(.rightMouseDown, at: timestamp, clickCount: click)
            send(.rightMouseUp, at: timestamp + 0.01, clickCount: click)
        }
        pump(holdDuration + 0.05)
        XCTAssertEqual(edges, [])
    }

    func testHoldStillWaitsForConfiguredThreshold() {
        send(.rightMouseDown, at: 1, clickCount: 1)
        pump(holdDuration / 2)
        XCTAssertEqual(edges, [])
        pump(holdDuration / 2 + 0.05)
        XCTAssertEqual(edges, ["start"])
        send(.rightMouseUp, at: 1 + holdDuration + 0.05, clickCount: 1)
        pump(0.01)
        XCTAssertEqual(edges, ["start", "stop"])
    }

    private func send(_ type: NSEvent.EventType, at timestamp: TimeInterval, clickCount: Int) {
        let event = NSEvent.mouseEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: timestamp,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 0
        )!
        monitor.handle(event)
    }

    private func pump(_ duration: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    }
}
