import AppKit
import SwiftUI

/// Plain native text, a dedicated undo owner, and normal Enter/newline behavior.
/// It never borrows the source editor's undo manager or first responder.
struct GitMessageField: NSViewRepresentable {
    @Binding var text: String
    @Binding var composing: Bool
    let enabled: Bool
    @Environment(\.colorScheme) private var scheme
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let view = GitMessageTextView()
        view.isRichText = false
        view.isEditable = enabled
        view.isSelectable = true
        view.allowsUndo = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainerInset = CGSize(width: 5, height: 6)
        view.font = .systemFont(ofSize: 13)
        view.drawsBackground = false
        view.delegate = context.coordinator
        view.changedComposition = { [weak coordinator = context.coordinator] in coordinator?.publish($0) }
        scroll.documentView = view
        WorkbenchScroller.configure(scroll, vertical: true)
        view.setAccessibilityLabel("Git 提交消息，Enter 换行")
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? GitMessageTextView else { return }
        context.coordinator.update = { text, marked in
            self.text = text
            self.composing = marked
        }
        view.isEditable = enabled
        view.textColor = WorkbenchColors.nativeText
        scroll.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        if view.string != text && !view.hasMarkedText() {
            view.string = text
            view.undoManager?.removeAllActions()
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var update: (String, Bool) -> Void = { _, _ in }
        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? GitMessageTextView { publish(view) }
        }
        fileprivate func publish(_ view: GitMessageTextView) { update(view.string, view.hasMarkedText()) }
    }
}

final class GitMessageTextView: NSTextView {
    private let history = UndoManager()
    var changedComposition: (GitMessageTextView) -> Void = { _ in }
    override var undoManager: UndoManager? { history }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        changedComposition(self)
    }
    override func unmarkText() {
        super.unmarkText()
        changedComposition(self)
    }
}
