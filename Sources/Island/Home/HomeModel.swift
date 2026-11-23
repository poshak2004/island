import AppKit
import IslandCore
import Observation

/// The Island's home: your pinned items, context suggestions and the status line.
/// Usage history (what you open, when) stays on this Mac and only feeds suggestions.
@MainActor
@Observable
final class HomeModel {
    static let usageKey = "island.home.usage.v1"

    @ObservationIgnored let settings: IslandSettings
    @ObservationIgnored let shortcuts: ShortcutsCatalog
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var commands: CommandRouter?
    /// Supplies live state (calendar, camera, downloads) when suggestions are computed.
    @ObservationIgnored var context: () -> HomeContext = { HomeContext(now: Date()) }
    private(set) var usage = HomeUsage()
    /// The last finished download, for "Keep … on Shelf".
    var recentDownload: HomeFile?
    /// Diagnostics only: stands in for the calendar's next event.
    var eventOverride: HomeEvent?

    init(settings: IslandSettings, shortcuts: ShortcutsCatalog, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.shortcuts = shortcuts
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.usageKey), let saved = try? JSONDecoder().decode(HomeUsage.self, from: data) {
            usage = saved
        }
    }

    var pins: [HomeItem] { settings.homePins }

    func suggestions(at date: Date) -> [HomeSuggestion] {
        guard settings.homeSuggestions else { return [] }
        var c = context()
        c.now = date
        if let eventOverride { c.event = eventOverride }
        c.usage = usage
        c.pinned = pins
        c.recentDownload = recentDownload
        return HomeSuggestionEngine.suggest(c)
    }

    func statusLine(at date: Date) -> String? { HomeStatus.line(now: date, event: eventOverride ?? context().event) }

    // MARK: Actions

    func open(_ item: HomeItem) {
        record(item)
        commands?.perform(item.command)
        collapseUnless(item.command)
    }

    func open(_ suggestion: HomeSuggestion) {
        if case .frequent(let item) = suggestion { record(item) }
        if case .shelveDownload = suggestion { recentDownload = nil }
        commands?.perform(suggestion.command)
        collapseUnless(suggestion.command)
    }

    /// Something was opened from search: count it towards habits when it's pinnable.
    func noteOpened(_ result: SearchResult) {
        if let item = HomeItem(result: result) { record(item) }
    }

    func pin(_ item: HomeItem) { settings.homePins = HomePins.adding(item, to: settings.homePins) }
    func unpin(_ item: HomeItem) { settings.homePins = HomePins.removing(item, from: settings.homePins) }
    func isPinned(_ item: HomeItem) -> Bool { settings.homePins.contains(item) }
    func move(_ item: HomeItem, by offset: Int) {
        guard let i = settings.homePins.firstIndex(of: item) else { return }
        settings.homePins = HomePins.moving(item, to: i + offset, in: settings.homePins)
    }

    func clearHistory() {
        usage = HomeUsage()
        defaults.removeObject(forKey: Self.usageKey)
    }

    // MARK: Internals

    private func record(_ item: HomeItem) {
        usage = usage.recording(item, at: Date())
        if let data = try? JSONEncoder().encode(usage) { defaults.set(data, forKey: Self.usageKey) }
    }

    /// Opening something elsewhere closes the Island; Island features (shelf, search, teleprompter) take it over instead.
    private func collapseUnless(_ command: IslandCommand) {
        switch command {
        case .ui, .shelf(.reveal), .action(.startTeleprompter): return
        default: commands?.perform(.ui(.collapse))
        }
    }
}
