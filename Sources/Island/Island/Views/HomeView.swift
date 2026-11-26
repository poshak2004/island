import AppKit
import IslandCore
import SwiftUI

/// The Island's home: one way in to do anything (search), what's useful right now (suggestions), and
/// what you chose (pins). The time and the status line live in the header row beside the notch.
struct HomeView: View {
    let home: HomeModel
    @Environment(\.islandCommands) private var send
    @Environment(\.islandContentActive) private var active
    @State private var adding = false

    var body: some View {
        if !home.settings.hasCompletedWelcome {
            WelcomeView(settings: home.settings)
        } else {
            content
        }
    }

    /// Search, your pins in one row, and one line for what matters now. Everything else (adding pins,
    /// Settings) is a right-click away — the Island shows content, not controls.
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchBar
            if adding {
                HomePicker(home: home) { adding = false }
            } else {
                pinsRow
                TimelineView(.everyMinute) { ctx in nowLine(at: ctx.date) }
            }
        }
        .contextMenu {
            Button("Add to Home…") { adding = true }
            Button("Settings…") { send(.openSettings) }
        }
        .onChange(of: active) { _, isActive in if !isActive { adding = false } }
    }

    // MARK: Search

    /// Only promise "ask" when AI answers are actually on.
    private var searchPrompt: String {
        home.settings.effectiveAIProvider != .none ? "Search, open, or ask anything" : "Search apps, files, and actions"
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Button { send(.ui(.toggleSearch)) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold))
                    Text(searchPrompt).font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 4)
                    Text(home.settings.searchShortcut.display)
                        .font(.system(size: 11, weight: .semibold).monospaced())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.1)))
                }
                .foregroundStyle(.white.opacity(0.62))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.09)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(searchPrompt)
            .accessibilityHint("Shortcut \(home.settings.searchShortcut.display)")
        }
    }

    // MARK: Suggested

    /// One line: the most useful suggestion (a meeting to join, a download to keep), else the status.
    @ViewBuilder private func nowLine(at date: Date) -> some View {
        if let s = home.suggestions(at: date).first {
            Button { home.open(s) } label: {
                Label(s.title, systemImage: s.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .help(s.title)
        } else if let status = home.statusLine(at: date) {
            Text(status)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IslandPalette.secondaryText)
                .lineLimit(1)
        }
    }

    // MARK: Pins

    /// Every pin in one row (scrolls sideways past what fits, so none is hidden). An empty Home offers
    /// one clear next step instead of an empty grid.
    @ViewBuilder private var pinsRow: some View {
        if home.pins.isEmpty {
            IslandPillButton(title: "Add to Home", symbol: "plus", tint: .white) { adding = true }
                .help("Pin apps, Shortcuts, timers and more. You can also right-click a search result.")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(home.pins) { item in
                        HomeTile(item: item) { home.open(item) }
                            .contextMenu {
                                Button("Open") { home.open(item) }
                                Button("Move Left") { home.move(item, by: -1) }.disabled(home.pins.first == item)
                                Button("Move Right") { home.move(item, by: 1) }.disabled(home.pins.last == item)
                                Divider()
                                Button("Remove from Home") { home.unpin(item) }
                                Button("Add to Home…") { adding = true }
                            }
                    }
                }
            }
        }
    }
}

// MARK: - Picker

/// Add to Home, inside the Island: Island features, your apps and your Shortcuts. Click to pin or unpin.
private struct HomePicker: View {
    let home: HomeModel
    var done: () -> Void
    @State private var source: Source = .island
    @State private var shortcutNames: [String]?

    enum Source: String, CaseIterable, Identifiable {
        case island = "Island", apps = "Apps", shortcuts = "Shortcuts"
        var id: String { rawValue }
    }

    static let islandItems: [HomeItem] = [
        .feature(.teleprompter), .feature(.shelf), .feature(.search),
        .feature(.timer(minutes: 5)), .feature(.timer(minutes: 10)), .feature(.timer(minutes: 25)), .feature(.timer(minutes: 50)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Source.allCases) { s in
                    Button { source = s } label: {
                        Text(s.rawValue).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(source == s ? .black : .white)
                            .padding(.horizontal, 11).frame(height: 28)
                            .background(Capsule().fill(source == s ? .white : .white.opacity(0.1)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(source == s ? .isSelected : [])
                }
                Spacer()
                IslandPillButton(title: "Done", symbol: nil, tint: .white, action: done)
            }
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: HomeTileStyle.columns, alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        let pinned = home.isPinned(item)
                        HomeTile(item: item, checked: pinned) { pinned ? home.unpin(item) : home.pin(item) }
                            .accessibilityValue(pinned ? "Pinned" : "Not pinned")
                    }
                }
                .padding(.vertical, 2)
                if source == .shortcuts, shortcutNames?.isEmpty == true {
                    Text("No shortcuts yet. Make one in the Shortcuts app and it shows up here.")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(IslandPalette.secondaryText)
                }
            }
            .frame(height: 150)
            Text("Websites and files: right-click a search result and choose Pin to Home.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .task(id: source) {
            if source == .shortcuts, shortcutNames == nil { shortcutNames = await home.shortcuts.names() }
        }
    }

    private var items: [HomeItem] {
        switch source {
        case .island: return Self.islandItems
        case .apps: return HomeApps.list()
        case .shortcuts: return (shortcutNames ?? []).map { .shortcut(name: $0) }
        }
    }
}

/// Running apps first (what you use now), then everything installed, alphabetically.
@MainActor
enum HomeApps {
    static var installed: () -> [(name: String, url: URL)] = { [] }

    static func list() -> [HomeItem] {
        var seen = Set<String>()
        var out: [HomeItem] = []
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, URL)? in app.bundleURL.map { (app.localizedName ?? $0.deletingPathExtension().lastPathComponent, $0) } }
        for (name, url) in running + installed().map({ ($0.name, $0.url) }) where !seen.contains(url.path) {
            guard url.path.hasPrefix("/Applications") || url.path.hasPrefix("/System/Applications")
                || url.path.hasPrefix(NSHomeDirectory() + "/Applications") else { continue }
            seen.insert(url.path)
            out.append(.app(path: url.path, name: name))
        }
        return out
    }
}

// MARK: - Tiles

enum HomeTileStyle {
    /// Wide enough for "Teleprompter" at 11 pt, so every label is the same size (no shrinking).
    static let width: CGFloat = 74
    static let icon: CGFloat = 40
    static let columns = Array(repeating: GridItem(.fixed(width), spacing: 4, alignment: .top), count: 6)

    static func tint(_ item: HomeItem) -> Color {
        switch item {
        case .feature(.teleprompter): TeleprompterStyle.tint
        case .feature(.shelf): ShelfStyle.tint
        case .feature(.timer): IslandPalette.timer
        case .feature(.search): .white
        case .shortcut: Color(nsColor: .systemPink)
        case .website: Color(nsColor: .systemBlue)
        case .app, .file: .white
        }
    }
}

struct HomeTile: View {
    let item: HomeItem
    var checked = false
    /// Off where the title already sits beside the icon (Settings › Home), so it isn't said twice.
    var showsTitle = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                icon
                    .frame(width: HomeTileStyle.icon, height: HomeTileStyle.icon)
                    .overlay(alignment: .topTrailing) {
                        if checked {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.black, .white)
                                .offset(x: 5, y: -5)
                        }
                    }
                if showsTitle {
                    Text(item.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                }
            }
            .frame(width: showsTitle ? HomeTileStyle.width : HomeTileStyle.icon)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(item.title)
        .accessibilityLabel(item.title)
    }

    @ViewBuilder private var icon: some View {
        switch item {
        case .app(let path, _), .file(let path, _):
            Image(nsImage: ImageCache.fileIcon(path: path)).resizable().interpolation(.high)
        default:
            let tint = HomeTileStyle.tint(item)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(tint.opacity(0.18))
                .overlay {
                    if case .feature(.timer(let m)) = item {
                        Text("\(m)").font(.system(size: 16, weight: .bold).monospacedDigit()).foregroundStyle(tint)
                    } else {
                        Image(systemName: item.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
                    }
                }
        }
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
            .accessibilityAddTraits(.isHeader)
    }
}

/// Time and the next thing on your calendar, in the row beside the notch.
/// Home's header context: the time and date, beside the notch. (The status line now lives in Home's
/// body, so the header has the same shape everywhere: context left, tabs right.)
struct HomeClock: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            HStack(spacing: 6) {
                Text(ctx.date, format: .dateTime.hour().minute()).foregroundStyle(.white)
                Text(ctx.date, format: .dateTime.weekday(.abbreviated).day())
                    .foregroundStyle(IslandPalette.secondaryText)
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .combine)
        }
    }
}
