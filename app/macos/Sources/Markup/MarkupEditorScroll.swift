import AppKit
import HyCodeWorkspace

extension NativeTextEditor {
    func previewScrollPosition() -> (line: Int, fraction: Double) {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return (0, 0) }
        var rect = textView.visibleRect
        rect.origin.x -= textView.textContainerOrigin.x
        rect.origin.y -= textView.textContainerOrigin.y
        let glyphs = layout.glyphRange(forBoundingRect: rect, in: container)
        let range = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let line = presentation?.gutter.lines.line(at: range.location) ?? 0
        let distance = max(1, textView.bounds.height - scroll.contentView.bounds.height)
        return (line, MarkupScrollMapping.fraction(scroll.contentView.bounds.minY / distance))
    }
    func scrollPreview(to line: Int?, fraction: Double) {
        let y: CGFloat
        if let line, let lines = presentation?.gutter.lines, let layout = textView.layoutManager,
            let container = textView.textContainer,
            let source = textView.textStorage, source.length > 0
        {
            let offset = min(source.length - 1, lines.start(of: line))
            let glyph = layout.glyphIndexForCharacter(at: offset)
            let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            _ = container
            y = rect.minY + textView.textContainerOrigin.y
        } else {
            y =
                MarkupScrollMapping.fraction(fraction)
                * max(0, textView.bounds.height - scroll.contentView.bounds.height)
        }
        let maxY = max(0, textView.bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: min(maxY, max(0, y))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
