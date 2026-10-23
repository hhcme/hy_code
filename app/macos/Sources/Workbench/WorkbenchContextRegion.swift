import AppKit
import SwiftUI

extension View {
    /// Only secondary/control-click hit testing enters the overlay. Normal
    /// activation, double click, focus and drag remain with the SwiftUI control.
    func workbenchContextMenu(_ items: [WorkbenchMenuItem]) -> some View {
        overlay(WorkbenchContextRegion(items: items))
    }
}
private struct WorkbenchContextRegion: NSViewRepresentable {
    let items: [WorkbenchMenuItem]
    func makeNSView(context: Context) -> Region { Region() }
    func updateNSView(_ view: Region, context: Context) { view.items = items }
    static func dismantleNSView(_ view: Region, coordinator: ()) { view.popup.hide() }
    final class Region: NSView {
        var items: [WorkbenchMenuItem] = []
        let popup = WorkbenchContextMenu()
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                event.type == .rightMouseDown
                    || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            else { return nil }
            return super.hitTest(point)
        }
        override func rightMouseDown(with event: NSEvent) { show(event) }
        override func mouseDown(with event: NSEvent) { show(event) }
        private func show(_ event: NSEvent) {
            guard let window else { return }
            popup.show(items.map(\.contextCommand), at: window.convertPoint(toScreen: event.locationInWindow), in: self)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { popup.hide() }
        }
    }
}
