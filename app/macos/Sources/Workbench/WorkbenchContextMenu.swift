import AppKit
import HyCodeWorkspace
import Observation
import SwiftUI

@MainActor struct WorkbenchContextCommand {
    var title: String
    var symbol = ""
    var shortcut = ""
    var enabled = true
    var action: (() -> Void)?
    var isSeparator: Bool { action == nil && title.isEmpty }
    static var separator: Self { Self(title: "", enabled: false) }
}

@MainActor @Observable private final class ContextMenuModel {
    let items: [WorkbenchContextCommand]
    var selection: ContextMenuSelection
    let choose: (Int) -> Void
    init(items: [WorkbenchContextCommand], choose: @escaping (Int) -> Void) {
        self.items = items
        selection = ContextMenuSelection(enabled: items.map { $0.enabled && !$0.isSeparator })
        self.choose = choose
    }
}

/// A non-key child panel: the editor remains the text-input owner. Its local
/// event monitor exists only while the menu is open and never consumes clicks
/// outside the menu, text input or events belonging to another window.
@MainActor final class WorkbenchContextMenu: NSObject {
    private var panel: ContextPanel?
    private var model: ContextMenuModel?
    private weak var owner: NSView?
    private weak var parent: NSWindow?
    private var monitor: Any?
    func show(_ items: [WorkbenchContextCommand], at anchor: NSPoint, in view: NSView) {
        hide()
        guard let parent = view.window, parent.isKeyWindow, !items.isEmpty else { return }
        owner = view
        self.parent = parent
        let model = ContextMenuModel(items: items) { [weak self] in self?.choose($0) }
        self.model = model
        let panel = ContextPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.panel = panel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.level = parent.level
        panel.appearance = view.effectiveAppearance
        let screen =
            NSScreen.screens.first(where: { $0.frame.contains(anchor) })?.visibleFrame
            ?? parent.screen?.visibleFrame ?? parent.frame
        let font = NSFont.systemFont(ofSize: 12.5)
        let contentWidth =
            items.filter { !$0.isSeparator }.map { item in
                (item.title as NSString).size(withAttributes: [.font: font]).width
                    + (item.shortcut as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 0
        let width = ContextMenuMetrics.width(contentWidth: contentWidth, screenWidth: screen.width)
        let naturalHeight = CGFloat(items.reduce(12) { $0 + ($1.isSeparator ? 9 : 28) })
        let frame = ContextMenuPlacement.frame(
            anchor: anchor, size: NSSize(width: width, height: naturalHeight), screen: screen)
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let host = ContextHost(
            rootView: ContextMenuContent(model: model).environment(\.colorScheme, dark ? .dark : .light))
        host.sizingOptions = []
        host.setAccessibilityRole(.menu)
        host.setAccessibilityLabel("编辑菜单")
        panel.contentView = host
        panel.setFrame(frame, display: false)
        parent.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        for name in [
            NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
            NSWindow.willMoveNotification, NSWindow.didResizeNotification,
        ] {
            NotificationCenter.default.addObserver(self, selector: #selector(dismiss), name: name, object: parent)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(dismiss), name: NSApplication.didResignActiveNotification, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown,
        ]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.receive(event) == nil
            }
            return consumed ? nil : event
        }
    }
    @objc private func dismiss(_ notification: Notification) { hide() }
    func hide() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.removeObserver(self)
        if let panel { panel.parent?.removeChildWindow(panel) }
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        model = nil
        owner = nil
        parent = nil
    }
    private func choose(_ index: Int) {
        guard let model, model.items.indices.contains(index), model.items[index].enabled,
            let owner, let parent, owner.window === parent, parent.isKeyWindow
        else {
            hide()
            return
        }
        let action = model.items[index].action
        hide()
        action?()
    }
    private func receive(_ event: NSEvent) -> NSEvent? {
        guard let panel, let model, let owner, owner.window === parent, panel.isVisible else {
            hide()
            return event
        }
        if event.type != .keyDown {
            if event.window !== panel { hide() }
            return event
        }
        guard event.window === parent else {
            hide()
            return event
        }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            hide()
            return event
        }
        switch event.keyCode {
        case 53: hide()
        case 125: model.selection.move(forward: true)
        case 126: model.selection.move(forward: false)
        case 115: model.selection.edge(last: false)
        case 119: model.selection.edge(last: true)
        case 36, 76: if let index = model.selection.index { choose(index) }
        default:
            hide()
            return event
        }
        return nil
    }
}

private final class ContextPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private final class ContextHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
private struct ContextMenuContent: View {
    @Bindable var model: ContextMenuModel
    @Environment(\.displayScale) private var scale
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.items.indices, id: \.self) { index in
                        let item = model.items[index]
                        if item.isSeparator {
                            Rectangle().fill(WorkbenchColors.tabBorder).frame(height: 1 / scale)
                                .padding(.horizontal, 8).frame(height: 9)
                        } else {
                            Button {
                                model.choose(index)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: item.symbol.isEmpty ? "circle" : item.symbol)
                                        .opacity(item.symbol.isEmpty ? 0 : 1).frame(width: 16)
                                    Text(item.title).lineLimit(1)
                                    Spacer(minLength: 20)
                                    Text(item.shortcut).foregroundStyle(WorkbenchColors.secondary)
                                        .fixedSize(horizontal: true, vertical: false)
                                }.font(.system(size: 12.5)).padding(.horizontal, 8).frame(height: 28)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        model.selection.index == index ? WorkbenchColors.selection : .clear,
                                        in: RoundedRectangle(cornerRadius: 4)
                                    )
                                    .contentShape(Rectangle())
                            }.buttonStyle(WorkbenchButtonStyle(active: model.selection.index == index))
                                .disabled(!item.enabled)
                                .onHover { over in if over { model.selection.select(index) } }
                                .accessibilityLabel(item.title).accessibilityHint(item.shortcut).id(index)
                        }
                    }
                }.padding(6)
            }.scrollIndicators(.hidden)
                .onChange(of: model.selection.index) { _, value in if let value { proxy.scrollTo(value) } }
        }.foregroundStyle(WorkbenchColors.text)
            .background(WorkbenchColors.chrome, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(WorkbenchColors.tabBorder, lineWidth: 1 / scale)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
