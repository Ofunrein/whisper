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

    private func checkPermissions() {
        var missing: [PermissionGuidance] = []
        if Permissions.microphoneStatus() != .authorized {
            Permissions.requestMicrophone { _ in }
            missing.append(Permissions.guidance(for: .microphone))
        }
        if !Permissions.accessibilityTrusted(prompt: true) {
            missing.append(Permissions.guidance(for: .accessibility))
        }
        guard !missing.isEmpty else { return }

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
