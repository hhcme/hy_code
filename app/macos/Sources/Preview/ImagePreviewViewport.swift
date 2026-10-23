import AppKit
import HyCodeWorkspace

/// A stable, immediate-mode native viewport. Pixel decoding never runs here.
/// Two external transparent scrollers avoid AppKit's legacy junction square.
@MainActor final class ImagePreviewViewport: NSView {
    private let scroll = ImageScrollView()
    private let canvas = ImageCanvas()
    private let extentView = ImageExtentView()
    private let vertical = WorkbenchScroller(frame: NSRect(x: 0, y: 0, width: 8, height: 32))
    private let horizontal = WorkbenchScroller(frame: NSRect(x: 0, y: 0, width: 32, height: 8))
    private var pixels = CGSize(width: 1, height: 1)
    private var zoomState = ImagePreviewZoom()
    private var projection = ImagePreviewLayout(pixels: CGSize(width: 1, height: 1), viewport: .zero, scale: 1)
    var zoomChanged: (CGFloat, Bool) -> Void = { _, _ in }
    var background = ImagePreviewBackground.checkerboard { didSet { canvas.background = background } }
    init() {
        super.init(frame: .zero)
        clipsToBounds = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = .init()
        scroll.contentView.drawsBackground = false
        scroll.documentView = extentView
        addSubview(scroll)
        addSubview(canvas)
        for control in [vertical, horizontal] {
            control.scrollerStyle = .legacy
            control.controlSize = .small
            control.target = self
            control.action = #selector(scrollControl(_:))
            control.isContinuous = true
            addSubview(control)
        }
        vertical.setAccessibilityLabel("图片纵向滚动")
        horizontal.setAccessibilityLabel("图片横向滚动")
        scroll.didReflect = { [weak self] in self?.scrolled() }
        scroll.zoomGesture = { [weak self] event, ratio in self?.zoomGesture(event, ratio: ratio) }
        canvas.zoomGesture = scroll.zoomGesture
        canvas.wheel = { [weak scroll] in scroll?.scrollWheel(with: $0) }
        canvas.pan = { [weak self] delta in self?.pan(delta) }
        canvas.command = { [weak self] action in
            guard let self else { return }
            switch action {
            case .fit: fit()
            case .actual: zoom(to: 1)
            case .larger: zoom(by: 1.25)
            case .smaller: zoom(by: 1 / 1.25)
            }
        }
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        WorkbenchColors.nativeCanvas.setFill()
        dirtyRect.fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        canvas.needsDisplay = true
    }
    override func layout() {
        super.layout()
        let oldSize = scroll.contentView.bounds.size
        let oldOrigin = scroll.contentView.bounds.origin
        let lane = WorkbenchMetrics.scrollerWidth
        let width = max(0, bounds.width - lane)
        let height = max(0, bounds.height - lane)
        scroll.frame = CGRect(x: 0, y: 0, width: width, height: height)
        canvas.frame = scroll.frame
        vertical.frame = CGRect(x: width, y: 0, width: min(lane, bounds.width), height: height)
        horizontal.frame = CGRect(x: 0, y: height, width: width, height: min(lane, bounds.height))
        relayout(
            anchor: CGPoint(x: oldSize.width / 2, y: oldSize.height / 2),
            newAnchor: CGPoint(x: width / 2, y: height / 2), oldOrigin: oldOrigin)
    }
    func display(_ content: ImagePreviewContent?) {
        guard canvas.image !== content?.image else { return }
        canvas.image = content?.image
        if let content {
            pixels = content.pixelSize
            canvas.setAccessibilityLabel("图片 \(Int(pixels.width)) × \(Int(pixels.height))，\(content.format)，只读")
        }
        relayout()
    }
    func fit() {
        zoomState.fit()
        relayout()
    }
    func zoom(to value: CGFloat) {
        zoomState.set(value)
        relayout()
    }
    func zoom(by ratio: CGFloat) { zoom(to: zoomState.factor(pixels: pixels, viewport: scroll.contentSize) * ratio) }
    private func zoomGesture(_ event: NSEvent, ratio: CGFloat) {
        guard canvas.image != nil else { return }
        let clip = scroll.contentView
        let point = clip.convert(event.locationInWindow, from: nil)
        let anchor = CGPoint(x: point.x - clip.bounds.minX, y: point.y - clip.bounds.minY)
        zoomState.set(zoomState.factor(pixels: pixels, viewport: clip.bounds.size) * ratio)
        relayout(anchor: anchor)
    }
    private func relayout(anchor: CGPoint? = nil, newAnchor: CGPoint? = nil, oldOrigin: CGPoint? = nil) {
        let clip = scroll.contentView
        let size = clip.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let old = projection
        let origin = oldOrigin ?? clip.bounds.origin
        let factor = zoomState.factor(pixels: pixels, viewport: size)
        projection = ImagePreviewLayout(pixels: pixels, viewport: size, scale: factor)
        extentView.frame.size = projection.extent
        let target = anchor ?? CGPoint(x: size.width / 2, y: size.height / 2)
        var offset = projection.preservingAnchor(
            from: old, origin: origin, anchor: target, viewport: size, newAnchor: newAnchor)
        if zoomState.fits { offset = .zero }
        clip.scroll(to: projection.clamp(origin: offset, viewport: size))
        scroll.reflectScrolledClipView(clip)
        zoomChanged(factor, zoomState.fits)
    }
    private func pan(_ delta: CGPoint) {
        let clip = scroll.contentView
        let origin = CGPoint(x: clip.bounds.minX + delta.x, y: clip.bounds.minY + delta.y)
        clip.scroll(to: projection.clamp(origin: origin, viewport: clip.bounds.size))
        scroll.reflectScrolledClipView(clip)
    }
    private func scrolled() {
        let offset = scroll.contentView.bounds.origin
        canvas.imageRect = projection.image.offsetBy(dx: -offset.x, dy: -offset.y)
        reflect()
    }
    private func reflect() {
        let clip = scroll.contentView
        for (control, vertical) in [(vertical, true), (horizontal, false)] {
            let axis = ProjectTreeScrollAxis(
                viewport: vertical ? clip.bounds.height : clip.bounds.width,
                extent: vertical ? extentView.frame.height : extentView.frame.width)
            control.knobProportion = axis.knobProportion
            control.doubleValue = axis.normalized(vertical ? clip.bounds.minY : clip.bounds.minX)
            control.isEnabled = canvas.image != nil && axis.maximumOffset > 0
        }
    }
    @objc private func scrollControl(_ sender: NSScroller) {
        let y = sender === vertical
        let clip = scroll.contentView
        let axis = ProjectTreeScrollAxis(
            viewport: y ? clip.bounds.height : clip.bounds.width,
            extent: y ? extentView.frame.height : extentView.frame.width)
        let current = y ? clip.bounds.minY : clip.bounds.minX
        let offset: CGFloat
        switch sender.hitPart {
        case .knob, .knobSlot: offset = axis.offset(for: sender.doubleValue)
        case .decrementLine: offset = current - 20
        case .incrementLine: offset = current + 20
        case .decrementPage: offset = current - axis.viewport * 0.9
        case .incrementPage: offset = current + axis.viewport * 0.9
        default: return
        }
        var origin = clip.bounds.origin
        if y { origin.y = axis.clamp(offset) } else { origin.x = axis.clamp(offset) }
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
    }
}
/// Pure scroll extent: no bitmap backing is allocated for a zoomed million-point
/// document. The actual drawing canvas is always viewport-sized above the scroll.
private final class ImageExtentView: NSView {
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = NSColor.clear.cgColor }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }
}
private enum ImagePreviewCommand { case fit, actual, larger, smaller }
private final class ImageScrollView: NSScrollView {
    var didReflect: () -> Void = {}
    var zoomGesture: (NSEvent, CGFloat) -> Void = { _, _ in }
    override func draw(_ dirtyRect: NSRect) {}
    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        didReflect()
    }
    override func magnify(with event: NSEvent) { zoomGesture(event, max(0.1, 1 + event.magnification)) }
    override func scrollWheel(with event: NSEvent) {
        if !event.modifierFlags.intersection([.command, .control]).isEmpty {
            zoomGesture(event, exp(event.scrollingDeltaY * 0.015))
        } else {
            super.scrollWheel(with: event)
        }
    }
}
private final class ImageCanvas: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }
    var imageRect = CGRect.zero { didSet { if oldValue != imageRect { needsDisplay = true } } }
    var background = ImagePreviewBackground.checkerboard { didSet { needsDisplay = true } }
    var zoomGesture: (NSEvent, CGFloat) -> Void = { _, _ in }
    var wheel: (NSEvent) -> Void = { _ in }
    var pan: (CGPoint) -> Void = { _ in }
    var command: (ImagePreviewCommand) -> Void = { _ in }
    private var dragPoint: CGPoint?
    private let checker: CGColor = {
        var callbacks = CGPatternCallbacks(
            version: 0,
            drawPattern: { _, context in
                context.setFillColor(CGColor(gray: 0.22, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
                context.setFillColor(CGColor(gray: 0.29, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
                context.fill(CGRect(x: 8, y: 8, width: 8, height: 8))
            }, releaseInfo: nil)
        let pattern = CGPattern(
            info: nil, bounds: CGRect(x: 0, y: 0, width: 16, height: 16), matrix: .identity,
            xStep: 16, yStep: 16, tiling: .constantSpacing, isColored: true, callbacks: &callbacks)!
        return CGColor(patternSpace: CGColorSpace(patternBaseSpace: nil)!, pattern: pattern, components: [1])!
    }()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        setAccessibilityRole(.image)
        setAccessibilityHelp("只读图片；拖动平移，触控板捏合或 ⌘滚轮缩放；⌥⌘0 适应窗口，⌥⌘1 原始尺寸")
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() {
        if image != nil { addCursorRect(visibleRect, cursor: dragPoint == nil ? .openHand : .closedHand) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { dragPoint = nil }
    }
    override func draw(_ dirtyRect: NSRect) {
        WorkbenchColors.nativeCanvas.setFill()
        dirtyRect.fill()
        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: dirtyRect)
        switch background {
        case .checkerboard: context.setFillColor(checker)
        case .light: context.setFillColor(CGColor(gray: 1, alpha: 1))
        case .dark: context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        }
        context.fill(imageRect)
        context.interpolationQuality = .high
        context.translateBy(x: imageRect.minX, y: imageRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: imageRect.size))
        context.restoreGState()
    }
    override func mouseDown(with event: NSEvent) {
        guard image != nil else { return }
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            command(.actual)
            return
        }
        dragPoint = event.locationInWindow
        window?.invalidateCursorRects(for: self)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let previous = dragPoint else { return }
        let point = event.locationInWindow
        dragPoint = point
        pan(CGPoint(x: previous.x - point.x, y: point.y - previous.y))
    }
    override func mouseUp(with event: NSEvent) {
        dragPoint = nil
        window?.invalidateCursorRects(for: self)
    }
    override func scrollWheel(with event: NSEvent) { wheel(event) }
    override func magnify(with event: NSEvent) { zoomGesture(event, max(0.1, 1 + event.magnification)) }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "+", "=": command(.larger)
            case "-": command(.smaller)
            case "0" where event.modifierFlags.contains(.option): command(.fit)
            case "1" where event.modifierFlags.contains(.option): command(.actual)
            default: super.keyDown(with: event)
            }
        } else {
            switch event.keyCode {
            case 123: pan(CGPoint(x: -30, y: 0))
            case 124: pan(CGPoint(x: 30, y: 0))
            case 125: pan(CGPoint(x: 0, y: 30))
            case 126: pan(CGPoint(x: 0, y: -30))
            default: super.keyDown(with: event)
            }
        }
    }
}
