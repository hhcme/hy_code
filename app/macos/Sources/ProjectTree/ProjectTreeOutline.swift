import AppKit

/// The document remains at least viewport-wide, but grows to the widest expanded
/// row. Resizing the sidebar only applies cached width; it never remeasures names.
@MainActor final class ProjectTreeOutline: NSOutlineView {
    var makeContextMenu: ((Int) -> [WorkbenchMenuItem]?)?
    private let contextPopup = WorkbenchContextMenu()
    var contentWidth: CGFloat = 0 { didSet { fitContentWidth() } }
    private var applyingWidth = false
    private weak var observedClip: NSClipView?
    private var visibleX: CGFloat?
    private var visibleWidth: CGFloat?

    override func menu(for event: NSEvent) -> NSMenu? { nil }
    override func rightMouseDown(with event: NSEvent) { showContextMenu(event) }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { showContextMenu(event) } else { super.mouseDown(with: event) }
    }
    private func showContextMenu(_ event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard isEnabled, row >= 0, let items = makeContextMenu?(row), let window else { return }
        contextPopup.show(
            items.map(\.contextCommand), at: window.convertPoint(toScreen: event.locationInWindow), in: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { contextPopup.hide() }
        let clip = window == nil ? nil : enclosingScrollView?.contentView
        guard observedClip !== clip else { return }
        if let observedClip {
            NotificationCenter.default.removeObserver(
                self, name: NSView.boundsDidChangeNotification, object: observedClip)
        }
        observedClip = clip
        visibleX = clip?.bounds.minX
        visibleWidth = clip?.bounds.width
        if let clip {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(clipBoundsChanged(_:)), name: NSView.boundsDidChangeNotification, object: clip
            )
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func clipBoundsChanged(_ notification: Notification) {
        guard let clip = observedClip, notification.object as? NSClipView === clip,
            visibleX != clip.bounds.minX || visibleWidth != clip.bounds.width
        else { return }
        visibleX = clip.bounds.minX
        visibleWidth = clip.bounds.width
        // Horizontal scrolling or resizing may copy old backing pixels. Repaint
        // only highlighted rows so both viewport-anchored corners update.
        enumerateAvailableRowViews { view, _ in
            if let row = view as? ProjectRowView, row.hasHighlight { row.needsDisplay = true }
        }
    }

    func fitContentWidth() {
        guard !applyingWidth, let scroll = enclosingScrollView, let column = outlineTableColumn else { return }
        let width = ceil(max(contentWidth, scroll.contentSize.width))
        guard column.width != width || frame.width != width else { return }
        applyingWidth = true
        defer { applyingWidth = false }
        column.width = width
        if frame.width != width { setFrameSize(NSSize(width: width, height: frame.height)) }
        let clip = scroll.contentView
        let constrained = clip.constrainBoundsRect(clip.bounds)
        if clip.bounds.origin != constrained.origin { clip.scroll(to: constrained.origin) }
        scroll.reflectScrolledClipView(clip)
    }
}
