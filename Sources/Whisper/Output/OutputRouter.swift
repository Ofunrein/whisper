import Foundation
import AppKit
import CoreGraphics

/// Delivers transcribed text to the user: paste at cursor, copy only, or paste and keep.
final class OutputRouter {
    private let pasteDelay: TimeInterval = 0.35
    private let keyHoldDelay: TimeInterval = 0.04
    private let restoreDelay: TimeInterval = 0.3
    private let vKeyCode: CGKeyCode = 9 // "v"

    private static var history: [[(NSPasteboard.PasteboardType, Data)]] = []
    private static let maxHistory = 5

    func deliver(text: String, mode: OutputMode, keepOnClipboard: Bool, targetPID: pid_t? = nil) {
        switch mode {
        case .copyOnly:
            setClipboard(text)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            self.pasteViaCommandV(text: text, targetPID: targetPID)
        }
    }

    private func pasteViaCommandV(text: String, targetPID: pid_t?) {
        guard AXIsProcessTrusted() else {
            NSLog("Whisper: Accessibility permission missing; cannot auto-paste")
            return
        }

        if insertFocusedTextViaAccessibility(text) {
            NSLog("Whisper: auto-paste inserted via AX selected text")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
            ?? CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        post(down, targetPID: targetPID)
        DispatchQueue.main.asyncAfter(deadline: .now() + keyHoldDelay) {
            self.post(up, targetPID: targetPID)
        }
    }

    private func insertFocusedTextViaAccessibility(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return false }

        let element = focused as! AXUIElement
        let selectedStatus = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        return selectedStatus == .success
    }

    private func post(_ event: CGEvent, targetPID: pid_t?) {
        if let targetPID, targetPID > 0 {
            event.postToPid(targetPID)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }
}
