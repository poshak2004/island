import Foundation
import IslandCore

/// Your Shortcuts (Shortcuts app), read and run through Apple's `shortcuts` command-line tool.
/// One `shortcuts list` runs at a time and its result is cached briefly; running a shortcut never
/// blocks the Island.
final class ShortcutsCatalog: @unchecked Sendable {
    static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")
    private static let cacheLifetime: TimeInterval = 60
    private static let listTimeout: TimeInterval = 5

    private let lock = NSLock()
    private var cached: [String] = []
    private var cachedAt = Date.distantPast
    private var inFlight: Task<[String], Never>?

    enum ToolError: Error { case timedOut, failed(Int32) }

    var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: Self.tool.path) }

    /// Names of your shortcuts, alphabetically. Keeps the last good list when the tool fails.
    func names() async -> [String] {
        let task: Task<[String], Never> = lock.withLock {
            if Date().timeIntervalSince(cachedAt) < Self.cacheLifetime { return Task { [cached] in cached } }
            if let inFlight { return inFlight }
            let t = Task { [weak self] () -> [String] in await self?.load() ?? [] }
            inFlight = t
            return t
        }
        return await task.value
    }

    /// Loads the list in the background so the first search or Home picker is instant.
    func prewarm() { Task { _ = await names() } }

    private func load() async -> [String] {
        defer { lock.withLock { inFlight = nil } }
        guard isAvailable, let output = try? await Self.runTool(["list"], timeout: Self.listTimeout) else {
            return lock.withLock { cached }
        }
        let list = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        lock.withLock {
            cached = list
            cachedAt = Date()
        }
        return list
    }

    /// Starts a shortcut and returns immediately. Names that look like options are refused so they
    /// can't be read as flags by the tool.
    func run(_ name: String) {
        guard isAvailable, !name.isEmpty, !name.hasPrefix("-") else { return }
        let process = Process()
        process.executableURL = Self.tool
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { NSLog("Island: couldn't run shortcut %@: %@", name, error.localizedDescription) }
    }

    /// Runs the tool, draining its output as it arrives (so a long list can't fill the pipe and stall),
    /// and treats a timeout as failure rather than returning a truncated result.
    private static func runTool(_ arguments: [String], timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let state = RunState()
            process.executableURL = tool
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            pipe.fileHandleForReading.readabilityHandler = { handle in state.append(handle.availableData) }
            let timer = DispatchWorkItem {
                state.markTimedOut()
                if process.isRunning { process.terminate() }
            }
            process.terminationHandler = { p in
                timer.cancel()
                pipe.fileHandleForReading.readabilityHandler = nil
                state.append(pipe.fileHandleForReading.readDataToEndOfFile())
                if state.timedOut { continuation.resume(throwing: ToolError.timedOut) }
                else if p.terminationStatus != 0 { continuation.resume(throwing: ToolError.failed(p.terminationStatus)) }
                else { continuation.resume(returning: String(decoding: state.data, as: UTF8.self)) }
            }
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private final class RunState: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private var didTimeOut = false
        var data: Data { lock.withLock { buffer } }
        var timedOut: Bool { lock.withLock { didTimeOut } }
        func append(_ d: Data) { lock.withLock { buffer.append(d) } }
        func markTimedOut() { lock.withLock { didTimeOut = true } }
    }
}

/// "Run shortcut …" results in Island search.
final class ShortcutsSearchProvider: SearchProvider, @unchecked Sendable {
    let id = "shortcuts"
    let category = SearchCategory.action
    let timeout: TimeInterval = 1.5
    private let catalog: ShortcutsCatalog
    init(catalog: ShortcutsCatalog) { self.catalog = catalog }

    func search(_ request: SearchRequest) async throws -> [SearchResult] {
        guard request.query.count >= 2 else { return [] }
        return await catalog.names().compactMap { name -> SearchResult? in
            let s = SearchRanker.score(name, query: request.query)
            guard s > 0.35 else { return nil }
            return SearchResult(id: "shortcut-\(name)", category: .action, providerID: id, title: "Run “\(name)”",
                                subtitle: "Shortcut", symbol: "square.2.layers.3d.fill", score: 0.5 * s,
                                command: .runShortcut(name: name))
        }
        .sorted { $0.score > $1.score }
        .prefix(request.limit).map { $0 }
    }
}
