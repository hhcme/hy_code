import AppKit
import SwiftUI

@MainActor final class EditorApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var store: WorkbenchStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        Task {
            await Task.yield()
            store.prepareToCloseWindow { sender.reply(toApplicationShouldTerminate: $0) }
        }
        return .terminateLater
    }
}

/// Preserve SwiftUI's existing delegate by forwarding optional methods. Only
/// the user's close request is intercepted to protect dirty document buffers.
struct EditorWindowCloseGuard: NSViewRepresentable {
    let store: WorkbenchStore
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeNSView(context: Context) -> Marker {
        let marker = Marker()
        marker.coordinator = context.coordinator
        return marker
    }
    func updateNSView(_ view: Marker, context: Context) { context.coordinator.attach(view.window) }
    static func dismantleNSView(_ view: Marker, coordinator: Coordinator) { coordinator.detach() }
    final class Marker: NSView {
        weak var coordinator: Coordinator?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attach(window)
        }
    }
    final class Coordinator: NSObject, NSWindowDelegate {
        weak var window: NSWindow?
        weak var previous: NSWindowDelegate?
        let store: WorkbenchStore
        private var closing = false
        init(store: WorkbenchStore) { self.store = store }
        @MainActor func attach(_ window: NSWindow?) {
            guard self.window !== window else { return }
            detach()
            self.window = window
            previous = window?.delegate
            window?.delegate = self
        }
        @MainActor func detach() {
            if window?.delegate === self { window?.delegate = previous }
            window = nil
            previous = nil
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (previous?.responds(to: selector) ?? false)
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            previous?.responds(to: selector) == true ? previous : super.forwardingTarget(for: selector)
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if closing { return previous?.windowShouldClose?(sender) ?? true }
            store.prepareToCloseWindow { [weak self, weak sender] allowed in
                guard let self, let sender, allowed else { return }
                self.closing = true
                sender.performClose(nil)
                self.closing = false
            }
            return false
        }
    }
}
