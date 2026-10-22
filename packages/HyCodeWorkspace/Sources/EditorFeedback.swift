import CoreGraphics

public struct EditorFeedbackPalette: Sendable {
    public let caret: UInt32
    public let background: UInt32
    public let currentLine: UInt32
    public static let dark = Self(caret: 0xF1F2F4, background: 0x191A1C, currentLine: 0x22242A)
    public static let light = Self(caret: 0x202126, background: 0xFFFFFF, currentLine: 0xF1F3F7)
}

public enum EditorFeedbackGeometry {
    public static func damage(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let caret = caret(rect, scale: scale)
        return caret.isEmpty ? rect : rect.union(caret)
    }
    /// Keep the native caret's position/height and blink lifecycle; give its
    /// drawing a visible two-point width aligned to backing pixels.
    public static func caret(_ rect: CGRect, scale: CGFloat) -> CGRect {
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
            rect.height > 0, scale.isFinite, scale > 0
        else { return .zero }
        return CGRect(
            x: (rect.minX * scale).rounded() / scale,
            y: (rect.minY * scale).rounded() / scale,
            width: ceil(max(2, rect.width) * scale) / scale,
            height: ceil(rect.height * scale) / scale)
    }
}
