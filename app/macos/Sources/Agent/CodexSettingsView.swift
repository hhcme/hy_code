import HyCodeWorkspace
import SwiftUI

struct CodexSettingsView: View {
    @Bindable var controller: CodexWorkspaceController
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = CodexConfiguration()
    @State private var key = ""
    @State private var makeDefault = false
    private var efforts: [String] {
        let values = configuration.supportedEfforts
        return values.contains(configuration.effort) ? values : values + [configuration.effort]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Codex 设置").font(.system(size: 18, weight: .semibold))
            Text("设置模型服务和新对话的默认值。各对话可单独调整。")
                .font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
            Menu("DeepSeek 预设") {
                Button("DeepSeek V4 Pro") { configuration = .deepSeek() }
                Button("DeepSeek Flash") { configuration = .deepSeek(model: "deepseek-flash") }
            }.menuStyle(.borderlessButton).fixedSize()
            VStack(alignment: .leading, spacing: 10) {
                setting("服务地址") { TextField("https://api.deepseek.com", text: $configuration.baseURL) }
                setting("模型") { TextField("模型名称", text: $configuration.model) }
                setting("API Key") { SecureField(controller.hasKey ? "留空保留现有密钥" : "输入密钥", text: $key) }
                setting("思考") {
                    Picker("默认思考", selection: $configuration.effort) {
                        ForEach(efforts, id: \.self) { Text(CodexChatPresentation.effortName($0)).tag($0) }
                    }.labelsHidden()
                }
                setting("上下文") {
                    HStack {
                        TextField("模型默认", value: $configuration.contextWindow, format: .number.grouping(.never))
                        Text("tokens").font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                    }
                }
            }
            Toggle("作为 HyCode 的默认服务，供未配置的项目使用", isOn: $makeDefault)
                .font(.system(size: 12))
            Text(
                "API Key 由 HyCode 保存在专用本地凭据文件中，仅当前用户可读写，不使用系统钥匙串。这里填写模型服务的 API Key。项目设置优先；DeepSeek 上下文上限为 1048576 tokens。"
            )
            .font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary).fixedSize(
                horizontal: false, vertical: true)
            if let issue = controller.credentialIssue {
                Text(issue).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(
                    horizontal: false, vertical: true)
            }
            if let error = controller.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(controller.configuring ? "正在保存…" : "保存") {
                    Task {
                        if await controller.applySettings(configuration, key: key, makeDefault: makeDefault) {
                            key = ""
                            dismiss()
                            if controller.state.conversations.isEmpty { controller.newConversation() }
                        }
                    }
                }.disabled(controller.busy || controller.configuring).keyboardShortcut(.defaultAction)
            }.buttonStyle(WorkbenchActionButtonStyle())
        }.padding(24).frame(width: 470).workbenchContentStyle()
            .onAppear { configuration = controller.state.configuration }
    }
    private func setting<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 12)).frame(width: 54, alignment: .leading)
            content().frame(maxWidth: .infinity)
        }
    }
}
