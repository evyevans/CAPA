import SwiftUI
import CapaCore

private let gold = Color(red: 0.75, green: 0.66, blue: 0.48)

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var audio: VoiceAudio
    @ObservedObject var ptt: PTTController
    @Environment(\.scenePhase) private var phase
    @State private var settings = false
    @State private var discardRecording = false
    @State private var clearReply = false

    var body: some View {
        NavigationStack {
            Group {
                if model.credential == nil { PairingView(model: model) }
                else { home }
            }
            .background(Color(red: 0.025, green: 0.025, blue: 0.035))
            .tint(gold)
            .navigationTitle("CAPA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.credential != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "slider.horizontal.3") { settings = true }
                    }
                }
            }
            .sheet(isPresented: $settings) { SettingsView(model: model, ptt: ptt) }
            .sheet(item: $model.selectedTask) { task in TaskView(model: model, task: task) }
            .confirmationDialog("Discard the unsent recording?", isPresented: $discardRecording) {
                Button("Discard recording", role: .destructive) { model.discardRecording() }
            }
            .confirmationDialog("Return to a new task and discard this unsent reply?", isPresented: $clearReply) {
                Button("Discard reply", role: .destructive) { model.clearReply() }
            }
        }
        .task {
            while !Task.isCancelled {
                if phase == .active, model.credential != nil { await model.refresh() }
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private var home: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 8) {
                    Circle().fill(model.available && ptt.joined ? Color.green : Color.gray).frame(width: 6, height: 6)
                    Text(model.available ? ptt.status : "Incoming voice off")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 16)
                Text("Give it work.\nGo about your day.")
                    .font(.system(size: 31, weight: .light, design: .rounded)).multilineTextAlignment(.center)
                Button {
                    Task { await model.toggleRecording() }
                } label: {
                    ZStack {
                        Circle().fill(gold.opacity(0.06)).frame(width: 190, height: 190)
                        Circle().stroke(gold.opacity(audio.recording || audio.speaking ? 0.8 : 0.25), lineWidth: 1)
                            .frame(width: 164, height: 164)
                        Image(systemName: audio.recording ? "stop.fill" : audio.speaking ? "speaker.wave.2.fill" : "waveform")
                            .font(.system(size: 44, weight: .ultraLight))
                    }.foregroundStyle(gold)
                }
                .accessibilityLabel(audio.recording ? "Stop recording and send memo" : audio.speaking ? "Stop speaking" : "Record a request to Hermes")
                .disabled(model.busy || audio.processing)
                Text(audio.recording ? "Listening · tap to send" : audio.processing ? "Transcribing your memo…" :
                        model.capturePending ? "Preparing microphone…" : audio.speaking ? "Hermes is speaking · tap to stop" : "Tap to speak")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !model.message.isEmpty {
                    Text(model.message).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).accessibilityAddTraits(.updatesFrequently)
                }
                if let reply = model.replyContext {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Replying to Hermes").font(.caption).foregroundStyle(gold)
                        Text(reply.control.label).font(.subheadline)
                        Button("Return to a new task") { clearReply = true }
                            .font(.caption)
                    }
                }
                if !model.pushConfigured {
                    Label("Background delivery needs Apple push setup on your bridge. Tasks still work here.", systemImage: "bell.slash")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !model.events.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Updates waiting for you").font(.headline)
                        ForEach(model.events) { event in
                            HStack {
                                Button { Task { await model.receive(event.id, manual: true) } } label: {
                                    Label(event.requiresReview ? "Hermes needs you" : "Hear the brief", systemImage: "play.circle")
                                }
                                Spacer()
                                Button("Open") { model.selectedTask = model.tasks.first { $0.id == event.taskID } }
                            }.padding().background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                DisclosureGroup(model.hasPendingSubmission ? "Submission awaiting confirmation" : "Type a request") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("What should Hermes do?", text: $model.draft, axis: .vertical)
                            .lineLimit(3...8).disabled(model.hasPendingSubmission)
                        Button(model.hasPendingSubmission ? "Check / retry the same request" : model.replyContext != nil ? "Answer this question" : "Send to Hermes") {
                            Task { await model.sendDraft() }
                        }.disabled(model.busy)
                    }.padding(.top, 12)
                }.font(.subheadline)
                if audio.hasSavedRecording, !audio.recording {
                    Button("Retry saved recording") { Task { await model.transcribeMemo() } }
                        .font(.footnote).disabled(model.hasPendingSubmission || audio.processing)
                    Button("Discard unsent recording", role: .destructive) { discardRecording = true }
                        .font(.footnote).disabled(model.hasPendingSubmission || audio.processing)
                }
                if !model.tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your work").font(.headline)
                        ForEach(model.tasks) { task in
                            Button { model.selectedTask = task } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(task.text).lineLimit(2).foregroundStyle(.primary)
                                    Text(task.status.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption).foregroundStyle(gold)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(24)
        }.refreshable { await model.refresh(); await model.syncDevice() }
    }
}

private struct PairingView: View {
    @ObservedObject var model: AppModel
    @State private var address = ""
    @State private var code = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "waveform").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(gold)
            Text("Your agent.\nWithin reach.").font(.system(size: 36, weight: .light, design: .rounded))
            Text("Connect CAPA to the bridge beside your Hermes installation. Your agent, tools, and model stay there.")
                .font(.subheadline).foregroundStyle(.secondary)
            TextField("https://your-private-bridge", text: $address)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            SecureField("One-use pairing code", text: $code).textInputAutocapitalization(.never)
                .autocorrectionDisabled().textFieldStyle(.roundedBorder)
            Button { Task { await model.pair(url: address, code: code) } } label: {
                Text(model.busy ? "Connecting…" : "Connect Hermes").frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).disabled(model.busy || code.isEmpty || address.isEmpty)
            Text(model.message).font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding(28)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ptt: PTTController
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRevoke = false
    @State private var revokeLinkedDevice: LinkedDevice?
    var body: some View {
        NavigationStack {
            Form {
                Section("Reply preferences") {
                    Picker("Task updates", selection: Binding(get: { model.identity?.reply_mode ?? "notifications" }, set: { mode in
                        Task { await model.selectDelivery(mode: mode) }
                    })) {
                        Text("Notifications").tag("notifications")
                        Text("Spoken on selected device").tag("spoken")
                    }
                    Toggle("Speak after a request is accepted", isOn: $model.spokenAcknowledgment)
                    Text("Notifications open the full result. Read aloud is available when you want it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Incoming voice on this iPhone") {
                    Toggle("Let Hermes speak first", isOn: Binding(get: { model.available }, set: { value in
                        Task { await model.setAvailable(value) }
                    }))
                    Text("Stays on until you turn it off or leave the system voice channel. The microphone records only when you choose to reply.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(ptt.status).font(.caption)
                    Button("Enable completion notifications") { Task { await model.enableNotifications() } }
                }
                Section("Connections") {
                    NavigationLink("Tools available to Hermes") { ConnectionsView(model: model) }
                }
                Section("Linked devices") {
                    Text(model.identity?.name ?? "My Hermes").font(.headline)
                    Text("Linked devices can read and control the same tasks. Link only devices you trust.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Link another device") { Task { await model.linkAnotherDevice() } }
                    if let invitation = model.invitation {
                        Text(invitation.code).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Text("Use with this bridge address. Expires five minutes after creation; usable once.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(model.linkedDevices) { device in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(device.name).font(.headline)
                            Text("\(device.platform)\(device.id == model.credential?.deviceID ? " · This device" : "")\(device.revoked != 0 ? " · Revoked" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                            if device.revoked == 0 {
                                if model.identity?.preferred_device_id == device.id { Text("Receives updates").font(.caption) }
                                else { Button("Send updates here") { Task { await model.selectDelivery(deviceID: device.id) } } }
                                if device.id != model.credential?.deviceID {
                                    Button("Revoke access", role: .destructive) { revokeLinkedDevice = device }
                                }
                            }
                        }
                    }
                }
                Section("Your connection") {
                    Text(model.credential?.baseURL.absoluteString ?? "Not paired").font(.footnote)
                    LabeledContent("Apple push", value: model.pushConfigured ? "Configured" : "Not configured")
                    LabeledContent("Host speech", value: model.hostSpeech ? "Enabled" : "Device speech")
                    Text("Spoken updates may be heard by people nearby. Calls, network outages, and iOS session state can interrupt delivery; results remain in CAPA.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Disconnect and revoke this iPhone", role: .destructive) { confirmRevoke = true }
                }
                Text(model.message).font(.footnote)
            }.navigationTitle("CAPA settings")
                .toolbar { Button("Done") { dismiss() } }
                .confirmationDialog("Revoke linked device access?", isPresented: Binding(get: { revokeLinkedDevice != nil }, set: { if !$0 { revokeLinkedDevice = nil } })) {
                    if let device = revokeLinkedDevice {
                        Button("Revoke \(device.name)", role: .destructive) { Task { await model.revokeLinked(device) } }
                    }
                }
                .confirmationDialog("Revoke this iPhone? Hermes work already accepted keeps running.", isPresented: $confirmRevoke) {
                    Button("Revoke device", role: .destructive) { Task { await model.revoke(); if model.credential == nil { dismiss() } } }
                }
        }.tint(gold)
    }
}

private struct TaskView: View {
    @ObservedObject var model: AppModel
    let task: AgentTask
    @Environment(\.dismiss) private var dismiss
    @State private var answer = ""
    @State private var approval: AgentControl?
    private var current: AgentTask { model.tasks.first { $0.id == task.id } ?? task }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(current.text).font(.title3)
                    Text(current.status.replacingOccurrences(of: "_", with: " ").capitalized).foregroundStyle(gold)
                    ForEach(current.controls) { control in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(control.label).font(.headline).textSelection(.enabled)
                            if control.isClarification {
                                Button("Speak an answer", systemImage: "mic") {
                                    model.prepareReply(task: current, control: control)
                                    dismiss()
                                    Task { await model.toggleRecording() }
                                }
                                TextField("Your answer", text: $answer, axis: .vertical).textFieldStyle(.roundedBorder)
                                Button("Answer Hermes") {
                                    Task { await model.respond(task: current, control: control, answer: answer) }
                                }.disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            } else {
                                if let edit = control.editDescription {
                                    Text(edit).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                                }
                                Button("Review approval") { approval = control }
                            }
                        }.padding().background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if !current.output.isEmpty {
                        Text(.init(current.output)).textSelection(.enabled)
                    }
                    if !current.terminal {
                        Button("Ask Hermes to stop", role: .destructive) { Task { await model.stop(current) } }
                    }
                    Text(model.message).font(.footnote).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.navigationTitle("Task").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
                .refreshable { await model.refresh() }
                .confirmationDialog("Approve this exact action once?", isPresented: Binding(
                    get: { approval != nil }, set: { if !$0 { approval = nil } })) {
                    if let control = approval {
                        if control.canApproveOnce {
                            Button("Approve once") { Task { await model.respond(task: current, control: control, choice: "once") } }
                        }
                        if control.choices?.contains("deny") == true {
                            Button("Deny", role: .destructive) { Task { await model.respond(task: current, control: control, choice: "deny") } }
                        }
                    }
                } message: { Text(approval?.label ?? "") }
        }.tint(gold)
    }
}

private struct ConnectionsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        List {
            Section {
                Text("CAPA uses the tools already configured in your Hermes. Their accounts and permissions stay there.")
                    .foregroundStyle(.secondary)
                Button("Refresh connections") { Task { await model.loadConnections() } }
            }
            if let inventory = model.connections {
                Section { Text(inventory.message).font(.callout) }
                ForEach(inventory.toolsets) { connection in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(connection.label ?? connection.name).font(.headline)
                        Text(connection.status).font(.caption).foregroundStyle(gold)
                        if let detail = connection.description { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                        if let tools = connection.tools { Text(tools.joined(separator: ", ")).font(.caption).textSelection(.enabled) }
                    }
                }
                if !inventory.skills.isEmpty {
                    Section("Skills in Hermes") { ForEach(inventory.skills) { Text($0.name) } }
                }
            } else { Text("Discovery has not completed. No tool access is assumed.").font(.footnote) }
        }.navigationTitle("Connections").task { await model.loadConnections() }
    }
}
