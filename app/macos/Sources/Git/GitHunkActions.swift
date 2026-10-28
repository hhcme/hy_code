import AppKit
import HyCodeWorkspace

/// Actions always revalidate the active review and document revision in the
/// controller. These controls never own text, an index or a mutable patch.
struct GitHunkActions {
    let showsSelection: Bool
    let selectionEnabled: Bool
    let selectionHelp: String
    let restoreEnabled: Bool
    let restoreHelp: String
    let isSelected: @MainActor (Int) -> Bool
    let choose: @MainActor (Int, Bool) -> Void
    let restore: @MainActor (Int) -> Void
}

@MainActor final class GitHunkButton: NSButton {
    var perform: () -> Void = {}
    init(selection: Bool) {
        super.init(frame: .zero)
        if selection {
            setButtonType(.switch)
            title = ""
            controlSize = .small
        } else {
            isBordered = false
            imagePosition = .imageOnly
            image = NSImage(systemSymbolName: "chevron.right.2", accessibilityDescription: "还原此处更改")
            contentTintColor = WorkbenchColors.nativeSecondary
        }
        target = self
        action = #selector(clicked)
        focusRingType = .none
    }
    required init?(coder: NSCoder) { nil }
    @objc private func clicked() { perform() }
}
