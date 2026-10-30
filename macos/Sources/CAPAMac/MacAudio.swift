import AppKit
import AVFoundation
import Speech
import Combine
import CoreAudio
import CapaCore

@MainActor
final class MacAudio: NSObject, ObservableObject, AVAudioRecorderDelegate, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published private(set) var recording = false
    @Published private(set) var processing = false
    @Published private(set) var speaking = false
    @Published private(set) var saved = false
    var onLimit: (() -> Void)?
    var onSpeechEnd: ((Bool) -> Void)?
    @Published private(set) var preparing = false
    @Published private(set) var voiceLevel = 0.0
    @Published private(set) var voicePitch = 0.0
    @Published private(set) var speechLanguage = "On-device model not checked yet"
    var onCaptureFailure: ((String) -> Void)?
    private var analyzerEngine: AVAudioEngine?
    private var captureGeneration = UUID()
    private let analysisQueue = DispatchQueue(label: "app.capa.voice-analysis", qos: .userInitiated)
    private var meterTask: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private let voice = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private var recognition: SFSpeechRecognitionTask?
    private var recognitionID: UUID?
    private var continuation: CheckedContinuation<String, Error>?
    private var recognitionTimeout: Task<Void, Never>?
    private var playbackTimeout: Task<Void, Never>?
    let url: URL

    override init() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("CAPA", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        url = directory.appendingPathComponent("unsent-memo.m4a")
        super.init()
        saved = FileManager.default.fileExists(atPath: url.path)
        voice.delegate = self
        // Stop rather than moving private speech onto a newly selected speaker.
        var output = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &output, .main) { [weak self] _, _ in
            Task { @MainActor in self?.stopSpeaking() }
        }
        var input = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &input, .main) { [weak self] _, _ in
            Task { @MainActor in
                if self?.recording == true {
                    self?.stop()
                    self?.onCaptureFailure?("Microphone changed. Your recording is saved; recover it or discard it before recording again.")
                }
            }
        }
    }

    func start() async throws {
        guard !preparing, !recording, !processing, !saved else { throw BridgeError.message("Recover or discard the saved memo first.") }
        preparing = true; defer { preparing = false }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw BridgeError.message("Enable CAPA's microphone in System Settings → Privacy & Security.")
        }
        stopSpeaking()
        let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record(forDuration: 180) else {
            throw BridgeError.message("Microphone is not ready.")
        }
        recorder.isMeteringEnabled = true
        self.recorder = recorder
        recording = true
        beginAnalysis()
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func stop() {
        captureGeneration = UUID()
        meterTask?.cancel(); meterTask = nil
        if let analyzerEngine {
            analyzerEngine.stop(); analyzerEngine.inputNode.removeTap(onBus: 0)
        }
        analyzerEngine = nil; voiceLevel = 0; voicePitch = 0
        recorder?.stop(); recorder = nil; recording = false
        saved = FileManager.default.fileExists(atPath: url.path)
    }
    /// User-requested preservation before a fresh capture. Never sends old audio.
    func archiveSavedMemo() throws {
        guard saved, !recording, !processing, !preparing else { throw BridgeError.message("Finish the current recording first.") }
        let directory = url.deletingLastPathComponent().appendingPathComponent("Archived Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent("memo-\(UUID().uuidString).m4a")
        try FileManager.default.moveItem(at: url, to: destination)
        saved = false
    }
    func discard() { try? FileManager.default.removeItem(at: url); saved = FileManager.default.fileExists(atPath: url.path) }

    private func beginAnalysis() {
        let generation = UUID(); captureGeneration = generation
        let engine = AVAudioEngine()
        let input = engine.inputNode, format = engine.inputNode.outputFormat(forBus: 0)
        if format.sampleRate > 0, format.channelCount > 0 {
            let queue = analysisQueue
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                guard let samples = buffer.floatChannelData?.pointee else { return }
                let values = Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
                let rate = buffer.format.sampleRate
                queue.async {
                    let signal = VoiceSignal.measure(samples: values, sampleRate: rate)
                    Task { @MainActor in
                        guard let self, self.recording, self.captureGeneration == generation else { return }
                        self.voicePitch = signal.pitch
                    }
                }
            }
            do { try engine.start(); analyzerEngine = engine }
            catch { input.removeTap(onBus: 0); engine.stop() }
        }
        // Volume comes from the recorder itself even if the optional pitch tap cannot start.
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.recording else { return }
                self.recorder?.updateMeters()
                self.voiceLevel = min(1, max(0, (Double(self.recorder?.averagePower(forChannel: 0) ?? -100) + 55) / 50))
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    func transcribe(client: BridgeClient, hostSpeech: Bool) async throws -> String {
        guard saved, !processing, !recording else { throw BridgeError.message("No saved memo is ready.") }
        processing = true; defer { processing = false }
        let authorization = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        if authorization == .authorized, let recognizer = installedRecognizer() {
            do { return try await recognizeLocally(recognizer) }
            catch is CancellationError { throw CancellationError() }
            catch {
                guard hostSpeech else {
                    throw BridgeError.message("On-device transcription failed. Your recording is saved. Retry recovery, enable on-device dictation in macOS Settings, or configure Hermes host speech.")
                }
            }
        }
        guard hostSpeech else { throw BridgeError.message("On-device recognition is unavailable. Configure Hermes host speech or type your request; your recording is saved.") }
        try Task.checkCancellation()
        return try await client.transcribe(url)
    }

    private func installedRecognizer() -> SFSpeechRecognizer? {
        let locale = Locale.current
        let language = locale.language.languageCode?.identifier ?? "en"
        let installed = SFSpeechRecognizer.supportedLocales().filter {
            $0.language.languageCode?.identifier == language &&
                SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true
        }.map(\.identifier)
        guard let chosen = SpeechLocaleChoice.select(preferred: locale.identifier, language: language,
            region: locale.region?.identifier, installed: installed) else {
            speechLanguage = "No installed on-device model for this language"
            return nil
        }
        speechLanguage = Locale.current.localizedString(forIdentifier: chosen) ?? chosen
        return SFSpeechRecognizer(locale: Locale(identifier: chosen))
    }

    private func recognizeLocally(_ recognizer: SFSpeechRecognizer) async throws -> String {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { c in
                recognitionID = id; continuation = c
                recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    let text = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                    Task { @MainActor in
                        if let text { self?.finishRecognition(id, .success(text)) }
                        else if let error { self?.finishRecognition(id, .failure(error)) }
                    }
                }
                recognitionTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(40))
                    guard !Task.isCancelled else { return }
                    self?.finishRecognition(id, .failure(BridgeError.message("Recognition timed out. Your recording is saved.")))
                }
            }
        } onCancel: { Task { @MainActor in self.finishRecognition(id, .failure(CancellationError())) } }
    }

    private func finishRecognition(_ id: UUID, _ result: Result<String, Error>) {
        guard recognitionID == id else { return }
        recognitionID = nil
        let c = continuation; continuation = nil
        recognitionTimeout?.cancel(); recognitionTimeout = nil
        recognition?.cancel(); recognition = nil
        c?.resume(with: result)
    }

    func speak(_ text: String, audio: Data? = nil, completion: @escaping (Bool) -> Void) {
        stopSpeaking()
        onSpeechEnd = completion; speaking = true
        if let audio, let player = try? AVAudioPlayer(data: audio) {
            self.player = player; player.delegate = self
            if !player.play() { endSpeech(false) }
        } else {
            let phrase = AVSpeechUtterance(string: text)
            phrase.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance = phrase; voice.speak(phrase)
        }
        playbackTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else { return }
            self?.stopSpeaking()
        }
    }
    func stopSpeaking() {
        utterance = nil; player?.stop(); player = nil
        voice.stopSpeaking(at: .immediate)
        if onSpeechEnd != nil { endSpeech(false) }
    }
    private func endSpeech(_ success: Bool) {
        playbackTimeout?.cancel(); playbackTimeout = nil
        speaking = false; utterance = nil; player = nil
        let callback = onSpeechEnd; onSpeechEnd = nil
        callback?(success)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if self.utterance === utterance { self.endSpeech(true) } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in if self.utterance === utterance { self.endSpeech(false) } }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if self.player === player { self.endSpeech(flag) } }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder && self.recording else { return }
            if flag { self.onLimit?() }
            else { self.stop(); self.onCaptureFailure?("Recording was interrupted. Your audio is saved for recovery.") }
        }
    }
}
