import AppKit
import HyCodeWorkspace

/// Explicit sibling order: native text panes, opaque connector canvas, then
/// transparent number/action rails. No connector depends on a split-view
/// background showing through its descendants.
@MainActor final class GitDiffHost: NSView {
    let split = GitDiffSplit()
    private let canvas = GitConnectionCanvas()
    private var updating = false
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = true
        addSubview(split)
        addSubview(canvas)
        addSubview(split.leftGutter)
        addSubview(split.rightGutter)
        split.presentationChanged = { [weak self] in self?.updatePresentation() }
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        WorkbenchColors.nativePanel.setFill()
        dirtyRect.fill()
    }
    override func layout() {
        super.layout()
        layoutSplit()
    }
    override func resizeSubviews(withOldSize oldSize: NSSize) { layoutSplit() }
    private func layoutSplit() {
        split.frame = bounds
        split.layoutSubtreeIfNeeded()
        updatePresentation()
    }
    private func updatePresentation() {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        canvas.isHidden = split.connectionRect(in: self) == nil
        canvas.frame = split.connectionRect(in: self) ?? .zero
        let frames = split.gutterFrames(in: self)
        split.leftGutter.frame = frames.0
        split.rightGutter.frame = frames.1
        split.leftGutter.refreshActions()
        split.rightGutter.refreshActions()
        if !canvas.isHidden {
            canvas.configure(split.connectionScene(in: canvas))
        } else {
            canvas.configure(.empty)
        }
        needsDisplay = true
    }
}

/// This view has no opaque child views, and is above both native panes. Its
/// drawing consumes a prepared scene; drawing never causes child layout.
@MainActor private final class GitConnectionCanvas: NSView {
    private var scene = GitConnectionScene.empty
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { nil }
    func configure(_ scene: GitConnectionScene) {
        self.scene = scene
        needsDisplay = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        scene.draw(
            in: context, bounds: bounds, background: WorkbenchColors.nativePanel.cgColor,
            dividerColour: WorkbenchColors.nativeBorder.withAlphaComponent(0.6).cgColor,
            colour: { GitStyle.changeColor($0)?.cgColor })
    }
}
