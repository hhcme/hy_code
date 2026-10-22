import HyCodeWorkspace
import SwiftUI

struct LanguageAnalysisPanel: View {
    @Bindable var store: WorkbenchStore
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach([("dart", "Dart / Flutter"), ("web", "Web")], id: \.0) { key, title in
                    Button {
                        store.analysisLanguage = key
                    } label: {
                        Text(title).padding(6)
                    }
                    .buttonStyle(WorkbenchButtonStyle(active: store.analysisLanguage == key))
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).frame(height: 34)
            WorkbenchSeparator()
            if store.analysisLanguage == "web" {
                WebAnalysisPanel(controller: store.web)
            } else {
                DartAnalysisPanel(controller: store.dart)
            }
        }
    }
}

private struct WebAnalysisPanel: View {
    @Bindable var controller: WebWorkspaceController
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(controller.status).textSelection(.enabled)
                Text(controller.projectAnalysis.state).textSelection(.enabled)
                Button("重新扫描项目", action: controller.projectAnalysis.rescan)
                HStack {
                    Button("重启 Web 分析器", action: controller.restart)
                    SettingsLink { Text("配置 Node…") }
                }
                if let tools = controller.toolchain {
                    Text(tools.node.path).font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                        .textSelection(.enabled)
                }
                WorkbenchSeparator()
                Toggle(
                    "允许当前工作区的 Vue 项目插件",
                    isOn: Binding(
                        get: { controller.projectCodeTrusted }, set: controller.setProjectCodeTrusted)
                )
                .toggleStyle(.checkbox).disabled(controller.toolRunning)
                Text("Vue 分析可能执行配置中的插件。仅为可信项目开启；关闭时 JS/TS 等基础分析仍可用。")
                    .font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                if let project = controller.project {
                    Text(project.name + " · " + project.manager.rawValue).fontWeight(.semibold)
                    Text(project.root.path).font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                        .textSelection(.enabled)
                    ViewThatFits(in: .horizontal) {
                        HStack { dependencyActions }
                        VStack(alignment: .leading, spacing: 6) { dependencyActions }
                    }.disabled(!controller.canRunTool)
                    HStack {
                        TextField("包名或 包名@版本", text: $controller.packageName).textFieldStyle(.roundedBorder)
                        Button("添加") { controller.run("add") }
                        Button("移除") { controller.run("remove") }
                    }.disabled(!controller.canRunTool)
                    Toggle("添加为开发依赖", isOn: $controller.addDevDependency).toggleStyle(.checkbox)
                        .disabled(controller.toolRunning)
                    Text("依赖操作默认禁用生命周期脚本；运行清单脚本会执行项目代码。")
                        .foregroundStyle(WorkbenchColors.secondary).font(.system(size: 11))
                    Text("脚本").fontWeight(.semibold)
                    if project.scripts.isEmpty {
                        Text("package.json 没有 scripts").foregroundStyle(WorkbenchColors.secondary)
                    }
                    ForEach(project.scripts.keys.sorted(), id: \.self) { name in
                        HStack {
                            FlutterActionButton(title: "运行脚本 " + name, symbol: "play.fill", color: .green) {
                                controller.run("script", package: name)
                            }.disabled(!controller.canRunTool)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).fontWeight(.medium)
                                Text(project.scripts[name] ?? "").font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(WorkbenchColors.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }.help(project.scripts[name] ?? name)
                    }
                    Text("声明依赖 · \(project.dependencies.count)").fontWeight(.semibold)
                    ForEach(project.dependencies) { item in
                        HStack(alignment: .top) {
                            Text(item.name).textSelection(.enabled)
                            Spacer(minLength: 4)
                            Text(item.version).foregroundStyle(WorkbenchColors.secondary)
                        }.help(item.kind)
                    }
                    if !project.workspaces.isEmpty {
                        Text("Workspaces").fontWeight(.semibold)
                        ForEach(project.workspaces, id: \.self) { Text($0).foregroundStyle(WorkbenchColors.secondary) }
                    }
                } else {
                    Text("当前文件的工作区父目录没有 package.json").foregroundStyle(WorkbenchColors.secondary)
                }
                if controller.toolRunning { Button("停止任务", action: controller.cancelTool) }
                if !controller.output.isEmpty {
                    WorkbenchSeparator()
                    Text(controller.output).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(WorkbenchScrollStyle())
        }.font(.system(size: 12)).buttonStyle(WorkbenchButtonStyle())
            .foregroundStyle(WorkbenchColors.text).background(WorkbenchColors.panel)
    }
    @ViewBuilder private var dependencyActions: some View {
        Button("安装依赖") { controller.run("install") }
        Button("检查过期") { controller.run("outdated") }
        Button("依赖详情") { controller.run("list") }
    }
}
