import AppKit
import IslandCore

/// Composition root. Wires providers → ActivityManager → Island, and UI → CommandRouter → services.
@MainActor
final class AppEnvironment {
    let settings: IslandSettings
    let bus = EventBus()
    let manager: ActivityManager
    let display = DisplayManager()
    let accessibility = AccessibilityMonitor()
    let commands = CommandRouter()
    let island: IslandViewModel
    let search = SearchViewModel()
    let window: IslandWindowController
    let timers: TimerService
    private var settingsObservation: Any?

    init(settings: IslandSettings) {
        self.settings = settings
        manager = ActivityManager(bus: bus)
        island = IslandViewModel(manager: manager, settings: settings, accessibility: accessibility, commands: commands)
        window = IslandWindowController(model: island, search: search)
        let submit: (ActivityUpdate) -> Void = { [manager] in manager.submit($0) }
        timers = TimerService(bus: bus, sink: submit)

        search.commands = commands
        search.onHeightChange = { [weak island] h in island?.searchHeight = h }

        commands.timer = { [weak self] in self?.timers.handle($0) }
        commands.ui = { [weak self] in self?.handleUI($0) }

        display.selection = settings.display
        display.onChange = { [weak self] g in self?.geometryChanged(g) }
        geometryChanged(display.geometry)
        applySettings()
        observeSettings()
    }

    func start() {
        if settings.islandEnabled { window.show() }
    }

    private func geometryChanged(_ g: NotchGeometry?) {
        island.updateGeometry(g)
        search.compactHeight = island.metrics.compactHeight
        window.reposition()
    }

    private func handleUI(_ c: IslandUICommand) {
        switch c {
        case .expand: island.expand()
        case .collapse: island.collapse()
        case .toggleSearch:
            guard settings.searchEnabled else { return }
            island.toggleSearch()
        case .presentTransient(let s): island.presentTransient(seconds: s)
        case .select(let id): manager.select(id: id)
        case .selectNext: manager.selectNext()
        case .dismiss(let id): manager.dismiss(id: id)
        }
    }

    private func applySettings() {
        manager.enabledKinds = settings.enabledKinds
        island.settingsChanged()
        if display.selection != settings.display { display.selection = settings.display }
        window.reposition()
        if settings.islandEnabled { window.show() } else { window.hide() }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.enabledKinds
            _ = settings.hoverExpansion
            _ = settings.display
            _ = settings.islandScale
            _ = settings.cornerRadius
            _ = settings.islandEnabled
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.applySettings()
                self?.observeSettings()
            }
        }
    }
}
