import AppKit
import SwiftUI

/// One user-invoked floating-surface lifetime. Never key/main; preserves the
/// editor responder, shares outside-click handling across a submenu chain and
/// tears down its local monitor together with every child panel.
@MainActor final class WorkbenchPopupSession: NSObject {
    private(set) weak var owner: NSView?
    private(set) weak var parent: NSWindow?
    private(set) var panels: [NSPanel] = []
    private var monitor: PopupEventMonitor?
    private var consumeAnchorClick = false
    var onClose: () -> Void = {}
    var keyDown: (NSEvent) -> Bool = { _ in false }
    var scrolled: (Int) -> Void = { _ in }
    var isVisible: Bool { panels.first?.isVisible == true }
    func begin(in owner: NSView, consumeAnchorClick: Bool = false) -> Bool {
        close(notify: false)
        guard let parent = owner.window, parent.isKeyWindow else { return false }
        self.owner = owner
        self.parent = parent
        self.consumeAnchorClick = consumeAnchorClick
        for name in [
            NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
            NSWindow.willMoveNotification, NSWindow.didResizeNotification,
        ] {
            NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: name, object: parent)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(interrupted),
            name: NSApplication.didResignActiveNotification, object: nil)
        let token = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .scrollWheel, .keyDown,
        ]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.receive(event) ?? false }
            return consumed ? nil : event
        }
        monitor = token.map(PopupEventMonitor.init)
        return true
    }
    func append<Content: View>(_ content: Content, frame: CGRect, label: String, role: NSAccessibility.Role = .menu)
        -> NSPanel?
    {
        guard let parent, let owner, owner.window === parent else { return nil }
        let panel = PopupPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.level = parent.level
        panel.appearance = owner.effectiveAppearance
        let dark = owner.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let host = PopupHost(rootView: content.environment(\.colorScheme, dark ? .dark : .light))
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.setAccessibilityRole(role)
        host.setAccessibilityLabel(label)
        panel.contentView = host
        panel.setFrame(frame, display: false)
        parent.addChildWindow(panel, ordered: .above)
        panels.append(panel)
        panel.orderFront(nil)
        return panel
    }
    func trim(to count: Int) {
        while panels.count > count {
            let panel = panels.removeLast()
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }
    func close(notify: Bool = true) {
        let active = owner != nil || !panels.isEmpty
        monitor = nil
        NotificationCenter.default.removeObserver(self)
        trim(to: 0)
        owner = nil
        parent = nil
        if active && notify { onClose() }
    }
    @objc private func interrupted(_ note: Notification) { close() }
    private func receive(_ event: NSEvent) -> Bool {
        guard let owner, let parent, owner.window === parent, parent.isKeyWindow, isVisible else {
            close()
            return false
        }
        if event.type == .keyDown {
            guard event.window === parent else {
                close()
                return false
            }
            if event.keyCode == 53 {
                close()
                return true
            }
            if keyDown(event) { return true }
            close()
            return false
        }
        if let index = panels.firstIndex(where: { $0 === event.window }) {
            if event.type == .scrollWheel { scrolled(index) }
            return false
        }
        let atAnchor =
            consumeAnchorClick && event.type != .scrollWheel && event.window === parent
            && owner.visibleRect.contains(owner.convert(event.locationInWindow, from: nil))
        close()
        return atAnchor
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

private final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private final class PopupHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Removing the local monitor is mandatory even if its owner is released while
/// a window tears down. Normal dismissal removes it explicitly before panels.
private final class PopupEventMonitor: @unchecked Sendable {
    let token: Any
    init(_ token: Any) { self.token = token }
    deinit { NSEvent.removeMonitor(token) }
}
