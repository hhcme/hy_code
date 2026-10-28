import AppKit
import HyCodeWorkspace

@MainActor final class GitDiffSplit: NSSplitView, NSSplitViewDelegate {
    private let left = GitSnapshotEditor()
    private let right = GitSnapshotEditor()
    private let leftPane = GitDiffPane()
    private let rightPane = GitDiffPane()
    private let workingLayout = GitTextLayout()
    private weak var workingEditor: NativeTextEditor?
    private var model: GitDiff?
    private var unified = false
    private var aligned = false
    private var syncing = false
    private var arranging = false
    private var ratio = UserDefaults.standard.object(forKey: "git.diff.ratio") as? Double ?? 0.5
    private var target: Int?
    private var observed: [NSClipView] = []
    private var origins: [ObjectIdentifier: NSPoint] = [:]
    private var needsInitialScroll = true
    var presentationChanged: () -> Void = {}
    var leftGutter: GitDiffGutter { leftPane.gutter }
    var rightGutter: GitDiffGutter { rightPane.gutter }
    override var dividerThickness: CGFloat { unified ? 0 : 1 }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isVertical = true
        dividerStyle = .thin
        delegate = self
        addArrangedSubview(leftPane)
        addArrangedSubview(rightPane)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    func configure(
        _ diff: GitDiff, left leftSource: GitTextComparison.Side, right rightSource: GitTextComparison.Side,
        unified: Bool, target: Int?, document: EditorDocument?, aligned: Bool,
        selection: GitDiffSelection?, actions: GitHunkActions, numbers: Bool, syntax: Bool
    ) {
        let newFile = model?.path != diff.path || model?.comparison != diff.comparison
        if newFile || self.unified != unified { needsInitialScroll = true }
        model = diff
        self.aligned = aligned
        left.scroll.leadingVerticalScroller = !unified
        if self.unified != unified {
            self.unified = unified
            if unified { rightPane.removeFromSuperview() } else { addArrangedSubview(rightPane) }
        }
        let editable = !unified && diff.text != nil && document?.largeFile == nil ? document?.editor : nil
        if workingEditor !== editable {
            detachWorkingEditor()
            workingEditor = editable
        }
        let rows = unified ? diff.unifiedRows.count + 1 : diff.text?.rowCount ?? diff.rows.count + 1
        left.configure(
            leftSource, width: unified ? max(diff.leftWidth, diff.rightWidth) + 32 : diff.leftWidth,
            rows: rows, path: diff.path, numbers: false, syntax: syntax && !unified,
            aligned: document == nil || aligned)
        leftPane.setScroll(left.scroll)
        if let editable {
            // A source host may have detached this presentation while switching
            // tabs; install it again only for this active comparison host.
            editable.presentComparison(workingLayout)
            workingLayout.configure(side: aligned ? rightSource : nil, width: diff.rightWidth, rows: rows)
            rightPane.setScroll(editable.scroll)
            editable.scroll.appearance = nil
            editable.applyAppearance()
            editable.presentation?.configure(lineNumbers: false, syntaxHighlight: syntax)
        } else {
            right.configure(
                rightSource, width: diff.rightWidth, rows: rows, path: diff.path, numbers: false, syntax: syntax)
            rightPane.setScroll(right.scroll)
        }
        let fullSource = !unified && diff.text != nil
        let blocks = fullSource && aligned ? diff.text?.blocks ?? [] : []
        let showRestore = fullSource && document != nil
        func gutterWidth(_ count: Int, actions: Bool) -> CGFloat {
            numbers ? max(48, CGFloat(String(count).count) * 8 + 24) : actions ? 22 : 0
        }
        leftPane.configureGutter(
            trailing: !unified, visible: numbers || showRestore,
            width: unified ? 82 : gutterWidth(leftSource.index.count, actions: showRestore))
        rightPane.configureGutter(
            trailing: false, visible: !unified && (numbers || (fullSource && actions.showsSelection)),
            width: gutterWidth(rightSource.index.count, actions: actions.showsSelection))
        leftPane.gutter.connected = fullSource
        rightPane.gutter.connected = fullSource
        leftPane.gutter.allowsDividerTracking = !unified
        rightPane.gutter.allowsDividerTracking = !unified
        let projected = unified ? diff.unifiedRows : diff.rows
        leftPane.gutter.configure(
            textView: left.textView, index: { [weak left] in left?.lineIndex ?? TextLineIndex() },
            label: { line in
                guard numbers else { return nil }
                if fullSource { return leftSource.text.isEmpty ? nil : String(line + 1) }
                guard projected.indices.contains(line) else { return nil }
                let row = projected[line]
                if unified {
                    return (row.leftNumber.map(String.init) ?? "") + "  " + (row.rightNumber.map(String.init) ?? "")
                }
                return row.leftNumber.map(String.init)
            }, color: { [weak left] in left?.layout.lineColor(at: $0) })
        if let editable {
            rightPane.gutter.configure(
                textView: editable.textView,
                index: { [weak editable] in editable?.presentation?.gutter.lines ?? TextLineIndex() },
                label: { numbers && !rightSource.text.isEmpty ? String($0 + 1) : nil },
                color: { [weak workingLayout] in workingLayout?.lineColor(at: $0) })
        } else {
            rightPane.gutter.configure(
                textView: right.textView, index: { [weak right] in right?.lineIndex ?? TextLineIndex() },
                label: { line in
                    guard numbers else { return nil }
                    if fullSource { return rightSource.text.isEmpty ? nil : String(line + 1) }
                    guard diff.rows.indices.contains(line) else { return nil }
                    return diff.rows[line].rightNumber.map(String.init)
                }, color: { [weak right] in right?.layout.lineColor(at: $0) })
        }
        leftPane.gutter.configureActions(
            blocks: showRestore ? blocks : [], left: true, actions: actions,
            layout: left.layout)
        rightPane.gutter.configureActions(
            blocks: actions.showsSelection ? blocks : [], left: false, actions: actions,
            layout: editable == nil ? right.layout : workingLayout)
        let unsaved = document?.isDirty == true
        let rightTitle = editable == nil ? diff.rightTitle : "工作区（\(unsaved ? "未保存" : "已保存") · 可编辑）"
        leftPane.header.configure(
            title: unified ? "统一差异（只读）" : diff.leftTitle, path: diff.path, selection: unified ? selection : nil)
        rightPane.header.configure(title: rightTitle, path: "", selection: selection, editable: editable != nil)
        observeScrolls()
        layoutColumns()
        if needsInitialScroll, aligned, !unified, let comparison = diff.text,
            !comparison.right.text.isEmpty,
            let position = (editable == nil ? right.layout : workingLayout).visiblePosition()
        {
            syncing = true
            left.layout.scroll(to: GitDiffBlock.map(position, fromLeft: false, blocks: comparison.blocks))
            syncing = false
            needsInitialScroll = false
        }
        if self.target != target || newFile {
            self.target = target
            if let target {
                syncing = true
                defer { syncing = false }
                if !unified, let block = diff.text?.blocks.first(where: { $0.id == target }) {
                    left.layout.reveal(line: block.left.lowerBound)
                    (editable == nil ? right.layout : workingLayout).reveal(line: block.right.lowerBound)
                } else {
                    let index = (unified ? diff.unifiedRows : diff.rows).firstIndex(where: { $0.id == target }) ?? 0
                    left.layout.reveal(line: index)
                    if !unified { right.layout.reveal(line: index) }
                }
            }
        }
        needsDisplay = true
        presentationChanged()
    }
    func detach() {
        for clip in observed {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: clip)
        }
        observed = []
        origins = [:]
        detachWorkingEditor()
        left.suspend()
        right.suspend()
        model = nil
        aligned = false
        leftPane.gutter.isHidden = true
        rightPane.gutter.isHidden = true
        presentationChanged()
    }
    private func detachWorkingEditor() {
        if let workingEditor, workingEditor.comparison?.id == workingLayout.id { workingEditor.presentComparison(nil) }
        workingEditor = nil
    }
    private func observeScrolls() {
        let clips = [leftPane.scroll, rightPane.scroll].compactMap { $0?.contentView }
        guard clips.count != observed.count || !zip(clips, observed).allSatisfy({ $0 === $1 }) else { return }
        for clip in observed {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: clip)
        }
        observed = clips
        origins = Dictionary(uniqueKeysWithValues: clips.map { (ObjectIdentifier($0), $0.bounds.origin) })
        for clip in clips {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: clip)
        }
    }
    override func resizeSubviews(withOldSize oldSize: NSSize) { layoutColumns() }
    private func layoutColumns() {
        guard !arranging else { return }
        arranging = true
        defer { arranging = false }
        if unified {
            leftPane.frame = bounds
        } else {
            let available = max(0, bounds.width - dividerThickness)
            let width = (available * ratio).rounded()
            leftPane.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
            rightPane.frame = NSRect(
                x: width + dividerThickness, y: 0, width: max(0, available - width), height: bounds.height)
        }
        for pane in [leftPane, rightPane] {
            pane.needsLayout = true
            pane.layoutSubtreeIfNeeded()
        }
        needsDisplay = true
        presentationChanged()
    }
    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !arranging, !unified, bounds.width > dividerThickness else { return }
        ratio = min(0.85, max(0.15, leftPane.frame.width / (bounds.width - dividerThickness)))
        for pane in [leftPane, rightPane] {
            pane.layoutSubtreeIfNeeded()
            pane.gutter.refreshActions()
        }
        needsDisplay = true
        presentationChanged()
    }
    func splitView(
        _ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int
    ) -> NSRect {
        unified ? .zero : drawnRect.insetBy(dx: -4, dy: 0)
    }
    func splitView(
        _ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        min(bounds.width * 0.85, max(bounds.width * 0.15, proposedPosition))
    }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        UserDefaults.standard.set(ratio, forKey: "git.diff.ratio")
    }
    @objc private func scrolled(_ notification: Notification) {
        leftPane.gutter.needsDisplay = true
        rightPane.gutter.needsDisplay = true
        leftPane.gutter.refreshActions()
        rightPane.gutter.refreshActions()
        needsDisplay = true
        presentationChanged()
        guard let source = notification.object as? NSClipView else { return }
        let previous = origins.updateValue(source.bounds.origin, forKey: ObjectIdentifier(source))
        guard !syncing, !arranging, !unified, aligned, previous?.y != source.bounds.minY,
            let a = leftPane.scroll, let b = rightPane.scroll
        else { return }
        syncing = true
        defer { syncing = false }
        let fromLeft = source === a.contentView
        if let comparison = model?.text,
            fromLeft ? comparison.left.text.isEmpty : comparison.right.text.isEmpty
        {
            return
        }
        let sourceLayout = fromLeft ? left.layout : workingEditor == nil ? right.layout : workingLayout
        let targetLayout = fromLeft ? workingEditor == nil ? right.layout : workingLayout : left.layout
        if let comparison = model?.text, let position = sourceLayout.visiblePosition() {
            targetLayout.scroll(to: GitDiffBlock.map(position, fromLeft: fromLeft, blocks: comparison.blocks))
        } else {
            let destination = fromLeft ? b : a
            let bounds = destination.contentView.bounds
            let constrained = destination.contentView.constrainBoundsRect(
                NSRect(x: bounds.minX, y: source.bounds.minY, width: bounds.width, height: bounds.height))
            destination.contentView.scroll(to: constrained.origin)
            destination.reflectScrolledClipView(destination.contentView)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        WorkbenchColors.nativePanel.setFill()
        dirtyRect.fill()
        if !unified {
            drawDivider(in: NSRect(x: leftPane.frame.maxX, y: 0, width: dividerThickness, height: bounds.height))
        }
    }
    override func drawDivider(in rect: NSRect) {
        WorkbenchColors.nativeBorder.withAlphaComponent(0.6).setFill()
        rect.fill()
    }
    func connectionRect(in view: NSView) -> NSRect? {
        guard !unified, model?.text != nil,
            let a = leftPane.scroll?.contentView, let b = rightPane.scroll?.contentView
        else { return nil }
        return GitConnectionBand.bridge(
            leftViewport: a.convert(a.bounds, to: view),
            rightViewport: b.convert(b.bounds, to: view))
    }
    func gutterFrames(in view: NSView) -> (NSRect, NSRect) {
        func frame(_ pane: GitDiffPane) -> NSRect {
            guard !pane.gutter.isHidden, let clip = pane.scroll?.contentView else { return .zero }
            let rail = pane.convert(pane.gutterFrame, to: view)
            let body = clip.convert(clip.bounds, to: view)
            return NSRect(x: rail.minX, y: body.minY, width: rail.width, height: body.height)
        }
        return (frame(leftPane), unified ? .zero : frame(rightPane))
    }
    func connectionScene(in view: NSView) -> GitConnectionScene {
        let divider = view.convert(NSPoint(x: leftPane.frame.maxX + dividerThickness / 2, y: 0), from: self).x
        let empty = GitConnectionScene(divider: divider, paints: [])
        guard aligned, !unified, let comparison = model?.text,
            left.layout.side != nil, let leftView = left.layout.sourceView, let bridge = connectionRect(in: view)
        else { return empty }
        let rightLayout = workingEditor == nil ? right.layout : workingLayout
        guard rightLayout.side != nil, let rightView = rightLayout.sourceView else { return empty }
        var paints: [GitConnectionPaint] = []
        let leftStart = left.layout.visiblePosition() ?? 0
        let rightStart = rightLayout.visiblePosition() ?? 0
        let span = Double(bridge.height / WorkbenchMetrics.editorLineHeight) + 2
        for block in comparison.blocks {
            let leftVisible =
                Double(block.left.upperBound) >= leftStart
                && Double(block.left.lowerBound) <= leftStart + span
            let rightVisible =
                Double(block.right.upperBound) >= rightStart
                && Double(block.right.lowerBound) <= rightStart + span
            let crossing =
                (Double(block.left.upperBound) < leftStart && Double(block.right.lowerBound) > rightStart + span)
                || (Double(block.right.upperBound) < rightStart && Double(block.left.lowerBound) > leftStart + span)
            guard leftVisible || rightVisible || crossing else {
                continue
            }
            @MainActor func edge(_ range: Range<Int>, layout: GitTextLayout, view source: NSTextView) -> ClosedRange<
                CGFloat
            > {
                let top = view.convert(NSPoint(x: 0, y: layout.lineRect(range.lowerBound).minY), from: source).y
                let bottom =
                    range.isEmpty
                    ? top
                    : view.convert(NSPoint(x: 0, y: layout.lineRect(range.upperBound - 1).maxY), from: source).y
                return top...max(top, bottom)
            }
            guard
                let band = GitConnectionBand(
                    bridge: bridge, divider: divider,
                    left: edge(block.left, layout: left.layout, view: leftView),
                    right: edge(block.right, layout: rightLayout, view: rightView)), band.isVisible
            else { continue }
            paints.append(GitConnectionPaint(band: band, kind: block.kind))
        }
        return GitConnectionScene(divider: divider, paints: paints)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

@MainActor private final class GitDiffPane: NSView {
    let header = GitDiffVersionHeader()
    let gutter = GitDiffGutter()
    private var gutterWidth: CGFloat = 64
    private(set) var gutterFrame = NSRect.zero
    private(set) var scroll: NSScrollView?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(header)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    func configureGutter(trailing: Bool, visible: Bool, width: CGFloat) {
        gutter.trailing = trailing
        gutter.isHidden = !visible
        gutterWidth = visible ? width : 0
        needsLayout = true
    }
    func setScroll(_ view: NSScrollView) {
        guard scroll !== view || view.superview !== self else { return }
        scroll?.removeFromSuperview()
        scroll = view
        view.removeFromSuperview()
        addSubview(view)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: GitStyle.versionHeight)
        header.needsLayout = true
        let width = min(gutterWidth, bounds.width)
        let height = max(0, bounds.height - GitStyle.versionHeight)
        gutterFrame = NSRect(
            x: gutter.trailing ? bounds.width - width : 0, y: GitStyle.versionHeight, width: width, height: height)
        scroll?.frame = NSRect(
            x: gutter.trailing ? 0 : width, y: GitStyle.versionHeight,
            width: max(0, bounds.width - width), height: height)
    }
}
@MainActor final class GitDiffVersionHeader: NSView {
    private let text = NSTextField(labelWithString: "")
    private let lock = NSImageView()
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var selection: GitDiffSelection?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        text.font = .systemFont(ofSize: 12)
        text.textColor = WorkbenchColors.nativeSecondary
        text.lineBreakMode = .byTruncatingMiddle
        lock.image = NSImage(systemSymbolName: "lock", accessibilityDescription: "只读比较版本")
        lock.contentTintColor = WorkbenchColors.nativeSecondary
        checkbox.target = self
        checkbox.action = #selector(choose)
        checkbox.controlSize = .small
        checkbox.allowsMixedState = true
        checkbox.setAccessibilityLabel("选入本次提交，不改变暂存区")
        checkbox.toolTip = "选入本次提交，不改变暂存区"
        for child in [lock, checkbox, text] as [NSView] { addSubview(child) }
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    func configure(title: String, path: String, selection: GitDiffSelection?, editable: Bool = false) {
        self.selection = selection
        text.stringValue = title + (path.isEmpty ? "" : "   " + path)
        text.toolTip = text.stringValue
        checkbox.isHidden = selection == nil
        lock.isHidden = selection != nil
        lock.image = NSImage(
            systemSymbolName: editable ? "pencil" : "lock", accessibilityDescription: editable ? "可编辑工作区正文" : "只读比较版本")
        checkbox.state = selection?.state ?? .off
        checkbox.isEnabled = selection?.enabled == true
        needsLayout = true
    }
    @objc private func choose() {
        guard let selection else { return }
        selection.choose(selection.state != .on)
    }
    override func layout() {
        super.layout()
        lock.frame = NSRect(x: 8, y: 8, width: 12, height: 12)
        checkbox.frame = NSRect(x: 7, y: 5, width: 18, height: 18)
        text.frame = NSRect(x: 28, y: 6, width: max(0, bounds.width - 36), height: 18)
    }
    override func draw(_ dirtyRect: NSRect) {
        WorkbenchColors.nativePanel.setFill()
        dirtyRect.fill()
        WorkbenchColors.nativeBorder.setFill()
        NSRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5).fill()
    }
}
