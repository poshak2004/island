import IslandCore
import SwiftUI

/// The Island's SwiftUI content. The surface itself — outline, glass, clip and the open/close
/// morph — is `IslandSurfaceView` (Core Animation), so this view is laid out at its final size and
/// never re-laid-out frame by frame while the Island springs.
struct IslandRootView: View {
    let model: IslandViewModel
    let search: SearchViewModel

    var body: some View {
        let metrics = model.metrics
        let mode = model.mode
        let canvas = metrics.windowSize
        // Read here so a change re-renders the Island with the right text contrast.
        let _ = { IslandPalette.increasedContrast = model.highContrast }()

        content(metrics: metrics, size: model.islandSize)
            .offset(x: mode == .compact ? model.horizontalOffset : 0)
            .frame(width: canvas.width, height: canvas.height, alignment: .top)
            // Clicks only reach this window inside the Island (the rest is click-through).
            .contentShape(Rectangle())
            .onTapGesture { model.click() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Island")
            .accessibilityAddTraits(mode == .compact ? .isButton : [])
            .accessibilityAction(named: mode == .expanded ? "Collapse" : "Expand") {
                mode == .expanded ? model.collapse() : model.expand()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // No shared matched-geometry namespace: compact and expanded are both mounted and crossfade,
            // and duplicate matched IDs in mounted views would misplace content.
            .environment(\.islandReduceMotion, model.reduceMotion)
            .environment(\.airPodsRevealed, model.airPods.map { $0.phase == .idle || $0.isRevealed } ?? true)
            .environment(\.islandCommands, model.commandSink)
            .environment(\.colorScheme, .dark)
            .environment(\.teleprompterFontSize, CGFloat(model.settings.teleprompterFontSize))
            .environment(\.teleprompterReady, !model.settings.teleprompterScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !model.manager.ordered.contains { $0.kind == .teleprompter })
            .animation(IslandAnimation.contentChange(reduceMotion: model.reduceMotion), value: model.manager.primary?.id)
            .animation(IslandAnimation.contentChange(reduceMotion: model.reduceMotion), value: model.manager.secondaries.map(\.id))
    }

    /// Compact and expanded stay mounted and crossfade, so opening never builds views mid-animation
    /// (that's what dropped frames). Hidden layers don't take clicks, aren't announced by VoiceOver,
    /// and their once-per-second clocks pause (`islandContentActive`).
    @ViewBuilder
    private func content(metrics: IslandMetrics, size: CGSize) -> some View {
        let mode = model.mode
        let reduce = model.reduceMotion
        ZStack(alignment: .top) {
            if let primary = model.primary {
                let compactShown = mode == .compact
                CompactLayout(activity: primary, minimals: Array(model.secondaries.prefix(IslandMetrics.maxMinimals)),
                              metrics: metrics, style: model.compactStyle, showsTitle: model.settings.compactShowsTitle,
                              overflow: model.manager.overflowCount)
                    .offset(x: metrics.horizontalOffset(mode: .compact, compact: model.compactStyle,
                                                        minimals: min(model.secondaries.count, IslandMetrics.maxMinimals)))
                    .id("compact-\(primary.id)")
                    .environment(\.islandContentActive, compactShown)
                    .layer(shown: compactShown, reduceMotion: reduce)
            }
            ExpandedLayout(model: model, metrics: metrics)
                .frame(width: metrics.expandedWidth(model.expandedStyle))
                .environment(\.islandContentActive, mode == .expanded)
                .layer(shown: mode == .expanded, reduceMotion: reduce)
            if mode == .search {
                SearchSurface(model: search, metrics: metrics)
                    .frame(width: metrics.searchWidth, height: size.height, alignment: .top)
                    .transition(IslandAnimation.contentTransition(reduceMotion: reduce))
            }
        }
    }
}

private extension View {
    /// Crossfade a mounted layer on the shared content springs: leaving is quick, arriving follows.
    func layer(shown: Bool, reduceMotion: Bool) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97, anchor: .top)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .animation(shown ? IslandAnimation.contentIn(reduceMotion: reduceMotion)
                             : IslandAnimation.contentOut(reduceMotion: reduceMotion), value: shown)
    }
}

/// `[ minimal₂ │ leading ]  notch  [ trailing │ minimal₁ ]` — both wings the same width, so the pill
/// stays centred on the notch; every minimal gets the same fixed square, vertically centred.
struct CompactLayout: View {
    let activity: Activity
    let minimals: [Activity]
    let metrics: IslandMetrics
    let style: CompactStyle
    var showsTitle = false
    /// Live activities beyond the visible bubbles: a "+N" badge, so nothing is silently hidden.
    var overflow = 0
    @Environment(\.islandNamespace) private var ns

    var body: some View {
        let wings = metrics.compactWings(style, minimals: minimals.count)
        let pad = max(8, metrics.compactHeight * 0.28)
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                if minimals.count > 1 {
                    minimal(minimals[1])
                    separator
                }
                CompactLeadingView(activity: activity, showsTitle: showsTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: wings.leading - pad, height: metrics.compactHeight)
            .padding(.leading, pad)
            Color.clear.frame(width: metrics.notchSize.width)
            HStack(spacing: 0) {
                CompactTrailingView(activity: activity)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if let first = minimals.first {
                    separator
                    minimal(first)
                        .overlay(alignment: .topTrailing) { if overflow > 0 { overflowBadge } }
                }
            }
            .frame(width: wings.trailing - pad, height: metrics.compactHeight)
            .padding(.trailing, pad)
        }
        .frame(height: metrics.compactHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ActivityPresentation.accessibilityLabel(for: activity))
    }

    private var overflowBadge: some View {
        Text("+\(overflow)")
            .font(.system(size: 9, weight: .bold).monospacedDigit())
            .foregroundStyle(.black)
            .padding(.horizontal, 3)
            .background(Capsule().fill(.white))
            .offset(x: 2, y: 3)
            .accessibilityLabel("\(overflow) more")
    }

    private var separator: some View {
        Capsule().fill(.white.opacity(0.18))
            .frame(width: 1, height: metrics.compactHeight * 0.45)
            .frame(width: metrics.minimalSeparator)
    }

    private func minimal(_ m: Activity) -> some View {
        MinimalView(activity: m)
            .frame(width: 18 * metrics.scale, height: 18 * metrics.scale)
            .frame(width: metrics.minimalSlot, height: metrics.compactHeight)
            .islandMatched("bubble-\(m.id)", in: ns)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ActivityPresentation.accessibilityLabel(for: m))
            .transition(.opacity.combined(with: .scale(scale: 0.6)))
    }
}

/// Expanded surface: a header that straddles the notch, then the activity's interactive content.
struct ExpandedLayout: View {
    let model: IslandViewModel
    let metrics: IslandMetrics
    @Environment(\.islandNamespace) private var ns

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: metrics.compactHeight)
            ZStack(alignment: .top) {
                if model.isShowingHome, let home = model.home {
                    HomeView(home: home)
                        .transition(IslandAnimation.contentTransition(reduceMotion: model.reduceMotion))
                } else if let primary = model.primary {
                    ExpandedActivityView(activity: primary)
                        .id(primary.id)
                        .transition(IslandAnimation.contentTransition(reduceMotion: model.reduceMotion))
                }
            }
            // Natural height, independent of the (animating) container — reported so the Island sizes to fit.
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geo in
                Color.clear.preference(key: ExpandedContentHeightKey.self, value: geo.size.height)
            })
            .onPreferenceChange(ExpandedContentHeightKey.self) { [style = model.expandedStyle] h in
                model.reportContentHeight(h, for: style)
            }
            .padding(.horizontal, isBanner ? IslandMetrics.airPodsBannerMargin : 22)
            .padding(.top, IslandMetrics.expandedTopPadding)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        // The banner replaces whatever was there outright: a crossfade let the Home clock ghost through.
        // Scoped to the switch itself, so the banner's own animations (the ring sweep) still run.
        .transaction(value: isBanner) { t in if isBanner { t.animation = nil } }
    }

    /// The AirPods banner has no header: just the notch band, then its one row.
    private var isBanner: Bool { model.expandedStyle == .airPods }

    @ViewBuilder private var header: some View {
        if isBanner {
            Color.clear
        } else if model.isShowingHome, model.primary == nil, let home = model.home {
            HomeHeader(home: home, notchWidth: metrics.notchSize.width)
        } else {
            activityHeader
        }
    }

    private var activityHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if model.showsHome { Text("Home").lineLimit(1) } else if let p = model.primary { Text(title(for: p)).lineLimit(1) }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(IslandPalette.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 22)
            Color.clear.frame(width: metrics.notchSize.width)
            ActivitySwitcher(model: model)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 22) // matches the 22 pt leading margin
        }
    }

    /// Media names its source; the teleprompter names its script. Other content says what it is.
    private func title(for a: Activity) -> String {
        switch a.content {
        case .media(let m): return m.sourceName
        case .teleprompter(let t): return t.script.title.isEmpty ? "Teleprompter" : t.script.title
        case .shelf: return "File Shelf"
        default: return ""
        }
    }
}

struct ExpandedContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Small activity tabs in the expanded header. They share geometry with the compact bubbles.
struct ActivitySwitcher: View {
    static let maxTabs = 5
    let model: IslandViewModel
    @Environment(\.islandNamespace) private var ns

    var body: some View {
        // Every live activity gets a tab (up to a handful), so none is ever unreachable.
        let items = Array(model.manager.ordered.prefix(Self.maxTabs))
        if !items.isEmpty, model.home != nil {
            HStack(spacing: 4) {
                // Home is always one click away, even while something is playing.
                Button { model.showHome(true) } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(model.showsHome ? 0.2 : 0.06)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .help("Home")
                .accessibilityLabel("Home")
                .accessibilityAddTraits(model.showsHome ? .isSelected : [])
                ForEach(items) { a in
                    let selected = a.id == model.primary?.id && !model.showsHome
                    Button {
                        model.showHome(false)
                        model.commands.perform(.ui(.select(activityID: a.id)))
                    } label: {
                        MinimalView(activity: a)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(.white.opacity(selected ? 0.2 : 0.06)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .islandMatched("bubble-\(a.id)", in: ns)
                    .accessibilityLabel(ActivityPresentation.accessibilityLabel(for: a))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}
