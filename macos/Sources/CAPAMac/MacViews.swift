import SwiftUI
import CapaCore

let capaGold = Color(red: 0.75, green: 0.66, blue: 0.48)
let capaBackground = Color(red: 0.045, green: 0.045, blue: 0.055)

enum HubPage: String, CaseIterable, Identifiable {
    case tasks = "History", setup = "Setup", connections = "Connections", devices = "Devices", preferences = "Preferences"
    var id: Self { self }
    var icon: String {
        switch self {
        case .tasks: "waveform"
        case .setup: "checklist"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .devices: "laptopcomputer.and.iphone"
        case .preferences: "slider.horizontal.3"
        }
    }
}

struct MacHub: View {
    @ObservedObject var model: MacModel
    @ObservedObject var audio: MacAudio
    @State private var page: HubPage? = .tasks
    @State private var address = "http://127.0.0.1:8787"
    @State private var code = ""
    @State private var historySearch = ""
    @State private var confirmDiscard = false
    @State private var revokeDevice: LinkedDevice?

    var body: some View {
        Group {
            if model.credential == nil { pairing }
            else {
                NavigationSplitView {
                    VStack(alignment: .leading, spacing: 24) {
                        Label("CAPA", systemImage: "waveform").font(.title2.weight(.semibold)).foregroundStyle(capaGold)
                            .padding(.horizontal, 16).padding(.top, 20)
                        List(HubPage.allCases, selection: $page) { item in
                            Label(item.rawValue, systemImage: item.icon).tag(item)
                        }.listStyle(.sidebar)
                        Text(model.identity?.name ?? "My Hermes").font(.caption).foregroundStyle(.secondary).padding(16)
                    }.frame(minWidth: 180)
                } detail: {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Text(page?.rawValue ?? "Tasks").font(.largeTitle.weight(.light))
                            switch page ?? .tasks {
                            case .tasks: taskList
                            case .setup: setup
                            case .connections: connections
                            case .devices: devices
                            case .preferences: preferences
                            }
                            if !model.message.isEmpty { Text(model.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                        }.frame(maxWidth: 850, alignment: .leading).padding(32)
                    }.background(capaBackground)
                }
            }
        }
        .tint(capaGold).preferredColorScheme(.dark)
        .frame(minWidth: 780, minHeight: 570)
        .onChange(of: page) { _, value in if value == .connections { Task { await model.loadConnections() } } }
        .sheet(item: $model.selectedTask) { MacTaskDetails(model: model, task: $0) }
        .confirmationDialog("Discard the unsent memo?", isPresented: $confirmDiscard) {
            Button("Discard memo", role: .destructive) { model.discardMemo() }
        }
        .confirmationDialog("Revoke this device's access?", isPresented: Binding(get: { revokeDevice != nil }, set: { if !$0 { revokeDevice = nil } })) {
            if let device = revokeDevice { Button("Revoke \(device.name)", role: .destructive) { Task { await model.revoke(device) } } }
        }
    }

    private var pairing: some View {
        HStack(spacing: 64) {
            VStack(alignment: .leading, spacing: 24) {
                Label("CAPA", systemImage: "waveform").foregroundStyle(capaGold).font(.title2)
                Text("Say it.\nLet Hermes handle it.").font(.system(size: 42, weight: .light, design: .rounded))
                Text("One small control for your agent.\nYour tasks follow you between linked devices.")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                Text("Connect your Hermes").font(.title2)
                Text("Use a one-use connection code, or restore your saved connection. The local bridge address belongs in the field below; it is not a browser sign-in page.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Restore saved connection") { Task { await model.restoreConnection() } }
                    .disabled(model.busy)
                TextField("Bridge address", text: $address)
                SecureField("One-use connection code", text: $code)
                Button(model.busy ? "Connecting…" : "Connect") { Task { await model.pair(address: address, code: code) } }
                    .buttonStyle(.borderedProminent).disabled(model.busy || code.isEmpty || address.isEmpty)
                Text("No separate model subscription. Your configured Hermes providers still apply.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.message).font(.callout).foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder).frame(width: 310)
        }.padding(48).frame(maxWidth: .infinity, maxHeight: .infinity).background(capaBackground)
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your memos. Their results.").font(.title2.weight(.light))
                    Text("Click the waveform to record. Click again to transcribe and send.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.recordFromWidget() } } label: {
                    Label(audio.recording ? "Stop & send" : audio.speaking ? "Stop voice" : "Record", systemImage: audio.recording ? "stop.fill" : "mic")
                }.buttonStyle(.borderedProminent).disabled(model.busy || audio.processing)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            TextField("Search sent memos", text: $historySearch).textFieldStyle(.roundedBorder)
            if model.hasPending || !model.draft.isEmpty || audio.saved || model.reply != nil {
                DisclosureGroup("Unsent memo and recovery") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let reply = model.reply { Text("Answering: \(reply.control.label)") }
                        if !model.draft.isEmpty || model.reply != nil {
                            TextField("Review saved transcript or answer", text: $model.draft, axis: .vertical)
                                .lineLimit(2...6).disabled(model.hasPending)
                            Button(model.hasPending ? "Check the same request" : "Send saved memo") {
                                Task { await model.sendDraft() }
                            }.disabled(model.busy || audio.recording || audio.processing)
                        }
                        if audio.saved {
                            Button("Retry saved recording") { Task { await model.recoverMemo() } }
                                .disabled(model.hasPending || audio.processing || audio.recording)
                        }
                        Button("Discard unsent memo", role: .destructive) { confirmDiscard = true }
                            .disabled(model.hasPending || audio.recording || audio.processing || model.busy)
                    }.padding(.top, 8)
                }
            }
            ForEach(model.savedNotificationReplies.filter { $0.deviceID == model.credential?.deviceID }) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notification reply awaiting delivery").font(.headline)
                    Text(item.answer).textSelection(.enabled)
                    Button("Retry saved reply") { Task { _ = await model.retryNotificationReply(item.id) } }
                }.padding(18).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            }
            if model.tasks.isEmpty {
                ContentUnavailableView("Your first task starts here", systemImage: "waveform",
                                       description: Text("Ask Hermes for something useful. Accepted work and results will appear on all linked devices."))
            }
            ForEach(model.tasks.filter { historySearch.isEmpty || $0.text.localizedCaseInsensitiveContains(historySearch) || $0.output.localizedCaseInsensitiveContains(historySearch) }) { task in
                Button { model.selectedTask = task } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Date(timeIntervalSince1970: task.createdAt), style: .date).font(.caption).foregroundStyle(.secondary)
                            Text(Date(timeIntervalSince1970: task.createdAt), style: .time).font(.caption).foregroundStyle(.secondary)
                            Text(task.text).font(.body).foregroundStyle(.primary).lineLimit(3)
                            if !task.output.isEmpty { Text(task.output).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                            Text(task.status.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption).foregroundStyle(capaGold)
                        }
                        Spacer()
                        if !task.controls.isEmpty { Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(capaGold) }
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.padding(18).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
        }
    }

    private func promptCard(_ title: String, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(prompt).font(.callout).textSelection(.enabled)
            Button("Copy prompt") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prompt, forType: .string) }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }
    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect once. Speak whenever you need.").font(.title2.weight(.light))
            Text("1. Keep Hermes and the CAPA bridge running on your host. Your chat window can be closed. The host must stay awake and online.")
            Text("2. Pair using a one-use code. This Mac is already paired. Use Devices to link another device.")
            Text("3. Allow microphone and speech access when recording. Enable completion notifications in Preferences.")
            Text("4. Click the waveform, speak, then click again. CAPA transcribes and sends. History stores accepted memos and results.")
            promptCard("Check my Hermes connection", "Help me connect CAPA to my existing Hermes installation. Inspect the installed CAPA bridge documentation and my active Hermes profile. Check the authenticated Hermes API and CAPA bridge health without displaying secrets. Preserve my providers, tools and credentials. Explain missing configuration and exact changes before applying them. Keep services local by default. Verify a harmless reply-only request and show me how to obtain a one-use pairing code using the installed bridge. Do not invent commands or claim success before testing.")
            Text("A setup prompt helps configure services; pairing and API routing establish the actual connection.").foregroundStyle(.secondary)
            promptCard("Connect my iPhone", "Help me reach my existing CAPA bridge from my iPhone. Check that my Hermes host is awake and online. Guide me through a private Tailscale connection on both devices and trusted HTTPS using Tailscale Serve for the CAPA bridge at 127.0.0.1:8787. Keep the Hermes API private and preserve CAPA device authentication. Do not publish an unauthenticated service. Verify reachability from the phone, then help me pair with a fresh code from CAPA Devices. Explain that localhost on my phone refers to the phone. Do not claim background notifications work without testing push delivery.")
            Text("A VPS is optional. A private HTTPS connection can reach your home Mac while it is awake. An always-on host is needed when your Mac sleeps. iPhone background completion alerts need a separately verified push delivery path.").foregroundStyle(.secondary)
            Link("Hermes API documentation", destination: URL(string: "https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server/")!)
            Link("Tailscale Serve documentation", destination: URL(string: "https://tailscale.com/docs/features/tailscale-serve")!)
        }
    }
    private var connections: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Use what your agent already knows.").font(.title2.weight(.light))
            Text("CAPA routes requests to Hermes. Tool accounts and permissions are managed in that Hermes installation.")
                .foregroundStyle(.secondary)
            promptCard("Connect a tool", "Help me connect [tool name] to my existing Hermes agent for use through CAPA. Inspect my installed tools, skills and MCP support. Prefer an existing integration; otherwise check the provider’s official MCP or API documentation. Guide me through secure authorization with minimum permissions. Never ask me to paste secrets into chat. Verify a harmless read-only operation and report what is actually available. Do not send messages, publish content or change external records during setup.")
            Button("Refresh connections") { Task { await model.loadConnections() } }
            if let inventory = model.inventory {
                Text(inventory.message).font(.callout)
                ForEach(inventory.toolsets) { connection in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(connection.label ?? connection.name).font(.headline)
                        Text(connection.status).foregroundStyle(capaGold).font(.caption)
                        Button("Copy setup prompt") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("Help me connect \(connection.label ?? connection.name) to my existing Hermes agent for use through CAPA. Inspect the installed integration and official setup documentation. Guide me through secure authorization without exposing credentials. Verify a harmless read-only operation and explain missing capabilities. Do not perform external write actions during setup.", forType: .string)
                        }
                        if let description = connection.description { Text(description).font(.callout).foregroundStyle(.secondary) }
                        if let tools = connection.tools { Text(tools.joined(separator: ", ")).font(.caption).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                }
                if !inventory.skills.isEmpty {
                    Text("Skills in Hermes").font(.headline)
                    ForEach(inventory.skills) { skill in Text(skill.name).font(.callout) }
                }
            } else { Text("Refresh to discover your Hermes tools. No connection status is assumed.").foregroundStyle(.secondary) }
        }
    }

    private var devices: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("One workspace. Your devices.").font(.title2.weight(.light))
            Text("Link only devices you trust. Linked devices can read and control every task in this workspace.")
                .foregroundStyle(.secondary)
            Button("Link another device") { Task { await model.linkDevice() } }
            if let invitation = model.invitation {
                Text(invitation.code).font(.system(.title3, design: .monospaced)).textSelection(.enabled)
                Text("Use this code with the same bridge address. Expires five minutes after creation; usable once.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.devices) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(device.name).font(.headline)
                        Text("\(device.platform)\(device.id == model.credential?.deviceID ? " · This device" : "")\(device.revoked != 0 ? " · Revoked" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if device.revoked == 0 {
                        if model.identity?.preferred_device_id == device.id { Label("Receives updates", systemImage: "checkmark").font(.caption) }
                        else { Button("Send updates here") { Task { await model.preferences(deviceID: device.id) } } }
                        Button("Revoke", role: .destructive) { revokeDevice = device }
                    }
                }.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker("Task updates", selection: Binding(get: { model.identity?.reply_mode ?? "notifications" }, set: { mode in
                Task { await model.preferences(mode: mode) }
            })) {
                Text("Notifications").tag("notifications")
                Text("Speak on selected device").tag("spoken")
            }.pickerStyle(.segmented)
            Text("Hermes replies arrive as macOS notifications. Choose Speak on selected device to also hear replies aloud here while CAPA is running; banners remain available for follow-up.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Show archived recordings") {
                let directory = audio.url.deletingLastPathComponent().appendingPathComponent("Archived Recordings", isDirectory: true)
                NSWorkspace.shared.open(FileManager.default.fileExists(atPath: directory.path) ? directory : audio.url.deletingLastPathComponent())
            }
            Text("Speech: \(audio.speechLanguage)").font(.caption).foregroundStyle(.secondary)
            Text("Notifications: \(model.notificationState)").font(.caption).foregroundStyle(.secondary)
            Text("Enable notifications here to select this installation for updates. Expand a notification or use its Options menu to reply without opening CAPA. Approval requests always open the task for review. Notification previews follow your macOS settings.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open macOS notification settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            }
            Button("Enable notifications on this Mac") { Task { await model.enableNotifications() } }
            Button("Send test notification") { Task { await model.testNotification() } }
            Toggle("Speak an acknowledgment after acceptance", isOn: $model.spokenAcknowledgment)
            Toggle("Show floating bar", isOn: $model.showBar)
            Button("Reset widget position") { model.onResetBarPosition?() }
            Text("Drag the widget anywhere on your displays. Its position is saved between launches. Click the waveform to record, or the separate arrow to open CAPA.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Record shortcut: ⇧⌘R while CAPA is active. The floating bar and menu-bar control work while other apps are active.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct MacTaskDetails: View {
    @ObservedObject var model: MacModel
    let task: AgentTask
    @Environment(\.dismiss) private var dismiss
    @State private var answer = ""
    @State private var approval: AgentControl?
    private var current: AgentTask { model.tasks.first { $0.id == task.id } ?? task }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("Task").font(.title2); Spacer(); Button("Done") { dismiss() } }
                Text(current.text).font(.title3).textSelection(.enabled)
                Text(current.status.replacingOccurrences(of: "_", with: " ").capitalized).foregroundStyle(capaGold)
                ForEach(current.controls) { control in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(control.label).textSelection(.enabled)
                        if control.isClarification {
                            TextField("Your answer", text: $answer, axis: .vertical).textFieldStyle(.roundedBorder)
                            HStack {
                                Button("Send answer") { Task { await model.control(task: current, control: control, answer: answer) } }
                                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("Answer by voice") { model.prepareReply(task: current, control: control); dismiss() }
                            }
                        } else {
                            if let edit = control.editDescription { Text(edit).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                            Button("Review action") { approval = control }
                        }
                    }.padding().background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }
                if !current.output.isEmpty { Text(.init(current.output)).textSelection(.enabled) }
                ForEach(model.events.filter { $0.taskID == current.id }) { event in
                    Button("Read aloud", systemImage: "speaker.wave.2") { Task { await model.read(event) } }
                }
                if !current.terminal { Button("Request stop", role: .destructive) { Task { await model.stop(current) } } }
                Text(model.message).font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }.frame(minWidth: 600, minHeight: 450).tint(capaGold).preferredColorScheme(.dark)
            .confirmationDialog("Approve this exact action once?", isPresented: Binding(get: { approval != nil }, set: { if !$0 { approval = nil } })) {
                if let approval {
                    if approval.canApproveOnce { Button("Approve once") { Task { await model.control(task: current, control: approval, choice: "once") } } }
                    if approval.choices?.contains("deny") == true { Button("Deny", role: .destructive) { Task { await model.control(task: current, control: approval, choice: "deny") } } }
                }
            } message: { Text(approval?.label ?? "") }
    }
}

struct FloatingBarView: View {
    @ObservedObject var model: MacModel
    @ObservedObject var audio: MacAudio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recordHovered = false
    @State private var arrowHovered = false
    @State private var widgetHovered = false
    @State private var showRecovery = false
    @State private var confirmDiscard = false
    let openHub: () -> Void
    let moveWidget: (CGPoint, Bool) -> Void

    private var needsReview: Bool { audio.saved || model.hasPending || !model.draft.isEmpty || model.recordingIssue != nil }
    private var waiting: Bool { model.busy || audio.processing || audio.preparing }
    private var recordHelp: String {
        if audio.recording { return "Click to finish recording and send to Hermes" }
        if audio.preparing { return "Waiting for microphone permission" }
        if audio.processing { return "Transcribing your memo" }
        if audio.speaking { return "Click to stop read aloud" }
        if model.busy { return "Sending to Hermes" }
        if needsReview { return "Click to review your unsent memo" }
        return "Click to record a request for Hermes"
    }
    var body: some View {
        expandedControls.padding(6).preferredColorScheme(.dark)
    }
    private var expandedControls: some View {
        ZStack {
            VoiceWidgetFace(recording: audio.recording, speaking: audio.speaking, waiting: waiting,
                needsReview: needsReview, level: audio.voiceLevel, pitch: audio.voicePitch, reduceMotion: reduceMotion,
                hovered: widgetHovered, recordHovered: recordHovered)
            Button(action: activate) {
                Color.clear.frame(width: CompactWidgetGeometry.recordWidth, height: CompactWidgetGeometry.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { recordHovered = $0 }
            .accessibilityLabel(recordHelp)
            .help(recordHelp)
            Button {
                guard !audio.recording, !audio.preparing else { return }
                showRecovery = false; openHub()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(audio.recording || audio.preparing ? 0.22 : arrowHovered ? 1 : 0.65))
                    .frame(width: CompactWidgetGeometry.arrowWidth, height: CompactWidgetGeometry.arrowHeight)
                    .background(Capsule().fill(.white.opacity(arrowHovered && !audio.recording && !audio.preparing ? 0.14 : 0)))
                    .contentShape(Rectangle())
            }
            .onHover { arrowHovered = $0 }
            .buttonStyle(.plain).disabled(audio.recording || audio.preparing)
            .offset(x: CompactWidgetGeometry.arrowCenter - CompactWidgetGeometry.width / 2)
            .accessibilityLabel("Open CAPA")
            .help(audio.recording || audio.preparing ? "Finish recording before opening CAPA" : "Open CAPA")
        }
        .frame(width: CompactWidgetGeometry.width, height: CompactWidgetGeometry.height)
        .overlay {
            WidgetPointerSurface(click: { start, end in
                switch CompactWidgetGeometry.click(startX: start.x, startY: start.y, endX: end.x, endY: end.y, capturing: audio.recording || audio.preparing) {
                case .record: WidgetInputTrace.record("action record"); activate()
                case .openApp: WidgetInputTrace.record("action open"); showRecovery = false; openHub()
                case .none: WidgetInputTrace.record("action none")
                }
            }, move: moveWidget).accessibilityHidden(true)
        }
        .onHover { widgetHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: widgetHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: recordHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: arrowHovered)
        .contextMenu {
            Button("Open CAPA", action: openHub)
            if needsReview { Button("Review saved memo") { showRecovery = true } }
            Button("Reset widget position") { model.onResetBarPosition?() }
            Button("Hide widget") { model.showBar = false }
        }
        .onChange(of: model.recordingIssue) { _, error in if error != nil { showRecovery = true } }
        .popover(isPresented: $showRecovery, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your memo is safe").font(.headline)
                if let error = model.recordingIssue { Text(error).font(.callout).foregroundStyle(.orange) }
                if model.hasPending {
                    Text("Hermes acceptance is unconfirmed. Checking reuses the same request and does not duplicate the work.").font(.callout)
                    Button("Check the same request") { showRecovery = false; Task { await model.sendDraft() } }
                } else if audio.saved {
                    Text("An unsent recording is saved. Recover it before starting a new recording.").font(.callout)
                    Button("Retry saved recording") { showRecovery = false; Task { await model.recoverMemo() } }
                    if audio.saved && model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Keep memo and record a new one") {
                            showRecovery = false; Task { await model.keepMemoAndRecord() }
                        }
                    }
                    Button("Discard unsent memo", role: .destructive) { confirmDiscard = true }
                } else if !model.draft.isEmpty {
                    Text("A draft is waiting in CAPA. Review or send it before recording another memo.").font(.callout)
                    Button("Review draft") { showRecovery = false; openHub() }
                } else {
                    Button("Try recording again") { showRecovery = false; Task { await model.toggleRecording() } }
                }
                Divider()
                Button("Open CAPA") { showRecovery = false; openHub() }
            }.padding(20).frame(width: 300).disabled(waiting)
        }
        .confirmationDialog("Discard this unsent recording?", isPresented: $confirmDiscard) {
            Button("Discard recording", role: .destructive) { model.discardMemo(); showRecovery = false }
        }
    }
    private func activate() {
        guard model.credential != nil else {
            model.message = "Connect your Hermes in CAPA before recording."
            WidgetInputTrace.record("record needs connection")
            openHub(); return
        }
        guard !model.busy else { return }
        switch RecorderIntent.resolve(recording: audio.recording, preparing: audio.preparing,
            processing: audio.processing, speaking: audio.speaking, pending: model.hasPending,
            hasDraft: !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, saved: audio.saved) {
        case .reviewMemo:
            if audio.saved && !model.hasPending && model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { await model.recordFromWidget() }
            } else { showRecovery = true }
        case .wait: break
        default: Task { await model.toggleRecording() }
        }
    }
}
