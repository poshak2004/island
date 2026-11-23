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

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartWork: DispatchWorkItem?
    private static let tailWords = 6
    private static let restartDelay: TimeInterval = 0.3

    /// Starts listening. Returns a user-facing reason when it can't.
    func start() async -> String? {
        guard !isRunning else { return nil }
        guard await Self.speechAuthorized() else {
            return "Speech recognition is off for Island. Turn it on in System Settings › Privacy & Security › Speech Recognition."
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            return "Island can't use the microphone. Turn it on in System Settings › Privacy & Security › Microphone."
        }
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
        restartWork?.cancel()
        let wasRunning = isRunning
        isRunning = false
        tearDown()
        if wasRunning { onListening?(false) }
    }

    // MARK: Internals

    private func begin(with recognizer: SFSpeechRecognizer) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer) // thread-safe; captured directly so the tap never touches self
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let words = result.map { $0.bestTranscription.segments.suffix(Self.tailWords).map(\.substring) }
            let ended = error != nil || (result?.isFinal ?? false)
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                if let words, !words.isEmpty { self.onWords?(words) }
                if ended { self.scheduleRestart() }
            }
        }
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
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
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
