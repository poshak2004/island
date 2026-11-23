import AVFoundation
import Foundation
import Speech

/// On-device speech recognition for teleprompter voice follow. Audio never leaves the Mac:
/// recognition is refused when the on-device model isn't available rather than falling back to a server.
@MainActor
final class VoiceFollower {
    /// The most recent words heard (tail of the current transcript).
    var onWords: (([String]) -> Void)?
    var onListening: ((Bool) -> Void)?
    private(set) var isRunning = false
    /// Permission prompts are up; `start()` must not run twice.
    private(set) var isStarting = false
    /// Cleared by `stop()`, so a stop during the permission prompts wins over the pending start.
    private var wanted = false
    /// Bumped for every recognition task; callbacks from older tasks are ignored.
    private var generation = 0

    /// Created on first use only. Touching `inputNode` binds the microphone and can block the main
    /// thread in CoreAudio, so nothing here touches the engine unless listening really started.
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartWork: DispatchWorkItem?
    nonisolated private static let tailWords = 6
    private static let restartDelay: TimeInterval = 0.3

    enum StartError: LocalizedError {
        case noInputDevice
        var errorDescription: String? { "No microphone is available." }
    }

    /// Starts listening. Returns a user-facing reason when it can't.
    func start() async -> String? {
        guard !isRunning, !isStarting else { return nil }
        wanted = true
        isStarting = true
        defer { isStarting = false }
        guard await Self.speechAuthorized() else {
            return "Speech recognition is off for Island. Turn it on in System Settings › Privacy & Security › Speech Recognition."
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            return "Island can't use the microphone. Turn it on in System Settings › Privacy & Security › Microphone."
        }
        guard wanted else { return nil } // turned off while the prompts were up
        guard let recognizer = Self.recognizer(), recognizer.isAvailable else {
            return "Speech recognition isn't available for your language right now."
        }
        guard recognizer.supportsOnDeviceRecognition else {
            return "On-device speech recognition isn't available for your language, so voice follow stays off."
        }
        isRunning = true
        do {
            try begin(with: recognizer)
        } catch {
            stop()
            return "Couldn't start listening: \(error.localizedDescription)"
        }
        onListening?(true)
        return nil
    }

    func stop() {
        wanted = false
        guard isRunning || isStarting || tapInstalled || task != nil else { return } // never started: nothing to touch
        restartWork?.cancel()
        let wasRunning = isRunning
        isRunning = false
        tearDown()
        if wasRunning { onListening?(false) }
    }

    // MARK: Internals

    private func begin(with recognizer: SFSpeechRecognizer) throws {
        let engine = self.engine ?? AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // No device, or one mid-switch (Bluetooth headsets): installing a tap with this format raises.
        guard format.sampleRate > 0, format.channelCount > 0 else { throw StartError.noInputDevice }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.request = request
        generation += 1

        if tapInstalled { input.removeTap(onBus: 0) }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(for: request))
        tapInstalled = true
        engine.prepare()
        try engine.start()
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(generation: generation, owner: self))
    }

    /// Built outside the main actor: the audio thread calls this, and it must not inherit main-actor isolation.
    nonisolated private static func tapBlock(for request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { @Sendable buffer, _ in request.append(buffer) }
    }

    nonisolated private static func resultHandler(generation: Int, owner: VoiceFollower) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak owner] result, error in
            let words = result.map { $0.bestTranscription.segments.suffix(tailWords).map(\.substring) }
            let ended = error != nil || (result?.isFinal ?? false)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { owner?.received(words: words, ended: ended, generation: generation) }
            }
        }
    }

    private func received(words: [String]?, ended: Bool, generation: Int) {
        guard isRunning, generation == self.generation else { return }
        if let words, !words.isEmpty { onWords?(words) }
        if ended { scheduleRestart() }
    }

    /// Recognition tasks end on long pauses or after a time limit; keep listening by starting a new one.
    private func scheduleRestart() {
        restartWork?.cancel()
        tearDown()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, let recognizer = Self.recognizer() else { return }
            do { try self.begin(with: recognizer) } catch {
                NSLog("Island: voice follow restart failed: %@", error.localizedDescription)
                self.stop()
            }
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restartDelay, execute: work)
    }

    private func tearDown() {
        generation += 1 // late callbacks from the old task are now stale
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        guard let engine else { return }
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private static func recognizer() -> SFSpeechRecognizer? {
        SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    private static func speechAuthorized() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { c in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
            }
        @unknown default: return false
        }
    }
}
