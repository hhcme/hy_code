import AppKit
import SwiftUI

/// Native frames change during dragging; only the final ratio is persisted.
/// Hosting views keep their SwiftUI identity while the tool is folded/moved.
struct GitPaneSplit<First: View, Second: View>: NSViewRepresentable {
    let name: String
    let vertical: Bool
    let initial: Double
    let first: First
    let second: Second
    @Environment(\.colorScheme) private var scheme
    init(
        name: String, vertical: Bool, initial: Double = 0.5, @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        self.name = name
        self.vertical = vertical
        self.initial = initial
        self.first = first()
        self.second = second()
    }
    func makeNSView(context: Context) -> GitPaneContainer {
        GitPaneContainer(name: name, vertical: vertical, initial: initial)
    }
    func updateNSView(_ view: GitPaneContainer, context: Context) {
        view.first.rootView = AnyView(first.workbenchContentStyle().environment(\.colorScheme, scheme))
        view.second.rootView = AnyView(second.workbenchContentStyle().environment(\.colorScheme, scheme))
    }
}

@MainActor final class GitPaneContainer: NSSplitView, NSSplitViewDelegate {
    let first = NSHostingView(rootView: AnyView(EmptyView()))
    let second = NSHostingView(rootView: AnyView(EmptyView()))
    private let key: String
    private var fraction: Double
    private var arranging = false
    override var isFlipped: Bool { true }
    override var dividerThickness: CGFloat { 5 }
    init(name: String, vertical: Bool, initial: Double) {
        key = "git.split." + name
        fraction = min(0.85, max(0.15, UserDefaults.standard.object(forKey: key) as? Double ?? initial))
        super.init(frame: .zero)
        isVertical = vertical
        dividerStyle = .thin
        delegate = self
        for host in [first, second] {
            host.safeAreaRegions = []
            host.sizingOptions = []
            host.wantsLayer = true
            host.layer?.masksToBounds = true
            addArrangedSubview(host)
        }
    }
    required init?(coder: NSCoder) { nil }
    override func drawDivider(in rect: NSRect) {
        WorkbenchColors.nativeChrome.setFill()
        rect.fill()
    }
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        guard !arranging else { return }
        arranging = true
        defer { arranging = false }
        let available = max(0, (isVertical ? bounds.width : bounds.height) - dividerThickness)
        let size = (available * fraction).rounded()
        if isVertical {
            first.frame = CGRect(x: 0, y: 0, width: size, height: bounds.height)
            second.frame = CGRect(
                x: size + dividerThickness, y: 0, width: max(0, available - size), height: bounds.height)
        } else {
            first.frame = CGRect(x: 0, y: 0, width: bounds.width, height: size)
            second.frame = CGRect(
                x: 0, y: size + dividerThickness, width: bounds.width, height: max(0, available - size))
        }
    }
    func splitViewDidResizeSubviews(_ notification: Notification) {
        let total = (isVertical ? bounds.width : bounds.height) - dividerThickness
        guard !arranging, total > 0 else { return }
        fraction = min(0.85, max(0.15, (isVertical ? first.frame.width : first.frame.height) / total))
    }
    func splitView(
        _ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        let total = max(0, (isVertical ? bounds.width : bounds.height) - dividerThickness)
        return min(total * 0.85, max(total * 0.15, proposedPosition))
    }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        UserDefaults.standard.set(fraction, forKey: key)
    }
}
