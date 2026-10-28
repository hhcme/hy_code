import AppKit
import HyCodeWorkspace
import SwiftUI

/// The native input view owns IME composition and local undo. The conversation
/// owns only the persisted draft; streaming output never replaces marked text.
struct CodexComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var focusRequest: UUID?
    var enabled = true
    let submit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> CodexComposerScrollView {
        let scroll = CodexComposerScrollView()
        let input = CodexInputTextView(frame: .zero)
        input.isRichText = false
        input.allowsUndo = true
        input.drawsBackground = false
        input.font = .systemFont(ofSize: 14)
        input.textColor = CodexAppearance.nativeText
        input.insertionPointColor = CodexAppearance.nativeText
        input.textContainerInset = NSSize(width: 0, height: 8)
        input.textContainer?.lineFragmentPadding = 0
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.isAutomaticDashSubstitutionEnabled = false
        input.isAutomaticTextReplacementEnabled = false
        input.isContinuousSpellCheckingEnabled = false
        input.setAccessibilityLabel("发送给 Codex 的消息")
        input.delegate = context.coordinator
        input.submit = { [weak coordinator = context.coordinator] in coordinator?.parent.submit() }
        scroll.documentView = input
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.hasHorizontalScroller = false
        scroll.onHeight = { [weak coordinator = context.coordinator] in coordinator?.reportHeight($0) }
        scroll.onWindowReady = { [weak coordinator = context.coordinator] in coordinator?.applyFocus() }
        context.coordinator.input = input
        return scroll
    }
    func updateNSView(_ view: CodexComposerScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let input = view.documentView as? CodexInputTextView else { return }
        input.isEditable = enabled
        if input.string != text, !input.hasMarkedText() {
            input.string = text
            input.undoManager?.removeAllActions()
        }
        coordinator.applyFocus()
        view.needsLayout = true
    }
    static func dismantleNSView(_ view: CodexComposerScrollView, coordinator: Coordinator) {
        (view.documentView as? CodexInputTextView)?.submit = nil
        (view.documentView as? NSTextView)?.delegate = nil
        view.onHeight = nil
        view.onWindowReady = nil
        coordinator.localUndo.removeAllActions()
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodexComposerTextView
        weak var input: NSTextView?
        let localUndo = UndoManager()
        private var appliedFocus: UUID?
        init(_ parent: CodexComposerTextView) {
            self.parent = parent
        }
        func undoManager(for view: NSTextView) -> UndoManager? { localUndo }
        func applyFocus() {
            guard let request = parent.focusRequest, request != appliedFocus, let input,
                input.isEditable, let window = input.window, window.isKeyWindow,
                window.makeFirstResponder(input)
            else { return }
            appliedFocus = request
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.focusRequest == request else { return }
                self.parent.focusRequest = nil
            }
        }
        func textDidChange(_ notification: Notification) {
            guard let input else { return }
            parent.text = input.string
            input.enclosingScrollView?.needsLayout = true
        }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?)
            -> Bool
        {
            guard let replacementString else { return true }
            let value = textView.string as NSString
            guard affectedCharRange.location <= value.length,
                affectedCharRange.length <= value.length - affectedCharRange.location
            else { return false }
            return value.replacingCharacters(in: affectedCharRange, with: replacementString).utf8.count <= 65_536
        }
        func reportHeight(_ value: CGFloat) {
            let next = CGFloat(CodexChatPresentation.composerHeight(Double(value)))
            guard abs(parent.height - next) > 0.5 else { return }
            // Native layout can run during updateNSView; publish on the next
            // main-queue turn rather than mutating SwiftUI while it lays out.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.input != nil else { return }
                self.parent.height = next
            }
        }
    }
}

final class CodexComposerScrollView: NSScrollView {
    var onHeight: ((CGFloat) -> Void)?
    var onWindowReady: (() -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowReady?()
        DispatchQueue.main.async { [weak self] in self?.onWindowReady?() }
    }
    override func layout() {
        super.layout()
        guard let input = documentView as? NSTextView, let container = input.textContainer,
            let manager = input.layoutManager, contentSize.width > 0
        else { return }
        container.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let content = max(20, manager.usedRect(for: container).height) + input.textContainerInset.height * 2
        input.setFrameSize(NSSize(width: contentSize.width, height: max(contentSize.height, content)))
        onHeight?(content)
    }
}

final class CodexInputTextView: NSTextView {
    var submit: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
        if [36, 76].contains(event.keyCode), !hasMarkedText(), modifiers.isEmpty || modifiers == .command {
            submit?()
            return
        }
        super.keyDown(with: event)
    }
}
