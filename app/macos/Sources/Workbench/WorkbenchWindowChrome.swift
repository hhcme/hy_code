import AppKit
import HyCodeWorkspace
import SwiftUI

/// Configures only the window containing this view. Never activates or moves it.
struct WorkbenchWindowChrome: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> ChromeView { ChromeView() }

    func updateNSView(_ view: ChromeView, context: Context) {
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        view.updateChrome()
    }

    final class ChromeView: NSView {
        private weak var observedWindow: NSWindow?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observeWindow()
            updateChrome()
        }
        deinit { NotificationCenter.default.removeObserver(self) }
        override func layout() {
            super.layout()
            alignWindowControls()
        }
        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            alignWindowControls()
        }
        private func observeWindow() {
            guard observedWindow !== window else { return }
            NotificationCenter.default.removeObserver(self)
            observedWindow = window
            guard let window else { return }
            for name in [NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowChanged), name: name, object: window)
            }
        }
        @objc private func windowChanged(_ notification: Notification) { needsLayout = true }

        private func alignWindowControls() {
            guard let window, !window.styleMask.contains(.fullScreen), let content = window.contentView else { return }
            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (index, type) in types.enumerated() {
                guard let button = window.standardWindowButton(type), let parent = button.superview else { continue }
                let target = WorkbenchChromeGeometry.trafficLight(
                    size: button.frame.size, index: index, scale: window.backingScaleFactor)
                let rect = NSRect(
                    x: content.bounds.minX + target.minX,
                    y: content.isFlipped ? content.bounds.minY + target.minY : content.bounds.maxY - target.maxY,
                    width: target.width, height: target.height)
                let origin = parent.convert(rect, from: content).origin
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
        }

        func updateChrome() {
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
            window.isOpaque = true
            effectiveAppearance.performAsCurrentDrawingAppearance {
                window.backgroundColor =
                    NSColor(cgColor: WorkbenchColors.nativeChrome.cgColor) ?? WorkbenchColors.nativeChrome
            }
            window.setAutorecalculatesContentBorderThickness(false, for: .minY)
            window.setContentBorderThickness(0, for: .minY)
            alignWindowControls()
        }
    }
}

/// Native dragging on the empty header background leaves buttons interactive.
struct WorkbenchWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
