import Foundation
import AppKit
import CoreGraphics

/// Delivers transcribed text to the user: paste at cursor (with clipboard
/// restore), copy only, or paste and keep.
final class OutputRouter {
    private let restoreDelay: TimeInterval = 0.3
    private let vKeyCode: CGKeyCode = 9 // "v"

    func deliver(text: String, mode: OutputMode) {
        switch mode {
        case .copyOnly:
            setClipboard(text)
        case .pasteAndKeep:
            setClipboard(text)
            pasteViaCommandV()
        case .pasteAtCursor:
            let saved = snapshotClipboard()
            setClipboard(text)
            pasteViaCommandV()
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) { [weak self] in
                self?.restoreClipboard(saved)
            }
        }
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

    private func pasteViaCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
