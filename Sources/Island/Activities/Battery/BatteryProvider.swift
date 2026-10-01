import Foundation
import IOKit.ps
import IslandCore

/// Power source changes via IOKit's power-source notification run-loop source (event-driven).
/// Surfaces only useful, short-lived moments: plugged in, low battery thresholds, fully charged.
@MainActor
final class BatteryProvider {
    struct Reading: Equatable {
        var level: Int
        var charging: Bool
        var onAC: Bool
    }

    private let sink: (ActivityUpdate) -> Void
    private let bus: EventBus
    private var source: CFRunLoopSource?
    private(set) var last: Reading?
    private var lowThresholdsShown: Set<Int> = []
    static let lowThresholds = [20, 10, 5]

    init(bus: EventBus, sink: @escaping (ActivityUpdate) -> Void) {
        self.bus = bus
        self.sink = sink
    }

    func start() {
        guard source == nil else { return }
        last = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let provider = Unmanaged<BatteryProvider>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { provider.changed() }
        }, context)?.takeRetainedValue() else { return }
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }

    private func changed() {
        guard let now = Self.read() else { return }
        let events = Self.events(from: last, to: now, shownLow: &lowThresholdsShown)
        last = now
        bus.publish(.batteryLevel(percent: now.level, charging: now.charging))
        for reason in events { present(now, reason) }
    }

    /// Pure transition logic (unit-testable without IOKit).
    static func events(from old: Reading?, to new: Reading, shownLow: inout Set<Int>) -> [BatteryActivity.Reason] {
        guard let old else { return [] }
        var out: [BatteryActivity.Reason] = []
        if new.onAC && !old.onAC { out.append(.pluggedIn); shownLow.removeAll() }
        if new.onAC, new.level >= 100, old.level < 100 { out.append(.full) }
        if !new.onAC {
            for t in lowThresholds where new.level <= t && old.level > t && !shownLow.contains(t) {
                shownLow.insert(t)
                out.append(.low)
                break
            }
        }
        return out
    }

    private func present(_ r: Reading, _ reason: BatteryActivity.Reason) {
        let priority: ActivityPriority = reason == .low ? .high : (reason == .pluggedIn ? .high : .normal)
        let linger: TimeInterval = reason == .low ? 6 : 3.5
        sink(.upsert(Activity(id: "battery", kind: .battery, priority: priority,
                              content: .battery(BatteryActivity(level: r.level, isCharging: r.charging, reason: reason)),
                              expiresAt: Date().addingTimeInterval(linger))))
    }

    static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let level = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
            return Reading(level: level, charging: desc[kIOPSIsChargingKey] as? Bool ?? false,
                           onAC: (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
        }
        return nil
    }
}
