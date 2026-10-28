import AppKit
import HyCodeWorkspace
import SwiftUI

struct CodexMessageView: View {
    let message: CodexMessage
    var running = false
    var lastReply = false
    @State private var blocks: [CodexRenderedBlock] = []
    @State private var expanded = false
    @State private var copied = false
    var body: some View {
        Group {
            switch message.role {
            case .user:
                Text(verbatim: message.text).font(.system(size: 14)).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(CodexAppearance.raised, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.leading, 28).frame(maxWidth: .infinity, alignment: .trailing)
            case .command, .changes:
                CodexLegacyToolView(message: message)
            case .assistant:
                VStack(alignment: .leading, spacing: 12) {
                    if blocks.isEmpty { Text(verbatim: message.text).textSelection(.enabled) }
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in render(block) }
                    if !running && (lastReply || message.phase == "final_answer") {
                        HStack {
                            copyButton
                            Spacer()
                        }.foregroundStyle(CodexAppearance.secondary)
                    }
                }.font(.system(size: 14)).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu { Button("复制回复", action: copyReply) }
            case .reasoning:
                Button {
                    expanded.toggle()
                } label: {
                    Text(verbatim: message.text).font(.system(size: 12)).lineSpacing(4)
                        .foregroundStyle(CodexAppearance.muted).lineLimit(expanded ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                }.buttonStyle(.plain).help(expanded ? "收起思考摘要" : "展开思考摘要")
            case .system:
                if let activity = message.activity, activity.kind == .turn {
                    HStack(spacing: 10) {
                        Text(turnTitle(activity)).font(.system(size: 11)).foregroundStyle(CodexAppearance.muted)
                        Rectangle().fill(CodexAppearance.border).frame(height: 0.5)
                    }.padding(.vertical, 2)
                } else {
                    Text(verbatim: message.text).font(.system(size: 11)).foregroundStyle(CodexAppearance.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .environment(
            \.openURL,
            OpenURLAction { url in
                ["https", "http"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
            }
        )
        .task(id: copied) {
            if copied {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { copied = false }
            }
        }
        .task(id: message.text) {
            guard message.role == .assistant else { return }
            let text = message.text
            let task = Task.detached(priority: .utility) { CodexRenderedBlock.project(text) }
            let value = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
            if !Task.isCancelled { blocks = value }
        }
    }
    private var copyButton: some View {
        Button(action: copyReply) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11)).frame(width: 24, height: 23)
        }.buttonStyle(CodexQuietButtonStyle()).help(copied ? "已复制" : "复制回复")
    }
    private func copyReply() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        copied = true
    }
    private func turnTitle(_ activity: CodexActivity) -> String {
        let title = activity.status == "interrupted" ? "已停止" : activity.status == "failed" ? "任务失败" : "已完成"
        return activity.durationMs.map { title + " · " + CodexChatPresentation.duration($0) } ?? title
    }
    @ViewBuilder private func render(_ block: CodexRenderedBlock) -> some View {
        switch block {
        case .paragraph(let text): Text(text).textSelection(.enabled)
        case .heading(let level, let text):
            Text(text).font(.system(size: level == 1 ? 20 : level == 2 ? 17 : 14, weight: .semibold))
                .padding(.top, 3).textSelection(.enabled)
        case .item(let marker, let text):
            HStack(alignment: .top, spacing: 8) {
                Text(marker).foregroundStyle(CodexAppearance.secondary)
                Text(text).textSelection(.enabled)
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1).fill(CodexAppearance.border).frame(width: 2)
                Text(text).foregroundStyle(CodexAppearance.secondary).textSelection(.enabled)
            }.fixedSize(horizontal: false, vertical: true)
        case .divider: WorkbenchSeparator(visible: true).padding(.vertical, 3)
        case .code(let language, let text): CodexCodeBlock(language: language, text: text)
        }
    }
}

private struct CodexCodeBlock: View {
    let language: String
    let text: String
    @State private var copied = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(language.isEmpty ? "代码" : language).font(.system(size: 10, weight: .medium))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                }.buttonStyle(.plain)
            }.foregroundStyle(CodexAppearance.secondary).padding(.horizontal, 10).frame(height: 30)
            WorkbenchSeparator()
            ScrollView(.horizontal) {
                Text(verbatim: text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.background(CodexAppearance.raised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10).strokeBorder(CodexAppearance.border.opacity(0.6), lineWidth: 0.5)
            )
            .task(id: copied) {
                if copied {
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled { copied = false }
                }
            }
    }
}

private enum CodexRenderedBlock: Sendable {
    case paragraph(AttributedString)
    case heading(Int, AttributedString)
    case item(String, AttributedString)
    case quote(AttributedString)
    case divider
    case code(String, String)

    nonisolated static func project(_ source: String) -> [Self] {
        func inline(_ value: String) -> AttributedString {
            var result =
                (try? AttributedString(
                    markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(value)
            for run in result.runs where run.inlinePresentationIntent?.contains(.code) == true {
                result[run.range].font = .system(size: 12, design: .monospaced)
                result[run.range].backgroundColor = CodexAppearance.raised
            }
            return result
        }
        var result: [Self] = []
        for block in CodexChatMarkdown.blocks(source) {
            if Task.isCancelled { return [] }
            switch block {
            case .code(let language, let text): result.append(.code(language, text))
            case .markdown(let raw):
                var paragraph: [String] = []
                func flush() {
                    if !paragraph.isEmpty {
                        result.append(.paragraph(inline(paragraph.joined(separator: "\n"))))
                        paragraph.removeAll()
                    }
                }
                for line in raw.components(separatedBy: "\n") {
                    if Task.isCancelled { return [] }
                    let value = line.trimmingCharacters(in: .whitespaces)
                    if value.isEmpty {
                        flush()
                        continue
                    }
                    let hashes = value.prefix(while: { $0 == "#" }).count
                    if (1...6).contains(hashes), value.dropFirst(hashes).first == " " {
                        flush()
                        result.append(.heading(hashes, inline(String(value.dropFirst(hashes + 1)))))
                    } else if ["---", "***", "___"].contains(value) {
                        flush()
                        result.append(.divider)
                    } else if value.hasPrefix("> ") {
                        flush()
                        result.append(.quote(inline(String(value.dropFirst(2)))))
                    } else if ["- ", "* ", "+ "].contains(where: { value.hasPrefix($0) }) {
                        flush()
                        result.append(.item("•", inline(String(value.dropFirst(2)))))
                    } else {
                        let digits = value.prefix(while: { $0.isASCII && $0.isNumber })
                        if (1...9).contains(digits.count), value.dropFirst(digits.count).hasPrefix(". ") {
                            flush()
                            result.append(
                                .item(String(digits) + ".", inline(String(value.dropFirst(digits.count + 2)))))
                        } else {
                            paragraph.append(line)
                        }
                    }
                    if result.count >= 256 { return [.paragraph(AttributedString(source))] }
                }
                flush()
            }
        }
        return result
    }
}
