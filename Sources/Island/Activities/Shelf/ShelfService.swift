import AppKit
import IslandCore
import Observation

/// Files parked on the Island. Paths persist across launches; missing files are dropped on load.
/// While a file drag is near the notch the shelf takes the Island (critical priority) to show its
/// drop targets, then steps back to a low-priority bubble.
@MainActor
@Observable
final class ShelfService {
    static let activityID = "shelf"
    static let storageKey = "island.shelf.v1"

    @ObservationIgnored private let sink: (ActivityUpdate) -> Void
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var items: [ShelfItem] = []
    private(set) var isDropTarget = false
    private(set) var lastError: String?
    /// Shown on request (Home tile) even when empty; cleared when the Island closes.
    private var revealed = false
    private var running = false

    init(defaults: UserDefaults = .standard, sink: @escaping (ActivityUpdate) -> Void) {
        self.defaults = defaults
        self.sink = sink
        load()
    }

    func start() {
        running = true
        publish()
    }

    func stop() {
        running = false
        isDropTarget = false
        sink(.remove(id: Self.activityID))
    }

    func handle(_ command: ShelfCommand) {
        switch command {
        case .add(let urls):
            items = ShelfLogic.adding(urls, to: items)
            isDropTarget = false
            save()
        case .remove(let id):
            items = ShelfLogic.removing(id, from: items)
            save()
        case .clear:
            items = []
            save()
        case .reveal:
            revealed = true
            publish(priority: .high)
            return
        case .airDrop(let urls):
            isDropTarget = false
            send(urls.isEmpty ? items.map(\.url) : urls)
        }
        publish()
    }

    /// A file drag entered or left the area around the notch.
    func setDragActive(_ active: Bool) {
        guard running, isDropTarget != active else { return }
        isDropTarget = active
        publish()
    }

    /// The activity was dismissed from the Island: the files stay saved, only the bubble goes away.
    func activityEnded() { isDropTarget = false }

    // MARK: Internals

    /// The Island closed: an empty, revealed shelf goes away again.
    func conceal() {
        guard revealed else { return }
        revealed = false
        publish()
    }

    private func publish(priority requested: ActivityPriority? = nil) {
        guard running else { return }
        guard !items.isEmpty || isDropTarget || revealed else {
            sink(.remove(id: Self.activityID))
            return
        }
        let content = ShelfActivity(items: items, isDropTarget: isDropTarget)
        let priority = requested ?? (isDropTarget ? .critical : (revealed ? .high : .low))
        sink(.upsert(Activity(id: Self.activityID, kind: .shelf, priority: priority, content: .shelf(content))))
    }

    private func send(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { lastError = "Those files are no longer there."; return }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: existing) else {
            lastError = "AirDrop isn't available. Turn on Wi-Fi and Bluetooth, then try again."
            return
        }
        lastError = nil
        // The AirDrop sheet belongs to the frontmost app; Island is an accessory app, so bring it forward.
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: existing)
    }

    private func load() {
        let paths = defaults.stringArray(forKey: Self.storageKey) ?? []
        let urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        items = ShelfLogic.adding(urls, to: [])
    }

    private func save() {
        defaults.set(items.map(\.url.path), forKey: Self.storageKey)
    }
}
