import CoreGraphics

public struct WorkbenchResizeRequest: Equatable, Sendable {
    public let axis: WorkbenchDivider
    public let value: Double
}

public struct WorkbenchDividerIndicator: Equatable, Sendable {
    public let frame: CGRect
    public let emphasized: Bool
}

/// One owner for every divider's transient state. A release/interrupt clears hover
/// too: a delayed enter notification cannot resurrect a line without pointer motion.
public struct WorkbenchResizeInteraction: Sendable {
    public private(set) var dragging: WorkbenchDivider?
    private var pending: WorkbenchResizeRequest?
    private var hovered: WorkbenchDivider?
    private var focused: WorkbenchDivider?

    public init() {}

    public mutating func begin(_ axis: WorkbenchDivider) {
        dragging = axis
        pending = nil
        hovered = nil
        focused = nil
    }
    public mutating func enqueue(_ axis: WorkbenchDivider, value: Double) {
        guard dragging == axis, value.isFinite else { return }
        pending = WorkbenchResizeRequest(axis: axis, value: value)
    }
    public mutating func takePending() -> WorkbenchResizeRequest? {
        defer { pending = nil }
        return pending
    }
    @discardableResult public mutating func finish() -> WorkbenchResizeRequest? {
        let last = takePending()
        reset()
        return last
    }
    public mutating func reset() {
        dragging = nil
        pending = nil
        hovered = nil
        focused = nil
    }
    public mutating func clearHover() { hovered = nil }
    public mutating func focus(_ axis: WorkbenchDivider?) {
        guard dragging == nil else { return }
        focused = axis
    }
    public mutating func pointer(at point: CGPoint, frames: WorkbenchPaneFrames, moved: Bool) {
        // Enter/exit ordering is not guaranteed by AppKit. Only a real motion
        // event can arm a highlight, even after moving away following release.
        guard dragging == nil, moved else { return }
        hovered = WorkbenchDivider.allCases.first { !frames[$0].isEmpty && frames[$0].contains(point) }
    }
    public func indicator(in frames: WorkbenchPaneFrames, scale: Double) -> WorkbenchDividerIndicator? {
        guard let axis = dragging ?? hovered ?? focused else { return nil }
        let divider = frames[axis]
        let inset = 10.0
        let grid = WorkbenchPixelGrid(scale: scale)
        let pixel = 1 / grid.scale
        let line: CGRect
        if axis.vertical {
            line = CGRect(
                x: grid.snap(divider.midX), y: divider.minY + inset, width: pixel,
                height: max(0, divider.height - inset * 2))
        } else {
            line = CGRect(
                x: divider.minX + inset, y: grid.snap(divider.midY), width: max(0, divider.width - inset * 2),
                height: pixel)
        }
        guard !divider.isEmpty, !line.isEmpty else { return nil }
        return WorkbenchDividerIndicator(frame: line, emphasized: dragging != nil || hovered != nil)
    }
}
