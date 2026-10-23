import HyCodeWorkspace
import SwiftUI

struct FlutterRunConfigurationEditor: View {
    @Bindable var controller: FlutterWorkspaceController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FlutterConfigurationDraft
    @State private var definesText: String
    @State private var argumentsText: String
    @State private var error = ""
    init(controller: FlutterWorkspaceController) {
        self.controller = controller
        _draft = State(
            initialValue: FlutterConfigurationDraft(
                context: controller.configurationContext,
                configuration: controller.launch))
        _definesText = State(initialValue: controller.launch.defines.joined(separator: "\n"))
        _argumentsText = State(initialValue: controller.launch.arguments.joined(separator: "\n"))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkbenchDialogHeader(title: "运行 / 调试配置", symbol: "chevron.left.forwardslash.chevron.right")
            WorkbenchSeparator()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Flutter", systemImage: "play.rectangle").font(.system(size: 13, weight: .semibold))
                    Text(controller.project?.root.path ?? "尚未识别 Flutter 包")
                        .foregroundStyle(WorkbenchColors.secondary).textSelection(.enabled)
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("Dart 入口文件")
                            TextField("lib/main.dart", text: $draft.value.program)
                        }
                        GridRow {
                            Text("运行模式")
                            WorkbenchMenuButton(
                                title: "运行模式",
                                items: FlutterLaunchConfiguration.Mode.allCases.map { mode in
                                    WorkbenchMenuItem(title: mode.rawValue, checked: draft.value.mode == mode) {
                                        draft.value.mode = mode
                                    }
                                }
                            ) {
                                HStack {
                                    Text(draft.value.mode.rawValue)
                                    Spacer()
                                    Image(systemName: "chevron.down").font(.system(size: 9))
                                }.padding(.horizontal, 8).frame(width: 144, height: 28)
                                    .background(WorkbenchColors.field, in: RoundedRectangle(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4).strokeBorder(
                                            WorkbenchColors.tabBorder, lineWidth: 0.5))
                            }
                        }
                        GridRow {
                            Text("设备 ID")
                            TextField("从顶部设备菜单选择", text: $draft.value.deviceID)
                        }
                        GridRow {
                            Text("Build flavor")
                            TextField("可留空", text: $draft.value.flavor)
                        }
                        GridRow(alignment: .top) {
                            Text("Dart defines")
                            TextField("每行 KEY=VALUE", text: $definesText, axis: .vertical).lineLimit(3...6)
                        }
                        GridRow(alignment: .top) {
                            Text("运行参数")
                            TextField("每行一项", text: $argumentsText, axis: .vertical).lineLimit(3...6)
                        }
                    }.textFieldStyle(WorkbenchTextFieldStyle())
                    Toggle("Dart 文件保存成功后自动热重载", isOn: $draft.value.hotReloadOnSave).toggleStyle(.checkbox)
                    if !controller.available {
                        HStack {
                            Text("运行需要 Flutter SDK 与 Flutter 包").foregroundStyle(WorkbenchColors.secondary)
                            SettingsLink { Text("配置 SDK…") }
                        }
                    }
                    if !error.isEmpty { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(WorkbenchScrollStyle())
            }.frame(height: 370)
            WorkbenchSeparator()
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("确定") {
                    do {
                        draft.value.defines = definesText.components(separatedBy: "\n").filter { !$0.isEmpty }
                        draft.value.arguments = argumentsText.components(separatedBy: "\n").filter { !$0.isEmpty }
                        try controller.applyConfiguration(draft)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(WorkbenchActionButtonStyle(primary: true)).keyboardShortcut(.defaultAction).disabled(
                    !controller.canEditConfiguration)
            }.padding(12)
        }.workbenchContentStyle()
            .frame(width: 600)
    }
}

struct FlutterBreakpointsEditor: View {
    @Bindable var controller: FlutterWorkspaceController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkbenchDialogHeader(title: "断点", symbol: "smallcircle.filled.circle")
            WorkbenchSeparator()
            FlutterToolScroll {
                if controller.breakpoints.values.allSatisfy(\.isEmpty) {
                    FlutterToolEmpty("点击 Dart 行号栏添加断点", symbol: "smallcircle.filled.circle")
                }
                ForEach(controller.breakpoints.keys.sorted(), id: \.self) { path in
                    ForEach(controller.breakpoints[path] ?? []) { item in
                        FlutterBreakpointRow(controller: controller, path: path, item: item)
                    }
                }
            }.frame(height: 320)
            WorkbenchSeparator()
            HStack {
                Text("修改即时生效；实心断点表示适配器已确认").foregroundStyle(WorkbenchColors.secondary)
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(WorkbenchActionButtonStyle(primary: true)).keyboardShortcut(
                    .defaultAction)
            }.padding(12)
        }.workbenchContentStyle()
            .frame(width: 600)
    }
}

private struct FlutterBreakpointRow: View {
    @Bindable var controller: FlutterWorkspaceController
    let path: String
    let item: FlutterBreakpoint
    private func binding<T>(_ key: WritableKeyPath<FlutterBreakpoint, T>) -> Binding<T> {
        Binding(
            get: { (controller.breakpoints[path]?.first(where: { $0.line == item.line }) ?? item)[keyPath: key] },
            set: { value in
                var current = controller.breakpoints[path]?.first(where: { $0.line == item.line }) ?? item
                current[keyPath: key] = value
                controller.updateBreakpoint(path: path, value: current)
            })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("\(URL(fileURLWithPath: path).lastPathComponent):\(item.line)", isOn: binding(\.enabled))
                    .toggleStyle(.checkbox)
                Spacer()
                WorkbenchIconButton(title: "移除断点", symbol: "minus.circle", size: 24) {
                    controller.toggleBreakpoint(path: path, line: item.line)
                }
            }.help(path)
            TextField("暂停条件，可留空", text: binding(\.condition))
            TextField("日志断点内容，可留空", text: binding(\.logMessage))
        }.textFieldStyle(WorkbenchTextFieldStyle()).padding(8)
            .background(WorkbenchColors.tab, in: RoundedRectangle(cornerRadius: 4))
    }
}
