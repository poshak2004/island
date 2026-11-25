import Foundation

/// Thread-safe handle for an out-of-process helper (osascript, system_profiler).
///
/// The captured output is written on a reader queue and read on the waiting queue, and the process
/// can be terminated from a Task cancellation handler on any thread, so every shared field sits
/// behind one lock.
final class ChildProcess: @unchecked Sendable {
    let process: Process
    private let lock = NSLock()
    private var launched = false
    private var cancelled = false
    private var output = Data()

    init(_ process: Process) { self.process = process }

    /// True once `cancel()` ran (the calling Task was cancelled).
    var isCancelled: Bool { lock.withLock { cancelled } }

    /// Output captured so far by `captureOutput(of:)`.
    var data: Data { lock.withLock { output } }

    /// Launches the process unless it was already cancelled.
    func launch() throws {
        try lock.withLock {
            if cancelled { throw CancellationError() }
            try process.run()
            launched = true
        }
    }

    /// Reads the pipe to EOF on its own queue (so a full pipe can't deadlock the child), storing the
    /// result under the lock and signalling `done` afterwards.
    func captureOutput(of pipe: Pipe, done: DispatchSemaphore) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let read = pipe.fileHandleForReading.readDataToEndOfFile()
            lock.withLock { output = read }
            done.signal()
        }
    }

    /// Kills the process if it is still running (timeout path).
    func terminate() {
        lock.withLock { terminateLocked() }
    }

    /// The calling Task was cancelled: stop a running process and prevent a pending launch.
    func cancel() {
        lock.withLock {
            cancelled = true
            terminateLocked()
        }
    }

    private func terminateLocked() {
        guard launched, process.isRunning else { return }
        process.terminate()
    }
}
