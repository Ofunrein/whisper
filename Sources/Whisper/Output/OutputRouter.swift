import Foundation
import AppKit
import CoreGraphics

/// Delivers transcribed text to the user: paste at cursor (with clipboard
/// restore), copy only, or paste and keep.
final class OutputRouter {
    private let pasteDelay: TimeInterval = 0.35
    private let keyHoldDelay: TimeInterval = 0.04
    private let restoreDelay: TimeInterval = 0.3
    private let vKeyCode: CGKeyCode = 9 // "v"

    /// Clipboard snapshots from before each paste, most recent last. A
    /// dedicated Cmd+Shift+Z hotkey (ClipboardRestoreMonitor) pops these back
    /// onto the pasteboard — a safety net if a dictation paste overwrote
    /// something the user still needed, without touching the system Cmd+Z.
    private static var history: [[(NSPasteboard.PasteboardType, Data)]] = []
    private static let maxHistory = 5

    func deliver(text: String, mode: OutputMode, keepOnClipboard: Bool) {
        switch mode {
        case .copyOnly:
            setClipboard(text)
        case .pasteAndKeep:
            setClipboard(text)
            pasteAfterClipboardSettles()
        case .pasteAtCursor:
            let saved = snapshotClipboard()
            Self.history.append(saved)
            if Self.history.count > Self.maxHistory { Self.history.removeFirst() }
            setClipboard(text)
            pasteAfterClipboardSettles()
            guard !keepOnClipboard else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay + restoreDelay) {
                self.restoreClipboard(saved)
            }
        }
    }

    /// Pops the most recent pre-paste clipboard snapshot back onto the
    /// pasteboard. Returns false if there's nothing to restore.
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

    // MARK: - Clipboard

    private func setClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Best-effort snapshot of the current pasteboard: capture data for every
    /// type currently present so we can put it back afterward.
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

    // MARK: - Paste synthesis

    private func pasteAfterClipboardSettles() {
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            self.pasteViaCommandV()
        }
    }

    private func pasteViaCommandV() {
        guard AXIsProcessTrusted() else {
            NSLog("Whisper: Accessibility permission missing; cannot auto-paste")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
            ?? CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + keyHoldDelay) {
            up.post(tap: .cghidEventTap)
        }
    }
}
