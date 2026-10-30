import AVFoundation
import SwiftUI
import UserNotifications
import CapaCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var credential: Credential? = CredentialStore.load()
    @Published var available = UserDefaults.standard.bool(forKey: "capa.available")
    @Published var message = ""
    @Published var draft = UserDefaults.standard.string(forKey: "capa.draft") ?? "" {
        didSet { UserDefaults.standard.set(draft, forKey: "capa.draft") }
    }
    @Published var identity: WorkspaceIdentity?
    @Published var linkedDevices: [LinkedDevice] = []
    @Published var connections: ConnectionInventory?
    @Published var invitation: DeviceInvitation?
    @Published var spokenAcknowledgment = UserDefaults.standard.bool(forKey: "capa.spokenAck") {
        didSet { UserDefaults.standard.set(spokenAcknowledgment, forKey: "capa.spokenAck") }
    }
    @Published var tasks: [AgentTask] = []
    @Published var events: [AgentEvent] = []
    @Published var busy = false
    @Published var pushConfigured = false
    @Published var hostSpeech = false
    @Published var selectedTask: AgentTask?
    @Published var capturePending = false
    @Published private(set) var replyContext: ClarificationReply? {
        didSet {
            if let replyContext, let data = try? JSONEncoder().encode(replyContext) {
                UserDefaults.standard.set(data, forKey: "capa.replyContext")
            } else { UserDefaults.standard.removeObject(forKey: "capa.replyContext") }
        }
    }
    let audio = VoiceAudio()
    let ptt = PTTController()
    private var policy = DeliveryPolicy(available: false)
    private var pendingMemo: PendingMemo?
    private var notificationToken: String?
    private var pttToken: String?
    private var observers: [NSObjectProtocol] = []
    private var refreshRunning = false
    private var playedTokens = UserDefaults.standard.dictionary(forKey: "capa.playedTokens") as? [String: String] ?? [:]
    private var memoProcessingTask: Task<Void, Never>?
    var client: BridgeClient? { credential.map(BridgeClient.init) }
    var hasPendingSubmission: Bool { pendingMemo != nil }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "capa.replyContext") {
            replyContext = try? JSONDecoder().decode(ClarificationReply.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: "capa.pendingMemo") {
            pendingMemo = try? JSONDecoder().decode(PendingMemo.self, from: data)
            draft = pendingMemo?.text ?? ""
        }
        let receipts = Set(UserDefaults.standard.stringArray(forKey: "capa.played") ?? [])
        policy = DeliveryPolicy(available: available, acknowledged: receipts)
        ptt.onToken = { [weak self] token in
            self?.pttToken = token
            Task { await self?.syncDevice() }
        }
        ptt.onIncoming = { [weak self] id in Task { await self?.receive(id, systemOwnsSession: true) } }
        ptt.onCaptureStart = { [weak self] in self?.beginPTTCapture() }
        ptt.onCaptureEnd = { [weak self] in self?.endPTTCapture() }
        ptt.onLeave = { [weak self] in
            guard let self else { return }
            self.available = false; self.policy.available = false
            UserDefaults.standard.set(false, forKey: "capa.available")
            self.audio.stopPlayback()
            self.audio.finishCapture(systemOwnsSession: true)
            Task { await self.syncDevice() }
        }
        ptt.onError = { [weak self] in self?.message = $0 }
        audio.onRecordingLimit = { [weak self] in
            guard let self else { return }
            Task { await self.toggleRecording() }
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] notification in
                guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      type == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in self?.interruptAudio() }
            })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main) { [weak self] notification in
                guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                Task { @MainActor in self?.interruptAudio() }
            })
    }

    func initialize() async {
        // Preserve the user's restored channel intent. Automatic playback still
        // requires a fresh workspace lease, even while the host is unreachable.
        await ptt.initialize(available: credential != nil && available)
        if credential != nil {
            UIApplication.shared.registerForRemoteNotifications()
            await refresh()
            if available { await ptt.setAvailable(true) }
            await syncDevice()
        }
    }

    func pair(url: String, code: String) async {
        busy = true; defer { busy = false }
        do {
            let value = try await BridgeClient.pair(url: url, code: code)
            try CredentialStore.save(value)
            credential = value
            message = "Paired with your Hermes bridge."
            await refresh()
        } catch { message = error.localizedDescription }
    }

    func setAvailable(_ value: Bool) async {
        available = value; policy.available = value
        UserDefaults.standard.set(value, forKey: "capa.available")
        if !value { interruptAudio(); pttToken = nil }
        if value {
            guard await audio.microphonePermission() else {
                available = false; policy.available = false
                UserDefaults.standard.set(false, forKey: "capa.available")
                message = "Enable microphone access in iPhone Settings to use the voice channel."
                return
            }
            await enableNotifications()
            do {
                if let client, let credential {
                    identity = try await client.preferences(mode: "spoken", deviceID: credential.deviceID)
                }
            } catch {
                available = false; policy.available = false
                UserDefaults.standard.set(false, forKey: "capa.available")
                message = "Could not select this phone for spoken updates. Try again when connected."
                return
            }
        }
        await ptt.setAvailable(value)
        await syncDevice()
    }

    func enableNotifications() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if allowed { UIApplication.shared.registerForRemoteNotifications() }
            else { message = "Notifications are off. Results remain available when you open CAPA." }
        } catch { message = error.localizedDescription }
    }

    func registerNotificationToken(_ data: Data) {
        notificationToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await syncDevice() }
    }

    func syncDevice() async {
        guard let client else { return }
        var body: [String: Any] = ["available": available]
        if let notificationToken { body["notification_token"] = notificationToken }
        if available, let pttToken {
            body["ptt_token"] = pttToken; body["channel_id"] = ptt.channelID.uuidString
        }
        do { try await client.device(body) }
        catch { message = "Availability change is saved on this phone; the bridge is unreachable. CAPA will retry when opened." }
    }

    func refresh() async {
        guard !refreshRunning, let client else { return }
        refreshRunning = true; defer { refreshRunning = false }
        do {
            tasks = try await client.tasks()
            events = try await client.events()
            identity = try await client.identity()
            linkedDevices = try await client.linkedDevices()
            if available && (identity?.reply_mode != "spoken" || identity?.preferred_device_id != credential?.deviceID) {
                available = false; policy.available = false
                UserDefaults.standard.set(false, forKey: "capa.available")
                interruptAudio(); await ptt.setAvailable(false)
            }
            let capabilities: BridgeCapabilities = try await client.call("v1/capabilities")
            pushConfigured = capabilities.push_configured; hostSpeech = capabilities.host_speech
            // Retry receipts lost during a disconnect before considering any new speech.
            for event in events where policy.acknowledged.contains(event.id) {
                try? await client.acknowledge(event.id, token: playedTokens[event.id])
            }
            events.removeAll { policy.acknowledged.contains($0.id) }
            if let selected = selectedTask { selectedTask = tasks.first { $0.id == selected.id } }
        } catch { message = "Your bridge is unavailable. Saved tasks will return when it reconnects." }
    }

    func toggleRecording() async {
        guard client != nil, !busy, !audio.processing else { return }
        if audio.speaking { interruptAudio(); return }
        if audio.recording || capturePending {
            if ptt.joined { ptt.stopTransmitting() }
            else { audio.finishCapture(); await transcribeMemo() }
            return
        }
        guard !hasPendingSubmission else { message = "Resolve the pending submission before recording another memo."; return }
        guard !audio.hasSavedRecording else { message = "Recover or discard your saved recording before starting another memo."; return }
        guard draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Send or clear your current typed draft before recording another memo."; return
        }
        guard await audio.microphonePermission() else { message = "Enable CAPA's microphone in iPhone Settings."; return }
        capturePending = true
        if ptt.joined { ptt.startTransmitting() }
        else {
            do { try audio.startCapture(); capturePending = false }
            catch { capturePending = false; message = error.localizedDescription }
        }
    }

    private func beginPTTCapture() {
        guard !hasPendingSubmission else { ptt.stopTransmitting(); return }
        do { try audio.startCapture(systemOwnsSession: true); capturePending = false }
        catch { capturePending = false; message = error.localizedDescription; ptt.stopTransmitting() }
    }

    private func endPTTCapture() {
        capturePending = false
        guard audio.recording else { return }
        audio.finishCapture(systemOwnsSession: true)
        memoProcessingTask = Task {
            let background = UIApplication.shared.beginBackgroundTask(withName: "Finish CAPA memo") { [weak self] in
                Task { @MainActor in
                    self?.memoProcessingTask?.cancel()
                    self?.message = "iOS paused memo processing. Your recording is saved; reopen CAPA to retry."
                }
            }
            defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
            await transcribeMemo()
        }
    }

    func transcribeMemo() async {
        guard let client else { return }
        do {
            draft = try await audio.transcribe(using: client, hostSpeech: hostSpeech)
            guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                message = "No words recognized. The recording is saved for retry."; return
            }
            await sendDraft()
        } catch { message = error.localizedDescription }
    }

    func sendDraft() async {
        guard !busy, let client else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pendingMemo != nil || !text.isEmpty else { return }
        busy = true; defer { busy = false }
        if let context = replyContext {
            // A reply resumes the existing waiter; it must never start another run.
            do {
                try await client.control(taskID: context.taskID, control: context.control, answer: text)
                draft = ""; replyContext = nil; audio.discardMemo()
                message = "Your answer was sent to Hermes."
                await refresh()
            } catch { message = "Reply not confirmed. Review the current question before retrying. Your memo is saved." }
            return
        }
        if pendingMemo == nil { pendingMemo = PendingMemo(text: text) }
        pendingMemo?.markSending(); saveMemo()
        do {
            let task = try await client.submit(pendingMemo!)
            pendingMemo?.accept(runID: task.runID)
            if task.runID != nil {
                pendingMemo = nil; draft = ""; audio.discardMemo(); saveMemo()
                message = "Received by Hermes. You can go about your day."
                if spokenAcknowledgment && UIApplication.shared.applicationState == .active {
                    audio.play("Your request was received by Hermes. I'll report back when there's an update.") { _ in }
                }
            } else if task.terminal {
                pendingMemo = nil; saveMemo()
                message = "Hermes could not confirm this request. Review its task status before trying again."
            } else {
                saveMemo(); message = "Sent to the bridge; Hermes acceptance is not confirmed yet. Retry checks the same request."
            }
            await refresh()
        } catch {
            pendingMemo?.markUnconfirmed(); saveMemo()
            message = "Acceptance is unconfirmed. Your memo is saved; retry uses the same request ID."
        }
    }

    private func saveMemo() {
        if let pendingMemo, let data = try? JSONEncoder().encode(pendingMemo) {
            UserDefaults.standard.set(data, forKey: "capa.pendingMemo")
        } else { UserDefaults.standard.removeObject(forKey: "capa.pendingMemo") }
    }

    func receive(_ id: String, systemOwnsSession: Bool = false, manual: Bool = false) async {
        guard let client else { ptt.finishReceiving(); return }
        if !manual && (!available || policy.acknowledged.contains(id)) { ptt.finishReceiving(); return }
        guard !audio.recording, !audio.processing, !audio.speaking else { ptt.finishReceiving(); return }
        let oldAvailable = policy.available
        if manual { policy.available = true }
        let eligible = policy.begin(id)
        policy.available = oldAvailable
        guard eligible else { ptt.finishReceiving(); return }
        let playbackToken = UUID().uuidString
        do {
            let event = try await client.event(id)
            if manual {
                selectedTask = try? await client.call("v1/tasks/\(event.taskID)")
            }
            guard event.acknowledged == 0 else { policy.finished(id); ptt.finishReceiving(); return }
            if event.kind == "clarification", pendingMemo == nil, replyContext == nil,
               !audio.hasSavedRecording, draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let task: AgentTask = try await client.call("v1/tasks/\(event.taskID)")
                if let control = task.controls.first(where: { $0.isClarification }) {
                    replyContext = ClarificationReply(taskID: task.id, control: control)
                }
            }
            // Approval details remain on screen; automatic speech only requests a review.
            let data = hostSpeech ? try? await client.audio(id) : nil
            guard manual || available else { policy.interrupted(); ptt.finishReceiving(); return }
            guard !audio.recording, !capturePending, !audio.processing, !audio.speaking else {
                policy.interrupted(); ptt.finishReceiving(); return
            }
            try await client.claim(id, token: playbackToken, manual: manual)
            guard (manual || available), !audio.recording, !capturePending, !audio.processing, !audio.speaking else {
                policy.interrupted(); ptt.finishReceiving(); return
            }
            audio.play(event.announcement, audio: event.kind == "approval" ? nil : data,
                       systemOwnsSession: systemOwnsSession) { [weak self] completed in
                guard let self else { return }
                if completed {
                    self.policy.finished(id)
                    self.playedTokens[id] = playbackToken
                    UserDefaults.standard.set(self.playedTokens, forKey: "capa.playedTokens")
                    UserDefaults.standard.set(Array(self.policy.acknowledged), forKey: "capa.played")
                    Task { try? await client.acknowledge(id, token: playbackToken); await self.refresh() }
                } else { self.policy.interrupted() }
                if systemOwnsSession { self.ptt.finishReceiving() }
            }
        } catch {
            policy.interrupted(); ptt.finishReceiving()
            message = "This update could not play. It remains saved for you to open."
        }
    }

    func openUpdate(_ id: String) async {
        guard let client else { return }
        do {
            let event = try await client.event(id)
            selectedTask = try await client.call("v1/tasks/\(event.taskID)")
            await refresh()
        } catch { message = "Update unavailable. Reconnect to retrieve your saved work." }
    }

    func loadConnections() async {
        do { connections = try await client?.connections() }
        catch { connections = nil; message = "Hermes tool discovery is unavailable." }
    }

    func linkAnotherDevice() async {
        do { invitation = try await client?.invite() }
        catch { message = error.localizedDescription }
    }

    func selectDelivery(mode: String? = nil, deviceID: String? = nil) async {
        guard let client, let identity, let credential else { return }
        do {
            self.identity = try await client.preferences(mode: mode ?? identity.reply_mode,
                deviceID: deviceID ?? identity.preferred_device_id ?? credential.deviceID)
            if self.identity?.reply_mode != "spoken" || self.identity?.preferred_device_id != credential.deviceID {
                await setAvailable(false)
            }
            await refresh()
        } catch { message = error.localizedDescription }
    }

    func revokeLinked(_ device: LinkedDevice) async {
        if device.id == credential?.deviceID { await revoke(); return }
        do { try await client?.revokeDevice(device.id); await refresh() }
        catch { message = "Could not confirm device revocation." }
    }

    func interruptAudio() {
        audio.stopPlayback(); policy.interrupted(); ptt.finishReceiving()
        if audio.recording {
            audio.finishCapture(systemOwnsSession: ptt.joined)
            if ptt.joined { ptt.stopTransmitting() }
            message = "Recording interrupted. Your audio is saved; tap Retry saved recording."
        }
        capturePending = false
    }

    func respond(task: AgentTask, control: AgentControl, answer: String? = nil, choice: String? = nil) async {
        guard let client else { return }
        do {
            try await client.control(taskID: task.id, control: control, answer: answer, choice: choice)
            message = "Response sent to Hermes."
            await refresh()
        } catch { message = error.localizedDescription; await refresh() }
    }

    func prepareReply(task: AgentTask, control: AgentControl) {
        guard pendingMemo == nil else { message = "Confirm the pending submission before replying to another task."; return }
        guard !audio.hasSavedRecording, draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Recover or discard your existing memo before starting this reply."; return
        }
        replyContext = ClarificationReply(taskID: task.id, control: control)
        selectedTask = nil
        message = "Your next memo answers this question: \(control.label)"
    }

    func discardRecording() {
        guard !hasPendingSubmission, !audio.recording, !audio.processing, !busy else { return }
        audio.discardMemo()
        draft = ""
        message = "Unsent recording discarded."
    }

    func clearReply() {
        guard !hasPendingSubmission, !audio.recording, !audio.processing, !busy else { return }
        replyContext = nil
        audio.discardMemo()
        draft = ""
        message = "Ready for a new task."
    }

    func stop(_ task: AgentTask) async {
        do { try await client?.stop(task.id); message = "Stop requested. Waiting for Hermes to confirm."; await refresh() }
        catch { message = error.localizedDescription }
    }

    func revoke() async {
        do {
            await setAvailable(false)
            try await client?.revoke()
            CredentialStore.remove(); credential = nil; tasks = []; events = []
            pendingMemo = nil; saveMemo(); audio.discardMemo()
            replyContext = nil; draft = ""
            policy = DeliveryPolicy(available: false)
            UserDefaults.standard.removeObject(forKey: "capa.played")
            UserDefaults.standard.removeObject(forKey: "capa.playedTokens")
            playedTokens = [:]; identity = nil; linkedDevices = []; connections = nil; invitation = nil
        } catch { message = "Revocation is not confirmed. Reconnect or revoke this device on the Hermes host." }
    }
}
