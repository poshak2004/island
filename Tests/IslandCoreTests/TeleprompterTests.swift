import Foundation
@testable import IslandCore

@MainActor
func registerTeleprompterTests() {
    let S = "Teleprompter"

    test(S, "wrap keeps words whole and lines within the limit") {
        let lines = ScriptLayout.wrap("The quick brown fox jumps over the lazy dog", maxChars: 12)
        expectEqual(lines.map(\.text), ["The quick", "brown fox", "jumps over", "the lazy dog"])
        expect(lines.allSatisfy { $0.text.count <= 12 })
    }

    test(S, "wrap tracks word indexes across lines and paragraphs") {
        let lines = ScriptLayout.wrap("one two three\n\nfour five", maxChars: 8)
        expectEqual(lines.map(\.text), ["one two", "three", "", "four", "five"])
        expectEqual(lines.map(\.firstWord), [0, 2, 3, 3, 4])
        expectEqual(lines.map(\.wordCount), [2, 1, 0, 1, 1])
    }

    test(S, "wrap collapses runs of blank lines and splits over-long words") {
        let lines = ScriptLayout.wrap("a\n\n\n\nb supercalifragilistic", maxChars: 6)
        expectEqual(lines.map(\.text), ["a", "", "b", "superc", "alifra", "gilist", "ic"])
    }

    test(S, "script rejects empty text and counts words") {
        expect(TeleprompterScript(text: "  \n \n", title: "x", maxLineChars: 30) == nil)
        let s = TeleprompterScript(text: "Hello there, world.", title: "Intro", maxLineChars: 30)
        expectEqual(s?.wordCount, 3)
        expectEqual(s?.words, ["hello", "there", "world"])
    }

    test(S, "position advances with words per minute only while playing") {
        let script = TeleprompterScript(text: Array(repeating: "word", count: 120).joined(separator: " "), title: "", maxLineChars: 20)!
        let t0 = Date(timeIntervalSince1970: 1000)
        var a = TeleprompterActivity(script: script, wordsPerMinute: 120, anchorDate: t0)
        expectEqual(a.position(at: t0.addingTimeInterval(10)), 0) // paused by default
        a.play(at: t0)
        expectEqual(a.position(at: t0.addingTimeInterval(10)), 20)
        a.pause(at: t0.addingTimeInterval(10))
        expectEqual(a.position(at: t0.addingTimeInterval(60)), 20)
    }

    test(S, "position clamps at the end and reports finish time") {
        let script = TeleprompterScript(text: "a b c d e f", title: "", maxLineChars: 20)!
        let t0 = Date(timeIntervalSince1970: 0)
        var a = TeleprompterActivity(script: script, wordsPerMinute: 60, anchorDate: t0)
        a.play(at: t0)
        expectEqual(a.position(at: t0.addingTimeInterval(100)), 6)
        expectEqual(a.progress(at: t0.addingTimeInterval(3)), 0.5)
        expectEqual(a.finishDate, t0.addingTimeInterval(6))
    }

    test(S, "changing speed keeps the current position") {
        let script = TeleprompterScript(text: Array(repeating: "w", count: 100).joined(separator: " "), title: "", maxLineChars: 20)!
        let t0 = Date(timeIntervalSince1970: 0)
        var a = TeleprompterActivity(script: script, wordsPerMinute: 60, anchorDate: t0)
        a.play(at: t0)
        a.setSpeed(120, at: t0.addingTimeInterval(10)) // at word 10
        expectEqual(a.position(at: t0.addingTimeInterval(10)), 10)
        expectEqual(a.position(at: t0.addingTimeInterval(15)), 20)
        a.setSpeed(10_000, at: t0.addingTimeInterval(15))
        expectEqual(a.wordsPerMinute, TeleprompterActivity.speedRange.upperBound)
    }

    test(S, "line offset interpolates within a line") {
        let script = TeleprompterScript(text: "a b c d\ne f", title: "", maxLineChars: 20)!
        var a = TeleprompterActivity(script: script, wordsPerMinute: 60, anchorDate: .distantPast)
        a.seek(toWord: 2)
        expectEqual(a.lineOffset(at: .distantPast), 0.5)
        a.seek(toWord: 5)
        expectEqual(a.lineOffset(at: .distantPast), 1.5)
        a.seek(toWord: 99)
        expectEqual(a.position(at: .distantPast), 6)
    }

    test(S, "skip lines moves by whole lines and clamps") {
        let script = TeleprompterScript(text: "a b\nc d\ne f", title: "", maxLineChars: 20)!
        var a = TeleprompterActivity(script: script, wordsPerMinute: 60, anchorDate: .distantPast)
        a.skip(lines: 1, at: .distantPast)
        expectEqual(a.position(at: .distantPast), 2)
        a.skip(lines: 5, at: .distantPast)
        expectEqual(a.position(at: .distantPast), 4)
        a.skip(lines: -9, at: .distantPast)
        expectEqual(a.position(at: .distantPast), 0)
    }

    test(S, "matcher follows the speaker forward") {
        let words = ScriptMatcher.normalize("Welcome to the show. Today we talk about notch apps and why they matter.")
        expectEqual(ScriptMatcher.advance(script: words, current: 0, heard: ["welcome", "to", "the"]), 3)
        expectEqual(ScriptMatcher.advance(script: words, current: 3, heard: ["Today", "we", "talk"]), 7)
    }

    test(S, "matcher ignores noise and never jumps far backwards") {
        let words = ScriptMatcher.normalize("one two three four five six seven eight nine ten one two three")
        expect(ScriptMatcher.advance(script: words, current: 4, heard: ["banana", "pancake"]) == nil)
        // "one two three" appears twice; prefer the occurrence ahead of the reader.
        expectEqual(ScriptMatcher.advance(script: words, current: 9, heard: ["one", "two", "three"]), 13)
        // A single common word is not enough evidence to move.
        expect(ScriptMatcher.advance(script: words, current: 4, heard: ["seven"]) == nil)
    }

    test(S, "matcher tolerates one misheard word") {
        let words = ScriptMatcher.normalize("the island lives in your notch all day")
        expectEqual(ScriptMatcher.advance(script: words, current: 2, heard: ["lives", "inn", "your", "notch"]), 6)
    }

    test(S, "parser recognises teleprompter commands") {
        expect(ActionRouter.parse("teleprompter").contains(.startTeleprompter))
        expect(ActionRouter.parse("Start prompter").contains(.startTeleprompter))
        expect(!ActionRouter.parse("open teleprompter app").contains(.startTeleprompter))
    }

    test(S, "presentation stays open for a pinned activity until Escape") {
        var p = IslandPresentation()
        p.handle(.activityAvailabilityChanged(hasActivity: true))
        p.pinsExpansion = true
        p.handle(.click)
        expectEqual(p.mode, .expanded)
        p.handle(.hoverBegan)
        p.handle(.hoverEnded)
        p.handle(.autoCollapse)
        p.handle(.clickOutside)
        expectEqual(p.mode, .expanded)
        p.handle(.escape)
        expectEqual(p.mode, .compact)
    }

    test(S, "settings migration enables new user-started kinds once") {
        let d = UserDefaults(suiteName: "island.test.\(UUID().uuidString)")!
        let old = #"{"enabledKinds":["media","timer"]}"#.data(using: .utf8)!
        d.set(old, forKey: IslandSettings.storageKey)
        let s = IslandSettings(defaults: d)
        expect(s.enabledKinds.contains(.teleprompter))
        expect(s.enabledKinds.contains(.shelf))
        s.enabledKinds.remove(.teleprompter)
        let reloaded = IslandSettings(defaults: d)
        expect(!reloaded.enabledKinds.contains(.teleprompter), "user's choice to turn it off survives reload")
    }
}
