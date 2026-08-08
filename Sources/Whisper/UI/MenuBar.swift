import AppKit
import SwiftUI
import Combine

/// Owns the NSStatusItem and its menu.
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    var openHistory: (() -> Void)?
    var openSettings: (() -> Void)?

    private var statusItem: NSStatusItem!
    private var cleanupItem: NSMenuItem!
    private var outputModeItems: [OutputMode: NSMenuItem] = [:]
    private var cancellable: AnyCancellable?

    override init() {
        super.init()
        setup()
        observeSettings()
    }

    private func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Whisper")
        }

        let menu = NSMenu()
        menu.delegate = self

        let cleanup = NSMenuItem(title: "Clean up my speech", action: #selector(toggleCleanup), keyEquivalent: "")
        cleanup.target = self
        menu.addItem(cleanup)
        self.cleanupItem = cleanup

        let outputMenu = NSMenu()
        for mode in OutputMode.allCases {
            let mi = NSMenuItem(title: mode.displayName, action: #selector(selectOutputMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = mode
            outputMenu.addItem(mi)
            outputModeItems[mode] = mi
        }
        let outputParent = NSMenuItem(title: "Output Mode", action: nil, keyEquivalent: "")
        outputParent.submenu = outputMenu
        menu.addItem(outputParent)

        menu.addItem(.separator())

        let historyItem = NSMenuItem(title: "History...", action: #selector(handleOpenHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(handleOpenSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(handleCheckForUpdates), keyEquivalent: "")
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Whisper", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item

        refreshCheckmarks()
    }

    private func observeSettings() {
        cancellable = SettingsStore.shared.$settings.sink { [weak self] _ in
            self?.refreshCheckmarks()
        }
    }

    private func refreshCheckmarks() {
        let settings = SettingsStore.shared.settings
        cleanupItem?.state = settings.cleanupEnabled ? .on : .off
        for (mode, item) in outputModeItems {
            item.state = (mode == settings.outputMode) ? .on : .off
        }
    }

    @objc private func toggleCleanup() {
        SettingsStore.shared.settings.cleanupEnabled.toggle()
    }

    @objc private func selectOutputMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? OutputMode else { return }
        SettingsStore.shared.settings.outputMode = mode
    }

    @objc private func handleOpenHistory() {
        openHistory?()
    }

    @objc private func handleOpenSettings() {
        openSettings?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func handleCheckForUpdates() {
        Task {
            let release = await UpdateChecker.checkForUpdate()
            await MainActor.run {
                presentUpdateResult(release)
            }
        }
    }

    /// Silent background check (app launch): only surfaces UI if a newer
    /// release actually exists. Never nags on "you're up to date."
    func checkForUpdatesSilently() {
        Task {
            guard let release = await UpdateChecker.checkForUpdate() else { return }
            await MainActor.run {
                presentUpdateResult(release)
            }
        }
    }

    private func presentUpdateResult(_ release: UpdateChecker.Release?) {
        let alert = NSAlert()
        if let release {
            alert.messageText = "Update Available"
            alert.informativeText = "Whisper \(release.tagName) is available. You're on \(UpdateChecker.currentVersion)."
            alert.addButton(withTitle: "Download & Install")
            alert.addButton(withTitle: "View Release Page")
            alert.addButton(withTitle: "Later")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                installUpdate(release)
            case .alertSecondButtonReturn:
                if let url = URL(string: release.htmlURL) {
                    NSWorkspace.shared.open(url)
                }
            default:
                break
            }
        } else {
            alert.messageText = "You're up to date"
            alert.informativeText = "Whisper \(UpdateChecker.currentVersion) is the latest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Downloads, installs, and relaunches. On success the app quits itself
    /// (see Updater.relaunch), so there's no "success" UI path to design here
    /// -- only the failure path needs a visible alert.
    private func installUpdate(_ release: UpdateChecker.Release) {
        Task {
            do {
                try await Updater.downloadAndInstall(release)
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Update Failed"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "View Release Page")
                    alert.addButton(withTitle: "OK")
                    if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: release.htmlURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

/// Creates and fronts windows hosting SettingsView / HistoryView, keeping strong
/// references so they aren't deallocated while open.
enum WindowPresenter {
    private static var settingsWindow: NSWindow?
    private static var settingsController: NSHostingController<SettingsView>?

    private static var historyWindow: NSWindow?
    private static var historyController: NSHostingController<HistoryView>?

    static func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(onIdealHeightChange: { height in
                resizeSettingsWindow(toContentHeight: height)
            }))
            let window = NSWindow(contentViewController: controller)
            window.title = "Whisper Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 560, height: 280)
            window.center()
            settingsController = controller
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Snaps the settings window to fit the currently-selected tab's ideal
    /// height (clamped to a sane range), anchoring the top-left corner so it
    /// grows/shrinks downward instead of jumping around the screen. A user's
    /// own manual resize is respected in between tab switches — this only
    /// fires when the ideal height for the *current* tab actually changes.
    private static func resizeSettingsWindow(toContentHeight height: CGFloat) {
        guard let window = settingsWindow else { return }
        let clamped = max(280, min(height, 720))
        var frame = window.frame
        let currentContentHeight = window.contentView?.frame.height ?? frame.height
        guard abs(currentContentHeight - clamped) > 1 else { return }
        let delta = clamped - currentContentHeight
        frame.origin.y -= delta
        frame.size.height += delta
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    static func showHistory() {
        if historyWindow == nil {
            let controller = NSHostingController(rootView: HistoryView())
            let window = NSWindow(contentViewController: controller)
            window.title = "Whisper History"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 520, height: 420))
            window.center()
            historyController = controller
            historyWindow = window
        }
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
