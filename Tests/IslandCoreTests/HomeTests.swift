import Foundation
@testable import IslandCore

@MainActor
func registerHomeTests() {
    let S = "Home"
    let notion = HomeItem.app(path: "/Applications/Notion.app", name: "Notion")
    let gmail = HomeItem.website(url: URL(string: "https://mail.google.com")!, title: "Gmail")
    let standup = HomeItem.shortcut(name: "Standup notes")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    test(S, "items map to the command that runs them") {
        expectEqual(notion.command, .launchApplication(URL(fileURLWithPath: "/Applications/Notion.app")))
        expectEqual(gmail.command, .openURL(URL(string: "https://mail.google.com")!))
        expectEqual(standup.command, .runShortcut(name: "Standup notes"))
        expectEqual(HomeItem.feature(.teleprompter).command, .action(.startTeleprompter))
        expectEqual(HomeItem.feature(.timer(minutes: 25)).command, .timer(.start(duration: 1500, label: "25 min")))
    }

    test(S, "search results become pinnable items, other results don't") {
        let app = SearchResult(id: "a", category: .application, providerID: "apps", title: "Notion",
                               command: .launchApplication(URL(fileURLWithPath: "/Applications/Notion.app")))
        expectEqual(HomeItem(result: app), notion)
        let web = SearchResult(id: "w", category: .web, providerID: "web", title: "Gmail", command: .openURL(URL(string: "https://mail.google.com")!))
        expectEqual(HomeItem(result: web), gmail)
        let file = SearchResult(id: "f", category: .file, providerID: "files", title: "Notes.pdf", command: .openFile(URL(fileURLWithPath: "/tmp/Notes.pdf")))
        expectEqual(HomeItem(result: file), .file(path: "/tmp/Notes.pdf", name: "Notes.pdf"))
        let ai = SearchResult(id: "x", category: .ai, providerID: "ai", title: "Ask")
        expect(HomeItem(result: ai) == nil)
    }

    test(S, "pins dedupe, cap and reorder") {
        var pins = HomePins.adding(notion, to: [])
        pins = HomePins.adding(notion, to: pins)
        expectEqual(pins, [notion])
        pins = HomePins.adding(gmail, to: pins)
        pins = HomePins.adding(standup, to: pins)
        expectEqual(HomePins.moving(standup, to: 0, in: pins), [standup, notion, gmail])
        expectEqual(HomePins.removing(notion, from: pins), [gmail, standup])
        let many = (0..<20).map { HomeItem.shortcut(name: "s\($0)") }
        expectEqual(many.reduce([]) { HomePins.adding($1, to: $0) }.count, HomePins.maxPins)
    }

    test(S, "pins survive a JSON round trip") {
        let pins = [notion, gmail, standup, .feature(.shelf), .feature(.timer(minutes: 5)), .file(path: "/tmp/x", name: "x")]
        let data = try JSONEncoder().encode(pins)
        expectEqual(try JSONDecoder().decode([HomeItem].self, from: data), pins)
    }

    test(S, "an unreadable pin is skipped without losing other settings") {
        let d = UserDefaults(suiteName: "island.test.\(UUID().uuidString)")!
        let json = #"{"glassIntensity":0.3,"homePins":[{"shortcut":{"name":"Standup notes"}},{"hologram":{"x":1}}]}"#
        d.set(json.data(using: .utf8)!, forKey: IslandSettings.storageKey)
        let s = IslandSettings(defaults: d)
        expectEqual(s.glassIntensity, 0.3)
        expectEqual(s.homePins, [.shortcut(name: "Standup notes")])
    }

    test(S, "finds meeting links in event fields") {
        expectEqual(MeetingLink.find(in: ["Room 4", "Join: https://meet.google.com/abc-defg-hij"])?.host, "meet.google.com")
        expectEqual(MeetingLink.find(in: ["https://acme.zoom.us/j/123?pwd=x"])?.host, "acme.zoom.us")
        expect(MeetingLink.find(in: ["https://example.com/agenda", "no link"]) == nil)
    }

    test(S, "status line prefers a soon event, then says when the next one is") {
        let soon = HomeEvent(title: "Standup", start: t0.addingTimeInterval(19 * 60), joinURL: nil)
        expectEqual(HomeStatus.line(now: t0, event: soon), "Standup in 19 min")
        let now = HomeEvent(title: "Design review", start: t0.addingTimeInterval(-120), joinURL: nil)
        expectEqual(HomeStatus.line(now: t0, event: now), "Design review now")
        let later = HomeEvent(title: "1:1", start: t0.addingTimeInterval(3 * 3600), joinURL: nil)
        expect(HomeStatus.line(now: t0, event: later)?.hasPrefix("1:1 at ") == true)
        expect(HomeStatus.line(now: t0, event: nil) == nil)
    }

    test(S, "suggests joining a meeting that starts soon") {
        var c = HomeContext(now: t0)
        c.event = HomeEvent(title: "Standup", start: t0.addingTimeInterval(5 * 60), joinURL: URL(string: "https://meet.google.com/x"))
        expectEqual(HomeSuggestionEngine.suggest(c).first, .joinEvent(title: "Standup", url: URL(string: "https://meet.google.com/x")!))
        c.event = HomeEvent(title: "Later", start: t0.addingTimeInterval(40 * 60), joinURL: URL(string: "https://meet.google.com/x"))
        expect(HomeSuggestionEngine.suggest(c).isEmpty)
    }

    test(S, "suggests the teleprompter when the camera is on and a script is saved") {
        var c = HomeContext(now: t0)
        c.cameraOn = true
        expect(!HomeSuggestionEngine.suggest(c).contains(.startTeleprompter))
        c.hasTeleprompterScript = true
        expect(HomeSuggestionEngine.suggest(c).contains(.startTeleprompter))
    }

    test(S, "suggests shelving a fresh download, not an old one") {
        var c = HomeContext(now: t0)
        let url = URL(fileURLWithPath: "/Users/x/Downloads/report.pdf")
        c.recentDownload = HomeFile(name: "report.pdf", url: url, at: t0.addingTimeInterval(-120))
        expect(HomeSuggestionEngine.suggest(c).contains(.shelveDownload(name: "report.pdf", url: url)))
        c.recentDownload = HomeFile(name: "report.pdf", url: url, at: t0.addingTimeInterval(-3600))
        expect(!HomeSuggestionEngine.suggest(c).contains(.shelveDownload(name: "report.pdf", url: url)))
    }

    test(S, "suggests things you use often, never ones already pinned, at most three") {
        var usage = HomeUsage()
        for _ in 0..<5 { usage = usage.recording(gmail, at: t0.addingTimeInterval(-3600)) }
        for _ in 0..<3 { usage = usage.recording(standup, at: t0.addingTimeInterval(-7200)) }
        usage = usage.recording(notion, at: t0) // once is not a habit
        var c = HomeContext(now: t0)
        c.usage = usage
        expectEqual(HomeSuggestionEngine.suggest(c), [.frequent(gmail), .frequent(standup)])
        c.pinned = [gmail]
        expectEqual(HomeSuggestionEngine.suggest(c), [.frequent(standup)])
        c.cameraOn = true; c.hasTeleprompterScript = true
        c.event = HomeEvent(title: "Standup", start: t0, joinURL: URL(string: "https://meet.google.com/x"))
        c.recentDownload = HomeFile(name: "a", url: URL(fileURLWithPath: "/a"), at: t0)
        expectEqual(HomeSuggestionEngine.suggest(c).count, HomeSuggestionEngine.maxSuggestions)
    }

    test(S, "usage forgets old habits and stays bounded") {
        var usage = HomeUsage()
        usage = usage.recording(gmail, at: t0.addingTimeInterval(-60 * 86_400))
        usage = usage.recording(gmail, at: t0.addingTimeInterval(-59 * 86_400))
        expect(usage.score(for: gmail, at: t0) < usage.score(for: gmail, at: t0.addingTimeInterval(-58 * 86_400)))
        for i in 0..<200 { usage = usage.recording(.shortcut(name: "s\(i)"), at: t0) }
        expect(usage.entries.count <= HomeUsage.maxEntries)
    }
}
