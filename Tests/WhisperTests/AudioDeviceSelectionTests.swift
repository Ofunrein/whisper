import XCTest
@testable import Whisper

/// Covers the first-run mic auto-pin. This used to hardcode "Yeti", so a user
/// on any other USB mic got no pin at all and the app silently followed the
/// system default -- which AirPods take over the moment they connect.
final class AudioDeviceSelectionTests: XCTestCase {
    func testPicksFifineOverBuiltInAndBluetooth() {
        let names = ["iMac Microphone", "Martin's AirPods Pro #2", "fifine Microphone"]
        XCTAssertEqual(AudioDevices.preferredDedicatedMic(from: names), "fifine Microphone")
    }

    /// Capture cards, webcams and virtual audio devices all enumerate as
    /// input-capable; none of them is a sane default microphone.
    func testIgnoresCaptureCardsAndVirtualDevices() {
        let names = ["USB3.0 Capture", "Camo Microphone", "WebexMediaAudioDevice", "iMac Microphone"]
        XCTAssertNil(AudioDevices.preferredDedicatedMic(from: names))
    }

    func testNoDedicatedMicLeavesSystemDefault() {
        XCTAssertNil(AudioDevices.preferredDedicatedMic(from: ["iMac Microphone"]))
    }

    /// Device names are not case-normalised by CoreAudio -- the FIFINE reports
    /// itself lowercase as "fifine Microphone".
    func testMatchIsCaseInsensitive() {
        XCTAssertEqual(AudioDevices.preferredDedicatedMic(from: ["FIFINE K669B"]), "FIFINE K669B")
    }

    /// Allow-list order is the preference order: a Yeti wins over a FIFINE
    /// when both are attached, so existing users' pins don't move.
    func testAllowListOrderIsPreferenceOrder() {
        let names = ["fifine Microphone", "Yeti X"]
        XCTAssertEqual(AudioDevices.preferredDedicatedMic(from: names), "Yeti X")
    }
}
