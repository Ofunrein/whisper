import Foundation

/// Where a self-update currently is.
///
/// `Updater.downloadAndInstall` used to run silently: the "Update Available"
/// alert dismissed and then nothing visible happened until the app abruptly
/// quit and relaunched, which reads as a hang (a release DMG is tens of MB).
/// These phases drive `UpdateProgressView` so the user sees the download
/// filling and the install happening.
enum UpdatePhase: Equatable {
    case preparing
    case downloading(receivedBytes: Int64, totalBytes: Int64)
    case mounting
    case installing
    case relaunching

    /// 0...1 when the phase has a measurable size, else nil for phases that
    /// should render as an indeterminate bar.
    var fractionCompleted: Double? {
        switch self {
        case .downloading(let received, let total):
            // A server that omits Content-Length reports -1; treat as unknown
            // rather than dividing by it.
            guard total > 0 else { return nil }
            return min(1, max(0, Double(received) / Double(total)))
        case .preparing, .mounting, .installing, .relaunching:
            return nil
        }
    }

    var title: String {
        switch self {
        case .preparing: return "Preparing update…"
        case .downloading: return "Downloading update…"
        case .mounting: return "Opening disk image…"
        case .installing: return "Installing…"
        case .relaunching: return "Restarting Whisper…"
        }
    }

    /// Secondary line, e.g. "12.3 MB of 48 MB". Nil when there's nothing
    /// meaningful to add beyond `title`.
    var detail: String? {
        guard case .downloading(let received, let total) = self else { return nil }
        // Before the first byte lands there's nothing worth showing, and
        // ByteCountFormatter renders 0 as the odd-looking "Zero KB".
        guard received > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let receivedText = formatter.string(fromByteCount: received)
        guard total > 0 else { return receivedText }
        return "\(receivedText) of \(formatter.string(fromByteCount: total))"
    }
}

/// Observable phase holder the progress window binds to.
@MainActor
final class UpdateProgressModel: ObservableObject {
    @Published var phase: UpdatePhase = .preparing

    /// Version being installed, e.g. "v0.1.25", shown in the window.
    let versionLabel: String

    init(versionLabel: String) {
        self.versionLabel = versionLabel
    }
}
