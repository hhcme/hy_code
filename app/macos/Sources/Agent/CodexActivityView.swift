import HyCodeWorkspace
import SwiftUI

struct CodexActivityGroupView: View {
    let entry: CodexTranscriptEntry
    let review: (CodexFileChange) -> Void
    @State private var expanded = false
    private var active: Bool { entry.messages.contains { $0.activity?.status == "inProgress" } }
    private var failed: Bool {
        entry.messages.contains { ["failed", "declined", "interrupted"].contains($0.activity?.status ?? "") }
    }
    private var rowCount: Int {
        entry.messages.reduce(0) { $0 + max(1, max($1.activity?.files.count ?? 0, $1.activity?.actions.count ?? 0)) }
    }
    var body: some View {
        if entry.messages.count == 1, let message = entry.messages.first, message.role == .command,
            (message.activity?.actions.count ?? 0) <= 1
        {
            CodexCommandView(message: message)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(
                            systemName: active
                                ? "circle.dotted"
                                : entry.messages.contains(where: { $0.role == .changes }) ? "pencil" : "wrench"
                        )
                        .frame(width: 14)
                        Text(entry.title.isEmpty ? "工具活动" : entry.title).lineLimit(2).multilineTextAlignment(.leading)
                        if failed {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(CodexAppearance.permission)
                        }
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9))
                        Spacer(minLength: 0)
                    }.font(.system(size: 12)).foregroundStyle(CodexAppearance.secondary).padding(.vertical, 3)
                }.buttonStyle(CodexQuietButtonStyle()).accessibilityLabel((expanded ? "收起" : "展开") + "工具活动")
                if expanded {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(entry.messages) { message in
                                if message.role == .command {
                                    if let actions = message.activity?.actions, actions.count > 1 {
                                        ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                                            CodexCommandView(message: message, action: action)
                                        }
                                    } else {
                                        CodexCommandView(message: message)
                                    }
                                } else if let activity = message.activity, !activity.files.isEmpty {
                                    ForEach(Array(activity.files.enumerated()), id: \.offset) { _, file in
                                        CodexChangedFileRow(
                                            file: file, status: activity.status, action: { review(file) })
                                    }
                                } else {
                                    CodexLegacyToolView(message: message)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 6)
                    }.frame(height: min(244, CGFloat(rowCount) * 28))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CodexCommandView: View {
    let message: CodexMessage
    var action: CodexCommandAction?
    @State private var expanded = false
    private var presented: CodexMessage {
        guard let action else { return message }
        var copy = message
        copy.activity?.actions = [action]
        return copy
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: symbol).frame(width: 14)
                    Text(CodexChatPresentation.activityTitle(presented)).lineLimit(1).truncationMode(.tail)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 8))
                    Spacer(minLength: 0)
                }.font(.system(size: 12)).foregroundStyle(CodexAppearance.secondary).padding(.vertical, 2)
            }.buttonStyle(CodexQuietButtonStyle()).help(
                String((action?.path ?? message.activity?.command ?? message.text).prefix(4096)))
            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    if let code = message.activity?.exitCode {
                        Text("退出码 \(code)").font(.system(size: 10)).foregroundStyle(
                            code == 0 ? CodexAppearance.secondary : CodexAppearance.red)
                    }
                    ScrollView([.vertical, .horizontal]) {
                        Text(verbatim: message.text).font(.system(size: 11, design: .monospaced)).textSelection(
                            .enabled
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 210)
                }.padding(10).background(CodexAppearance.raised, in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }
    private var symbol: String {
        guard let action = presented.activity?.actions.first, presented.activity?.actions.count == 1 else {
            return "terminal"
        }
        switch action.kind {
        case "read": return "book"
        case "search": return "magnifyingglass"
        case "listFiles": return "folder"
        default: return "terminal"
        }
    }
}

struct CodexChangedFileRow: View {
    let file: CodexFileChange
    let status: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "pencil").frame(width: 14)
                Text(prefix)
                Text((file.path as NSString).lastPathComponent).underline().lineLimit(1).truncationMode(.middle)
                if status == "completed" {
                    Text("+\(file.added)").foregroundStyle(CodexAppearance.green)
                    Text("-\(file.removed)").foregroundStyle(CodexAppearance.red)
                    if file.kind == "add" { Circle().fill(CodexAppearance.blue).frame(width: 5, height: 5) }
                }
                Spacer(minLength: 0)
            }.font(.system(size: 11)).foregroundStyle(CodexAppearance.secondary).padding(.vertical, 2)
        }.buttonStyle(CodexQuietButtonStyle()).help(file.path).accessibilityLabel(prefix + " " + file.path + "，查看报告的差异")
    }
    private var prefix: String {
        if status == "inProgress" { return "正在编辑" }
        if status != "completed" { return "未完成" }
        return file.kind == "add" ? "已创建" : file.kind == "delete" ? "已删除" : "已编辑"
    }
}

struct CodexLegacyToolView: View {
    let message: CodexMessage
    @State private var expanded = false
    var body: some View {
        DisclosureGroup("文件更改", isExpanded: $expanded) {
            ScrollView([.vertical, .horizontal]) {
                Text(verbatim: message.text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }.frame(maxHeight: 210)
        }.font(.system(size: 12)).foregroundStyle(CodexAppearance.secondary)
    }
}
