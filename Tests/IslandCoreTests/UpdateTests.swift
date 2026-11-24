import Foundation
@testable import IslandCore

@MainActor
func registerUpdateTests() {
    let S = "Updates"
    let release = #"""
    {"tag_name": "v0.3.0", "html_url": "https://github.com/poshak2004/island/releases/tag/v0.3.0",
     "assets": [
       {"name": "Island.dmg", "browser_download_url": "https://example.com/Island.dmg"},
       {"name": "version.json", "browser_download_url": "https://example.com/version.json"}
     ]}
    """#.data(using: .utf8)!

    test(S, "finds the version manifest and release page in GitHub's latest-release JSON") {
        let r = ReleaseFeed.parseRelease(release)
        expectEqual(r?.manifestURL, URL(string: "https://example.com/version.json"))
        expectEqual(r?.pageURL, URL(string: "https://github.com/poshak2004/island/releases/tag/v0.3.0"))
        expect(ReleaseFeed.parseRelease(#"{"tag_name": "v1", "assets": []}"#.data(using: .utf8)!)?.manifestURL == nil)
        expect(ReleaseFeed.parseRelease(Data("not json".utf8)) == nil)
    }

    test(S, "an update is a higher build — the tag can stay the same when a release is replaced") {
        let m = ReleaseFeed.parseManifest(#"{"version": "0.3.0", "build": 31}"#.data(using: .utf8)!)
        expectEqual(m, ReleaseManifest(version: "0.3.0", build: 31))
        let page = URL(string: "https://github.com/poshak2004/island/releases/latest")!
        expectEqual(ReleaseFeed.update(current: 30, manifest: m!, page: page)?.build, 31)
        expect(ReleaseFeed.update(current: 31, manifest: m!, page: page) == nil, "same build is not an update")
        expect(ReleaseFeed.update(current: 40, manifest: m!, page: page) == nil, "a newer local build is not an update")
        expect(ReleaseFeed.parseManifest(#"{"version": "0.3.0"}"#.data(using: .utf8)!) == nil)
    }

    test(S, "checks at most once a day unless asked") {
        let now = Date(timeIntervalSince1970: 100_000)
        expect(ReleaseFeed.isDue(lastCheck: nil, now: now))
        expect(!ReleaseFeed.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        expect(ReleaseFeed.isDue(lastCheck: now.addingTimeInterval(-ReleaseFeed.interval - 1), now: now))
    }

    test(S, "update checks are on by default and persist") {
        let d = UserDefaults(suiteName: "island.tests.\(UUID().uuidString)")!
        let s = IslandSettings(defaults: d)
        expectEqual(s.checkForUpdates, true)
        s.checkForUpdates = false
        expectEqual(IslandSettings(defaults: d).checkForUpdates, false)
    }
}
