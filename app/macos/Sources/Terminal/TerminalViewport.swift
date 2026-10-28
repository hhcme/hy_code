import AppKit

/// Terminal content and scroll controls have separate, stable geometry, sharing
/// the exact WorkbenchScroller used by the editor and project tree.
@MainActor final class TerminalViewport: NSView {
    let terminal: HyCodeTerminalView
    private let scroller = WorkbenchScroller(frame: NSRect(x: 0, y: 0, width: 8, height: 32))
    init(terminal: HyCodeTerminalView) {
        self.terminal = terminal
        super.init(frame: .zero)
        clipsToBounds = true
        terminal.hideBuiltInScroller()
        addSubview(terminal)
        scroller.scrollerStyle = .legacy
        scroller.controlSize = .small
        scroller.isContinuous = true
        scroller.target = self
        scroller.action = #selector(scrollControl(_:))
        scroller.setAccessibilityLabel("终端输出滚动")
        addSubview(scroller)
        terminal.onViewportChange = { [weak self] in self?.synchronizeScroller() }
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        let lane = min(WorkbenchMetrics.scrollerWidth, bounds.width)
        let rect = NSRect(x: 0, y: 0, width: max(0, bounds.width - lane), height: bounds.height)
        if terminal.frame != rect { terminal.frame = rect }
        scroller.frame = NSRect(x: rect.maxX, y: 0, width: lane, height: bounds.height)
        synchronizeScroller()
    }
    func synchronizeScroller() {
        scroller.isEnabled = terminal.canScroll
        scroller.knobProportion = terminal.canScroll ? terminal.scrollThumbsize : 1
        scroller.doubleValue = terminal.scrollPosition
        scroller.needsDisplay = true
    }
    @objc private func scrollControl(_ sender: NSScroller) {
        guard terminal.canScroll else { return }
        switch sender.hitPart {
        case .knob, .knobSlot: terminal.scroll(toPosition: min(1, max(0, sender.doubleValue)))
        case .decrementPage: terminal.pageUp()
        case .incrementPage: terminal.pageDown()
        case .decrementLine: terminal.scrollUp(lines: 1)
        case .incrementLine: terminal.scrollDown(lines: 1)
        default: return
        }
        synchronizeScroller()
    }
}
