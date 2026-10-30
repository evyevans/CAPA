import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Screen-space placement only; never raises the widget over system UI.
public enum WidgetPlacement {
    public static func origin(screen: CGRect, usable: CGRect, panel: CGSize, dock: [CGRect] = []) -> CGPoint {
        let safe = screen.intersection(usable)
        let area = safe.isNull || safe.isEmpty ? screen : safe
        let x = min(max(screen.midX - panel.width / 2, area.minX), max(area.minX, area.maxX - panel.width))
        var y = max(screen.minY, area.minY)
        for rect in dock where rect.width > rect.height && rect.height > 2 && rect.height < screen.height * 0.4 {
            guard rect.minY <= screen.minY + 2, rect.maxY > screen.minY,
                  rect.maxX > x, rect.minX < x + panel.width else { continue }
            y = max(y, rect.maxY)
        }
        return CGPoint(x: x.rounded(), y: min(y, max(screen.minY, area.maxY - panel.height)).rounded())
    }
    public static func clamped(_ origin: CGPoint, usable: CGRect, panel: CGSize) -> CGPoint {
        CGPoint(x: min(max(origin.x, usable.minX), max(usable.minX, usable.maxX - panel.width)),
                y: min(max(origin.y, usable.minY), max(usable.minY, usable.maxY - panel.height)))
    }
    /// WindowServer uses a top-left origin, AppKit a bottom-left global origin.
    public static func appKitRect(_ rect: CGRect, primaryTop: Double) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }
}
