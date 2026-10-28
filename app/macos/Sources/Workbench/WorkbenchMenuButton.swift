import AppKit
import SwiftUI

@MainActor
struct WorkbenchMenuItem {
    var title: String
    var enabled = true
    var checked: Bool?
    var children: [WorkbenchMenuItem] = []
    var action: (() -> Void)?
    static var separator: Self { Self(title: "-") }
}

/// Shared label and popup chrome; a native anchor owns keyboard activation.
/// A transparent native button avoids NSPopUpButton's extra chevron, tint and label sizing.
struct WorkbenchMenuButton<Label: View>: View {
    let title: String
    let items: [WorkbenchMenuItem]
    var labelColor: Color = WorkbenchColors.text
    var neutral = false
    @ViewBuilder let label: () -> Label
    @State private var interaction = WorkbenchMenuInteraction()
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        label().foregroundStyle(labelColor).accessibilityHidden(true)
            .modifier(
                WorkbenchControlSurface(
                    active: interaction.open, neutral: neutral, hovering: interaction.hovering,
                    pressed: interaction.pressed, focused: interaction.focused)
            )
            .overlay {
                WorkbenchMenuAnchor(title: title, items: items) { interaction = $0 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .help(title)
            .onChange(of: enabled) { _, value in if !value { interaction = WorkbenchMenuInteraction() } }
            .onDisappear { interaction = WorkbenchMenuInteraction() }
    }
}

private struct WorkbenchMenuInteraction: Equatable {
    var hovering = false
    var pressed = false
    var focused = false
    var open = false
}

private struct WorkbenchMenuAnchor: NSViewRepresentable {
    let title: String
    let items: [WorkbenchMenuItem]
    let interactionChanged: (WorkbenchMenuInteraction) -> Void
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> MenuButton { MenuButton() }
    func updateNSView(_ button: MenuButton, context: Context) {
        button.updatingFromSwiftUI = true
        defer { button.updatingFromSwiftUI = false }
        button.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        button.items = items
        button.interactionChanged = interactionChanged
        button.isEnabled = enabled
        button.setAccessibilityLabel(title)
    }

    final class MenuButton: NSButton {
        var items: [WorkbenchMenuItem] = []
        private let popup = WorkbenchContextMenu()
        var updatingFromSwiftUI = false
        var interactionChanged: (WorkbenchMenuInteraction) -> Void = { _ in }
        private var interaction = WorkbenchMenuInteraction()
        private var lastPublished: WorkbenchMenuInteraction?
        private var tracking: NSTrackingArea?
        override var isEnabled: Bool {
            didSet {
                guard oldValue != isEnabled else { return }
                if !isEnabled { popup.hide() }
                interaction = WorkbenchMenuInteraction()
                lastPublished = nil
                window?.invalidateCursorRects(for: self)
            }
        }
        init() {
            super.init(frame: .zero)
            let menuCell = MenuButtonCell(textCell: "")
            cell = menuCell
            menuCell.highlightChanged = { [weak self] highlighted in
                guard let self else { return }
                interaction.pressed = isEnabled && highlighted
                if updatingFromSwiftUI {
                    publishInteractionLater()
                } else {
                    publishInteraction()
                }
            }
            title = ""
            isBordered = false
            focusRingType = .none
            target = self
            action = #selector(showMenu)
            let area = NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
            addTrackingArea(area)
            tracking = area
        }
        required init?(coder: NSCoder) { nil }
        // SwiftUI draws the shared feedback underneath the label; this native
        // overlay owns hit testing and keyboard activation only.
        override func draw(_ dirtyRect: NSRect) {}
        override func resetCursorRects() {
            super.resetCursorRects()
            if isEnabled, !visibleRect.isEmpty { addCursorRect(visibleRect, cursor: .pointingHand) }
        }
        override func mouseEntered(with event: NSEvent) {
            interaction.hovering = isEnabled
            publishInteraction()
        }
        override func mouseExited(with event: NSEvent) {
            interaction.hovering = false
            publishInteraction()
        }
        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            defer {
                interaction.pressed = false
                interaction.hovering =
                    window?.isKeyWindow == true
                    && visibleRect.contains(convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil))
                publishInteraction()
            }
            super.mouseDown(with: event)
        }
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            interaction.focused = accepted
            publishInteractionLater()
            return accepted
        }
        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            if accepted {
                interaction.focused = false
                publishInteractionLater()
            }
            return accepted
        }
        // Focus may be released by a representable update that hides a pane.
        // Publish after that update rather than mutate SwiftUI state inside it.
        private func publishInteractionLater() {
            Task { @MainActor [weak self] in self?.publishInteraction() }
        }
        private func publishInteraction() {
            guard lastPublished != interaction else { return }
            lastPublished = interaction
            interactionChanged(interaction)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { popup.hide() }
        }
        @objc private func showMenu() {
            guard isEnabled, let window else { return }
            interaction.open = true
            publishInteraction()
            popup.onClose = { [weak self] in
                guard let self else { return }
                interaction.open = false
                interaction.hovering = false
                publishInteractionLater()
            }
            popup.show(
                items.map(\.contextCommand), at: window.convertPoint(toScreen: convert(.zero, to: nil)),
                in: self, dropdown: true)
            if !popup.isVisible {
                interaction.open = false
                publishInteractionLater()
            }
        }
    }

    /// NSButtonCell owns drag-out/re-entry tracking and keyboard highlight.
    /// Mirror that state instead of latching a press for the whole tracking loop.
    final class MenuButtonCell: NSButtonCell {
        var highlightChanged: (Bool) -> Void = { _ in }
        override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
            super.highlight(flag, withFrame: cellFrame, in: controlView)
            highlightChanged(flag)
        }
    }
}

extension WorkbenchAppearance {
    @MainActor static func menuItems(selection: Binding<Self>) -> [WorkbenchMenuItem] {
        allCases.map { appearance in
            WorkbenchMenuItem(title: appearance.title, checked: selection.wrappedValue == appearance) {
                selection.wrappedValue = appearance
            }
        }
    }
}
