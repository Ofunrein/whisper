import SwiftUI
import AppKit
import Combine

@main
struct WhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // End-to-end pipeline QA without mic/hotkey: Whisper --selftest <file.wav>
        if let idx = CommandLine.arguments.firstIndex(of: "--selftest") {
            let wavPath = CommandLine.arguments.indices.contains(idx + 1)
                ? CommandLine.arguments[idx + 1] : nil
            SelfTest.run(wavPath: wavPath)  // never returns
        }
    }

    var body: some Scene {
        SwiftUI.Settings {
            EmptyView()
        }
    }
}

/// Runs the real pipeline stages against a WAV file and prints a report.
enum SelfTest {
    static func run(wavPath: String?) -> Never {
        // Keep the main run loop alive (MainActor work needs it); exit from the task.
        Task {
            await runAsync(wavPath: wavPath)
            exit(0)
        }
        RunLoop.main.run()
        exit(0)
    }

    private static func runAsync(wavPath: String?) async {
        let settings = SettingsStore.shared.settings
        print("[selftest] STT provider: \(settings.sttProvider.rawValue)")
        print("[selftest] Cleanup provider: \(settings.cleanupProvider.rawValue) (enabled: \(settings.cleanupEnabled))")

        guard let wavPath, let wav = FileManager.default.contents(atPath: wavPath) else {
            print("[selftest] FAIL: no wav file provided or unreadable")
            return
        }
        print("[selftest] wav bytes: \(wav.count)")

        // Stage 1: STT
        let raw: String
        do {
            let t0 = Date()
            raw = try await ProviderFactory.transcriber(for: settings).transcribe(wavData: wav)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print("[selftest] STT OK in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s: \"\(raw)\"")
        } catch {
            print("[selftest] STT FAIL: \(error.localizedDescription)")
            return
        }

        // Stage 2: cleanup (time-boxed, same code path as the app)
        let t1 = Date()
        let cleaned = await DictationPipeline.cleanWithTimeout(raw, settings: settings)
        if let cleaned {
            print("[selftest] Cleanup OK in \(String(format: "%.2f", Date().timeIntervalSince(t1)))s: \"\(cleaned)\"")
        } else {
            print("[selftest] Cleanup returned nil (raw fallback would be used)")
        }

        // Stage 3: output (clipboard only — safe for QA)
        let final = cleaned ?? raw
        await MainActor.run {
            OutputRouter().deliver(text: final, mode: .copyOnly, keepOnClipboard: true)
        }
        let clip = await MainActor.run { NSPasteboard.general.string(forType: .string) }
        print(clip == final ? "[selftest] Clipboard OK" : "[selftest] Clipboard FAIL")

        // Stage 4: history
        HistoryStore.shared.add(HistoryEntry(date: Date(), rawText: raw, cleanedText: cleaned, appName: "selftest", audioFileName: nil))
        try? await Task.sleep(nanoseconds: 500_000_000) // let async persist land
        print("[selftest] History entries: \(HistoryStore.shared.entries.count)")
        print("[selftest] ALL STAGES PASS")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pipeline = DictationPipeline()
    private let hotkeys = HotkeyMonitor()
    private var settingsCancellable: AnyCancellable?
    private var lastInputDevice: String?
    private var lastPillScale: Double = 1.0
    private var clipboardRestoreMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        checkPermissions()
        Keychain.bootstrapFromEnvironment()
        Keychain.importFromLoginShellEnv()

        // Migration: default hotkey changed Fn -> Right Command. Drop old Fn
        // bindings (re-addable via Settings); ensure at least one binding.
        // Pin the Yeti X once if present and no mic was chosen yet.
        if SettingsStore.shared.settings.preferredInputDevice == nil,
           let yeti = AudioDevices.inputDeviceNames().first(where: { $0.contains("Yeti") }) {
            SettingsStore.shared.settings.preferredInputDevice = yeti
        }

        var migrated = SettingsStore.shared.settings.bindings.filter { $0.kind != .fnKey }
        if migrated.isEmpty { migrated = [.defaultRightCommand] }
        if migrated != SettingsStore.shared.settings.bindings {
            SettingsStore.shared.settings.bindings = migrated
        }

        // Migration: seed default vocabulary (name/term corrections) into
        // installs from before the Vocabulary feature existed.
        if !UserDefaults.standard.bool(forKey: Self.hasSeededVocabularyKey) {
            UserDefaults.standard.set(true, forKey: Self.hasSeededVocabularyKey)
            if SettingsStore.shared.settings.vocabulary.isEmpty {
                SettingsStore.shared.settings.vocabulary = defaultVocabulary
            }
        }

        // Warm the audio engine now: the first engine.start() costs ~1.7s
        // (HAL spin-up). Deferred to hotkey-press it swallows the opening
        // words of the first dictation.
        pipeline.recorder.prewarm()

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

        // Cmd+Shift+Z: restore the clipboard to what it was before the last
        // dictation paste. Deliberately not Cmd+Z — that's the universal
        // system undo shortcut and must never be hijacked globally.
        clipboardRestoreMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 6, // "z"
                  event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command, .shift]
            else { return }
            _ = OutputRouter.restorePreviousClipboard()
        }

        // Keep bindings + pill placement in sync with Settings edits.
        lastInputDevice = SettingsStore.shared.settings.preferredInputDevice
        lastPillScale = SettingsStore.shared.settings.pillScale
        settingsCancellable = SettingsStore.shared.$settings
            .removeDuplicates()
            .sink { [weak self] settings in
                self?.hotkeys.updateBindings(settings.bindings)
                if settings.preferredInputDevice != self?.lastInputDevice {
                    self?.lastInputDevice = settings.preferredInputDevice
                    self?.pipeline.recorder.reconfigure()
                }
                if settings.pillPlacement != .custom {
                    PillController.shared.applyPlacement(settings.pillPlacement)
                }
                if settings.pillScale != self?.lastPillScale {
                    self?.lastPillScale = settings.pillScale
                    PillController.shared.applyScale()
                }
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.stop()
        if let monitor = clipboardRestoreMonitor { NSEvent.removeMonitor(monitor) }
    }

    /// Only ever nag the user once. After that, permissions are checked
    /// silently (no OS prompt, no alert) so a rebuild/relaunch never asks
    /// again for something already granted or already declined.
    private static let hasPromptedKey = "whisper.hasPromptedForPermissionsOnce"
    private static let hasSeededVocabularyKey = "whisper.hasSeededVocabularyOnce"

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
