import AppKit
import HyCodeWorkspace
import SwiftUI

/// NSTextStorage's primitive captures exact UTF-16 deltas, including native
/// undo and IME changes, without diffing/copying the whole document on typing.
private final class EditorTextStorage: NSTextStorage, @unchecked Sendable {
    private let backing = NSMutableAttributedString(string: "")
    var onReplace: (@MainActor (NSRange, String, String) -> Void)?
    override var string: String { backing.string }
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }
    override func replaceCharacters(in range: NSRange, with str: String) {
        let removed = backing.mutableString.substring(with: range)
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
    let scroll = NSScrollView()
    let textView: NSTextView
    private let storage = EditorTextStorage()
    private let undo = UndoManager()
    private weak var document: EditorDocument?
    init(document: EditorDocument, content: String) {
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
        textView.isEditable = !document.closing
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
        textView.string = content
        undo.removeAllActions()
        storage.onReplace = { [weak document] range, text, removed in
            document?.replaced(range: range, text: text, removed: removed)
        }
        scroll.documentView = textView
        scroll.borderType = .noBorder
        WorkbenchScroller.configure(scroll)
        textView.setAccessibilityLabel("代码编辑区 · " + document.path)
        applyAppearance()
    }
    func undoManager(for view: NSTextView) -> UndoManager? { undo }
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
    func applyAppearance() {
        textView.backgroundColor = WorkbenchColors.nativePanel
        textView.textColor = WorkbenchColors.nativeText
        textView.insertionPointColor = WorkbenchColors.nativeText
        textView.selectedTextAttributes = [.backgroundColor: WorkbenchColors.nativeSelection]
        scroll.contentView.backgroundColor = WorkbenchColors.nativePanel
    }
}

struct NativeEditorHost: NSViewRepresentable {
    let editor: NativeTextEditor
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> NSScrollView { editor.scroll }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        scroll.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        scroll.effectiveAppearance.performAsCurrentDrawingAppearance { editor.applyAppearance() }
    }
}
