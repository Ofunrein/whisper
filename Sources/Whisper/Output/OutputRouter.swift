import Foundation
import AppKit
import CoreGraphics

/// Delivers transcribed text: paste at cursor, copy only, or paste and keep.
final class OutputRouter {
    private let pasteDelay: TimeInterval = 0.75
    private let keyHoldDelay: TimeInterval = 0.06
    private let restoreDelay: TimeInterval = 0.8
    private let commandKeyCode: CGKeyCode = 55
    private let vKeyCode: CGKeyCode = 9

    private static var history: [[(NSPasteboard.PasteboardType, Data)]] = []
    private static let maxHistory = 5

    func deliver(text: String, mode: OutputMode, keepOnClipboard: Bool, targetPID: pid_t? = nil) {
        logPaste("deliver mode=\(mode.rawValue) target=\(targetPID.map(String.init) ?? "nil") bytes=\(text.utf8.count)")
        switch mode {
        case .copyOnly:
            setClipboard(text)
            logPaste("copyOnly clipboard set")
        case .pasteAndKeep:
            setClipboard(text)
            pasteAfterClipboardSettles(text: text, targetPID: targetPID)
        case .pasteAtCursor:
            let saved = snapshotClipboard()
            Self.history.append(saved)
            if Self.history.count > Self.maxHistory { Self.history.removeFirst() }
            setClipboard(text)
            pasteAfterClipboardSettles(text: text, targetPID: targetPID)
            guard !keepOnClipboard else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay + restoreDelay) {
                self.restoreClipboard(saved)
                self.logPaste("clipboard restored")
            }
        }
    }

    static func restorePreviousClipboard() -> Bool {
        guard let last = history.popLast() else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !last.isEmpty else { return true }
        pb.declareTypes(last.map { $0.0 }, owner: nil)
        for (type, data) in last {
            pb.setData(data, forType: type)
        }
        return true
    }

    func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private func setClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func snapshotClipboard() -> [(NSPasteboard.PasteboardType, Data)] {
        let pb = NSPasteboard.general
        guard let types = pb.types else { return [] }
        var saved: [(NSPasteboard.PasteboardType, Data)] = []
        for type in types {
            if let data = pb.data(forType: type) {
                saved.append((type, data))
            }
        }
        return saved
    }

    private func restoreClipboard(_ saved: [(NSPasteboard.PasteboardType, Data)]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !saved.isEmpty else { return }
        pb.declareTypes(saved.map { $0.0 }, owner: nil)
        for (type, data) in saved {
            pb.setData(data, forType: type)
        }
    }

    private func pasteAfterClipboardSettles(text: String, targetPID: pid_t?) {
        activateTarget(targetPID)
        waitForTargetThenPaste(targetPID: targetPID, attemptsRemaining: 30)
    }

    private func waitForTargetThenPaste(targetPID: pid_t?, attemptsRemaining: Int) {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if targetPID == nil || frontPID == targetPID || attemptsRemaining <= 0 {
            pasteViaCommandV(targetPID: targetPID)
            return
        }
        activateTarget(targetPID)
        logPaste("waiting for target front front=\(frontPID.map(String.init) ?? "nil") target=\(targetPID.map(String.init) ?? "nil") attempts=\(attemptsRemaining)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.waitForTargetThenPaste(targetPID: targetPID, attemptsRemaining: attemptsRemaining - 1)
        }
    }

    private func pasteViaCommandV(targetPID: pid_t?) {
        guard Permissions.accessibilityTrusted(prompt: true) else {
            logPaste("blocked: Accessibility permission missing; prompted user")
            NSLog("Whisper: Accessibility permission missing; prompted user")
            return
        }

        let front = NSWorkspace.shared.frontmostApplication
        logPaste("posting command-v front=\(front?.localizedName ?? "nil") frontPID=\(front?.processIdentifier.description ?? "nil") target=\(targetPID.map(String.init) ?? "nil")")
        postExplicitCommandV()
        NSLog("Whisper: auto-paste sent explicit Command-V chord")
    }

    private func activateTarget(_ targetPID: pid_t?) {
        guard let targetPID,
              targetPID > 0,
              let target = NSRunningApplication(processIdentifier: targetPID),
              target.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        target.activate()
        logPaste("activate target=\(target.localizedName ?? "nil") pid=\(targetPID)")
    }

    private func postExplicitCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
            ?? CGEventSource(stateID: .combinedSessionState)
        guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: false) else {
            logPaste("failed: could not create CGEvents")
            return
        }

        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandUp.flags = []

        commandDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + keyHoldDelay) { vDown.post(tap: .cghidEventTap) }
        DispatchQueue.main.asyncAfter(deadline: .now() + keyHoldDelay * 2) { vUp.post(tap: .cghidEventTap) }
        DispatchQueue.main.asyncAfter(deadline: .now() + keyHoldDelay * 3) { commandUp.post(tap: .cghidEventTap) }
    }

    private func logPaste(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Whisper", isDirectory: true) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("paste-debug.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
