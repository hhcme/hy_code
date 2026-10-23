import AppKit
import HyCodeWorkspace

@MainActor final class EditorLineRuler: NSRulerView {
    weak var semantic: EditorLanguageFeatures?
    var lines: TextLineIndex
    private weak var editor: NSTextView?
    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: WorkbenchMetrics.gutterFontSize, weight: .regular)
    override var isFlipped: Bool { true }
    init(scroll: NSScrollView, textView: NSTextView, lines: TextLineIndex) {
        self.lines = lines
        editor = textView
        super.init(scrollView: scroll, orientation: .verticalRuler)
        clipsToBounds = true
        clientView = textView
        updateThickness()
        setAccessibilityLabel("行号")
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func resetCursorRects() {
        super.resetCursorRects()
        if semantic?.document?.readOnly == false, semantic?.controller?.flutter != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let semantic, semantic.document?.readOnly == false,
            let editor, let layout = editor.layoutManager, let container = editor.textContainer,
            let path = semantic.document?.sourceURL.path
        else {
            super.mouseDown(with: event)
            return
        }
        let point = editor.convert(event.locationInWindow, from: nil)
        let local = NSPoint(x: 0, y: point.y - editor.textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: local, in: container)
        let offset =
            glyph < layout.numberOfGlyphs ? layout.characterIndexForGlyph(at: glyph) : (editor.textStorage?.length ?? 0)
        semantic.controller?.flutter?.toggleBreakpoint(path: path, line: semantic.lines.line(at: offset) + 1)
        needsDisplay = true
    }
    func updateThickness() {
        let width = max(52, CGFloat(String(lines.count).count) * 8 + 28)
        if ruleThickness != width { ruleThickness = width }
    }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        EditorGutterDrawing.draw(in: context, bounds: bounds, dirtyRect: rect) { clippedRect in
            drawLines(in: clippedRect)
        }
    }
    private func drawLines(in rect: NSRect) {
        WorkbenchColors.nativePanel.setFill()
        rect.fill()
        guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return }
        let origin = editor.textContainerOrigin
        var visible = editor.visibleRect
        visible.origin.x -= origin.x
        visible.origin.y -= origin.y
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let selectedLine = lines.line(at: editor.selectedRange().location)
        let length = editor.textStorage?.length ?? 0
        var line = lines.line(at: chars.location)
        while line < lines.count {
            let offset = lines.start(of: line)
            if offset > NSMaxRange(chars) { break }
            let fragment: NSRect
            if offset == length {
                fragment =
                    layout.extraLineFragmentRect.isEmpty
                    ? NSRect(
                        x: 0, y: 0, width: 0,
                        height: max(
                            WorkbenchMetrics.editorLineHeight, layout.defaultLineHeight(for: editor.font ?? numberFont))
                    )
                    : layout.extraLineFragmentRect
            } else {
                let glyph = layout.glyphIndexForCharacter(at: offset)
                fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            let point = convert(NSPoint(x: 0, y: fragment.minY + origin.y), from: editor)
            if point.y > bounds.maxY { break }
            if point.y + fragment.height >= 0 {
                if let semantic, let path = semantic.document?.sourceURL.path,
                    let runtime = semantic.controller?.flutter
                {
                    let number = semantic.lines.line(at: offset) + 1
                    if let breakpoint = runtime.breakpoints[path]?.first(where: { $0.line == number }) {
                        let dot = NSRect(x: 4, y: point.y + max(0, (fragment.height - 9) / 2), width: 9, height: 9)
                        (breakpoint.enabled ? NSColor.systemRed : NSColor.secondaryLabelColor).set()
                        let shape = NSBezierPath(ovalIn: dot)
                        if runtime.verified[path]?.contains(number) == true { shape.fill() } else { shape.stroke() }
                    }
                    if runtime.state.phase == .paused,
                        let frame = runtime.frames.first(where: { $0["id"].int == runtime.selectedFrame }),
                        frame["source"]["path"].string == path, frame["line"].int == number
                    {
                        let arrow = NSBezierPath()
                        let y = point.y + fragment.height / 2
                        arrow.move(to: NSPoint(x: 15, y: y - 4))
                        arrow.line(to: NSPoint(x: 21, y: y))
                        arrow.line(to: NSPoint(x: 15, y: y + 4))
                        arrow.close()
                        NSColor.systemYellow.setFill()
                        arrow.fill()
                    }
                }
                let label = NSAttributedString(
                    string: String(line + 1),
                    attributes: [
                        .font: numberFont,
                        .foregroundColor: line == selectedLine
                            ? WorkbenchColors.nativeText : NSColor.secondaryLabelColor,
                    ])
                label.draw(
                    at: NSPoint(
                        x: ruleThickness - 12 - label.size().width,
                        y: point.y + max(0, (fragment.height - label.size().height) / 2)))
            }
            line += 1
        }
    }
}
