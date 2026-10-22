import CoreGraphics

public enum ContextMenuMetrics {
    /// Measured title + shortcut width; remaining space is the icon, gaps and
    /// padding shared by all rows. Clamp to the pointer's screen on small displays.
    public static func width(contentWidth: CGFloat, screenWidth: CGFloat) -> CGFloat {
        min(max(1, screenWidth - 12), min(360, max(220, ceil(contentWidth) + 88)))
    }
}

/// Keyboard selection never lands on separators or disabled commands.
public struct ContextMenuSelection: Sendable {
    public let enabled: [Bool]
    public private(set) var index: Int?
    public init(enabled: [Bool]) {
        self.enabled = enabled
        index = enabled.firstIndex(of: true)
    }
    public mutating func select(_ index: Int?) {
        guard let index, enabled.indices.contains(index), enabled[index] else { return }
        self.index = index
    }
    public mutating func move(forward: Bool) {
        guard !enabled.isEmpty else { return }
        var candidate = index ?? (forward ? enabled.count - 1 : 0)
        for _ in enabled.indices {
            candidate = forward ? (candidate + 1) % enabled.count : (candidate + enabled.count - 1) % enabled.count
            if enabled[candidate] {
                index = candidate
                return
            }
        }
    }
    public mutating func edge(last: Bool) { index = last ? enabled.lastIndex(of: true) : enabled.firstIndex(of: true) }
}

public enum ContextMenuPlacement {
    /// Anchor is in screen coordinates (bottom-left origin). Prefer opening
    /// below/right of the pointer; keep the menu inside the usable screen.
    public static func frame(anchor: CGPoint, size: CGSize, screen: CGRect) -> CGRect {
        let inset = screen.insetBy(dx: min(6, screen.width / 4), dy: min(6, screen.height / 4))
        let width = min(max(1, size.width), max(1, inset.width))
        let height = min(max(1, size.height), max(1, inset.height))
        let preferredX = anchor.x + width > inset.maxX ? anchor.x - width : anchor.x
        let preferredY = anchor.y - height < inset.minY ? anchor.y : anchor.y - height
        return CGRect(
            x: min(max(preferredX, inset.minX), inset.maxX - width),
            y: min(max(preferredY, inset.minY), inset.maxY - height), width: width, height: height)
    }
}
