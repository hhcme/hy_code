import AppKit
import HyCodeWorkspace
import Observation
import SwiftUI

@MainActor struct WorkbenchContextCommand {
    var title: String
    var symbol = ""
    var shortcut = ""
    var help = ""
    var enabled = true
    var checked: Bool?
    var children: [Self] = []
    var action: (() -> Void)?
    var isSeparator: Bool { action == nil && children.isEmpty && title.isEmpty }
    static var separator: Self { Self(title: "", enabled: false) }
}
extension WorkbenchMenuItem {
    var contextCommand: WorkbenchContextCommand {
        if title == "-" { return .separator }
        return WorkbenchContextCommand(
            title: title, enabled: enabled, checked: checked,
            children: children.map(\.contextCommand), action: action)
    }
}
@MainActor @Observable private final class ContextMenuModel {
    let items: [WorkbenchContextCommand]
    var selection: ContextMenuSelection
    let choose: (Int) -> Void
    let hover: (Int) -> Void
    let rowFrame: (Int, NSView) -> Void
    init(
        items: [WorkbenchContextCommand], choose: @escaping (Int) -> Void,
        hover: @escaping (Int) -> Void, rowFrame: @escaping (Int, NSView) -> Void
    ) {
        self.items = items
        selection = ContextMenuSelection(enabled: items.map { $0.enabled && !$0.isSeparator })
        self.choose = choose
        self.hover = hover
        self.rowFrame = rowFrame
    }
}

/// All app-owned menus share one non-key popup chain. Editor input keeps its
/// responder; outside clicks pass through and keyboard commands remain scoped
/// to the parent window. Commands retain their existing revision/safety guards.
@MainActor final class WorkbenchContextMenu {
    private let session = WorkbenchPopupSession()
    private struct Level {
        let model: ContextMenuModel
        let frame: CGRect
        var rows: [Int: MenuRowReference] = [:]
        var expanded: Int?
    }
    private var levels: [Level] = []
    private var screen = CGRect.zero
    var onClose: () -> Void = {}
    var isVisible: Bool { session.isVisible }
    func show(
        _ items: [WorkbenchContextCommand], at anchor: NSPoint, in view: NSView,
        dropdown: Bool = false
    ) {
        hide()
        guard !items.isEmpty, session.begin(in: view, consumeAnchorClick: dropdown) else { return }
        session.onClose = { [weak self] in
            guard let self else { return }
            levels.removeAll()
            onClose()
        }
        session.keyDown = { [weak self] event in self?.keyDown(event) ?? false }
        session.scrolled = { [weak self] depth in
            guard let self, levels.indices.contains(depth) else { return }
            trim(after: depth)
            levels[depth].expanded = nil
        }
        screen =
            NSScreen.screens.first(where: { $0.frame.contains(anchor) })?.visibleFrame
            ?? view.window?.screen?.visibleFrame ?? view.window!.frame
        let size = menuSize(items)
        let frame =
            dropdown
            ? WorkbenchPopupPlacement.dropdown(
                anchor: view.window!.convertToScreen(view.convert(view.bounds, to: nil)),
                size: size, screen: screen)
            : ContextMenuPlacement.frame(anchor: anchor, size: size, screen: screen)
        append(items, frame: frame)
    }
    func hide() {
        session.close()
        levels.removeAll()
    }
    private func menuSize(_ items: [WorkbenchContextCommand]) -> CGSize {
        let font = NSFont.systemFont(ofSize: 13)
        let contentWidth =
            items.filter { !$0.isSeparator }.map {
                ($0.title as NSString).size(withAttributes: [.font: font]).width
                    + ($0.shortcut as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 0
        return CGSize(
            width: ContextMenuMetrics.width(contentWidth: contentWidth, screenWidth: screen.width),
            height: CGFloat(items.reduce(12) { $0 + ($1.isSeparator ? 9 : 28) }))
    }
    private func append(_ source: [WorkbenchContextCommand], frame: CGRect) {
        let depth = levels.count
        let model = ContextMenuModel(
            items: Array(source.prefix(200)),
            choose: { [weak self] in self?.choose($0, depth: depth) },
            hover: { [weak self] in self?.hover($0, depth: depth) },
            rowFrame: { [weak self] index, view in
                guard let self, levels.indices.contains(depth) else { return }
                levels[depth].rows[index] = MenuRowReference(view)
            })
        levels.append(Level(model: model, frame: frame))
        if session.append(ContextMenuContent(model: model), frame: frame, label: "菜单") == nil { hide() }
    }
    private func trim(after depth: Int) {
        guard levels.count > depth + 1 else { return }
        levels.removeLast(levels.count - depth - 1)
        session.trim(to: depth + 1)
    }
    private func hover(_ index: Int, depth: Int) {
        guard levels.indices.contains(depth) else { return }
        levels[depth].model.selection.select(index)
        guard levels[depth].expanded != index else { return }
        trim(after: depth)
        levels[depth].expanded = nil
        open(index, depth: depth)
    }
    private func open(_ index: Int, depth: Int) {
        guard levels.indices.contains(depth), depth < 7,
            levels[depth].model.items.indices.contains(index)
        else { return }
        let item = levels[depth].model.items[index]
        guard item.enabled, !item.children.isEmpty else { return }
        trim(after: depth)
        levels[depth].expanded = index
        let parent = levels[depth].frame
        let above = levels[depth].model.items.prefix(index).reduce(6) { $0 + ($1.isSeparator ? 9 : 28) }
        let row =
            levels[depth].rows[index]?.screenFrame
            ?? CGRect(x: parent.minX + 6, y: parent.maxY - CGFloat(above) - 28, width: parent.width - 12, height: 28)
        append(
            item.children,
            frame: WorkbenchPopupPlacement.submenu(
                parent: parent, row: row,
                size: menuSize(item.children), screen: screen))
    }
    private func choose(_ index: Int, depth: Int) {
        guard session.isVisible, let owner = session.owner, owner.window === session.parent,
            session.parent?.isKeyWindow == true, levels.indices.contains(depth),
            levels[depth].model.items.indices.contains(index)
        else {
            hide()
            return
        }
        let item = levels[depth].model.items[index]
        guard item.enabled else { return }
        if !item.children.isEmpty {
            open(index, depth: depth)
            return
        }
        hide()
        item.action?()
    }
    private func keyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
            let model = levels.last?.model
        else { return false }
        let depth = levels.count - 1
        switch event.keyCode {
        case 48: model.selection.move(forward: !event.modifierFlags.contains(.shift))
        case 125: model.selection.move(forward: true)
        case 126: model.selection.move(forward: false)
        case 115: model.selection.edge(last: false)
        case 119: model.selection.edge(last: true)
        case 124: if let index = model.selection.index { open(index, depth: depth) }
        case 123:
            if depth > 0 {
                trim(after: depth - 1)
                levels[depth - 1].expanded = nil
            }
        case 36, 76: if let index = model.selection.index { choose(index, depth: depth) }
        default: return false
        }
        return true
    }
}
private struct ContextMenuContent: View {
    @Bindable var model: ContextMenuModel
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.items.indices, id: \.self) { index in
                        let item = model.items[index]
                        if item.isSeparator {
                            WorkbenchSeparator(visible: true).padding(.horizontal, 8).frame(height: 9)
                        } else {
                            Button {
                                model.choose(index)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(
                                        systemName: item.checked == true
                                            ? "checkmark" : (item.symbol.isEmpty ? "circle" : item.symbol)
                                    )
                                    .opacity(item.checked == true || !item.symbol.isEmpty ? 1 : 0).frame(width: 16)
                                    Text(item.title).lineLimit(1)
                                    Spacer(minLength: 16)
                                    Text(item.shortcut).foregroundStyle(WorkbenchColors.secondary)
                                        .fixedSize(horizontal: true, vertical: false)
                                    if !item.children.isEmpty {
                                        Image(systemName: "chevron.right").font(.system(size: 9)).frame(width: 10)
                                    }
                                }.font(.system(size: 13)).padding(.horizontal, 8).frame(height: 28)
                                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(WorkbenchButtonStyle(active: model.selection.index == index))
                                .disabled(!item.enabled)
                                .onHover { if $0 { model.hover(index) } }
                                .background(MenuRowAnchor { model.rowFrame(index, $0) })
                                .help(item.help).accessibilityLabel(item.title).accessibilityHint(item.shortcut).id(
                                    index)
                        }
                    }
                }.padding(6)
            }.scrollIndicators(.hidden)
                .onChange(of: model.selection.index) { _, value in if let value { proxy.scrollTo(value) } }
        }.foregroundStyle(WorkbenchColors.text).workbenchPopupSurface()
    }
}
@MainActor private final class MenuRowReference {
    weak var view: NSView?
    init(_ view: NSView) { self.view = view }
    var screenFrame: CGRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}
private struct MenuRowAnchor: NSViewRepresentable {
    let frameChanged: (NSView) -> Void
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) { frameChanged(view) }
    final class Marker: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
