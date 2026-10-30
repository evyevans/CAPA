import AppKit
import SwiftUI
import UserNotifications
import CapaCore

@main
struct CAPAMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
    @StateObject private var model = MacModel.shared
    var body: some Scene {
        WindowGroup("CAPA", id: "hub") {
            MacHub(model: model, audio: model.audio)
        }.defaultSize(width: 1040, height: 720)
        MenuBarExtra("CAPA", systemImage: "waveform") {
            Button("Record / send memo") { Task { await model.toggleRecording() } }.disabled(model.credential == nil)
            Button("Open CAPA") { delegate.openHub() }
            Button(model.showBar ? "Hide floating bar" : "Show floating bar") { model.showBar.toggle() }
            Divider()
            Button("Quit CAPA") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private var draggingWidget = false
    private var customOrigin: CGPoint? {
        get {
            guard let x = UserDefaults.standard.object(forKey: "capa.mac.widgetX") as? Double,
                  let y = UserDefaults.standard.object(forKey: "capa.mac.widgetY") as? Double,
                  x.isFinite, y.isFinite else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            UserDefaults.standard.set(newValue?.x, forKey: "capa.mac.widgetX")
            UserDefaults.standard.set(newValue?.y, forKey: "capa.mac.widgetY")
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        let followUp = UNTextInputNotificationAction(identifier: "CAPA_REPLY", title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Reply to Hermes")
        let review = UNNotificationAction(identifier: "CAPA_OPEN", title: "Review in CAPA", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "CAPA_UPDATE", actions: [followUp, review], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "CAPA_REVIEW", actions: [review], intentIdentifiers: [], options: [])
        ])
        let model = MacModel.shared
        model.onBarPosition = { [weak self] in self?.positionBar() }
        model.onResetBarPosition = { [weak self] in self?.customOrigin = nil; self?.positionBar() }
        WidgetInputTrace.record("launch paired=\(model.credential != nil)")
        model.start()
        positionBar()
        if model.credential != nil {
            Task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                if settings.authorizationStatus == .notDetermined { await model.enableNotifications() }
            }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { _ in
                Task { @MainActor in
                    model.audio.stopSpeaking()
                    if model.audio.recording { model.audio.stop(); model.message = "Mac went to sleep. Your recording is saved." }
                }
            })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.positionBar(); await model.refresh() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.positionBar() } })
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func openHub() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "hub" || ($0.title == "CAPA" && !($0 is NSPanel)) }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "CAPA"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MacHub(model: .shared, audio: MacModel.shared.audio))
            window.center(); window.makeKeyAndOrderFront(nil)
        }
    }
    func positionBar() {
        let model = MacModel.shared
        guard model.showBar else { panel?.orderOut(nil); return }
        if panel == nil {
            let value = WidgetPanel(contentRect: NSRect(x: 0, y: 0, width: CompactWidgetGeometry.width + 12, height: CompactWidgetGeometry.height + 12),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            value.isFloatingPanel = true; value.hidesOnDeactivate = false
            value.level = .statusBar
            value.becomesKeyOnlyIfNeeded = true
            value.ignoresMouseEvents = false
            // Give WindowServer a native backing surface, even behind glass.
            value.isOpaque = false; value.backgroundColor = NSColor.black.withAlphaComponent(0.02)
            // The native pointer surface owns dragging and defers click actions.
            value.isMovable = false; value.isMovableByWindowBackground = false
            value.acceptsMouseMovedEvents = true
            value.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            value.contentView = NSHostingView(rootView: FloatingBarView(model: model, audio: model.audio,
                openHub: { [weak self] in self?.openHub() },
                moveWidget: { [weak self] origin, finished in self?.moveWidget(to: origin, finished: finished) }))
            panel = value
        }
        guard !draggingWidget, let panel, let primary = NSScreen.screens.first else { return }
        if let saved = customOrigin {
            let center = CGPoint(x: saved.x + panel.frame.width / 2, y: saved.y + panel.frame.height / 2)
            let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? primary
            panel.setFrameOrigin(WidgetPlacement.clamped(saved, usable: screen.visibleFrame, panel: panel.frame.size))
        } else {
            panel.setFrameOrigin(WidgetPlacement.origin(screen: primary.frame, usable: primary.visibleFrame, panel: panel.frame.size))
        }
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        WidgetInputTrace.record("panel ready keyEligible=\(panel.canBecomeKey) level=\(panel.level.rawValue)")
    }
    private func moveWidget(to origin: CGPoint, finished: Bool) {
        guard let panel else { return }
        WidgetInputTrace.record(finished ? "move finished" : "move update")
        draggingWidget = !finished
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.screens.first else { return }
        let safe = WidgetPlacement.clamped(origin, usable: screen.visibleFrame, panel: panel.frame.size)
        panel.setFrameOrigin(safe)
        if finished { customOrigin = safe }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let taskID = info["task_id"] as? String
        let eventID = info["event_id"] as? String
        let originatingDeviceID = info["device_id"] as? String
        let controlID = info["control_id"] as? String
        let generation = info["generation"] as? Int
        let replyText = (response as? UNTextInputNotificationResponse)?.userText
        let action = response.actionIdentifier
        Task { @MainActor in
            defer { completionHandler() }
            if action == UNNotificationDismissActionIdentifier { return }
            if action == "CAPA_REPLY", let replyText, let taskID, let eventID {
                let sent = await MacModel.shared.replyFromNotification(eventID: eventID, taskID: taskID, text: replyText, originatingDeviceID: originatingDeviceID, controlID: controlID, generation: generation)
                if sent { return }
            }
            await MacModel.shared.refresh()
            self.openHub()
            MacModel.shared.selectedTask = MacModel.shared.tasks.first { $0.id == taskID }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
