import AppKit
import IslandCore
import Observation
import SwiftUI

/// Drives the Island UI: combines activity state, presentation state, geometry and preferences.
/// Owns hover-intent / collapse timing. Features never touch this type directly.
@MainActor
@Observable
final class IslandViewModel {
    let manager: ActivityManager
    let settings: IslandSettings
    let accessibility: AccessibilityMonitor
    @ObservationIgnored var commands: CommandRouter

    private(set) var presentation = IslandPresentation()
    private(set) var geometry: NotchGeometry?
    var searchHeight: CGFloat = 0
    /// Bumped on every mode change; useful for diagnostics and tests.
    private(set) var transitionCount = 0
    private(set) var isAnimating = false

    @ObservationIgnored private var hoverWork: DispatchWorkItem?
    @ObservationIgnored private var collapseWork: DispatchWorkItem?
    @ObservationIgnored private var transientWork: DispatchWorkItem?
    @ObservationIgnored private var animationEndWork: DispatchWorkItem?
    @ObservationIgnored private(set) var mouseInside = false
    @ObservationIgnored var onModeChange: ((IslandMode) -> Void)?

    init(manager: ActivityManager, settings: IslandSettings, accessibility: AccessibilityMonitor, commands: CommandRouter) {
        self.manager = manager
        self.settings = settings
        self.accessibility = accessibility
        self.commands = commands
        presentation.hoverExpansionEnabled = settings.hoverExpansion
        observeActivities()
    }

    // MARK: Derived state

    var mode: IslandMode { presentation.mode }
    var primary: Activity? { manager.primary }
    var secondaries: [Activity] { manager.secondaries }

    var metrics: IslandMetrics {
        IslandMetrics(
            notchSize: geometry?.notchSize ?? CGSize(width: DisplayResolver.virtualNotchWidth, height: 32),
            hasNotch: geometry?.hasNotch ?? false,
            scale: settings.islandScale,
            expandedCornerRadius: settings.cornerRadius
        )
    }

    var compactStyle: CompactStyle { ActivityPresentation.compactStyle(for: primary) }
    var expandedStyle: ExpandedStyle { ActivityPresentation.expandedStyle(for: primary) }

    var islandSize: CGSize {
        metrics.size(mode: mode, compact: compactStyle, expanded: expandedStyle, searchHeight: searchHeight)
    }

    var visibleBubbles: [Activity] { mode == .compact ? secondaries : [] }

    var reduceMotion: Bool { settings.forceReduceMotion || accessibility.reduceMotion }
    var reduceTransparency: Bool { settings.forceReduceTransparency || accessibility.reduceTransparency }
    var highContrast: Bool { settings.forceHighContrast || accessibility.increaseContrast }

    var morphAnimation: Animation { IslandAnimation.morph(reduceMotion: reduceMotion, speed: settings.animationSpeed) }

    /// Window-local hit rect (anchor-relative, y downward).
    var hitRect: CGRect { metrics.hitRect(islandSize: islandSize, bubbles: visibleBubbles.count, mode: mode) }

    // MARK: Geometry

    func updateGeometry(_ g: NotchGeometry?) { geometry = g }

    // MARK: Input

    func mouseInsideChanged(_ inside: Bool) {
        guard inside != mouseInside else { return }
        mouseInside = inside
        hoverWork?.cancel()
        if inside {
            collapseWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.apply(.hoverBegan) }
            hoverWork = work
            let delay = mode == .compact || mode == .idle ? settings.hoverDelay : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            guard presentation.hovering || mode == .expanded else { return }
            let work = DispatchWorkItem { [weak self] in self?.apply(.hoverEnded) }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    func click() { apply(.click) }
    func clickOutside() { apply(.clickOutside) }
    func escape() { apply(.escape) }
    func toggleSearch() { apply(.toggleSearch) }
    func expand() { apply(.expand) }
    func collapse() { apply(.collapse) }

    func presentTransient(seconds: TimeInterval) {
        apply(.presentTransient)
        transientWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.apply(.transientEnded) }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func settingsChanged() {
        presentation.hoverExpansionEnabled = settings.hoverExpansion
    }

    func apply(_ input: IslandInput) {
        var next = presentation
        next.hoverExpansionEnabled = settings.hoverExpansion
        next.handle(input)
        guard next != presentation else { return }
        let modeChanged = next.mode != presentation.mode
        withAnimation(morphAnimation) { presentation = next }
        if modeChanged {
            transitionCount += 1
            markAnimating()
            if next.mode == .expanded, settings.hapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["ISLAND_TRACE"] != nil { NSLog("Island mode → %@ (%@)", next.mode.rawValue, String(describing: input)) }
            #endif
            onModeChange?(next.mode)
        }
        scheduleAutoCollapse()
    }

    private func scheduleAutoCollapse() {
        collapseWork?.cancel()
        guard settings.autoCollapse, presentation.mode == .expanded, presentation.reason == .click, !mouseInside else { return }
        let work = DispatchWorkItem { [weak self] in self?.apply(.autoCollapse) }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.autoCollapseDelay, execute: work)
    }

    private func markAnimating() {
        isAnimating = true
        animationEndWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.isAnimating = false }
        animationEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 / settings.animationSpeed, execute: work)
    }

    private func observeActivities() {
        withObservationTracking {
            _ = manager.primary?.id
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                let has = self.manager.primary != nil
                if has != self.presentation.hasActivity { self.apply(.activityAvailabilityChanged(hasActivity: has)) }
                self.observeActivities()
            }
        }
    }
}
