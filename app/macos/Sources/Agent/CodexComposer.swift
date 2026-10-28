import HyCodeWorkspace
import SwiftUI

struct CodexComposer: View {
    @Bindable var controller: CodexWorkspaceController
    let conversation: CodexConversation
    @Binding var focusRequest: UUID?
    @State private var inputHeight: CGFloat = CodexChatPresentation.composerMinimumHeight
    @State private var showingModel = false
    @State private var showingContext = false
    @State private var modelDraft = ""

    var body: some View {
        VStack(spacing: 8) {
            if !controller.hasKey {
                Button {
                    controller.showingSettings = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "key.horizontal")
                        Text(controller.credentialIssue == nil ? "连接模型服务" : "重新填写 API Key").fontWeight(.medium)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }.font(.system(size: 11)).padding(.horizontal, 4)
                }.buttonStyle(.plain).foregroundStyle(CodexAppearance.secondary)
                    .help(controller.credentialIssue ?? "配置模型服务的 API Key")
                if let issue = controller.credentialIssue {
                    Text(issue).font(.system(size: 10)).foregroundStyle(CodexAppearance.permission)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if conversation.draft.isEmpty {
                        Text("和 Codex 一起工作")
                            .font(.system(size: 14)).foregroundStyle(CodexAppearance.muted)
                            .padding(.top, 8).allowsHitTesting(false)
                    }
                    CodexComposerTextView(
                        text: string(\.draft), height: $inputHeight, focusRequest: $focusRequest,
                        enabled: controller.ready, submit: send
                    ).frame(height: inputHeight)
                }
                ViewThatFits(in: .horizontal) {
                    controls(compact: false)
                    controls(compact: true)
                }
            }
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 9)
            .background(CodexAppearance.composer, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22).strokeBorder(CodexAppearance.border, lineWidth: 0.6)
            }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 14)
        .popover(isPresented: $showingModel, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("自定义模型").fontWeight(.semibold)
                TextField("模型名称", text: $modelDraft).onSubmit(applyModel)
                Button("应用", action: applyModel).frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(16).frame(width: 270).workbenchContentStyle()
        }
        .popover(isPresented: $showingContext, arrowEdge: .bottom) { contextSettings }
    }
    private func controls(compact: Bool) -> some View {
        HStack(spacing: compact ? 3 : 5) {
            WorkbenchMenuButton(title: "对话和设置", items: additionalItems, labelColor: CodexAppearance.text, neutral: true)
            {
                Image(systemName: "plus").font(.system(size: 16, weight: .regular)).frame(width: 23, height: 28)
            }.fixedSize()
            WorkbenchMenuButton(
                title: "项目访问权限", items: modeItems,
                labelColor: conversation.mode == .readOnly ? CodexAppearance.secondary : CodexAppearance.permission,
                neutral: true
            ) {
                HStack(spacing: 5) {
                    Image(systemName: conversation.mode == .readOnly ? "eye" : "exclamationmark.shield")
                    if !compact { Text(conversation.mode == .readOnly ? "只读" : "项目访问").fixedSize() }
                }.frame(height: 28).padding(.horizontal, 4)
            }.fixedSize().disabled(controller.running(conversation.id))
                .help(conversation.mode == .readOnly ? "只读：讨论和阅读代码" : "允许修改授权项目；修改期间暂停原生编辑")
            Spacer(minLength: 1)
            Button {
                showingContext = true
            } label: {
                ZStack {
                    Circle().stroke(CodexAppearance.secondary.opacity(0.3), lineWidth: 2)
                    Circle().trim(from: 0, to: contextFraction).stroke(
                        CodexAppearance.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                }.frame(width: 11, height: 11).frame(width: 23, height: 28)
            }.buttonStyle(CodexQuietButtonStyle())
                .help("上下文预算 · " + CodexChatPresentation.contextName(conversation.contextWindow))
            WorkbenchMenuButton(
                title: "模型和思考程度", items: modelItems, labelColor: CodexAppearance.secondary, neutral: true
            ) {
                chip(
                    (compact ? compactModel : CodexChatPresentation.modelName(conversation.model)) + " "
                        + CodexChatPresentation.effortName(conversation.effort))
            }.fixedSize().disabled(controller.running(conversation.id))
            Button {
                if controller.running(conversation.id) { controller.stop(conversation.id) } else { send() }
            } label: {
                Image(systemName: controller.running(conversation.id) ? "stop.fill" : "arrow.up")
                    .font(.system(size: controller.running(conversation.id) ? 10 : 13, weight: .semibold))
                    .frame(width: 28, height: 28).foregroundStyle(.white).background(CodexAppearance.blue, in: Circle())
            }.buttonStyle(.plain)
                .opacity(canSend || controller.running(conversation.id) ? 1 : 0.3)
                .disabled(!canSend && !controller.running(conversation.id))
                .help(controller.running(conversation.id) ? "停止生成" : "发送 · Enter；Shift+Enter 换行")
                .accessibilityLabel(controller.running(conversation.id) ? "停止生成" : "发送消息")
        }.font(.system(size: 11)).foregroundStyle(CodexAppearance.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var additionalItems: [WorkbenchMenuItem] {
        [
            WorkbenchMenuItem(title: "新对话", enabled: controller.ready && !controller.configuring) {
                controller.newConversation()
                focusRequest = UUID()
            }, WorkbenchMenuItem(title: "上下文预算…") { showingContext = true }, .separator,
            WorkbenchMenuItem(title: "模型服务设置…") { controller.showingSettings = true },
        ]
    }
    private var modeItems: [WorkbenchMenuItem] {
        [
            WorkbenchMenuItem(title: "只读 · 讨论和阅读代码", checked: conversation.mode == .readOnly) {
                update { $0.mode = .readOnly }
            },
            WorkbenchMenuItem(title: "Agent · 修改项目", checked: conversation.mode == .workspaceWrite) {
                update { $0.mode = .workspaceWrite }
            },
        ]
    }
    private var modelItems: [WorkbenchMenuItem] {
        var items: [WorkbenchMenuItem] = []
        if controller.state.configuration.isDeepSeekModel {
            items += CodexModelCatalog.deepSeekModels.map { model in
                WorkbenchMenuItem(title: CodexChatPresentation.modelName(model), checked: conversation.model == model) {
                    update { $0.model = model }
                }
            }
        }
        items.append(
            WorkbenchMenuItem(title: "自定义模型…") {
                modelDraft = conversation.model
                showingModel = true
            })
        items += [
            .separator,
            WorkbenchMenuItem(
                title: "思考程度",
                children: efforts.map { value in
                    WorkbenchMenuItem(
                        title: CodexChatPresentation.effortName(value), checked: value == conversation.effort
                    ) { update { $0.effort = value } }
                }),
        ]
        return items
    }
    private var contextFraction: CGFloat {
        guard let usage = conversation.tokenUsage, let window = usage.modelContextWindow, window > 0 else { return 0 }
        return CGFloat(min(1, max(0, Double(usage.lastRequestTokens) / Double(window))))
    }
    private var contextSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("上下文预算").fontWeight(.semibold)
            if let usage = conversation.tokenUsage {
                Text("最近一次请求：\(usage.lastRequestTokens) tokens").font(.system(size: 11)).foregroundStyle(
                    CodexAppearance.secondary)
                if let window = usage.modelContextWindow {
                    Text("运行时可用窗口：\(window) tokens").font(.system(size: 11)).foregroundStyle(CodexAppearance.secondary)
                }
            }
            TextField(
                "自动",
                value: Binding(get: { current.contextWindow }, set: { value in update { $0.contextWindow = value } }),
                format: .number.grouping(.never)
            ).disabled(controller.running(conversation.id))
            HStack {
                ForEach([131_072, 262_144, 1_048_576], id: \.self) { value in
                    Button(CodexChatPresentation.contextName(value)) { update { $0.contextWindow = value } }
                }
                Button("自动") { update { $0.contextWindow = nil } }
            }.disabled(controller.running(conversation.id))
            Text(
                controller.state.configuration.isDeepSeekModel
                    ? "DeepSeek 上限 1048576 tokens。Codex 会预留输出空间并自动压缩历史。" : "预算需符合模型的实际容量。Codex 会预留输出空间并自动压缩历史。"
            )
            .font(.system(size: 11)).foregroundStyle(CodexAppearance.secondary)
        }.padding(16).frame(width: 290).workbenchContentStyle()
    }
    private var current: CodexConversation {
        controller.state.conversations.first { $0.id == conversation.id } ?? conversation
    }
    private var compactModel: String {
        conversation.model == "deepseek-v4-pro" ? "Pro" : conversation.model == "deepseek-flash" ? "Flash" : "模型"
    }
    private var canSend: Bool {
        controller.ready && controller.hasKey
            && !current.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var efforts: [String] {
        var settings = controller.state.configuration
        settings.model = conversation.model
        let values = settings.supportedEfforts
        return values.contains(conversation.effort) ? values : values + [conversation.effort]
    }
    private func chip(_ title: String, symbol: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11)) }
            if !title.isEmpty { Text(title).lineLimit(1).fixedSize() }
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .medium))
        }.padding(.horizontal, 4).frame(height: 26).contentShape(Rectangle())
    }
    private func string(_ key: WritableKeyPath<CodexConversation, String>) -> Binding<String> {
        Binding(
            get: { current[keyPath: key] },
            set: { value in controller.update(conversation.id) { $0[keyPath: key] = value } })
    }
    private func update(_ edit: (inout CodexConversation) -> Void) {
        guard !controller.running(conversation.id) else { return }
        controller.update(conversation.id, edit)
    }
    private func applyModel() {
        let value = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 200 else {
            controller.error = "请填写有效的模型名称（最多 200 字节）"
            return
        }
        update { $0.model = value }
        showingModel = false
    }
    private func send() {
        guard canSend, !controller.running(conversation.id) else { return }
        controller.send(conversation.id)
        focusRequest = UUID()
    }
}
