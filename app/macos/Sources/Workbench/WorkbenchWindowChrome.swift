import AppKit
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
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateChrome()
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
