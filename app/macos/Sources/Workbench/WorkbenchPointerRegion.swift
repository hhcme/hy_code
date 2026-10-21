import AppKit
import SwiftUI

/// Native cursor rectangles avoid unbalanced global NSCursor push/pop calls.
/// This background view never handles clicks or contributes a layout size.
struct WorkbenchPointerRegion: NSViewRepresentable {
    var enabled: Bool
    func makeNSView(context: Context) -> CursorRegion { CursorRegion() }
    func updateNSView(_ view: CursorRegion, context: Context) { view.enabled = enabled }

    final class CursorRegion: NSView {
        var enabled = true {
            didSet { if oldValue != enabled { window?.invalidateCursorRects(for: self) } }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() {
            super.resetCursorRects()
            if enabled, !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty {
                addCursorRect(visibleRect, cursor: .pointingHand)
            }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }
    }
}
