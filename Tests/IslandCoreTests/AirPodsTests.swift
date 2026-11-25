import Foundation
@testable import IslandCore

@MainActor
func registerAirPodsTests() {
    let S = "AirPods"

    test(S, "state machine runs the full sequence in order") {
        var m = AirPodsConnectionStateMachine()
        let steps: [(AirPodsConnectionEvent, AirPodsConnectionPhase)] = [
            (.deviceConnected, .detecting), (.detailsReady, .expanding), (.islandOpened, .revealingDevice),
            (.revealFinished, .connected), (.holdElapsed, .dismissing), (.islandClosed, .idle),
        ]
        for (e, want) in steps { expectEqual(m.handle(e), want) }
    }

    test(S, "state machine never skips or repeats a phase") {
        var m = AirPodsConnectionStateMachine()
        expectEqual(m.handle(.islandOpened), .idle)           // out of order: ignored
        m.handle(.deviceConnected)
        expectEqual(m.handle(.deviceConnected), .detecting)   // duplicate connect: ignored
        expectEqual(m.handle(.revealFinished), .detecting)    // can't reveal before the Island opens
        m.handle(.detailsReady)
        expectEqual(m.handle(.islandClosed), .expanding)
    }

    test(S, "disconnect mid-sequence dismisses; while detecting it returns to idle") {
        var a = AirPodsConnectionStateMachine()
        a.handle(.deviceConnected)
        expectEqual(a.handle(.deviceDisconnected), .idle)
        var b = AirPodsConnectionStateMachine()
        b.handle(.deviceConnected); b.handle(.detailsReady); b.handle(.islandOpened)
        expectEqual(b.handle(.deviceDisconnected), .dismissing)
        expectEqual(b.handle(.islandClosed), .idle)
    }

    test(S, "user dismiss during reveal goes straight to dismissing") {
        var m = AirPodsConnectionStateMachine()
        m.handle(.deviceConnected); m.handle(.detailsReady); m.handle(.islandOpened)
        expectEqual(m.handle(.holdElapsed), .dismissing)
        expect(!m.phase.isPresenting)
    }

    test(S, "parses system_profiler output: connected AirPods with battery") {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[{"Poshak’s AirPods Pro":{"device_address":"AA:BB","device_productID":"0x2024",
          "device_vendorID":"0x004C","device_batteryLevelLeft":"82%","device_batteryLevelRight":"79%","device_batteryLevelCase":"61%"}}],
          "device_not_connected":[{"WH-CH720N":{"device_productID":"0x0EAF","device_vendorID":"0x054C"}}]}]}
        """
        let r = SystemProfilerBluetoothParser.parse(Data(json.utf8))
        expectEqual(r.count, 2)
        let pods = r.first { $0.connected }
        expectEqual(pods?.productID, 0x2024)
        expectEqual(pods?.vendorID, 0x004C)
        expectEqual(pods?.battery, AirPodsBattery(left: 82, right: 79, caseLevel: 61))
        expect(r.first { !$0.connected }?.battery.isEmpty == true)
    }

    test(S, "parser tolerates garbage and missing sections") {
        expect(SystemProfilerBluetoothParser.parse(Data("nope".utf8)).isEmpty)
        expect(SystemProfilerBluetoothParser.parse(Data(#"{"SPBluetoothDataType":[{}]}"#.utf8)).isEmpty)
    }

    test(S, "name matching handles apostrophe and spacing variants") {
        let reports = [BluetoothDeviceReport(name: "Poshak ’s AirPods Pro", connected: false),
                       BluetoothDeviceReport(name: "Poshak’s AirPods Pro", productID: 0x2024, connected: true)]
        expectEqual(SystemProfilerBluetoothParser.match("Poshak's AirPods Pro", in: reports)?.productID, 0x2024)
        expect(SystemProfilerBluetoothParser.match("Unrelated Speaker", in: reports) == nil)
    }

    test(S, "model resolution: product ID first, then name") {
        expectEqual(AirPodsModel.resolve(productID: 0x2024, name: "x"), .airPodsPro2USBC)
        expectEqual(AirPodsModel.resolve(productID: 0x200A, name: "x"), .airPodsMax)
        expectEqual(AirPodsModel.resolve(productID: nil, name: "My AirPods Pro"), .airPodsPro2)
        expectEqual(AirPodsModel.resolve(productID: nil, name: "Kitchen AirPods Max"), .airPodsMax)
        expect(AirPodsModel.resolve(productID: nil, name: "WH-1000XM5") == nil)
        expectEqual(AirPodsModel.resolve(productID: 0x2024, name: "x")?.displayName, "AirPods Pro")
        expectEqual(AirPodsModel.deviceModelCode(productID: 0x2024), "Device1,8228")
    }

    test(S, "battery headline is the lower bud; clamped; empty when unreported") {
        expectEqual(AirPodsBattery(left: 82, right: 79, caseLevel: 61).headline, 79)
        expectEqual(AirPodsBattery(single: 64).headline, 64)
        expectEqual(AirPodsBattery(left: 150).left, 100)
        expect(AirPodsBattery().isEmpty && AirPodsBattery().headline == nil)
    }

    test(S, "case level alone is never headlined as the buds' level") {
        expect(AirPodsBattery(caseLevel: 1).headline == nil)
        expectEqual(AirPodsBattery(left: 60, right: 59, caseLevel: 1).headline, 59)
    }

    test(S, "battery is only live for a device the system reports as connected") {
        let cached = BluetoothDeviceReport(name: "AirPods Pro", address: nil, productID: 0x2024, vendorID: 0x004C,
                                           connected: false, battery: AirPodsBattery(left: 60, right: 59))
        expect(cached.liveBattery == nil, "a not-connected entry's levels are stale cache")
        var live = cached
        live.connected = true
        expectEqual(live.liveBattery?.headline, 59)
        live.battery = AirPodsBattery()
        expect(live.liveBattery == nil, "nothing reported → no battery, never a guess")
    }

    test(S, "connection banner is a short, wide pill: narrower than a card, no header row") {
        let m = IslandMetrics(notchSize: CGSize(width: 185, height: 32), hasNotch: true)
        let banner = m.size(mode: .expanded, compact: .standard, expanded: .airPods)
        let card = m.size(mode: .expanded, compact: .standard, expanded: .device)
        expect(banner.width < card.width, "banner \(banner.width) should be narrower than card \(card.width)")
        expect(banner.width >= m.notchSize.width + 160, "banner must clear the notch with room for art and ring")
        expect(banner.height < card.height, "banner \(banner.height) should be shorter than card \(card.height)")
        expect(banner.height > m.compactHeight + 40, "banner must fit a 44pt row below the notch")
    }

    test(S, "banner cooldown: a device presented within the window stays quiet") {
        var c = AirPodsBannerCooldown(interval: 60)
        let t0 = Date(timeIntervalSince1970: 1_000)
        expect(c.shouldPresent(name: "Poshak's AirPods", now: t0), "never shown → present")
        c.recordPresented(name: "Poshak's AirPods", now: t0)
        expect(!c.shouldPresent(name: "Poshak's AirPods", now: t0.addingTimeInterval(30)), "re-fire within 60 s suppressed")
        expect(c.shouldPresent(name: "Poshak's AirPods", now: t0.addingTimeInterval(60)), "cooldown expires at the interval")
    }

    test(S, "banner cooldown is per device and tolerant of apostrophe variants") {
        var c = AirPodsBannerCooldown(interval: 60)
        let t0 = Date(timeIntervalSince1970: 1_000)
        c.recordPresented(name: "Poshak’s AirPods", now: t0)
        expect(!c.shouldPresent(name: "Poshak's AirPods", now: t0.addingTimeInterval(5)))
        expect(c.shouldPresent(name: "Kitchen AirPods Max", now: t0.addingTimeInterval(5)), "another pair is unaffected")
    }

    test(S, "banner cooldown ignores a clock that went backwards") {
        var c = AirPodsBannerCooldown(interval: 60)
        let t0 = Date(timeIntervalSince1970: 1_000)
        c.recordPresented(name: "AirPods", now: t0)
        expect(c.shouldPresent(name: "AirPods", now: t0.addingTimeInterval(-10)), "negative elapsed time never suppresses")
    }

    test(S, "pending connection: starts at once when idle, queues one (latest wins) otherwise") {
        var q = AirPodsPendingConnection()
        expect(q.offer(name: "A", phase: .idle), "idle → start now")
        expect(q.pending == nil)
        expect(!q.offer(name: "B", phase: .connected), "busy → queued")
        expect(!q.offer(name: "C", phase: .dismissing))
        expectEqual(q.pending, "C")
        expect(q.take(phase: .dismissing) == nil, "nothing runs until idle")
        expectEqual(q.take(phase: .idle), "C")
        expect(q.take(phase: .idle) == nil, "taken once")
    }

    test(S, "pending connection: a disconnect drops the queued device") {
        var q = AirPodsPendingConnection()
        _ = q.offer(name: "B", phase: .revealingDevice)
        expect(q.dropOnDisconnect(), "had a pending device")
        expect(q.pending == nil)
        expect(!q.dropOnDisconnect(), "nothing left to drop")
    }

    test(S, "pending connection: re-offering the device already running is not queued") {
        var q = AirPodsPendingConnection()
        _ = q.offer(name: "A", phase: .idle)
        expect(!q.offer(name: "A", phase: .connected, current: "A"))
        expect(q.pending == nil, "same pair re-announced mid-sequence is ignored")
    }

    test(S, "Apple report identifies renamed AirPods by product ID; other vendors/products don't") {
        let renamed = BluetoothDeviceReport(name: "Poshak's Buds", productID: 0x2014, vendorID: 0x004C, connected: true)
        expectEqual(AirPodsModel.identify(renamed), .airPodsPro2)
        var sony = renamed; sony.vendorID = 0x054C
        expect(AirPodsModel.identify(sony) == nil, "non-Apple vendor")
        var beats = renamed; beats.productID = 0x2011
        expect(AirPodsModel.identify(beats) == nil, "Apple but not an AirPods product ID")
        var noPID = renamed; noPID.productID = nil
        expect(AirPodsModel.identify(noPID) == nil, "name alone never makes a renamed device AirPods")
    }

    test(S, "only Bluetooth outputs without 'airpods' in the name need a lookup") {
        expect(AirPodsRouting.needsLookup(name: "Poshak's Buds", isBluetooth: true))
        expect(!AirPodsRouting.needsLookup(name: "Poshak's AirPods Pro", isBluetooth: true))
        expect(!AirPodsRouting.needsLookup(name: "LG Monitor", isBluetooth: false))
        expect(AirPodsRouting.isAirPodsName("My AIRPODS"))
    }
}
