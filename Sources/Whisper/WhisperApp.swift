import SwiftUI
import AppKit
import Combine

@main
struct WhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pipeline = DictationPipeline()
    private let hotkeys = HotkeyMonitor()
    private var settingsCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        checkPermissions()

        // Menu bar
        MenuBarController.shared.openSettings = { WindowPresenter.showSettings() }
        MenuBarController.shared.openHistory = { WindowPresenter.showHistory() }

        // Pill
        PillController.shared.show()
        PillController.shared.setState(.collapsed)
        pipeline.onStateChange = { state in
            PillController.shared.setState(state == .idle ? .collapsed : state)
        }

        // Hotkeys
        hotkeys.updateBindings(SettingsStore.shared.settings.bindings)
        hotkeys.onRecordStart = { [weak self] in self?.pipeline.recordStart() }
        hotkeys.onRecordStop = { [weak self] in self?.pipeline.recordStop() }
        hotkeys.start()

        // Keep bindings + pill placement in sync with Settings edits.
        settingsCancellable = SettingsStore.shared.$settings
            .removeDuplicates()
            .sink { [weak self] settings in
                self?.hotkeys.updateBindings(settings.bindings)
                if settings.pillPlacement != .custom {
                    PillController.shared.applyPlacement(settings.pillPlacement)
                }
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.stop()
    }

    /// Only ever nag the user once. After that, permissions are checked
    /// silently (no OS prompt, no alert) so a rebuild/relaunch never asks
    /// again for something already granted or already declined.
    private static let hasPromptedKey = "whisper.hasPromptedForPermissionsOnce"

    private func checkPermissions() {
        let micOK = Permissions.microphoneStatus() == .authorized
        // Never pass prompt:true here: that triggers the native OS Accessibility
        // dialog on every single launch until the user grants it. Check silently;
        // only steer them to System Settings ourselves, and only once.
        let axOK = Permissions.accessibilityTrusted(prompt: false)
        guard !micOK || !axOK else { return }

        let alreadyPrompted = UserDefaults.standard.bool(forKey: Self.hasPromptedKey)
        guard !alreadyPrompted else {
            NSLog("Whisper: permissions still missing (mic=\(micOK), accessibility=\(axOK)); not re-prompting, see menu bar / Settings.")
            return
        }
        UserDefaults.standard.set(true, forKey: Self.hasPromptedKey)

        var missing: [PermissionGuidance] = []
        if !micOK {
            Permissions.requestMicrophone { _ in }
            missing.append(Permissions.guidance(for: .microphone))
        }
        if !axOK {
            missing.append(Permissions.guidance(for: .accessibility))
        }

        let alert = NSAlert()
        alert.messageText = "Whisper needs permissions"
        alert.informativeText = missing
            .map { "\($0.title)\n\($0.whatToClick)" }
            .joined(separator: "\n\n")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn, let first = missing.first {
            Permissions.openSystemSettings(pane: first.settingsPane)
        }
    }
}
