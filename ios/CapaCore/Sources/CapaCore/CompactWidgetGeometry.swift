import Foundation

/// Shared geometry keeps the two controls disjoint as visuals change state.
public enum CompactWidgetGeometry {
    public static let width = 104.0
    public static let height = 30.0
    public static let recordWidth = 52.0
    public static let arrowWidth = 20.0
    public static let arrowHeight = 26.0
    public static let arrowCenter = 92.0
    public enum Action { case none, record, openApp }
    public static func click(startX: Double, startY: Double, endX: Double, endY: Double, capturing: Bool) -> Action {
        let initial = action(x: startX, y: startY, capturing: capturing)
        return initial == action(x: endX, y: endY, capturing: capturing) ? initial : .none
    }
    public static func action(x: Double, y: Double, capturing: Bool) -> Action {
        guard x.isFinite, y.isFinite, y >= 0, y <= height else { return .none }
        if x >= (width - recordWidth) / 2, x <= (width + recordWidth) / 2 { return .record }
        if !capturing, x >= arrowCenter - arrowWidth / 2, x <= arrowCenter + arrowWidth / 2,
           y >= (height - arrowHeight) / 2, y <= (height + arrowHeight) / 2 { return .openApp }
        return .none
    }
}
