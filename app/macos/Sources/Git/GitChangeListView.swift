import AppKit
import HyCodeWorkspace
import SwiftUI

struct GitChangeListView: NSViewRepresentable {
    let rows: [GitChangeListRow]
    let selected: String?
    let selectionState: (String) -> NSControl.StateValue
    let selecting: Set<String>
    let stagedMode: Bool
    let writing: Bool
    let loading: Bool
    let projectName: String
    let show: (GitChangeListRow) -> Void
    let openSource: (String) -> Void
    let choose: (GitStatusEntry) -> Void
    let stage: (GitChangeListRow) -> Void
    let toggleGroup: (String) -> Void
    let menu: (GitStatusEntry) -> [WorkbenchMenuItem]
    @Environment(\.colorScheme) private var scheme
    func makeNSView(context: Context) -> GitChangeListScroll { GitChangeListScroll() }
    func updateNSView(_ view: GitChangeListScroll, context: Context) {
        view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        view.configure(self)
    }
}

/// No SwiftUI row overlays or guessed scroll offsets. AppKit's row(at:),
/// rect(ofRow:), row view, selection and cell controls share one coordinate space.
@MainActor final class GitChangeListScroll: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = GitChangeTable()
    private var model: GitChangeListView?
    private var updating = false
    private var tiling = false
    private var requestedSelection: String?
    private var pendingReveal: String?
    override init(frame: NSRect) {
        super.init(frame: frame)
        borderType = .noBorder
        WorkbenchScroller.configure(self, horizontal: false)
        table.headerView = nil
        table.autoresizingMask = [.width]
        table.rowHeight = GitStyle.rowHeight
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.selectionHighlightStyle = .regular
        table.backgroundColor = WorkbenchColors.nativePanel
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.doubleAction = #selector(openFile)
        table.allowsMultipleSelection = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("change"))
        column.minWidth = 80
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.contextItems = { [weak self] row in
            guard let self, let model, !model.loading, model.rows.indices.contains(row),
                let entry = model.rows[row].entry
            else {
                return []
            }
            return model.menu(entry)
        }
        table.space = { [weak self] in self?.toggleSelected() }
        documentView = table
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: contentView)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func tile() {
        guard !tiling else { return }
        tiling = true
        defer { tiling = false }
        super.tile()
        let width = max(80, contentView.bounds.width)
        if table.frame.width != width { table.setFrameSize(NSSize(width: width, height: table.frame.height)) }
        if table.tableColumns.first?.width != width { table.tableColumns.first?.width = width }
        table.updateHover()
    }
    func configure(_ value: GitChangeListView) {
        updating = true
        defer { updating = false }
        let old = model
        let top = table.row(at: NSPoint(x: 0, y: contentView.bounds.minY))
        let topID = top >= 0 && old?.rows.indices.contains(top) == true ? old?.rows[top].id : nil
        let topOffset = top >= 0 ? contentView.bounds.minY - table.rect(ofRow: top).minY : 0
        if value.selected != requestedSelection {
            requestedSelection = value.selected
            pendingReveal = value.selected
        }
        let oldSelected =
            table.selectedRow >= 0 && (old?.rows.indices.contains(table.selectedRow) == true)
            ? old?.rows[table.selectedRow].id : nil
        model = value
        table.isEnabled = !value.loading
        table.alphaValue = value.loading ? 0 : 1
        table.backgroundColor = WorkbenchColors.nativePanel
        let structural = old?.rows != value.rows || old?.stagedMode != value.stagedMode
        if structural {
            table.reloadData()
        } else {
            table.enumerateAvailableRowViews { rowView, row in
                if let cell = rowView.view(atColumn: 0) as? GitChangeCell { self.configure(cell, row: row) }
                rowView.needsDisplay = true
            }
        }
        let identity = value.selected ?? oldSelected
        var revealed = false
        if let row = value.rows.firstIndex(where: { $0.id == identity }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if identity == pendingReveal, !value.loading {
                table.scrollRowToVisible(row)
                pendingReveal = nil
                revealed = true
            }
        } else {
            table.deselectAll(nil)
        }
        if structural, !revealed, !value.loading, let topID,
            let top = value.rows.firstIndex(where: { $0.id == topID })
        {
            let bounds = contentView.bounds
            let restored = contentView.constrainBoundsRect(
                NSRect(
                    x: bounds.minX,
                    y: table.rect(ofRow: top).minY + topOffset, width: bounds.width, height: bounds.height))
            contentView.scroll(to: restored.origin)
            reflectScrolledClipView(contentView)
        }
        table.updateHover()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { model?.rows.count ?? 0 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell =
            tableView.makeView(withIdentifier: GitChangeCell.identifier, owner: nil) as? GitChangeCell
            ?? GitChangeCell()
        configure(cell, row: row)
        return cell
    }
    private func configure(_ cell: GitChangeCell, row: Int) {
        guard let model, model.rows.indices.contains(row) else { return }
        let item = model.rows[row]
        cell.configure(
            item, stagedMode: model.stagedMode, projectName: model.projectName,
            selected: item.entry.map { model.selectionState($0.path) } ?? .off,
            enabled: !model.writing && !model.loading
                && item.entry.map { !$0.conflicted && !$0.submodule && !model.selecting.contains($0.path) } == true)
        cell.checkAction = { [weak self] in
            guard let model = self?.model, let current = model.rows.first(where: { $0.id == item.id }) else { return }
            if current.entry == nil {
                model.toggleGroup(current.id)
            } else if let entry = current.entry {
                model.choose(entry)
            }
        }
        cell.stageAction = { [weak self] in
            guard let model = self?.model, let current = model.rows.first(where: { $0.id == item.id }) else { return }
            model.stage(current)
        }
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = GitChangeRowView()
        view.hovered = table.hoveredRow == row
        return view
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updating, !table.handlingMouseSelection, let model, !model.loading,
            model.rows.indices.contains(table.selectedRow)
        else {
            return
        }
        let row = model.rows[table.selectedRow]
        if row.entry != nil { model.show(row) }
    }
    @objc private func clicked() {
        guard let model, !model.loading, model.rows.indices.contains(table.clickedRow) else { return }
        let row = model.rows[table.clickedRow]
        if row.entry == nil {
            model.toggleGroup(row.id)
        }
        // Reopen a selected diff after switching to a source tab.
        else {
            model.show(row)
        }
    }
    @objc private func openFile() {
        guard let model, !model.loading, model.rows.indices.contains(table.clickedRow),
            let entry = model.rows[table.clickedRow].entry
        else { return }
        model.openSource(entry.path)
    }
    private func toggleSelected() {
        guard let model, !model.loading, !model.writing, model.rows.indices.contains(table.selectedRow) else { return }
        let row = model.rows[table.selectedRow]
        if row.entry == nil {
            model.toggleGroup(row.id)
        } else if let entry = row.entry, !entry.conflicted, !entry.submodule, !model.selecting.contains(entry.path) {
            if model.stagedMode { model.stage(row) } else { model.choose(entry) }
        }
    }
    @objc private func scrolled() { table.updateHover() }
}

@MainActor private final class GitChangeTable: NSTableView {
    private(set) var handlingMouseSelection = false
    private var tracking: NSTrackingArea?
    private(set) var hoveredRow = -1
    var contextItems: (Int) -> [WorkbenchMenuItem] = { _ in [] }
    var space: () -> Void = {}
    private let popup = WorkbenchContextMenu()
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self
        )
        addTrackingArea(area)
        tracking = area
        updateHover()
    }
    func updateHover(point: NSPoint? = nil) {
        let local =
            point ?? window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) } ?? NSPoint(x: -1, y: -1)
        let next = visibleRect.contains(local) ? row(at: local) : -1
        guard next != hoveredRow else { return }
        let previous = hoveredRow
        hoveredRow = next
        for index in [previous, next] where index >= 0 && index < numberOfRows {
            if let view = rowView(atRow: index, makeIfNecessary: false) as? GitChangeRowView {
                view.hovered = index == next
                view.needsDisplay = true
            }
        }
    }
    override func mouseMoved(with event: NSEvent) { updateHover(point: convert(event.locationInWindow, from: nil)) }
    override func mouseDown(with event: NSEvent) {
        handlingMouseSelection = true
        defer { handlingMouseSelection = false }
        super.mouseDown(with: event)
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { updateHover(point: NSPoint(x: -1, y: -1)) }
    override func rightMouseDown(with event: NSEvent) {
        let index = row(at: convert(event.locationInWindow, from: nil))
        let items = contextItems(index)
        guard !items.isEmpty, let window else { return }
        popup.show(items.map(\.contextCommand), at: window.convertPoint(toScreen: event.locationInWindow), in: self)
    }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " ",
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        {
            space()
        } else {
            super.keyDown(with: event)
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { popup.hide() }
    }
}

@MainActor private final class GitChangeRowView: NSTableRowView {
    var hovered = false
    override func drawBackground(in dirtyRect: NSRect) {
        WorkbenchColors.nativePanel.setFill()
        dirtyRect.fill()
        if hovered && !isSelected {
            NSColor.labelColor.withAlphaComponent(0.055).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
    }
    override func drawSelection(in dirtyRect: NSRect) {
        WorkbenchColors.nativeText.withAlphaComponent(isEmphasized ? 0.11 : 0.07).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 1), xRadius: 4, yRadius: 4).fill()
    }
}

@MainActor private final class GitChangeCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("GitChangeCell")
    private let check = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let icon = NSImageView()
    private let folder = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let path = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let stage = NSButton()
    private var group = false
    private var stagedMode = false
    var checkAction: () -> Void = {}
    var stageAction: () -> Void = {}
    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        check.target = self
        check.action = #selector(checked)
        check.controlSize = .small
        check.allowsMixedState = true
        stage.target = self
        stage.action = #selector(staged)
        stage.isBordered = false
        stage.imagePosition = .imageOnly
        for label in [name, path, status] {
            label.isSelectable = false
            label.lineBreakMode = .byTruncatingMiddle
            label.font = .systemFont(ofSize: 12)
            label.maximumNumberOfLines = 1
        }
        path.font = .systemFont(ofSize: 11)
        status.font = .systemFont(ofSize: 10)
        name.font = .systemFont(ofSize: WorkbenchMetrics.uiFontSize)
        folder.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        folder.contentTintColor = WorkbenchColors.nativeSecondary
        for view in [check, icon, folder, name, path, status, stage] as [NSView] { addSubview(view) }
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    func configure(
        _ row: GitChangeListRow, stagedMode: Bool, projectName: String, selected: NSControl.StateValue, enabled: Bool
    ) {
        group = row.entry == nil
        self.stagedMode = stagedMode
        check.isHidden = group || stagedMode
        check.state = selected
        check.isEnabled = enabled
        check.setAccessibilityLabel("选入本次提交：" + (row.entry?.path ?? ""))
        stage.isHidden = group || !stagedMode
        stage.isEnabled = enabled
        stage.image = NSImage(
            systemSymbolName: row.staged ? "minus" : "plus", accessibilityDescription: row.staged ? "取消暂存" : "暂存已保存版本")
        path.isHidden = group
        folder.isHidden = !group
        status.isHidden = group || !stagedMode
        if let entry = row.entry {
            let ext = (entry.path as NSString).pathExtension.lowercased()
            let symbol =
                entry.conflicted
                ? "exclamationmark.triangle"
                : ["json", "json5", "jsonc"].contains(ext)
                    ? "curlybraces" : ["md", "lock"].contains(ext) ? "text.alignleft" : "doc.text"
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: entry.label)
            icon.contentTintColor =
                entry.conflicted
                ? .systemOrange
                : ["json", "json5", "jsonc"].contains(ext)
                    ? .systemPurple : ["yaml", "yml"].contains(ext) ? .systemPink : NSColor(GitStyle.fileColor(entry))
            name.stringValue = (entry.path as NSString).lastPathComponent
            name.textColor = NSColor(GitStyle.fileColor(entry))
            let directory = (entry.path as NSString).deletingLastPathComponent
            path.stringValue =
                entry.originalPath.map { $0 + " → " + entry.path }
                ?? (directory.isEmpty ? projectName : directory)
            path.textColor = WorkbenchColors.nativeSecondary
            status.stringValue =
                entry.conflicted
                ? "!"
                : entry.untracked
                    ? "?"
                    : String(row.staged ? entry.indexStatus : entry.unstaged ? entry.worktreeStatus : entry.indexStatus)
            status.textColor = WorkbenchColors.nativeSecondary
            toolTip = entry.path + " · " + entry.label
        } else {
            icon.image = NSImage(
                systemSymbolName: row.expanded ? "chevron.down" : "chevron.right",
                accessibilityDescription: row.expanded ? "折叠" : "展开")
            icon.contentTintColor = WorkbenchColors.nativeSecondary
            name.stringValue = row.title ?? ""
            name.textColor = WorkbenchColors.nativeSecondary
            toolTip = row.title
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let y = max(0, (bounds.height - 18) / 2)
        check.frame = NSRect(x: 28, y: y, width: 18, height: 18)
        let iconX: CGFloat = group ? 9 : stagedMode ? 32 : 50
        icon.frame = NSRect(x: iconX, y: y + 2, width: 14, height: 14)
        folder.frame = NSRect(x: 30, y: y + 2, width: 14, height: 14)
        let left: CGFloat = group ? 50 : iconX + 20
        let right = bounds.width - (stagedMode && !group ? 28 : 8)
        stage.frame = NSRect(x: bounds.width - 26, y: y - 1, width: 22, height: 20)
        status.frame = NSRect(x: right - 18, y: y + 1, width: 18, height: 16)
        let available = max(0, right - left - (group || !stagedMode ? 0 : 24))
        // A truncating NSTextField's intrinsic width can depend on its previous
        // narrow frame. Measure the full filename, then give the directory only
        // the remaining space; repeated reuse/layout must not shrink the name.
        let measured = (name.stringValue as NSString).size(withAttributes: [.font: name.font!]).width + 6
        let nameWidth = group ? available : min(available, measured)
        name.frame = NSRect(x: left, y: y + 1, width: nameWidth, height: 17)
        path.frame = NSRect(x: left + nameWidth + 6, y: y + 2, width: max(0, available - nameWidth - 6), height: 16)
    }
    @objc private func checked() { checkAction() }
    @objc private func staged() { stageAction() }
}
