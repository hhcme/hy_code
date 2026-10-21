import AppKit
import HyCodeWorkspace

/// Event/accessibility adapter only. The canvas owns the single indicator layer,
/// drag lifecycle and display-synchronized resize queue.
@MainActor
final class WorkbenchResizeHandle: NSView {
    let axis: WorkbenchDivider
    var readValue: () -> Double = { 0 }
    var resize: (Double) -> Void = { _ in }
    var beginResize: () -> Void = {}
    var endResize: () -> Void = {}
    var focusChanged: (Bool) -> Void = { _ in }
    private var anchor: (point: NSPoint, value: Double)?
    var interactive = true {
        didSet {
            guard oldValue != interactive else { return }
            if !interactive {
                finishTracking()
                focusChanged(false)
                if window?.firstResponder === self { window?.makeFirstResponder(nil) }
            }
            setAccessibilityHidden(!interactive)
            window?.invalidateCursorRects(for: self)
        }
    }
    override var acceptsFirstResponder: Bool { interactive }
    override var isFlipped: Bool { true }

    init(axis: WorkbenchDivider) {
        self.axis = axis
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel(title)
        setAccessibilityOrientation(axis.vertical ? .vertical : .horizontal)
    }
    required init?(coder: NSCoder) { nil }

    private var title: String {
        switch axis {
        case .project: "左上工具区宽度"
        case .information: "右上工具区宽度"
        case .bottom: "底部工具窗口高度"
        case .bottomSplit: "底部左右工具窗口分界"
        }
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if interactive, !bounds.isEmpty {
            addCursorRect(bounds, cursor: axis.vertical ? .resizeLeftRight : .resizeUpDown)
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard interactive else { return }
        window?.makeFirstResponder(self)
        anchor = (event.locationInWindow, readValue())
        beginResize()
    }
    override func mouseDragged(with event: NSEvent) {
        guard interactive, let anchor else { return }
        let delta: Double
        switch axis {
        case .project, .bottomSplit: delta = event.locationInWindow.x - anchor.point.x
        case .information: delta = anchor.point.x - event.locationInWindow.x
        case .bottom: delta = event.locationInWindow.y - anchor.point.y
        }
        resize(anchor.value + delta)
    }
    override func mouseUp(with event: NSEvent) { finishTracking() }
    override func cancelOperation(_ sender: Any?) { finishTracking() }

    /// Called by the canvas on release recovery, deactivation, hide and detach.
    /// It deliberately does not call back into layout while layout is being applied.
    func clearTracking() { anchor = nil }
    private func finishTracking() {
        guard anchor != nil else { return }
        anchor = nil
        endResize()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { finishTracking() }
    }
    override func keyDown(with event: NSEvent) {
        guard interactive else { return }
        let increase: Bool
        switch (axis, event.keyCode) {
        case (.project, 124), (.bottomSplit, 124), (.information, 123), (.bottom, 126): increase = true
        case (.project, 123), (.bottomSplit, 123), (.information, 124), (.bottom, 125): increase = false
        default:
            super.keyDown(with: event)
            return
        }
        focusChanged(true)
        resize(readValue() + (increase ? 16 : -16))
    }
    override func becomeFirstResponder() -> Bool {
        focusChanged(interactive)
        return interactive
    }
    override func resignFirstResponder() -> Bool {
        focusChanged(false)
        return true
    }
    override func accessibilityValue() -> Any? { "\(Int(readValue())) 点" }
    override func accessibilityPerformIncrement() -> Bool {
        guard interactive else { return false }
        focusChanged(true)
        resize(readValue() + 16)
        return true
    }
    override func accessibilityPerformDecrement() -> Bool {
        guard interactive else { return false }
        focusChanged(true)
        resize(readValue() - 16)
        return true
    }
}
