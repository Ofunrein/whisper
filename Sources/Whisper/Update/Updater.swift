import AppKit
import Foundation

/// Performs a one-click, fully-silent self-update: download the latest
/// GitHub release's DMG asset, mount it, copy Whisper.app over
/// /Applications/Whisper.app, strip quarantine, and relaunch.
///
/// This app is not notarized/signed with an Apple Developer ID, so Gatekeeper
/// would normally re-quarantine a freshly-copied app bundle and block it on
/// next launch. Stripping `com.apple.quarantine` here is a legitimate
/// self-update of the same publisher's app the user already approved once
/// (not an arbitrary bypass of a bundle the user hasn't seen).
enum Updater {
    enum UpdateError: Error, LocalizedError {
        case noSupportedAsset
        case downloadFailed(String)
        case mountFailed(String)
        case appNotFoundOnVolume
        case copyFailed(String)
        case installerFailed(String)

        var errorDescription: String? {
            switch self {
            case .noSupportedAsset:
                return "This release has no DMG or PKG asset Whisper knows how to install automatically."
            case .downloadFailed(let why):
                return "Couldn't download the update: \(why)"
            case .mountFailed(let why):
                return "Couldn't mount the downloaded disk image: \(why)"
            case .appNotFoundOnVolume:
                return "Whisper.app wasn't found inside the downloaded disk image."
            case .copyFailed(let why):
                return "Couldn't install the update: \(why)"
            case .installerFailed(let why):
                return "Installer failed: \(why)"
            }
        }
    }

    private static let installedAppPath = "/Applications/Whisper.app"

    /// Downloads and installs `release`, then relaunches the app. Throws on
    /// any failure; caller is expected to surface `error.localizedDescription`.
    /// Runs entirely off the main actor except for the final relaunch spawn.
    ///
    /// `onPhase` is called as the update advances so the caller can show
    /// progress; it may be invoked from arbitrary threads, so UI callers must
    /// hop to the main actor themselves.
    static func downloadAndInstall(
        _ release: UpdateChecker.Release,
        onPhase: @escaping (UpdatePhase) -> Void = { _ in }
    ) async throws {
        onPhase(.preparing)
        // Prefer a DMG asset (no privilege escalation needed); fall back to PKG.
        if let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) {
            try await installFromDMG(dmgAsset, onPhase: onPhase)
        } else if let pkgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".pkg") }) {
            try await installFromPKG(pkgAsset, onPhase: onPhase)
        } else {
            throw UpdateError.noSupportedAsset
        }
        onPhase(.relaunching)
        relaunch()
    }

    // MARK: - DMG path

    private static func installFromDMG(
        _ asset: UpdateChecker.Asset,
        onPhase: @escaping (UpdatePhase) -> Void
    ) async throws {
        let dmgURL = try await download(asset, onPhase: onPhase)
        defer { try? FileManager.default.removeItem(at: dmgURL) }

        onPhase(.mounting)
        let mountPoint = try mountDMG(dmgURL)
        defer { detachDMG(mountPoint) }

        let sourceApp = mountPoint.appendingPathComponent("Whisper.app")
        guard FileManager.default.fileExists(atPath: sourceApp.path) else {
            throw UpdateError.appNotFoundOnVolume
        }

        onPhase(.installing)
        try installApp(from: sourceApp)
    }

    private static func mountDMG(_ dmgURL: URL) throws -> URL {
        let mountRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-update-mount-\(UUID().uuidString)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", dmgURL.path, "-mountpoint", mountRoot.path, "-nobrowse", "-quiet"]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw UpdateError.mountFailed(error.localizedDescription)
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let err = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw UpdateError.mountFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return mountRoot
    }

    private static func detachDMG(_ mountPoint: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path, "-quiet"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    /// Copies `sourceApp` to /Applications/Whisper.app (replacing any
    /// existing copy) and strips quarantine so Gatekeeper doesn't re-block
    /// the freshly-installed, unsigned app on relaunch.
    private static func installApp(from sourceApp: URL) throws {
        let fm = FileManager.default
        let destination = URL(fileURLWithPath: installedAppPath)

        if fm.fileExists(atPath: destination.path) {
            do {
                try fm.removeItem(at: destination)
            } catch {
                throw UpdateError.copyFailed("Couldn't remove existing app: \(error.localizedDescription)")
            }
        }

        do {
            try fm.copyItem(at: sourceApp, to: destination)
        } catch {
            throw UpdateError.copyFailed(error.localizedDescription)
        }

        stripQuarantine(at: destination)
    }

    // MARK: - PKG path

    /// Installing a PKG system-wide needs admin privileges. `installer -pkg
    /// ... -target /` run directly would fail (or silently no-op) without
    /// root, so we shell out via AppleScript `with administrator privileges`
    /// to get the standard macOS authorization prompt, same as double-clicking
    /// the PKG in Finder would.
    private static func installFromPKG(
        _ asset: UpdateChecker.Asset,
        onPhase: @escaping (UpdatePhase) -> Void
    ) async throws {
        let pkgURL = try await download(asset, onPhase: onPhase)
        defer { try? FileManager.default.removeItem(at: pkgURL) }

        onPhase(.installing)
        let escapedPath = pkgURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        do shell script "/usr/sbin/installer -pkg \\"\(escapedPath)\\" -target /" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw UpdateError.installerFailed(error.localizedDescription)
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let err = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw UpdateError.installerFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        stripQuarantine(at: URL(fileURLWithPath: installedAppPath))
    }

    // MARK: - Shared helpers

    private static func download(
        _ asset: UpdateChecker.Asset,
        onPhase: @escaping (UpdatePhase) -> Void
    ) async throws -> URL {
        guard let url = URL(string: asset.downloadURL) else {
            throw UpdateError.downloadFailed("Invalid asset URL")
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(asset.name)
        try? FileManager.default.removeItem(at: destination)

        // Report 0-of-unknown immediately: GitHub redirects release assets to a
        // CDN, so the first byte-progress callback can be a second or two out,
        // and the window should show "Downloading" rather than "Preparing".
        onPhase(.downloading(receivedBytes: 0, totalBytes: 0))

        do {
            let downloader = ProgressiveDownloader { received, total in
                onPhase(.downloading(receivedBytes: received, totalBytes: total))
            }
            return try await downloader.download(from: url, to: destination)
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.downloadFailed(error.localizedDescription)
        }
    }

    private static func stripQuarantine(at path: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-cr", path.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    /// Relaunches the freshly-installed app and quits this process. Uses a
    /// tiny detached shell script that waits for our PID to exit before
    /// launching the new copy, so we don't race our own termination against
    /// `open` still resolving the app bundle.
    private static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done
        open "\(installedAppPath)"
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        // Detach stdio so the relaunch script survives after we exit.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try? process.run()

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}

/// Downloads a file to `destination` while reporting byte progress.
///
/// The obvious approach -- passing a delegate to the async
/// `URLSession.download(for:delegate:)` -- silently reports nothing: that
/// convenience method never invokes `didWriteData` (measured: zero callbacks
/// across an 83 MB download), so the progress bar would sit at zero for the
/// whole download. A session-level delegate does fire, so this bridges the
/// classic delegate API back to async/await with a continuation.
private final class ProgressiveDownloader: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?

    init(onProgress: @escaping (Int64, Int64) -> Void) {
        self.onProgress = onProgress
        super.init()
    }

    func download(from url: URL, to destination: URL) async throws -> URL {
        self.destination = destination
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        // Break the session's strong reference to this delegate once the
        // transfer ends, otherwise the session (and self) leak.
        defer { session.finishTasksAndInvalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // URLSession deletes `location` as soon as this method returns, so the
        // file has to be moved synchronously here rather than after awaiting.
        guard let destination else {
            finish(.failure(Updater.UpdateError.downloadFailed("No download destination")))
            return
        }

        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            finish(.failure(Updater.UpdateError.downloadFailed("Unexpected server response (HTTP \(http.statusCode))")))
            return
        }

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(Updater.UpdateError.downloadFailed(error.localizedDescription)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Only meaningful for the failure case; a successful transfer has
        // already resumed the continuation in didFinishDownloadingTo.
        if let error {
            finish(.failure(error))
        }
    }

    /// Resumes the continuation at most once -- both delegate callbacks can
    /// fire for one transfer, and resuming twice would trap.
    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
