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

/// Draw the label ourselves; NSMenu owns popup interaction, keyboard and accessibility.
/// A transparent native button avoids NSPopUpButton's extra chevron, tint and label sizing.
struct WorkbenchMenuButton<Label: View>: View {
    let title: String
    let items: [WorkbenchMenuItem]
    @ViewBuilder let label: () -> Label
    @State private var interaction = WorkbenchMenuInteraction()
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        label().foregroundStyle(WorkbenchColors.text).accessibilityHidden(true)
            .modifier(
                WorkbenchControlSurface(
                    active: interaction.open, hovering: interaction.hovering,
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
        private var actions: [MenuAction] = []
        var updatingFromSwiftUI = false
        var interactionChanged: (WorkbenchMenuInteraction) -> Void = { _ in }
        private var interaction = WorkbenchMenuInteraction()
        private var lastPublished: WorkbenchMenuInteraction?
        private var tracking: NSTrackingArea?
        override var isEnabled: Bool {
            didSet {
                guard oldValue != isEnabled else { return }
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
        // overlay owns hit testing, keyboard behavior and NSMenu tracking only.
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
        @objc private func showMenu() {
            guard isEnabled else { return }
            interaction.open = true
            publishInteraction()
            defer {
                interaction.open = false
                interaction.hovering = false
                publishInteraction()
                actions.removeAll()
            }
            actions.removeAll()
            let menu = buildMenu(items)
            let y = isFlipped ? bounds.maxY + 3 : bounds.minY - 3
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: self)
        }
        private func buildMenu(_ items: [WorkbenchMenuItem]) -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for item in items {
                if item.title == "-" {
                    menu.addItem(.separator())
                    continue
                }
                let entry = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                entry.isEnabled = item.enabled
                if let checked = item.checked { entry.state = checked ? .on : .off }
                if !item.children.isEmpty { entry.submenu = buildMenu(item.children) }
                if let action = item.action {
                    let target = MenuAction(action)
                    actions.append(target)
                    entry.target = target
                    entry.action = #selector(MenuAction.invokeAction)
                }
                menu.addItem(entry)
            }
            return menu
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

@MainActor
private final class MenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invokeAction() { action() }
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
