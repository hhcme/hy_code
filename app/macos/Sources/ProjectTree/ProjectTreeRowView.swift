import AppKit
import HyCodeWorkspace

@MainActor final class ProjectRowView: NSTableRowView {
    private var hovering = false
    var hasHighlight: Bool { isSelected || hovering }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
    }
    required init?(coder: NSCoder) { nil }
    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { hovering = false }
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { isSelected ? .emphasized : .normal }

    override func drawBackground(in dirtyRect: NSRect) {
        WorkbenchColors.nativePanel.setFill()
        bounds.fill()
        if hovering, !isSelected { fillHighlight(WorkbenchColors.nativeTreeHover) }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        fillHighlight(isEmphasized ? WorkbenchColors.nativeSelection : WorkbenchColors.nativeInactiveSelection)
    }

    private func fillHighlight(_ color: NSColor) {
        // Use only the visible horizontal span, but keep the complete row's
        // vertical geometry so partly scrolled rows do not acquire new corners.
        let visible = visibleRect
        guard !visible.isEmpty else { return }
        let rect = NSRect(x: visible.minX, y: bounds.minY, width: visible.width, height: bounds.height)
            .insetBy(dx: 0, dy: 1)
        guard !rect.isEmpty else { return }
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor final class ProjectTreeCell: NSTableCellView {
    static func nameFont(root: Bool) -> NSFont {
        .systemFont(ofSize: ProjectTreeText.nameFontSize, weight: root ? .semibold : .regular)
    }
    static func contentWidth(nameWidth: CGFloat) -> CGFloat { 2 + 16 + 6 + ceil(nameWidth) + 4 + 6 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        let icon = NSImageView()
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byClipping
        label.usesSingleLineMode = true
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.spacing = 6
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        imageView = icon
        textField = label
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
        ])
    }
}
