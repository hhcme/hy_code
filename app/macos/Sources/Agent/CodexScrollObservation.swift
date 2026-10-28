import AppKit
import HyCodeWorkspace
import SwiftUI

/// Observes only the containing chat scroll view. No global event monitor,
/// synthetic scroll, window manipulation, or application-wide observer.
struct CodexScrollObservation: NSViewRepresentable {
    let onScroll: (Bool) -> Void
    func makeNSView(context: Context) -> Probe { Probe(onScroll: onScroll) }
    func updateNSView(_ view: Probe, context: Context) {
        view.onScroll = onScroll
        view.attachWhenReady()
    }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.detach() }

    @MainActor final class Probe: NSView {
        var onScroll: (Bool) -> Void
        private weak var scroll: NSScrollView?
        private var observations: [NSObjectProtocol] = []
        private var live = false
        init(onScroll: @escaping (Bool) -> Void) {
            self.onScroll = onScroll
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attachWhenReady()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachWhenReady()
        }
        func attachWhenReady() {
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }
        private func attach() {
            guard window != nil, let candidate = enclosingScrollView, candidate !== scroll else { return }
            detach()
            scroll = candidate
            candidate.contentView.postsBoundsChangedNotifications = true
            observe(NSScrollView.willStartLiveScrollNotification, object: candidate) { owner in
                owner.live = true
                owner.onScroll(false)
            }
            observe(NSScrollView.didEndLiveScrollNotification, object: candidate) { owner in
                owner.live = false
                owner.report()
            }
            observe(NSView.boundsDidChangeNotification, object: candidate.contentView) { owner in
                let event = NSApp?.currentEvent?.type
                if owner.live {
                    owner.onScroll(false)
                } else if event == .scrollWheel || event == .leftMouseDragged {
                    owner.report()
                }
            }
        }
        private func observe(_ name: Notification.Name, object: AnyObject, action: @escaping @MainActor (Probe) -> Void)
        {
            observations.append(
                NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if let self { action(self) } }
                })
        }
        private func report() {
            guard let scroll, let document = scroll.documentView else { return }
            let clip = scroll.contentView.documentVisibleRect
            let bottom = document.isFlipped ? clip.maxY : document.bounds.height - clip.minY
            let following = CodexChatPresentation.nearBottom(
                documentHeight: document.bounds.height, viewportBottom: bottom)
            DispatchQueue.main.async { [weak self] in self?.onScroll(following) }
        }
        func detach() {
            for observation in observations { NotificationCenter.default.removeObserver(observation) }
            observations.removeAll()
            scroll = nil
            live = false
        }
    }
}
