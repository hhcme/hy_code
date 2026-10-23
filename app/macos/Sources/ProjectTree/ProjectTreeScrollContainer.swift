import AppKit
import HyCodeWorkspace

/// Keep the two native scroller controls outside the NSScrollView. The content
/// scrolls natively, but AppKit never owns a legacy two-scroller junction here.
@MainActor final class ProjectTreeScrollContainer: NSView {
    private let scroll = ContentScrollView()
    private let vertical = WorkbenchScroller(frame: NSRect(x: 0, y: 0, width: 8, height: 32))
    private let horizontal = WorkbenchScroller(frame: NSRect(x: 0, y: 0, width: 32, height: 8))

    init(outline: ProjectTreeOutline) {
        super.init(frame: .zero)
        clipsToBounds = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = .init()
        scroll.contentView.drawsBackground = true
        scroll.contentView.backgroundColor = WorkbenchColors.nativePanel
        scroll.documentView = outline
        addSubview(scroll)
        for scroller in [vertical, horizontal] {
            scroller.scrollerStyle = .legacy
            scroller.controlSize = .small
            scroller.target = self
            scroller.action = #selector(scrollControl(_:))
            scroller.isContinuous = true
            addSubview(scroller)
        }
        vertical.setAccessibilityLabel("文件列表纵向滚动")
        horizontal.setAccessibilityLabel("文件列表横向滚动")
        scroll.didReflect = { [weak self] in self?.synchronizeControls() }
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        WorkbenchColors.nativePanel.setFill()
        dirtyRect.fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    override func layout() {
        super.layout()
        let lane = WorkbenchMetrics.scrollerWidth
        let width = max(0, bounds.width - lane)
        let height = max(0, bounds.height - lane)
        let viewport = NSRect(x: 0, y: 0, width: width, height: height)
        if scroll.frame != viewport { scroll.frame = viewport }
        vertical.frame = NSRect(x: width, y: 0, width: min(lane, bounds.width), height: height)
        horizontal.frame = NSRect(x: 0, y: height, width: width, height: min(lane, bounds.height))
        (scroll.documentView as? ProjectTreeOutline)?.fitContentWidth()
        synchronizeControls()
    }
    private func axis(vertical: Bool) -> ProjectTreeScrollAxis {
        let viewport = scroll.contentView.bounds.size
        let document = scroll.documentView?.frame.size ?? .zero
        return ProjectTreeScrollAxis(
            viewport: vertical ? viewport.height : viewport.width,
            extent: vertical ? document.height : document.width)
    }
    private var documentFlipped: Bool { scroll.documentView?.isFlipped ?? true }
    private func synchronizeControls() {
        let origin = scroll.contentView.bounds.origin
        for (control, isVertical) in [(vertical, true), (horizontal, false)] {
            let axis = axis(vertical: isVertical)
            let offset = isVertical ? origin.y : origin.x
            let value = axis.normalized(offset)
            let normalized = isVertical && !documentFlipped ? 1 - value : value
            if control.knobProportion != axis.knobProportion { control.knobProportion = axis.knobProportion }
            if control.doubleValue != normalized { control.doubleValue = normalized }
            let enabled = axis.maximumOffset > 0 && axis.viewport > 0
            if control.isEnabled != enabled { control.isEnabled = enabled }
        }
    }
    @objc private func scrollControl(_ sender: NSScroller) {
        let isVertical = sender === vertical
        let axis = axis(vertical: isVertical)
        guard axis.maximumOffset > 0 else { return }
        let clip = scroll.contentView
        var origin = clip.bounds.origin
        let reversed = isVertical && !documentFlipped
        let current = isVertical ? origin.y : origin.x
        var offset = reversed ? axis.maximumOffset - current : current
        let line = isVertical ? scroll.verticalLineScroll : scroll.horizontalLineScroll
        let overlap = isVertical ? scroll.verticalPageScroll : scroll.horizontalPageScroll
        let page = max(line, axis.viewport - overlap)
        switch sender.hitPart {
        case .knob, .knobSlot: offset = axis.offset(for: sender.doubleValue)
        case .decrementLine: offset -= line
        case .incrementLine: offset += line
        case .decrementPage: offset -= page
        case .incrementPage: offset += page
        default: return
        }
        offset = axis.clamp(offset)
        let position = reversed ? axis.maximumOffset - offset : offset
        if isVertical { origin.y = position } else { origin.x = position }
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        scroll.reflectScrolledClipView(clip)
    }

    private final class ContentScrollView: NSScrollView {
        var didReflect: (() -> Void)?
        override var isOpaque: Bool { false }
        override func draw(_ dirtyRect: NSRect) {}
        override func reflectScrolledClipView(_ clipView: NSClipView) {
            super.reflectScrolledClipView(clipView)
            didReflect?()
        }
        override func tile() {
            super.tile()
            (documentView as? ProjectTreeOutline)?.fitContentWidth()
            didReflect?()
        }
    }
}
