import CoreGraphics

/// AppKit dirty rectangles can extend outside a view's bounds. Keep all gutter
/// background/label drawing inside the view, and restore the caller's graphics
/// state so subsequent text and sibling drawing retain their original clip.
public enum EditorGutterDrawing {
    public static func draw(
        in context: CGContext, bounds: CGRect, dirtyRect: CGRect, body: (CGRect) -> Void
    ) {
        guard isFinite(bounds), isFinite(dirtyRect), bounds.width > 0, bounds.height > 0,
            dirtyRect.width > 0, dirtyRect.height > 0
        else { return }
        let clip = bounds.intersection(dirtyRect)
        guard !clip.isNull, !clip.isEmpty else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: clip)
        body(clip)
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
    }
}
