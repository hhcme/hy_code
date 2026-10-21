import AppKit
import SwiftUI

/// App-owned scroll views reserve a fixed 8pt lane, independent of content length
/// or the system's auto-hide setting. The only painted part is the 4pt thumb.
@MainActor
final class WorkbenchScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { false }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style)
        -> CGFloat
    { WorkbenchMetrics.scrollerWidth }
    override var isOpaque: Bool { false }
    // NSScroller's legacy draw path can paint a bezel outside drawKnobSlot.
    // Own the complete drawing path while retaining native tracking/hit testing.
    override func draw(_ dirtyRect: NSRect) { drawKnob() }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        guard isEnabled, knobProportion < 1 else { return }
        let knob = rect(for: .knob)
        let vertical = bounds.height >= bounds.width
        let thumb = vertical ? knob.insetBy(dx: 2, dy: 1) : knob.insetBy(dx: 1, dy: 2)
        guard !thumb.isEmpty else { return }
        WorkbenchColors.nativeSecondary.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: 2, yRadius: 2).fill()
    }

    static func configure(_ scroll: NSScrollView, vertical: Bool = true, horizontal: Bool = false) {
        scroll.scrollerStyle = .legacy
        scroll.autohidesScrollers = false
        scroll.drawsBackground = false
        if vertical, !(scroll.verticalScroller is WorkbenchScroller) {
            scroll.verticalScroller = WorkbenchScroller(
                frame: NSRect(x: 0, y: 0, width: WorkbenchMetrics.scrollerWidth, height: 32))
        }
        if horizontal, !(scroll.horizontalScroller is WorkbenchScroller) {
            scroll.horizontalScroller = WorkbenchScroller(
                frame: NSRect(x: 0, y: 0, width: 32, height: WorkbenchMetrics.scrollerWidth))
        }
        scroll.hasVerticalScroller = vertical
        scroll.hasHorizontalScroller = horizontal
        scroll.verticalScroller?.controlSize = .small
        scroll.horizontalScroller?.controlSize = .small
    }
}

/// Attach inside a SwiftUI ScrollView's content, so the marker is a descendant of
/// that scroll view. Only its nearest owning scroll is configured; no global hooks.
struct WorkbenchScrollStyle: NSViewRepresentable {
    var vertical = true
    var horizontal = false
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) {
        view.vertical = vertical
        view.horizontal = horizontal
        view.configure()
    }
    final class Marker: NSView {
        var vertical = true
        var horizontal = false
        weak var configuredScroll: NSScrollView?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configure()
        }
        override func layout() {
            super.layout()
            configure()
        }
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configure()
        }
        func configure() {
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? NSScrollView {
                    if configuredScroll !== scroll || scroll.scrollerStyle != .legacy || scroll.autohidesScrollers
                        || scroll.hasVerticalScroller != vertical || scroll.hasHorizontalScroller != horizontal
                        || (vertical && !(scroll.verticalScroller is WorkbenchScroller))
                        || (horizontal && !(scroll.horizontalScroller is WorkbenchScroller))
                    {
                        WorkbenchScroller.configure(scroll, vertical: vertical, horizontal: horizontal)
                        configuredScroll = scroll
                    }
                    return
                }
                ancestor = view.superview
            }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
