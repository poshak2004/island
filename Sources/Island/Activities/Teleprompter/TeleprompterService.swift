import AppKit
import IslandCore
import Observation

/// Owns the single teleprompter session. Event-driven like timers: the activity stores an anchor and a
/// rate, the view extrapolates the scroll, and the only scheduled wake-up is the moment it finishes.
@MainActor
@Observable
final class TeleprompterService {
    static let activityID = "teleprompter"

    @ObservationIgnored private let settings: IslandSettings
    @ObservationIgnored private let sink: (ActivityUpdate) -> Void
    @ObservationIgnored private let voice = VoiceFollower()
    @ObservationIgnored private var finishTask: Task<Void, Never>?
    private(set) var current: TeleprompterActivity?
    /// Characters per line for the current display (from the expanded width and font size).
    @ObservationIgnored var lineCharacters: () -> Int = { 40 }
    /// Called when the session starts, so the Island can open; and when it ends.
    @ObservationIgnored var onSessionChange: ((Bool) -> Void)?
    /// Whether the pointer is over the Island right now (a session can start under it).
    @ObservationIgnored var isPointerInside: () -> Bool = { false }
    /// Voice follow problems (permission denied, recogniser unavailable) for the UI to surface.
    private(set) var lastVoiceError: String?

    init(settings: IslandSettings, sink: @escaping (ActivityUpdate) -> Void) {
        self.settings = settings
        self.sink = sink
        voice.onWords = { [weak self] words in self?.heard(words) }
        voice.onListening = { [weak self] on in self?.listeningChanged(on) }
    }

    var isActive: Bool { current != nil }

    func handle(_ command: TeleprompterCommand) {
        let now = Date()
        switch command {
        case .start(let text, let title):
            start(text: text, title: title, autoplay: true)
            return
        case .stop:
            stop()
            return
        default:
            break
        }
        guard var a = current else { return }
        switch command {
        case .togglePlayPause:
            if a.state == .playing { a.pause(at: now) } else { a.play(at: now) }
        case .restart:
            a.seek(toWord: 0, at: now)
        case .faster:
            a.setSpeed(a.wordsPerMinute + TeleprompterActivity.speedStep, at: now)
            settings.teleprompterSpeed = a.wordsPerMinute
        case .slower:
            a.setSpeed(a.wordsPerMinute - TeleprompterActivity.speedStep, at: now)
            settings.teleprompterSpeed = a.wordsPerMinute
        case .skip(let lines):
            a.skip(lines: lines, at: now)
        case .toggleVoiceFollow:
            a.setVoiceFollow(!a.voiceFollow, at: now)
            settings.teleprompterVoiceFollow = a.voiceFollow
        case .pointerInside(let inside):
            guard settings.teleprompterPauseOnHover, a.hoverPaused != inside else { return }
            a.setHoverPaused(inside, at: now)
        case .start, .stop:
            return
        }
        update(a)
    }

    /// Opens a script. `autoplay: false` is used when the camera turns on: ready, but waiting for you.
    func start(text: String, title: String, autoplay: Bool) {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let script = TeleprompterScript(text: source, title: title, maxLineChars: lineCharacters()) else { return }
        let now = Date()
        var a = TeleprompterActivity(script: script, wordsPerMinute: settings.teleprompterSpeed, anchorDate: now)
        if settings.teleprompterVoiceFollow { a.setVoiceFollow(true, at: now) }
        if autoplay { a.play(at: now) }
        if settings.teleprompterPauseOnHover, isPointerInside() { a.setHoverPaused(true, at: now) }
        let isNew = current == nil
        update(a)
        if isNew { onSessionChange?(true) }
    }

    func stop() {
        guard current != nil else { return }
        current = nil
        finishTask?.cancel()
        voice.stop()
        sink(.remove(id: Self.activityID))
        onSessionChange?(false)
    }

    /// The activity was dismissed elsewhere (manager, debug panel).
    func activityEnded() {
        guard current != nil else { return }
        current = nil
        finishTask?.cancel()
        voice.stop()
        onSessionChange?(false)
    }

    // MARK: Internals

    private func update(_ a: TeleprompterActivity) {
        current = a
        syncVoice(a)
        scheduleFinish(a)
        // High while reading so it holds the Island; low once finished so other activities can return.
        let priority: ActivityPriority = a.state == .finished ? .low : .high
        sink(.upsert(Activity(id: Self.activityID, kind: .teleprompter, priority: priority, content: .teleprompter(a))))
    }

    private func scheduleFinish(_ a: TeleprompterActivity) {
        finishTask?.cancel()
        guard let end = a.finishDate else { return }
        let delay = max(0, end.timeIntervalSinceNow)
        finishTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((delay + 0.05) * 1_000_000_000))
            guard !Task.isCancelled, let self, var a = self.current else { return }
            a.markFinished(at: Date())
            self.update(a)
        }
    }

    private func syncVoice(_ a: TeleprompterActivity) {
        let wantsVoice = a.voiceFollow && a.state == .playing
        if wantsVoice, !voice.isRunning, !voice.isStarting {
            Task { [weak self] in
                guard let self else { return }
                let error = await self.voice.start()
                self.lastVoiceError = error
                if let error, var a = self.current {
                    NSLog("Island: voice follow unavailable: %@", error)
                    a.setVoiceFollow(false, at: Date())
                    self.update(a)
                }
            }
        } else if !wantsVoice, voice.isRunning || voice.isStarting {
            voice.stop()
        }
    }

    private func heard(_ words: [String]) {
        guard var a = current, a.voiceFollow, a.state == .playing else { return }
        let now = Date()
        let at = Int(a.position(at: now).rounded(.down))
        guard let next = ScriptMatcher.advance(script: a.script.words, current: at, heard: words), next != at else { return }
        a.seek(toWord: Double(next), at: now)
        if next >= a.script.wordCount { a.markFinished(at: now) }
        update(a)
    }

    private func listeningChanged(_ on: Bool) {
        guard var a = current, a.listening != on else { return }
        a.listening = on
        update(a)
    }
}
