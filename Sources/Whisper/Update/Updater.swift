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
    static func downloadAndInstall(_ release: UpdateChecker.Release) async throws {
        // Prefer a DMG asset (no privilege escalation needed); fall back to PKG.
        if let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) {
            try await installFromDMG(dmgAsset)
        } else if let pkgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".pkg") }) {
            try await installFromPKG(pkgAsset)
        } else {
            throw UpdateError.noSupportedAsset
        }
        relaunch()
    }

    // MARK: - DMG path

    private static func installFromDMG(_ asset: UpdateChecker.Asset) async throws {
        let dmgURL = try await download(asset)
        defer { try? FileManager.default.removeItem(at: dmgURL) }

        let mountPoint = try mountDMG(dmgURL)
        defer { detachDMG(mountPoint) }

        let sourceApp = mountPoint.appendingPathComponent("Whisper.app")
        guard FileManager.default.fileExists(atPath: sourceApp.path) else {
            throw UpdateError.appNotFoundOnVolume
        }

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
    private static func installFromPKG(_ asset: UpdateChecker.Asset) async throws {
        let pkgURL = try await download(asset)
        defer { try? FileManager.default.removeItem(at: pkgURL) }

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

    private static func download(_ asset: UpdateChecker.Asset) async throws -> URL {
        guard let url = URL(string: asset.downloadURL) else {
            throw UpdateError.downloadFailed("Invalid asset URL")
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(asset.name)
        try? FileManager.default.removeItem(at: destination)

        do {
            let (tempURL, response) = try await URLSession.shared.download(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.downloadFailed("Unexpected server response")
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            return destination
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
