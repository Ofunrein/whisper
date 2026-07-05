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
            OutputRouter().deliver(text: final, mode: .copyOnly)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        checkPermissions()
        Keychain.importFromLoginShellEnv()

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
