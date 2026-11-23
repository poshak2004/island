import Foundation

// MARK: - Script layout

/// One display line of a script. `firstWord`/`wordCount` index into the script's word list, so the
/// reading position (in words) maps onto a scroll offset (in lines) without measuring text.
public struct ScriptLine: Equatable, Sendable {
    public let text: String
    public let firstWord: Int
    public let wordCount: Int
}

public enum ScriptLayout {
    /// Greedy word wrap into lines of at most `maxChars`. Paragraph breaks become one empty line
    /// (runs of blank lines collapse), and a word longer than a line is split across lines.
    public static func wrap(_ text: String, maxChars: Int) -> [ScriptLine] {
        let limit = max(4, maxChars)
        var lines: [ScriptLine] = []
        var wordIndex = 0
        var pendingBlank = false

        for paragraph in text.components(separatedBy: .newlines) {
            let tokens = paragraph.split(whereSeparator: \.isWhitespace).map(String.init)
            if tokens.isEmpty { pendingBlank = !lines.isEmpty; continue }
            if pendingBlank { lines.append(ScriptLine(text: "", firstWord: wordIndex, wordCount: 0)) }
            pendingBlank = false

            var current: [String] = []
            var currentFirst = wordIndex
            func flush() {
                guard !current.isEmpty else { return }
                lines.append(ScriptLine(text: current.joined(separator: " "), firstWord: currentFirst, wordCount: current.count))
                current = []
            }
            for token in tokens {
                if token.count > limit {
                    flush()
                    let chunks = stride(from: 0, to: token.count, by: limit).map { start -> String in
                        let a = token.index(token.startIndex, offsetBy: start)
                        let b = token.index(a, offsetBy: min(limit, token.count - start))
                        return String(token[a..<b])
                    }
                    for (i, chunk) in chunks.enumerated() {
                        lines.append(ScriptLine(text: chunk, firstWord: i == 0 ? wordIndex : wordIndex + 1, wordCount: i == 0 ? 1 : 0))
                    }
                    wordIndex += 1
                    currentFirst = wordIndex
                    continue
                }
                let candidate = (current + [token]).joined(separator: " ")
                if !current.isEmpty, candidate.count > limit { flush(); currentFirst = wordIndex }
                if current.isEmpty { currentFirst = wordIndex }
                current.append(token)
                wordIndex += 1
            }
            flush()
        }
        return lines
    }
}

/// An immutable, laid-out script. Equality is by identity, so large scripts compare cheaply.
public struct TeleprompterScript: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let lines: [ScriptLine]
    /// Normalised words, index-aligned with the layout (punctuation-only tokens are empty strings).
    public let words: [String]
    public var wordCount: Int { words.count }

    public static let maxCharacters = 100_000

    public init?(text: String, title: String, maxLineChars: Int, id: UUID = UUID()) {
        let clipped = String(text.prefix(Self.maxCharacters))
        let words = ScriptMatcher.normalize(clipped)
        guard !words.isEmpty else { return nil }
        self.id = id
        self.title = title
        self.words = words
        self.lines = ScriptLayout.wrap(clipped, maxChars: maxLineChars)
    }

    public static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}

// MARK: - Activity

/// Reading state. Position is stored as an anchor (word index at a moment) plus a rate, like media
/// playback, so the view extrapolates smoothly and the activity only changes on real events.
public struct TeleprompterActivity: Equatable, Sendable {
    public enum State: String, Equatable, Sendable { case paused, playing, finished }
    public static let speedRange: ClosedRange<Double> = 60...300
    public static let speedStep: Double = 10

    public let script: TeleprompterScript
    public private(set) var state: State = .paused
    public private(set) var wordsPerMinute: Double
    public private(set) var anchorWord: Double = 0
    public private(set) var anchorDate: Date
    /// Scrolls with the speaker's voice instead of a fixed speed.
    public private(set) var voiceFollow = false
    /// The speech recogniser is running (voice follow).
    public var listening = false
    /// Paused while the pointer rests on the Island.
    public private(set) var hoverPaused = false

    public init(script: TeleprompterScript, wordsPerMinute: Double, anchorDate: Date = Date()) {
        self.script = script
        self.wordsPerMinute = Self.clampSpeed(wordsPerMinute)
        self.anchorDate = anchorDate
    }

    var total: Double { Double(script.wordCount) }

    /// Words per second actually applied right now.
    public var rate: Double {
        state == .playing && !hoverPaused && !voiceFollow ? wordsPerMinute / 60 : 0
    }

    public func position(at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(anchorDate))
        return min(total, max(0, anchorWord + rate * elapsed))
    }

    public func progress(at date: Date) -> Double { total > 0 ? position(at: date) / total : 1 }

    /// When the timed scroll reaches the end, if it is moving.
    public var finishDate: Date? {
        guard rate > 0 else { return nil }
        return anchorDate.addingTimeInterval(max(0, total - anchorWord) / rate)
    }

    /// Fractional line index for the reading position. A line's words span the line itself plus any
    /// blank lines after it, so the scroll never jumps at paragraph breaks.
    public func lineOffset(at date: Date) -> Double {
        let p = position(at: date)
        let lines = script.lines
        let content = lines.indices.filter { lines[$0].wordCount > 0 }
        guard let last = content.last else { return 0 }
        for (n, i) in content.enumerated() {
            let line = lines[i]
            let end = Double(line.firstWord + line.wordCount)
            guard p < end else { continue }
            let next = n + 1 < content.count ? content[n + 1] : i + 1
            let fraction = max(0, p - Double(line.firstWord)) / Double(line.wordCount)
            return Double(i) + fraction * Double(next - i)
        }
        return Double(last + 1)
    }

    // MARK: Mutations (all re-anchor first, so changes never jump)

    public mutating func play(at date: Date) {
        if state == .finished || position(at: date) >= total { anchorWord = 0; anchorDate = date }
        rebase(at: date)
        state = .playing
    }

    public mutating func pause(at date: Date) {
        rebase(at: date)
        state = .paused
    }

    public mutating func markFinished(at date: Date) {
        rebase(at: date)
        state = .finished
    }

    public mutating func setSpeed(_ wpm: Double, at date: Date) {
        rebase(at: date)
        wordsPerMinute = Self.clampSpeed(wpm)
    }

    public mutating func setHoverPaused(_ paused: Bool, at date: Date) {
        rebase(at: date)
        hoverPaused = paused
    }

    public mutating func setVoiceFollow(_ on: Bool, at date: Date) {
        rebase(at: date)
        voiceFollow = on
        if !on { listening = false }
    }

    public mutating func seek(toWord word: Double, at date: Date? = nil) {
        anchorWord = min(total, max(0, word.isFinite ? word : 0))
        if let date { anchorDate = date }
        if state == .finished, anchorWord < total { state = .paused }
    }

    public mutating func skip(lines delta: Int, at date: Date) {
        rebase(at: date)
        let lines = script.lines
        let content = lines.indices.filter { lines[$0].wordCount > 0 }
        guard !content.isEmpty else { return }
        let currentLine = Int(lineOffset(at: date).rounded(.down))
        let currentSlot = content.lastIndex { $0 <= currentLine } ?? 0
        let target = min(content.count - 1, max(0, currentSlot + delta))
        seek(toWord: Double(lines[content[target]].firstWord), at: date)
    }

    private mutating func rebase(at date: Date) {
        anchorWord = position(at: date)
        anchorDate = date
    }

    public static func clampSpeed(_ wpm: Double) -> Double {
        min(speedRange.upperBound, max(speedRange.lowerBound, wpm.isFinite ? wpm : 140))
    }
}

// MARK: - Voice follow

/// Aligns recently heard words with the script. Pure and deterministic: no audio here.
public enum ScriptMatcher {
    public static let lookBehind = 4
    public static let lookAhead = 30
    static let window = 4

    /// Lowercased words with surrounding punctuation removed. Index-aligned with whitespace tokens.
    public static func normalize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(normalizeWord)
    }

    public static func normalizeWord<S: StringProtocol>(_ word: S) -> String {
        String(word.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "'" })
    }

    /// The word index after the best match of the heard tail near `current`, or nil when the
    /// evidence is too weak (fewer than two words, or the last word doesn't match).
    public static func advance(script words: [String], current: Int, heard: [String]) -> Int? {
        let tail = Array(heard.map { normalizeWord($0) }.filter { !$0.isEmpty }.suffix(window))
        guard tail.count >= 2, !words.isEmpty else { return nil }
        let k = tail.count
        let needed = max(2, k - 1)
        let low = max(0, current - lookBehind)
        let high = min(words.count - 1, current + lookAhead)
        guard low <= high else { return nil }

        var best: (end: Int, score: Int)?
        for end in low...high where words[end] == tail[k - 1] {
            var score = 0
            for i in 0..<k where end - i >= 0 && words[end - i] == tail[k - 1 - i] { score += 1 }
            guard score >= needed else { continue }
            if let b = best {
                let closer = abs(end + 1 - current) < abs(b.end + 1 - current)
                if score > b.score || (score == b.score && closer) { best = (end, score) }
            } else {
                best = (end, score)
            }
        }
        return best.map { $0.end + 1 }
    }
}
