import AppKit
import HyCodeWorkspace
import QuartzCore
import SwiftUI

/// The native canvas owns live geometry; SwiftUI supplies content and docking changes.
struct WorkbenchCanvas: NSViewRepresentable {
    let docking: WorkbenchDocking
    let workspaceSession: UUID
    let editor: AnyView
    let tools: [WorkbenchTool: AnyView]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> NativeWorkbenchCanvas { NativeWorkbenchCanvas() }
    func updateNSView(_ view: NativeWorkbenchCanvas, context: Context) {
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        func root(_ content: AnyView) -> AnyView {
            AnyView(
                content.font(.system(size: 13)).controlSize(.small)
                    .tint(WorkbenchColors.accent).environment(\.colorScheme, colorScheme)
                    .transaction {
                        $0.animation = nil
                        $0.disablesAnimations = true
                    })
        }
        view.update(
            editor: root(editor), tools: tools.mapValues(root), docking: docking,
            workspaceSession: workspaceSession, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: NativeWorkbenchCanvas, coordinator: ()) { view.stopActivity() }
}

@MainActor
final class NativeWorkbenchCanvas: NSView {
    private let panes = (0..<5).map { _ in WorkbenchPaneHost() }
    private let editorHost = NSHostingView(rootView: AnyView(EmptyView()))
    private var toolHosts: [WorkbenchTool: NSHostingView<AnyView>] = [:]
    private var dividers: [WorkbenchDivider: WorkbenchResizeHandle] = [:]
    private var sizes = WorkbenchPaneSizes()
    private var visibility = WorkbenchVisibility()
    private var initialized = false
    private var contentLayoutDirty = true
    private var lastVisibleTools: Set<WorkbenchTool> = []
    private var displayRefresh: CADisplayLink?
    private var settleTimer: Timer?
    private lazy var refreshTarget = WorkbenchRefreshTarget(owner: self)
    private var animating = false
    private var animationStart: TimeInterval = 0
    private var animationFrom: WorkbenchPaneFrames?
    private var presented: WorkbenchPaneFrames?
    private var contentTransitions = Array(repeating: false, count: 5)
    private var previousSize = CGSize.zero
    private var interaction = WorkbenchResizeInteraction()
    private let resizeIndicator = CALayer()
    private var lastIndicator: WorkbenchDividerIndicator?
    private var indicatorAppearance: NSAppearance.Name?
    private weak var observedWindow: NSWindow?
    private var pointerTracking: NSTrackingArea?
    private var lastDocking: WorkbenchDocking?
    private var workspaceSession: UUID?
    private var deferredContent: (editor: AnyView, tools: [WorkbenchTool: AnyView])?
    private var liveResize: Bool { interaction.dragging != nil }
    override var isFlipped: Bool { true }
    private var scale: Double { Double(window?.backingScaleFactor ?? 2) }
    private var flags: [Bool] {
        [visibility.project, true, visibility.information, visibility.openTabs, visibility.workspace]
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        editorHost.sizingOptions = []
        editorHost.safeAreaRegions = []
        for pane in panes { addSubview(pane) }
        panes[1].mount(editorHost)
        for axis in WorkbenchDivider.allCases {
            let handle = WorkbenchResizeHandle(axis: axis)
            handle.readValue = { [weak self] in self?.dividerValue(axis) ?? 0 }
            handle.beginResize = { [weak self] in self?.beginLiveResize(axis) }
            handle.resize = { [weak self] value in self?.resize(axis, value: value) }
            handle.endResize = { [weak self] in self?.endLiveResize() }
            handle.focusChanged = { [weak self] focused in self?.focusDivider(focused ? axis : nil) }
            dividers[axis] = handle
            addSubview(handle)
        }
        resizeIndicator.isHidden = true
        resizeIndicator.zPosition = 1000
        layer?.addSublayer(resizeIndicator)
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag,
            ],
            owner: self)
        addTrackingArea(tracking)
        pointerTracking = tracking
    }
    required init?(coder: NSCoder) { nil }

    func update(
        editor: AnyView, tools: [WorkbenchTool: AnyView], docking: WorkbenchDocking,
        workspaceSession: UUID, reduceMotion: Bool
    ) {
        // Directory completions may arrive while the pointer is held. Keep only
        // the latest roots; do not rebind every visible SwiftUI host mid-drag.
        if liveResize, lastDocking == docking, self.workspaceSession == workspaceSession {
            deferredContent = (editor, tools)
            return
        }
        if liveResize {
            deferredContent = nil
            endLiveResize()
        }
        lastDocking = docking
        self.workspaceSession = workspaceSession
        let visibility = docking.visibility
        contentLayoutDirty = true
        if self.visibility != visibility {
            interaction.reset()
            updateIndicator()
            let old = flags
            let wasAnimating = animating
            animationFrom = presented
            animationStart = ProcessInfo.processInfo.systemUptime
            self.visibility = visibility
            for index in contentTransitions.indices {
                contentTransitions[index] = old[index] != flags[index] || (wasAnimating && contentTransitions[index])
            }
            if initialized, window != nil, !reduceMotion { startAnimation() } else { stopAnimation() }
        } else if reduceMotion {
            stopAnimation()
        }
        initialized = true
        updateContent(editor: editor, tools: tools, docking: docking)
        needsLayout = true
    }

    private func updateContent(editor: AnyView, tools: [WorkbenchTool: AnyView], docking: WorkbenchDocking) {
        let interval = WorkbenchPerformance.begin("HostRootUpdate")
        defer { WorkbenchPerformance.end("HostRootUpdate", interval) }
        contentLayoutDirty = true
        editorHost.rootView = editor
        // Create each tool's host only when first opened; keep it through tab switches
        // and reparent the same host when moving corners, preserving the native tree.
        for tool in docking.active.values where toolHosts[tool] == nil {
            let host = NSHostingView(rootView: AnyView(EmptyView()))
            host.sizingOptions = []
            host.safeAreaRegions = []
            toolHosts[tool] = host
        }
        for (tool, host) in toolHosts {
            let shown = docking.isVisible(tool)
            if shown || lastVisibleTools.contains(tool), let root = tools[tool] {
                host.rootView = AnyView(root.disabled(!shown).allowsHitTesting(shown).accessibilityHidden(!shown))
            }
            host.setAccessibilityHidden(!shown)
            if !shown { releaseFocus(in: host) }
        }
        lastVisibleTools = Set(docking.active.values)
        for corner in WorkbenchCorner.allCases {
            let pane = panes[corner.paneIndex]
            if let tool = docking.active[corner], let host = toolHosts[tool] { pane.mount(host) }
            pane.interactive = docking.active[corner] != nil
            pane.setAccessibilityHidden(!pane.interactive)
            if !pane.interactive { releaseFocus(in: pane) }
        }
        needsLayout = true
    }

    private func releaseFocus(in view: NSView) {
        if let responder = window?.firstResponder as? NSView, responder === view || responder.isDescendant(of: view) {
            window?.makeFirstResponder(nil)
        }
    }

    override func layout() {
        super.layout()
        applyGeometry()
    }

    private func applyGeometry() {
        let interval = WorkbenchPerformance.begin("CanvasLayout")
        defer { WorkbenchPerformance.end("CanvasLayout", interval) }
        if previousSize != bounds.size {
            interaction.clearHover()
            stopAnimation()
            previousSize = bounds.size
        }
        let target = sizes.frames(width: bounds.width, height: bounds.height, visibility: visibility, scale: scale)
        let frames: WorkbenchPaneFrames
        if let from = animationFrom, animating {
            let t = min(1, (ProcessInfo.processInfo.systemUptime - animationStart) / 0.20)
            frames = from.interpolated(to: target, progress: t * t * (3 - 2 * t), scale: scale)
            if t >= 1 { stopAnimation() }
        } else {
            frames = target
        }
        // Pointer deltas smaller than a backing pixel, or clamped at an edge,
        // must not send identical frames back through every hosting view.
        guard contentLayoutDirty || presented != frames else { return }
        contentLayoutDirty = false
        presented = frames
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let rectangles = [frames.project, frames.editor, frames.information, frames.openTabs, frames.workspace]
        let targets = [target.project, target.editor, target.information, target.openTabs, target.workspace]
        let sources = animationFrom.map { [$0.project, $0.editor, $0.information, $0.openTabs, $0.workspace] }
        for (index, pane) in panes.enumerated() {
            let hidden = rectangles[index].isEmpty
            if pane.isHidden != hidden { pane.isHidden = hidden }
            // A hidden host keeps its last content size, avoiding a zero-size
            // SwiftUI reflow during unrelated splitter movements.
            if hidden { continue }
            pane.anchorTrailing = contentTransitions[index] && (index == 0 || index == 3)
            if let source = sources?[index], animating, contentTransitions[index] {
                pane.contentSize = CGSize(
                    width: max(pane.contentSize.width, source.width, targets[index].width),
                    height: max(pane.contentSize.height, source.height, targets[index].height))
            } else {
                pane.contentSize = rectangles[index].size
            }
            let changed = pane.frame != rectangles[index]
            if changed { pane.frame = rectangles[index] }
            pane.layoutContent()
        }
        for (axis, handle) in dividers {
            let shown: Bool
            switch axis {
            case .project: shown = visibility.project
            case .information: shown = visibility.information
            case .bottom: shown = visibility.openTabs || visibility.workspace
            case .bottomSplit: shown = visibility.openTabs && visibility.workspace
            }
            let hidden = !shown || frames[axis].isEmpty
            if handle.isHidden != hidden { handle.isHidden = hidden }
            handle.interactive = shown && !animating
            if handle.frame != frames[axis] { handle.frame = frames[axis] }
        }
        updateIndicator()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installWindowObservers()
        if window == nil { stopActivity() }
        needsLayout = true
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    private func dividerValue(_ axis: WorkbenchDivider) -> Double {
        guard let f = presented else { return 0 }
        switch axis {
        case .project: return f.project.width
        case .information: return f.information.width
        case .bottom: return max(f.openTabs.height, f.workspace.height)
        case .bottomSplit: return f.openTabs.width
        }
    }
    private func resize(_ axis: WorkbenchDivider, value: Double) {
        if liveResize { interaction.enqueue(axis, value: value) } else { applyResize(axis, value: value) }
    }
    @discardableResult
    private func applyResize(_ axis: WorkbenchDivider, value: Double, scheduleLayout: Bool = true) -> Bool {
        let previous = sizes
        sizes.resize(axis, to: value, width: bounds.width, height: bounds.height, visibility: visibility)
        let changed = previous != sizes
        if changed, scheduleLayout { needsLayout = true }
        return changed
    }
    private func beginLiveResize(_ axis: WorkbenchDivider) {
        interaction.begin(axis)
        updateIndicator()
        startRefresh()
    }
    private func endLiveResize() {
        let pending = interaction.finish()
        for handle in dividers.values { handle.clearTracking() }
        if let pending { applyResize(pending.axis, value: pending.value, scheduleLayout: false) }
        // Clear even when no geometry changed, and before applying deferred roots.
        updateIndicator()
        if let deferred = deferredContent, let docking = lastDocking {
            deferredContent = nil
            updateContent(editor: deferred.editor, tools: deferred.tools, docking: docking)
        }
        applyGeometry()
        if !animating { stopRefresh() }
    }

    private func startAnimation() {
        animating = true
        settleTimer?.invalidate()
        // The one-shot deadline also completes while occluded, when display callbacks stop.
        let timer = Timer(
            timeInterval: 0.20, target: refreshTarget, selector: #selector(WorkbenchRefreshTarget.settle),
            userInfo: nil, repeats: false)
        settleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        startRefresh()
    }
    private func startRefresh() {
        guard displayRefresh == nil, window != nil else { return }
        let link = displayLink(target: refreshTarget, selector: #selector(WorkbenchRefreshTarget.tick))
        displayRefresh = link
        link.add(to: .main, forMode: .common)
    }
    private func stopRefresh() {
        displayRefresh?.invalidate()
        displayRefresh = nil
    }
    fileprivate func displayTick() {
        let interval = WorkbenchPerformance.begin("ResizeDisplayTick")
        defer { WorkbenchPerformance.end("ResizeDisplayTick", interval) }
        // AppKit normally delivers mouseUp to the original view even outside it.
        // Recover if tracking was interrupted and that final callback was missed.
        if liveResize, NSEvent.pressedMouseButtons & 1 == 0 {
            endLiveResize()
            return
        }
        var changed = false
        if let pending = interaction.takePending() {
            changed = applyResize(pending.axis, value: pending.value, scheduleLayout: false)
        }
        // Apply in this display callback, without scheduling a second run-loop
        // layout pass or forcing layoutSubtreeIfNeeded through every hosting view.
        if changed || animating { applyGeometry() }
    }
    fileprivate func finishAnimation() {
        stopAnimation()
        needsLayout = true
    }
    private func stopAnimation() {
        // Even if the last rounded animation frame already equals its target,
        // the final content-size commit must not be skipped.
        if animating { contentLayoutDirty = true }
        animating = false
        settleTimer?.invalidate()
        settleTimer = nil
        animationFrom = nil
        contentTransitions = Array(repeating: false, count: 5)
        if !liveResize { stopRefresh() }
    }
    func stopActivity() {
        interaction.reset()
        deferredContent = nil
        for handle in dividers.values { handle.clearTracking() }
        updateIndicator()
        stopAnimation()
        stopRefresh()
        removeWindowObservers()
    }

    override func mouseEntered(with event: NSEvent) { trackPointer(event, moved: false) }
    override func mouseMoved(with event: NSEvent) { trackPointer(event, moved: true) }
    override func mouseExited(with event: NSEvent) {
        interaction.clearHover()
        updateIndicator()
    }
    private func trackPointer(_ event: NSEvent, moved: Bool) {
        guard window?.isKeyWindow == true, NSApp?.isActive == true, !animating, let presented else {
            interaction.clearHover()
            updateIndicator()
            return
        }
        if !liveResize, NSEvent.pressedMouseButtons != 0 {
            interaction.clearHover()
        } else {
            interaction.pointer(at: convert(event.locationInWindow, from: nil), frames: presented, moved: moved)
        }
        updateIndicator()
    }
    private func focusDivider(_ axis: WorkbenchDivider?) {
        interaction.focus(axis)
        updateIndicator()
    }
    private func updateIndicator() {
        let active =
            window?.isKeyWindow == true && NSApp?.isActive == true && !isHiddenOrHasHiddenAncestor && !animating
        let state = active ? presented.flatMap { interaction.indicator(in: $0, scale: scale) } : nil
        let appearance = effectiveAppearance.name
        guard state != lastIndicator || appearance != indicatorAppearance else { return }
        lastIndicator = state
        indicatorAppearance = appearance
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        resizeIndicator.removeAllAnimations()
        resizeIndicator.isHidden = state == nil
        resizeIndicator.frame = state?.frame ?? .zero
        if let state {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                resizeIndicator.backgroundColor =
                    (state.emphasized ? WorkbenchColors.nativeAccent : WorkbenchColors.nativeSecondary)
                    .withAlphaComponent(0.55).cgColor
            }
        } else {
            resizeIndicator.backgroundColor = nil
        }
        CATransaction.commit()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateIndicator()
    }
    private func installWindowObservers() {
        guard observedWindow !== window else { return }
        removeWindowObservers()
        guard let window else { return }
        observedWindow = window
        let center = NotificationCenter.default
        for name in [
            NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification, NSWindow.willCloseNotification,
        ] {
            center.addObserver(self, selector: #selector(interruptInteraction), name: name, object: window)
        }
        center.addObserver(
            self, selector: #selector(interruptInteraction), name: NSApplication.didResignActiveNotification,
            object: nil)
    }
    private func removeWindowObservers() {
        let center = NotificationCenter.default
        if let observedWindow {
            for name in [
                NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification, NSWindow.willCloseNotification,
            ] {
                center.removeObserver(self, name: name, object: observedWindow)
            }
        }
        center.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
        observedWindow = nil
    }
    @objc private func interruptInteraction(_ notification: Notification) {
        endLiveResize()
        interaction.reset()
        updateIndicator()
    }
}

@MainActor
private final class WorkbenchRefreshTarget: NSObject {
    weak var owner: NativeWorkbenchCanvas?
    init(owner: NativeWorkbenchCanvas) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) {
        if let owner { owner.displayTick() } else { link.invalidate() }
    }
    @objc func settle(_ timer: Timer) { owner?.finishAnimation() }
}

extension WorkbenchCorner {
    fileprivate var paneIndex: Int {
        switch self {
        case .topLeading: 0
        case .topTrailing: 2
        case .bottomLeading: 3
        case .bottomTrailing: 4
        }
    }
}

@MainActor
private final class WorkbenchPaneHost: NSView {
    private(set) var host: NSHostingView<AnyView>?
    var interactive = true
    var anchorTrailing = false
    var contentSize = CGSize.zero
    override var isFlipped: Bool { true }
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = WorkbenchMetrics.islandRadius
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { nil }
    func mount(_ host: NSHostingView<AnyView>) {
        guard self.host !== host else { return }
        self.host?.removeFromSuperview()
        if let previous = host.superview as? WorkbenchPaneHost { previous.host = nil }
        host.removeFromSuperview()
        self.host = host
        addSubview(host)
        layoutContent()
    }
    func layoutContent() {
        let width = max(bounds.width, contentSize.width)
        let rect = CGRect(
            x: anchorTrailing ? bounds.width - width : 0, y: 0, width: width,
            height: max(bounds.height, contentSize.height))
        guard let host, host.frame != rect else { return }
        let interval = WorkbenchPerformance.begin("HostContentResize")
        defer { WorkbenchPerformance.end("HostContentResize", interval) }
        host.frame = rect
    }
    override func layout() {
        super.layout()
        layoutContent()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { interactive ? super.hitTest(point) : nil }
}
