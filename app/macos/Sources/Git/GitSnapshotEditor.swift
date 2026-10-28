import AppKit
import HyCodeWorkspace

/// Read-only historical source. A real NSTextView supports multi-line selection,
/// native copy/find and scrolling without constructing a writable document owner.
@MainActor final class GitSnapshotEditor: NSObject {
    let scroll = GitSnapshotScroll()
    let textView: CodeTextView
    let layout = GitTextLayout()
    private let gutter: EditorLineRuler
    var lineIndex: TextLineIndex { gutter.lines }
    private var side: GitTextComparison.Side?
    private var path = ""
    private let worker = SyntaxFragmentWorker()
    private var syntaxTask: Task<Void, Never>?
    private var syntaxTicket = UUID()
    private var syntaxEnabled = true
    private var numbersEnabled = true
    private var painted = NSRange(location: 0, length: 0)
    private var dark: Bool?
    override init() {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        manager.allowsNonContiguousLayout = true
        let container = NSTextContainer(
            containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        textView = CodeTextView(frame: .zero, textContainer: container)
        gutter = EditorLineRuler(scroll: scroll, textView: textView, lines: TextLineIndex())
        super.init()
        textView.isRichText = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.font = .monospacedSystemFont(ofSize: WorkbenchMetrics.editorFontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = WorkbenchMetrics.editorLineHeight
        textView.defaultParagraphStyle = paragraph
        textView.textContainerInset = WorkbenchMetrics.editorInset
        scroll.documentView = textView
        scroll.verticalRulerView = gutter
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.borderType = .noBorder
        layout.bind(textView: textView, scroll: scroll, gutter: gutter)
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.windowChanged = { [weak self] in self?.scheduleSyntax() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    func configure(
        _ side: GitTextComparison.Side, width: Double, rows: Int, path: String,
        numbers: Bool, syntax: Bool, aligned: Bool = true
    ) {
        let changed = self.side?.text.utf8.elementsEqual(side.text.utf8) != true || self.path != path
        let isDark = textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let resetSyntax = changed || dark != isDark || syntaxEnabled != syntax
        dark = isDark
        self.side = side
        self.path = path
        numbersEnabled = numbers
        syntaxEnabled = syntax
        if changed {
            syntaxTask?.cancel()
            syntaxTicket = UUID()
            painted = .init(location: 0, length: 0)
            textView.string = side.text
            if let paragraph = textView.defaultParagraphStyle {
                textView.textStorage?.addAttribute(
                    .paragraphStyle, value: paragraph,
                    range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
            }
            gutter.lines = side.index
            gutter.updateThickness()
        }
        scroll.rulersVisible = numbersEnabled
        layout.configure(side: aligned ? side : nil, width: width, rows: rows)
        textView.backgroundColor = WorkbenchColors.nativePanel
        textView.textColor = WorkbenchColors.nativeText
        textView.updateEditorFocus()
        scroll.contentView.backgroundColor = WorkbenchColors.nativePanel
        gutter.needsDisplay = true
        if resetSyntax { clearSyntax() }
        scheduleSyntax()
    }
    func suspend() {
        syntaxTask?.cancel()
        syntaxTask = nil
        syntaxTicket = UUID()
    }
    @objc private func scrolled() {
        gutter.needsDisplay = true
        scheduleSyntax()
    }
    private func clearSyntax() {
        textView.layoutManager?.removeTemporaryAttribute(
            .foregroundColor, forCharacterRange: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        textView.layoutManager?.removeTemporaryAttribute(
            .font, forCharacterRange: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        painted = NSRange(location: 0, length: 0)
    }
    private func scheduleSyntax() {
        guard scroll.window != nil, syntaxEnabled, !path.isEmpty, let manager = textView.layoutManager,
            let container = textView.textContainer
        else {
            suspend()
            return
        }
        let visible = textView.visibleRect.offsetBy(
            dx: -textView.textContainerOrigin.x, dy: -textView.textContainerOrigin.y)
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        let chars = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        guard NSIntersectionRange(chars, painted) != chars,
            let range = SyntaxViewportState.requestRange(for: chars, source: textView.textStorage?.mutableString ?? ""),
            range.length > 0
        else { return }
        syntaxTask?.cancel()
        let ticket = UUID()
        syntaxTicket = ticket
        let text = textView.textStorage!.mutableString.substring(with: range)
        let path = self.path
        let worker = worker
        syntaxTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(30))
                let result = try await worker.highlight(text: text, path: path, start: range.location)
                guard let self, !Task.isCancelled, self.syntaxTicket == ticket,
                    let manager = self.textView.layoutManager
                else { return }
                self.clearSyntax()
                let dark = self.textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                for span in result.spans where NSMaxRange(span.range) <= (self.textView.textStorage?.length ?? 0) {
                    manager.addTemporaryAttributes(
                        SyntaxPalette.attributes(span.style, language: result.language, dark: dark),
                        forCharacterRange: span.range)
                }
                self.painted = range
            } catch {
                // Syntax is optional; native selection and source remain available.
            }
        }
    }
}

@MainActor final class GitSnapshotScroll: NSScrollView {
    var windowChanged: () -> Void = {}
    var leadingVerticalScroller = false {
        didSet { if oldValue != leadingVerticalScroller { tile() } }
    }
    private var fitting = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowChanged()
    }
    override func tile() {
        guard !fitting else { return }
        fitting = true
        defer { fitting = false }
        super.tile()
        if leadingVerticalScroller, let verticalScroller,
            let placement = GitScrollPlacement(
                content: contentView.frame, vertical: verticalScroller.frame,
                horizontal: horizontalScroller?.frame)
        {
            contentView.frame = placement.content
            verticalScroller.frame = placement.vertical
            if let horizontal = placement.horizontal { horizontalScroller?.frame = horizontal }
        }
        guard let editor = documentView as? NSTextView else { return }
        editor.minSize.width = contentView.bounds.width
        if editor.frame.width < contentView.bounds.width {
            editor.setFrameSize(NSSize(width: contentView.bounds.width, height: editor.frame.height))
        }
    }
}
