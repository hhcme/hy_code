import AppKit
import HyCodeWorkspace

@MainActor final class CodeTextView: NSTextView {
    var externalHistory: UndoManager?
    override var undoManager: UndoManager? { externalHistory ?? super.undoManager }
    weak var semantic: EditorLanguageFeatures?
    private lazy var windowFeedback = EditorWindowFeedback(view: self)
    private var lastLineRect = NSRect.zero
    private var editorFocused: Bool { window?.isKeyWindow == true && window?.firstResponder === self }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { Task { @MainActor [weak self] in self?.updateEditorFocus() } }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            contextMenu.hide()
            Task { @MainActor [weak self] in self?.updateEditorFocus() }
        }
        return accepted
    }
    func updateEditorFocus() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            insertionPointColor = WorkbenchColors.nativeCaret.usingColorSpace(.sRGB)
            selectedTextAttributes = [
                .backgroundColor: editorFocused
                    ? WorkbenchColors.nativeSelection : WorkbenchColors.nativeInactiveSelection,
                .foregroundColor: WorkbenchColors.nativeText,
            ]
        }
        updateInsertionPointStateAndRestartTimer(true)
        selectionFeedbackChanged()
    }
    func selectionFeedbackChanged() {
        if !lastLineRect.isEmpty { setNeedsDisplay(lastLineRect) }
        lastLineRect = currentLineRect()
        if !lastLineRect.isEmpty { setNeedsDisplay(lastLineRect) }
    }
    private func currentLineRect() -> NSRect {
        guard editorFocused, selectedRange().length == 0, let layout = layoutManager,
            textContainer != nil
        else { return .zero }
        let offset = min(selectedRange().location, textStorage?.length ?? 0)
        let fragment: NSRect
        if offset == (textStorage?.length ?? 0), !layout.extraLineFragmentRect.isEmpty {
            fragment = layout.extraLineFragmentRect
        } else if (textStorage?.length ?? 0) > 0 {
            let index = max(0, offset == (textStorage?.length ?? 0) ? offset - 1 : offset)
            let glyphs = layout.glyphRange(
                forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            guard glyphs.length > 0 else { return .zero }
            fragment = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        } else {
            fragment = NSRect(
                x: 0, y: 0, width: 0,
                height: max(
                    WorkbenchMetrics.editorLineHeight,
                    layout.defaultLineHeight(for: font ?? .systemFont(ofSize: WorkbenchMetrics.editorFontSize))))
        }
        return NSRect(
            x: visibleRect.minX, y: fragment.minY + textContainerOrigin.y,
            width: visibleRect.width, height: fragment.height)
    }
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let band = currentLineRect().intersection(rect)
        if !band.isEmpty {
            WorkbenchColors.nativeEditorLine.setFill()
            band.fill()
        }
    }
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let caret = EditorFeedbackGeometry.caret(rect, scale: window?.backingScaleFactor ?? 2)
        guard !caret.isEmpty else { return }
        super.drawInsertionPoint(in: caret, color: insertionPointColor, turnedOn: flag)
    }
    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        super.setNeedsDisplay(
            EditorFeedbackGeometry.damage(rect, scale: window?.backingScaleFactor ?? 2),
            avoidAdditionalLayout: flag)
    }
    var semanticLinkRange: NSRange? { didSet { window?.invalidateCursorRects(for: self) } }
    private var hoverTracking: NSTrackingArea?
    override func resetCursorRects() {
        super.resetCursorRects()
        if !visibleRect.isEmpty { addCursorRect(visibleRect, cursor: .iBeam) }
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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showEditorMenu(event)
            return
        }
        contextMenu.hide()
        window?.makeFirstResponder(self)
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
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if let externalHistory, event.charactersIgnoringModifiers == "z",
            modifiers == .command || modifiers == [.command, .shift]
        {
            if isEditable, !hasMarkedText() {
                if modifiers.contains(.shift) { externalHistory.redo() } else { externalHistory.undo() }
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        contextMenu.hide()
        semantic?.dismissHover()
        if event.keyCode == 109, event.modifierFlags.contains(.shift) {
            _ = accessibilityPerformShowMenu()
            return
        }
        if event.charactersIgnoringModifiers == "\t",
            event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
            semantic?.advanceSnippet(backward: event.modifierFlags.contains(.shift)) == true
        {
            return
        }
        super.keyDown(with: event)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        contextMenu.hide()
        semantic?.dismissHover()
        windowFeedback.observe(window)
        updateEditorFocus()
    }
    override func complete(_ sender: Any?) { if let semantic { semantic.complete() } else { super.complete(sender) } }
    private let contextMenu = WorkbenchContextMenu()
    override func rightMouseDown(with event: NSEvent) { showEditorMenu(event) }
    private func showEditorMenu(_ event: NSEvent) {
        semantic?.dismissHover()
        window?.makeFirstResponder(self)
        if !hasMarkedText() {
            let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
            let selection = selectedRange()
            if !NSLocationInRange(index, selection) { setSelectedRange(NSRange(location: index, length: 0)) }
        }
        guard let window else { return }
        contextMenu.show(
            EditorContextCommands.make(for: self, semantic: semantic),
            at: window.convertPoint(toScreen: event.locationInWindow), in: self)
    }
    override func menu(for event: NSEvent) -> NSMenu? { nil }
    override func accessibilityPerformShowMenu() -> Bool {
        guard let window, window.isKeyWindow, window.makeFirstResponder(self) else { return false }
        let point = firstRect(forCharacterRange: selectedRange(), actualRange: nil).origin
        contextMenu.show(EditorContextCommands.make(for: self, semantic: semantic), at: point, in: self)
        return window.isKeyWindow
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

/// Own registrations on a separate target: removing NSTextView's observers
/// would also remove private AppKit caret/focus subscriptions.
@MainActor private final class EditorWindowFeedback: NSObject {
    private weak var view: CodeTextView?
    private weak var window: NSWindow?
    init(view: CodeTextView) { self.view = view }
    deinit { NotificationCenter.default.removeObserver(self) }
    func observe(_ window: NSWindow?) {
        guard self.window !== window else { return }
        NotificationCenter.default.removeObserver(self)
        self.window = window
        if let window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(changed), name: name, object: window)
            }
        }
    }
    @objc private func changed(_ note: Notification) { view?.updateEditorFocus() }
}
