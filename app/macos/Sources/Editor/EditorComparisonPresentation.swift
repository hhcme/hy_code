import AppKit

/// A temporary view projection. It cannot own or replace document characters,
/// the text delegate, undo manager, input method or save lifecycle.
@MainActor protocol EditorComparisonPresentation: AnyObject {
    var id: UUID { get }
    func attach(to editor: NativeTextEditor)
    func detach(from editor: NativeTextEditor)
    func willReplace()
    func drawBackground(in rect: NSRect, textView: NSTextView)
    func lineColor(at line: Int) -> NSColor?
    func containsChange(at offset: Int) -> Bool
    func showsLineNumber(at line: Int) -> Bool
}
