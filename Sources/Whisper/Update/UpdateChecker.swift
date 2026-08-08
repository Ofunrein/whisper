import Foundation

/// Checks GitHub Releases for a newer tagged version than the running app.
///
/// Historically this was check-only: it just opened the release page in a
/// browser for the user to download manually, because the app isn't
/// notarized and a silently-replaced binary would hit the same Gatekeeper
/// quarantine wall again on next launch. `Updater` (see Updater.swift) now
/// handles that: it downloads the release DMG, mounts it, copies
/// Whisper.app to /Applications, and strips the quarantine attribute from
/// the freshly-copied app before relaunching -- which is safe because it's
/// a self-update of the same publisher's app the user already approved
/// once, not an arbitrary Gatekeeper bypass. The "open release page in
/// browser" behavior is kept as a manual fallback.
enum UpdateChecker {
    struct Asset: Decodable {
        let name: String
        let downloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    static let repo = "Ofunrein/whisper"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Returns the newer release if one exists, else nil.
    static func checkForUpdate() async -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data) else {
            return nil
        }

        let latest = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        return isNewer(latest, than: currentVersion) ? release : nil
    }

    private static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").compactMap { Int($0) }
        let bv = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
