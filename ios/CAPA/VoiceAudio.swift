import AVFoundation
import Speech
import Combine
import CapaCore

/// Owns deliberate capture. PTT owns audio-session activation during a PTT turn.
@MainActor
final class VoiceAudio: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate, AVAudioRecorderDelegate {
    @Published private(set) var recording = false
    @Published private(set) var processing = false
    @Published private(set) var speaking = false
    @Published private(set) var level: Float = 0
    @Published private(set) var hasSavedRecording = false
    var onRecordingLimit: (() -> Void)?
    private var recorder: AVAudioRecorder?
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var completion: ((Bool) -> Void)?
    private var recognition: SFSpeechRecognitionTask?
    private var recognitionID: UUID?
    private var recognitionContinuation: CheckedContinuation<String, Error>?
    private var recognitionTimeout: Task<Void, Never>?
    private var meter: Timer?
    private var pttPlayback = false
    private var activeUtterance: AVSpeechUtterance?
    private var speechWatchdog: Task<Void, Never>?
    let memoURL = URL.documentsDirectory.appendingPathComponent("unsent-memo.m4a")

    override init() {
        super.init(); synthesizer.delegate = self
        hasSavedRecording = FileManager.default.fileExists(atPath: memoURL.path)
    }

    func microphonePermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startCapture(systemOwnsSession: Bool = false) throws {
        guard !recording, !processing else { return }
        guard !hasSavedRecording else { throw BridgeError.message("Recover or discard the saved recording before starting another memo.") }
        if !systemOwnsSession {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        }
        let recorder = try AVAudioRecorder(url: memoURL, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24000,
            AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
        recorder.isMeteringEnabled = true
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record(forDuration: 180) else { throw BridgeError.message("Microphone is not ready.") }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: memoURL.path)
        self.recorder = recorder
        recording = true
        meter = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recorder?.updateMeters()
                self?.level = pow(10, (self?.recorder?.averagePower(forChannel: 0) ?? -80) / 20)
            }
        }
    }

    func finishCapture(systemOwnsSession: Bool = false) {
        recorder?.stop() // Finalizes the audio file before recognition reads it.
        recorder = nil
        meter?.invalidate(); meter = nil
        recording = false; level = 0
        hasSavedRecording = FileManager.default.fileExists(atPath: memoURL.path)
        if !systemOwnsSession { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    func discardMemo() {
        try? FileManager.default.removeItem(at: memoURL)
        hasSavedRecording = FileManager.default.fileExists(atPath: memoURL.path)
    }

    func transcribe(using client: BridgeClient, hostSpeech: Bool) async throws -> String {
        guard FileManager.default.fileExists(atPath: memoURL.path) else { throw BridgeError.message("No saved recording.") }
        processing = true
        defer { processing = false }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        if status == .authorized, let recognizer = SFSpeechRecognizer(), recognizer.supportsOnDeviceRecognition {
            let request = SFSpeechURLRecognitionRequest(url: memoURL)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false
            let id = UUID()
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    recognitionID = id
                    recognitionContinuation = continuation
                    recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                        let finalText = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                        Task { @MainActor in
                            if let finalText { self?.finishRecognition(id, result: .success(finalText)) }
                            else if let error { self?.finishRecognition(id, result: .failure(error)) }
                        }
                    }
                    recognitionTimeout = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(40))
                        guard !Task.isCancelled else { return }
                        self?.finishRecognition(id, result: .failure(BridgeError.message(
                            "Recognition timed out. Your recording is saved for retry.")))
                    }
                }
            } onCancel: {
                Task { @MainActor in self.finishRecognition(id, result: .failure(CancellationError())) }
            }
        }
        guard hostSpeech else {
            throw BridgeError.message("On-device recognition is unavailable for this language. Enable host speech or type your memo; the recording is saved.")
        }
        return try await client.transcribe(memoURL)
    }

    private func finishRecognition(_ id: UUID, result: Result<String, Error>) {
        guard recognitionID == id else { return }
        recognitionID = nil
        recognitionTimeout?.cancel(); recognitionTimeout = nil
        let continuation = recognitionContinuation; recognitionContinuation = nil
        recognition?.cancel(); recognition = nil
        continuation?.resume(with: result)
    }

    func play(_ text: String, audio: Data? = nil, systemOwnsSession: Bool = false,
              completion: @escaping (Bool) -> Void) {
        stopPlayback()
        self.completion = completion
        pttPlayback = systemOwnsSession
        do {
            if !systemOwnsSession {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
            }
            speaking = true
            if let audio {
                let player = try AVAudioPlayer(data: audio)
                player.delegate = self
                self.player = player
                guard player.play() else { finishPlayback(false); return }
            } else {
                // PTT activates the application's shared session. A separate
                // system-managed synthesis session would not inherit that grant.
                synthesizer.usesApplicationAudioSession = true
                let utterance = AVSpeechUtterance(string: text)
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                activeUtterance = utterance
                synthesizer.speak(utterance)
            }
            speechWatchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(90))
                guard !Task.isCancelled else { return }
                self?.stopPlayback()
            }
        } catch { finishPlayback(false) }
    }

    func stopPlayback() {
        activeUtterance = nil
        player?.stop(); player = nil
        synthesizer.stopSpeaking(at: .immediate)
        if completion != nil { finishPlayback(false) }
    }

    private func finishPlayback(_ success: Bool) {
        speechWatchdog?.cancel(); speechWatchdog = nil
        speaking = false
        activeUtterance = nil
        player = nil
        if !pttPlayback { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        let callback = completion; completion = nil
        callback?(success)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.activeUtterance === utterance else { return }
            self.finishPlayback(true)
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.activeUtterance === utterance else { return }
            self.finishPlayback(false)
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.finishPlayback(flag)
        }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder, self.recording else { return }
            self.onRecordingLimit?()
        }
    }
}
