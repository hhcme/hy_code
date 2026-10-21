import AppKit

/// Each native menu retains its own action targets until tracking ends, including
/// submenus. The tree/coordinator is held weakly by the supplied action closures.
@MainActor enum ProjectTreeContextMenu {
    static func make(_ items: [WorkbenchMenuItem]) -> NSMenu {
        let menu = ActionMenu(title: "")
        menu.autoenablesItems = false
        for item in items {
            if item.title == "-" {
                menu.addItem(.separator())
                continue
            }
            let entry = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            entry.isEnabled = item.enabled
            if let checked = item.checked { entry.state = checked ? .on : .off }
            if !item.children.isEmpty { entry.submenu = make(item.children) }
            if let action = item.action {
                let target = Action(action)
                menu.targets.append(target)
                entry.target = target
                entry.action = #selector(Action.invoke)
            }
            menu.addItem(entry)
        }
        return menu
    }

    private final class ActionMenu: NSMenu {
        var targets: [Action] = []
    }
    private final class Action: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func invoke() { action() }
    }
}
