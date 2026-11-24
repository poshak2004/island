import Foundation
import IslandCore
import Network

/// Connectivity changes via NWPathMonitor. Only going offline is shown, and only once it has lasted
/// `offlineGrace`; coming back online just clears that card (and still reaches automations via the bus).
@MainActor
final class NetworkProvider {
    private let sink: (ActivityUpdate) -> Void
    private let bus: EventBus
    private var monitor: NWPathMonitor?
    private var lastConnected: Bool?
    private var lastInterface: NetworkActivity.Interface = .none
    private var pendingOffline: DispatchWorkItem?

    init(bus: EventBus, sink: @escaping (ActivityUpdate) -> Void) {
        self.bus = bus
        self.sink = sink
    }

    func start() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let iface: NetworkActivity.Interface =
                path.usesInterfaceType(.wifi) ? .wifi :
                path.usesInterfaceType(.wiredEthernet) ? .ethernet :
                path.usesInterfaceType(.cellular) ? .cellular : (connected ? .other : .none)
            DispatchQueue.main.async { self?.update(connected: connected, interface: iface) }
        }
        m.start(queue: DispatchQueue(label: "island.network"))
        monitor = m
    }

    func stop() {
        pendingOffline?.cancel()
        pendingOffline = nil
        monitor?.cancel()
        monitor = nil
    }

    /// A drop shorter than this (Wi-Fi roaming, a blip) never interrupts anything.
    static let offlineGrace: TimeInterval = 3
    static let offlineCardSeconds: TimeInterval = 5

    private func update(connected: Bool, interface: NetworkActivity.Interface) {
        defer { lastConnected = connected; lastInterface = interface }
        guard let was = lastConnected, was != connected else { return }
        bus.publish(.networkChanged(connected: connected))
        pendingOffline?.cancel()
        pendingOffline = nil
        guard !connected else {
            sink(.remove(id: "network"))
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.lastConnected == false else { return }
            self.sink(.upsert(Activity(id: "network", kind: .network, priority: .normal,
                                       content: .network(NetworkActivity(connected: false, interface: interface)),
                                       expiresAt: Date().addingTimeInterval(Self.offlineCardSeconds))))
        }
        pendingOffline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.offlineGrace, execute: work)
    }
}
