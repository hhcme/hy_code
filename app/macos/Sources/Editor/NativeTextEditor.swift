import AppKit
import HyCodeWorkspace
import SwiftUI

@MainActor private final class EditorScrollView: NSScrollView {
    weak var presentation: EditorPresentation?
    private var fitting = false
    override func tile() {
        guard !fitting else { return }
        fitting = true
        defer { fitting = false }
        super.tile()
        guard let editor = documentView as? NSTextView, editor.isHorizontallyResizable else { return }
        let size = contentView.bounds.size
        editor.minSize = size
        let fitted = NSSize(width: max(size.width, editor.frame.width), height: max(size.height, editor.frame.height))
        if fitted != editor.frame.size { editor.setFrameSize(fitted) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { presentation?.cancel() } else { presentation?.schedule() }
    }
}

/// NSTextStorage's primitive captures exact UTF-16 deltas, including native
/// undo and IME changes, without diffing/copying the whole document on typing.
private final class EditorTextStorage: NSTextStorage, @unchecked Sendable {
    private let backing = NSMutableAttributedString(string: "")
    var suppressCallbacks = false
    var onReplace: (@MainActor (NSRange, String, String) -> Void)?
    var onWillReplace: (@MainActor (TextLineChange) -> Void)?
    var onWillEdit: (@MainActor (TextLineChange, LSPDocumentChange?) -> Void)?
    override var string: String { backing.string }
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }
    override func replaceCharacters(in range: NSRange, with str: String) {
        if suppressCallbacks {
            backing.replaceCharacters(in: range, with: str)
            edited(.editedCharacters, range: range, changeInLength: str.utf16.count - range.length)
            return
        }
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

@MainActor final class NativeTextEditor: NSObject, NSTextViewDelegate {
    let scroll: NSScrollView = EditorScrollView()
    let textView: NSTextView
    private let storage = EditorTextStorage()
    private let undo = UndoManager()
    private var replacingPage = false
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
        view.externalHistory = document.largeFile?.history
        super.init()
        view.compositionChanged = { [weak document, weak view] in
            guard let view else { return }
            document?.inputChanged(composing: view.hasMarkedText())
        }
        textView.delegate = self
        textView.isRichText = false
        textView.isEditable = !document.closing && !document.readOnly && !document.toolManaged
        textView.isSelectable = true
        textView.allowsUndo = document.largeFile == nil
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
        textView.font = .monospacedSystemFont(ofSize: WorkbenchMetrics.editorFontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = WorkbenchMetrics.editorLineHeight
        textView.defaultParagraphStyle = paragraph
        textView.textContainerInset = WorkbenchMetrics.editorInset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        container.widthTracksTextView = true
        if document.largeFile != nil {
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            container.widthTracksTextView = false
            container.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        textView.string = content.text
        storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
        textView.typingAttributes[.paragraphStyle] = paragraph
        undo.removeAllActions()
        storage.onReplace = { [weak document] range, text, removed in
            document?.replaced(range: range, text: text, removed: removed)
        }
        storage.onWillEdit = { [weak document] change, protocolChange in
            document?.semantic?.willReplace(change: change, protocolChange: protocolChange)
        }
        scroll.documentView = textView
        scroll.borderType = .noBorder
        WorkbenchScroller.configure(scroll, horizontal: document.largeFile != nil)
        if document.largeFile != nil { textView.sizeToFit() }
        presentation = EditorPresentation(
            document: document, scroll: scroll, textView: textView, lines: content.lineIndex)
        presentation?.gutter.localNumbers = document.largeFile != nil
        (scroll as? EditorScrollView)?.presentation = presentation
        storage.onWillReplace = { [weak self] change in
            self?.presentation?.willReplace(change)
        }
        textView.setAccessibilityLabel("代码编辑区 · " + document.path)
        applyAppearance()
    }
    func undoManager(for view: NSTextView) -> UndoManager? { document?.largeFile?.history ?? undo }
    func connect(_ semantic: EditorLanguageFeatures?) {
        guard let view = textView as? CodeTextView else { return }
        view.semantic = semantic
        presentation?.gutter.semantic = semantic
        semantic?.hoverInteraction.linkChanged = { [weak view] range in view?.semanticLinkRange = range }
    }
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?)
        -> Bool
    {
        guard !replacingPage else { return false }
        guard let replacementString else { return true }
        let removed = storage.mutableString.substring(with: affectedCharRange)
        return document?.permitsEdit(
            range: affectedCharRange, replacement: replacementString,
            removed: removed, currentLength: storage.length) ?? false
    }
    func textView(
        _ textView: NSTextView, shouldChangeTextInRanges affectedRanges: [NSValue], replacementStrings: [String]?
    ) -> Bool {
        guard !replacingPage else { return false }
        guard let replacementStrings else { return true }
        return document?.permitsBatch(
            ranges: affectedRanges.map(\.rangeValue), replacements: replacementStrings, source: storage.mutableString)
            ?? false
    }
    func textDidChange(_ notification: Notification) {
        if !replacingPage { document?.inputChanged(composing: textView.hasMarkedText()) }
    }
    func loadPage(_ content: TextDocumentContent) {
        replacingPage = true
        storage.suppressCallbacks = true
        presentation?.replacePage(lines: content.lineIndex)
        textView.string = content.text
        if let paragraph = textView.defaultParagraphStyle {
            storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
        }
        (textView as? CodeTextView)?.newline =
            content.lineEnding == "CRLF" ? "\r\n" : content.lineEnding == "CR" ? "\r" : "\n"
        textView.sizeToFit()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        storage.suppressCallbacks = false
        replacingPage = false
        presentation?.schedule()
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        (textView as? CodeTextView)?.selectionFeedbackChanged()
        presentation?.selectionChanged()
    }
    func applyAppearance() {
        textView.backgroundColor = WorkbenchColors.nativePanel
        textView.textColor = WorkbenchColors.nativeText
        (textView as? CodeTextView)?.updateEditorFocus()
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
