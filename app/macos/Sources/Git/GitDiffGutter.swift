import AppKit
import HyCodeWorkspace

/// Both gutters sit beside the centre divider. TextKit supplies the same line
/// fragments as selection/caret; no independent row-height or scroll offset.
@MainActor final class GitDiffGutter: NSView {
    private weak var textView: NSTextView?
    private var index: () -> TextLineIndex = { TextLineIndex() }
    private var label: (Int) -> String? = { String($0 + 1) }
    private var color: (Int) -> NSColor? = { _ in nil }
    private weak var comparisonLayout: GitTextLayout?
    private var blocks: [GitDiffBlock] = []
    private var actions: GitHunkActions?
    private var left = true
    private var buttons: [Int: GitHunkButton] = [:]
    private let font = NSFont.monospacedDigitSystemFont(ofSize: WorkbenchMetrics.gutterFontSize, weight: .regular)
    var trailing = false
    var connected = false
    var allowsDividerTracking = true
    override var isOpaque: Bool { !connected }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = true
        setAccessibilityLabel("差异行号")
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        // The rails are foreground siblings. Leave the centre margin to the
        // underlying native split view's enlarged divider tracking rectangle.
        if allowsDividerTracking && (trailing ? local.x >= bounds.maxX - 4 : local.x <= bounds.minX + 4) { return nil }
        return super.hitTest(point)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    func configure(
        textView: NSTextView, index: @escaping () -> TextLineIndex,
        label: @escaping (Int) -> String?, color: @escaping (Int) -> NSColor?
    ) {
        self.textView = textView
        self.index = index
        self.label = label
        self.color = color
        needsDisplay = true
    }
    func configureActions(blocks: [GitDiffBlock], left: Bool, actions: GitHunkActions, layout: GitTextLayout) {
        self.blocks = blocks
        self.left = left
        self.actions = actions
        comparisonLayout = layout
        refreshActions()
    }
    override func layout() {
        super.layout()
        refreshActions()
    }
    /// Retain native controls only for visible block anchors. Their y coordinate
    /// comes from exactly the line fragment used for the number and text.
    func refreshActions() {
        var visible = Set<Int>()
        if !isHidden, let actions, let layout = comparisonLayout, let view = layout.sourceView,
            let start = layout.visiblePosition()
        {
            let end = start + Double(bounds.height / WorkbenchMetrics.editorLineHeight) + 2
            for block in blocks {
                let line = (left ? block.left : block.right).lowerBound
                guard Double(line) >= start - 1, Double(line) <= end else { continue }
                let fragment = layout.lineRect(line)
                let point = convert(NSPoint(x: 0, y: fragment.minY), from: view)
                guard point.y + fragment.height >= 0, point.y < bounds.height else { continue }
                visible.insert(block.id)
                let button = buttons[block.id] ?? GitHunkButton(selection: !left)
                if button.superview !== self {
                    addSubview(button)
                    buttons[block.id] = button
                }
                button.frame = NSRect(
                    x: left ? 1 : max(0, bounds.width - 20),
                    y: point.y + max(0, (fragment.height - 18) / 2), width: 18, height: 18)
                button.isEnabled = left ? actions.restoreEnabled : actions.selectionEnabled
                button.toolTip = left ? actions.restoreHelp : actions.selectionHelp
                button.setAccessibilityLabel(left ? "还原此处更改，可撤销" : "将此处更改选入提交")
                let selected = actions.isSelected(block.id)
                if !left { button.state = selected ? .on : .off }
                let left = self.left
                button.perform = { if left { actions.restore(block.id) } else { actions.choose(block.id, !selected) } }
            }
        }
        for id in Array(buttons.keys) where !visible.contains(id) {
            buttons.removeValue(forKey: id)?.removeFromSuperview()
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        if !connected {
            WorkbenchColors.nativePanel.setFill()
            dirtyRect.fill()
        }
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let lines = index()
        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let length = textView.textStorage?.length ?? 0
        var line = lines.line(at: chars.location)
        while line < lines.count {
            let offset = lines.start(of: line)
            if offset > NSMaxRange(chars) { break }
            var fragment: NSRect
            if offset < length {
                fragment = layout.lineFragmentRect(
                    forGlyphAt: layout.glyphIndexForCharacter(at: offset), effectiveRange: nil)
            } else {
                fragment = layout.extraLineFragmentRect
                if fragment.isEmpty {
                    fragment = NSRect(
                        x: 0, y: CGFloat(line) * WorkbenchMetrics.editorLineHeight, width: 0,
                        height: WorkbenchMetrics.editorLineHeight)
                }
            }
            let point = convert(NSPoint(x: 0, y: fragment.minY + origin.y), from: textView)
            if point.y > bounds.maxY { break }
            if point.y + fragment.height >= 0 {
                let band = NSRect(x: 0, y: point.y, width: bounds.width, height: fragment.height).intersection(
                    dirtyRect)
                if !connected, let color = color(line) {
                    color.withAlphaComponent(GitStyle.bandAlpha).setFill()
                    band.fill()
                }
                if let value = label(line) {
                    let number = NSAttributedString(
                        string: value, attributes: [.font: font, .foregroundColor: WorkbenchColors.nativeSecondary])
                    number.draw(
                        at: NSPoint(
                            x: trailing ? max(4, bounds.width - 9 - number.size().width) : 8,
                            y: point.y + max(0, (fragment.height - number.size().height) / 2)))
                }
            }
            line += 1
        }
        if !connected {
            WorkbenchColors.nativeBorder.withAlphaComponent(0.7).setFill()
            NSRect(x: trailing ? 0 : bounds.width - 0.5, y: 0, width: 0.5, height: bounds.height).intersection(
                dirtyRect
            )
            .fill()
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let textView, textView.isSelectable, let layout = textView.layoutManager,
            let container = textView.textContainer
        else { return }
        let point = textView.convert(event.locationInWindow, from: nil)
        let glyph = layout.glyphIndex(for: NSPoint(x: 0, y: point.y - textView.textContainerOrigin.y), in: container)
        let length = textView.textStorage?.length ?? 0
        let offset = glyph < layout.numberOfGlyphs ? layout.characterIndexForGlyph(at: glyph) : length
        let lines = index()
        let line = lines.line(at: offset)
        guard label(line) != nil else { return }
        let start = lines.start(of: line)
        let end = line + 1 < lines.count ? lines.start(of: line + 1) : length
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
    }
}
