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
    let teleprompter: TeleprompterService
    let shelf: ShelfService
    let fileDrags = FileDragWatcher()
    let media: MediaService
    let downloads: DownloadProvider
    let battery: BatteryProvider
    let network: NetworkProvider
    let devices: AudioDeviceProvider
    let recording: RecordingProvider
    let calendar: CalendarProvider
    let clipboard: ClipboardProvider
    let airPods: AirPodsConnectionAnimator
    private(set) var providersRunning = false
    private(set) lazy var features = FeatureHub(env: self)
    private var running: Set<String> = []

    init(settings: IslandSettings) {
        self.settings = settings
        manager = ActivityManager(bus: bus)
        island = IslandViewModel(manager: manager, settings: settings, accessibility: accessibility, commands: commands)
        window = IslandWindowController(model: island, search: search)
        let submit: (ActivityUpdate) -> Void = { [manager] in manager.submit($0) }
        timers = TimerService(bus: bus, sink: submit)
        teleprompter = TeleprompterService(settings: settings, sink: submit)
        shelf = ShelfService(sink: submit)
        media = MediaService(bus: bus, sink: submit)
        downloads = DownloadProvider(bus: bus, sink: submit)
        battery = BatteryProvider(bus: bus, sink: submit)
        network = NetworkProvider(bus: bus, sink: submit)
        devices = AudioDeviceProvider(bus: bus, sink: submit)
        recording = RecordingProvider(sink: submit)
        calendar = CalendarProvider(sink: submit)
        clipboard = ClipboardProvider(sink: submit)
        let router = commands
        airPods = AirPodsConnectionAnimator(sink: submit, ui: { router.perform(.ui($0)) },
                                            reduceMotion: { [weak island] in island?.reduceMotion ?? false })
        island.airPods = airPods
        devices.onAirPodsConnected = { [weak airPods] in airPods?.deviceConnected(name: $0) }
        devices.onAirPodsDisconnected = { [weak airPods] in airPods?.deviceDisconnected() }

        search.commands = commands
        search.onHeightChange = { [weak island] h in island?.searchHeight = h }

        commands.timer = { [weak self] in self?.timers.handle($0) }
        commands.media = { [weak self] c, source in self?.media.perform(c, source: source) }
        commands.download = { [weak self] in self?.downloads.handle($0) }
        commands.teleprompter = { [weak self] in self?.teleprompter.handle($0) }
        commands.shelf = { [weak self] in self?.handleShelf($0) }
        commands.ui = { [weak self] in self?.handleUI($0) }

        wireTeleprompter()
        wireShelf()

        display.selection = settings.display
        display.onChange = { [weak self] g in self?.geometryChanged(g) }
        geometryChanged(display.geometry)
        applySettings()
        observeSettings()
    }

    func start(providers: Bool = true) {
        if settings.islandEnabled { window.show() }
        providersRunning = providers
        syncProviders()
        features.start()
    }

    func showDebugPanel() { features.debug.showPanel(env: self) }

    // MARK: Providers

    /// Starts/stops each integration to match the enabled activity kinds. Each provider is independent:
    /// one failing integration never affects the others.
    private func syncProviders() {
        guard providersRunning else { return }
        let kinds = settings.enabledKinds
        toggle("media", kinds.contains(.media), start: {
            media.register(AppleMusicProvider())
            media.register(SpotifyProvider())
            media.register(VLCProvider())
        }, stop: {
            media.providers.map(\.bundleID).forEach { media.unregister(bundleID: $0) }
        })
        toggle("browserMedia", kinds.contains(.media) && settings.browserMediaEnabled, start: {
            BrowserMediaProvider.all().forEach { media.register($0) }
        }, stop: {
            BrowserMediaProvider.all().forEach { media.unregister(bundleID: $0.bundleID) }
        })
        toggle("download", kinds.contains(.download), start: { downloads.start() }, stop: { downloads.stop() })
        toggle("battery", kinds.contains(.battery), start: { battery.start() }, stop: { battery.stop() })
        toggle("network", kinds.contains(.network), start: { network.start() }, stop: { network.stop() })
        toggle("device", kinds.contains(.device), start: { devices.start() }, stop: { devices.stop() })
        toggle("recording", kinds.contains(.recording), start: { recording.start() }, stop: { recording.stop() })
        toggle("calendar", kinds.contains(.calendar), start: { calendar.start() }, stop: { calendar.stop() })
        toggle("clipboard", kinds.contains(.clipboard), start: { clipboard.start() }, stop: { clipboard.stop() })
        toggle("shelf", kinds.contains(.shelf), start: { shelf.start(); fileDrags.start() }, stop: { fileDrags.stop(); shelf.stop() })
    }

    private func toggle(_ key: String, _ on: Bool, start: () -> Void, stop: () -> Void) {
        if on, !running.contains(key) { running.insert(key); start() }
        else if !on, running.contains(key) { running.remove(key); stop() }
    }

    var runningProviders: [String] { running.sorted() }

    // MARK: Geometry / UI

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
            guard settings.searchEnabled, settings.islandEnabled else { return }
            island.toggleSearch()
        case .presentTransient(let s): island.presentTransient(seconds: s)
        case .select(let id): manager.select(id: id)
        case .selectNext: manager.selectNext()
        case .dismiss(let id):
            if id == AirPodsConnectionAnimator.activityID { airPods.dismiss() }
            manager.dismiss(id: id)
        }
    }

    private func applySettings() {
        manager.enabledKinds = settings.enabledKinds
        island.settingsChanged()
        if display.selection != settings.display { display.selection = settings.display }
        window.reposition()
        if settings.islandEnabled { window.show() } else { window.hide() }
        syncProviders()
        if providersRunning { features.configure() }
        updateCaptureVisibility()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.enabledKinds
            _ = settings.browserMediaEnabled
            _ = settings.hoverExpansion
            _ = settings.display
            _ = settings.islandScale
            _ = settings.cornerRadius
            _ = settings.islandEnabled
            _ = settings.searchEnabled
            _ = settings.searchShortcut
            _ = settings.fileSearchEnabled
            _ = settings.webSearchEnabled
            _ = settings.webSearchProviders
            _ = settings.aiProvider
            _ = settings.aiModel
            _ = settings.performanceOverlay
            _ = settings.teleprompterHideFromCapture
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.applySettings()
                self?.observeSettings()
            }
        }
    }
}

// MARK: Teleprompter

extension AppEnvironment {
    fileprivate func wireTeleprompter() {
        teleprompter.lineCharacters = { [weak self] in
            guard let self else { return 40 }
            let width = self.island.metrics.expandedWidth - 44
            return TeleprompterStyle.lineCharacters(width: width, fontSize: CGFloat(self.settings.teleprompterFontSize))
        }
        teleprompter.isPointerInside = { [weak self] in self?.island.mouseInside ?? false }
        teleprompter.onSessionChange = { [weak self] active in
            guard let self else { return }
            self.updateCaptureVisibility()
            if active { self.island.expand() } else { self.island.collapse() }
        }
        island.onPointerChange = { [weak self] inside in
            guard let self, self.teleprompter.isActive else { return }
            self.teleprompter.handle(.pointerInside(inside))
        }
        bus.subscribe { [weak self] event in
            guard let self else { return }
            switch event {
            case .activityEnded(let id, .teleprompter) where id == TeleprompterService.activityID:
                self.teleprompter.activityEnded()
            case .activityStarted(_, .recording):
                self.cameraMaybeStarted()
            default: break
            }
        }
    }

    /// Search, automation and the menu bar start the saved script; with none saved, the clipboard.
    func startTeleprompterFromSettings() {
        let saved = settings.teleprompterScript.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = saved.isEmpty ? (NSPasteboard.general.string(forType: .string) ?? "") : saved
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            commands.openSettings?()
            return
        }
        teleprompter.start(text: text, title: saved.isEmpty ? "Clipboard" : "Teleprompter", autoplay: true)
    }

    /// "Show when the camera turns on": opens the saved script paused, ready for you to press play.
    private func cameraMaybeStarted() {
        guard settings.teleprompterStartWithCamera, settings.enabledKinds.contains(.teleprompter), !teleprompter.isActive else { return }
        let cameraOn = manager.ordered.contains { a in
            if case .recording(let r) = a.content { return r.camera }
            return false
        }
        let script = settings.teleprompterScript
        guard cameraOn, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        teleprompter.start(text: script, title: "Teleprompter", autoplay: false)
    }

    fileprivate func updateCaptureVisibility() {
        window.setHiddenFromCapture(teleprompter.isActive && settings.teleprompterHideFromCapture)
    }
}

// MARK: File shelf

extension AppEnvironment {
    /// How far around the open Island a file drag still counts as "heading for the notch".
    static let shelfDragMargin: CGFloat = 60
    static let shelfConfirmSeconds: TimeInterval = 2.5

    fileprivate func wireShelf() {
        fileDrags.isNearIsland = { [weak self] point in
            guard let self, let g = self.island.geometry else { return false }
            let m = self.island.metrics
            let width = m.expandedWidth + 2 * Self.shelfDragMargin
            let height = m.expandedHeight(.shelf) + Self.shelfDragMargin
            return NSRect(x: g.anchor.x - width / 2, y: g.anchor.y - height, width: width, height: height).contains(point)
        }
        fileDrags.onChange = { [weak self] active in
            guard let self else { return }
            self.shelf.setDragActive(active)
            if active { self.island.expand() } else { self.settleAfterShelf(confirmDrop: false) }
        }
        bus.subscribe { [weak self] event in
            if case .activityEnded(let id, .shelf) = event, id == ShelfService.activityID { self?.shelf.activityEnded() }
        }
    }

    fileprivate func handleShelf(_ command: ShelfCommand) {
        switch command {
        case .add, .airDrop: fileDrags.dropCompleted()
        case .remove, .clear: break
        }
        shelf.handle(command)
        switch command {
        case .airDrop: settleAfterShelf(confirmDrop: false)
        case .add: settleAfterShelf(confirmDrop: true)
        case .remove, .clear: break
        }
    }

    /// After a drag or drop: a teleprompter you were reading comes straight back, open. Otherwise a drop
    /// shows the shelf for a moment, and an abandoned drag just closes the Island.
    private func settleAfterShelf(confirmDrop: Bool) {
        if let prompter = teleprompter.current, prompter.state != .finished {
            manager.select(id: TeleprompterService.activityID)
            island.expand()
        } else if confirmDrop {
            island.collapse()
            manager.select(id: ShelfService.activityID)
            island.presentTransient(seconds: Self.shelfConfirmSeconds)
        } else if !island.mouseInside {
            island.collapse()
        }
    }
}

