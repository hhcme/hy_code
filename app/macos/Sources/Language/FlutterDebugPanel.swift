import HyCodeWorkspace
import SwiftUI

struct FlutterDebugPanel: View {
    @Bindable var controller: FlutterWorkspaceController
    let headerHeight: CGFloat
    let hide: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("调试").fontWeight(.semibold).fixedSize()
                HStack(spacing: 6) {
                    Circle().fill(controller.active || controller.commandRunning ? Color.green : WorkbenchColors.muted)
                        .frame(width: 5, height: 5)
                    Text(controller.sessionTitle).lineLimit(1)
                }.padding(.horizontal, 10).frame(height: 28)
                    .background(WorkbenchColors.tab, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(WorkbenchColors.tabBorder, lineWidth: 0.5))
                Spacer(minLength: 0)
                WorkbenchIconButton(title: "隐藏调试面板", symbol: "minus", size: 24, action: hide)
            }.padding(.leading, 12).padding(.trailing, 6).frame(height: headerHeight)
            WorkbenchSeparator()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    FlutterDebuggerControls(controller: controller)
                    WorkbenchSeparator(vertical: true).frame(height: 18).padding(.horizontal, 4)
                    ForEach(FlutterToolSection.allCases) { section in
                        WorkbenchSectionTab(title: section.title, active: controller.section == section) {
                            controller.section = section
                        }
                    }
                }.padding(.horizontal, 8).frame(height: 34)
            }.fixedSize(horizontal: false, vertical: true)
            WorkbenchSeparator()
            Group {
                switch controller.section {
                case .debugger: FlutterDebuggerContent(controller: controller)
                case .console: FlutterConsoleContent(controller: controller)
                case .inspector: FlutterInspectorContent(controller: controller)
                case .tests: FlutterTestContent(controller: controller)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            WorkbenchSeparator()
            FlutterToolStatus(controller: controller)
        }.workbenchContentStyle()
    }
}

private struct FlutterDebuggerControls: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        HStack(spacing: 2) {
            FlutterActionButton(
                title: controller.state.phase == .paused ? "继续" : "暂停",
                symbol: controller.state.phase == .paused ? "play.fill" : "pause.fill", color: .green
            ) {
                controller.control(controller.state.phase == .paused ? "continue" : "pause")
            }.disabled(![.running, .paused].contains(controller.state.phase) || controller.controlsBusy)
            FlutterActionButton(title: "停止会话或任务", symbol: "stop", color: .red) { controller.stop() }
                .disabled(!controller.active && !controller.commandRunning)
            Group {
                WorkbenchIconButton(title: "单步跳过", symbol: "arrow.turn.down.right") { controller.control("next") }
                WorkbenchIconButton(title: "单步进入", symbol: "arrow.down.to.line") { controller.control("stepIn") }
                WorkbenchIconButton(title: "单步跳出", symbol: "arrow.up.to.line") { controller.control("stepOut") }
            }.disabled(controller.state.phase != .paused || controller.controlsBusy)
            WorkbenchIconButton(title: "查看与编辑断点", symbol: "smallcircle.filled.circle") {
                controller.dialog = .breakpoints
            }
            FlutterActionButton(title: "热重载 ⌘\\", symbol: "bolt.fill", color: .yellow) {
                controller.control("hotReload")
            }.disabled(!controller.canReload)
            FlutterActionButton(title: "热重启 ⇧⌘\\", symbol: "arrow.clockwise", color: .green) {
                controller.control("hotRestart")
            }.disabled(!controller.canReload)
        }
    }
}

private struct FlutterToolStatus: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        Text(controller.status).lineLimit(1).help(controller.status)
            .font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 24)
    }
}

private struct FlutterConsoleContent: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        ScrollView {
            Text(controller.output.isEmpty ? "运行后在此显示控制台输出" : controller.output)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(controller.output.isEmpty ? WorkbenchColors.secondary : WorkbenchColors.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
                .background(WorkbenchScrollStyle())
        }.padding(.trailing, 4).padding(.bottom, 8)
    }
}

private struct FlutterInspectorContent: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                WorkbenchIconButton(
                    title: "刷新 Widget 树", symbol: "arrow.clockwise", action: controller.refreshInspector
                )
                .disabled(!controller.canInspect || controller.inspectorBusy)
                Text("Widget 树").foregroundStyle(WorkbenchColors.secondary)
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).frame(height: 32)
            WorkbenchSeparator()
            FlutterToolScroll {
                if controller.widgets.isEmpty {
                    FlutterToolEmpty("连接调试会话后刷新 Widget 树", symbol: "rectangle.3.group")
                }
                ForEach(controller.widgets) { row in
                    Button {
                        controller.selectWidget(row)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.dashed").foregroundStyle(WorkbenchColors.accent)
                            Text(row.label).lineLimit(1)
                        }.padding(.leading, CGFloat(row.depth) * 12).padding(.horizontal, 6).frame(height: 24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(WorkbenchButtonStyle()).help(row.label)
                }
            }
        }
    }
}

private struct FlutterTestContent: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    testPath
                    testActions
                }
                VStack(alignment: .leading, spacing: 6) {
                    testPath
                    testActions
                }
            }.padding(8)
            WorkbenchSeparator()
            FlutterToolScroll {
                if controller.tests.done {
                    Label(
                        controller.tests.success ? "测试全部通过" : "存在失败测试",
                        systemImage: controller.tests.success ? "checkmark.circle" : "exclamationmark.circle"
                    )
                    .foregroundStyle(controller.tests.success ? Color.green : .orange).padding(6)
                } else if controller.tests.items.isEmpty {
                    FlutterToolEmpty("运行测试后在此显示结果", symbol: "checkmark.diamond")
                }
                if controller.tests.limited { Text("结果超过保留上限，查看控制台输出").foregroundStyle(.orange) }
                ForEach(controller.tests.items.values.sorted { $0.id < $1.id }) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.status + " · " + item.name)
                        if !item.error.isEmpty { Text(item.error).foregroundStyle(.orange).textSelection(.enabled) }
                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private var testPath: some View {
        TextField("测试文件或目录，留空运行全部", text: $controller.testPath).textFieldStyle(WorkbenchTextFieldStyle())
            .frame(minWidth: 130).disabled(controller.active || controller.commandRunning)
    }
    private var testActions: some View {
        HStack(spacing: 8) {
            Toggle("生成覆盖率", isOn: $controller.coverage).toggleStyle(.checkbox)
                .disabled(controller.active || controller.commandRunning)
            FlutterActionButton(title: "运行测试", symbol: "play.fill", color: .green) { controller.runCommand("test") }
                .disabled(!controller.canStart)
        }.fixedSize()
    }
}

struct FlutterToolScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2, content: content)
                .frame(maxWidth: .infinity, alignment: .topLeading).padding(6)
                .background(WorkbenchScrollStyle())
        }.padding(.trailing, 4).padding(.bottom, 8)
    }
}

struct FlutterToolEmpty: View {
    let title: String
    let symbol: String
    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }
    var body: some View {
        Label(title, systemImage: symbol).foregroundStyle(WorkbenchColors.secondary)
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
    }
}
