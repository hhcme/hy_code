import AppKit
import HyCodeWorkspace
import SwiftUI

@MainActor private final class EditorScrollView: NSScrollView {
    weak var presentation: EditorPresentation?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { presentation?.cancel() } else { presentation?.schedule() }
    }
}

/// NSTextStorage's primitive captures exact UTF-16 deltas, including native
/// undo and IME changes, without diffing/copying the whole document on typing.
private final class EditorTextStorage: NSTextStorage, @unchecked Sendable {
    private let backing = NSMutableAttributedString(string: "")
    var onReplace: (@MainActor (NSRange, String, String) -> Void)?
    var onWillReplace: (@MainActor (TextLineChange) -> Void)?
    var onWillEdit: (@MainActor (TextLineChange, LSPDocumentChange?) -> Void)?
    override var string: String { backing.string }
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }
    override func replaceCharacters(in range: NSRange, with str: String) {
        let removed = backing.mutableString.substring(with: range)
        let willReplace = onWillReplace
        let willEdit = onWillEdit
        let change = TextLineChange(source: backing.mutableString, range: range, replacement: str)
        let protocolChange = LSPDocumentChange(source: backing.mutableString, range: range, replacement: str)
        MainActor.assumeIsolated {
            willEdit?(change, protocolChange)
            willReplace?(change)
        }
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        // This storage belongs only to a main-thread TextKit 1 view. Rust and
        // worker threads never borrow it; they receive owned delta strings.
        let callback = onReplace
        MainActor.assumeIsolated { callback?(range, str, removed) }
    }
    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }
}

@MainActor private final class CodeTextView: NSTextView {
    weak var semantic: DartEditorFeatures?
    var semanticLinkRange: NSRange? { didSet { window?.invalidateCursorRects(for: self) } }
    private var hoverTracking: NSTrackingArea?
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let range = semanticLinkRange, let layout = layoutManager, let container = textContainer,
            NSMaxRange(range) <= (textStorage?.length ?? 0)
        else { return }
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        layout.enumerateEnclosingRects(
            forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container
        ) { rect, _ in
            self.addCursorRect(
                rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y), cursor: .pointingHand)
        }
    }
    private func symbolOffset(at point: NSPoint) -> Int? {
        guard let layout = layoutManager, let container = textContainer else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: local, in: container)
        guard glyph < layout.numberOfGlyphs,
            layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local)
        else { return nil }
        return layout.characterIndexForGlyph(at: glyph)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self
        )
        addTrackingArea(area)
        hoverTracking = area
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        semantic?.hoverInteraction.move(at: symbolOffset(at: point), command: event.modifierFlags.contains(.command))
    }
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        semantic?.hoverInteraction.move(
            at: visibleRect.contains(point) ? symbolOffset(at: point) : nil,
            command: event.modifierFlags.contains(.command))
    }
    override func mouseExited(with event: NSEvent) {
        semantic?.hoverInteraction.pointerExitedEditor()
        super.mouseExited(with: event)
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let semantic,
            let offset = symbolOffset(at: convert(event.locationInWindow, from: nil))
        {
            semantic.navigate(
                "textDocument/definition", at: offset)
        } else {
            semantic?.dismissHover()
            super.mouseDown(with: event)
        }
    }
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2, let semantic,
            let offset = symbolOffset(at: convert(event.locationInWindow, from: nil))
        {
            semantic.navigate("textDocument/definition", at: offset)
        } else {
            super.otherMouseDown(with: event)
        }
    }
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber != 2 || semantic == nil { super.otherMouseUp(with: event) }
    }
    override func keyDown(with event: NSEvent) {
        semantic?.dismissHover()
        super.keyDown(with: event)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        semantic?.dismissHover()
    }
    override func complete(_ sender: Any?) { if let semantic { semantic.complete() } else { super.complete(sender) } }
    override func menu(for event: NSEvent) -> NSMenu? {
        semantic?.dismissHover()
        if semantic != nil {
            let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
            if !NSLocationInRange(index, selectedRange()) { setSelectedRange(NSRange(location: index, length: 0)) }
        }
        let menu = super.menu(for: event) ?? NSMenu()
        if let semantic {
            menu.addItem(.separator())
            for (title, action) in [
                ("跳转定义 ⌘B", #selector(DartEditorFeatures.definition)),
                ("查找引用", #selector(DartEditorFeatures.references)), ("格式化文档", #selector(DartEditorFeatures.format)),
            ] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = semantic
                menu.addItem(item)
            }
        }
        return menu
    }
    var newline = "\n"
    var compositionChanged: (() -> Void)?
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        compositionChanged?()
    }
    override func unmarkText() {
        super.unmarkText()
        compositionChanged?()
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        compositionChanged?()
    }
    override func insertNewline(_ sender: Any?) {
        if newline == "\n" {
            super.insertNewline(sender)
        } else {
            insertText(newline, replacementRange: selectedRange())
        }
    }
}

@MainActor final class NativeTextEditor: NSObject, NSTextViewDelegate {
    let scroll: NSScrollView = EditorScrollView()
    let textView: NSTextView
    private let storage = EditorTextStorage()
    private let undo = UndoManager()
    private weak var document: EditorDocument?
    private(set) var presentation: EditorPresentation?
    init(document: EditorDocument, content: TextDocumentContent) {
        self.document = document
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let view = CodeTextView(frame: .zero, textContainer: container)
        view.newline = document.lineEnding == "CRLF" ? "\r\n" : document.lineEnding == "CR" ? "\r" : "\n"
        textView = view
        super.init()
        view.compositionChanged = { [weak document, weak view] in
            guard let view else { return }
            document?.inputChanged(composing: view.hasMarkedText())
        }
        textView.delegate = self
        textView.isRichText = false
        textView.isEditable = !document.closing && !document.readOnly && !document.toolManaged
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        container.widthTracksTextView = true
        textView.string = content.text
        undo.removeAllActions()
        storage.onReplace = { [weak document] range, text, removed in
            document?.replaced(range: range, text: text, removed: removed)
        }
        storage.onWillEdit = { [weak document] change, protocolChange in
            document?.semantic?.willReplace(change: change, protocolChange: protocolChange)
        }
        scroll.documentView = textView
        scroll.borderType = .noBorder
        WorkbenchScroller.configure(scroll)
        presentation = EditorPresentation(
            document: document, scroll: scroll, textView: textView, lines: content.lineIndex)
        (scroll as? EditorScrollView)?.presentation = presentation
        storage.onWillReplace = { [weak self] change in
            self?.presentation?.willReplace(change)
        }
        textView.setAccessibilityLabel("代码编辑区 · " + document.path)
        applyAppearance()
    }
    func undoManager(for view: NSTextView) -> UndoManager? { undo }
    func connect(_ semantic: DartEditorFeatures?) {
        guard let view = textView as? CodeTextView else { return }
        view.semantic = semantic
        presentation?.gutter.semantic = semantic
        semantic?.hoverInteraction.linkChanged = { [weak view] range in view?.semanticLinkRange = range }
    }
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?)
        -> Bool
    {
        guard let replacementString else { return true }
        let removed = storage.mutableString.substring(with: affectedCharRange)
        return document?.permitsEdit(
            range: affectedCharRange, replacement: replacementString,
            removed: removed, currentLength: storage.length) ?? false
    }
    func textDidChange(_ notification: Notification) { document?.inputChanged(composing: textView.hasMarkedText()) }
    func textViewDidChangeSelection(_ notification: Notification) { presentation?.selectionChanged() }
    func applyAppearance() {
        textView.backgroundColor = WorkbenchColors.nativePanel
        textView.textColor = WorkbenchColors.nativeText
        textView.insertionPointColor = WorkbenchColors.nativeText
        textView.selectedTextAttributes = [.backgroundColor: WorkbenchColors.nativeSelection]
        scroll.contentView.backgroundColor = WorkbenchColors.nativePanel
        presentation?.appearanceChanged()
    }
}

struct NativeEditorHost: NSViewRepresentable {
    let editor: NativeTextEditor
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("editor.lineNumbers") private var lineNumbers = true
    @AppStorage("editor.syntaxHighlight") private var syntaxHighlight = true
    func makeNSView(context: Context) -> NSScrollView { editor.scroll }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let name: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        if scroll.appearance?.name != name {
            scroll.appearance = NSAppearance(named: name)
            scroll.effectiveAppearance.performAsCurrentDrawingAppearance { editor.applyAppearance() }
        }
        editor.presentation?.configure(lineNumbers: lineNumbers, syntaxHighlight: syntaxHighlight)
    }
}
