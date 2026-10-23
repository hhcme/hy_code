import AppKit
import HyCodeWorkspace
import SwiftUI

@main
struct HyCodeApplication: App {
    @NSApplicationDelegateAdaptor(EditorApplicationDelegate.self) private var appDelegate
    @State private var store = WorkbenchStore()
    @AppStorage("workbench.appearance") private var appearance = WorkbenchAppearance.dark

    var body: some Scene {
        Window("HyCode", id: "workbench") {
            WorkbenchView(store: store, appearance: $appearance)
                .frame(minWidth: 860, minHeight: 540)
                .tint(WorkbenchColors.accent)
                .preferredColorScheme(appearance.colorScheme)
                .task {
                    appDelegate.store = store
                    store.restorePreviousProjectIfNeeded()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开项目目录…", action: store.chooseProject).keyboardShortcut("o")
                Button("关闭项目", action: store.closeProject).disabled(store.rootURL == nil)
                Divider()
                Button("保存", action: store.saveActiveDocument).keyboardShortcut("s")
                    .disabled(store.activeDocument == nil)
                Button("全部保存", action: store.saveAllDocuments).keyboardShortcut("s", modifiers: [.command, .option])
            }
            CommandMenu("图片") {
                Button("放大") { store.activeImage?.zoom(by: 1.25) }.keyboardShortcut("=")
                    .disabled(store.activeImage == nil)
                Button("缩小") { store.activeImage?.zoom(by: 1 / 1.25) }.keyboardShortcut("-")
                    .disabled(store.activeImage == nil)
                Divider()
                Button("适应窗口") { store.activeImage?.fit() }.keyboardShortcut("0", modifiers: [.command, .option])
                    .disabled(store.activeImage == nil)
                Button("原始尺寸") { store.activeImage?.zoom(to: 1) }.keyboardShortcut("1", modifiers: [.command, .option])
                    .disabled(store.activeImage == nil)
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
            CommandMenu("代码") {
                Button("跳转定义") { store.activeDocument?.semantic?.definition() }.keyboardShortcut("b")
                    .disabled(store.activeDocument?.semantic == nil)
                Button("查找引用") { store.activeDocument?.semantic?.references() }.keyboardShortcut(
                    "b", modifiers: [.command, .shift]
                )
                .disabled(store.activeDocument?.semantic == nil)
                Button("代码补全") { store.activeDocument?.semantic?.complete() }.keyboardShortcut(
                    .space, modifiers: .control
                )
                .disabled(store.activeDocument?.semantic == nil)
                Button("格式化文档") { store.activeDocument?.semantic?.format() }.keyboardShortcut(
                    "l", modifiers: [.command, .option]
                )
                .disabled(store.activeDocument?.semantic == nil)
                Divider()
                Group {
                    Button("跳转类型") { store.activeDocument?.semantic?.typeDefinition() }
                    Button("跳转实现") { store.activeDocument?.semantic?.implementation() }
                    Button("参数信息") { store.activeDocument?.semantic?.signatureHelp() }.keyboardShortcut("p")
                    Button("快速修复 / 重构…") { store.activeDocument?.semantic?.quickFix() }
                        .keyboardShortcut(.return, modifiers: .option)
                    Button("重命名…") { store.activeDocument?.semantic?.renameSymbol() }
                    Button("整理导入…") { store.activeDocument?.semantic?.organizeImports() }
                }.disabled(store.activeDocument?.semantic?.controller?.supportsWorkspaceEdits != true)
                Divider()
                Button("Dart / Flutter 依赖管理") {
                    store.analysisLanguage = "dart"
                    if !store.docking.isVisible(.analysis) { store.docking.toggle(.analysis) }
                }.disabled(store.rootURL == nil)
                Button("显示问题") {
                    if !store.docking.isVisible(.problems) { store.docking.toggle(.problems) }
                }
                Button("重启 Dart 分析器", action: store.dart.restart).disabled(store.rootURL == nil)
                Button("Web 依赖与脚本") {
                    store.analysisLanguage = "web"
                    if !store.docking.isVisible(.analysis) { store.docking.toggle(.analysis) }
                }.disabled(store.rootURL == nil)
                Button("重启 Web 分析器", action: store.web.restart).disabled(store.rootURL == nil)
            }
            CommandMenu("外观") {
                Picker("主题", selection: $appearance) {
                    ForEach(WorkbenchAppearance.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            }
            CommandMenu("Flutter") {
                Button("运行") { store.flutter.start(debug: false) }.keyboardShortcut("r", modifiers: [.control])
                    .disabled(!store.flutter.canStart)
                Button("调试") { store.flutter.start(debug: true) }.keyboardShortcut("d", modifiers: [.control])
                    .disabled(!store.flutter.canStart || store.flutter.launch.mode != .debug)
                Button("停止") { store.flutter.stop() }.keyboardShortcut(".", modifiers: [.control])
                    .disabled(!store.flutter.active && !store.flutter.commandRunning)
                Divider()
                Button("热重载") { store.flutter.control("hotReload") }.keyboardShortcut("\\", modifiers: [.command])
                    .disabled(!store.flutter.canReload)
                Button("热重启") { store.flutter.control("hotRestart") }.keyboardShortcut(
                    "\\", modifiers: [.command, .shift]
                )
                .disabled(!store.flutter.canReload)
                Button("继续") { store.flutter.control("continue") }.disabled(store.flutter.state.phase != .paused)
                Button("单步跳过") { store.flutter.control("next") }.disabled(store.flutter.state.phase != .paused)
                Button("进入") { store.flutter.control("stepIn") }.disabled(store.flutter.state.phase != .paused)
                Button("跳出") { store.flutter.control("stepOut") }.disabled(store.flutter.state.phase != .paused)
                Divider()
                Button("运行测试") { store.flutter.runCommand("test") }.disabled(!store.flutter.canStart)
                Button("编辑运行配置…") { store.flutter.dialog = .configuration }
                    .disabled(store.rootURL == nil || !store.flutter.canEditConfiguration)
                Button("查看断点…") { store.flutter.dialog = .breakpoints }
                    .disabled(store.rootURL == nil)
                Button("显示调试面板") {
                    if !store.docking.isVisible(.debug) { store.docking.toggle(.debug) }
                }.disabled(store.rootURL == nil)
            }
            CommandGroup(replacing: .help) {
                Text("HyCode · 文件浏览工作台")
            }
        }
        Settings { EditorSettingsView(store: store).preferredColorScheme(appearance.colorScheme) }
    }
}
