import HyCodeWorkspace
import SwiftUI

struct FlutterDebuggerContent: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        GeometryReader { geometry in
            // Native split views own their local divider tracking. No workbench
            // observable state, disk writes or language requests on drag events.
            if geometry.size.width >= 480 && geometry.size.height >= 120 {
                HSplitView {
                    FlutterStackContent(controller: controller).frame(minWidth: 150, idealWidth: 240)
                    FlutterVariablesContent(controller: controller).frame(minWidth: 200)
                }
            } else if geometry.size.height < 220 {
                FlutterToolScroll {
                    Text("调用栈").fontWeight(.medium).padding(8)
                    FlutterStackRows(controller: controller)
                    WorkbenchSeparator()
                    FlutterVariablesHeader(controller: controller)
                    FlutterVariableRows(controller: controller)
                    WorkbenchSeparator()
                    FlutterEvaluationContent(controller: controller)
                    FlutterEvaluationResult(controller: controller)
                }
            } else {
                VSplitView {
                    FlutterStackContent(controller: controller).frame(minHeight: 60, idealHeight: 110)
                    FlutterVariablesContent(controller: controller).frame(minHeight: 150)
                }
            }
        }
    }
}

private struct FlutterStackContent: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("调用栈").fontWeight(.medium)
                Spacer(minLength: 0)
                if let thread = controller.threads.first(where: { $0["id"].int == controller.state.threadID }) {
                    Text(thread["name"].string ?? "").foregroundStyle(WorkbenchColors.secondary).lineLimit(1)
                }
            }.padding(.horizontal, 10).frame(height: 30)
            WorkbenchSeparator()
            FlutterToolScroll {
                FlutterStackRows(controller: controller)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FlutterVariablesContent: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        VStack(spacing: 0) {
            FlutterVariablesHeader(controller: controller)
            WorkbenchSeparator()
            FlutterToolScroll {
                FlutterVariableRows(controller: controller)
                FlutterEvaluationResult(controller: controller)
            }
            WorkbenchSeparator()
            FlutterEvaluationContent(controller: controller)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FlutterStackRows: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        Group {
            if controller.frames.isEmpty {
                FlutterToolEmpty("暂停程序后显示调用栈", symbol: "rectangle.stack")
            }
            ForEach(Array(controller.frames.enumerated()), id: \.offset) { _, frame in
                Button {
                    controller.selectFrame(frame)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right").foregroundStyle(WorkbenchColors.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(frame["name"].string ?? "栈帧").lineLimit(1)
                            Text("\(frame["source"]["name"].string ?? ""): \(frame["line"].int ?? 0)")
                                .font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 6).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(WorkbenchButtonStyle(active: frame["id"].int == controller.selectedFrame))
                    .help((frame["name"].string ?? "") + "\n" + (frame["source"]["path"].string ?? ""))
            }
        }
    }
}

private struct FlutterVariablesHeader: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        HStack(spacing: 6) {
            Text("变量").fontWeight(.medium)
            Spacer(minLength: 0)
            WorkbenchMenuButton(
                title: "选择作用域",
                items: controller.scopes.map { scope in
                    WorkbenchMenuItem(title: scope["name"].string ?? "作用域") {
                        if let reference = scope["variablesReference"].int { controller.loadVariables(reference) }
                    }
                }
            ) {
                HStack(spacing: 4) {
                    Text("作用域")
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }.padding(.horizontal, 6).frame(height: 24)
            }.disabled(controller.scopes.isEmpty)
        }.padding(.horizontal, 10).frame(height: 30)
    }
}
private struct FlutterVariableRows: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        Group {
            if controller.variables.isEmpty {
                FlutterToolEmpty(
                    controller.state.phase == .paused ? "当前作用域没有变量" : "暂停程序后查看变量",
                    symbol: "list.bullet.indent")
            }
            ForEach(Array(controller.variables.enumerated()), id: \.offset) { _, value in
                variable(value)
            }
        }
    }
    private func variable(_ value: JSONValue) -> some View {
        let reference = value["variablesReference"].int ?? 0
        return HStack(alignment: .top, spacing: 5) {
            if reference > 0 {
                WorkbenchIconButton(title: "查看 \(value["name"].string ?? "") 的成员", symbol: "chevron.right", size: 18) {
                    controller.loadVariables(reference)
                }
            } else {
                Color.clear.frame(width: 18, height: 18)
            }
            Text(value["name"].string ?? "").foregroundStyle(WorkbenchColors.accent)
            Text("=").foregroundStyle(WorkbenchColors.secondary)
            Text(String((value["value"].string ?? "").prefix(4_000))).textSelection(.enabled)
            Spacer(minLength: 0)
        }.font(.system(size: 12, design: .monospaced)).padding(.horizontal, 4).padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct FlutterEvaluationContent: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                TextField("求值表达式（可执行代码）", text: $controller.expression)
                    .textFieldStyle(WorkbenchTextFieldStyle()).onSubmit(controller.evaluate)
                WorkbenchIconButton(title: "求值表达式", symbol: "return", size: 24, action: controller.evaluate)
            }.disabled(controller.state.phase != .paused)
        }.padding(.horizontal, 10).padding(.vertical, 6)
    }
}

private struct FlutterEvaluationResult: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        if !controller.evaluation.isEmpty {
            Text(controller.evaluation).font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled).padding(8)
        }
    }
}
