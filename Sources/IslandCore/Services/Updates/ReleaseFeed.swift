import Foundation

/// `version.json`, published as an asset of every GitHub release. Updates are detected by build
/// number, because a release can be replaced in place under the same tag.
public struct ReleaseManifest: Codable, Equatable, Sendable {
    public let version: String
    public let build: Int

    public init(version: String, build: Int) {
        self.version = version
        self.build = build
    }
}

public struct AvailableUpdate: Equatable, Sendable {
    public let version: String
    public let build: Int
    /// The release page — Island never downloads or installs anything itself.
    public let page: URL
}

/// Pure logic for the update check: parse GitHub's latest-release JSON, find the manifest, compare.
/// The network calls live in the app layer.
public enum ReleaseFeed {
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/poshak2004/island/releases/latest")!
    public static let releasesPage = URL(string: "https://github.com/poshak2004/island/releases/latest")!
    public static let manifestName = "version.json"
    /// Automatic checks happen at most this often.
    public static let interval: TimeInterval = 24 * 60 * 60

    public struct Release: Equatable, Sendable {
        public let manifestURL: URL?
        public let pageURL: URL
    }

    public static func parseRelease(_ data: Data) -> Release? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let page = (root["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
        let assets = root["assets"] as? [[String: Any]] ?? []
        let manifest = assets.first { $0["name"] as? String == manifestName }?["browser_download_url"] as? String
        return Release(manifestURL: manifest.flatMap(URL.init(string:)), pageURL: page)
    }

    public static func parseManifest(_ data: Data) -> ReleaseManifest? {
        try? JSONDecoder().decode(ReleaseManifest.self, from: data)
    }

    /// An update only when the published build is newer than the running one.
    public static func update(current build: Int, manifest: ReleaseManifest, page: URL) -> AvailableUpdate? {
        manifest.build > build ? AvailableUpdate(version: manifest.version, build: manifest.build, page: page) : nil
    }

    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }
}
