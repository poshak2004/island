import AppKit
import IslandCore
import Observation

/// Reads model and battery details with `system_profiler SPBluetoothDataType -json` — Apple's public
/// reporting tool. Runs out of process with a timeout, so a slow query can never block the Island.
enum AirPodsInfoProvider {
    /// Cancelling the calling Task terminates system_profiler and returns nil.
    static func lookup(name: String, timeout: TimeInterval = 6) async -> BluetoothDeviceReport? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let child = ChildProcess(p)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = profilerOutput(child, timeout: timeout)
                    cont.resume(returning: data.flatMap {
                        SystemProfilerBluetoothParser.match(name, in: SystemProfilerBluetoothParser.parse($0))
                    })
                }
            }
        } onCancel: {
            child.cancel()
        }
    }

    /// Blocking: system_profiler's JSON, or nil on launch failure, timeout, cancellation or a non-zero exit.
    private static func profilerOutput(_ child: ChildProcess, timeout: TimeInterval) -> Data? {
        let p = child.process
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try child.launch() } catch {
            if !(error is CancellationError) { NSLog("Island: system_profiler launch failed: %@", error.localizedDescription) }
            return nil
        }
        let read = DispatchSemaphore(value: 0)
        child.captureOutput(of: out, done: read)
        if read.wait(timeout: .now() + timeout) == .timedOut {
            child.terminate()
            NSLog("Island: system_profiler timed out after %.0fs", timeout)
            return nil
        }
        p.waitUntilExit() // EOF seen: the process is exiting; needed before reading its status
        if child.isCancelled { return nil }
        guard p.terminationStatus == 0 else {
            NSLog("Island: system_profiler exited with status %d", p.terminationStatus)
            return nil
        }
        return child.data
    }
}

/// Drives the AirPods connection sequence:
/// idle → detecting → expanding → revealingDevice → connected → dismissing → idle.
///
/// It owns only the *AirPods* animation. The Island itself is opened and closed through the normal
/// `CommandRouter` UI commands, so the rest of the Dynamic Island is unchanged.
@MainActor
@Observable
final class AirPodsConnectionAnimator {
    private(set) var machine = AirPodsConnectionStateMachine()
    private(set) var device: DeviceActivity?
    var phase: AirPodsConnectionPhase { machine.phase }
    /// The artwork is shown once the Island has opened (never in a half-open frame).
    var isRevealed: Bool { phase == .revealingDevice || phase == .connected || phase == .dismissing }

    @ObservationIgnored private let sink: (ActivityUpdate) -> Void
    @ObservationIgnored private let ui: (IslandUICommand) -> Void
    @ObservationIgnored private let reduceMotion: () -> Bool
    @ObservationIgnored private var sequence: Task<Void, Never>?
    @ObservationIgnored private var details: Task<Void, Never>?
    @ObservationIgnored var lookup: (String) async -> BluetoothDeviceReport? = { await AirPodsInfoProvider.lookup(name: $0) }

    static let activityID = "device"

    // Timings (seconds). The Island spring settles in ~0.4 s; the artwork entrance takes ~0.55 s.
    static let detailsBudget: TimeInterval = 0.5
    static let islandOpen: TimeInterval = 0.4
    static let reveal: TimeInterval = 0.55
    static let hold: TimeInterval = 2.0
    static let islandClose: TimeInterval = 0.4
    /// How long the compact "connected" state stays after the card closes.
    static let compactLinger: TimeInterval = 2.5

    init(sink: @escaping (ActivityUpdate) -> Void, ui: @escaping (IslandUICommand) -> Void, reduceMotion: @escaping () -> Bool) {
        self.sink = sink
        self.ui = ui
        self.reduceMotion = reduceMotion
    }

    // MARK: Input

    func deviceConnected(name: String) {
        guard phase == .idle else { return } // one sequence at a time
        machine.handle(.deviceConnected)
        device = DeviceActivity(name: name, type: .headphones, connected: true, airPods: AirPodsModel.resolve(productID: nil, name: name))

        // Details (exact model + battery) are fetched in parallel. The card opens after a short budget
        // even if they're not back yet; battery then fades in when it arrives.
        details = Task { [weak self] in
            guard let report = await self?.lookup(name), !Task.isCancelled, let self else { return }
            self.apply(report)
        }
        sequence = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.detailsBudget * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.run()
        }
    }

    func deviceDisconnected() {
        guard phase != .idle else { return }
        details?.cancel()
        let wasDetecting = phase == .detecting
        machine.handle(.deviceDisconnected)
        if wasDetecting {
            sequence?.cancel()
            device = nil
        } else if phase == .dismissing {
            ui(.collapse)
            finishDismissal()
        }
    }

    /// User dismissed the card (✕ or Escape): skip straight to dismissing.
    func dismiss() {
        guard phase.isPresenting else { return }
        machine.handle(.holdElapsed)
        ui(.collapse)
        finishDismissal()
    }

    // MARK: Sequence

    private func run() async {
        guard machine.handle(.detailsReady) == .expanding, let device else { return }
        publish(device, lingerAfterCard: true)
        // Open the Island for exactly the card's duration (the existing transient presentation).
        let reduced = reduceMotion()
        let shown = Self.islandOpen + (reduced ? 0.15 : Self.reveal) + Self.hold
        ui(.presentTransient(seconds: shown))

        await sleep(Self.islandOpen)
        guard machine.handle(.islandOpened) == .revealingDevice else { return }
        await sleep(reduced ? 0.15 : Self.reveal)
        guard machine.handle(.revealFinished) == .connected else { return finishDismissal() }
        await sleep(Self.hold)
        machine.handle(.holdElapsed)
        finishDismissal()
    }

    private func finishDismissal() {
        Task { [weak self] in
            await self?.sleep(Self.islandClose)
            self?.machine.handle(.islandClosed)
        }
    }

    private func apply(_ report: BluetoothDeviceReport) {
        guard var d = device else { return }
        d.productID = report.productID
        d.airPods = AirPodsModel.resolve(productID: report.vendorID == 0x004C ? report.productID : nil, name: report.name) ?? d.airPods
        d.battery = report.liveBattery
        device = d
        if phase != .detecting && phase != .idle { publish(d, lingerAfterCard: true) }
    }

    private func publish(_ d: DeviceActivity, lingerAfterCard: Bool) {
        let total = Self.islandOpen + Self.reveal + Self.hold + Self.islandClose + Self.compactLinger
        sink(.upsert(Activity(id: Self.activityID, kind: .device, priority: .high, content: .device(d),
                              expiresAt: Date().addingTimeInterval(total))))
    }

    private func sleep(_ s: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }
}
