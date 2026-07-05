import Foundation
import AVFoundation
import AppKit
import ApplicationServices

/// Guidance shown in the UI when a required permission is missing.
struct PermissionGuidance: Identifiable {
    enum Kind: String { case microphone, accessibility }
    var id: String { kind.rawValue }
    let kind: Kind
    let title: String
    let whatToClick: String
    let settingsPane: Permissions.Pane
}

enum Permissions {
    enum Pane: String {
        case microphone = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    }

    // MARK: - Microphone

    static func microphoneStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    // MARK: - Accessibility (needed for the event tap + synthetic Cmd+V)

    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Settings deep links

    static func openSystemSettings(pane: Pane) {
        guard let url = URL(string: pane.rawValue) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Guidance

    static func guidance(for kind: PermissionGuidance.Kind) -> PermissionGuidance {
        switch kind {
        case .microphone:
            return PermissionGuidance(
                kind: .microphone,
                title: "Microphone access is required to record.",
                whatToClick: "Enable Whisper under Privacy & Security → Microphone.",
                settingsPane: .microphone)
        case .accessibility:
            return PermissionGuidance(
                kind: .accessibility,
                title: "Accessibility access is required for the hotkey and paste.",
                whatToClick: "Enable Whisper under Privacy & Security → Accessibility.",
                settingsPane: .accessibility)
        }
    }
}
