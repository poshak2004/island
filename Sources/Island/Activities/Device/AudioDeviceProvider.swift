import CoreAudio
import Foundation
import IslandCore

/// Audio output route changes (AirPods / headphones / speakers) via CoreAudio property listeners.
/// Public API, no Bluetooth permission needed.
@MainActor
final class AudioDeviceProvider {
    private let sink: (ActivityUpdate) -> Void
    private let bus: EventBus
    private var listener: AudioObjectPropertyListenerBlock?
    private var lastDevice: AudioDeviceID?
    private var lastName: String?
    private var lastWasExternal = false
    /// AirPods connections are animated by `AirPodsConnectionAnimator` instead of the generic card.
    var onAirPodsConnected: ((String) -> Void)?
    var onAirPodsDisconnected: (() -> Void)?
    /// Asks the system which Bluetooth device a route is, to recognise AirPods the user renamed.
    /// Injectable so it can be stubbed; short timeout because the generic card waits on it.
    var lookup: (String) async -> BluetoothDeviceReport? = { await AirPodsInfoProvider.lookup(name: $0, timeout: 3) }
    /// Lookup verdicts per route name (true = AirPods), so a renamed pair's disconnect is handled as
    /// AirPods too and a known device is never looked up twice.
    private var knownRoutes: [String: Bool] = [:]
    private var lookupTask: Task<Void, Never>?

    init(bus: EventBus, sink: @escaping (ActivityUpdate) -> Void) {
        self.bus = bus
        self.sink = sink
    }

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    func start() {
        guard listener == nil else { return }
        lastDevice = Self.defaultOutput()
        lastName = lastDevice.flatMap(Self.name)
        lastWasExternal = lastDevice.map { Self.transport($0) != kAudioDeviceTransportTypeBuiltIn } ?? false
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.changed() }
        }
        listener = block
        var addr = Self.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
    }

    func stop() {
        guard let listener else { return }
        var addr = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, listener)
        self.listener = nil
    }

    private func changed() {
        guard let dev = Self.defaultOutput(), dev != lastDevice else { return }
        let name = Self.name(dev) ?? "Audio device"
        let transport = Self.transport(dev)
        let external = transport != kAudioDeviceTransportTypeBuiltIn
        let wasExternal = lastWasExternal
        let wasAirPods = wasExternal && lastName.map(isAirPods) == true
        lastDevice = dev; lastName = name; lastWasExternal = external
        lookupTask?.cancel()
        // Signalled even when the new route is another pair, so an AirPods → AirPods switch is seen.
        if wasAirPods { onAirPodsDisconnected?() }
        // Devices leave quietly — no "Disconnected" popup; the connected card is simply cleared.
        guard external else {
            if wasExternal { sink(.remove(id: "device")) }
            return
        }
        route(name: name, transport: transport)
    }

    private func isAirPods(_ name: String) -> Bool {
        AirPodsRouting.isAirPodsName(name) || knownRoutes[name] == true
    }

    private func route(name: String, transport: UInt32) {
        guard let onAirPodsConnected else { return publishGeneric(name: name, transport: transport) }
        if isAirPods(name) { return onAirPodsConnected(name) }
        let bluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        guard knownRoutes[name] == nil, AirPodsRouting.needsLookup(name: name, isBluetooth: bluetooth) else {
            return publishGeneric(name: name, transport: transport)
        }
        lookupTask = Task { [weak self, lookup] in
            let report = await lookup(name)
            guard !Task.isCancelled, let self, self.lastName == name else { return }
            self.finishLookup(name: name, transport: transport, report: report)
        }
    }

    /// Renamed AirPods are recognised by Apple vendor + product ID; anything else gets the generic card.
    private func finishLookup(name: String, transport: UInt32, report: BluetoothDeviceReport?) {
        let airPods = report.flatMap(AirPodsModel.identify) != nil
        // A failed lookup (nil report) isn't cached, so the next connection asks again.
        if report != nil { knownRoutes[name] = airPods }
        if airPods, let onAirPodsConnected { return onAirPodsConnected(name) }
        publishGeneric(name: name, transport: transport)
    }

    private func publishGeneric(name: String, transport: UInt32) {
        let activity = DeviceActivity(name: name, type: Self.type(name: name, transport: transport), connected: true)
        bus.publish(.deviceConnected(name: name))
        // Linger a little longer than the automatic presentation so the card never vanishes mid-animation.
        sink(.upsert(Activity(id: "device", kind: .device, priority: .high, content: .device(activity),
                              expiresAt: Date().addingTimeInterval(5))))
    }

    static func type(name: String, transport: UInt32) -> DeviceActivity.DeviceType {
        let lower = name.lowercased()
        if lower.contains("airpods") || lower.contains("headphone") || lower.contains("buds") || lower.contains("beats") { return .headphones }
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
        case kAudioDeviceTransportTypeAirPlay: return .speaker
        default: return .other
        }
    }

    static func defaultOutput() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = defaultOutputAddress
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return err == noErr && id != 0 ? id : nil
    }

    static func name(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr, let cf = name?.takeRetainedValue() else { return nil }
        return cf as String
    }

    static func transport(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var t: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &t)
        return t
    }
}
