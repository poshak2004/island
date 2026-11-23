import Foundation

// MARK: - Pinned items

/// Island's own features that can sit on the home surface.
public enum HomeFeature: Codable, Hashable, Sendable {
    case teleprompter, shelf, search
    case timer(minutes: Int)
}

/// Anything you can pin to the Island's home: an Island feature, an app, a Shortcut, a website or a
/// file/folder. Stored as data and turned into a typed `IslandCommand` only when you click it.
public enum HomeItem: Codable, Hashable, Sendable, Identifiable {
    case feature(HomeFeature)
    case app(path: String, name: String)
    case shortcut(name: String)
    case website(url: URL, title: String)
    case file(path: String, name: String)

    public var id: String { key }

    /// Stable identity used for de-duplication and usage history.
    public var key: String {
        switch self {
        case .feature(let f): "feature:\(f)"
        case .app(let path, _): "app:\(path)"
        case .shortcut(let name): "shortcut:\(name)"
        case .website(let url, _): "web:\(url.absoluteString)"
        case .file(let path, _): "file:\(path)"
        }
    }

    public var title: String {
        switch self {
        case .feature(let f):
            switch f {
            case .teleprompter: "Teleprompter"
            case .shelf: "File Shelf"
            case .search: "Search"
            case .timer(let m): "\(m) min"
            }
        case .app(_, let name): name
        case .shortcut(let name): name
        case .website(let url, let title): title.isEmpty ? (url.host ?? url.absoluteString) : title
        case .file(_, let name): name
        }
    }

    /// SF Symbol for items without a real icon (apps and files use their Finder icon).
    public var symbol: String {
        switch self {
        case .feature(let f):
            switch f {
            case .teleprompter: "text.alignleft"
            case .shelf: "tray.full.fill"
            case .search: "magnifyingglass"
            case .timer: "timer"
            }
        case .app: "app"
        case .shortcut: "square.2.layers.3d.fill"
        case .website: "globe"
        case .file: "doc"
        }
    }

    public var command: IslandCommand {
        switch self {
        case .feature(let f):
            switch f {
            case .teleprompter: .action(.startTeleprompter)
            case .shelf: .shelf(.reveal)
            case .search: .ui(.toggleSearch)
            case .timer(let m): .timer(.start(duration: TimeInterval(m * 60), label: "\(m) min"))
            }
        case .app(let path, _): .launchApplication(URL(fileURLWithPath: path))
        case .shortcut(let name): .runShortcut(name: name)
        case .website(let url, _): .openURL(url)
        case .file(let path, _): .openFile(URL(fileURLWithPath: path))
        }
    }

    /// The pinnable form of a search result, when it has one.
    public init?(result: SearchResult) {
        switch result.command {
        case .launchApplication(let url): self = .app(path: url.path, name: result.title)
        case .openFile(let url): self = .file(path: url.path, name: result.title)
        case .openURL(let url): self = .website(url: url, title: result.title)
        case .runShortcut(let name): self = .shortcut(name: name)
        case .action(.startTeleprompter): self = .feature(.teleprompter)
        case .timer(.start(let duration, _)) where duration > 0 && duration.truncatingRemainder(dividingBy: 60) == 0:
            self = .feature(.timer(minutes: Int(duration / 60)))
        default: return nil
        }
    }
}

public enum HomePins {
    public static let maxPins = 12
    public static let defaults: [HomeItem] = [.feature(.teleprompter), .feature(.shelf), .feature(.timer(minutes: 25))]

    public static func adding(_ item: HomeItem, to pins: [HomeItem]) -> [HomeItem] {
        guard !pins.contains(item), pins.count < maxPins else { return pins }
        return pins + [item]
    }

    public static func removing(_ item: HomeItem, from pins: [HomeItem]) -> [HomeItem] {
        pins.filter { $0 != item }
    }

    public static func moving(_ item: HomeItem, to index: Int, in pins: [HomeItem]) -> [HomeItem] {
        guard pins.contains(item) else { return pins }
        var rest = pins.filter { $0 != item }
        rest.insert(item, at: min(max(0, index), rest.count))
        return rest
    }
}

// MARK: - Usage history

/// What you open from the Island and when, kept small and local, so home can suggest your habits.
public struct HomeUsage: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let item: HomeItem
        public var uses: [Date]
    }
    public static let maxEntries = 60
    static let maxUsesPerItem = 20
    /// A use counts half as much after this long.
    static let halfLife: TimeInterval = 14 * 86_400

    public private(set) var entries: [String: Entry] = [:]
    public init() {}

    public func recording(_ item: HomeItem, at date: Date) -> HomeUsage {
        var copy = self
        var entry = copy.entries[item.key] ?? Entry(item: item, uses: [])
        entry.uses = Array((entry.uses + [date]).suffix(Self.maxUsesPerItem))
        copy.entries[item.key] = entry
        if copy.entries.count > Self.maxEntries {
            let weakest = copy.entries.min { copy.score(forKey: $0.key, at: date) < copy.score(forKey: $1.key, at: date) }
            if let weakest { copy.entries[weakest.key] = nil }
        }
        return copy
    }

    public func score(for item: HomeItem, at date: Date) -> Double { score(forKey: item.key, at: date) }

    func score(forKey key: String, at date: Date) -> Double {
        (entries[key]?.uses ?? []).reduce(0) { sum, use in
            sum + pow(0.5, max(0, date.timeIntervalSince(use)) / Self.halfLife)
        }
    }
}

// MARK: - Context and suggestions

public struct HomeEvent: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var joinURL: URL?
    public init(title: String, start: Date, joinURL: URL?) {
        self.title = title
        self.start = start
        self.joinURL = joinURL
    }
}

public struct HomeFile: Equatable, Sendable {
    public var name: String
    public var url: URL
    public var at: Date
    public init(name: String, url: URL, at: Date) {
        self.name = name
        self.url = url
        self.at = at
    }
}

/// Everything home looks at to decide what's useful right now.
public struct HomeContext: Sendable {
    public var now: Date
    public var event: HomeEvent?
    public var cameraOn = false
    public var hasTeleprompterScript = false
    public var recentDownload: HomeFile?
    public var usage = HomeUsage()
    public var pinned: [HomeItem] = []
    public init(now: Date) { self.now = now }
}

public enum HomeSuggestion: Equatable, Sendable, Identifiable {
    case joinEvent(title: String, url: URL)
    case startTeleprompter
    case shelveDownload(name: String, url: URL)
    case frequent(HomeItem)

    public var id: String {
        switch self {
        case .joinEvent(_, let url): "join:\(url.absoluteString)"
        case .startTeleprompter: "teleprompter"
        case .shelveDownload(_, let url): "shelve:\(url.path)"
        case .frequent(let item): "frequent:\(item.key)"
        }
    }

    public var title: String {
        switch self {
        case .joinEvent(let title, _): "Join \(title)"
        case .startTeleprompter: "Teleprompter"
        case .shelveDownload(let name, _): "Keep \(name) on Shelf"
        case .frequent(let item): item.title
        }
    }

    public var symbol: String {
        switch self {
        case .joinEvent: "video.fill"
        case .startTeleprompter: "text.alignleft"
        case .shelveDownload: "tray.and.arrow.down.fill"
        case .frequent(let item): item.symbol
        }
    }

    public var command: IslandCommand {
        switch self {
        case .joinEvent(_, let url): .openURL(url)
        case .startTeleprompter: .action(.startTeleprompter)
        case .shelveDownload(_, let url): .shelf(.add([url]))
        case .frequent(let item): item.command
        }
    }
}

public enum HomeSuggestionEngine {
    public static let maxSuggestions = 3
    static let joinWindowBefore: TimeInterval = 10 * 60
    static let joinWindowAfter: TimeInterval = 10 * 60
    static let freshDownload: TimeInterval = 10 * 60
    /// Roughly "used twice recently": one use is not a habit.
    static let habitScore = 1.8

    public static func suggest(_ c: HomeContext) -> [HomeSuggestion] {
        var out: [HomeSuggestion] = []
        if let e = c.event, let url = e.joinURL,
           e.start.timeIntervalSince(c.now) <= joinWindowBefore, c.now.timeIntervalSince(e.start) <= joinWindowAfter {
            out.append(.joinEvent(title: e.title, url: url))
        }
        if c.cameraOn, c.hasTeleprompterScript, !c.pinned.contains(.feature(.teleprompter)) {
            out.append(.startTeleprompter)
        }
        if let d = c.recentDownload, c.now.timeIntervalSince(d.at) <= freshDownload {
            out.append(.shelveDownload(name: d.name, url: d.url))
        }
        // Spelled out step by step: older compilers time out type-checking this as one chain.
        var habits: [(item: HomeItem, score: Double)] = []
        for entry in c.usage.entries.values {
            let score: Double = c.usage.score(for: entry.item, at: c.now)
            if score >= habitScore, !c.pinned.contains(entry.item) { habits.append((entry.item, score)) }
        }
        habits.sort { a, b in a.score != b.score ? a.score > b.score : a.item.key < b.item.key }
        for habit in habits { out.append(HomeSuggestion.frequent(habit.item)) }
        return Array(out.prefix(maxSuggestions))
    }
}

public enum HomeStatus {
    static let soonWindow: TimeInterval = 60 * 60
    static let todayWindow: TimeInterval = 12 * 3600
    static let inProgressWindow: TimeInterval = 15 * 60

    /// One short line about what's next, or nil when there's nothing worth saying.
    public static func line(now: Date, event: HomeEvent?) -> String? {
        guard let e = event else { return nil }
        let until = e.start.timeIntervalSince(now)
        if until <= 0 { return -until <= inProgressWindow ? "\(e.title) now" : nil }
        if until <= soonWindow { return "\(e.title) in \(Int((until / 60).rounded(.up))) min" }
        if until <= todayWindow {
            let f = DateFormatter()
            f.timeStyle = .short
            f.dateStyle = .none
            return "\(e.title) at \(f.string(from: e.start))"
        }
        return nil
    }
}

/// Finds a video-call link (Meet, Zoom, Teams, Webex, FaceTime…) in an event's URL, location or notes.
public enum MeetingLink {
    static let hosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "webex.com",
                        "whereby.com", "facetime.apple.com", "around.co", "chime.aws"]

    public static func find(in fields: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for field in fields.compactMap({ $0 }) {
            let range = NSRange(field.startIndex..., in: field)
            for match in detector.matches(in: field, range: range) {
                guard let url = match.url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { continue }
                if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }
}
