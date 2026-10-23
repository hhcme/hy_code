import HyCodeWorkspace
import SwiftUI

struct NativeLanguageSettingsView: View {
    @Bindable var tools: NativeToolsController
    var body: some View {
        WorkbenchSeparator(visible: true).padding(.vertical, 4)
        Text("Swift / Java / SQL").fontWeight(.semibold)
        TextField("SourceKit-LSP 可执行文件（留空自动发现 Xcode）", text: $tools.sourceKitPath)
        TextField("JDK 21+ 的 JAVA_HOME（留空自动发现）", text: $tools.javaHome)
        TextField("Eclipse JDT LS 目录（包含 plugins 与 config_mac）", text: $tools.jdtlsPath)
        Picker("SQL 方言", selection: $tools.dialect) {
            ForEach(SQLDialect.allCases, id: \.self) { dialect in Text(dialect.title).tag(dialect) }
        }
        Button("应用并重启语言工具", action: tools.applySettings)
        Text("信任项目后，SwiftPM / Xcode 构建服务器、Maven / Gradle 可读取项目配置、运行构建脚本并解析依赖。只信任你了解的项目。SQL 为离线检查，不连接数据库。")
            .font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
        Toggle("信任当前项目的 Swift 构建配置", isOn: Binding(get: { tools.swift.trusted }, set: tools.swift.setTrusted)).disabled(
            !tools.hasWorkspace)
        Toggle("信任当前项目的 Java 导入与构建配置", isOn: Binding(get: { tools.java.trusted }, set: tools.java.setTrusted)).disabled(
            !tools.hasWorkspace)
        ForEach(tools.owners, id: \.language) { owner in
            HStack {
                Text(owner.status).font(.system(size: 12)).textSelection(.enabled)
                Spacer()
                Button("重启", action: owner.restart)
            }.foregroundStyle(WorkbenchColors.secondary)
        }
        Text(tools.status).font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
    }
}
