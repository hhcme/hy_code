import HyCodeWorkspace
import SwiftUI

struct DartAnalysisPanel: View {
    @Bindable var controller: DartWorkspaceController
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(controller.status).font(.system(size: 12)).textSelection(.enabled)
                HStack {
                    Button("重启分析器", action: controller.restart)
                    SettingsLink { Text("配置 SDK…") }
                }
                if let sdk = controller.toolchain {
                    Text("Dart \(sdk.dartVersion)" + (sdk.flutterSDK == nil ? "" : " · Flutter SDK"))
                    Text(sdk.flutterSDK?.path ?? sdk.dartSDK.path).font(.system(size: 11)).foregroundStyle(
                        WorkbenchColors.secondary
                    ).textSelection(.enabled)
                }
                Divider()
                if let project = controller.project {
                    Text(project.root.lastPathComponent).fontWeight(.semibold)
                    HStack {
                        Button("获取依赖") { controller.runPub("get") }
                        Button("检查过期") { controller.runPub("outdated") }
                        Button("升级依赖") { controller.runPub("upgrade") }
                    }.disabled(
                        controller.toolRunning || controller.toolchain == nil || controller.flutter?.active == true
                            || controller.flutter?.commandRunning == true)
                    HStack {
                        TextField("包名或 包名:版本约束", text: $controller.packageName)
                        Button("添加") { controller.runPub("add") }
                        Button("移除") { controller.runPub("remove") }
                    }.disabled(
                        controller.toolRunning || controller.toolchain == nil || controller.flutter?.active == true
                            || controller.flutter?.commandRunning == true)
                    Toggle("添加为开发依赖", isOn: $controller.addDevDependency)
                    Text(project.resolved ? "已解析 \(project.packages.count) 个包（含传递依赖）" : "尚无有效 package_config，先获取依赖")
                        .foregroundStyle(WorkbenchColors.secondary)
                    ForEach(project.packages) { package in
                        HStack {
                            Image(systemName: "shippingbox")
                            Text(package.name)
                            Spacer(minLength: 4)
                            Text(package.version ?? "本地 / 未知版本").foregroundStyle(WorkbenchColors.secondary)
                            Text(
                                package.dependency == "direct main"
                                    ? "直接"
                                    : package.dependency == "direct dev"
                                        ? "开发" : package.dependency == "transitive" ? "间接" : "项目"
                            )
                            .foregroundStyle(WorkbenchColors.muted)
                        }.help(
                            package.root.path + "\nDart 语言版本 " + package.languageVersion + " · "
                                + (package.source ?? "workspace"))
                    }
                } else {
                    Text("当前目录或打开文件的父目录没有 pubspec.yaml").foregroundStyle(WorkbenchColors.secondary)
                }
                if controller.toolRunning { Button("停止工具任务", action: controller.cancelTool) }
                if !controller.output.isEmpty {
                    Divider()
                    Text(controller.output).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(WorkbenchScrollStyle())
        }.buttonStyle(WorkbenchButtonStyle())
            .foregroundStyle(WorkbenchColors.text).background(WorkbenchColors.panel)
    }
}

struct DartProblemsPanel: View {
    let controller: any EditorLanguageController
    let navigate: (LSPLocation) -> Void
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if !controller.locations.isEmpty {
                    HStack {
                        Text("导航结果 · \(controller.locations.count)").fontWeight(.semibold)
                        Spacer()
                        Button("清除", action: controller.clearLocations)
                    }
                    ForEach(controller.locations) { target in
                        location(target, title: URL(string: target.uri)?.lastPathComponent ?? target.uri)
                    }
                    Divider()
                }
                let items = controller.diagnostics.sorted { $0.key < $1.key }
                let count = items.reduce(0) { $0 + $1.value.count }
                Text("问题 · \(count)").fontWeight(.semibold)
                if count == 0 { Text("当前没有收到诊断").foregroundStyle(WorkbenchColors.secondary) }
                if controller.diagnosticsLimited { Text("诊断较多，当前最多保留 5,000 项").foregroundStyle(.orange) }
                ForEach(items, id: \.key) { uri, values in
                    ForEach(Array(values.enumerated()), id: \.offset) { _, diagnostic in
                        Button {
                            navigate(LSPLocation(uri: uri, range: diagnostic.range))
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(
                                    systemName: diagnostic.severity == 1
                                        ? "xmark.circle.fill" : "exclamationmark.triangle.fill"
                                )
                                .foregroundStyle(diagnostic.severity == 1 ? Color.red : Color.orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(diagnostic.message).lineLimit(3)
                                    Text(
                                        "\(URL(string: uri)?.lastPathComponent ?? uri):\(diagnostic.range.start.line + 1):\(diagnostic.range.start.character + 1)"
                                    )
                                    .font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(WorkbenchButtonStyle())
                    }
                }
            }.font(.system(size: 12)).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(WorkbenchScrollStyle())
        }.foregroundStyle(WorkbenchColors.text).background(WorkbenchColors.panel)
    }
    private func location(_ target: LSPLocation, title: String) -> some View {
        Button {
            navigate(target)
        } label: {
            HStack {
                Image(systemName: "arrow.turn.down.right")
                Text("\(title):\(target.range.start.line + 1):\(target.range.start.character + 1)").lineLimit(1)
                Spacer(minLength: 0)
            }.padding(6).help(URL(string: target.uri)?.path ?? target.uri)
        }.buttonStyle(WorkbenchButtonStyle())
    }
}

struct DartStructurePanel: View {
    let controller: any EditorLanguageController
    let document: EditorDocument?
    private struct Row: Identifiable {
        let id: String
        let name: String
        let depth: Int
        let range: LSPRange
    }
    private func rows(_ values: [JSONValue], prefix: String = "", depth: Int = 0) -> [Row] {
        var result: [Row] = []
        func walk(_ values: [JSONValue], prefix: String, depth: Int) {
            guard depth < 16 else { return }
            for (index, value) in values.enumerated() {
                guard result.count < 2_000 else { return }
                let id = prefix + "/\(index)"
                guard let name = value["name"].string,
                    let range = try? (value["selectionRange"] == .null ? value["range"] : value["selectionRange"])
                        .decode(LSPRange.self)
                else { continue }
                result.append(Row(id: id, name: name, depth: depth, range: range))
                walk(value["children"].array, prefix: id, depth: depth + 1)
            }
        }
        walk(values, prefix: prefix, depth: depth)
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("刷新当前文件结构") { if let feature = document?.semantic { controller.showSymbols(feature) } }
                .disabled(document?.semantic == nil).padding(10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(controller.symbolURI == document?.sourceURL.absoluteString ? rows(controller.symbols) : [])
                    { row in
                        Button {
                            document?.reveal(row.range)
                        } label: {
                            Label(row.name, systemImage: "curlybraces")
                                .padding(.leading, CGFloat(row.depth) * 14 + 8).frame(
                                    maxWidth: .infinity, alignment: .leading
                                ).frame(height: 26)
                        }.buttonStyle(WorkbenchButtonStyle())
                    }
                }.background(WorkbenchScrollStyle())
            }
        }.font(.system(size: 12)).foregroundStyle(WorkbenchColors.text).background(WorkbenchColors.panel)
    }
}
