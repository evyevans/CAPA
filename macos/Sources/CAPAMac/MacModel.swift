import AppKit
import SwiftUI
import UserNotifications
import CapaCore
import CryptoKit

struct SavedNotificationReply: Codable, Identifiable {
    let id: String
    let deviceID: String
    let taskID: String
    let answer: String
    var memo: PendingMemo?
    let controlID: String?
    let generation: Int?
}

@MainActor
final class MacModel: ObservableObject {
    static let shared = MacModel()
    @Published private(set) var credential: Credential?
    @Published var tasks: [AgentTask] = []
    @Published var events: [AgentEvent] = []
    @Published var identity: WorkspaceIdentity?
    @Published var devices: [LinkedDevice] = []
    @Published var inventory: ConnectionInventory?
    @Published var selectedTask: AgentTask?
    @Published var invitation: DeviceInvitation?
    @Published var message = ""
    @Published var busy = false
    @Published var recordingIssue: String?
    @Published private(set) var savedNotificationReplies: [SavedNotificationReply] =
        (UserDefaults.standard.data(forKey: "capa.mac.notificationReplies").flatMap {
            try? JSONDecoder().decode([SavedNotificationReply].self, from: $0)
        }) ?? []
    private var sendingNotificationReplies = Set<String>()
    @Published var notificationState = "Checking…"
    private var lastNotificationStatusCheck = Date.distantPast
    @Published var draft = UserDefaults.standard.string(forKey: "capa.mac.draft") ?? "" {
        didSet { UserDefaults.standard.set(draft, forKey: "capa.mac.draft") }
    }
    @Published var showBar = UserDefaults.standard.object(forKey: "capa.mac.showBar") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showBar, forKey: "capa.mac.showBar"); onBarPosition?() }
    }
    @Published var spokenAcknowledgment = UserDefaults.standard.bool(forKey: "capa.mac.spokenAck") {
        didSet { UserDefaults.standard.set(spokenAcknowledgment, forKey: "capa.mac.spokenAck") }
    }
    @Published private(set) var reply: ClarificationReply? {
        didSet { save(reply, key: "capa.mac.reply") }
    }
    let audio = MacAudio()
    var onBarPosition: (() -> Void)?
    var onResetBarPosition: (() -> Void)?
    private var hostSpeech = false
    private var checkingCapabilities = false
    private var lastCapabilityCheck = Date.distantPast
    private var pending: PendingMemo? {
        didSet { save(pending, key: "capa.mac.pending") }
    }
    private var interruptedSpeech = Set(UserDefaults.standard.stringArray(forKey: "capa.mac.interruptedSpeech") ?? [])
    private var received = Set(UserDefaults.standard.stringArray(forKey: "capa.mac.notified") ?? [])
    private var played = UserDefaults.standard.dictionary(forKey: "capa.mac.played") as? [String: String] ?? [:]
    private var poller: Task<Void, Never>?
    private var restoringConnection = false
    private var polling = false
    private var receiving = false
    private var playingEventID: String?
    var client: BridgeClient? { credential.map(BridgeClient.init) }
    var hasPending: Bool { pending != nil }
    var status: String {
        if audio.preparing { return "Preparing microphone" }
        if audio.recording { return "Listening · click to send" }
        if audio.processing { return "Transcribing…" }
        if busy { return "Sending to Hermes…" }
        if audio.speaking { return "Speaking · click to stop" }
        return credential == nil ? "Connect Hermes" : "Speak to Hermes"
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "capa.mac.pending") {
            pending = try? JSONDecoder().decode(PendingMemo.self, from: data)
            draft = pending?.text ?? draft
        }
        if let data = UserDefaults.standard.data(forKey: "capa.mac.reply") {
            reply = try? JSONDecoder().decode(ClarificationReply.self, from: data)
        }
        audio.onCaptureFailure = { [weak self] error in self?.recordingIssue = error; self?.message = error }
        audio.onLimit = { [weak self] in Task { await self?.toggleRecording() } }
    }
    private func save<T: Encodable>(_ value: T?, key: String) {
        if let value, let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
    func start() {
        guard poller == nil else { return }
        Task {
            await refreshNotificationStatus(force: true)
            await restoreConnection(allowInteraction: false)
        }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
    func restoreConnection(allowInteraction: Bool = true) async {
        guard !busy, !restoringConnection else { return }
        restoringConnection = true; defer { restoringConnection = false }
        if allowInteraction {
            NSApp.activate(ignoringOtherApps: true)
            message = "Waiting for saved connection access. Allow CAPA if macOS shows a Keychain prompt."
        }
        WidgetInputTrace.record("connection restore began interactive=\(allowInteraction)")
        let saved = await Task.detached(priority: .userInitiated) {
            CredentialStore.load(allowInteraction: allowInteraction)
        }.value
        guard let saved else {
            message = "Saved connection needs permission. Click Restore saved connection and allow CAPA's Keychain prompt, or use a fresh connection code."
            WidgetInputTrace.record("connection restore unavailable")
            return
        }
        credential = saved; onBarPosition?()
        await refresh()
        WidgetInputTrace.record("connection restored")
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined { await enableNotifications() }
    }
    func pair(address: String, code: String) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let value = try await BridgeClient.pair(url: address, code: code, name: Host.current().localizedName ?? "My Mac", platform: "macos")
            try await Task.detached(priority: .userInitiated) { try CredentialStore.save(value) }.value
            credential = value
            message = "Connected. Your work follows you across linked devices."
            onBarPosition?()
            await refresh()
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .notDetermined { await enableNotifications() }
        } catch { message = error.localizedDescription }
    }
    func refresh() async {
        guard !polling, let client else { return }
        polling = true; defer { polling = false }
        do {
            tasks = try await client.tasks()
            events = try await client.events()
            identity = try await client.identity()
            devices = try await client.linkedDevices()
            await refreshNotificationStatus()
            // A separate, throttled check cannot delay delivery of persisted results.
            refreshCapabilities(client)
            try? await client.device(["available": identity?.reply_mode == "spoken" && identity?.preferred_device_id == credential?.deviceID])
            for event in events {
                if let token = played[event.id] { try? await client.acknowledge(event.id, token: token) }
            }
            events.removeAll { played[$0.id] != nil }
            if let selectedTask { self.selectedTask = tasks.first { $0.id == selectedTask.id } }
            for event in events where event.deliveryDeviceID == credential?.deviceID && !received.contains(event.id) {
                if playingEventID == event.id { continue }
                let speakReply = identity?.reply_mode == "spoken" &&
                    identity?.preferred_device_id == credential?.deviceID && !event.requiresReview &&
                    !interruptedSpeech.contains(event.id) && !audio.recording && !audio.processing &&
                    !busy && !receiving && !audio.speaking
                // Keep a visible, actionable update even when speech is selected.
                await notify(event)
                if speakReply {
                    await read(event, manual: false)
                    break
                }
            }
        } catch { message = "Connection unavailable. Your draft and accepted work are retained." }
    }
    private func refreshCapabilities(_ client: BridgeClient) {
        guard !checkingCapabilities, Date().timeIntervalSince(lastCapabilityCheck) > 60 else { return }
        checkingCapabilities = true; lastCapabilityCheck = Date()
        Task { [weak self] in
            guard let self else { return }
            defer { self.checkingCapabilities = false }
            if let capabilities: BridgeCapabilities = try? await client.call("v1/capabilities"),
               self.credential?.deviceID == client.credential.deviceID {
                self.hostSpeech = capabilities.host_speech
            }
        }
    }
    func loadConnections() async {
        do { inventory = try await client?.connections() }
        catch { inventory = nil; message = "Hermes tool discovery is unavailable." }
    }
    func linkDevice() async {
        do { invitation = try await client?.invite() }
        catch { message = error.localizedDescription }
    }
    func preferences(mode: String? = nil, deviceID: String? = nil) async {
        guard let client, let identity else { return }
        do {
            self.identity = try await client.preferences(mode: mode ?? identity.reply_mode,
                deviceID: deviceID ?? identity.preferred_device_id ?? credential!.deviceID)
            if self.identity?.reply_mode != "spoken" || self.identity?.preferred_device_id != credential?.deviceID {
                audio.stopSpeaking()
            }
            await refresh()
        } catch { message = error.localizedDescription }
    }
    func revoke(_ device: LinkedDevice) async {
        do {
            try await client?.revokeDevice(device.id)
            if device.id == credential?.deviceID { await clearCredentials() }
            else { await refresh() }
        } catch { message = "Revocation was not confirmed. Reconnect before retrying." }
    }
    private func clearCredentials() async {
        audio.stopSpeaking(); audio.stop(); audio.discard()
        await Task.detached { CredentialStore.remove() }.value
        credential = nil; identity = nil; devices = []; tasks = []; events = []
        inventory = nil; invitation = nil; pending = nil; reply = nil; draft = ""
        received = []; played = [:]; interruptedSpeech = []
        UserDefaults.standard.removeObject(forKey: "capa.mac.interruptedSpeech")
        UserDefaults.standard.removeObject(forKey: "capa.mac.notified")
        UserDefaults.standard.removeObject(forKey: "capa.mac.played")
        onBarPosition?()
    }
    func toggleRecording() async {
        WidgetInputTrace.record("record requested paired=\(client != nil) busy=\(busy) saved=\(audio.saved) recording=\(audio.recording)")
        guard client != nil, !busy, !audio.processing, !audio.preparing else { return }
        recordingIssue = nil
        if audio.speaking { audio.stopSpeaking(); return }
        if audio.recording { audio.stop(); await recoverMemo(); return }
        guard pending == nil, draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Send or clear your current memo first."; return
        }
        do { try await audio.start(); WidgetInputTrace.record("record started=\(audio.recording)") }
        catch { WidgetInputTrace.record("record start error"); recordingIssue = error.localizedDescription; message = error.localizedDescription }
    }
    func recordFromWidget() async {
        if audio.saved && !audio.recording && !audio.processing && !audio.preparing {
            await keepMemoAndRecord()
        } else { await toggleRecording() }
    }
    func keepMemoAndRecord() async {
        guard audio.saved, pending == nil, draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !busy, !audio.recording, !audio.processing, !audio.preparing else { return }
        do {
            try audio.archiveSavedMemo()
            audio.stopSpeaking()
            message = "Previous audio kept in Archived Recordings."
            await toggleRecording()
        } catch { recordingIssue = error.localizedDescription; message = error.localizedDescription }
    }
    func recoverMemo() async {
        guard let client, pending == nil else { return }
        recordingIssue = nil
        do {
            draft = try await audio.transcribe(client: client, hostSpeech: hostSpeech)
            await sendDraft()
        } catch { recordingIssue = error.localizedDescription; message = error.localizedDescription }
    }
    func discardMemo() {
        guard pending == nil, !audio.recording, !audio.processing, !busy else { return }
        audio.discard(); draft = ""; reply = nil; recordingIssue = nil; message = "Unsent memo discarded."
    }
    func sendDraft() async {
        guard !busy, !audio.recording, !audio.processing, !audio.preparing, let client else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pending != nil || !text.isEmpty else { return }
        busy = true; defer { busy = false }
        if let reply {
            do {
                try await client.control(taskID: reply.taskID, control: reply.control, answer: text)
                self.reply = nil; draft = ""; audio.discard(); message = "Answer sent to Hermes."
            } catch { message = "Answer unconfirmed. Review the same task before retrying; your memo is saved." }
            await refresh(); return
        }
        if pending == nil { pending = PendingMemo(text: text) }
        pending?.markSending()
        do {
            let task = try await client.submit(pending!)
            pending?.accept(runID: task.runID)
            if task.runID != nil {
                pending = nil; draft = ""; audio.discard(); recordingIssue = nil; message = "Received by Hermes. You can keep working."
                if spokenAcknowledgment { audio.speak("Received by Hermes. I'll notify you when there's an update.") { _ in } }
            } else if task.terminal {
                pending = nil; message = "Hermes did not confirm acceptance. Review the task before sending again."
            } else { message = "Acceptance unconfirmed. Retry checks the same request." }
        } catch { pending?.markUnconfirmed(); message = "Connection interrupted. Retry uses your saved request ID." }
        await refresh()
    }
    func prepareReply(task: AgentTask, control: AgentControl) {
        guard pending == nil, !audio.saved, draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Resolve your current memo before starting a reply."; return
        }
        reply = ClarificationReply(taskID: task.id, control: control)
        message = "Your next memo answers: \(control.label)"
    }
    func control(task: AgentTask, control: AgentControl, answer: String? = nil, choice: String? = nil) async {
        do { try await client?.control(taskID: task.id, control: control, answer: answer, choice: choice); await refresh() }
        catch { message = error.localizedDescription; await refresh() }
    }
    func stop(_ task: AgentTask) async {
        do { try await client?.stop(task.id); message = "Stop requested; waiting for Hermes."; await refresh() }
        catch { message = error.localizedDescription }
    }
    func read(_ event: AgentEvent, manual: Bool = true) async {
        guard !receiving, !audio.speaking, !audio.recording, !audio.processing, let client else { return }
        receiving = true; playingEventID = event.id
        let token = UUID().uuidString
        do {
            let data = hostSpeech ? try? await client.audio(event.id) : nil
            if !manual {
                let current = try await client.identity()
                guard current.reply_mode == "spoken", current.preferred_device_id == credential?.deviceID else {
                    receiving = false; playingEventID = nil; return
                }
            }
            guard !audio.recording, !audio.processing, !audio.speaking else { receiving = false; playingEventID = nil; return }
            try await client.claim(event.id, token: token, manual: manual)
            guard !audio.recording, !audio.processing, !audio.speaking else { receiving = false; playingEventID = nil; return }
            audio.speak(event.announcement, audio: data) { [weak self] success in
                guard let self else { return }
                self.receiving = false; self.playingEventID = nil
                if !success {
                    self.interruptedSpeech.insert(event.id)
                    UserDefaults.standard.set(Array(self.interruptedSpeech), forKey: "capa.mac.interruptedSpeech")
                    self.message = "Playback stopped. The full result is saved in CAPA."
                    Task { await self.notify(event) }
                }
                if success {
                    self.interruptedSpeech.remove(event.id)
                    UserDefaults.standard.set(Array(self.interruptedSpeech), forKey: "capa.mac.interruptedSpeech")
                    self.played[event.id] = token
                    UserDefaults.standard.set(self.played, forKey: "capa.mac.played")
                    Task { try? await client.acknowledge(event.id, token: token); await self.refresh() }
                }
            }
        } catch { receiving = false; playingEventID = nil; message = error.localizedDescription }
    }
    func refreshNotificationStatus(force: Bool = false) async {
        guard force || Date().timeIntervalSince(lastNotificationStatusCheck) >= 30 else { return }
        lastNotificationStatusCheck = Date()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized:
            if let deviceID = credential?.deviceID, let identity {
                notificationState = identity.preferred_device_id == deviceID
                    ? "Allowed · this Mac selected"
                    : "Allowed · updates go to another device"
            } else {
                notificationState = credential == nil ? "Allowed · connect Hermes to select a device" : "Allowed · checking delivery device"
            }
            if settings.alertSetting == .disabled || settings.alertStyle == .none {
                notificationState += " · banners off in macOS Settings"
            }
        case .provisional:
            notificationState = "Allowed quietly · check macOS alert settings"
        case .denied:
            notificationState = "Off in macOS Settings"
        case .notDetermined:
            notificationState = "Permission not requested"
        @unknown default:
            notificationState = "Permission status unavailable"
        }
    }
    func enableNotifications() async {
        do {
            let result = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            notificationState = result ? "Allowed" : "Off in macOS Settings"
            if result, let deviceID = credential?.deviceID {
                await preferences(mode: "notifications", deviceID: deviceID)
            }
            await refreshNotificationStatus(force: true)
            if result {
                message = identity?.preferred_device_id == credential?.deviceID && identity?.reply_mode == "notifications"
                    ? "Notifications enabled on this Mac. Replies appear in the notification’s options."
                    : "macOS notifications are allowed. Select this Mac in Devices to receive Hermes updates."
            } else { message = "Notifications are off. Results stay in CAPA." }
            await refresh()
        } catch { message = error.localizedDescription }
    }
    func testNotification() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            await refreshNotificationStatus(force: true)
            message = settings.authorizationStatus == .denied
                ? "Allow CAPA alerts in System Settings → Notifications, then try again."
                : "Enable notifications on this Mac first."
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "CAPA notifications are ready"
        content.body = "You can keep working in another app. New Hermes replies will appear here."
        content.categoryIdentifier = "CAPA_REVIEW"
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            message = "Test notification queued. Focus and macOS alert settings control whether a banner appears."
        } catch { message = "Could not queue the test notification: \(error.localizedDescription)" }
    }
    private func saveNotificationReplies() {
        if let data = try? JSONEncoder().encode(savedNotificationReplies) {
            UserDefaults.standard.set(data, forKey: "capa.mac.notificationReplies")
        }
    }
    func replyFromNotification(eventID: String, taskID: String, text: String, originatingDeviceID: String?, controlID: String?, generation: Int?) async -> Bool {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return true }
        // The same OS response must reuse the same admission identity after a retry.
        let key = eventID + ":" + SHA256.hash(data: Data(answer.utf8)).map { String(format: "%02x", $0) }.joined()
        let sent = UserDefaults.standard.stringArray(forKey: "capa.mac.notificationRepliesSent") ?? []
        if sent.contains(key) { return true }
        if !savedNotificationReplies.contains(where: { $0.id == key }) {
            let deviceID = originatingDeviceID ?? credential?.deviceID ?? "unpaired"
            savedNotificationReplies.append(SavedNotificationReply(id: key, deviceID: deviceID, taskID: taskID, answer: answer, memo: nil, controlID: controlID, generation: generation))
            saveNotificationReplies()
        }
        return await retryNotificationReply(key)
    }
    func retryNotificationReply(_ id: String) async -> Bool {
        guard let item = savedNotificationReplies.first(where: { $0.id == id }),
              let client, credential?.deviceID == item.deviceID, !sendingNotificationReplies.contains(id) else { return false }
        sendingNotificationReplies.insert(id)
        defer { sendingNotificationReplies.remove(id) }
        do {
            let task: AgentTask = try await client.call("v1/tasks/\(item.taskID)")
            if let controlID = item.controlID {
                guard let control = task.controls.first(where: { $0.id == controlID && $0.executionGeneration == item.generation && $0.isClarification }) else {
                    message = "Saved reply needs review: the question has changed."; return false
                }
                try await client.control(taskID: item.taskID, control: control, answer: item.answer)
            } else {
                guard task.controls.isEmpty, task.terminal else {
                    message = "Saved reply needs review: the task is still running or needs approval."; return false
                }
                let memo = item.memo ?? PendingMemo(text: "Follow-up to my request: \(task.text)\nHermes replied: \(task.output)\nMy reply: \(item.answer)")
                if let index = savedNotificationReplies.firstIndex(where: { $0.id == id }) {
                    savedNotificationReplies[index].memo = memo; saveNotificationReplies()
                }
                let accepted = try await client.submit(memo)
                guard accepted.runID?.isEmpty == false else {
                    message = "Hermes has not confirmed this reply. It remains saved; Retry checks the same request."; await refresh(); return false
                }
            }
            var sent = UserDefaults.standard.stringArray(forKey: "capa.mac.notificationRepliesSent") ?? []
            sent.append(id); UserDefaults.standard.set(Array(sent.suffix(200)), forKey: "capa.mac.notificationRepliesSent")
            savedNotificationReplies.removeAll { $0.id == id }; saveNotificationReplies()
            message = "Reply sent to Hermes."; await refresh(); return true
        } catch {
            message = "Reply delivery is unconfirmed. It is saved in History; Retry reuses the same request."; return false
        }
    }
    private func notify(_ event: AgentEvent) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            await refreshNotificationStatus(force: true)
            return
        }
        await refreshNotificationStatus(force: true)
        let content = UNMutableNotificationContent()
        content.title = event.kind == "approval" ? "Hermes needs approval" : event.kind == "clarification" ? "Hermes has a question" : "Hermes replied"
        content.body = String((event.text.isEmpty ? event.announcement : event.text).prefix(1000))
        content.categoryIdentifier = event.requiresReview ? "CAPA_REVIEW" : "CAPA_UPDATE"
        content.threadIdentifier = event.taskID
        content.sound = .default
        content.userInfo = ["task_id": event.taskID, "event_id": event.id, "device_id": credential?.deviceID ?? ""]
        // Events currently lack an immutable control identity. Keep formal questions
        // review-only rather than attaching a newer task control to an older event.
        do {
            try await center.add(UNNotificationRequest(identifier: event.id, content: content, trigger: nil))
            received.insert(event.id); UserDefaults.standard.set(Array(received), forKey: "capa.mac.notified")
        } catch { message = "Notifications unavailable. Your result is saved in CAPA." }
    }
}
