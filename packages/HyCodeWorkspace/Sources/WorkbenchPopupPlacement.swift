import CoreGraphics

/// Screen coordinates, bottom-left origin. All floating surfaces share the
/// same edge margin, including left-hand/negative-coordinate displays.
public enum WorkbenchPopupPlacement {
    public static func dropdown(anchor: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        let area = screen.insetBy(dx: min(6, screen.width / 4), dy: min(6, screen.height / 4))
        let width = min(max(1, size.width), max(1, area.width))
        let height = min(max(1, size.height), max(1, area.height))
        let below = anchor.minY - 4 - height
        let y = below >= area.minY ? below : anchor.maxY + 4
        return CGRect(
            x: min(max(area.minX, anchor.minX), area.maxX - width),
            y: min(max(area.minY, y), area.maxY - height), width: width, height: height)
    }
    public static func submenu(parent: CGRect, row: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        let area = screen.insetBy(dx: min(6, screen.width / 4), dy: min(6, screen.height / 4))
        let width = min(max(1, size.width), max(1, area.width))
        let height = min(max(1, size.height), max(1, area.height))
        let right = parent.maxX - 2
        let x = right + width <= area.maxX ? right : parent.minX + 2 - width
        return CGRect(
            x: min(max(area.minX, x), area.maxX - width),
            y: min(max(area.minY, row.maxY + 6 - height), area.maxY - height), width: width, height: height)
    }
}
