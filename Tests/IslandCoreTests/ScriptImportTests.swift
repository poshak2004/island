import Foundation
@testable import IslandCore

@MainActor
func registerScriptImportTests() {
    let S = "ScriptImport"
    let strip = TeleprompterScript.plainText(fromMarkdown:)

    test(S, "headings lose their hashes, including closing ones") {
        expectEqual(strip("# Welcome\n## Part two ##\n###### Deep"), "Welcome\nPart two\nDeep")
        expectEqual(strip("#hashtag stays"), "#hashtag stays")
    }

    test(S, "emphasis, strong and strikethrough markers are removed") {
        expectEqual(strip("This is *really* **very** _quite_ __so__ ~~not~~ important"),
                    "This is really very quite so not important")
    }

    test(S, "underscores inside words and lone asterisks survive") {
        expectEqual(strip("call snake_case_name and 2 * 3 = 6"), "call snake_case_name and 2 * 3 = 6")
    }

    test(S, "inline code keeps its text without backticks") {
        expectEqual(strip("Run `make build` then ``say `hi` ``"), "Run make build then say `hi`")
    }

    test(S, "links keep their text and images vanish") {
        expectEqual(strip("See [our site](https://example.com \"t\") ![logo](logo.png) now"), "See our site now")
        expectEqual(strip("A [reference][1] link\n\n[1]: https://example.com"), "A reference link")
        expectEqual(strip("Mail <mailto:a@b.c>"), "Mail mailto:a@b.c")
    }

    test(S, "list markers and task boxes are removed") {
        expectEqual(strip("- one\n* two\n+ three\n1. four\n2) five\n- [x] six\n  - nested"),
                    "one\ntwo\nthree\nfour\nfive\nsix\nnested")
    }

    test(S, "blockquotes lose their markers, even nested") {
        expectEqual(strip("> Quoted\n>> Deeper\n> ## Heading in quote"), "Quoted\nDeeper\nHeading in quote")
    }

    test(S, "HTML comments are removed, even across lines") {
        expectEqual(strip("Say this <!-- not this --> and this\n<!-- a\nmulti-line\nnote -->\nEnd"),
                    "Say this and this\n\nEnd")
    }

    test(S, "front matter at the top is removed") {
        expectEqual(strip("---\ntitle: Talk\ndate: 2026\n---\n# Hello\nWorld"), "Hello\nWorld")
        expectEqual(strip("Intro\n---\nnot: front matter\n---"), "Intro\n\nnot: front matter")
    }

    test(S, "an unclosed front matter opener is left as a rule") {
        expectEqual(strip("---\nJust text"), "Just text")
    }

    test(S, "paragraph breaks survive and blank runs collapse") {
        expectEqual(strip("\n\nFirst para\nline two\n\n\n\nSecond para\n\n"), "First para\nline two\n\nSecond para")
    }

    test(S, "code fences go, their content stays") {
        expectEqual(strip("Before\n```swift\nlet x = 1\n```\nAfter"), "Before\nlet x = 1\nAfter")
    }

    test(S, "horizontal rules become paragraph breaks") {
        expectEqual(strip("One\n***\nTwo\n___\nThree"), "One\n\nTwo\n\nThree")
    }

    test(S, "backslash escapes keep the literal character") {
        expectEqual(strip("Price \\*not\\* emphasised \\# and \\_x\\_"), "Price *not* emphasised # and _x_")
    }

    test(S, "simple HTML tags are dropped") {
        expectEqual(strip("Line<br>with <b>bold</b>"), "Linewith bold")
    }

    test(S, "CRLF input is normalised") {
        expectEqual(strip("# Title\r\n\r\nBody\r\n"), "Title\n\nBody")
    }

    test(S, "decodes UTF-8, UTF-8 with BOM, UTF-16 and Mac Roman") {
        expectEqual(TeleprompterScript.decodeText(Data("héllo".utf8)), "héllo")
        expectEqual(TeleprompterScript.decodeText(Data([0xEF, 0xBB, 0xBF]) + Data("hi".utf8)), "hi")
        let utf16 = "héllo".data(using: .utf16) ?? Data()
        expectEqual(TeleprompterScript.decodeText(utf16), "héllo")
        // 0x8E is "é" in Mac OS Roman and invalid as UTF-8 on its own.
        expectEqual(TeleprompterScript.decodeText(Data([0x63, 0x61, 0x66, 0x8E])), "café")
    }

    test(S, "import strips markdown only for markdown extensions") {
        let data = Data("# Title\n*hi*".utf8)
        expectEqual(TeleprompterScript.importText(data: data, fileExtension: "MD"),
                    .success(ScriptImport(text: "Title\nhi", truncated: false)))
        expectEqual(TeleprompterScript.importText(data: data, fileExtension: "txt"),
                    .success(ScriptImport(text: "# Title\n*hi*", truncated: false)))
    }

    test(S, "import rejects empty files") {
        expectEqual(TeleprompterScript.importText(data: Data("  \n<!-- x -->\n".utf8), fileExtension: "md"), .failure(.empty))
        expectEqual(TeleprompterScript.importText(data: Data(), fileExtension: "txt"), .failure(.empty))
    }

    test(S, "import truncates to the script limit and says so") {
        let long = String(repeating: "a", count: TeleprompterScript.maxCharacters + 10)
        let result = TeleprompterScript.importText(data: Data(long.utf8), fileExtension: "txt")
        guard case let .success(imported) = result else { return expect(false, "expected success") }
        expect(imported.truncated)
        expectEqual(imported.text.count, TeleprompterScript.maxCharacters)
        expect(!TeleprompterScript.clip("short").truncated)
    }
}
