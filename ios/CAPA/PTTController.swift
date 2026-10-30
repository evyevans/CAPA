import AVFoundation
import PushToTalk
import UIKit
import Combine

/// Delegate callbacks may arrive before SwiftUI is visible, including a cold background launch.
final class PTTController: NSObject, ObservableObject, PTChannelManagerDelegate, PTChannelRestorationDelegate {
    @Published private(set) var joined = false
    @Published private(set) var status = "Voice channel off"
    private var manager: PTChannelManager?
    private var initializing = false
    private var joining = false
    private let lock = NSLock()
    private var permitted = false
    private var pendingEventID: String?
    private var audioActive = false
    private var transmitting = false
    private var captureRequested = false
    private var incomingWatchdog: Task<Void, Never>?
    let channelID: UUID = {
        let key = "capa.channelID"
        if let value = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: value) { return id }
        let id = UUID(); UserDefaults.standard.set(id.uuidString, forKey: key); return id
    }()
    var onToken: (@MainActor (String) -> Void)?
    var onIncoming: (@MainActor (String) -> Void)?
    var onCaptureStart: (@MainActor () -> Void)?
    var onCaptureEnd: (@MainActor () -> Void)?
    var onLeave: (@MainActor () -> Void)?
    var onError: (@MainActor (String) -> Void)?

    @MainActor
    func initialize(available: Bool) async {
        lock.withLock { permitted = available }
        guard manager == nil, !initializing else { return }
        initializing = true
        defer { initializing = false }
        do {
            manager = try await PTChannelManager.channelManager(delegate: self, restorationDelegate: self)
            joined = available && manager?.activeChannelUUID == channelID
            if joined { status = "Available for Hermes" }
            if !available, let active = manager?.activeChannelUUID {
                manager?.leaveChannel(channelUUID: active)
            }
            if available, manager?.activeChannelUUID == nil {
                joining = true
                manager?.requestJoinChannel(channelUUID: channelID, descriptor: descriptor())
            }
        } catch {
            status = "Notifications available; voice channel unavailable"
            onError?("Voice channel could not start. CAPA will retain your results and use notifications when configured.")
        }
    }

    @MainActor
    func setAvailable(_ value: Bool) async {
        lock.withLock { permitted = value }
        await initialize(available: value)
        if value {
            guard let manager else { return }
            if manager.activeChannelUUID == channelID { joined = true; return }
            guard !joining else { return }
            joining = true
            status = "Connecting voice channel…"
            manager.requestJoinChannel(channelUUID: channelID, descriptor: descriptor())
        } else {
            finishReceiving()
            if let active = manager?.activeChannelUUID { manager?.leaveChannel(channelUUID: active) }
            joined = false; status = "Voice channel off"
        }
    }

    private func descriptor() -> PTChannelDescriptor {
        PTChannelDescriptor(name: "CAPA · Hermes", image: UIImage(systemName: "waveform"))
    }

    @MainActor
    func startTransmitting() { manager?.requestBeginTransmitting(channelUUID: channelID) }
    @MainActor
    func stopTransmitting() { manager?.stopTransmitting(channelUUID: channelID) }

    @MainActor
    func finishReceiving() {
        incomingWatchdog?.cancel(); incomingWatchdog = nil
        lock.withLock { pendingEventID = nil }
        manager?.setActiveRemoteParticipant(nil, channelUUID: channelID, completionHandler: nil)
    }

    func channelDescriptor(restoredChannelUUID channelUUID: UUID) -> PTChannelDescriptor { descriptor() }

    func channelManager(_ channelManager: PTChannelManager, didJoinChannel channelUUID: UUID, reason: PTChannelJoinReason) {
        Task { @MainActor in
            self.joining = false
            guard self.lock.withLock({ self.permitted }) else {
                channelManager.leaveChannel(channelUUID: channelUUID)
                return
            }
            self.joined = true; self.status = "Available for Hermes"
        }
    }
    func channelManager(_ channelManager: PTChannelManager, didLeaveChannel channelUUID: UUID, reason: PTChannelLeaveReason) {
        lock.withLock { permitted = false; pendingEventID = nil; audioActive = false; transmitting = false }
        Task { @MainActor in
            self.joining = false; self.joined = false; self.status = "Voice channel off"; self.onLeave?()
        }
    }
    func channelManager(_ channelManager: PTChannelManager, failedToJoinChannel channelUUID: UUID, error: Error) {
        Task { @MainActor in
            self.joining = false; self.joined = false; self.status = "Using notification fallback"
            self.onError?("Voice channel could not join. Results remain available in CAPA.")
        }
    }
    func channelManager(_ channelManager: PTChannelManager, failedToLeaveChannel channelUUID: UUID, error: Error) {
        Task { @MainActor in self.onError?("Voice reception is disabled locally; the system channel could not close yet.") }
    }
    func channelManager(_ channelManager: PTChannelManager, receivedEphemeralPushToken pushToken: Data) {
        let token = pushToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in self.onToken?(token) }
    }

    func incomingPushResult(channelManager: PTChannelManager, channelUUID: UUID, pushPayload: [String: Any]) -> PTPushResult {
        let allowed = lock.withLock { permitted }
        guard allowed, channelUUID == channelID,
              let id = pushPayload["event_id"] as? String, UUID(uuidString: id) != nil,
              pushPayload["channel_id"] as? String == channelID.uuidString else { return .leaveChannel }
        let wasTransmitting = lock.withLock { transmitting }
        if wasTransmitting { channelManager.stopTransmitting(channelUUID: channelUUID) }
        lock.withLock { pendingEventID = id }
        // No network request occurs on this synchronous delegate callback.
        Task { @MainActor in
            self.incomingWatchdog?.cancel()
            self.incomingWatchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(100))
                guard !Task.isCancelled else { return }
                self?.finishReceiving()
            }
        }
        return .activeRemoteParticipant(PTParticipant(name: "Hermes", image: nil))
    }

    func channelManager(_ channelManager: PTChannelManager, didActivate audioSession: AVAudioSession) {
        let state = lock.withLock { () -> (String?, Bool) in
            audioActive = true
            return (pendingEventID, captureRequested)
        }
        Task { @MainActor in
            if let id = state.0 { self.onIncoming?(id) }
            else if state.1 { self.onCaptureStart?() }
        }
    }
    func channelManager(_ channelManager: PTChannelManager, didDeactivate audioSession: AVAudioSession) {
        lock.withLock { audioActive = false }
    }
    func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID,
                        didBeginTransmittingFrom source: PTChannelTransmitRequestSource) {
        let active = lock.withLock { () -> Bool in
            transmitting = true; captureRequested = true; return audioActive
        }
        if active { Task { @MainActor in self.onCaptureStart?() } }
    }
    func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID,
                        didEndTransmittingFrom source: PTChannelTransmitRequestSource) {
        lock.withLock { transmitting = false; captureRequested = false }
        Task { @MainActor in self.onCaptureEnd?() }
    }
    func channelManager(_ channelManager: PTChannelManager, failedToBeginTransmittingInChannel channelUUID: UUID, error: Error) {
        Task { @MainActor in self.onError?("Microphone is unavailable. Check for an active call and try again.") }
    }
    func channelManager(_ channelManager: PTChannelManager, failedToStopTransmittingInChannel channelUUID: UUID, error: Error) {
        Task { @MainActor in self.onError?("Transmission could not stop. Leave the voice channel to end it.") }
    }
}
