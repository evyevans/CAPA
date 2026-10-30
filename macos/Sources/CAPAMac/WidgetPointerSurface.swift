import AppKit
import SwiftUI

/// Defers click actions until mouse-up, so dragging anywhere in the capsule
/// cannot also start a recording or open the hub. Existing SwiftUI buttons
/// remain the accessibility/keyboard actions underneath this pointer surface.
struct WidgetPointerSurface: NSViewRepresentable {
    let click: (CGPoint, CGPoint) -> Void
    let move: (CGPoint, Bool) -> Void
    func makeNSView(context: Context) -> PointerView { PointerView() }
    func updateNSView(_ view: PointerView, context: Context) {
        view.click = click; view.move = move
    }
    final class PointerView: NSView {
        var click: ((CGPoint, CGPoint) -> Void)?
        var move: ((CGPoint, Bool) -> Void)?
        private var startMouse = CGPoint.zero
        private var startLocal = CGPoint.zero
        private var startOrigin = CGPoint.zero
        private var dragged = false
        private var contextClick = false
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var needsPanelToBecomeKey: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(0.04).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 15, yRadius: 15).fill()
        }
        private func screenPoint(_ event: NSEvent) -> CGPoint {
            window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        }
        override func mouseDown(with event: NSEvent) {
            WidgetInputTrace.record("pointer down")
            contextClick = event.modifierFlags.contains(.control)
            if contextClick { super.rightMouseDown(with: event); return }
            startMouse = screenPoint(event)
            startLocal = convert(event.locationInWindow, from: nil)
            startOrigin = window?.frame.origin ?? .zero
            dragged = false
        }
        override func mouseDragged(with event: NSEvent) {
            guard !contextClick else { return }
            let mouse = screenPoint(event)
            let dx = mouse.x - startMouse.x, dy = mouse.y - startMouse.y
            guard dragged || hypot(dx, dy) >= 5 else { return }
            dragged = true
            move?(CGPoint(x: startOrigin.x + dx, y: startOrigin.y + dy), false)
        }
        override func mouseUp(with event: NSEvent) {
            WidgetInputTrace.record(dragged ? "pointer drop" : "pointer click")
            guard !contextClick else { contextClick = false; return }
            if dragged { move?(window?.frame.origin ?? startOrigin, true) }
            else { click?(startLocal, convert(event.locationInWindow, from: nil)) }
            dragged = false
        }
    }
}
