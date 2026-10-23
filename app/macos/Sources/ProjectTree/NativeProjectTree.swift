import AppKit
import HyCodeWorkspace
import SwiftUI

/// A native, row-virtualized outline. Expansion requests data; datasource callbacks never do I/O.
struct NativeProjectTree: NSViewRepresentable {
    let store: WorkbenchStore
    let revision: Int
    let visible: Bool
    let selectedPath: String?

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> ProjectTreeScrollContainer {
        let outline = ProjectTreeOutline()
        let column = NSTableColumn(identifier: .init("name"))
        column.minWidth = 0
        column.maxWidth = .greatestFiniteMagnitude
        column.resizingMask = []
        outline.columnAutoresizingStyle = .noColumnAutoresizing
        outline.autoresizesOutlineColumn = false
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.cornerView = nil
        outline.rowHeight = WorkbenchMetrics.rowHeight
        outline.indentationPerLevel = 16
        outline.intercellSpacing = NSSize(width: 0, height: 0)
        outline.style = .plain
        outline.selectionHighlightStyle = .regular
        outline.backgroundColor = WorkbenchColors.nativePanel
        outline.focusRingType = .none
        outline.allowsEmptySelection = true
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.doubleClick(_:))
        outline.setAccessibilityLabel("项目文件树")
        outline.makeContextMenu = { [weak coordinator = context.coordinator] row in
            coordinator?.contextMenu(for: row)
        }
        let scroll = ProjectTreeScrollContainer(outline: outline)
        context.coordinator.outline = outline
        return scroll
    }

    func updateNSView(_ scroll: ProjectTreeScrollContainer, context: Context) {
        scroll.setAccessibilityHidden(!visible)
        context.coordinator.outline?.isEnabled = visible
        if !visible, let window = scroll.window, let responder = window.firstResponder as? NSView,
            responder === scroll || responder.isDescendant(of: scroll)
        {
            window.makeFirstResponder(nil)
        }
        context.coordinator.update(revision: revision)
        context.coordinator.select(path: selectedPath)
    }

    @MainActor final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        let store: WorkbenchStore
        weak var outline: ProjectTreeOutline?
        private var nodes: [String: Node] = [:]
        private var childCache: [String: [Node]] = [:]
        private var lastRevision = -1
        private var lastCollapseRevision = 0
        private var updating = false
        private var initialized = false
        private var lastReset = -1
        private var directoryRevisions: [String: Int] = [:]
        private var expandedPaths: Set<String> = [""]
        private var knownChildren: [String: Set<String>] = [:]
        private var symbolImages: [String: NSImage] = [:]

        init(store: WorkbenchStore) { self.store = store }

        private var root: Node {
            node(WorkspaceEntry(name: store.projectName, relativePath: "", kind: .directory))
        }
        private func node(_ entry: WorkspaceEntry) -> Node {
            if let existing = nodes[entry.relativePath] {
                if existing.entry.name != entry.name {
                    existing.measuredWidth = nil
                    existing.expandedWidth = nil
                }
                existing.entry = entry
                return existing
            }
            let item = Node(entry: entry)
            nodes[entry.relativePath] = item
            return item
        }
        private func status(_ parent: String, title: String, retry: Bool = false) -> Node {
            let key = "\0status/" + parent
            let result = nodes[key] ?? Node(entry: WorkspaceEntry(name: title, relativePath: key, kind: .other))
            if result.entry.name != title {
                result.measuredWidth = nil
                result.expandedWidth = nil
            }
            result.entry = WorkspaceEntry(name: title, relativePath: key, kind: .other)
            result.statusParent = parent
            result.retry = retry
            nodes[key] = result
            return result
        }
        private func children(_ parent: Node) -> [Node] {
            let path = parent.entry.relativePath
            if let cached = childCache[path] { return cached }
            let result: [Node]
            if let snapshot = store.snapshots[path] {
                let widths = store.treeNameWidths[path, default: [:]]
                var children = snapshot.entries.map { entry in
                    let child = node(entry)
                    if child.measuredWidth == nil, let width = widths[entry.relativePath] {
                        child.measuredWidth = ProjectTreeCell.contentWidth(nameWidth: width)
                    }
                    return child
                }
                if snapshot.truncated || snapshot.skipped > 0 {
                    children.append(
                        status(path, title: snapshot.truncated ? "目录达到上限，显示部分项目" : "\(snapshot.skipped) 项无法读取"))
                }
                result = children
            } else if let error = store.errors[path] {
                result = [status(path, title: error + " · 双击重试", retry: true)]
            } else {
                result = [status(path, title: "正在读取…")]
            }
            childCache[path] = result
            return result
        }

        func update(revision: Int) {
            guard let outline, revision != lastRevision else { return }
            let interval = WorkbenchPerformance.begin("TreeBranchReload")
            defer { WorkbenchPerformance.end("TreeBranchReload", interval) }
            let reset = !initialized || lastReset != store.treeResetRevision
            let collapsing = lastCollapseRevision != store.treeCollapseRevision
            lastCollapseRevision = store.treeCollapseRevision
            lastReset = store.treeResetRevision
            lastRevision = revision
            let changed = store.directoryRevisions.keys.filter {
                directoryRevisions[$0] != store.directoryRevisions[$0]
            }
            .sorted { $0.count < $1.count }
            directoryRevisions = store.directoryRevisions
            updating = true
            defer { updating = false }
            if reset || collapsing {
                for node in nodes.values { node.expandedWidth = nil }
            }
            if collapsing {
                expandedPaths = [""]
                outline.collapseItem(nil, collapseChildren: true)
            }
            for path in changed {
                invalidateWidth(path)
                childCache[path] = nil
                if let snapshot = store.snapshots[path] {
                    nodes.removeValue(forKey: "\0status/" + path)
                    let paths = Set(snapshot.entries.map(\.relativePath))
                    for removed in knownChildren[path, default: []].subtracting(paths) { evictSubtree(removed) }
                    knownChildren[path] = paths
                }
            }
            if reset {
                childCache.removeAll(keepingCapacity: true)
                outline.reloadData()
                initialized = true
            } else {
                for path in changed {
                    guard let parent = nodes[path], outline.row(forItem: parent) >= 0,
                        outline.isItemExpanded(parent)
                    else { continue }
                    outline.reloadItem(parent, reloadChildren: true)
                }
            }
            for path in expandedPaths.sorted(by: { $0.count < $1.count }) {
                let item = path.isEmpty ? root : nodes[path]
                if let item, outline.row(forItem: item) >= 0 {
                    if !outline.isItemExpanded(item) { outline.expandItem(item) }
                    // reloadData can preserve AppKit's expanded state, so expandItem
                    // may not call shouldExpandItem. Restore its read independently.
                    requestExpansion(path)
                }
            }
            updateContentWidth()
        }

        private func invalidateWidth(_ path: String) {
            var path = path
            while true {
                nodes[path]?.expandedWidth = nil
                guard !path.isEmpty else { return }
                path = path.split(separator: "/").dropLast().joined(separator: "/")
            }
        }

        private func updateContentWidth() {
            guard let outline else { return }
            outline.contentWidth = expandedWidth(of: root, level: 0)
        }

        private func expandedWidth(of node: Node, level: Int) -> CGFloat {
            if let cached = node.expandedWidth { return cached }
            let path = node.entry.relativePath
            let measured: CGFloat
            if let cached = node.measuredWidth {
                measured = cached
            } else {
                let font = ProjectTreeCell.nameFont(root: path.isEmpty)
                let nameWidth = (node.entry.name as NSString).size(withAttributes: [.font: font]).width
                // Same insets, icon and spacing as the cell; reserve 4pt per text
                // field for its intrinsic cell insets rather than truncating glyphs.
                measured = ProjectTreeCell.contentWidth(nameWidth: nameWidth)
                node.measuredWidth = measured
            }
            // Include disclosure and indentation, even for deeply nested files.
            var width = measured + CGFloat(level + 1) * (outline?.indentationPerLevel ?? 16)
            if node.entry.isDirectory, expandedPaths.contains(path) {
                for child in children(node) { width = max(width, expandedWidth(of: child, level: level + 1)) }
            }
            node.expandedWidth = width
            return width
        }

        private func evictSubtree(_ path: String) {
            // Follow the parent index instead of filtering every cache per removed
            // child: deleting N siblings stays linear in the removed subtree.
            var pending = [path]
            while let removed = pending.popLast() {
                if let children = knownChildren.removeValue(forKey: removed) {
                    pending.append(contentsOf: children)
                }
                nodes.removeValue(forKey: removed)
                nodes.removeValue(forKey: "\0status/" + removed)
                childCache.removeValue(forKey: removed)
                expandedPaths.remove(removed)
            }
        }

        private func requestExpansion(_ path: String) {
            guard store.snapshots[path] == nil, store.errors[path] == nil,
                !store.loadingPaths.contains(path)
            else { return }
            let session = store.sessionID
            Task { @MainActor [weak store] in
                guard let store, store.sessionID == session else { return }
                store.requestDirectory(path)
            }
        }

        func select(path: String?) {
            guard let outline, let path, let item = nodes[path] else { return }
            let row = outline.row(forItem: item)
            guard row >= 0, outline.selectedRow != row else { return }
            updating = true
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            updating = false
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !updating, let item = notification.userInfo?["NSObject"] as? Node else { return }
            let path = item.entry.relativePath
            expandedPaths.remove(path)
            invalidateWidth(path)
            updateContentWidth()
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !updating, let item = notification.userInfo?["NSObject"] as? Node else { return }
            let path = item.entry.relativePath
            expandedPaths.insert(path)
            invalidateWidth(path)
            updateContentWidth()
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let parent = item as? Node else { return 1 }
            return parent.entry.isDirectory ? children(parent).count : 0
        }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let parent = item as? Node else { return root }
            return children(parent)[index]
        }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? Node)?.entry.isDirectory == true
        }
        func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
            guard let item = item as? Node, item.entry.isDirectory else { return false }
            let path = item.entry.relativePath
            if !updating { expandedPaths.insert(path) }
            requestExpansion(path)
            return true
        }
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            (item as? Node)?.statusParent == nil
        }
        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            ProjectRowView()
        }
        func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
            guard let item = outlineView.item(atRow: row) as? Node else { return }
            rowView.toolTip = tooltip(for: item)
        }
        func outlineView(_ outlineView: NSOutlineView, didRemove rowView: NSTableRowView, forRow row: Int) {
            rowView.toolTip = nil
        }
        private func tooltip(for item: Node) -> String {
            guard item.statusParent == nil, let root = store.rootURL else { return item.entry.name }
            return item.entry.url(relativeTo: root).path
        }

        func contextMenu(for row: Int) -> [WorkbenchMenuItem]? {
            guard let outline, let item = outline.item(atRow: row) as? Node,
                item.statusParent == nil, let root = store.rootURL
            else { return nil }
            let entry = item.entry
            let session = store.sessionID
            let url = entry.url(relativeTo: root)
            // Capture the clicked entry, not the editor's current selection.
            // Delayed menu actions from an old workspace are no-ops.
            func action(_ body: @escaping (Coordinator) -> Void) -> () -> Void {
                { [weak self] in
                    guard let self, self.store.sessionID == session else { return }
                    body(self)
                }
            }
            var items: [WorkbenchMenuItem] = []
            if entry.isDirectory {
                let expanded = outline.isItemExpanded(item)
                items.append(
                    WorkbenchMenuItem(
                        title: expanded ? "折叠目录" : "展开目录",
                        action: action { owner in
                            guard let outline = owner.outline, let current = owner.nodes[entry.relativePath] else {
                                return
                            }
                            if outline.isItemExpanded(current) {
                                outline.collapseItem(current)
                            } else {
                                outline.expandItem(current)
                            }
                        }))
            } else {
                items.append(WorkbenchMenuItem(title: "打开", action: action { $0.store.open(entry, preview: false) }))
            }
            items.append(
                WorkbenchMenuItem(
                    title: "在访达中显示",
                    action: action { _ in
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }))
            items.append(.separator)
            items.append(
                WorkbenchMenuItem(
                    title: "复制路径/引用",
                    children: [
                        WorkbenchMenuItem(title: "复制完整路径", action: action { _ in Self.copy(url.path) }),
                        WorkbenchMenuItem(
                            title: "复制相对路径", action: action { _ in Self.copy(entry.projectRelativePath) }),
                        WorkbenchMenuItem(
                            title: entry.isDirectory ? "复制目录名" : "复制文件名",
                            action: action { _ in
                                Self.copy(entry.name)
                            }),
                    ]))
            items.append(.separator)
            items.append(
                WorkbenchMenuItem(
                    title: "文件信息",
                    action: action { owner in
                        owner.store.selectedEntry = entry
                        if !owner.store.docking.isVisible(.information) { owner.store.docking.toggle(.information) }
                    }))
            items.append(
                WorkbenchMenuItem(
                    title: entry.isDirectory ? "刷新此目录" : "刷新所在目录",
                    action: action { owner in
                        let directory =
                            entry.isDirectory
                            ? entry.relativePath
                            : entry.relativePath.split(separator: "/")
                                .dropLast().joined(separator: "/")
                        owner.store.requestDirectory(directory, force: true)
                    }))
            return items
        }
        private static func copy(_ value: String) {
            // Only reached from the user's explicit native-menu action.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let outline, outline.selectedRow >= 0,
                let item = outline.item(atRow: outline.selectedRow) as? Node, item.statusParent == nil
            else { return }
            store.open(item.entry, preview: true)
        }
        @objc func doubleClick(_ sender: NSOutlineView) {
            guard sender.clickedRow >= 0, let item = sender.item(atRow: sender.clickedRow) as? Node else { return }
            if let parent = item.statusParent {
                if item.retry { store.requestDirectory(parent, force: true) }
                return
            }
            store.open(item.entry, preview: false)
            if item.entry.isDirectory { sender.expandItem(item) }
        }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? Node else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("ProjectTreeCell")
            let cell: ProjectTreeCell
            if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? ProjectTreeCell {
                cell = reused
            } else {
                cell = ProjectTreeCell(frame: .zero)
                cell.identifier = identifier
            }
            cell.textField?.stringValue = item.entry.name
            cell.textField?.textColor =
                item.statusParent == nil
                ? WorkbenchColors.nativeText : WorkbenchColors.nativeSecondary
            cell.textField?.font = ProjectTreeCell.nameFont(root: item.entry.relativePath.isEmpty)
            let symbol = item.statusParent == nil ? item.entry.symbol : "ellipsis"
            if symbolImages[symbol] == nil {
                symbolImages[symbol] = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            cell.imageView?.image = symbolImages[symbol]
            cell.imageView?.contentTintColor = item.entry.symbolColor
            cell.toolTip = tooltip(for: item)
            cell.setAccessibilityLabel(item.entry.name)
            return cell
        }
    }
}

@MainActor private final class Node: NSObject {
    var entry: WorkspaceEntry
    var statusParent: String?
    var retry = false
    var measuredWidth: CGFloat?
    var expandedWidth: CGFloat?
    init(entry: WorkspaceEntry) { self.entry = entry }
}
