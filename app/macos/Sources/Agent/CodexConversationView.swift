import HyCodeWorkspace
import SwiftUI

struct CodexConversationView: View {
    @Bindable var controller: CodexWorkspaceController
    let conversation: CodexConversation
    @Binding var followOutput: Bool
    @Binding var focusRequest: UUID?
    @State private var entries: [CodexTranscriptEntry] = []
    @State private var changes = CodexChangeSummary(messages: [])
    @State private var review: CodexChangeReview?

    var body: some View {
        VStack(spacing: 0) {
            if let error = controller.conversationErrors[conversation.id] {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(CodexAppearance.permission).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            if conversation.messages.isEmpty { welcome } else { transcript }
            if let approvals = controller.approvals[conversation.id], !approvals.isEmpty { approvalCards(approvals) }
            VStack(spacing: 0) {
                if !changes.files.isEmpty {
                    Button {
                        review = CodexChangeReview(files: changes.files, reportedFileCount: changes.fileCount)
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(changes.fileCount) 个文件已更改").foregroundStyle(CodexAppearance.secondary)
                            if changes.limited {
                                Text("· 显示前 \(changes.files.count) 个").foregroundStyle(CodexAppearance.muted)
                            } else {
                                Text("+\(changes.added)").foregroundStyle(CodexAppearance.green)
                                Text("-\(changes.removed)").foregroundStyle(CodexAppearance.red)
                            }
                        }.font(.system(size: 11)).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(CodexAppearance.raised, in: Capsule())
                            .overlay(Capsule().strokeBorder(CodexAppearance.border, lineWidth: 0.5))
                    }.buttonStyle(CodexQuietButtonStyle()).help("查看本轮报告的文件差异").padding(.top, 8).padding(.bottom, 2)
                }
                CodexComposer(controller: controller, conversation: conversation, focusRequest: $focusRequest)
            }.frame(maxWidth: CodexAppearance.columnWidth + 32).frame(maxWidth: .infinity)
        }.sheet(item: $review) { CodexChangeReviewView(review: $0) }
            .task(id: conversation.updatedAt) {
                let messages = conversation.messages
                let projection = Task.detached(priority: .utility) {
                    (CodexTranscriptEntry.project(messages), CodexChangeSummary(messages: messages))
                }
                let result = await withTaskCancellationHandler(
                    operation: { await projection.value }, onCancel: { projection.cancel() })
                guard !Task.isCancelled else { return }
                entries = result.0
                changes = result.1
            }
    }
    private var welcome: some View {
        VStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 28, weight: .medium))
                .padding(.bottom, 3)
            Text("和 Codex 一起工作").font(.system(size: 22, weight: .medium))
            Text("从一个问题或一项任务开始。")
                .font(.system(size: 12)).foregroundStyle(CodexAppearance.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(entries) { entry in
                        if entry.isActivity {
                            CodexActivityGroupView(entry: entry) { file in
                                review = CodexChangeReview(files: [file], selectedPath: file.path)
                            }
                            .id(entry.id)
                        } else if let message = entry.messages.first {
                            CodexMessageView(
                                message: message, running: controller.running(conversation.id),
                                lastReply: message.id
                                    == conversation.messages.last(where: { $0.role == .assistant })?.id
                            ).id(
                                entry.id)
                        }
                    }
                    if controller.running(conversation.id) {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.mini)
                            Text(controller.statuses[conversation.id] ?? "正在思考")
                                .font(.system(size: 11)).foregroundStyle(CodexAppearance.secondary)
                        }.padding(.vertical, 1)
                    }
                    Color.clear.frame(height: 1).id("end")
                }.frame(maxWidth: CodexAppearance.columnWidth, alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(CodexScrollObservation { following in followOutput = following })
                    .background(WorkbenchScrollStyle())
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: entries) { _, _ in if followOutput { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: controller.running(conversation.id)) { _, _ in
                if followOutput { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: followOutput) { _, following in if following { proxy.scrollTo("end", anchor: .bottom) } }
            .overlay(alignment: .bottom) {
                if !followOutput {
                    Button {
                        followOutput = true
                    } label: {
                        Image(systemName: "arrow.down").font(.system(size: 12, weight: .medium))
                            .frame(width: 30, height: 30).background(CodexAppearance.raised, in: Circle())
                            .overlay(Circle().strokeBorder(CodexAppearance.border, lineWidth: 0.5))
                    }.buttonStyle(CodexQuietButtonStyle()).help("回到最新消息").padding(.bottom, 8)
                }
            }
        }
    }
    private func approvalCards(_ approvals: [CodexWorkspaceController.Approval]) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(approvals) { approval in
                    VStack(alignment: .leading, spacing: 9) {
                        Label(approval.title, systemImage: "hand.raised").font(.system(size: 12, weight: .medium))
                        Text(approval.detail).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Spacer()
                            Button("拒绝") { controller.answer(approval, conversation: conversation.id, accept: false) }
                            Button("允许一次") { controller.answer(approval, conversation: conversation.id, accept: true) }
                        }.buttonStyle(WorkbenchActionButtonStyle())
                    }.padding(12).background(CodexAppearance.raised, in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(.horizontal, 14)
        }.frame(maxHeight: 190)
    }
}
