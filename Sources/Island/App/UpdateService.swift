import Foundation
import IslandCore
import Observation

/// Asks GitHub whether a newer build was published. No timer: it checks at launch and when the
/// menu-bar menu opens, at most once a day (or right away from Settings › Check Now). It only reports;
/// downloading stays with the person, on the release page.
@MainActor
@Observable
final class UpdateService {
    enum Status: Equatable {
        case idle, checking, upToDate, failed(String)
    }

    private(set) var available: AvailableUpdate?
    private(set) var status: Status = .idle
    @ObservationIgnored private let settings: IslandSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?

    static let lastCheckKey = "island.updates.lastCheck"
    nonisolated static let requestTimeout: TimeInterval = 10

    init(settings: IslandSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
    }

    /// The running build, or nil for development builds (which never nag).
    static var currentBuild: Int? {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String, !version.contains("dev") else { return nil }
        return (info?["CFBundleVersion"] as? String).flatMap(Int.init)
    }

    private var lastCheck: Date? { defaults.object(forKey: Self.lastCheckKey) as? Date }

    /// Automatic check: only if enabled, a release build, and a day has passed.
    func checkIfDue() {
        guard settings.checkForUpdates, Self.currentBuild != nil,
              ReleaseFeed.isDue(lastCheck: lastCheck, now: Date()) else { return }
        checkNow()
    }

    func checkNow() {
        guard task == nil else { return }
        guard let build = Self.currentBuild else {
            status = .failed("Development builds don't check for updates.")
            return
        }
        status = .checking
        task = Task { [weak self] in
            let result = await Self.fetch(currentBuild: build)
            guard let self else { return }
            self.task = nil
            self.defaults.set(Date(), forKey: Self.lastCheckKey)
            switch result {
            case .success(let update):
                self.available = update
                self.status = update == nil ? .upToDate : .idle
            case .failure(let error):
                NSLog("Island: update check failed: %@", String(describing: error))
                self.status = .failed("Couldn't reach GitHub. Try again later.")
            }
        }
    }

    private enum CheckError: Error { case badResponse(Int), unreadable }

    private nonisolated static func fetch(currentBuild: Int) async -> Result<AvailableUpdate?, Error> {
        do {
            let releaseData = try await get(ReleaseFeed.latestReleaseAPI)
            guard let release = ReleaseFeed.parseRelease(releaseData) else { throw CheckError.unreadable }
            // A release without a manifest predates update checks: nothing to compare against.
            guard let manifestURL = release.manifestURL else { return .success(nil) }
            guard let manifest = ReleaseFeed.parseManifest(try await get(manifestURL)) else { throw CheckError.unreadable }
            return .success(ReleaseFeed.update(current: currentBuild, manifest: manifest, page: release.pageURL))
        } catch {
            return .failure(error)
        }
    }

    private nonisolated static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        // GitHub requires a User-Agent; a generic one, nothing about the person.
        request.setValue("Island", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw CheckError.badResponse(code) }
        return data
    }
}
