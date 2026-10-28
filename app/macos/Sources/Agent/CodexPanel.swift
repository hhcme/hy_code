import HyCodeWorkspace
import SwiftUI

struct CodexPanel: View {
    @Bindable var controller: CodexWorkspaceController
    let headerHeight: CGFloat
    let hide: () -> Void
    @State private var showingHistory = false
    @State private var followOutput = true
    @State private var focusRequest: UUID?
    @State private var renameID: UUID?
    @State private var renameTitle = ""
    @State private var historySearch = ""
    private var historyConversations: [CodexConversation] {
        controller.state.conversations.filter {
            historySearch.isEmpty || $0.title.localizedCaseInsensitiveContains(historySearch)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !controller.projectOpen {
                unavailable("在项目中开始", detail: "打开一个项目，与 Codex 一起写代码。")
            } else if controller.loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if let error = controller.error { errorNotice(error) }
                if let conversation = controller.active {
                    if !conversation.messages.isEmpty {
                        HStack(spacing: 7) {
                            Button {
                                showingHistory = true
                            } label: {
                                Image(systemName: "arrow.left").font(.system(size: 10)).frame(width: 20, height: 24)
                            }.buttonStyle(.plain).help("查看历史对话")
                            Text(conversation.title).font(.system(size: 12)).lineLimit(1).help(conversation.title)
                            Spacer(minLength: 0)
                        }.foregroundStyle(WorkbenchColors.secondary).padding(.horizontal, 12).frame(height: 28)
                    }
                    CodexConversationView(
                        controller: controller, conversation: conversation, followOutput: $followOutput,
                        focusRequest: $focusRequest
                    ).id(conversation.id)
                } else if controller.ready {
                    unavailable("开始新的对话", detail: "向 Codex 提问，或交给它一项任务。")
                        .overlay(alignment: .bottom) {
                            Button("新建对话", action: controller.newConversation)
                                .buttonStyle(WorkbenchActionButtonStyle()).padding(.bottom, 24)
                        }
                } else {
                    unavailable("对话暂不可用", detail: "上方提示中提供了恢复方式。")
                }
            }
        }
        .foregroundStyle(CodexAppearance.text).tint(CodexAppearance.text).background(CodexAppearance.background)
        .onChange(of: controller.active?.id) { _, _ in followOutput = true }
        .sheet(isPresented: $controller.showingSettings) { CodexSettingsView(controller: controller) }
        .alert("重命名对话", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField("名称", text: $renameTitle)
            Button("取消", role: .cancel) { renameID = nil }
            Button("保存") {
                if let id = renameID { controller.rename(id, title: renameTitle) }
                renameID = nil
            }
        }
    }
    private var header: some View {
        HStack(spacing: 3) {
            Text("Codex").font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
            Spacer(minLength: 2)
            if controller.busy {
                Text("\(controller.state.conversations.filter { controller.running($0.id) }.count)")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(WorkbenchColors.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2).background(WorkbenchColors.hover, in: Capsule())
                    .help("运行中的对话")
            }
            WorkbenchIconButton(title: "历史对话", symbol: "clock.arrow.circlepath", active: showingHistory, size: 27) {
                showingHistory.toggle()
            }.popover(isPresented: $showingHistory, arrowEdge: .top) { history }
            WorkbenchIconButton(title: "新对话", symbol: "square.and.pencil", size: 27) {
                controller.newConversation()
                focusRequest = UUID()
            }.disabled(!controller.ready || controller.configuring)
            WorkbenchMenuButton(title: "更多操作", items: menuItems, labelColor: CodexAppearance.secondary, neutral: true) {
                Image(systemName: "ellipsis").font(.system(size: 13)).frame(width: 25, height: 27)
            }.fixedSize()

        }.padding(.horizontal, 8).frame(height: headerHeight)
    }
    private var menuItems: [WorkbenchMenuItem] {
        var items = [
            WorkbenchMenuItem(title: "模型服务设置…", enabled: controller.ready) { controller.showingSettings = true }
        ]
        if let conversation = controller.active {
            items += [
                WorkbenchMenuItem(title: "重命名对话…") { rename(conversation) },
                WorkbenchMenuItem(title: "跟随最新输出", checked: followOutput) { followOutput.toggle() }, .separator,
                WorkbenchMenuItem(title: "删除此对话", enabled: !controller.running(conversation.id)) {
                    controller.delete(conversation.id)
                },
            ]
        }
        items += [.separator, WorkbenchMenuItem(title: "隐藏 Codex") { hide() }]
        return items
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近的对话").font(.system(size: 12, weight: .semibold))
                Spacer()
                WorkbenchIconButton(title: "新对话", symbol: "plus", size: 24) {
                    controller.newConversation()
                    showingHistory = false
                    focusRequest = UUID()
                }.disabled(!controller.ready)
            }
            TextField("搜索对话", text: $historySearch).textFieldStyle(.roundedBorder)
            if historyConversations.isEmpty {
                Text(historySearch.isEmpty ? "还没有历史对话" : "没有匹配的对话").font(.system(size: 12)).foregroundStyle(
                    CodexAppearance.secondary
                ).padding(
                    .vertical, 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(historyConversations) { conversation in
                            Button {
                                controller.select(conversation.id)
                                showingHistory = false
                            } label: {
                                HStack(spacing: 10) {
                                    Image(
                                        systemName: controller.running(conversation.id)
                                            ? "circle.dotted" : "bubble.left"
                                    )
                                    .foregroundStyle(WorkbenchColors.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(conversation.title).font(.system(size: 12)).lineLimit(1)
                                        HStack(spacing: 5) {
                                            Text(CodexChatPresentation.modelName(conversation.model)).lineLimit(1)
                                            if let status = controller.statuses[conversation.id] { Text("· " + status) }
                                        }.font(.system(size: 10)).foregroundStyle(WorkbenchColors.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if controller.active?.id == conversation.id {
                                        Image(systemName: "checkmark").font(.system(size: 10))
                                    }
                                }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(
                                WorkbenchButtonStyle(active: controller.active?.id == conversation.id, neutral: true)
                            )
                            .contextMenu {
                                Button("重命名…") { rename(conversation) }
                                Button("删除", role: .destructive) { controller.delete(conversation.id) }
                                    .disabled(controller.running(conversation.id))
                            }
                        }
                    }.background(WorkbenchScrollStyle())
                }.frame(height: min(360, CGFloat(historyConversations.count * 56)))
            }
        }.padding(12).frame(width: 310).foregroundStyle(CodexAppearance.text).background(CodexAppearance.background)
    }
    private func errorNotice(_ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(value).font(.system(size: 11)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !controller.ready {
                Button("重试", action: controller.retryLoading).font(.system(size: 11))
            } else {
                Button {
                    controller.error = nil
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }.buttonStyle(.plain)
            }
        }.padding(10).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
    private func unavailable(_ title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 29, weight: .medium))
            Text(title).font(.system(size: 19, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary).multilineTextAlignment(
                .center)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func rename(_ conversation: CodexConversation) {
        showingHistory = false
        renameTitle = conversation.title
        renameID = conversation.id
    }
}
