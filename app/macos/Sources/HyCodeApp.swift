import AppKit
import HyCodeWorkspace
import SwiftUI

@main
struct HyCodeApplication: App {
    @State private var store = WorkbenchStore()
    @AppStorage("workbench.appearance") private var appearance = WorkbenchAppearance.dark

    var body: some Scene {
        Window("HyCode", id: "workbench") {
            WorkbenchView(store: store, appearance: $appearance)
                .frame(minWidth: 860, minHeight: 540)
                .tint(WorkbenchColors.accent)
                .preferredColorScheme(appearance.colorScheme)
                .task { store.restorePreviousProjectIfNeeded() }
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开项目目录…", action: store.chooseProject).keyboardShortcut("o")
                Button("关闭项目", action: store.closeProject).disabled(store.rootURL == nil)
            }
            CommandMenu("浏览") {
                Button("后退", action: store.goBack).keyboardShortcut("[", modifiers: .command).disabled(
                    !store.history.canGoBack)
                Button("前进", action: store.goForward).keyboardShortcut("]", modifiers: .command).disabled(
                    !store.history.canGoForward)
                Button("上级目录", action: store.goToParent).keyboardShortcut(.upArrow, modifiers: .command).disabled(
                    store.location?.parentDirectory == nil)
                Divider()
                Button("打开所选项", action: store.openSelected).keyboardShortcut(.downArrow, modifiers: .command).disabled(
                    store.selectedEntry == nil)
                Button("刷新目录", action: store.refresh).keyboardShortcut("r").disabled(store.rootURL == nil)
                Button("取消目录读取", action: store.cancelReading).disabled(!store.isLoading)
            }
            CommandMenu("工具窗口") {
                ForEach(WorkbenchTool.allCases) { tool in
                    let binding = Binding(
                        get: { store.docking.isVisible(tool) },
                        set: { if $0 != store.docking.isVisible(tool) { store.docking.toggle(tool) } })
                    if let key = tool.shortcut {
                        Toggle(tool.title, isOn: binding).keyboardShortcut(KeyEquivalent(key))
                    } else {
                        Toggle(tool.title, isOn: binding)
                    }
                }
                Divider()
                Toggle("显示隐藏文件", isOn: $store.includeHidden).keyboardShortcut(".", modifiers: [.command, .shift])
            }
            CommandMenu("外观") {
                Picker("主题", selection: $appearance) {
                    ForEach(WorkbenchAppearance.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            }
            CommandGroup(replacing: .help) {
                Text("HyCode · 文件浏览工作台")
            }
        }
    }
}
