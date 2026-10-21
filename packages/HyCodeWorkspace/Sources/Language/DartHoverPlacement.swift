import Foundation

public enum DartHoverPlacement {
    public static func screen(for anchor: CGRect, screens: [CGRect], fallback: CGRect) -> CGRect {
        let point = CGPoint(x: anchor.midX, y: anchor.midY)
        return screens.first { $0.contains(point) } ?? fallback
    }
    public static func frame(anchor: CGRect, size: CGSize, screens: [CGRect], fallback: CGRect) -> CGRect {
        let screen = screen(for: anchor, screens: screens, fallback: fallback)
        let width = min(size.width, max(1, screen.width - 16))
        let height = min(size.height, max(1, screen.height - 16))
        let x = min(max(anchor.minX - 12, screen.minX + 8), screen.maxX - width - 8)
        var y = anchor.minY - height - 7
        if y < screen.minY + 8 { y = anchor.maxY + 7 }
        y = min(max(y, screen.minY + 8), screen.maxY - height - 8)
        return CGRect(x: x, y: y, width: width, height: height)
    }
    /// Preserve a reachable corridor across the small gap between the symbol
    /// line and its card. Slow pointer travel is allowed; unrelated editor
    /// whitespace is outside this region and uses the close grace period.
    public static func isInBridge(_ point: CGPoint, anchor: CGRect, panel: CGRect) -> Bool {
        let lower: CGFloat
        let upper: CGFloat
        if panel.maxY <= anchor.minY {
            lower = panel.maxY
            upper = anchor.maxY
        } else if panel.minY >= anchor.maxY {
            lower = anchor.minY
            upper = panel.minY
        } else {
            return false
        }
        return CGRect(
            x: min(anchor.minX, panel.minX) - 2, y: lower - 2,
            width: max(anchor.maxX, panel.maxX) - min(anchor.minX, panel.minX) + 4, height: upper - lower + 4
        ).contains(point)
    }
}
