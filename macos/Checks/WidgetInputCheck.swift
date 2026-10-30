import AppKit
import SwiftUI
struct TestWidget: View {
 var click: (CGPoint,CGPoint)->Void
 var move: (CGPoint,Bool)->Void
 var body: some View {
  ZStack {
   Capsule().fill(Color.gray.opacity(0.6)).allowsHitTesting(false)
   Button("Record") {}.frame(width:52,height:30)
  }.frame(width:104,height:30)
   .overlay { WidgetPointerSurface(click:click,move:move).accessibilityHidden(true) }
   .onHover {_ in}.contextMenu {Button("Open") {}}
   .padding(6)
 }
}
@main struct Check {
 @MainActor static func main() {
  _ = NSApplication.shared
  let window=WidgetPanel(contentRect:NSRect(x:200,y:200,width:116,height:42),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  var clicks = 0, moves = 0, drops = 0
  let host=NSHostingView(rootView:TestWidget(click:{_,_ in clicks += 1},move:{origin,finished in
   window.setFrameOrigin(origin)
   if finished { drops += 1 } else { moves += 1 }
  }))
  window.contentView=host
  window.orderFrontRegardless()
  host.layoutSubtreeIfNeeded()
  RunLoop.main.run(until:Date().addingTimeInterval(0.2))
  let hit=host.hitTest(CGPoint(x:58,y:21))
  precondition(hit is WidgetPointerSurface.PointerView, "Native pointer view must receive initial hit tests")
  func event(_ type: NSEvent.EventType, _ x: Double, _ y: Double) -> NSEvent {
   NSEvent.mouseEvent(with:type, location:NSPoint(x:x,y:y), modifierFlags:[], timestamp:ProcessInfo.processInfo.systemUptime,
    windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
  }
  window.sendEvent(event(.leftMouseDown,58,21))
  window.sendEvent(event(.leftMouseUp,58,21))
  precondition(clicks == 1, "Click must traverse NSWindow + NSHostingView to callback")
  window.sendEvent(event(.leftMouseDown,58,21))
  window.sendEvent(event(.leftMouseDragged,78,31))
  window.sendEvent(event(.leftMouseUp,58,21))
  precondition(clicks == 1 && moves >= 1 && drops == 1, "Drag must traverse full hosting hierarchy without click")
  print("Hosted event routing passed: hit test, NSWindow click, NSWindow drag, no click on drop")
  window.orderOut(nil)
 }
}
