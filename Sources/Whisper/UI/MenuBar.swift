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
            let controller = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "Whisper Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsController = controller
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
