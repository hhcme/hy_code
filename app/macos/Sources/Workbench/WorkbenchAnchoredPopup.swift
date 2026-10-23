import AppKit
import HyCodeWorkspace
import SwiftUI

extension View {
    func workbenchPopup<Content: View>(
        isPresented: Binding<Bool>, size: CGSize,
        keyDown: @escaping (NSEvent) -> Bool = { _ in false },
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        background(WorkbenchAnchoredPopup(presented: isPresented, size: size, keyDown: keyDown, content: content))
    }
}
private struct WorkbenchAnchoredPopup<Content: View>: NSViewRepresentable {
    @Binding var presented: Bool
    let size: CGSize
    let keyDown: (NSEvent) -> Bool
    @ViewBuilder let content: () -> Content
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ anchor: Anchor, context: Context) {
        anchor.closed = { presented = false }
        anchor.popup.keyDown = keyDown
        if presented {
            anchor.show(content().workbenchPopupSurface(), size: size)
        } else {
            anchor.dismiss()
        }
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.dismiss() }
    final class Anchor: NSView {
        let popup = WorkbenchPopupSession()
        var closed: () -> Void = {}
        private var generation: UInt64 = 0
        func dismiss() {
            generation &+= 1
            popup.close(notify: false)
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { popup.close() }
        }
        func show<V: View>(_ content: V, size: CGSize) {
            guard !popup.isVisible else { return }
            generation &+= 1
            let ticket = generation
            guard let window, popup.begin(in: self, consumeAnchorClick: true) else {
                Task { @MainActor [weak self] in if let self, generation == ticket { closed() } }
                return
            }
            popup.onClose = { [weak self] in
                Task { @MainActor [weak self] in if let self, generation == ticket { closed() } }
            }
            let frame = WorkbenchPopupPlacement.dropdown(
                anchor: window.convertToScreen(convert(bounds, to: nil)),
                size: size, screen: window.screen?.visibleFrame ?? window.frame)
            _ = popup.append(
                content.frame(width: frame.width, height: frame.height), frame: frame, label: "切换项目", role: .group)
        }
    }
}
