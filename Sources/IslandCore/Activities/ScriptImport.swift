import Foundation

// MARK: - Importing scripts from files

/// The text of an imported script file, ready for the editor.
public struct ScriptImport: Equatable, Sendable {
    public let text: String
    /// The file was longer than `TeleprompterScript.maxCharacters` and was cut.
    public let truncated: Bool

    public init(text: String, truncated: Bool) {
        self.text = text
        self.truncated = truncated
    }
}

public enum ScriptImportError: Error, Equatable, Sendable {
    case empty
}

extension TeleprompterScript {
    public static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    /// Decodes file bytes, strips Markdown when the extension says so, and clips to `maxCharacters`.
    public static func importText(data: Data, fileExtension: String) -> Result<ScriptImport, ScriptImportError> {
        let raw = decodeText(data)
        let isMarkdown = markdownExtensions.contains(fileExtension.lowercased())
        let text = isMarkdown ? plainText(fromMarkdown: raw) : normalizeNewlines(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        return .success(clip(text))
    }

    /// UTF-8 first; UTF-16 only when the bytes look like it (a BOM or NUL bytes), since decoding
    /// arbitrary bytes as UTF-16 "succeeds" with garbage; Mac OS Roman as the never-failing fallback.
    public static func decodeText(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s }
        if looksLikeUTF16(data), let s = String(data: data, encoding: .utf16) { return s }
        return String(data: data, encoding: .macOSRoman) ?? ""
    }

    /// Cuts the text to `maxCharacters`, reporting whether anything was lost.
    public static func clip(_ text: String) -> ScriptImport {
        guard text.count > maxCharacters else { return ScriptImport(text: text, truncated: false) }
        return ScriptImport(text: String(text.prefix(maxCharacters)), truncated: true)
    }

    static func looksLikeUTF16(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(2))
        if bytes == [0xFF, 0xFE] || bytes == [0xFE, 0xFF] { return true }
        return data.prefix(512).contains(0)
    }

    static func normalizeNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

// MARK: - Markdown → speakable text

extension TeleprompterScript {
    /// Removes the Markdown a presenter shouldn't read aloud: front matter, HTML comments and tags,
    /// heading #'s, blockquote >'s, list markers, code fences, emphasis, inline-code backticks,
    /// images, and link syntax (keeping the link text). Paragraph breaks survive as one blank line.
    public static func plainText(fromMarkdown markdown: String) -> String {
        var text = normalizeNewlines(markdown)
        text = MarkdownStrip.removeFrontMatter(text)
        text = MarkdownStrip.replace(MarkdownStrip.htmlComment, in: text, with: "")
        let lines = MarkdownStrip.removeFences(text.components(separatedBy: "\n"))
            .compactMap(MarkdownStrip.stripBlock)
            .map(MarkdownStrip.stripInline)
        return MarkdownStrip.collapseBlankLines(lines)
    }
}

enum MarkdownStrip {
    // Escaped punctuation is parked in the Private Use Area so inline rules can't touch it.
    static let escapable = Array("\\`*_{}[]()#+-.!>~|<")
    static let parkBase: UInt32 = 0xF0000

    static let htmlComment = regex("<!--[\\s\\S]*?-->")
    static let heading = regex("^#{1,6}(\\s+|$)")
    static let closingHashes = regex("\\s+#+\\s*$")
    static let blockquote = regex("^(\\s*>\\s?)+")
    static let bullet = regex("^\\s*[-*+]\\s+(\\[[ xX]\\]\\s+)?")
    static let ordered = regex("^\\s*\\d{1,9}[.)]\\s+")
    static let rule = regex("^\\s*([-*_=])(\\s*\\1){2,}\\s*$")
    static let referenceDefinition = regex("^\\s*\\[[^\\]]+\\]:\\s*\\S+.*$")
    static let image = regex("!\\[[^\\]]*\\](\\([^)]*\\)|\\[[^\\]]*\\])")
    static let inlineLink = regex("\\[([^\\]]+)\\]\\([^)]*\\)")
    static let referenceLink = regex("\\[([^\\]]+)\\]\\[[^\\]]*\\]")
    static let autolink = regex("<((?:https?|mailto):[^>\\s]+)>")
    static let htmlTag = regex("</?[A-Za-z][^>]*>")
    static let inlineCode = regex("(`+)(.+?)\\1")
    static let strong = regex("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    static let starEmphasis = regex("\\*(?=\\S)(.+?)(?<=\\S)\\*")
    static let underscoreEmphasis = regex("(?<![\\p{L}\\p{N}_])_(?=\\S)(.+?)(?<=\\S)_(?![\\p{L}\\p{N}_])")
    static let strike = regex("~~(?=\\S)(.+?)(?<=\\S)~~")
    static let escape = regex("\\\\([\\\\`*_{}\\[\\]()#+\\-.!>~|<])")

    static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    static func replace(_ re: NSRegularExpression?, in text: String, with template: String) -> String {
        guard let re else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return re.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    static func matches(_ re: NSRegularExpression?, _ text: String) -> Bool {
        guard let re else { return false }
        return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Drops a leading `---` … `---` (or `...`) block. An unclosed opener is left alone.
    static func removeFrontMatter(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return text }
        let close = lines.dropFirst().firstIndex { ["---", "..."].contains($0.trimmingCharacters(in: .whitespaces)) }
        guard let close else { return text }
        return lines[(close + 1)...].joined(separator: "\n")
    }

    /// Removes ``` / ~~~ fence lines, keeping the code between them.
    static func removeFences(_ lines: [String]) -> [String] {
        lines.filter {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return !(t.hasPrefix("```") || t.hasPrefix("~~~"))
        }
    }

    /// Block-level markers. Returns nil for lines that vanish entirely; rules become blank lines.
    static func stripBlock(_ line: String) -> String? {
        if matches(referenceDefinition, line) { return nil }
        if matches(rule, line) { return "" }
        var s = replace(blockquote, in: line, with: "")
        if matches(heading, s) {
            s = replace(closingHashes, in: replace(heading, in: s, with: ""), with: "")
        }
        s = replace(bullet, in: s, with: "")
        s = replace(ordered, in: s, with: "")
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func stripInline(_ line: String) -> String {
        var s = park(line)
        s = replace(image, in: s, with: "")
        s = replace(inlineLink, in: s, with: "$1")
        s = replace(referenceLink, in: s, with: "$1")
        s = replace(autolink, in: s, with: "$1")
        s = replace(htmlTag, in: s, with: "")
        s = replace(inlineCode, in: s, with: "$2")
        s = replace(strong, in: s, with: "$2")
        s = replace(starEmphasis, in: s, with: "$1")
        s = replace(underscoreEmphasis, in: s, with: "$1")
        s = replace(strike, in: s, with: "$1")
        s = s.replacingOccurrences(of: "  ", with: " ")
        return unpark(s).trimmingCharacters(in: .whitespaces)
    }

    static func park(_ text: String) -> String {
        guard let re = escape else { return text }
        var result = ""
        var cursor = text.startIndex
        for match in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let char = Range(match.range(at: 1), in: text) else { continue }
            result += text[cursor..<whole.lowerBound]
            result += parked(text[char])
            cursor = whole.upperBound
        }
        return result + text[cursor...]
    }

    static func parked(_ s: Substring) -> String {
        guard let c = s.first, let i = escapable.firstIndex(of: c),
              let scalar = Unicode.Scalar(parkBase + UInt32(i)) else { return String(s) }
        return String(Character(scalar))
    }

    static func unpark(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            let offset = Int(scalar.value) - Int(parkBase)
            guard escapable.indices.contains(offset), let original = escapable[offset].unicodeScalars.first else { return scalar }
            return original
        }))
    }

    /// Runs of blank lines become one; leading and trailing blanks go.
    static func collapseBlankLines(_ lines: [String]) -> String {
        var out: [String] = []
        for line in lines {
            if line.isEmpty, out.last?.isEmpty ?? true { continue }
            out.append(line)
        }
        while out.last?.isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n")
    }
}
