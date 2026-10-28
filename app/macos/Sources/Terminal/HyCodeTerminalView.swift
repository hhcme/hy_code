import AppKit
import HyCodeWorkspace
import SwiftTerm
import SwiftUI

@MainActor final class HyCodeTerminalView: TerminalView {
    var onFocus: () -> Void = {}
    var onFind: () -> Void = {}
    var onPaste: (String) -> Void = { _ in }
    var onWillInput: () -> Void = {}
    var onCompletionKey: (UInt16) -> Bool = { _ in false }
    var onManualCompletion: () -> Bool = { false }
    var onDismissCompletion: () -> Void = {}
    var onViewportChange: () -> Void = {}
    var terminalVisible = false { didSet { updateKeyMonitor() } }
    var enabledForInput = true
    var focusWhenVisible = false
    private let popup = WorkbenchContextMenu()
    private var appliedAppearance: NSAppearance.Name?
    private var keyMonitor: TerminalKeyMonitor?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL])
        focusIfPossible()
        updateKeyMonitor()
        if let window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(checkCompletionFocus), name: NSWindow.didUpdateNotification, object: window)
        }
        if window == nil { popup.hide() }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow {
            if let window {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didUpdateNotification, object: window)
            }
            keyMonitor = nil
            releaseFocusIfHeld()
            popup.hide()
        }
        super.viewWillMove(toWindow: newWindow)
    }
    func releaseFocusIfHeld() {
        guard let window, let responder = window.firstResponder as? NSView,
            responder === self || responder.isDescendant(of: self)
        else { return }
        window.makeFirstResponder(nil)
    }
    func focusIfPossible() {
        guard focusWhenVisible, terminalVisible, let window, !isHiddenOrHasHiddenAncestor else { return }
        window.makeFirstResponder(self)
        focusWhenVisible = false
    }
    func applyTheme() {
        let name = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua
        guard appliedAppearance != name else { return }
        appliedAppearance = name
        // SwiftTerm snapshots colors into its VT palette. Resolve dynamic
        // workbench colors in this view's appearance, not the system default.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            nativeForegroundColor = TerminalPalette.foreground(dark: name == .darkAqua)
            nativeBackgroundColor = WorkbenchColors.nativePanel
            caretColor = WorkbenchColors.nativeCaret
            selectedTextBackgroundColor = WorkbenchColors.nativeSelection
            installColors(TerminalPalette.ansi(dark: name == .darkAqua))
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }
    override func mouseDown(with event: NSEvent) {
        guard terminalVisible else { return }
        onDismissCompletion()
        onFocus()
        super.mouseDown(with: event)
    }
    private func consumeCompletionKey(_ event: NSEvent) -> Bool {
        guard terminalVisible else { return false }
        if event.type != .keyDown {
            if event.window !== window || !bounds.contains(convert(event.locationInWindow, from: nil)) {
                onDismissCompletion()
            }
            return false
        }
        guard terminalVisible, enabledForInput, event.window === window, window?.firstResponder === self else {
            return false
        }
        if !hasMarkedText() {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if modifiers == .control, event.keyCode == 49 {
                return onManualCompletion()
            }
            if modifiers.isEmpty, onCompletionKey(event.keyCode) { return true }
        }
        if event.modifierFlags.contains(.command) { onDismissCompletion() } else { onWillInput() }
        return false
    }
    @objc private func checkCompletionFocus() {
        if window?.firstResponder !== self { onDismissCompletion() }
    }
    private func updateKeyMonitor() {
        guard terminalVisible, window != nil else {
            keyMonitor = nil
            return
        }
        guard keyMonitor == nil else { return }
        if let token = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.consumeCompletionKey(event) == true }
                return consumed ? nil : event
            })
        {
            keyMonitor = TerminalKeyMonitor(token)
        }
    }
    override func insertText(_ string: Any, replacementRange: NSRange) {
        onWillInput()
        super.insertText(string, replacementRange: replacementRange)
    }
    /// Pinned SwiftTerm has no public scroller factory. Hide only its direct
    /// NSScroller child; the app-owned viewport reserves and draws the 8pt lane.
    func hideBuiltInScroller() {
        for child in subviews.compactMap({ $0 as? NSScroller }) {
            child.isHidden = true
            child.setAccessibilityHidden(true)
        }
    }
    override func layout() {
        super.layout()
        onViewportChange()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard terminalVisible, window?.firstResponder === self,
            event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "f":
            onFind()
            return true
        case "k":
            clearScrollback()
            return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
    override func paste(_ sender: Any) {
        guard enabledForInput, terminalVisible, let text = NSPasteboard.general.string(forType: .string) else { return }
        onWillInput()
        onPaste(text)
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let window, terminalVisible else { return }
        onDismissCompletion()
        onFocus()
        popup.show(
            [
                WorkbenchContextCommand(
                    title: "复制", shortcut: "⌘C", action: { [weak self] in self?.copy(self as Any) }),
                WorkbenchContextCommand(
                    title: "粘贴", shortcut: "⌘V", enabled: enabledForInput,
                    action: { [weak self] in self?.paste(self as Any) }),
                .separator,
                WorkbenchContextCommand(title: "查找", shortcut: "⌘F", action: { [weak self] in self?.onFind() }),
                WorkbenchContextCommand(
                    title: "清除滚动历史", shortcut: "⌘K", action: { [weak self] in self?.clearScrollback() }),
            ], at: window.convertPoint(toScreen: event.locationInWindow), in: self)
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        terminalVisible && enabledForInput ? .copy : []
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard terminalVisible, enabledForInput,
            let files = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
            files.count <= 64
        else { return false }
        onWillInput()
        onPaste(files.map { TerminalConfiguration.quotePath($0.path) }.joined(separator: " "))
        return true
    }
}

private final class TerminalKeyMonitor {
    private let token: Any
    init(_ token: Any) { self.token = token }
    deinit { NSEvent.removeMonitor(token) }
}

struct TerminalNativeHost: NSViewRepresentable {
    let session: TerminalPaneSession
    let visible: Bool
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> TerminalViewport { TerminalViewport(terminal: session.view) }
    func updateNSView(_ host: TerminalViewport, context: Context) {
        let view = session.view
        view.terminalVisible = visible
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        view.applyTheme()
        view.setAccessibilityHidden(!visible)
        if !visible {
            session.dismissCompletion()
            view.releaseFocusIfHeld()
        }
        if visible { view.focusIfPossible() }
        host.synchronizeScroller()
    }
}
