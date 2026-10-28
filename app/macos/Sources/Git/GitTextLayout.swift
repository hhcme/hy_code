import AppKit
import HyCodeWorkspace

/// Presents continuous source paragraphs without blank alignment gaps. Drawing,
/// selection, caret and input all use TextKit's actual line-fragment geometry.
@MainActor final class GitTextLayout: NSObject, EditorComparisonPresentation {
    let id = UUID()
    private(set) var side: GitTextComparison.Side?
    private var width: CGFloat = 0
    private var rowCount = 0
    private weak var textView: NSTextView?
    private weak var scroll: NSScrollView?
    private weak var gutter: EditorLineRuler?
    private var previousHorizontal = false
    private var previousMask: NSView.AutoresizingMask = []
    private var previousContainerSize = NSSize.zero
    private var previousTracksWidth = true
    private var previousMinimum = NSSize.zero
    private var previousRulers = true
    private var previousClipBackground = true
    private var previousAppearance: NSAppearance?
    private weak var previousDelegate: (any NSLayoutManagerDelegate)?

    func configure(side: GitTextComparison.Side?, width: Double, rows: Int) {
        guard self.side != side || self.width != width || rowCount != rows else { return }
        self.side = side
        self.width = width
        rowCount = rows
        invalidate()
    }
    func attach(to editor: NativeTextEditor) {
        let view = editor.textView
        previousHorizontal = view.isHorizontallyResizable
        previousMask = view.autoresizingMask
        previousContainerSize = view.textContainer?.containerSize ?? .zero
        previousTracksWidth = view.textContainer?.widthTracksTextView ?? true
        previousMinimum = view.minSize
        previousRulers = editor.scroll.rulersVisible
        previousDelegate = view.layoutManager?.delegate
        bind(textView: view, scroll: editor.scroll, gutter: editor.presentation?.gutter)
    }
    func bind(textView: NSTextView, scroll: NSScrollView, gutter: EditorLineRuler?) {
        previousClipBackground = scroll.contentView.drawsBackground
        previousAppearance = scroll.appearance
        self.textView = textView
        self.scroll = scroll
        self.gutter = gutter
        (textView as? CodeTextView)?.comparison = self
        gutter?.comparison = self
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.rulersVisible = false
        scroll.contentView.drawsBackground = false
        // A source host may have set an explicit theme before lending its
        // editor. Inherit the active comparison's theme while it owns the view.
        scroll.appearance = nil
        WorkbenchScroller.configure(scroll, horizontal: true)
        invalidate()
    }
    func detach(from editor: NativeTextEditor) {
        guard textView === editor.textView else { return }
        let view = editor.textView
        clearCharacterBackgrounds()
        view.layoutManager?.delegate = previousDelegate
        view.isHorizontallyResizable = previousHorizontal
        view.autoresizingMask = previousMask
        view.textContainer?.widthTracksTextView = previousTracksWidth
        view.textContainer?.containerSize = previousContainerSize
        view.minSize = previousMinimum
        editor.scroll.rulersVisible = previousRulers
        editor.scroll.appearance = previousAppearance
        view.layoutManager?.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: view.textStorage?.length ?? 0), actualCharacterRange: nil)
        WorkbenchScroller.configure(editor.scroll, horizontal: previousHorizontal)
        editor.scroll.contentView.drawsBackground = previousClipBackground
        if !previousHorizontal {
            view.setFrameSize(
                NSSize(width: max(1, editor.scroll.contentSize.width), height: max(1, editor.scroll.contentSize.height))
            )
        }
        view.sizeToFit()
        view.needsDisplay = true
        gutter?.needsDisplay = true
        textView = nil
        scroll = nil
        gutter = nil
    }
    func willReplace() {
        // Old ranges and row offsets stop being valid before the first changed
        // character. Keep the native view/selection alive while preview catches up.
        guard side != nil else { return }
        side = nil
        invalidate()
    }
    private func clearCharacterBackgrounds() {
        guard let textView else { return }
        textView.layoutManager?.removeTemporaryAttribute(
            .backgroundColor,
            forCharacterRange: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
    }
    private func invalidate() {
        guard let textView, let scroll, let layout = textView.layoutManager else { return }
        clearCharacterBackgrounds()
        let length = textView.textStorage?.length ?? 0
        layout.invalidateLayout(forCharacterRange: NSRange(location: 0, length: length), actualCharacterRange: nil)
        if let side {
            for line in side.lines {
                guard let change = line.change, !change.isEmpty, line.offset + change.upperBound <= length else {
                    continue
                }
                layout.addTemporaryAttribute(
                    .backgroundColor, value: (GitStyle.changeColor(line.kind) ?? .systemBlue).withAlphaComponent(0.25),
                    forCharacterRange: NSRange(location: line.offset + change.lowerBound, length: change.count))
            }
        }
        let height =
            side == nil
            ? scroll.contentSize.height
            : CGFloat(side?.index.count ?? 1) * WorkbenchMetrics.editorLineHeight + WorkbenchMetrics.editorInset.height
                * 2
        textView.minSize = NSSize(width: scroll.contentSize.width, height: max(scroll.contentSize.height, height))
        textView.setFrameSize(
            NSSize(
                width: max(scroll.contentSize.width, width + WorkbenchMetrics.editorInset.width * 2 + 20),
                height: side == nil ? max(textView.minSize.height, textView.frame.height) : textView.minSize.height))
        textView.needsDisplay = true
        gutter?.needsDisplay = true
    }
    func drawBackground(in rect: NSRect, textView: NSTextView) {
        guard let side, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let origin = textView.textContainerOrigin
        let local = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layout.glyphRange(forBoundingRect: local, in: container)
        layout.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, range, _ in
            guard range.location < layout.numberOfGlyphs else { return }
            let offset = layout.characterIndexForGlyph(at: range.location)
            let line = side.lines[side.line(at: offset)]
            guard let color = GitStyle.changeColor(line.backgroundKind) else { return }
            let band = NSRect(
                x: textView.visibleRect.minX, y: fragment.minY + origin.y,
                width: textView.visibleRect.width, height: fragment.height
            ).intersection(rect)
            color.withAlphaComponent(GitStyle.bandAlpha).setFill()
            band.fill()
        }
    }
    func lineColor(at line: Int) -> NSColor? {
        guard let side, side.lines.indices.contains(line) else { return nil }
        return GitStyle.changeColor(side.lines[line].backgroundKind)
    }
    func containsChange(at offset: Int) -> Bool {
        guard let side, !side.lines.isEmpty else { return false }
        return side.lines[side.line(at: offset)].backgroundKind.isChange
    }
    func showsLineNumber(at line: Int) -> Bool { side?.text.isEmpty != true }
    var sourceView: NSTextView? { textView }
    func visiblePosition() -> Double? {
        guard let textView, let scroll, let side, let layout = textView.layoutManager,
            let container = textView.textContainer
        else { return nil }
        let y = scroll.contentView.bounds.minY - textView.textContainerOrigin.y
        let glyph = layout.glyphIndex(for: NSPoint(x: 0, y: y), in: container)
        let offset =
            glyph < layout.numberOfGlyphs
            ? layout.characterIndexForGlyph(at: glyph) : (textView.textStorage?.length ?? 0)
        let line = side.index.line(at: offset)
        let rect = lineRect(line)
        return Double(line) + Double((scroll.contentView.bounds.minY - rect.minY) / max(1, rect.height))
    }
    func lineRect(_ line: Int) -> NSRect {
        guard let textView, let side, let layout = textView.layoutManager else { return .zero }
        let index = max(0, min(side.index.count - 1, line))
        let offset = side.index.start(of: index)
        var rect: NSRect
        if offset < (textView.textStorage?.length ?? 0) {
            rect = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: offset), effectiveRange: nil)
        } else {
            rect = layout.extraLineFragmentRect
            if rect.isEmpty {
                rect = NSRect(
                    x: 0, y: CGFloat(index) * WorkbenchMetrics.editorLineHeight, width: 0,
                    height: WorkbenchMetrics.editorLineHeight)
            }
        }
        rect.origin.y += textView.textContainerOrigin.y
        rect.origin.y += CGFloat(line - index) * max(WorkbenchMetrics.editorLineHeight, rect.height)
        return rect
    }
    func scroll(to position: Double) {
        guard position.isFinite, let scroll else { return }
        let line = max(0, Int(position.rounded(.down)))
        let rect = lineRect(line)
        let y = rect.minY + CGFloat(position - Double(line)) * max(1, rect.height)
        let bounds = scroll.contentView.bounds
        let constrained = scroll.contentView.constrainBoundsRect(
            NSRect(x: bounds.minX, y: y, width: bounds.width, height: bounds.height))
        scroll.contentView.scroll(to: constrained.origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    func reveal(line: Int) { scroll(to: Double(max(0, line - 2))) }
}
