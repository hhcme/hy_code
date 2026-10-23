import AppKit
import HyCodeWorkspace
import QuartzCore
import SwiftUI

struct WorkbenchToolRail: NSViewRepresentable {
    let leading: Bool
    let docking: WorkbenchDocking
    let session: UUID
    let toggle: (WorkbenchTool) -> Void
    let move: (WorkbenchTool, WorkbenchCorner, Int) -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NativeToolRail { NativeToolRail(leading: leading, session: session) }
    func updateNSView(_ view: NativeToolRail, context: Context) {
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        view.toggle = toggle
        view.move = move
        view.update(docking)
    }
}

extension NSPasteboard.PasteboardType {
    fileprivate static let hycodeTool = NSPasteboard.PasteboardType("io.github.hhcme.hycode.tool-drag")
}

@MainActor
final class NativeToolRail: NSView {
    let leading: Bool
    let session: UUID
    var toggle: (WorkbenchTool) -> Void = { _ in }
    var move: (WorkbenchTool, WorkbenchCorner, Int) -> Void = { _, _, _ in }
    private(set) var docking = WorkbenchDocking()
    private var buttons: [WorkbenchTool: DockToolButton] = [:]
    private let insertionLine = CALayer()
    private var insertion: (corner: WorkbenchCorner, index: Int, y: CGFloat)?
    private var initialized = false
    override var isFlipped: Bool { true }
    private var top: WorkbenchCorner { leading ? .topLeading : .topTrailing }
    private var bottom: WorkbenchCorner { leading ? .bottomLeading : .bottomTrailing }
    private let step = WorkbenchMetrics.toolStep

    init(leading: Bool, session: UUID) {
        self.leading = leading
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(insertionLine)
        insertionLine.isHidden = true
        registerForDraggedTypes([.hycodeTool])
        setAccessibilityLabel(leading ? "左侧工具窗口" : "右侧工具窗口")
    }
    required init?(coder: NSCoder) { nil }

    func update(_ docking: WorkbenchDocking) {
        guard !initialized || self.docking != docking else { return }
        initialized = true
        self.docking = docking
        let tools = docking.groups[top, default: []] + docking.groups[bottom, default: []]
        for tool in Array(buttons.keys) where !tools.contains(tool) {
            buttons.removeValue(forKey: tool)?.removeFromSuperview()
        }
        for tool in tools {
            let button: DockToolButton
            if let existing = buttons[tool] {
                button = existing
            } else {
                button = DockToolButton(tool: tool, rail: self)
                buttons[tool] = button
                addSubview(button)
            }
            button.selected = docking.isVisible(tool)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        for corner in [top, bottom] {
            let tools = docking.groups[corner, default: []]
            let start = WorkbenchRailGeometry.start(count: tools.count, top: corner.isTop, height: bounds.height)
            for (index, tool) in tools.enumerated() {
                let side = WorkbenchMetrics.toolSide
                let frame = NSRect(
                    x: (bounds.width - side) / 2, y: start + CGFloat(index) * step, width: side, height: side)
                if buttons[tool]?.frame != frame { buttons[tool]?.frame = frame }
            }
        }
    }

    private func source(_ sender: NSDraggingInfo) -> DockToolButton? {
        guard let source = sender.draggingSource as? DockToolButton, source.rail?.session == session else { return nil }
        return source
    }
    private func locate(_ point: NSPoint) -> (corner: WorkbenchCorner, index: Int, y: CGFloat) {
        let upper = docking.groups[top, default: []]
        let lower = docking.groups[bottom, default: []]
        let upperEnd = WorkbenchMetrics.railEndInset + CGFloat(max(1, upper.count)) * step
        let lowerStart = max(
            upperEnd, WorkbenchRailGeometry.start(count: lower.count, top: false, height: bounds.height))
        let corner = point.y < (upperEnd + lowerStart) / 2 ? top : bottom
        let tools = docking.groups[corner, default: []]
        let slot = WorkbenchRailGeometry.insertionIndex(
            y: point.y, count: tools.count, top: corner.isTop, height: bounds.height)
        return (
            corner, slot,
            WorkbenchRailGeometry.insertionY(index: slot, count: tools.count, top: corner.isTop, height: bounds.height)
        )
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { false }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard source(sender) != nil else {
            clearInsertion()
            return []
        }
        setInsertion(locate(convert(sender.draggingLocation, from: nil)))
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { clearInsertion() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { source(sender) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let source = source(sender) else {
            clearInsertion()
            return false
        }
        let target = locate(convert(sender.draggingLocation, from: nil))
        let interval = WorkbenchPerformance.begin("DockPlacement")
        defer { WorkbenchPerformance.end("DockPlacement", interval) }
        move(source.tool, target.corner, target.index)
        clearInsertion()
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { clearInsertion() }
    private func clearInsertion() { setInsertion(nil) }
    private func setInsertion(_ target: (corner: WorkbenchCorner, index: Int, y: CGFloat)?) {
        if insertion?.corner == target?.corner, insertion?.index == target?.index, insertion?.y == target?.y { return }
        insertion = target
        updateInsertion()
    }
    private func updateInsertion() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        insertionLine.isHidden = insertion == nil
        if let insertion {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                insertionLine.backgroundColor = WorkbenchColors.nativeAccent.cgColor
            }
            insertionLine.frame = NSRect(x: 7, y: insertion.y, width: 26, height: 2)
            insertionLine.cornerRadius = 1
        }
        CATransaction.commit()
    }
}

@MainActor
private final class DockToolButton: NSButton, NSDraggingSource {
    let tool: WorkbenchTool
    weak var rail: NativeToolRail?
    var selected = false {
        didSet {
            if selected != oldValue {
                preparedDragImage = nil
                needsDisplay = true
            }
        }
    }
    private var press: (point: NSPoint, time: TimeInterval)?
    private var armTimer: Timer?
    private var armed = false
    private var dragging = false
    private var hovering = false
    private var tracking: NSTrackingArea?
    private let contextPopup = WorkbenchContextMenu()
    private let artwork: WorkbenchToolArtwork
    private var preparedDragImage: NSImage?

    init(tool: WorkbenchTool, rail: NativeToolRail) {
        self.tool = tool
        self.rail = rail
        artwork = WorkbenchToolArtwork(symbolName: tool.symbol)
        super.init(frame: .zero)
        title = ""
        isBordered = false
        target = self
        action = #selector(activateTool)
        toolTip = tool.title + (tool.shortcut.map { " ⌘\($0)" } ?? "") + " · 长按拖动以移动或排序"
        setAccessibilityLabel(tool.title)
        setAccessibilityHelp("点击切换；长按拖动换位置；右键菜单可移动或排序")
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    required init?(coder: NSCoder) { nil }
    @objc private func activateTool() { rail?.toggle(tool) }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showContextMenu(event)
            return
        }
        guard isEnabled, event.type == .leftMouseDown else { return }
        hovering = true
        needsDisplay = true
        press = (event.locationInWindow, ProcessInfo.processInfo.systemUptime)
        armed = false
        dragging = false
        armTimer?.invalidate()
        let timer = Timer(timeInterval: 0.28, target: self, selector: #selector(armDrag), userInfo: nil, repeats: false)
        armTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    @objc private func armDrag() {
        armed = press != nil
        armTimer = nil
        preparedDragImage = dragImage()
        needsDisplay = true
    }
    private func dragImage() -> NSImage? {
        artwork.image(
            state: selected ? .selected : .hover, appearance: effectiveAppearance,
            scale: window?.backingScaleFactor ?? 2)
    }
    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if hovering != inside {
            hovering = inside
            needsDisplay = true
        }
        guard let press, !dragging, armed else { return }
        let distance = hypot(event.locationInWindow.x - press.point.x, event.locationInWindow.y - press.point.y)
        guard distance >= 4 else { return }
        dragging = true
        armTimer?.invalidate()
        armTimer = nil
        let writer = NSPasteboardItem()
        writer.setString(tool.rawValue, forType: .hycodeTool)
        let item = NSDraggingItem(pasteboardWriter: writer)
        guard let preview = preparedDragImage ?? dragImage() else {
            resetPress()
            return
        }
        item.setDraggingFrame(bounds, contents: preview)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.draggingFormation = .none
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        let shouldActivate = press != nil && !dragging && bounds.contains(convert(event.locationInWindow, from: nil))
        resetPress()
        if shouldActivate { activateTool() }
    }
    override func cancelOperation(_ sender: Any?) { resetPress() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            contextPopup.hide()
            hovering = false
            resetPress()
        }
    }
    private func resetPress() {
        armTimer?.invalidate()
        armTimer = nil
        press = nil
        armed = false
        dragging = false
        preparedDragImage = nil
        needsDisplay = true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        resetPress()
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        preparedDragImage = nil
        needsDisplay = true
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        preparedDragImage = nil
        needsDisplay = true
    }
    override func mouseEntered(with event: NSEvent) {
        if !hovering {
            hovering = true
            needsDisplay = true
        }
    }
    override func mouseExited(with event: NSEvent) {
        if hovering {
            hovering = false
            needsDisplay = true
        }
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled, !visibleRect.isEmpty { addCursorRect(visibleRect, cursor: .pointingHand) }
    }
    override func accessibilityValue() -> Any? { selected ? "已展开" : "已折叠" }
    override func draw(_ dirtyRect: NSRect) {
        WorkbenchColors.nativeChrome.setFill()
        bounds.fill()
        let highlighted = hovering || armed || window?.firstResponder === self || isHighlighted
        let pressed = press != nil && !dragging && hovering
        let state: WorkbenchToolArtwork.State
        if selected {
            state = pressed ? .selectedPressed : highlighted ? .selectedHover : .selected
        } else {
            state = pressed ? .pressed : highlighted ? .hover : .idle
        }
        guard
            let image = artwork.image(
                state: state, appearance: effectiveAppearance, scale: window?.backingScaleFactor ?? 2)
        else { return }
        image.draw(
            in: bounds, from: .zero, operation: .sourceOver, fraction: dragging ? 0.4 : 1, respectFlipped: true,
            hints: nil)
    }

    override func menu(for event: NSEvent) -> NSMenu? { nil }
    override func rightMouseDown(with event: NSEvent) { showContextMenu(event) }
    private func showContextMenu(_ event: NSEvent) {
        guard isEnabled, let window, let rail, let corner = rail.docking.corner(of: tool),
            let index = rail.docking.groups[corner]?.firstIndex(of: tool)
        else { return }
        var items: [WorkbenchMenuItem] = []
        for destination in WorkbenchCorner.allCases {
            items.append(
                WorkbenchMenuItem(title: "移动到\(destination.title)", enabled: destination != corner) { [weak self] in
                    guard let self, let rail = self.rail else { return }
                    rail.move(self.tool, destination, rail.docking.groups[destination, default: []].count)
                })
        }
        items.append(.separator)
        items.append(
            WorkbenchMenuItem(title: "向前排列", enabled: index > 0) { [weak self] in
                guard let self else { return }
                self.rail?.move(self.tool, corner, index - 1)
            })
        items.append(
            WorkbenchMenuItem(title: "向后排列", enabled: index + 1 < rail.docking.groups[corner, default: []].count) {
                [weak self] in
                guard let self else { return }
                self.rail?.move(self.tool, corner, index + 2)
            })
        contextPopup.show(
            items.map(\.contextCommand), at: window.convertPoint(toScreen: event.locationInWindow), in: self)
    }
}
