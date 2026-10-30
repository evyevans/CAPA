import AppKit

/// Borderless nonactivating panels need an explicit key-window policy.
final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .leftMouseUp].contains(event.type) {
            let hit = contentView?.hitTest(event.locationInWindow)
            WidgetInputTrace.record("panel event=\(event.type.rawValue) ignores=\(ignoresMouseEvents) hit=\(hit.map { String(describing: type(of: $0)) } ?? "none")")
        }
        super.sendEvent(event)
    }
}

/// Opt-in, short-lived trace of this widget's actions only. No input contents.
enum WidgetInputTrace {
    private static let started = Date()
    private static let lock = NSLock()
    static func record(_ message: String) {
        guard ProcessInfo.processInfo.environment["CAPA_WIDGET_DIAGNOSTICS"] == "1",
              Date().timeIntervalSince(started) < 900 else { return }
        lock.lock(); defer { lock.unlock() }
        let directory = URL.applicationSupportDirectory.appendingPathComponent("CAPA/Diagnostics", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent("widget-\(ProcessInfo.processInfo.processIdentifier).log")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            guard try handle.seekToEnd() < 65536 else { return }
            try handle.write(contentsOf: Data("\(Date().timeIntervalSince1970) \(message)\n".utf8))
        } catch { /* Diagnostics never blocks an action on failure. */ }
    }
}
