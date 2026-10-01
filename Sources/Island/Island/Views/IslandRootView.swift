import IslandCore
import SwiftUI

/// The one and only Island surface. Every state is the same view tree morphing — size, corner radii,
/// material and content all animate together from a single state change.
struct IslandRootView: View {
    let model: IslandViewModel
    let search: SearchViewModel
    @Namespace private var ns

    var body: some View {
        let metrics = model.metrics
        let mode = model.mode
        let size = model.islandSize
        let ear = metrics.topEarRadius(mode: mode)
        let shape = IslandShape(earRadius: ear, bottomRadius: metrics.bottomCornerRadius(mode: mode, height: size.height))
        let open = mode == .expanded || mode == .search
        // Compact uses see-through glass (setting) so the Island doesn't read as a black slab over the menu bar.
        let compactGlass = mode == .compact && model.settings.compactGlass
        let glass = open || compactGlass ? model.settings.glassIntensity : 0

        ZStack(alignment: .top) {
            IslandBackground(shape: shape, glassAmount: glass, clear: compactGlass,
                             reduceTransparency: model.reduceTransparency, highContrast: model.highContrast)
                .opacity(mode == .idle ? (metrics.hasNotch ? 1 : 0) : 1)
            content(metrics: metrics, size: size)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape.inset(ear: ear))
        }
        .frame(width: size.width + 2 * ear, height: max(size.height, 0.5))
        .contentShape(shape)
        .onTapGesture { model.click() }
        .offset(x: model.horizontalOffset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Island")
        .accessibilityAddTraits(mode == .compact ? .isButton : [])
        .accessibilityAction(named: mode == .expanded ? "Collapse" : "Expand") {
            mode == .expanded ? model.collapse() : model.expand()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.islandNamespace, ns)
        .environment(\.islandReduceMotion, model.reduceMotion)
        .environment(\.islandCommands, IslandCommandSink { [weak model] c in model?.commands.perform(c) })
        .environment(\.colorScheme, .dark)
        .animation(model.morphAnimation, value: model.manager.primary?.id)
        .animation(model.morphAnimation, value: model.manager.secondaries.map(\.id))
    }

    @ViewBuilder
    private func content(metrics: IslandMetrics, size: CGSize) -> some View {
        let transition = IslandAnimation.contentTransition(reduceMotion: model.reduceMotion)
        switch model.mode {
        case .idle:
            Color.clear
        case .compact:
            if let primary = model.primary {
                CompactLayout(activity: primary, minimals: model.minimals, metrics: metrics, style: model.compactStyle,
                              showsTitle: model.settings.compactShowsTitle)
                    .transition(transition)
                    .id("compact-\(primary.id)")
            }
        case .expanded:
            ExpandedLayout(model: model, metrics: metrics)
                .transition(transition)
        case .search:
            SearchSurface(model: search, metrics: metrics)
                .transition(transition)
        }
    }
}

private extension IslandShape {
    /// Content clip: the body without the ears.
    func inset(ear: CGFloat) -> some Shape {
        IslandShape(earRadius: 0, bottomRadius: bottomRadius)
    }
}

/// `[ leading ]  notch  [ trailing · minimals ]`
struct CompactLayout: View {
    let activity: Activity
    let minimals: [Activity]
    let metrics: IslandMetrics
    let style: CompactStyle
    var showsTitle = false
    @Environment(\.islandNamespace) private var ns

    var body: some View {
        let wings = metrics.compactWings(style, minimals: minimals.count)
        let pad = max(8, metrics.compactHeight * 0.28)
        HStack(spacing: 0) {
            CompactLeadingView(activity: activity, showsTitle: showsTitle)
                .frame(width: wings.leading - pad, alignment: .leading)
                .padding(.leading, pad)
            Color.clear.frame(width: metrics.notchSize.width)
            HStack(spacing: 0) {
                CompactTrailingView(activity: activity)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if !minimals.isEmpty {
                    Capsule().fill(.white.opacity(0.18)).frame(width: 1, height: metrics.compactHeight * 0.45)
                        .padding(.horizontal, 4)
                    ForEach(minimals) { m in
                        MinimalView(activity: m)
                            .frame(width: 18, height: 18)
                            .frame(width: metrics.minimalSlot)
                            .islandMatched("bubble-\(m.id)", in: ns)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(ActivityPresentation.accessibilityLabel(for: m))
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
            }
            .frame(width: wings.trailing - pad)
            .padding(.trailing, pad)
        }
        .frame(height: metrics.compactHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ActivityPresentation.accessibilityLabel(for: activity))
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
                if let primary = model.primary {
                    ExpandedActivityView(activity: primary)
                        .id(primary.id)
                        .transition(IslandAnimation.contentTransition(reduceMotion: model.reduceMotion))
                } else {
                    HomeView()
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
            .padding(.horizontal, 22)
            .padding(.top, IslandMetrics.expandedTopPadding)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if let p = model.primary { Text(title(for: p)).lineLimit(1) }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(IslandPalette.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 22)
            Color.clear.frame(width: metrics.notchSize.width)
            ActivitySwitcher(model: model)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 20)
        }
    }

    /// Only media names its source (the content already says what every other activity is).
    private func title(for a: Activity) -> String {
        if case .media(let m) = a.content { return m.sourceName }
        return ""
    }
}

struct ExpandedContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Small activity tabs in the expanded header. They share geometry with the compact bubbles.
struct ActivitySwitcher: View {
    let model: IslandViewModel
    @Environment(\.islandNamespace) private var ns

    var body: some View {
        let items = Array(model.manager.ordered.prefix(model.manager.maxSecondaries + 1))
        if items.count > 1 {
            HStack(spacing: 4) {
                ForEach(items) { a in
                    let selected = a.id == model.primary?.id
                    Button { model.commands.perform(.ui(.select(activityID: a.id))) } label: {
                        MinimalView(activity: a)
                            .frame(width: 20, height: 20)
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
